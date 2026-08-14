import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/community/data/community_repository.dart';
import 'package:x300/features/community/domain/community_models.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';

class _MockForumClient extends Mock implements ForumClient {}

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

void main() {
  late AppDatabase database;
  late ForumLocalRepository localRepository;
  late _MockForumClient client;
  late CommunityRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    localRepository = ForumLocalRepository(database);
    client = _MockForumClient();
    _stubAccountLease(client);
    repository = CommunityRepository(client, localRepository, 42);
  });

  tearDown(() => database.close());

  test('只有连接失败才读取同 uid 规范缓存', () async {
    final Uri uri = _noticeUri();
    when(
      () => client.getText(uri),
    ).thenAnswer((_) async => _response(_noticeHtml(), uri));
    final CommunityNoticePage online = await repository.loadNotices(uri);
    expect(online.isFromCache, isFalse);

    reset(client);
    _stubAccountLease(client);
    when(
      () => client.getText(uri),
    ).thenThrow(const ForumConnectionException('离线'));
    final CommunityNoticePage cached = await repository.loadNotices(uri);
    expect(cached.isFromCache, isTrue);
    expect(cached.items.single.topicTarget?.postId, 321);

    final CommunityRepository otherAccount = CommunityRepository(
      client,
      localRepository,
      43,
    );
    await expectLater(
      otherAccount.loadNotices(uri),
      throwsA(isA<ForumConnectionException>()),
    );
  });

  test('模板漂移和错 uid 不会伪装成缓存成功', () async {
    final Uri uri = _noticeUri();
    when(
      () => client.getText(uri),
    ).thenAnswer((_) async => _response(_noticeHtml(), uri));
    await repository.loadNotices(uri);

    reset(client);
    _stubAccountLease(client);
    when(() => client.getText(uri)).thenAnswer(
      (_) async => _response(_shell('<div class="changed"></div>'), uri),
    );
    await expectLater(
      repository.loadNotices(uri),
      throwsA(isA<ForumParseException>()),
    );

    reset(client);
    _stubAccountLease(client);
    when(() => client.getText(uri)).thenAnswer(
      (_) async => _response(
        _noticeHtml().replaceFirst("discuz_uid='42'", "discuz_uid='7'"),
        uri,
      ),
    );
    await expectLater(
      repository.loadNotices(uri),
      throwsA(isA<ForumSessionExpiredException>()),
    );
  });

  test('同类旧请求后返时被 generation 拒绝且不写缓存', () async {
    final Uri firstUri = _noticeUri();
    final Uri secondUri = _noticeUri(page: 2);
    final Completer<Response<String>> first = Completer<Response<String>>();
    when(() => client.getText(firstUri)).thenAnswer((_) => first.future);
    when(
      () => client.getText(secondUri),
    ).thenAnswer((_) async => _response(_noticeHtml(page: 2), secondUri));

    final Future<CommunityNoticePage> stale = repository.loadNotices(firstUri);
    final CommunityNoticePage current = await repository.loadNotices(secondUri);
    first.complete(_response(_noticeHtml(), firstUri));

    expect(current.cursor.currentPage, 2);
    await expectLater(
      stale,
      throwsA(isA<CommunityRequestSupersededException>()),
    );
    final List<ForumCache> rows = await database
        .select(database.forumCaches)
        .get();
    expect(rows, hasLength(1));
  });

  test('私信会话必须复用返回 URI 中的精确 touid', () async {
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&do=pm&'
      'subop=view&touid=77&mobile=2',
    );
    await expectLater(
      repository.loadPmThread(uri, expectedPeerUserId: 88),
      throwsA(isA<ForumParseException>()),
    );
    verifyNever(() => client.getText(any()));
  });

  test('私信会话旧页后返时被 generation 拒绝', () async {
    final Uri firstUri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&do=pm&'
      'subop=view&touid=77&page=1&mobile=2',
    );
    final Uri secondUri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&do=pm&'
      'subop=view&touid=77&page=2&mobile=2',
    );
    final Completer<Response<String>> first = Completer<Response<String>>();
    when(() => client.getText(firstUri)).thenAnswer((_) => first.future);
    when(
      () => client.getText(secondUri),
    ).thenAnswer((_) async => _response(_pmThreadHtml(), secondUri));

    final Future<CommunityPmThreadPage> stale = repository.loadPmThread(
      firstUri,
      expectedPeerUserId: 77,
    );
    final CommunityPmThreadPage current = await repository.loadPmThread(
      secondUri,
      expectedPeerUserId: 77,
    );
    first.complete(_response(_pmThreadHtml(), firstUri));

    expect(current.cursor.currentPage, 2);
    await expectLater(
      stale,
      throwsA(isA<CommunityRequestSupersededException>()),
    );
  });

  test('私信正文只在当次读取内存中保留', () async {
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&do=pm&'
      'subop=view&touid=77&mobile=2',
    );
    when(
      () => client.getText(uri),
    ).thenAnswer((_) async => _response(_pmThreadHtml(), uri));

    final CommunityPmThreadPage page = await repository.loadPmThread(
      uri,
      expectedPeerUserId: 77,
    );

    expect(page.messages.single.message, '[已脱敏]私信正文');
    expect(await database.select(database.forumCaches).get(), isEmpty);
  });

  test('私信列表缓存不保存会话预览', () async {
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&do=pm&mobile=2',
    );
    when(
      () => client.getText(uri),
    ).thenAnswer((_) async => _response(_pmListHtml(), uri));

    final CommunityPmListPage online = await repository.loadPmList(uri);
    expect(online.items.single.preview, '[已脱敏]私信预览');
    expect(online.composeUri, isNotNull);

    reset(client);
    _stubAccountLease(client);
    when(
      () => client.getText(uri),
    ).thenThrow(const ForumConnectionException('离线'));
    final CommunityPmListPage cached = await repository.loadPmList(uri);

    expect(cached.isFromCache, isTrue);
    expect(cached.items.single.preview, isEmpty);
    expect(cached.composeUri, isNull);
    final String payload = (await database.select(
      database.forumCaches,
    ).getSingle()).payloadJson;
    expect(payload, isNot(contains('[已脱敏]私信预览')));
  });

  test('整个读取和缓存操作持有活跃账号租约', () async {
    final Uri uri = _noticeUri();
    when(
      () => client.getText(uri),
    ).thenAnswer((_) async => _response(_noticeHtml(), uri));

    await repository.loadNotices(uri);

    verify(() => client.withActiveAccount<void>(42, any())).called(1);
    verifyNever(() => client.postForm(any(), fields: any(named: 'fields')));
  });
}

