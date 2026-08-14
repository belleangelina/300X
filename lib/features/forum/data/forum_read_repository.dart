import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/forum/data/forum_announcement_parser.dart';
import 'package:x300/features/forum/data/forum_board_parser.dart';
import 'package:x300/features/forum/data/forum_cache_codec.dart';
import 'package:x300/features/forum/data/forum_index_parser.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_topic_parser.dart';
import 'package:x300/features/forum/domain/forum_announcement_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

final Provider<ForumReadRepository> forumReadRepositoryProvider =
    Provider<ForumReadRepository>(
      (Ref ref) => ForumReadRepository(
        ref.watch(forumClientProvider),
        ref.watch(forumLocalRepositoryProvider),
        ref.watch(authControllerProvider).value?.userId ?? 0,
      ),
    );

class ForumReadRepository {
  ForumReadRepository(
    this._client,
    this._localRepository,
    this._userId, [
    this._indexParser = const ForumIndexParser(),
    this._boardParser = const ForumBoardParser(),
    this._topicParser = const ForumTopicParser(),
    this._cacheCodec = const ForumCacheCodec(),
    this._originPolicy = const ForumOriginPolicy(),
    this._authParser = const AuthPageParser(),
    this._announcementParser = const ForumAnnouncementParser(),
  ]);

  static final Uri indexUri = ForumClient.baseUri.resolve('forum.php?mobile=2');
  static final Uri apiIndexUri = ForumClient.baseUri.resolve(
    'api/mobile/index.php?version=4&module=forumindex',
  );

  final ForumClient _client;
  final ForumLocalRepository _localRepository;
  final int _userId;
  final ForumIndexParser _indexParser;
  final ForumBoardParser _boardParser;
  final ForumTopicParser _topicParser;
  final ForumCacheCodec _cacheCodec;
  final ForumOriginPolicy _originPolicy;
  final AuthPageParser _authParser;
  final ForumAnnouncementParser _announcementParser;

  int _indexGeneration = 0;
  final Map<int, int> _boardGenerations = <int, int>{};
  final Map<int, int> _threadGenerations = <int, int>{};
  final Map<int, int> _announcementGenerations = <int, int>{};

  Future<ForumBoardIndex> loadIndex() {
    _checkUserId();
    final int generation = ++_indexGeneration;
    return _loadWithCache<ForumBoardIndex>(
      key: 'forum:v2:index',
      loadRemote: _fetchIndex,
      encode: _cacheCodec.encodeIndex,
      decode: (Map<String, dynamic> value) {
        final ForumBoardIndex result = _cacheCodec.decodeIndex(value);
        if (result.viewer.userId != _userId) {
          throw const ForumParseException('论坛缓存账号不一致');
        }
        return result;
      },
      markCached: (ForumBoardIndex value, DateTime updatedAt) =>
          ForumBoardIndex(
            sections: value.sections,
            unsectionedBoards: value.unsectionedBoards,
            viewer: value.viewer,
            navigation: value.navigation,
            sourceUri: value.sourceUri,
            isFromCache: true,
            cacheUpdatedAt: updatedAt,
          ),
      isCurrent: () => generation == _indexGeneration,
    );
  }

  Future<ForumBoardPage> loadBoard(Uri uri, {required int expectedBoardId}) {
    _checkUserId();
    if (expectedBoardId <= 0) {
      throw ArgumentError.value(expectedBoardId, 'expectedBoardId');
    }
    _originPolicy.requireMobilePage(uri);
    final int generation = (_boardGenerations[expectedBoardId] ?? 0) + 1;
    _boardGenerations[expectedBoardId] = generation;
    final String key = _cacheKey('board:$expectedBoardId', uri);
    return _loadWithCache<ForumBoardPage>(
      key: key,
      loadRemote: () => _fetchBoard(uri, expectedBoardId: expectedBoardId),
      encode: _cacheCodec.encodeBoardPage,
      decode: (Map<String, dynamic> value) {
        final ForumBoardPage result = _cacheCodec.decodeBoardPage(value);
        if (result.board.id != expectedBoardId) {
          throw const ForumParseException('版块缓存 fid 不一致');
        }
        return result;
      },
      markCached: (ForumBoardPage value, DateTime updatedAt) => ForumBoardPage(
        board: value.board,
        threads: value.threads,
        filters: value.filters,
        cursor: value.cursor,
        isFromCache: true,
        cacheUpdatedAt: updatedAt,
      ),
      isCurrent: () => _boardGenerations[expectedBoardId] == generation,
    );
  }

  Future<ForumBoardPage> loadNextBoard(ForumBoardPage cursor) {
    final Uri? uri = cursor.cursor.nextPageUri;
    if (uri == null) {
      return Future<ForumBoardPage>.value(cursor);
    }
    return loadBoard(uri, expectedBoardId: cursor.board.id);
  }

