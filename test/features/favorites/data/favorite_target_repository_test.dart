import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/favorites/data/favorite_target_repository.dart';
import 'package:x300/features/favorites/domain/favorite_target_models.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';

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
    _saveCount += 1;
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
  late ForumLocalRepository localRepository;
  late _MockForumClient client;
  late FavoriteTargetRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    localRepository = ForumLocalRepository(database);
    client = _MockForumClient();
    _stubAccountLeases(client);
    repository = FavoriteTargetRepository(client, localRepository, 42);
  });

  tearDown(() => database.close());

  test('群组收藏只 GET 原入口并验证最终同 fid 版块', () async {
    final Uri finalUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&action=list&fid=80&mobile=2',
    );
    when(() => client.getText(_groupBoardItem.targetUri!)).thenAnswer(
      (_) async => _response(_fixture('group_board_mobile.html'), finalUri),
    );

    final FavoriteTargetContent target = await repository.load(_groupBoardItem);

    expect(target, isA<FavoriteGroupBoardTarget>());
    expect((target as FavoriteGroupBoardTarget).board.id, 80);
    verify(() => client.getText(_groupBoardItem.targetUri!)).called(1);

    reset(client);
    _stubAccountLeases(client);
    when(
      () => client.getText(_groupBoardItem.targetUri!),
    ).thenThrow(const ForumConnectionException('离线'));
    final FavoriteGroupBoardTarget cached =
        await repository.load(_groupBoardItem) as FavoriteGroupBoardTarget;
    expect(cached.board.id, 80);
    expect(cached.board.uri, finalUri);
  });

  test('群组分类仅连接失败回退同 uid 缓存', () async {
    when(() => client.getText(_groupItem.targetUri!)).thenAnswer(
      (_) async => _response(
        _fixture('group_category_mobile.html'),
        _groupItem.targetUri!,
      ),
    );
    final FavoriteGroupPage remote =
        await repository.load(_groupItem) as FavoriteGroupPage;
    expect(remote.isFromCache, isFalse);
    expect(await database.select(database.forumCaches).get(), hasLength(1));

    reset(client);
    _stubAccountLeases(client);
    when(
      () => client.getText(_groupItem.targetUri!),
    ).thenThrow(const ForumConnectionException('离线'));
    final FavoriteGroupPage cached =
        await repository.load(_groupItem) as FavoriteGroupPage;
    expect(cached.isFromCache, isTrue);
    expect(cached.boards.map((value) => value.id), <int>[80, 81]);

    final FavoriteTargetRepository otherAccount = FavoriteTargetRepository(
      client,
      localRepository,
      43,
    );
    await expectLater(
      otherAccount.load(_groupItem),
      throwsA(isA<ForumConnectionException>()),
    );
  });

  test('群组版块缓存写入期间被新请求取代时不覆盖新缓存', () async {
    final _GatedForumLocalRepository gated = _GatedForumLocalRepository(
      database,
    );
    localRepository = gated;
    repository = FavoriteTargetRepository(client, localRepository, 42);
    var requestCount = 0;
    final Uri finalUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&action=list&fid=80&mobile=2',
    );
    when(() => client.getText(_groupBoardItem.targetUri!)).thenAnswer((_) async {
      requestCount += 1;
      return _response(
        _fixture('group_board_mobile.html').replaceFirst(
          '群组版块</div>',
          requestCount == 1 ? '旧群组版块</div>' : '新群组版块</div>',
        ),
        finalUri,
      );
    });

    final Future<FavoriteTargetContent> stale = repository.load(
      _groupBoardItem,
    );
    await gated.firstSaveStarted.future;
    final FavoriteTargetContent current = await repository.load(
      _groupBoardItem,
    );
    expect(
      (current as FavoriteGroupBoardTarget).board.name,
      '新群组版块',
    );
    gated.releaseFirstSave.complete();
    expect((await stale as FavoriteGroupBoardTarget).board.name, '旧群组版块');

    final ForumCacheSnapshot? snapshot = await localRepository.loadCache(
      userId: 42,
      key: 'favorites:v2:group-board:80',
    );
    expect(snapshot?.payload['name'], '新群组版块');
  });

  test('群组分类旧响应后返时不覆盖同页面新缓存', () async {
    final Completer<Response<String>> staleResponse =
        Completer<Response<String>>();
    final Completer<Response<String>> currentResponse =
        Completer<Response<String>>();
    var requestCount = 0;
    when(() => client.getText(_groupItem.targetUri!)).thenAnswer((_) {
      requestCount += 1;
      return requestCount == 1 ? staleResponse.future : currentResponse.future;
    });

    final Future<FavoriteTargetContent> stale = repository.load(_groupItem);
    final Future<FavoriteTargetContent> current = repository.load(_groupItem);
    currentResponse.complete(
      _response(
        _fixture('group_category_mobile.html').replaceFirst(
          '版块甲简介',
          '新版块甲简介',
        ),
        _groupItem.targetUri!,
      ),
    );
    expect(
      (await current as FavoriteGroupPage).boards.first.description,
      '新版块甲简介',
    );
    staleResponse.complete(
      _response(
        _fixture('group_category_mobile.html').replaceFirst(
          '版块甲简介',
          '旧版块甲简介',
        ),
        _groupItem.targetUri!,
      ),
    );
    expect(
      (await stale as FavoriteGroupPage).boards.first.description,
      '旧版块甲简介',
    );

    final String cacheKey =
        'favorites:v2:group:8:${Uri.encodeComponent(_groupItem.targetUri!.query)}';
    final ForumCacheSnapshot? snapshot = await localRepository.loadCache(
      userId: 42,
      key: cacheKey,
    );
    expect(
      (snapshot?.payload['boards'] as List<dynamic>).first['description'],
      '新版块甲简介',
    );
  });

  test('解析或身份错误不回退群组旧缓存', () async {
    when(() => client.getText(_groupItem.targetUri!)).thenAnswer(
      (_) async => _response(
        _fixture('group_category_mobile.html'),
        _groupItem.targetUri!,
      ),
    );
    await repository.load(_groupItem);

    when(() => client.getText(_groupItem.targetUri!)).thenAnswer(
      (_) async => _response(
        _fixture(
          'group_category_mobile.html',
        ).replaceFirst('id="group"', 'id="forum"'),
        _groupItem.targetUri!,
      ),
    );
    await expectLater(
      repository.load(_groupItem),
      throwsA(isA<ForumParseException>()),
    );

    when(() => client.getText(_groupItem.targetUri!)).thenAnswer(
      (_) async => _response(
        _fixture(
          'group_category_mobile.html',
        ).replaceFirst("discuz_uid = '42'", "discuz_uid = '43'"),
        _groupItem.targetUri!,
      ),
    );
    await expectLater(
      repository.load(_groupItem),
      throwsA(isA<ForumSessionExpiredException>()),
    );
  });

  test('日志和相册正文默认不写入论坛缓存', () async {
    when(() => client.getText(_blogItem.targetUri!)).thenAnswer(
      (_) async =>
          _response(_fixture('blog_mobile.html'), _blogItem.targetUri!),
    );
    when(() => client.getText(_albumItem.targetUri!)).thenAnswer(
      (_) async =>
          _response(_fixture('album_mobile.html'), _albumItem.targetUri!),
    );

    expect(await repository.load(_blogItem), isA<FavoriteBlog>());
    expect(await repository.load(_albumItem), isA<FavoriteAlbum>());
    expect(await database.select(database.forumCaches).get(), isEmpty);
    verify(() => client.getText(_blogItem.targetUri!)).called(1);
    verify(() => client.getText(_albumItem.targetUri!)).called(1);
  });

  test('最终 URI 的 uid、目标 id 或额外动作不一致时失败关闭', () async {
    for (final Uri finalUri in <Uri>[
      _blogItem.targetUri!.replace(
        queryParameters: <String, String>{
          ..._blogItem.targetUri!.queryParameters,
          'uid': '8',
        },
      ),
      _blogItem.targetUri!.replace(
        queryParameters: <String, String>{
          ..._blogItem.targetUri!.queryParameters,
          'id': '92',
        },
      ),
      _blogItem.targetUri!.replace(
        queryParameters: <String, String>{
          ..._blogItem.targetUri!.queryParameters,
          'op': 'delete',
        },
      ),
    ]) {
      reset(client);
      _stubAccountLeases(client);
      when(() => client.getText(_blogItem.targetUri!)).thenAnswer(
        (_) async => _response(_fixture('blog_mobile.html'), finalUri),
      );
      await expectLater(
        repository.load(_blogItem),
        throwsA(isA<ForumParseException>()),
      );
    }
  });
}

