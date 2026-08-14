import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/favorites/data/raw_favorite_parser.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';

final Provider<RawFavoriteRepository> rawFavoriteRepositoryProvider =
    Provider<RawFavoriteRepository>(
      (Ref ref) => RawFavoriteRepository(
        ref.watch(forumClientProvider),
        ref.watch(forumLocalRepositoryProvider),
        ref.watch(authControllerProvider).value?.userId ?? 0,
      ),
    );

class RawFavoriteRepository {
  RawFavoriteRepository(
    this._client,
    this._localRepository,
    this._userId, [
    this._parser = const RawFavoriteParser(),
    this._authParser = const AuthPageParser(),
  ]);

  static const String allCategoryKey = '__all__';
  static final Uri discoveryUri = ForumClient.baseUri.resolve(
    'home.php?mod=space&do=favorite&mobile=2',
  );

  final ForumClient _client;
  final ForumLocalRepository _localRepository;
  final int _userId;
  final RawFavoriteParser _parser;
  final AuthPageParser _authParser;
  final _RawFavoriteCacheCodec _cacheCodec = const _RawFavoriteCacheCodec();

  int _generation = 0;

  Future<RawFavoritePage> loadInitial({String? categoryKey}) {
    _checkUserId();
    final String selection = categoryKey ?? allCategoryKey;
    final int generation = ++_generation;
    return _loadWithCache(
      selection: selection,
      generation: generation,
      loadRemote: () async {
        final RawFavoritePage discovery = await _fetchPage(discoveryUri);
        if (categoryKey != null) {
          final RawFavoriteCategory? category = _categoryByKey(
            discovery.categories,
            categoryKey,
          );
          if (category == null) {
            throw const ForumParseException('服务端已移除该收藏分类');
          }
          final RawFavoritePage selected =
              discovery.selectedCategoryKey == category.key
              ? discovery
              : await _fetchPage(
                  category.uri,
                  expectedCategoryKey: category.key,
                );
          return _replacePage(
            selected,
            categories: discovery.categories,
            selectedCategoryKey: category.key,
          );
        }

        final RawFavoriteCategory? allCategory = _allCategory(
          discovery.categories,
        );
        if (allCategory != null) {
          final RawFavoritePage allPage =
              discovery.selectedCategoryKey == allCategory.key
              ? discovery
              : await _fetchPage(
                  allCategory.uri,
                  expectedCategoryKey: allCategory.key,
                );
          return _replacePage(
            allPage,
            categories: discovery.categories,
            selectedCategoryKey: allCategoryKey,
          );
        }
        return _mergeFirstPages(discovery);
      },
    );
  }

  Future<RawFavoritePage> loadNext(RawFavoritePage cursor) {
    _checkUserId();
    if (!cursor.hasNext || cursor.isFromCache) {
      return Future<RawFavoritePage>.value(cursor);
    }
    final int generation = ++_generation;
    return _loadWithCache(
      selection: cursor.selectedCategoryKey,
      generation: generation,
      loadRemote: () => cursor.mergedCursors.isEmpty
          ? _loadNextSingle(cursor, generation)
          : _loadNextMerged(cursor, generation),
    );
  }

  Future<RawFavoritePage> _mergeFirstPages(RawFavoritePage discovery) async {
    final List<RawFavoriteItem> items = <RawFavoriteItem>[];
    final LinkedHashMap<String, RawFavoriteCategoryCursor> cursors =
        LinkedHashMap<String, RawFavoriteCategoryCursor>();
    for (final RawFavoriteCategory category in discovery.categories) {
      final RawFavoritePage page = discovery.selectedCategoryKey == category.key
          ? discovery
          : await _fetchPage(category.uri, expectedCategoryKey: category.key);
      items.addAll(page.items);
      cursors[category.key] = RawFavoriteCategoryCursor(
        categoryKey: category.key,
        sourceUri: page.sourceUri,
        nextPageUri: page.nextPageUri,
      );
    }
    return RawFavoritePage(
      categories: discovery.categories,
      items: _deduplicate(items),
      selectedCategoryKey: allCategoryKey,
      currentPage: 1,
      totalPages: 1,
      sourceUri: discovery.sourceUri,
      mergedCursors: Map<String, RawFavoriteCategoryCursor>.unmodifiable(
        cursors,
      ),
    );
  }