  Future<ForumThreadPage> loadThread(
    Uri uri, {
    required int expectedThreadId,
    int? expectedBoardId,
    int? focusedPostId,
  }) {
    _checkUserId();
    if (expectedThreadId <= 0) {
      throw ArgumentError.value(expectedThreadId, 'expectedThreadId');
    }
    _originPolicy.requireMobilePage(uri);
    final int generation = (_threadGenerations[expectedThreadId] ?? 0) + 1;
    _threadGenerations[expectedThreadId] = generation;
    final String key = _cacheKey(
      focusedPostId == null
          ? 'thread:$expectedThreadId'
          : 'thread:$expectedThreadId:post:$focusedPostId',
      uri,
    );
    return _loadWithCache<ForumThreadPage>(
      key: key,
      loadRemote: () => _fetchThread(
        uri,
        expectedThreadId: expectedThreadId,
        expectedBoardId: expectedBoardId,
        focusedPostId: focusedPostId,
      ),
      encode: _cacheCodec.encodeThreadPage,
      decode: (Map<String, dynamic> value) {
        final ForumThreadPage result = _cacheCodec.decodeThreadPage(value);
        if (result.thread.id != expectedThreadId ||
            (focusedPostId != null && result.postById(focusedPostId) == null)) {
          throw const ForumParseException('主题缓存标识不一致');
        }
        return result;
      },
      markCached: (ForumThreadPage value, DateTime updatedAt) =>
          ForumThreadPage(
            thread: value.thread,
            posts: value.posts,
            readingOptions: value.readingOptions,
            cursor: value.cursor,
            focusedPostId: value.focusedPostId,
            isFromCache: true,
            cacheUpdatedAt: updatedAt,
          ),
      isCurrent: () => _threadGenerations[expectedThreadId] == generation,
    );
  }

  Future<ForumThreadPage> loadNextThread(ForumThreadPage cursor) {
    final Uri? uri = cursor.cursor.nextPageUri;
    if (uri == null) {
      return Future<ForumThreadPage>.value(cursor);
    }
    return loadThread(
      uri,
      expectedThreadId: cursor.thread.id,
      expectedBoardId: cursor.thread.boardId,
    );
  }

  Future<ForumThreadPage> loadThreadAtPost({
    required int threadId,
    required int postId,
  }) async {
    _checkUserId();
    if (threadId <= 0 || postId <= 0) {
      throw ArgumentError('tid 和 pid 必须为正数');
    }
    final Uri uri = ForumClient.baseUri.resolve(
      'forum.php?mod=redirect&goto=findpost&ptid=$threadId&'
      'pid=$postId&mobile=2',
    );
    final String key = _cacheKey('thread:$threadId:post:$postId', uri);
    final int generation = (_threadGenerations[threadId] ?? 0) + 1;
    _threadGenerations[threadId] = generation;
    return _loadWithCache<ForumThreadPage>(
      key: key,
      loadRemote: () async {
        final Response<String> response = await _client.getText(uri);
        final String html = response.data ?? '';
        _validateIdentity(html);
        if (response.realUri.queryParameters['mod'] != 'viewthread' ||
            response.realUri.queryParameters['mobile'] != '2') {
          throw const ForumParseException('无法定位移动论坛楼层');
        }
        return _topicParser.parse(
          html,
          response.realUri,
          expectedThreadId: threadId,
          focusedPostId: postId,
        );
      },
      encode: _cacheCodec.encodeThreadPage,
      decode: (Map<String, dynamic> value) {
        final ForumThreadPage result = _cacheCodec.decodeThreadPage(value);
        if (result.thread.id != threadId || result.postById(postId) == null) {
          throw const ForumParseException('主题缓存标识不一致');
        }
        return result;
      },
      markCached: (ForumThreadPage value, DateTime updatedAt) =>
          ForumThreadPage(
            thread: value.thread,
            posts: value.posts,
            readingOptions: value.readingOptions,
            cursor: value.cursor,
            focusedPostId: postId,
            isFromCache: true,
            cacheUpdatedAt: updatedAt,
          ),
      isCurrent: () => _threadGenerations[threadId] == generation,
    );
  }

  Future<ForumAnnouncement> loadAnnouncement(
    Uri uri, {
    required int expectedAnnouncementId,
  }) {
    _checkUserId();
    _announcementParser.requireAnnouncementUri(
      uri,
      expectedAnnouncementId: expectedAnnouncementId,
    );
    final int generation =
        (_announcementGenerations[expectedAnnouncementId] ?? 0) + 1;
    _announcementGenerations[expectedAnnouncementId] = generation;
    final String key = _cacheKey('announcement:$expectedAnnouncementId', uri);
    return _loadWithCache<ForumAnnouncement>(
      key: key,
      loadRemote: () => _fetchAnnouncement(
        uri,
        expectedAnnouncementId: expectedAnnouncementId,
      ),
      encode: _cacheCodec.encodeAnnouncement,
      decode: (Map<String, dynamic> value) {
        final ForumAnnouncement result = _cacheCodec.decodeAnnouncement(value);
        if (result.id != expectedAnnouncementId || result.title.isEmpty) {
          throw const ForumParseException('公告缓存标识不一致');
        }
        _announcementParser.requireAnnouncementUri(
          result.sourceUri,
          expectedAnnouncementId: expectedAnnouncementId,
        );
        return result;
      },
      markCached: (ForumAnnouncement value, DateTime updatedAt) =>
          ForumAnnouncement(
            id: value.id,
            title: value.title,
            metadataLabel: value.metadataLabel,
            contentBlocks: value.contentBlocks,
            messageHtml: value.messageHtml,
            sourceUri: value.sourceUri,
            isFromCache: true,
            cacheUpdatedAt: updatedAt,
          ),
      isCurrent: () =>
          _announcementGenerations[expectedAnnouncementId] == generation,
    );
  }