void _stubAccountLeases(_MockForumClient client) {
  when(
    () => client.withActiveAccount<FavoriteGroupBoardTarget>(any(), any()),
  ).thenAnswer((Invocation invocation) {
    final action =
        invocation.positionalArguments[1]
            as Future<FavoriteGroupBoardTarget> Function();
    return action();
  });
  when(
    () => client.withActiveAccount<FavoriteGroupPage>(any(), any()),
  ).thenAnswer((Invocation invocation) {
    final action =
        invocation.positionalArguments[1]
            as Future<FavoriteGroupPage> Function();
    return action();
  });
  when(() => client.withActiveAccount<FavoriteBlog>(any(), any())).thenAnswer((
    Invocation invocation,
  ) {
    final action =
        invocation.positionalArguments[1] as Future<FavoriteBlog> Function();
    return action();
  });
  when(() => client.withActiveAccount<FavoriteAlbum>(any(), any())).thenAnswer((
    Invocation invocation,
  ) {
    final action =
        invocation.positionalArguments[1] as Future<FavoriteAlbum> Function();
    return action();
  });
  when(
    () => client.withActiveAccount<ForumCacheSnapshot?>(any(), any()),
  ).thenAnswer((Invocation invocation) {
    final action =
        invocation.positionalArguments[1]
            as Future<ForumCacheSnapshot?> Function();
    return action();
  });
}

