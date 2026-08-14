import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

class _MockForumClient extends Mock implements ForumClient
{
}

void _stubAccountLease(_MockForumClient client)
{
    when(
        () => client.withActiveAccount<void>(any(), any()),
    ).thenAnswer((Invocation invocation)
    {
        final Future<void> Function() action =
            invocation.positionalArguments[1] as Future<void> Function();
        return action();
    });
    when(
        () => client.withActiveAccount<ForumCacheSnapshot?>(any(), any()),
    ).thenAnswer((Invocation invocation)
    {
        final Future<ForumCacheSnapshot?> Function() action =
            invocation.positionalArguments[1]
                as Future<ForumCacheSnapshot?> Function();
        return action();
    });
}

void main()
{
    late AppDatabase database;
    late ForumLocalRepository local;
    late _MockForumClient client;
    late ForumReadRepository repository;

    setUp(()
    {
        database = AppDatabase(NativeDatabase.memory());
        local = ForumLocalRepository(database);
        client = _MockForumClient();
        _stubAccountLease(client);
        repository = ForumReadRepository(client, local, 42);
    });

    tearDown(() => database.close());

    test('论坛首页以移动 HTML 为可见性权威并验证同账号 API', () async
    {
        when(() => client.getText(ForumReadRepository.indexUri)).thenAnswer(
            (_) async => _response(_indexHtml, ForumReadRepository.indexUri),
        );
        when(() => client.getText(ForumReadRepository.apiIndexUri)).thenAnswer(
            (_) async => _response(_indexJson, ForumReadRepository.apiIndexUri),
        );

        final ForumBoardIndex index = await repository.loadIndex();

        expect(index.viewer.userId, 42);
        expect(index.boardById(30)?.name, '漫画区');
        expect(index.boardById(77), isNull);
        verify(() => client.getText(ForumReadRepository.indexUri)).called(1);
        verify(() => client.getText(ForumReadRepository.apiIndexUri)).called(1);
    });

    test('连接失败才读取同账号缓存，模板漂移不会伪装成功', () async
    {
        final Uri boardUri = _boardUri(page: 1);
        when(() => client.getText(boardUri)).thenAnswer(
            (_) async => _response(_boardHtml(nextPage: 2), boardUri),
        );
        final ForumBoardPage online = await repository.loadBoard(
            boardUri,
            expectedBoardId: 30,
        );
        expect(online.isFromCache, isFalse);
        expect(online.cursor.nextPageUri, _boardUri(page: 2));

        reset(client);
        _stubAccountLease(client);
        when(() => client.getText(boardUri)).thenThrow(
            const ForumConnectionException('离线'),
        );
        final ForumBoardPage cached = await repository.loadBoard(
            boardUri,
            expectedBoardId: 30,
        );
        expect(cached.isFromCache, isTrue);
        expect(cached.cacheUpdatedAt, isNotNull);

        reset(client);
        _stubAccountLease(client);
        when(() => client.getText(boardUri)).thenAnswer(
            (_) async => _response(
                '''
                <head><script>var discuz_uid = '42';</script></head>
                <body id="forum" class="pg_forumdisplay"></body>
                ''',
                boardUri,
            ),
        );
        await expectLater(
            repository.loadBoard(boardUri, expectedBoardId: 30),
            throwsA(isA<ForumParseException>()),
        );

        final ForumReadRepository otherAccount = ForumReadRepository(
            client,
            local,
            43,
        );
        reset(client);
        _stubAccountLease(client);
        when(() => client.getText(boardUri)).thenThrow(
            const ForumConnectionException('离线'),
        );
        await expectLater(
            otherAccount.loadBoard(boardUri, expectedBoardId: 30),
            throwsA(isA<ForumConnectionException>()),
        );
    });

    test('版块翻页只使用页面返回的精确 URI', () async
    {
        final Uri firstUri = _boardUri(page: 1);
        final Uri nextUri = _boardUri(page: 2).replace(
            queryParameters: <String, String>{
                ..._boardUri(page: 2).queryParameters,
                'filter': 'digest',
                'digest': '1',
            },
        );
        when(() => client.getText(firstUri)).thenAnswer(
            (_) async => _response(
                _boardHtml(nextUri: nextUri),
                firstUri,
            ),
        );
        when(() => client.getText(nextUri)).thenAnswer(
            (_) async => _response(_boardHtml(), nextUri),
        );

        final ForumBoardPage first = await repository.loadBoard(
            firstUri,
            expectedBoardId: 30,
        );
        await repository.loadNextBoard(first);

        verify(() => client.getText(nextUri)).called(1);
    });

    test('错 uid 页面被判会话失效且不会写缓存', () async
    {
        final Uri boardUri = _boardUri(page: 1);
        when(() => client.getText(boardUri)).thenAnswer(
            (_) async => _response(
                _boardHtml().replaceFirst(
                    "discuz_uid = '42'",
                    "discuz_uid = '7'",
                ),
                boardUri,
            ),
        );

        await expectLater(
            repository.loadBoard(boardUri, expectedBoardId: 30),
            throwsA(isA<ForumSessionExpiredException>()),
        );

        expect(
            await database.select(database.forumCaches).get(),
            isEmpty,
        );
    });

    test('同一版块旧请求后返回时被世代保护拒绝', () async
    {
        final Uri firstUri = _boardUri(page: 1);
        final Uri secondUri = _boardUri(page: 2);
        final Completer<Response<String>> first =
            Completer<Response<String>>();
        when(() => client.getText(firstUri)).thenAnswer((_) => first.future);
        when(() => client.getText(secondUri)).thenAnswer(
            (_) async => _response(_boardHtml(), secondUri),
        );

        final Future<ForumBoardPage> stale = repository.loadBoard(
            firstUri,
            expectedBoardId: 30,
        );
        final ForumBoardPage current = await repository.loadBoard(
            secondUri,
            expectedBoardId: 30,
        );
        first.complete(_response(_boardHtml(), firstUri));

        expect(current.cursor.currentPage, 2);
        await expectLater(
            stale,
            throwsA(isA<ForumRequestSupersededException>()),
        );
    });

    test('findpost 只接受最终移动主题且必须包含目标 pid', () async
    {
        final Uri redirectUri = ForumClient.baseUri.resolve(
            'forum.php?mod=redirect&goto=findpost&ptid=501&'
            'pid=9001&mobile=2',
        );
        final Uri resolvedUri = ForumClient.baseUri.resolve(
            'forum.php?mod=viewthread&tid=501&page=2&mobile=2#pid9001',
        );
        when(() => client.getText(redirectUri)).thenAnswer(
            (_) async => _response(_topicHtml, resolvedUri),
        );

        final ForumThreadPage page = await repository.loadThreadAtPost(
            threadId: 501,
            postId: 9001,
        );

        expect(page.focusedPostId, 9001);
        expect(page.postById(9001), isNotNull);
    });
}

