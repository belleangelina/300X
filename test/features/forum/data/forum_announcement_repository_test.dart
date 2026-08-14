import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/domain/forum_announcement_models.dart';

class _MockForumClient extends Mock implements ForumClient {}

class _GatedForumLocalRepository extends ForumLocalRepository {
  _GatedForumLocalRepository(super.database);

  final Completer<void> firstSaveStarted = Completer<void>();
  final Completer<void> releaseFirstSave = Completer<void>();
  int _saveCount = 0;

  @override
  Future<bool> saveCacheIfCurrent({
    required int userId,
    required String key,
    required Map<String, dynamic> payload,
    required bool Function() isCurrent,
    DateTime? updatedAt,
  }) async {
    _saveCount++;
    if (_saveCount == 1) {
      firstSaveStarted.complete();
      await releaseFirstSave.future;
    }
    return super.saveCacheIfCurrent(
      userId: userId,
      key: key,
      payload: payload,
      isCurrent: isCurrent,
      updatedAt: updatedAt,
    );
  }
}

void main() {
  late AppDatabase database;
  late ForumLocalRepository local;
  late _MockForumClient client;
  late ForumReadRepository repository;
  final Uri uri = Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=announcement&id=7',
  );

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    local = ForumLocalRepository(database);
    client = _MockForumClient();
    _stubAccountLease(client);
    repository = ForumReadRepository(client, local, 42);
  });

  tearDown(() => database.close());

  test('公告 GET 成功后写入同账号缓存，离线只回退该账号', () async {
    when(
      () => client.getText(uri),
    ).thenAnswer((_) async => _response(_announcementHtml(), uri));

    final ForumAnnouncement online = await repository.loadAnnouncement(
      uri,
      expectedAnnouncementId: 7,
    );
    expect(online.isFromCache, isFalse);

    reset(client);
    _stubAccountLease(client);
    when(
      () => client.getText(uri),
    ).thenThrow(const ForumConnectionException('离线'));
    final ForumAnnouncement cached = await repository.loadAnnouncement(
      uri,
      expectedAnnouncementId: 7,
    );
    expect(cached.isFromCache, isTrue);
    expect(cached.cacheUpdatedAt, isNotNull);

    final ForumReadRepository otherAccount = ForumReadRepository(
      client,
      local,
      43,
    );
    await expectLater(
      otherAccount.loadAnnouncement(uri, expectedAnnouncementId: 7),
      throwsA(isA<ForumConnectionException>()),
    );
  });

  test('外域在发出 GET 前失败，错 id 最终页和登录失效不写缓存', () async {
    expect(
      () => repository.loadAnnouncement(
        Uri.parse('https://evil.example/forum.php?mod=announcement&id=7'),
        expectedAnnouncementId: 7,
      ),
      throwsA(isA<ForumActionSecurityException>()),
    );
    verifyNever(() => client.getText(any()));

    when(() => client.getText(uri)).thenAnswer(
      (_) async => _response(
        _announcementHtml(id: 8),
        uri.replace(
          queryParameters: <String, String>{'mod': 'announcement', 'id': '8'},
        ),
      ),
    );
    await expectLater(
      repository.loadAnnouncement(uri, expectedAnnouncementId: 7),
      throwsA(isA<ForumParseException>()),
    );
    expect(await database.select(database.forumCaches).get(), isEmpty);

    reset(client);
    _stubAccountLease(client);
    when(() => client.getText(uri)).thenAnswer(
      (_) async => _response(
        '<body class="pg_logging"><form id="loginform"></form></body>',
        uri,
      ),
    );
    await expectLater(
      repository.loadAnnouncement(uri, expectedAnnouncementId: 7),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    expect(await database.select(database.forumCaches).get(), isEmpty);
  });

  test('同一公告乱序返回时拒绝旧请求覆盖新结果', () async {
    final Completer<Response<String>> first = Completer<Response<String>>();
    var requestCount = 0;
    when(() => client.getText(uri)).thenAnswer((_) {
      requestCount++;
      if (requestCount == 1) {
        return first.future;
      }
      return Future<Response<String>>.value(
        _response(_announcementHtml(title: '新公告'), uri),
      );
    });

    final Future<ForumAnnouncement> stale = repository.loadAnnouncement(
      uri,
      expectedAnnouncementId: 7,
    );
    final ForumAnnouncement current = await repository.loadAnnouncement(
      uri,
      expectedAnnouncementId: 7,
    );
    first.complete(_response(_announcementHtml(title: '旧公告'), uri));

    expect(current.title, '新公告');
    await expectLater(stale, throwsA(isA<ForumRequestSupersededException>()));
  });

  test('缓存落盘期间被新请求替代时不返回或覆盖新公告', () async {
    final _GatedForumLocalRepository gated = _GatedForumLocalRepository(
      database,
    );
    repository = ForumReadRepository(client, gated, 42);
    var requestCount = 0;
    when(() => client.getText(uri)).thenAnswer((_) async {
      requestCount++;
      return _response(
        _announcementHtml(title: requestCount == 1 ? '旧公告' : '新公告'),
        uri,
      );
    });

    final Future<ForumAnnouncement> stale = repository.loadAnnouncement(
      uri,
      expectedAnnouncementId: 7,
    );
    await gated.firstSaveStarted.future;
    final ForumAnnouncement current = await repository.loadAnnouncement(
      uri,
      expectedAnnouncementId: 7,
    );
    gated.releaseFirstSave.complete();

    expect(current.title, '新公告');
    await expectLater(stale, throwsA(isA<ForumRequestSupersededException>()));

    reset(client);
    _stubAccountLease(client);
    when(
      () => client.getText(uri),
    ).thenThrow(const ForumConnectionException('离线'));
    final ForumAnnouncement cached = await repository.loadAnnouncement(
      uri,
      expectedAnnouncementId: 7,
    );
    expect(cached.title, '新公告');
    expect(cached.isFromCache, isTrue);
  });

  test('连接失败时拒绝源路由与公告 id 不一致的同账号缓存', () async {
    when(
      () => client.getText(uri),
    ).thenAnswer((_) async => _response(_announcementHtml(), uri));
    await repository.loadAnnouncement(uri, expectedAnnouncementId: 7);

    final ForumCache row =
        (await database.select(database.forumCaches).get()).single;
    final Map<String, dynamic> payload = Map<String, dynamic>.from(
      jsonDecode(row.payloadJson) as Map<String, dynamic>,
    );
    payload['sourceUri'] =
        'https://bbs.yamibo.com/forum.php?mod=announcement&id=8';
    await local.saveCache(userId: 42, key: row.cacheKey, payload: payload);

    reset(client);
    _stubAccountLease(client);
    when(
      () => client.getText(uri),
    ).thenThrow(const ForumConnectionException('离线'));
    await expectLater(
      repository.loadAnnouncement(uri, expectedAnnouncementId: 7),
      throwsA(isA<ForumConnectionException>()),
    );
  });
}

void _stubAccountLease(_MockForumClient client) {
  when(() => client.withActiveAccount<void>(any(), any())).thenAnswer((
    Invocation invocation,
  ) {
    final Future<void> Function() action =
        invocation.positionalArguments[1] as Future<void> Function();
    return action();
  });
  when(
    () => client.withActiveAccount<ForumCacheSnapshot?>(any(), any()),
  ).thenAnswer((Invocation invocation) {
    final Future<ForumCacheSnapshot?> Function() action =
        invocation.positionalArguments[1]
            as Future<ForumCacheSnapshot?> Function();
    return action();
  });
}

Response<String> _response(String body, Uri uri) {
  return Response<String>(
    requestOptions: RequestOptions(path: uri.toString()),
    data: body,
    statusCode: 200,
  );
}

String _announcementHtml({int id = 7, String title = '公告'}) {
  return '''
  <html><head><script>var discuz_uid = '42';</script></head>
    <body id="forum" class="pg_announcement">
      <div class="annlist"><ul><li class="cl">
        <h2>$title</h2><h3>时间</h3>
        <div id="ann_${id}_box" class="annlist_box"><p>正文</p></div>
      </li></ul></div>
    </body>
  </html>
  ''';
}