  Future<ForumBoardIndex> _fetchIndex() async {
    final Response<String> mobileResponse = await _client.getText(indexUri);
    String apiJson = '{}';
    Uri responseApiUri = apiIndexUri;
    try {
      final Response<String> apiResponse = await _client.getText(apiIndexUri);
      apiJson = apiResponse.data ?? '';
      responseApiUri = apiResponse.realUri;
    } on ForumConnectionException {
      // 移动 HTML 是首页语义权威；API 不可用时保留可见入口。
    }
    return _indexParser.parse(
      mobileHtml: mobileResponse.data ?? '',
      mobileUri: mobileResponse.realUri,
      apiJson: apiJson,
      apiUri: responseApiUri,
      expectedUserId: _userId,
    );
  }

  Future<ForumBoardPage> _fetchBoard(
    Uri uri, {
    required int expectedBoardId,
  }) async {
    final Response<String> response = await _client.getText(uri);
    final String html = response.data ?? '';
    _validateIdentity(html);
    return _boardParser.parse(
      html,
      response.realUri,
      expectedBoardId: expectedBoardId,
    );
  }

  Future<ForumThreadPage> _fetchThread(
    Uri uri, {
    required int expectedThreadId,
    int? expectedBoardId,
    int? focusedPostId,
  }) async {
    final Response<String> response = await _client.getText(uri);
    final String html = response.data ?? '';
    _validateIdentity(html);
    return _topicParser.parse(
      html,
      response.realUri,
      expectedThreadId: expectedThreadId,
      expectedBoardId: expectedBoardId,
      focusedPostId: focusedPostId,
    );
  }

  Future<ForumAnnouncement> _fetchAnnouncement(
    Uri uri, {
    required int expectedAnnouncementId,
  }) async {
    final Response<String> response = await _client.getText(uri);
    final String html = response.data ?? '';
    _validateIdentity(html);
    return _announcementParser.parse(
      html,
      response.realUri,
      expectedAnnouncementId: expectedAnnouncementId,
    );
  }

  Future<T> _loadWithCache<T>({
    required String key,
    required Future<T> Function() loadRemote,
    required Map<String, dynamic> Function(T value) encode,
    required T Function(Map<String, dynamic> value) decode,
    required T Function(T value, DateTime updatedAt) markCached,
    required bool Function() isCurrent,
  }) async {
    try {
      late T value;
      await _client.withActiveAccount<void>(_userId, () async {
        value = await loadRemote();
        if (!isCurrent()) {
          throw const ForumRequestSupersededException();
        }
        try {
          final bool saved = await _localRepository.saveCacheIfCurrent(
            userId: _userId,
            key: key,
            payload: encode(value),
            isCurrent: isCurrent,
          );
          if (!saved) {
            throw const ForumRequestSupersededException();
          }
        } on ForumRequestSupersededException {
          rethrow;
        } on ForumSessionExpiredException {
          rethrow;
        } on Object {
          // 本地缓存失败不得覆盖已成功取得的服务端结果。
        }
        if (!isCurrent()) {
          throw const ForumRequestSupersededException();
        }
      });
      return value;
    } on ForumConnectionException catch (error, stackTrace) {
      try {
        final ForumCacheSnapshot? snapshot = await _client.withActiveAccount(
          _userId,
          () => _localRepository.loadCache(userId: _userId, key: key),
        );
        if (snapshot != null) {
          if (!isCurrent()) {
            throw const ForumRequestSupersededException();
          }
          return markCached(decode(snapshot.payload), snapshot.updatedAt);
        }
      } on ForumRequestSupersededException {
        rethrow;
      } on ForumSessionExpiredException {
        rethrow;
      } on Object {
        // 损坏或不兼容缓存按不存在处理，并保留原连接错误。
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _validateIdentity(String html) {
    if (_authParser.currentUserId(html) != _userId) {
      throw const ForumSessionExpiredException();
    }
  }

  String _cacheKey(String kind, Uri uri) {
    final Uri normalized = uri.replace(fragment: '');
    final String digest = sha256
        .convert(utf8.encode(normalized.toString()))
        .toString();
    return 'forum:v2:$kind:$digest';
  }

  void _checkUserId() {
    if (_userId <= 0) {
      throw const ForumSessionExpiredException();
    }
  }
}

class ForumRequestSupersededException extends ForumException {
  const ForumRequestSupersededException() : super('论坛请求已被更新操作替代');
}
