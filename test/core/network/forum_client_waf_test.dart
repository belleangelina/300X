import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/network/waf_challenge_solver.dart';

void main() {
  test('百度 WAF 405 挑战成功后携带新 Cookie 重试 GET', () async {
    final _WafAdapter adapter = _WafAdapter();
    final _FakeWafChallengeSolver solver = _FakeWafChallengeSolver();
    final ForumClient client = _client(adapter, solver);

    final Response<String> response = await client.getText(ForumClient.baseUri);

    expect(response.statusCode, HttpStatus.ok);
    expect(response.data, 'forum page');
    expect(adapter.requestCount, 2);
    expect(adapter.cookieAcceptedCount, 1);
    expect(solver.callCount, 1);
  });

  test('挑战后替换 host 和 domain 中的旧 WAF Cookie', () async {
    final CookieJar cookieJar = CookieJar();
    final Cookie hostCookie = Cookie('nox_jst_v1', 'old-host-cookie')
      ..path = '/'
      ..expires = DateTime.now().toUtc().add(const Duration(minutes: 30))
      ..secure = true;
    await cookieJar.saveFromResponse(ForumClient.baseUri, <Cookie>[hostCookie]);
    final Cookie domainCookie = Cookie('nox_jst_v1', 'old-domain-cookie')
      ..domain = ForumClient.baseUri.host
      ..path = '/'
      ..expires = DateTime.now().toUtc().add(const Duration(minutes: 30))
      ..secure = true;
    await cookieJar.saveFromResponse(ForumClient.baseUri, <Cookie>[
      domainCookie,
    ]);
    final _WafAdapter adapter = _WafAdapter();
    final _FakeWafChallengeSolver solver = _FakeWafChallengeSolver();
    final ForumClient client = _client(adapter, solver, cookieJar: cookieJar);

    final Response<String> response = await client.getText(ForumClient.baseUri);
    final List<Cookie> cookies = await cookieJar.loadForRequest(
      ForumClient.baseUri,
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(
      cookies.where((Cookie value) => value.name == 'nox_jst_v1'),
      hasLength(1),
    );
    expect(
      cookies.singleWhere((Cookie value) => value.name == 'nox_jst_v1').value,
      'valid-waf-cookie',
    );
  });

  test('WAF Cookie 不作为可恢复的登录会话', () async {
    final CookieJar cookieJar = CookieJar();
    final Cookie wafCookie = Cookie('nox_jst_v1', 'waf-cookie');
    await cookieJar.saveFromResponse(ForumClient.baseUri, <Cookie>[wafCookie]);
    final ForumClient client = _client(
      _WafAdapter(),
      _FakeWafChallengeSolver(),
      cookieJar: cookieJar,
    );

    expect(await client.hasPotentialLoginSession(), isFalse);

    await cookieJar.saveFromResponse(ForumClient.baseUri, <Cookie>[
      Cookie('auth_session', 'forum-cookie'),
    ]);

    expect(await client.hasPotentialLoginSession(), isTrue);
  });

  test('并发 GET 只执行一次 WAF 挑战', () async {
    final _WafAdapter adapter = _WafAdapter();
    final _FakeWafChallengeSolver solver = _FakeWafChallengeSolver(
      waitForRelease: true,
    );
    final ForumClient client = _client(adapter, solver);

    final List<Future<Response<String>>> requests = <Future<Response<String>>>[
      client.getText(ForumClient.baseUri),
      client.getText(ForumClient.baseUri),
    ];
    await _waitUntil(() => adapter.wafResponseCount == 2);
    solver.release();
    final List<Response<String>> responses = await Future.wait(requests);

    expect(
      responses.map((Response<String> value) => value.statusCode),
      everyElement(HttpStatus.ok),
    );
    expect(solver.callCount, 1);
    expect(adapter.cookieAcceptedCount, 2);
  });

  test('图片 GET 遇到 WAF 后使用同一恢复链路', () async {
    final _WafAdapter adapter = _WafAdapter();
    final _FakeWafChallengeSolver solver = _FakeWafChallengeSolver();
    final ForumClient client = _client(adapter, solver);

    final Uint8List bytes = await client.getBytes(
      ForumClient.baseUri.resolve('image.jpg'),
    );

    expect(utf8.decode(bytes), 'forum page');
    expect(adapter.requestCount, 2);
    expect(solver.callCount, 1);
  });

  test('外站图片使用不带论坛 Cookie 的独立连接', () async {
    final CookieJar cookieJar = CookieJar();
    await cookieJar.saveFromResponse(ForumClient.baseUri, <Cookie>[
      Cookie('auth_session', 'private-forum-cookie'),
    ]);
    final _WafAdapter forumAdapter = _WafAdapter();
    final _PublicAdapter publicAdapter = _PublicAdapter();
    final ForumClient client = _client(
      forumAdapter,
      _FakeWafChallengeSolver(),
      cookieJar: cookieJar,
      publicAdapter: publicAdapter,
    );

    final Uint8List bytes = await client.getBytes(
      Uri.parse('https://media.example.test/image.jpg'),
      referer: ForumClient.baseUri.toString(),
    );

    expect(utf8.decode(bytes), 'public image');
    expect(forumAdapter.requestCount, 0);
    expect(publicAdapter.requestCount, 1);
    expect(publicAdapter.cookieHeader, isEmpty);
  });

  test('服务端相对跳转地址会解析为绝对论坛地址', () async {
    final Dio dio = Dio(BaseOptions(responseType: ResponseType.plain));
    dio.httpClientAdapter = _PublicAdapter();
    dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (
          Response<dynamic> response,
          ResponseInterceptorHandler handler,
        ) {
          response.redirects = <RedirectRecord>[
            RedirectRecord(
              HttpStatus.found,
              'GET',
              Uri.parse('forum.php?mod=viewthread&tid=1&mobile=2'),
            ),
          ];
          handler.next(response);
        },
      ),
    );
    final ForumClient client = ForumClient.forTesting(dio, CookieJar());

    final Response<String> response = await client.getText(
      ForumClient.baseUri.resolve(
        'forum.php?mod=redirect&goto=findpost&pid=2&mobile=2',
      ),
    );

    expect(
      response.realUri,
      ForumClient.baseUri.resolve(
        'forum.php?mod=viewthread&tid=1&mobile=2',
      ),
    );
  });

  test('普通业务 405 不触发 WAF 挑战', () async {
    final _WafAdapter adapter = _WafAdapter(isWafResponse: false);
    final _FakeWafChallengeSolver solver = _FakeWafChallengeSolver();
    final ForumClient client = _client(adapter, solver);

    await expectLater(
      client.getText(ForumClient.baseUri),
      throwsA(isA<ForumConnectionException>()),
    );

    expect(adapter.requestCount, 1);
    expect(solver.callCount, 0);
  });

  test('服务端判定旧 Cookie 过期后可以再次挑战', () async {
    final _WafAdapter adapter = _WafAdapter();
    final _FakeWafChallengeSolver solver = _FakeWafChallengeSolver();
    final ForumClient client = _client(adapter, solver);

    await client.getText(ForumClient.baseUri);
    adapter.rejectNextRequest();
    await client.getText(ForumClient.baseUri);

    expect(solver.callCount, 2);
    expect(adapter.requestCount, 4);
  });

  test('POST 遇到 WAF 时刷新 Cookie 但不自动重放', () async {
    final _WafAdapter adapter = _WafAdapter(alwaysRejectPost: true);
    final _FakeWafChallengeSolver solver = _FakeWafChallengeSolver();
    final ForumClient client = _client(adapter, solver);

    await expectLater(
      client.postForm(
        ForumClient.baseUri.resolve('member.php'),
        fields: const <String, dynamic>{'submit': 'true'},
      ),
      throwsA(
        isA<ForumConnectionException>().having(
          (ForumConnectionException value) => value.message,
          'message',
          '论坛安全验证已更新，请重新提交',
        ),
      ),
    );

    expect(adapter.requestCount, 1);
    expect(solver.callCount, 1);
  });
}

