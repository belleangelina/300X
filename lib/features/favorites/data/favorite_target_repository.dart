import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/favorites/data/favorite_target_contract.dart';
import 'package:x300/features/favorites/data/favorite_target_parser.dart';
import 'package:x300/features/favorites/domain/favorite_target_models.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

final Provider<FavoriteTargetRepository> favoriteTargetRepositoryProvider =
    Provider<FavoriteTargetRepository>(
      (Ref ref) => FavoriteTargetRepository(
        ref.watch(forumClientProvider),
        ref.watch(forumLocalRepositoryProvider),
        ref.watch(authControllerProvider).value?.userId ?? 0,
      ),
    );

class FavoriteTargetRepository {
  FavoriteTargetRepository(
    this._client,
    this._localRepository,
    this._userId, [
    this._parser = const FavoriteTargetParser(),
    this._contract = const FavoriteTargetContract(),
    this._authParser = const AuthPageParser(),
  ]);

  final ForumClient _client;
  final ForumLocalRepository _localRepository;
  final int _userId;
  final FavoriteTargetParser _parser;
  final FavoriteTargetContract _contract;
  final AuthPageParser _authParser;
  final _FavoriteGroupCacheCodec _groupCacheCodec =
      const _FavoriteGroupCacheCodec();
  final _FavoriteGroupBoardCacheCodec _groupBoardCacheCodec =
      const _FavoriteGroupBoardCacheCodec();
  final Map<String, int> _cacheGenerations = <String, int>{};

  Future<FavoriteTargetContent> load(RawFavoriteItem item) {
    _checkUserId();
    final FavoriteTargetDescriptor descriptor = _contract.requireItem(
      item,
      allowedKinds: const <RawFavoriteTargetKind>{
        RawFavoriteTargetKind.groupBoard,
        RawFavoriteTargetKind.groupCategory,
        RawFavoriteTargetKind.blog,
        RawFavoriteTargetKind.album,
      },
    );
    return switch (descriptor.kind) {
      RawFavoriteTargetKind.groupBoard => _loadGroupBoard(item, descriptor),
      RawFavoriteTargetKind.groupCategory => _loadGroupPageWithCache(
        descriptor.uri,
        groupId: descriptor.targetId,
        fallbackTitle: item.title,
      ),
      RawFavoriteTargetKind.blog => _loadBlog(descriptor),
      RawFavoriteTargetKind.album => _loadAlbum(descriptor),
      _ => throw const ForumParseException('该收藏目标暂不支持原生读取'),
    };
  }

  Future<FavoriteGroupPage> loadNextGroup(FavoriteGroupPage cursor) {
    _checkUserId();
    final Uri? nextPageUri = cursor.nextPageUri;
    if (cursor.isFromCache || nextPageUri == null) {
      return Future<FavoriteGroupPage>.value(cursor);
    }
    _contract.requireGroupCategoryPage(
      nextPageUri,
      expectedGroupId: cursor.groupId,
    );
    return _loadGroupPageWithCache(
      nextPageUri,
      groupId: cursor.groupId,
      fallbackTitle: cursor.title,
    );
  }