Response<String> _response(String body, Uri uri)
{
    return Response<String>(
        requestOptions: RequestOptions(path: uri.toString()),
        data: body,
        statusCode: 200,
    );
}

Uri _boardUri({required int page})
{
    return ForumClient.baseUri.resolve(
        'forum.php?mod=forumdisplay&fid=30&page=$page&mobile=2',
    );
}

String _boardHtml({int? nextPage, Uri? nextUri})
{
    final String next = nextUri?.toString() ??
        (nextPage == null ? '' : _boardUri(page: nextPage).toString());
    return '''
    <html><head><script>var discuz_uid = '42';</script></head>
    <body id="forum" class="pg_forumdisplay">
      <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
      <div class="threadlist"><ul>
        <li class="list"><a href="forum.php?mod=viewthread&amp;tid=501&amp;mobile=2"><div class="threadlist_tit"><em>测试主题</em></div></a><div class="threadlist_foot"><ul><li>12</li><li>3</li></ul></div></li>
      </ul></div>
      <div class="pg">
        <input name="custompage" value="${nextPage == null ? 2 : 1}">
        ${next.isEmpty ? '' : '<a class="nxt" href="$next">下一页</a>'}
      </div>
    </body></html>
    ''';
}

const String _indexHtml = '''
<html><head><script>var discuz_uid = '42';</script></head>
<body id="forum" class="pg_index">
  <a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a>
</body></html>
''';

const String _indexJson = '''
{"Variables":{"member_uid":"42","catlist":[{"fid":"1","name":"阅读区","forums":["30","77"]}],"forumlist":[{"fid":"30","name":"漫画区"},{"fid":"77","name":"隐藏区"}]}}
''';

const String _topicHtml = '''
<html><head><script>var discuz_uid = '42';</script></head>
<body id="forum" class="pg_viewthread">
  <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
  <div class="viewthread">
    <div class="view_tit">测试主题</div>
    <div class="plc cl" id="pid9001">
      <ul class="authi"><li class="mtit"><span class="y">31#</span><span class="z"><a href="home.php?mod=space&amp;uid=7&amp;mobile=2">作者</a></span></li><li class="mtime">刚刚</li></ul>
      <div class="message">楼层正文</div>
    </div>
  </div>
</body></html>
''';
