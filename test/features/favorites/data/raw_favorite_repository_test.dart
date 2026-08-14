import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/favorites/data/raw_favorite_repository.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
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
  late RawFavoriteRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    localRepository = ForumLocalRepository(database);
    client = _MockForumClient();
    _stubAccountLease(client);
    repository = RawFavoriteRepository(client, localRepository, 42);
  });

  tearDown(() => database.close());

  test('优先使用服务端全部分类及页面返回的精确翻页 URI', () async {
    final Uri allUri = _categoryUri('all').replace(
      queryParameters: <String, String>{
        ..._categoryUri('all').queryParameters,
        'server_token': 'category-token',
      },
    );
    final Uri nextUri = allUri.replace(
      queryParameters: <String, String>{
        ...allUri.queryParameters,
        'page': '2',
        'cursor': 'opaque-next',
      },
    );
    when(() => client.getText(RawFavoriteRepository.discoveryUri)).thenAnswer(
      (_) async => _response(
        _favoriteHtml(
          categories: <(String, String, Uri)>[
            ('thread', '主题', _categoryUri('thread')),
            ('forum', '版块', _categoryUri('forum')),
            ('all', '全部', allUri),
          ],
          selectedKey: 'thread',
          items: <String>[_threadItem(501, 71)],
        ),
        RawFavoriteRepository.discoveryUri,
      ),
    );
    when(() => client.getText(allUri)).thenAnswer(
      (_) async => _response(
        _favoriteHtml(
          categories: <(String, String, Uri)>[
            ('thread', '主题', _categoryUri('thread')),
            ('forum', '版块', _categoryUri('forum')),
            ('all', '全部', allUri),
          ],
          selectedKey: 'all',
          items: <String>[_threadItem(601, 81)],
          nextUri: nextUri,
        ),
        allUri,
      ),
    );
    when(() => client.getText(nextUri)).thenAnswer(
      (_) async => _response(
        _favoriteHtml(
          categories: <(String, String, Uri)>[
            ('thread', '主题', _categoryUri('thread')),
            ('forum', '版块', _categoryUri('forum')),
            ('all', '全部', allUri),
          ],
          selectedKey: 'all',
          items: <String>[_threadItem(602, 82)],
          currentPage: 2,
        ),
        nextUri,
      ),
    );

    final RawFavoritePage first = await repository.loadInitial();
    final RawFavoritePage second = await repository.loadNext(first);

    expect(first.selectedCategoryKey, RawFavoriteRepository.allCategoryKey);
    expect(first.items.single.threadId, 601);
    expect(second.items.map((RawFavoriteItem value) => value.threadId), <int?>[
      601,
      602,
    ]);
    verifyInOrder(<void Function()>[
      () => client.getText(RawFavoriteRepository.discoveryUri),
      () => client.getText(allUri),
      () => client.getText(nextUri),
    ]);
  });

  test('没有真实全部分类时按服务端顺序合并各分类及各自游标', () async {
    final Uri threadNext = _categoryUri('thread').replace(
      queryParameters: <String, String>{
        ..._categoryUri('thread').queryParameters,
        'page': '2',
        'cursor': 'thread-next',
      },
    );
    final Uri forumNext = _categoryUri('forum').replace(
      queryParameters: <String, String>{
        ..._categoryUri('forum').queryParameters,
        'page': '9',
        'cursor': 'forum-next',
      },
    );
    final List<(String, String, Uri)> categories = <(String, String, Uri)>[
      ('thread', '主题', _categoryUri('thread')),
      ('forum', '版块', _categoryUri('forum')),
      ('group', '群组', _categoryUri('group')),
    ];
    when(() => client.getText(RawFavoriteRepository.discoveryUri)).thenAnswer(
      (_) async => _response(
        _favoriteHtml(
          categories: categories,
          selectedKey: 'thread',
          items: <String>[_threadItem(501, 71)],
          nextUri: threadNext,
        ),
        RawFavoriteRepository.discoveryUri,
      ),
    );
    when(() => client.getText(_categoryUri('forum'))).thenAnswer(
      (_) async => _response(
        _favoriteHtml(
          categories: categories,
          selectedKey: 'forum',
          items: <String>[_boardItem(30)],
          nextUri: forumNext,
        ),
        _categoryUri('forum'),
      ),
    );
    when(() => client.getText(_categoryUri('group'))).thenAnswer(
      (_) async => _response(
        _favoriteHtml(
          categories: categories,
          selectedKey: 'group',
          items: <String>[_groupItem(80)],
        ),
        _categoryUri('group'),
      ),
    );
    when(() => client.getText(threadNext)).thenAnswer(
      (_) async => _response(
        _favoriteHtml(
          categories: categories,
          selectedKey: 'thread',
          items: <String>[_threadItem(502, 72)],
          currentPage: 2,
        ),
        threadNext,
      ),
    );
    when(() => client.getText(forumNext)).thenAnswer(
      (_) async => _response(
        _favoriteHtml(
          categories: categories,
          selectedKey: 'forum',
          items: <String>[_boardItem(31)],
          currentPage: 9,
        ),
        forumNext,
      ),
    );

    final RawFavoritePage first = await repository.loadInitial();
    final RawFavoritePage second = await repository.loadNext(first);

    expect(
      first.items.map((RawFavoriteItem value) => value.targetKind),
      <RawFavoriteTargetKind>[
        RawFavoriteTargetKind.thread,
        RawFavoriteTargetKind.board,
        RawFavoriteTargetKind.groupBoard,
      ],
    );
    expect(first.mergedCursors.keys, <String>['thread', 'forum', 'group']);
    expect(second.items, hasLength(5));
    expect(second.hasNext, isFalse);
    verifyInOrder(<void Function()>[
      () => client.getText(threadNext),
      () => client.getText(forumNext),
    ]);
  });

  test('仅连接失败回退同 uid 缓存且缓存不含 formhash', () async {
    final Uri allUri = _categoryUri('all').replace(
      queryParameters: <String, String>{
        ..._categoryUri('all').queryParameters,
        'formhash': 'secret-value',
      },
    );
    final List<(String, String, Uri)> categories = <(String, String, Uri)>[
      ('all', '全部', allUri),
    ];
    when(() => client.getText(RawFavoriteRepository.discoveryUri)).thenAnswer(
      (_) async => _response(
        _favoriteHtml(
          categories: categories,
          selectedKey: 'all',
          items: <String>[_threadItem(501, 71)],
        ),
        allUri,
      ),
    );

    await repository.loadInitial();

    final List<ForumCache> rows = await database
        .select(database.forumCaches)
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.payloadJson.toLowerCase(), isNot(contains('formhash')));
    expect(rows.single.payloadJson, isNot(contains('secret-value')));

    reset(client);
    _stubAccountLease(client);
    when(
      () => client.getText(RawFavoriteRepository.discoveryUri),
    ).thenThrow(const ForumConnectionException('离线'));
    final RawFavoritePage cached = await repository.loadInitial();
    expect(cached.isFromCache, isTrue);
    expect(cached.items.single.threadId, 501);

    final RawFavoriteRepository otherAccount = RawFavoriteRepository(
      client,
      localRepository,
      43,
    );
    await expectLater(
      otherAccount.loadInitial(),
      throwsA(isA<ForumConnectionException>()),
    );

    reset(client);
    _stubAccountLease(client);
    when(() => client.getText(RawFavoriteRepository.discoveryUri)).thenAnswer(
      (_) async => _response('''
                    <script>var discuz_uid = '42';</script>
                    <body class="pg_space">
                      <a href="${_categoryUri('all')}">全部</a>
                    </body>
                    ''', RawFavoriteRepository.discoveryUri),
    );
    await expectLater(
      repository.loadInitial(),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('旧请求晚返回时不会覆盖新收藏结果', () async {
    final Completer<Response<String>> stale = Completer<Response<String>>();
    var calls = 0;
    final List<(String, String, Uri)> categories = <(String, String, Uri)>[
      ('thread', '主题', _categoryUri('thread')),
    ];
    when(() => client.getText(RawFavoriteRepository.discoveryUri)).thenAnswer((
      _,
    ) async {
      if (calls++ == 0) {
        return stale.future;
      }
      return _response(
        _favoriteHtml(
          categories: categories,
          selectedKey: 'thread',
          items: <String>[_threadItem(502, 72)],
        ),
        RawFavoriteRepository.discoveryUri,
      );
    });

    final Future<RawFavoritePage> oldRequest = repository.loadInitial();
    final RawFavoritePage current = await repository.loadInitial();
    stale.complete(
      _response(
        _favoriteHtml(
          categories: categories,
          selectedKey: 'thread',
          items: <String>[_threadItem(501, 71)],
        ),
        RawFavoriteRepository.discoveryUri,
      ),
    );

    expect(current.items.single.threadId, 502);
    await expectLater(
      oldRequest,
      throwsA(isA<RawFavoriteRequestSupersededException>()),
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

Uri _categoryUri(String key) {
  return ForumClient.baseUri.resolve(
    'home.php?mod=space&do=favorite&type=$key&mobile=2',
  );
}

String _favoriteHtml({
  required List<(String, String, Uri)> categories,
  required String selectedKey,
  required List<String> items,
  Uri? nextUri,
  int currentPage = 1,
}) {
  final String categoryHtml = categories
      .map(
        ((String, String, Uri) value) =>
            '<a class="${value.$1 == selectedKey ? 'a' : ''}" '
            'href="${value.$3}">${value.$2}</a>',
      )
      .join();
  return '''
    <html><head><script>var discuz_uid = '42';</script></head>
    <body id="home" class="pg_space">
      <nav>$categoryHtml</nav>
      <div class="findbox"><ul>${items.join()}</ul></div>
      <div class="pg">
        <strong>$currentPage</strong>
        <input name="custompage" value="$currentPage">
        ${nextUri == null ? '' : '<a class="nxt" href="$nextUri">下一页</a>'}
      </div>
    </body></html>
    ''';
}

String _threadItem(int threadId, int favoriteId) {
  return '''
    <li class="sclist">
      <a href="home.php?mod=spacecp&amp;ac=favorite&amp;op=delete&amp;favid=$favoriteId&amp;mobile=2">删除</a>
      <h4><a href="forum.php?mod=viewthread&amp;tid=$threadId&amp;mobile=2">主题 $threadId</a></h4>
    </li>
    ''';
}

String _boardItem(int boardId) {
  return '''
    <li class="sclist">
      <h4><a href="forum.php?mod=forumdisplay&amp;fid=$boardId&amp;mobile=2">版块 $boardId</a></h4>
    </li>
    ''';
}

String _groupItem(int boardId) {
  return '''
    <li class="sclist">
      <h4><a href="forum.php?mod=group&amp;fid=$boardId&amp;mobile=2">群组 $boardId</a></h4>
    </li>
    ''';
}