Response<String> _response(String body, Uri realUri) {
  return Response<String>(
    requestOptions: RequestOptions(path: realUri.toString()),
    data: body,
    statusCode: 200,
  );
}

String _fixture(String name) {
  return File('test/fixtures/favorites/$name').readAsStringSync();
}

final RawFavoriteItem _groupBoardItem = RawFavoriteItem(
  categoryKey: 'group',
  title: '群组版块',
  targetKind: RawFavoriteTargetKind.groupBoard,
  targetUri: Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=group&fid=80&mobile=2',
  ),
  boardId: 80,
);

final RawFavoriteItem _groupItem = RawFavoriteItem(
  categoryKey: 'group',
  title: '群组分类',
  targetKind: RawFavoriteTargetKind.groupCategory,
  targetUri: Uri.parse('https://bbs.yamibo.com/group.php?gid=8&mobile=2'),
  groupId: 8,
);

final RawFavoriteItem _blogItem = RawFavoriteItem(
  categoryKey: 'blog',
  title: '日志',
  targetKind: RawFavoriteTargetKind.blog,
  targetUri: Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=space&do=blog&uid=7&id=91&mobile=2',
  ),
  userId: 7,
  contentId: 91,
);

final RawFavoriteItem _albumItem = RawFavoriteItem(
  categoryKey: 'album',
  title: '相册',
  targetKind: RawFavoriteTargetKind.album,
  targetUri: Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=space&do=album&uid=7&id=92&mobile=2',
  ),
  userId: 7,
  contentId: 92,
);