Uri _noticeUri({int page = 1}) {
  return Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=space&do=notice&'
    'page=$page&mobile=2',
  );
}

Response<String> _response(String html, Uri uri) {
  return Response<String>(
    requestOptions: RequestOptions(path: uri.toString()),
    data: html,
    statusCode: 200,
  );
}

String _pmThreadHtml() {
  return _shell('''
<div class="msgbox">
  <div class="friend_msg"><div class="dialog_c">[已脱敏]私信正文</div></div>
</div>
''');
}

String _pmListHtml() {
  return _shell('''
<a href="home.php?mod=spacecp&amp;ac=pm&amp;mobile=2">发送私信</a>
<div id="pmlist"><ul><li class="newpm">
  <a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=77&amp;mobile=2">
    <p class="mtit">用户A<span class="mtime">[时间]</span></p>
    <p class="mtxt">[已脱敏]私信预览</p>
  </a>
</li></ul></div>
''');
}

String _shell(String body) {
  return '''
<html><body id="home" class="pg_space">
<script>var discuz_uid='42';</script>
$body
</body></html>
''';
}

String _noticeHtml({int page = 1}) {
  return _shell('''
<div id="notice_ul"><ul><li class="cl">
  <p class="mtit"><a id="a_note_11">[已脱敏]通知</a></p>
  <p class="mbody"><a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=120&amp;pid=321&amp;mobile=2">[已脱敏]楼层</a></p>
  <a href="home.php?mod=spacecp&amp;ac=common&amp;op=ignore&amp;type=post&amp;mobile=2">[已脱敏]</a>
</li></ul></div>
<div class="pg"><strong>$page</strong></div>
''');
}
