import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/network/forum_webview_cookie_session.dart';
import 'package:x300/core/network/waf_challenge_solver.dart';

void main() {
  late Directory supportDirectory;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'x300_forum_sessions_',
    );
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('持久 Cookie 按 uid 分桶且切换时不会合并', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('session-a')]);

    await client.activateAccount(202);
    expect(await client.exportCookies(), isEmpty);
    await client.importCookies(<Cookie>[_cookie('session-b')]);

    await client.activateAccount(101);
    expect((await client.exportCookies()).single.value, 'session-a');
    await client.activateAccount(202);
    expect((await client.exportCookies()).single.value, 'session-b');
  });

  test('首次确认 uid 时把旧 V1 Cookie 经 pending 迁入账号桶', () async {
    final String legacyRoot = path.join(supportDirectory.path, 'sessions');
    final PersistCookieJar legacyJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(legacyRoot),
    );
    await legacyJar.saveFromResponse(ForumClient.baseUri, <Cookie>[
      _cookie('legacy-session'),
    ]);

    final ForumClient client = await ForumClient.create(
      supportDirectory: supportDirectory,
    );
    expect(client.activeUserId, 0);
    expect((await client.exportCookies()).single.value, 'legacy-session');

    await client.activateAccount(471581, migrateCurrentCookies: true);
    expect((await client.exportCookies()).single.value, 'legacy-session');
    await client.activateAccount(0);
    expect(await client.exportCookies(), isEmpty);
    await client.activateAccount(471581);
    expect((await client.exportCookies()).single.value, 'legacy-session');
  });

  test('WebView 登录没有本地凭据时仍从 active_uid 恢复账号桶', () async {
    final ForumClient loginClient = await ForumClient.create(
      supportDirectory: supportDirectory,
    );
    await loginClient.importCookies(<Cookie>[_cookie('web-session')]);
    await loginClient.activateAccount(471581, migrateCurrentCookies: true);

    final ForumClient restartedClient = await ForumClient.create(
      supportDirectory: supportDirectory,
    );

    expect(restartedClient.activeUserId, 471581);
    expect((await restartedClient.exportCookies()).single.value, 'web-session');
  });

  test('active_uid 比可能过期的保存凭据 uid 更优先', () async {
    final ForumClient first = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await first.importCookies(<Cookie>[_cookie('web-account')]);

    final ForumClient restarted = await ForumClient.create(
      userId: 202,
      supportDirectory: supportDirectory,
    );

    expect(restarted.activeUserId, 101);
    expect((await restarted.exportCookies()).single.value, 'web-account');
  });

  test('WebView 身份 Cookie 回写以完整快照替换本地 Cookie', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[
      _cookie('old-session'),
      Cookie('stale-cookie', 'must-be-removed'),
    ]);

    await client.importCookies(<Cookie>[_cookie('new-session')]);

    final List<Cookie> cookies = await client.exportCookies();
    expect(cookies, hasLength(1));
    expect(cookies.single.value, 'new-session');
  });

  test('WebView Cookie 快照等待旧请求落盘后再替换', () async {
    final _DelayedCookieAdapter adapter = _DelayedCookieAdapter();
    final Dio dio = Dio(BaseOptions(responseType: ResponseType.plain));
    dio.httpClientAdapter = adapter;
    final ForumClient client = ForumClient.forTesting(dio, CookieJar());

    final Future<Response<String>> oldRequest = client.getText(
      ForumClient.baseUri,
      retryCount: 0,
    );
    await adapter.started.future;
    bool imported = false;
    final Future<void> import = client
        .importCookies(<Cookie>[_cookie('web-snapshot')])
        .then((_) => imported = true);
    await Future<void>.delayed(Duration.zero);
    expect(imported, isFalse);

    adapter.release.complete();
    await Future.wait<Object?>(<Future<Object?>>[oldRequest, import]);

    final List<Cookie> cookies = await client.exportCookies();
    expect(cookies, hasLength(1));
    expect(cookies.single.value, 'web-snapshot');
  });

  test('WebView Cookie 快照替换期间阻止新请求进入', () async {
    final _BlockingCookieJar cookieJar = _BlockingCookieJar();
    final _CountingAdapter adapter = _CountingAdapter();
    final Dio dio = Dio(BaseOptions(responseType: ResponseType.plain));
    dio.httpClientAdapter = adapter;
    final ForumClient client = ForumClient.forTesting(dio, cookieJar);

    final Future<void> import = client.importCookies(<Cookie>[
      _cookie('web-snapshot'),
    ]);
    await cookieJar.deleteStarted.future;
    final Future<Response<String>> request = client.getText(
      ForumClient.baseUri,
      retryCount: 0,
    );
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requestCount, 0);

    cookieJar.releaseDelete.complete();
    await import;
    await request;
    expect(adapter.requestCount, 1);
  });

  test('WebView 释放租约后快照导入不与 WAF 请求环锁', () async {
    final _LeaseWafAdapter adapter = _LeaseWafAdapter();
    final _LeaseWafSolver solver = _LeaseWafSolver();
    final Dio dio = Dio(BaseOptions(responseType: ResponseType.plain));
    dio.httpClientAdapter = adapter;
    final CookieJar cookieJar = CookieJar();
    await cookieJar.saveFromResponse(ForumClient.baseUri, <Cookie>[
      _cookie('native-before-web'),
      _wafCookie('native-old-waf'),
    ]);
    final ForumClient client = ForumClient.forTesting(
      dio,
      cookieJar,
      wafChallengeSolver: solver,
    );
    final ForumWebViewCookieSessionLease pageLease =
        await forumWebViewCookieSession.acquire();

    final Future<Response<String>> request = client.getText(
      ForumClient.baseUri,
      retryCount: 0,
    );
    await solver.waitingForLease.future;
    final List<Cookie> webSnapshot = <Cookie>[
      _cookie('web-auth-snapshot'),
      _wafCookie('web-old-waf'),
    ];

    pageLease.release();
    final Future<void> import = client.importCookies(webSnapshot);
    await Future.wait<Object?>(<Future<Object?>>[request, import])
        .timeout(const Duration(seconds: 2));

    final List<Cookie> cookies = await client.exportCookies();
    expect(
      cookies.singleWhere((Cookie cookie) => cookie.name == 'auth').value,
      'web-auth-snapshot',
    );
    expect(
      cookies
          .singleWhere((Cookie cookie) => cookie.name == 'nox_jst_v1')
          .value,
      'native-new-waf',
    );
    expect(adapter.requestCount, 2);
  });

  test('WebView 初始化先等 session 快照再取全局租约且不会与 WAF 环锁', () async {
    final _ControlledLeaseWafAdapter adapter = _ControlledLeaseWafAdapter();
    final _LeaseWafSolver solver = _LeaseWafSolver();
    final Dio dio = Dio(BaseOptions(responseType: ResponseType.plain));
    dio.httpClientAdapter = adapter;
    final ForumClient client = ForumClient.forTesting(
      dio,
      CookieJar(),
      wafChallengeSolver: solver,
    );

    final Future<Response<String>> request = client.getText(
      ForumClient.baseUri,
      retryCount: 0,
    );
    await adapter.firstRequestStarted.future;
    final Future<void> mutation = client.importCookies(<Cookie>[
      _cookie('queued-mutation'),
    ]);
    final Future<ForumControlledWebSession> initialization =
        client.beginControlledWebSession();

    adapter.releaseFirstResponse.complete();
    final ForumControlledWebSession prepared =
        await initialization.timeout(const Duration(seconds: 2));
    prepared.lease.release();
    await Future.wait<Object?>(<Future<Object?>>[
      request,
      mutation,
    ]).timeout(const Duration(seconds: 2));

    expect(adapter.requestCount, 2);
    expect(
      prepared.cookies
          .singleWhere((Cookie cookie) => cookie.name == 'auth')
          .value,
      'queued-mutation',
    );
  });

  test('排队 WebView 在前页切号后重取最新身份快照', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('account-101')]);
    final ForumControlledWebSession first =
        await client.beginControlledWebSession();
    final Future<ForumControlledWebSession> secondFuture =
        client.beginControlledWebSession();
    await Future<void>.delayed(Duration.zero);

    final ForumWebSessionTransitionReservation reservation =
        client.reserveWebSessionTransition(first.identityGeneration);
    first.lease.release();
    final Future<void> transition = client.transitionWebSession<void>(
      cookies: <Cookie>[_cookie('account-202')],
      expectedIdentityGeneration: first.identityGeneration,
      reservation: reservation,
      verify: () async => const ForumWebSessionVerification<void>(
        userId: 202,
        value: null,
      ),
    );
    await transition;
    final ForumControlledWebSession second =
        await secondFuture.timeout(const Duration(seconds: 2));

    expect(client.activeUserId, 202);
    expect(
      second.cookies.singleWhere((Cookie cookie) => cookie.name == 'auth').value,
      'account-202',
    );
    expect(second.identityGeneration, isNot(first.identityGeneration));
    second.lease.release();
  });

  test('身份代际变化后拒绝旧 WebView 快照回写', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('account-101')]);
    final ForumControlledWebSession stale =
        await client.beginControlledWebSession();
    stale.lease.release();
    await client.activateAccount(202);
    await client.importCookies(<Cookie>[_cookie('account-202')]);

    await expectLater(
      client.transitionWebSession<void>(
        cookies: <Cookie>[_cookie('stale-account-101')],
        expectedIdentityGeneration: stale.identityGeneration,
        verify: () async => const ForumWebSessionVerification<void>(
          userId: 101,
          value: null,
        ),
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    expect(client.activeUserId, 202);
    expect((await client.exportCookies()).single.value, 'account-202');
  });

  test('WebView 冻结后预留 transition 会阻断业务且取消可恢复', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    final ForumControlledWebSession page =
        await client.beginControlledWebSession();
    final ForumWebSessionTransitionReservation reservation =
        client.reserveWebSessionTransition(page.identityGeneration);

    await expectLater(
      client.withActiveAccount<void>(101, () async {}),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    final Future<ForumControlledWebSession> nextPage =
        client.beginControlledWebSession();
    bool nextEntered = false;
    nextPage.then((ForumControlledWebSession _) => nextEntered = true);
    await Future<void>.delayed(Duration.zero);
    expect(nextEntered, isFalse);

    reservation.cancel();
    page.lease.release();
    final ForumControlledWebSession next =
        await nextPage.timeout(const Duration(seconds: 2));
    expect(next.identityGeneration, page.identityGeneration);
    next.lease.release();
  });

  test('Web 身份待确认期间拒绝旧 UID 和普通业务请求', () async {
    final _CountingAdapter adapter = _CountingAdapter();
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
      httpClientAdapter: adapter,
    );
    await client.importCookies(<Cookie>[_cookie('old-account')]);
    final Completer<void> verificationStarted = Completer<void>();
    final Completer<void> releaseVerification = Completer<void>();

    final Future<String> transition = client.transitionWebSession<String>(
      cookies: <Cookie>[_cookie('new-account')],
      verify: () async {
        await client.getText(ForumClient.baseUri, retryCount: 0);
        verificationStarted.complete();
        await releaseVerification.future;
        return const ForumWebSessionVerification<String>(
          userId: 202,
          value: 'verified',
        );
      },
    );
    await verificationStarted.future;

    expect(client.activeUserId, 0);
    expect(client.hasPendingWebIdentity, isTrue);
    await expectLater(
      client.withActiveAccount<void>(101, () async {}),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    await expectLater(
      client.getText(ForumClient.baseUri, retryCount: 0),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    expect(adapter.requestCount, 1);

    releaseVerification.complete();
    expect(await transition, 'verified');
    expect(client.activeUserId, 202);
    expect(client.hasPendingWebIdentity, isFalse);
    expect((await client.exportCookies()).single.value, 'new-account');
  });

  test('Web 身份 pending 标记使崩溃重启不能回绑旧 UID', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('old-account')]);
    final Completer<void> verificationStarted = Completer<void>();
    final Completer<void> releaseVerification = Completer<void>();
    final Future<void> transition = client.transitionWebSession<void>(
      cookies: <Cookie>[_cookie('web-account')],
      verify: () async {
        verificationStarted.complete();
        await releaseVerification.future;
        return const ForumWebSessionVerification<void>(
          userId: 202,
          value: null,
        );
      },
    );
    await verificationStarted.future;

    final ForumClient restarted = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    expect(restarted.activeUserId, 0);
    expect(restarted.hasPendingWebIdentity, isTrue);
    expect(
      (await restarted.cookieJar.loadForRequest(ForumClient.baseUri))
          .singleWhere((Cookie cookie) => cookie.name == 'auth')
          .value,
      'web-account',
    );
    await expectLater(
      restarted.withActiveAccount<void>(101, () async {}),
      throwsA(isA<ForumSessionExpiredException>()),
    );

    releaseVerification.complete();
    await transition;
  });

  test('Web 身份验证失败后重启只能续验 pending 会话', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('old-account')]);

    await expectLater(
      client.transitionWebSession<void>(
        cookies: <Cookie>[_cookie('web-account')],
        verify: () async => throw const ForumConnectionException('离线'),
      ),
      throwsA(isA<ForumConnectionException>()),
    );
    expect(client.activeUserId, 0);
    expect(client.hasPendingWebIdentity, isTrue);

    final ForumClient restarted = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    expect(restarted.activeUserId, 0);
    expect(restarted.hasPendingWebIdentity, isTrue);
    final String result = await restarted.resumePendingWebSession<String>(
      verify: () async => const ForumWebSessionVerification<String>(
        userId: 202,
        value: 'resumed',
      ),
    );
    expect(result, 'resumed');
    expect(restarted.activeUserId, 202);
    expect(restarted.hasPendingWebIdentity, isFalse);
    expect((await restarted.exportCookies()).single.value, 'web-account');
    expect(await _accountCookies(supportDirectory, 101), isEmpty);
  });

  test('WebView 从账号 A 切到 B 后清除 A 的持久 Cookie 桶', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('account-a')]);

    await client.transitionWebSession<void>(
      cookies: <Cookie>[_cookie('account-b')],
      verify: () async => const ForumWebSessionVerification<void>(
        userId: 202,
        value: null,
      ),
    );

    expect(client.activeUserId, 202);
    expect(await _accountCookies(supportDirectory, 101), isEmpty);
    expect(
      (await _accountCookies(supportDirectory, 202)).single.value,
      'account-b',
    );
  });

  test('WebView 登出账号 A 后清除 A 的持久 Cookie 桶', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('account-a')]);

    await client.transitionWebSession<void>(
      cookies: const <Cookie>[],
      verify: () async => const ForumWebSessionVerification<void>(
        userId: 0,
        value: null,
      ),
    );

    expect(client.activeUserId, 0);
    expect(client.hasPendingWebIdentity, isFalse);
    expect(await _accountCookies(supportDirectory, 101), isEmpty);
    expect(await client.exportCookies(), isEmpty);
  });

  test('WebView 仍为账号 A 时用新快照更新而不清空 A 桶', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('account-a-old')]);

    await client.transitionWebSession<void>(
      cookies: <Cookie>[_cookie('account-a-new')],
      verify: () async => const ForumWebSessionVerification<void>(
        userId: 101,
        value: null,
      ),
    );

    expect(client.activeUserId, 101);
    expect(
      (await _accountCookies(supportDirectory, 101)).single.value,
      'account-a-new',
    );
  });

  test('崩溃恢复从 pending 元数据清除进入前账号桶', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('account-a')]);
    await expectLater(
      client.transitionWebSession<void>(
        cookies: <Cookie>[_cookie('account-b')],
        verify: () async => throw const ForumConnectionException('离线'),
      ),
      throwsA(isA<ForumConnectionException>()),
    );
    final File pendingMarker = File(
      path.join(supportDirectory.path, 'sessions', 'identity_pending'),
    );
    expect(await pendingMarker.readAsString(), 'previous_uid=101\n');

    final ForumClient restarted = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await restarted.resumePendingWebSession<void>(
      verify: () async => const ForumWebSessionVerification<void>(
        userId: 202,
        value: null,
      ),
    );

    expect(restarted.activeUserId, 202);
    expect(await _accountCookies(supportDirectory, 101), isEmpty);
    expect(
      (await _accountCookies(supportDirectory, 202)).single.value,
      'account-b',
    );
  });

  test('pending 身份期间显式退出也会清除进入前账号桶', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('account-a')]);
    await expectLater(
      client.transitionWebSession<void>(
        cookies: <Cookie>[_cookie('unverified-account')],
        verify: () async => throw const ForumConnectionException('离线'),
      ),
      throwsA(isA<ForumConnectionException>()),
    );

    await client.clearSession();

    final String sessionRoot = path.join(
      supportDirectory.path,
      'sessions',
    );
    expect(client.activeUserId, 0);
    expect(client.hasPendingWebIdentity, isFalse);
    expect(await _accountCookies(supportDirectory, 101), isEmpty);
    expect(await client.exportCookies(), isEmpty);
    expect(
      await File(path.join(sessionRoot, 'identity_pending')).exists(),
      isFalse,
    );
    expect(
      await File(path.join(sessionRoot, 'active_uid')).exists(),
      isFalse,
    );
  });

  test('提交中崩溃且 pending marker 尚在时仍续验并清旧账号', () async {
    final String sessionRoot = path.join(supportDirectory.path, 'sessions');
    await Directory(sessionRoot).create(recursive: true);
    final PersistCookieJar oldJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(path.join(sessionRoot, 'uid-101')),
    );
    await oldJar.saveFromResponse(
      ForumClient.baseUri,
      <Cookie>[_cookie('account-a')],
    );
    final PersistCookieJar pendingJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(path.join(sessionRoot, 'pending')),
    );
    await pendingJar.saveFromResponse(
      ForumClient.baseUri,
      <Cookie>[_cookie('account-b')],
    );
    await File(path.join(sessionRoot, 'active_uid')).writeAsString('202\n');
    await File(path.join(sessionRoot, 'identity_pending'))
        .writeAsString('previous_uid=101\n');

    final ForumClient restarted = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    expect(restarted.activeUserId, 0);
    expect(restarted.hasPendingWebIdentity, isTrue);
    await restarted.resumePendingWebSession<void>(
      verify: () async => const ForumWebSessionVerification<void>(
        userId: 202,
        value: null,
      ),
    );

    expect(restarted.activeUserId, 202);
    expect(await _accountCookies(supportDirectory, 101), isEmpty);
    expect(
      (await _accountCookies(supportDirectory, 202)).single.value,
      'account-b',
    );
  });

  test('pending 提交点后即使残留 pending 桶重启也选择已确认 UID', () async {
    final String sessionRoot = path.join(supportDirectory.path, 'sessions');
    final PersistCookieJar targetJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(path.join(sessionRoot, 'uid-202')),
    );
    await targetJar.saveFromResponse(
      ForumClient.baseUri,
      <Cookie>[_cookie('confirmed-account')],
    );
    final PersistCookieJar pendingJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(path.join(sessionRoot, 'pending')),
    );
    await pendingJar.saveFromResponse(
      ForumClient.baseUri,
      <Cookie>[_cookie('pending-leftover')],
    );
    await Directory(sessionRoot).create(recursive: true);
    await File(path.join(sessionRoot, 'active_uid')).writeAsString('202\n');

    final ForumClient restarted = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );

    expect(restarted.hasPendingWebIdentity, isFalse);
    expect(restarted.activeUserId, 202);
    expect((await restarted.exportCookies()).single.value, 'confirmed-account');
  });

  test('账号切换等待账号绑定的本地落盘', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    final Completer<void> entered = Completer<void>();
    final Completer<void> release = Completer<void>();
    final Future<void> write = client.withActiveAccount(101, () async {
      entered.complete();
      await release.future;
    });
    await entered.future;

    var switched = false;
    final Future<void> switchAccount = client
        .activateAccount(202)
        .then((_) => switched = true);
    await Future<void>.delayed(Duration.zero);
    expect(switched, isFalse);

    release.complete();
    await Future.wait<void>(<Future<void>>[write, switchAccount]);
    expect(client.activeUserId, 202);
  });

  test('账号租约内可复用论坛请求且切换仍等待整个操作', () async {
    final _DelayedCookieAdapter adapter = _DelayedCookieAdapter();
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
      httpClientAdapter: adapter,
    );
    final Completer<void> operationFinished = Completer<void>();
    final Future<void> operation = client.withActiveAccount(101, () async {
      await client.getText(ForumClient.baseUri, retryCount: 0);
      operationFinished.complete();
    });
    await adapter.started.future;

    var switched = false;
    final Future<void> switchAccount = client
        .activateAccount(202)
        .then((_) => switched = true);
    await Future<void>.delayed(Duration.zero);
    expect(switched, isFalse);

    adapter.release.complete();
    await operationFinished.future.timeout(const Duration(seconds: 2));
    await Future.wait<void>(<Future<void>>[operation, switchAccount]);
    expect(client.activeUserId, 202);
  });

  test('active_uid 内容损坏时安全回到 pending', () async {
    final Directory sessionRoot = Directory(
      path.join(supportDirectory.path, 'sessions'),
    );
    await Directory(
      path.join(sessionRoot.path, 'uid-202'),
    ).create(recursive: true);
    await File(
      path.join(sessionRoot.path, 'active_uid'),
    ).writeAsString('../202');

    final ForumClient client = await ForumClient.create(
      supportDirectory: supportDirectory,
    );

    expect(client.activeUserId, 0);
    expect(
      await File(path.join(sessionRoot.path, 'active_uid')).exists(),
      isFalse,
    );
  });

  test('active_uid 对应账号桶不存在时安全回到 pending', () async {
    final Directory sessionRoot = Directory(
      path.join(supportDirectory.path, 'sessions'),
    );
    await sessionRoot.create(recursive: true);
    await File(
      path.join(sessionRoot.path, 'active_uid'),
    ).writeAsString('202\n');

    final ForumClient client = await ForumClient.create(
      supportDirectory: supportDirectory,
    );

    expect(client.activeUserId, 0);
    expect(
      await File(path.join(sessionRoot.path, 'active_uid')).exists(),
      isFalse,
    );
  });

  test('退出只删除当前账号会话并切回 pending', () async {
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
    );
    await client.importCookies(<Cookie>[_cookie('session-a')]);
    await client.activateAccount(202);
    await client.importCookies(<Cookie>[_cookie('session-b')]);

    await client.clearSession();

    expect(client.activeUserId, 0);
    expect(
      await File(
        path.join(supportDirectory.path, 'sessions', 'active_uid'),
      ).exists(),
      isFalse,
    );
    expect(await client.exportCookies(), isEmpty);
    await client.activateAccount(101);
    expect((await client.exportCookies()).single.value, 'session-a');
    await client.activateAccount(202);
    expect(await client.exportCookies(), isEmpty);
  });

  test('账号切换等待旧请求落盘且旧响应不会污染新账号', () async {
    final _DelayedCookieAdapter adapter = _DelayedCookieAdapter();
    final ForumClient client = await ForumClient.create(
      userId: 101,
      supportDirectory: supportDirectory,
      httpClientAdapter: adapter,
    );

    final Future<Response<String>> request = client.getText(
      ForumClient.baseUri,
      retryCount: 0,
    );
    await adapter.started.future;
    bool switched = false;
    final Future<void> switchRequest = client
        .activateAccount(202)
        .then((_) => switched = true);
    await Future<void>.delayed(Duration.zero);
    expect(switched, isFalse);

    adapter.release.complete();
    await request;
    await switchRequest;

    expect(client.activeUserId, 202);
    expect(await client.exportCookies(), isEmpty);
    await client.activateAccount(101);
    expect((await client.exportCookies()).single.value, 'late-session');
  });
}