  Future<FavoriteGroupBoardTarget> _loadGroupBoard(
    RawFavoriteItem item,
    FavoriteTargetDescriptor descriptor,
  ) async {
    final String cacheKey = 'favorites:v2:group-board:${descriptor.targetId}';
    final int generation = _beginCacheGeneration(cacheKey);
    try {
      return await _client.withActiveAccount<FavoriteGroupBoardTarget>(
        _userId,
        () async {
          final Response<String> response = await _client.getText(
            descriptor.uri,
          );
          final String html = response.data ?? '';
          _validateIdentity(html);
          final FavoriteGroupBoardTarget target = _parser.parseGroupBoardResult(
            html,
            response.realUri,
            expectedBoardId: descriptor.targetId,
            fallbackTitle: item.title,
          );
          try {
            await _localRepository.saveCacheIfCurrent(
              userId: _userId,
              key: cacheKey,
              payload: _groupBoardCacheCodec.encode(target, userId: _userId),
              isCurrent: () => _isCurrentCacheGeneration(
                cacheKey,
                generation,
              ),
            );
          } on Object {
            // 群组到版块的只读映射缓存失败不覆盖服务端成功结果。
          }
          return target;
        },
      );
    } on ForumConnectionException catch (error, stackTrace) {
      try {
        final ForumCacheSnapshot? snapshot = await _client.withActiveAccount(
          _userId,
          () => _localRepository.loadCache(userId: _userId, key: cacheKey),
        );
        if (snapshot != null) {
          return _groupBoardCacheCodec.decode(
            snapshot.payload,
            userId: _userId,
            expectedBoardId: descriptor.targetId,
          );
        }
      } on ForumSessionExpiredException {
        rethrow;
      } on Object {
        // 损坏或不兼容映射缓存按不存在处理，保留原连接错误。
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<FavoriteGroupPage> _loadGroupPageWithCache(
    Uri uri, {
    required int groupId,
    required String fallbackTitle,
  }) async {
    final String cacheKey = _groupCacheKey(uri, groupId);
    final int generation = _beginCacheGeneration(cacheKey);
    try {
      return await _client.withActiveAccount<FavoriteGroupPage>(
        _userId,
        () async {
          final Response<String> response = await _client.getText(uri);
          final String html = response.data ?? '';
          _validateIdentity(html);
          final FavoriteGroupPage page = _parser.parseGroupPage(
            html,
            response.realUri,
            expectedGroupId: groupId,
            fallbackTitle: fallbackTitle,
          );
          try {
            await _localRepository.saveCacheIfCurrent(
              userId: _userId,
              key: cacheKey,
              payload: _groupCacheCodec.encode(page, userId: _userId),
              isCurrent: () => _isCurrentCacheGeneration(
                cacheKey,
                generation,
              ),
            );
          } on Object {
            // 群组只读缓存失败不覆盖服务端成功结果。
          }
          return page;
        },
      );
    } on ForumConnectionException catch (error, stackTrace) {
      try {
        final ForumCacheSnapshot? snapshot = await _client.withActiveAccount(
          _userId,
          () => _localRepository.loadCache(userId: _userId, key: cacheKey),
        );
        if (snapshot != null) {
          return _groupCacheCodec.decode(
            snapshot.payload,
            userId: _userId,
            expectedGroupId: groupId,
            updatedAt: snapshot.updatedAt,
          );
        }
      } on ForumSessionExpiredException {
        rethrow;
      } on Object {
        // 损坏或不兼容缓存按不存在处理，保留原连接错误。
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<FavoriteBlog> _loadBlog(FavoriteTargetDescriptor descriptor) {
    return _client.withActiveAccount<FavoriteBlog>(_userId, () async {
      final Response<String> response = await _client.getText(descriptor.uri);
      final String html = response.data ?? '';
      _validateIdentity(html);
      return _parser.parseBlog(
        html,
        response.realUri,
        expectedBlogId: descriptor.targetId,
        expectedOwnerUserId: descriptor.ownerUserId!,
      );
    });
  }

  Future<FavoriteAlbum> _loadAlbum(FavoriteTargetDescriptor descriptor) {
    return _client.withActiveAccount<FavoriteAlbum>(_userId, () async {
      final Response<String> response = await _client.getText(descriptor.uri);
      final String html = response.data ?? '';
      _validateIdentity(html);
      return _parser.parseAlbum(
        html,
        response.realUri,
        expectedAlbumId: descriptor.targetId,
        expectedOwnerUserId: descriptor.ownerUserId!,
      );
    });
  }

  void _validateIdentity(String html) {
    if (_authParser.currentUserId(html) != _userId) {
      throw const ForumSessionExpiredException();
    }
  }

  String _groupCacheKey(Uri uri, int groupId) {
    return 'favorites:v2:group:$groupId:${Uri.encodeComponent(uri.query)}';
  }

  int _beginCacheGeneration(String scope) {
    final int generation = (_cacheGenerations[scope] ?? 0) + 1;
    _cacheGenerations[scope] = generation;
    return generation;
  }

  bool _isCurrentCacheGeneration(String scope, int generation) {
    return _cacheGenerations[scope] == generation;
  }

  void _checkUserId() {
    if (_userId <= 0) {
      throw const ForumSessionExpiredException();
    }
  }
}

class _FavoriteGroupBoardCacheCodec {
  const _FavoriteGroupBoardCacheCodec();

  Map<String, dynamic> encode(
    FavoriteGroupBoardTarget target, {
    required int userId,
  }) {
    return <String, dynamic>{
      'schema': 1,
      'userId': userId,
      'boardId': target.board.id,
      'name': target.board.name,
      'sourceUri': target.sourceUri.toString(),
    };
  }

  FavoriteGroupBoardTarget decode(
    Map<String, dynamic> value, {
    required int userId,
    required int expectedBoardId,
  }) {
    final int boardId = _integer(value['boardId']);
    final String name = value['name']?.toString() ?? '';
    final Uri? sourceUri = Uri.tryParse(value['sourceUri']?.toString() ?? '');
    if (_integer(value['schema']) != 1 ||
        _integer(value['userId']) != userId ||
        boardId != expectedBoardId ||
        name.isEmpty ||
        sourceUri == null) {
      throw const ForumParseException('群组版块映射缓存无效');
    }
    const FavoriteTargetContract().requireGroupBoardResult(
      sourceUri,
      expectedBoardId: expectedBoardId,
    );
    return FavoriteGroupBoardTarget(
      board: ForumBoardNode(id: boardId, name: name, uri: sourceUri),
      sourceUri: sourceUri,
    );
  }

  int _integer(Object? value) {
    return value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _FavoriteGroupCacheCodec {
  const _FavoriteGroupCacheCodec();

  Map<String, dynamic> encode(FavoriteGroupPage page, {required int userId}) {
    return <String, dynamic>{
      'schema': 1,
      'userId': userId,
      'groupId': page.groupId,
      'title': page.title,
      'currentPage': page.currentPage,
      'sourceUri': page.sourceUri.toString(),
      'nextPageUri': page.nextPageUri?.toString(),
      'boards': page.boards
          .map(
            (ForumBoardNode value) => <String, dynamic>{
              'id': value.id,
              'name': value.name,
              'description': value.description,
              'uri': value.uri.toString(),
            },
          )
          .toList(growable: false),
    };
  }

  FavoriteGroupPage decode(
    Map<String, dynamic> value, {
    required int userId,
    required int expectedGroupId,
    required DateTime updatedAt,
  }) {
    if (_integer(value['schema']) != 1 ||
        _integer(value['userId']) != userId ||
        _integer(value['groupId']) != expectedGroupId) {
      throw const ForumParseException('群组缓存版本、账号或目标不一致');
    }
    final Uri sourceUri = _requiredGroupUri(
      value['sourceUri'],
      expectedGroupId,
    );
    final Uri? nextPageUri = value['nextPageUri'] == null
        ? null
        : _requiredGroupUri(value['nextPageUri'], expectedGroupId);
    final Object? rawBoards = value['boards'];
    if (rawBoards is! List<dynamic>) {
      throw const ForumParseException('群组缓存版块列表无效');
    }
    final List<ForumBoardNode> boards = <ForumBoardNode>[];
    for (final Object? raw in rawBoards) {
      if (raw is! Map<String, dynamic>) {
        throw const ForumParseException('群组缓存版块无效');
      }
      final int id = _integer(raw['id']);
      final String name = raw['name']?.toString() ?? '';
      final Uri? uri = Uri.tryParse(raw['uri']?.toString() ?? '');
      if (id <= 0 || name.isEmpty || uri == null) {
        throw const ForumParseException('群组缓存版块无效');
      }
      final FavoriteTargetDescriptor? descriptor =
          const FavoriteTargetContract().describe(uri);
      if (descriptor?.kind != RawFavoriteTargetKind.board ||
          descriptor?.targetId != id) {
        throw const ForumParseException('群组缓存版块地址无效');
      }
      boards.add(
        ForumBoardNode(
          id: id,
          name: name,
          description: raw['description']?.toString() ?? '',
          uri: uri,
        ),
      );
    }
    final int currentPage = _integer(value['currentPage']);
    if (currentPage <= 0) {
      throw const ForumParseException('群组缓存页码无效');
    }
    return FavoriteGroupPage(
      groupId: expectedGroupId,
      title: value['title']?.toString() ?? '',
      boards: List<ForumBoardNode>.unmodifiable(boards),
      currentPage: currentPage,
      sourceUri: sourceUri,
      nextPageUri: nextPageUri,
      isFromCache: true,
      cacheUpdatedAt: updatedAt,
    );
  }

  Uri _requiredGroupUri(Object? value, int expectedGroupId) {
    final Uri? uri = Uri.tryParse(value?.toString() ?? '');
    if (uri == null) {
      throw const ForumParseException('群组缓存分页地址无效');
    }
    const FavoriteTargetContract().requireGroupCategoryPage(
      uri,
      expectedGroupId: expectedGroupId,
    );
    return uri;
  }

  int _integer(Object? value) {
    return value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
