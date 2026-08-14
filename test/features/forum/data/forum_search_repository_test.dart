import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';
import 'package:x300/features/forum/data/forum_search_repository.dart';
import 'package:x300/features/forum/domain/forum_search_models.dart';

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
  late ForumLocalRepository local;
  late _MockForumClient client;
  late ForumThreadSearchRepository repository;

  final Uri formUri = Uri.parse(
    'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=30&mobile=2',
  );
  final Uri actionUri = Uri.parse(
    'https://bbs.yamibo.com/search.php?mod=forum',
  );
  final Uri resultUri = Uri.parse(
    'https://bbs.yamibo.com/search.php?mod=forum&searchid=88&mobile=2',
  );

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    local = ForumLocalRepository(database);
    client = _MockForumClient();
    _stubAccountLease(client);
    repository = ForumThreadSearchRepository(client, local, 42);
  });

  tearDown(() => database.close());

  test('只提交移动表单声明字段和动态关键字且 POST 一次', () async {
    when(
      () => client.getText(formUri),
    ).thenAnswer((_) async => _response(_formHtml(), formUri));
    when(
      () => client.postForm(
        actionUri,
        fields: any(named: 'fields'),
        referer: formUri.toString(),
      ),
    ).thenAnswer((_) async => _response(_resultHtml(), resultUri));

    final ForumThreadSearchPage page = await repository.search(
      keyword: '  百合  ',
      formUri: formUri,
    );

    expect(page.boardId, 30);
    expect(page.hits.single.threadId, 501);
    final Map<String, dynamic> fields =
        verify(
              () => client.postForm(
                actionUri,
                fields: captureAny(named: 'fields'),
                referer: formUri.toString(),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(fields, <String, dynamic>{
      'formhash': 'secret-hash',
      'srhfid': '30',
      'searchsubmit': 'yes',
      'dynamic_keyword': '百合',
      'order_from_page': 'lastpost',
    });
    verify(() => client.getText(formUri)).called(1);
  });

  test('当前版块搜索提交到 curforum action 且保留 srhfid', () async {
    final Uri boardActionUri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=30',
    );
    when(
      () => client.getText(formUri),
    ).thenAnswer((_) async => _response(_curforumFormHtml(), formUri));
    when(
      () => client.postForm(
        boardActionUri,
        fields: any(named: 'fields'),
        referer: formUri.toString(),
      ),
    ).thenAnswer((_) async => _response(_resultHtml(), resultUri));

    final ForumThreadSearchPage page = await repository.search(
      keyword: '百合',
      formUri: formUri,
    );

    expect(page.boardId, 30);
    expect(page.hits.single.threadId, 501);
    final Map<String, dynamic> fields =
        verify(
              () => client.postForm(
                boardActionUri,
                fields: captureAny(named: 'fields'),
                referer: formUri.toString(),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(fields['srhfid'], '30');
    expect(fields['srchtxt'], '百合');
    expect(fields['searchsubmit'], 'yes');
  });

  test('连接失败才回退同 uid 规范化缓存且缓存不含表单秘密', () async {
    when(
      () => client.getText(formUri),
    ).thenAnswer((_) async => _response(_formHtml(), formUri));
    when(
      () => client.postForm(
        actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).thenAnswer((_) async => _response(_resultHtml(), resultUri));
    final ForumThreadSearchPage online = await repository.search(
      keyword: '百合',
      formUri: formUri,
    );
    expect(online.isFromCache, isFalse);

    final List<ForumCache> rows = await database
        .select(database.forumCaches)
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.payloadJson, isNot(contains('secret-hash')));
    expect(rows.single.payloadJson, isNot(contains('<html')));

    reset(client);
    _stubAccountLease(client);
    when(
      () => client.getText(formUri),
    ).thenThrow(const ForumConnectionException('离线'));
    final ForumThreadSearchPage cached = await repository.search(
      keyword: '百合',
      formUri: formUri,
    );
    expect(cached.isFromCache, isTrue);
    expect(cached.cacheUpdatedAt, isNotNull);
    expect(cached.hits.single.threadId, 501);
    expect(cached.hits.single.authorUri?.queryParameters['uid'], '7');

    final ForumThreadSearchRepository otherAccount =
        ForumThreadSearchRepository(client, local, 43);
    await expectLater(
      otherAccount.search(keyword: '百合', formUri: formUri),
      throwsA(isA<ForumConnectionException>()),
    );
  });

  test('在线模板解析失败不会被旧缓存伪装成成功', () async {
    when(
      () => client.getText(formUri),
    ).thenAnswer((_) async => _response(_formHtml(), formUri));
    when(
      () => client.postForm(
        actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).thenAnswer((_) async => _response(_resultHtml(), resultUri));
    await repository.search(keyword: '百合', formUri: formUri);

    reset(client);
    _stubAccountLease(client);
    when(
      () => client.getText(formUri),
    ).thenAnswer((_) async => _response(_formHtml(), formUri));
    when(
      () => client.postForm(
        actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).thenAnswer(
      (_) async => _response('''
                <head><script>var discuz_uid = '42';</script></head>
                <body id="search" class="pg_forum">
                    <div class="tip">移动模板已变化</div>
                </body>
                ''', resultUri),
    );

    await expectLater(
      repository.search(keyword: '百合', formUri: formUri),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('表单和结果都必须属于当前 uid', () async {
    when(() => client.getText(formUri)).thenAnswer(
      (_) async => _response(
        _formHtml().replaceFirst("discuz_uid = '42'", "discuz_uid = '7'"),
        formUri,
      ),
    );

    await expectLater(
      repository.search(keyword: '百合', formUri: formUri),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    verifyNever(
      () => client.postForm(
        any(),
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    );
  });

  test('翻页只请求结果页返回的精确 next URI', () async {
    final Uri nextUri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=forum&searchid=88&orderby=lastpost&page=2&mobile=2',
    );
    when(
      () => client.getText(formUri),
    ).thenAnswer((_) async => _response(_formHtml(), formUri));
    when(
      () => client.postForm(
        actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).thenAnswer(
      (_) async => _response(_resultHtml(nextUri: nextUri), resultUri),
    );
    when(
      () => client.getText(nextUri),
    ).thenAnswer((_) async => _response(_resultHtml(), nextUri));

    final ForumThreadSearchPage first = await repository.search(
      keyword: '百合',
      formUri: formUri,
    );
    expect(first.cursor.nextPageUri, nextUri);
    await repository.loadNext(first);

    verify(() => client.getText(nextUri)).called(1);
  });

  test('全站入口拒绝服务端暗中返回版块范围', () async {
    final Uri globalUri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
    );
    when(
      () => client.getText(globalUri),
    ).thenAnswer((_) async => _response(_formHtml(), globalUri));

    await expectLater(
      repository.search(keyword: '百合', formUri: globalUri),
      throwsA(isA<ForumParseException>()),
    );
    verifyNever(
      () => client.postForm(
        any(),
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    );
  });
}

Response<String> _response(String body, Uri uri) {
  return Response<String>(
    requestOptions: RequestOptions(path: uri.toString()),
    data: body,
    statusCode: 200,
  );
}

String _curforumFormHtml() {
  return '''
        <html><head><script>var discuz_uid = '42';</script></head>
        <body id="search" class="pg_curforum">
            <form class="searchform" method="post" action="search.php?mod=curforum&amp;srhfid=30">
                <input type="hidden" name="formhash" value="secret-hash">
                <input type="hidden" name="srhfid" value="30">
                <input type="hidden" name="searchsubmit" value="yes">
                <input type="search" name="srchtxt">
            </form>
        </body></html>
    ''';
}

String _formHtml() {
  return '''
        <html><head><script>var discuz_uid = '42';</script></head>
        <body id="search" class="pg_forum">
            <form class="searchform" method="post" action="search.php?mod=forum">
                <input type="hidden" name="formhash" value="secret-hash">
                <input type="hidden" name="srhfid" value="30">
                <input type="hidden" name="searchsubmit" value="yes">
                <input type="search" name="dynamic_keyword">
                <select name="order_from_page">
                    <option value="lastpost" selected>最新回复</option>
                    <option value="dateline">发布时间</option>
                </select>
            </form>
        </body></html>
    ''';
}

String _resultHtml({Uri? nextUri}) {
  final String pagination = nextUri == null
      ? ''
      : '''
            <div class="pg">
                <strong>1</strong>
                <a class="nxt" href="${nextUri.toString().replaceAll('&', '&amp;')}">下一页</a>
            </div>
        ''';
  return '''
        <html><head><script>var discuz_uid = '42';</script></head>
        <body id="search" class="pg_forum">
            <form class="searchform" method="post" action="search.php?mod=forum">
                <input type="hidden" name="formhash" value="result-hash">
                <input type="hidden" name="srhfid" value="30">
                <input type="text" name="srchtxt" value="百合">
            </form>
            <div class="threadlist_box">
                <h2>结果: 找到 “<span class="emfont">百合</span>” 相关内容 1 个</h2>
                <div class="threadlist"><ul>
                    <li class="list">
                        <div class="threadlist_top">
                            <div class="muser">
                                <a class="mmc" href="home.php?mod=space&amp;uid=7&amp;mobile=2">作者甲</a>
                                <span class="mtime">2026-8-12</span>
                            </div>
                        </div>
                        <a href="forum.php?mod=viewthread&amp;tid=501&amp;mobile=2">
                            <div class="threadlist_tit"><em>百合主题</em></div>
                        </a>
                        <div class="threadlist_mes">摘要</div>
                        <div class="threadlist_foot"><ul>
                            <li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">#漫画区</a></li>
                            <li>10</li><li>2</li>
                        </ul></div>
                    </li>
                </ul></div>
                $pagination
            </div>
        </body></html>
    ''';
}