Cookie _cookie(String value) {
  return Cookie('auth', value)
    ..domain = ForumClient.baseUri.host
    ..path = '/'
    ..secure = true;
}

Cookie _wafCookie(String value) {
  return Cookie('nox_jst_v1', value)
    ..domain = ForumClient.baseUri.host
    ..path = '/'
    ..expires = DateTime.now().toUtc().add(const Duration(minutes: 30))
    ..secure = true;
}

Future<List<Cookie>> _accountCookies(Directory supportDirectory, int userId) {
  final PersistCookieJar jar = PersistCookieJar(
    ignoreExpires: false,
    storage: FileStorage(
      path.join(supportDirectory.path, 'sessions', 'uid-$userId'),
    ),
  );
  return jar.loadForRequest(ForumClient.baseUri);
}

class _DelayedCookieAdapter implements HttpClientAdapter {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await release.future;
    return ResponseBody.fromString(
      'ok',
      HttpStatus.ok,
      headers: <String, List<String>>{
        HttpHeaders.setCookieHeader: <String>[
          'auth=late-session; Domain=bbs.yamibo.com; '
              'Path=/; Secure',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _BlockingCookieJar implements CookieJar {
  final CookieJar _delegate = CookieJar();
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> releaseDelete = Completer<void>();

  @override
  bool get ignoreExpires => _delegate.ignoreExpires;

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) {
    return _delegate.delete(uri, withDomainSharedCookie);
  }

  @override
  Future<void> deleteAll() async {
    deleteStarted.complete();
    await releaseDelete.future;
    await _delegate.deleteAll();
  }

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) {
    return _delegate.loadForRequest(uri);
  }

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) {
    return _delegate.saveFromResponse(uri, cookies);
  }
}

class _CountingAdapter implements HttpClientAdapter {
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    return ResponseBody.fromString('ok', HttpStatus.ok);
  }