ForumClient _client(
  _WafAdapter adapter,
  WafChallengeSolver solver, {
  CookieJar? cookieJar,
  _PublicAdapter? publicAdapter,
}) {
  final Dio dio = Dio(BaseOptions(responseType: ResponseType.plain));
  dio.httpClientAdapter = adapter;
  final Dio? publicDio = publicAdapter == null
      ? null
      : (Dio()..httpClientAdapter = publicAdapter);
  return ForumClient.forTesting(
    dio,
    cookieJar ?? CookieJar(),
    wafChallengeSolver: solver,
    publicDio: publicDio,
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  final Stopwatch timeout = Stopwatch()..start();
  while (!condition()) {
    if (timeout.elapsed > const Duration(seconds: 2)) {
      throw TimeoutException('等待并发请求进入 WAF 响应超时');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeWafChallengeSolver implements WafChallengeSolver {
  _FakeWafChallengeSolver({bool waitForRelease = false})
    : _release = waitForRelease ? Completer<void>() : null;

  final Completer<void>? _release;
  int callCount = 0;

  void release() {
    _release?.complete();
  }

  @override
  Future<WafChallengeCookie> solve(Uri forumUri) async {
    callCount++;
    await _release?.future;
    return WafChallengeCookie(
      name: 'nox_jst_v1',
      value: 'valid-waf-cookie',
      domain: forumUri.host,
      path: '/',
      expires: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    );
  }
}

class _WafAdapter implements HttpClientAdapter {
  _WafAdapter({this.alwaysRejectPost = false, this.isWafResponse = true});

  final bool alwaysRejectPost;
  final bool isWafResponse;
  int requestCount = 0;
  int wafResponseCount = 0;
  int cookieAcceptedCount = 0;
  int _forcedWafResponses = 0;

  void rejectNextRequest() {
    _forcedWafResponses++;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    final String cookie =
        options.headers[HttpHeaders.cookieHeader]?.toString() ?? '';
    final List<String> wafCookies = cookie
        .split(';')
        .map((String value) => value.trim())
        .where((String value) => value.startsWith('nox_jst_v1='))
        .toList(growable: false);
    final bool accepted =
        wafCookies.length == 1 &&
        wafCookies.single == 'nox_jst_v1=valid-waf-cookie';
    if (accepted) {
      cookieAcceptedCount++;
    }
    final bool forceWafResponse = _forcedWafResponses > 0;
    if (forceWafResponse) {
      _forcedWafResponses--;
    }
    if ((alwaysRejectPost && options.method == 'POST') ||
        !accepted ||
        forceWafResponse) {
      wafResponseCount++;
      return ResponseBody.fromString(
        isWafResponse
            ? '<script>window.__noxExpire=30</script>'
                  '<script src="nox.js">'
            : 'method not allowed',
        HttpStatus.methodNotAllowed,
        headers: <String, List<String>>{
          HttpHeaders.serverHeader: <String>[
            isWafResponse ? 'BAIDU_WAF' : 'origin-server',
          ],
          HttpHeaders.contentTypeHeader: <String>['text/html'],
        },
      );
    }
    return ResponseBody.fromString(
      'forum page',
      HttpStatus.ok,
      headers: <String, List<String>>{
        HttpHeaders.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _PublicAdapter implements HttpClientAdapter {
  int requestCount = 0;
  String cookieHeader = '';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    cookieHeader = options.headers[HttpHeaders.cookieHeader]?.toString() ?? '';
    return ResponseBody.fromString(
      'public image',
      HttpStatus.ok,
      headers: <String, List<String>>{
        HttpHeaders.contentTypeHeader: <String>['image/jpeg'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