  Future<RawFavoritePage> _loadNextSingle(
    RawFavoritePage cursor,
    int generation,
  ) async {
    final Uri? nextUri = cursor.nextPageUri;
    if (nextUri == null) {
      return cursor;
    }
    final String expectedCategoryKey =
        cursor.selectedCategoryKey == allCategoryKey
        ? _allCategory(cursor.categories)?.key ?? ''
        : cursor.selectedCategoryKey;
    if (expectedCategoryKey.isEmpty) {
      throw const ForumParseException('全部收藏缺少服务端分类标识');
    }
    final RawFavoritePage next = await _fetchPage(
      nextUri,
      expectedCategoryKey: expectedCategoryKey,
    );
    _ensureCurrent(generation);
    return _replacePage(
      next,
      categories: cursor.categories,
      items: _deduplicate(<RawFavoriteItem>[...cursor.items, ...next.items]),
      selectedCategoryKey: cursor.selectedCategoryKey,
    );
  }

  Future<RawFavoritePage> _loadNextMerged(
    RawFavoritePage cursor,
    int generation,
  ) async {
    final List<RawFavoriteItem> items = <RawFavoriteItem>[...cursor.items];
    final LinkedHashMap<String, RawFavoriteCategoryCursor> cursors =
        LinkedHashMap<String, RawFavoriteCategoryCursor>.from(
          cursor.mergedCursors,
        );
    Uri sourceUri = cursor.sourceUri;
    for (final MapEntry<String, RawFavoriteCategoryCursor> entry
        in cursor.mergedCursors.entries) {
      final Uri? nextUri = entry.value.nextPageUri;
      if (nextUri == null) {
        continue;
      }
      final RawFavoritePage next = await _fetchPage(
        nextUri,
        expectedCategoryKey: entry.key,
      );
      _ensureCurrent(generation);
      sourceUri = next.sourceUri;
      items.addAll(next.items);
      cursors[entry.key] = RawFavoriteCategoryCursor(
        categoryKey: entry.key,
        sourceUri: next.sourceUri,
        nextPageUri: next.nextPageUri,
      );
    }
    return RawFavoritePage(
      categories: cursor.categories,
      items: _deduplicate(items),
      selectedCategoryKey: allCategoryKey,
      currentPage: 1,
      totalPages: 1,
      sourceUri: sourceUri,
      mergedCursors: Map<String, RawFavoriteCategoryCursor>.unmodifiable(
        cursors,
      ),
    );
  }

  Future<RawFavoritePage> _fetchPage(
    Uri uri, {
    String? expectedCategoryKey,
  }) async {
    final Response<String> response = await _client.getText(uri);
    final String html = response.data ?? '';
    if (_authParser.currentUserId(html) != _userId) {
      throw const ForumSessionExpiredException();
    }
    if (expectedCategoryKey != null &&
        response.realUri.queryParameters['type'] != expectedCategoryKey) {
      throw const ForumParseException('收藏分类跳转结果不一致');
    }
    return _parser.parse(
      html,
      response.realUri,
      expectedCategoryKey: expectedCategoryKey,
    );
  }