  @override
  void close({bool force = false}) {}
}

class _LeaseWafSolver implements WafChallengeSolver {
  final Completer<void> waitingForLease = Completer<void>();

  @override
  Future<WafChallengeCookie> solve(Uri forumUri) {
    waitingForLease.complete();
    return forumWebViewCookieSession.runExclusive(() async {
      return WafChallengeCookie(
        name: 'nox_jst_v1',
        value: 'native-new-waf',
        domain: forumUri.host,
        path: '/',
        expires: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      );
    });
  }
}

class _LeaseWafAdapter implements HttpClientAdapter {
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    final String cookie =
        options.headers[HttpHeaders.cookieHeader]?.toString() ?? '';
    if (cookie.contains('nox_jst_v1=native-new-waf')) {
      return ResponseBody.fromString('ok', HttpStatus.ok);
    }
    return ResponseBody.fromString(
      '<script>window.__noxExpire=30</script><script src="nox.js">',
      HttpStatus.methodNotAllowed,
      headers: <String, List<String>>{
        HttpHeaders.serverHeader: <String>['BAIDU_WAF'],
        HttpHeaders.contentTypeHeader: <String>['text/html'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ControlledLeaseWafAdapter implements HttpClientAdapter {
  final Completer<void> firstRequestStarted = Completer<void>();
  final Completer<void> releaseFirstResponse = Completer<void>();
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    if (requestCount == 1) {
      firstRequestStarted.complete();
      await releaseFirstResponse.future;
      return ResponseBody.fromString(
        '<script>window.__noxExpire=30</script><script src="nox.js">',
        HttpStatus.methodNotAllowed,
        headers: <String, List<String>>{
          HttpHeaders.serverHeader: <String>['BAIDU_WAF'],
          HttpHeaders.contentTypeHeader: <String>['text/html'],
        },
      );
    }
    return ResponseBody.fromString('ok', HttpStatus.ok);
  }

  @override
  void close({bool force = false}) {}
}