  Future<RawFavoritePage> _loadWithCache({
    required String selection,
    required int generation,
    required Future<RawFavoritePage> Function() loadRemote,
  }) async {
    final String key = _cacheKey(selection);
    try {
      late RawFavoritePage page;
      await _client.withActiveAccount<void>(_userId, () async {
        page = await loadRemote();
        _ensureCurrent(generation);
        try {
          await _localRepository.saveCache(
            userId: _userId,
            key: key,
            payload: _cacheCodec.encode(page, userId: _userId),
          );
        } on RawFavoriteRequestSupersededException {
          rethrow;
        } on ForumSessionExpiredException {
          rethrow;
        } on Object {
          // 本地缓存失败不能覆盖服务端成功结果。
        }
      });
      return page;
    } on ForumConnectionException catch (error, stackTrace) {
      _ensureCurrent(generation);
      try {
        final ForumCacheSnapshot? snapshot = await _client.withActiveAccount(
          _userId,
          () => _localRepository.loadCache(userId: _userId, key: key),
        );
        if (snapshot != null) {
          _ensureCurrent(generation);
          return _cacheCodec.decode(
            snapshot.payload,
            userId: _userId,
            updatedAt: snapshot.updatedAt,
          );
        }
      } on RawFavoriteRequestSupersededException {
        rethrow;
      } on ForumSessionExpiredException {
        rethrow;
      } on Object {
        // 损坏或不兼容缓存按不存在处理，保留原连接错误。
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  RawFavoriteCategory? _allCategory(List<RawFavoriteCategory> categories) {
    for (final RawFavoriteCategory category in categories) {
      if (category.label == '全部') {
        return category;
      }
    }
    return null;
  }

  RawFavoriteCategory? _categoryByKey(
    List<RawFavoriteCategory> categories,
    String key,
  ) {
    for (final RawFavoriteCategory category in categories) {
      if (category.key == key) {
        return category;
      }
    }
    return null;
  }

  RawFavoritePage _replacePage(
    RawFavoritePage page, {
    required List<RawFavoriteCategory> categories,
    required String selectedCategoryKey,
    List<RawFavoriteItem>? items,
  }) {
    return RawFavoritePage(
      categories: List<RawFavoriteCategory>.unmodifiable(categories),
      items: List<RawFavoriteItem>.unmodifiable(items ?? page.items),
      selectedCategoryKey: selectedCategoryKey,
      currentPage: page.currentPage,
      totalPages: page.totalPages,
      sourceUri: page.sourceUri,
      previousPageUri: page.previousPageUri,
      nextPageUri: page.nextPageUri,
      mergedCursors: page.mergedCursors,
    );
  }

  List<RawFavoriteItem> _deduplicate(List<RawFavoriteItem> items) {
    final LinkedHashMap<String, RawFavoriteItem> result =
        LinkedHashMap<String, RawFavoriteItem>();
    for (final RawFavoriteItem item in items) {
      result.putIfAbsent(item.identityKey, () => item);
    }
    return List<RawFavoriteItem>.unmodifiable(result.values);
  }

  String _cacheKey(String selection) {
    return 'favorites:v2:raw:${Uri.encodeComponent(selection)}';
  }

  void _ensureCurrent(int generation) {
    if (generation != _generation) {
      throw const RawFavoriteRequestSupersededException();
    }
  }

  void _checkUserId() {
    if (_userId <= 0) {
      throw const ForumSessionExpiredException();
    }
  }
}

class RawFavoriteRequestSupersededException extends ForumException {
  const RawFavoriteRequestSupersededException() : super('收藏请求已被更新操作替代');
}

class _RawFavoriteCacheCodec {
  const _RawFavoriteCacheCodec();

  Map<String, dynamic> encode(RawFavoritePage page, {required int userId}) {
    return <String, dynamic>{
      'schema': 1,
      'userId': userId,
      'categories': page.categories
          .map(_encodeCategory)
          .toList(growable: false),
      'items': page.items.map(_encodeItem).toList(growable: false),
      'selectedCategoryKey': page.selectedCategoryKey,
      'currentPage': page.currentPage,
      'totalPages': page.totalPages,
      'sourceUri': _sanitizeUri(page.sourceUri).toString(),
      'previousPageUri': _encodeUri(page.previousPageUri),
      'nextPageUri': _encodeUri(page.nextPageUri),
      'mergedCursors': page.mergedCursors.values
          .map(_encodeCursor)
          .toList(growable: false),
    };
  }

  RawFavoritePage decode(
    Map<String, dynamic> value, {
    required int userId,
    required DateTime updatedAt,
  }) {
    if (_integer(value['schema']) != 1 || _integer(value['userId']) != userId) {
      throw const ForumParseException('收藏缓存版本或账号不一致');
    }
    final List<RawFavoriteCategory> categories = _mapList(
      value['categories'],
      _decodeCategory,
    );
    if (categories.isEmpty) {
      throw const ForumParseException('收藏缓存缺少分类');
    }
    final List<RawFavoriteCategoryCursor> cursors = _mapList(
      value['mergedCursors'],
      _decodeCursor,
    );
    return RawFavoritePage(
      categories: List<RawFavoriteCategory>.unmodifiable(categories),
      items: List<RawFavoriteItem>.unmodifiable(
        _mapList(value['items'], _decodeItem),
      ),
      selectedCategoryKey: value['selectedCategoryKey']?.toString() ?? '',
      currentPage: _positiveInteger(value['currentPage']),
      totalPages: _positiveInteger(value['totalPages']),
      sourceUri: _requiredUri(value['sourceUri']),
      previousPageUri: _optionalUri(value['previousPageUri']),
      nextPageUri: _optionalUri(value['nextPageUri']),
      mergedCursors: Map<String, RawFavoriteCategoryCursor>.unmodifiable(
        <String, RawFavoriteCategoryCursor>{
          for (final RawFavoriteCategoryCursor cursor in cursors)
            cursor.categoryKey: cursor,
        },
      ),
      isFromCache: true,
      cacheUpdatedAt: updatedAt,
    );
  }

  Map<String, dynamic> _encodeCategory(RawFavoriteCategory value) {
    return <String, dynamic>{
      'key': value.key,
      'label': value.label,
      'uri': _sanitizeUri(value.uri).toString(),
      'selected': value.selected,
    };
  }

  RawFavoriteCategory _decodeCategory(Map<String, dynamic> value) {
    return RawFavoriteCategory(
      key: value['key']?.toString() ?? '',
      label: value['label']?.toString() ?? '',
      uri: _requiredUri(value['uri']),
      selected: value['selected'] == true,
    );
  }

  Map<String, dynamic> _encodeItem(RawFavoriteItem value) {
    return <String, dynamic>{
      'favoriteId': value.favoriteId,
      'categoryKey': value.categoryKey,
      'title': value.title,
      'description': value.description,
      'targetUri': _encodeUri(value.targetUri),
      'targetKind': value.targetKind.name,
      'threadId': value.threadId,
      'boardId': value.boardId,
      'userId': value.userId,
      'groupId': value.groupId,
      'contentId': value.contentId,
    };
  }

  RawFavoriteItem _decodeItem(Map<String, dynamic> value) {
    final String targetName = value['targetKind']?.toString() ?? '';
    RawFavoriteTargetKind targetKind = RawFavoriteTargetKind.unknown;
    for (final RawFavoriteTargetKind candidate
        in RawFavoriteTargetKind.values) {
      if (candidate.name == targetName) {
        targetKind = candidate;
        break;
      }
    }
    return RawFavoriteItem(
      favoriteId: _optionalInteger(value['favoriteId']),
      categoryKey: value['categoryKey']?.toString() ?? '',
      title: value['title']?.toString() ?? '',
      description: value['description']?.toString() ?? '',
      targetUri: _optionalUri(value['targetUri']),
      deleteDialogUri: null,
      targetKind: targetKind,
      threadId: _optionalInteger(value['threadId']),
      boardId: _optionalInteger(value['boardId']),
      userId: _optionalInteger(value['userId']),
      groupId: _optionalInteger(value['groupId']),
      contentId: _optionalInteger(value['contentId']),
    );
  }

  Map<String, dynamic> _encodeCursor(RawFavoriteCategoryCursor value) {
    return <String, dynamic>{
      'categoryKey': value.categoryKey,
      'sourceUri': _sanitizeUri(value.sourceUri).toString(),
      'nextPageUri': _encodeUri(value.nextPageUri),
    };
  }

  RawFavoriteCategoryCursor _decodeCursor(Map<String, dynamic> value) {
    return RawFavoriteCategoryCursor(
      categoryKey: value['categoryKey']?.toString() ?? '',
      sourceUri: _requiredUri(value['sourceUri']),
      nextPageUri: _optionalUri(value['nextPageUri']),
    );
  }

  List<T> _mapList<T>(
    Object? value,
    T Function(Map<String, dynamic> value) decode,
  ) {
    if (value is! List<dynamic>) {
      return <T>[];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(decode)
        .toList(growable: false);
  }

  String? _encodeUri(Uri? uri) {
    return uri == null ? null : _sanitizeUri(uri).toString();
  }

  Uri _sanitizeUri(Uri uri) {
    return uri.replace(
      queryParameters: <String, String>{
        for (final MapEntry<String, String> entry
            in uri.queryParameters.entries)
          if (entry.key.toLowerCase() != 'formhash') entry.key: entry.value,
      },
    );
  }

  Uri _requiredUri(Object? value) {
    final Uri? uri = _optionalUri(value);
    if (uri == null) {
      throw const ForumParseException('收藏缓存 URI 无效');
    }
    return uri;
  }

  Uri? _optionalUri(Object? value) {
    final String text = value?.toString() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const ForumParseException('收藏缓存 URI 无效');
    }
    return uri;
  }

  int _positiveInteger(Object? value) {
    final int result = _integer(value);
    if (result <= 0) {
      throw const ForumParseException('收藏缓存页码无效');
    }
    return result;
  }

  int _integer(Object? value) {
    return value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _optionalInteger(Object? value) {
    final int result = _integer(value);
    return result > 0 ? result : null;
  }
}
