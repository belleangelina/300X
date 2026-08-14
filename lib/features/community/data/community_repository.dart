import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/community/data/community_cache_codec.dart';
import 'package:x300/features/community/data/community_parser.dart';
import 'package:x300/features/community/domain/community_models.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';

final Provider<CommunityRepository> communityRepositoryProvider =
    Provider<CommunityRepository>(
      (Ref ref) => CommunityRepository(
        ref.watch(forumClientProvider),
        ref.watch(forumLocalRepositoryProvider),
        ref.watch(authControllerProvider).value?.userId ?? 0,
      ),
    );

class CommunityRepository {
  CommunityRepository(
    this._client,
    this._localRepository,
    this._userId, [
    this._parser = const CommunityParser(),
    this._cacheCodec = const CommunityCacheCodec(),
    this._originPolicy = const ForumOriginPolicy(),
  ]);

  final ForumClient _client;
  final ForumLocalRepository _localRepository;
  final int _userId;
  final CommunityParser _parser;
  final CommunityCacheCodec _cacheCodec;
  final ForumOriginPolicy _originPolicy;
  final Map<String, int> _generations = <String, int>{};

  Future<CommunityNoticePage> loadNotices(Uri uri) {
    _requireSpaceRoute(uri, doValue: 'notice');
    return _load<CommunityNoticePage>(
      uri: uri,
      generationScope: 'notices',
      cacheKind: 'notices',
      parse: (String html, Uri realUri) =>
          _parser.parseNotices(html, realUri, expectedViewerUserId: _userId),
      encode: _cacheCodec.encodeNotices,
      decode: _cacheCodec.decodeNotices,
      validateCache: (CommunityNoticePage value) =>
          _requireSameSource(value.cursor.sourceUri, uri),
      markCached: (CommunityNoticePage value, DateTime updatedAt) =>
          CommunityNoticePage(
            items: value.items,
            categories: value.categories,
            cursor: value.cursor,
            navigation: value.navigation,
            readEffect: value.readEffect,
            isFromCache: true,
            cacheUpdatedAt: updatedAt,
          ),
    );
  }

  Future<CommunityPmListPage> loadPmList(Uri uri) {
    _requirePmListRoute(uri);
    return _load<CommunityPmListPage>(
      uri: uri,
      generationScope: 'pm-list',
      cacheKind: 'pm-list',
      parse: (String html, Uri realUri) =>
          _parser.parsePmList(html, realUri, expectedViewerUserId: _userId),
      encode: _cacheCodec.encodePmList,
      decode: _cacheCodec.decodePmList,
      validateCache: (CommunityPmListPage value) {
        _requireSameSource(value.cursor.sourceUri, uri);
        for (final CommunityPmConversation item in value.items) {
          _requirePmThreadRoute(item.uri, item.peerUserId);
        }
      },
      markCached: (CommunityPmListPage value, DateTime updatedAt) =>
          CommunityPmListPage(
            items: value.items,
            cursor: value.cursor,
            navigation: value.navigation,
            isFromCache: true,
            cacheUpdatedAt: updatedAt,
          ),
    );
  }

  Future<CommunityPmThreadPage> loadPmThread(
    Uri uri, {
    required int expectedPeerUserId,
  }) async {
    _requirePmThreadRoute(uri, expectedPeerUserId);
    _checkUserId();
    final String generationScope = 'pm-thread:$expectedPeerUserId';
    final int generation = (_generations[generationScope] ?? 0) + 1;
    _generations[generationScope] = generation;
    late CommunityPmThreadPage result;
    await _client.withActiveAccount<void>(_userId, () async {
      final Response<String> response = await _client.getText(uri);
      result = _parser.parsePmThread(
        response.data ?? '',
        response.realUri,
        expectedViewerUserId: _userId,
        expectedPeerUserId: expectedPeerUserId,
      );
      if (_generations[generationScope] != generation) {
        throw const CommunityRequestSupersededException();
      }
    });
    return result;
  }

  Future<CommunityProfile> loadProfile(
    Uri uri, {
    required int expectedProfileUserId,
  }) {
    _requireProfileRoute(uri, expectedProfileUserId);
    return _load<CommunityProfile>(
      uri: uri,
      generationScope: 'profile:$expectedProfileUserId',
      cacheKind: 'profile:$expectedProfileUserId',
      parse: (String html, Uri realUri) => _parser.parseProfile(
        html,
        realUri,
        expectedViewerUserId: _userId,
        expectedProfileUserId: expectedProfileUserId,
      ),
      encode: _cacheCodec.encodeProfile,
      decode: _cacheCodec.decodeProfile,
      validateCache: (CommunityProfile value) {
        _requireSameSource(value.sourceUri, uri);
        if (value.userId != expectedProfileUserId) {
          throw const ForumParseException('个人空间缓存 uid 不一致');
        }
      },
      markCached: (CommunityProfile value, DateTime updatedAt) =>
          CommunityProfile(
            userId: value.userId,
            username: value.username,
            avatarUri: value.avatarUri,
            sourceUri: value.sourceUri,
            entries: value.entries,
            details: value.details,
            isFromCache: true,
            cacheUpdatedAt: updatedAt,
          ),
    );
  }

  Future<CommunityActivityPage> loadActivity(
    Uri uri, {
    required int expectedProfileUserId,
    required CommunityActivityKind expectedKind,
  }) {
    _requireActivityRoute(uri, expectedProfileUserId, expectedKind);
    return _load<CommunityActivityPage>(
      uri: uri,
      generationScope: 'activity:$expectedProfileUserId:${expectedKind.name}',
      cacheKind: 'activity:$expectedProfileUserId:${expectedKind.name}',
      parse: (String html, Uri realUri) => _parser.parseActivity(
        html,
        realUri,
        expectedViewerUserId: _userId,
        expectedProfileUserId: expectedProfileUserId,
        expectedKind: expectedKind,
      ),
      encode: _cacheCodec.encodeActivity,
      decode: _cacheCodec.decodeActivity,
      validateCache: (CommunityActivityPage value) {
        _requireSameSource(value.cursor.sourceUri, uri);
        if (value.profileUserId != expectedProfileUserId ||
            value.kind != expectedKind) {
          throw const ForumParseException('主题或回复缓存目标不一致');
        }
        for (final CommunityActivityItem item in value.items) {
          _requireTopicTarget(item.target);
        }
      },
      markCached: (CommunityActivityPage value, DateTime updatedAt) =>
          CommunityActivityPage(
            kind: value.kind,
            profileUserId: value.profileUserId,
            items: value.items,
            cursor: value.cursor,
            tabs: value.tabs,
            isFromCache: true,
            cacheUpdatedAt: updatedAt,
          ),
    );
  }

  Future<CommunityPeoplePage> loadPeople(
    Uri uri, {
    required CommunityPeopleKind expectedKind,
  }) {
    _requirePeopleRoute(uri, expectedKind);
    return _load<CommunityPeoplePage>(
      uri: uri,
      generationScope: 'people:${expectedKind.name}',
      cacheKind: 'people:${expectedKind.name}',
      parse: (String html, Uri realUri) => _parser.parsePeople(
        html,
        realUri,
        expectedViewerUserId: _userId,
        expectedKind: expectedKind,
      ),
      encode: _cacheCodec.encodePeople,
      decode: _cacheCodec.decodePeople,
      validateCache: (CommunityPeoplePage value) {
        _requireSameSource(value.cursor.sourceUri, uri);
        if (value.kind != expectedKind) {
          throw const ForumParseException('好友或访客缓存分类不一致');
        }
        for (final CommunityPerson item in value.people) {
          _requireProfileRoute(item.profile.uri, item.profile.userId);
        }
      },
      markCached: (CommunityPeoplePage value, DateTime updatedAt) =>
          CommunityPeoplePage(
            kind: value.kind,
            people: value.people,
            tabs: value.tabs,
            cursor: value.cursor,
            isFromCache: true,
            cacheUpdatedAt: updatedAt,
          ),
    );
  }

  Future<T> _load<T>({
    required Uri uri,
    required String generationScope,
    required String cacheKind,
    required T Function(String html, Uri realUri) parse,
    required Map<String, dynamic> Function(T value) encode,
    required T Function(Map<String, dynamic> value) decode,
    required void Function(T value) validateCache,
    required T Function(T value, DateTime updatedAt) markCached,
  }) async {
    _checkUserId();
    final int generation = (_generations[generationScope] ?? 0) + 1;
    _generations[generationScope] = generation;
    bool isCurrent() => _generations[generationScope] == generation;
    final String cacheKey = _cacheKey(cacheKind, uri);
    try {
      late T result;
      await _client.withActiveAccount<void>(_userId, () async {
        final Response<String> response = await _client.getText(uri);
        result = parse(response.data ?? '', response.realUri);
        if (!isCurrent()) {
          throw const CommunityRequestSupersededException();
        }
        try {
          final bool saved = await _localRepository.saveCacheIfCurrent(
            userId: _userId,
            key: cacheKey,
            payload: encode(result),
            isCurrent: isCurrent,
          );
          if (!saved) {
            throw const CommunityRequestSupersededException();
          }
        } on CommunityRequestSupersededException {
          rethrow;
        } on ForumSessionExpiredException {
          rethrow;
        } on Object {
          // 缓存失败不能覆盖服务端读取结果。
        }
        if (!isCurrent()) {
          throw const CommunityRequestSupersededException();
        }
      });
      return result;
    } on ForumConnectionException catch (error, stackTrace) {
      try {
        final ForumCacheSnapshot? snapshot = await _client
            .withActiveAccount<ForumCacheSnapshot?>(
              _userId,
              () => _localRepository.loadCache(userId: _userId, key: cacheKey),
            );
        if (snapshot != null) {
          if (!isCurrent()) {
            throw const CommunityRequestSupersededException();
          }
          final T value = decode(snapshot.payload);
          validateCache(value);
          return markCached(value, snapshot.updatedAt);
        }
      } on CommunityRequestSupersededException {
        rethrow;
      } on ForumSessionExpiredException {
        rethrow;
      } on Object {
        // 损坏或不兼容缓存按不存在处理。
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _requireSameSource(Uri cached, Uri requested) {
    if (cached.replace(fragment: '') != requested.replace(fragment: '')) {
      throw const ForumParseException('社区缓存来源地址不一致');
    }
  }

  void _requireSpaceRoute(Uri uri, {required String doValue}) {
    _originPolicy.requireMobilePage(uri);
    if (uri.path != '/home.php' ||
        uri.fragment.isNotEmpty ||
        _single(uri, 'mod') != 'space' ||
        _single(uri, 'do') != doValue) {
      throw const ForumParseException('社区读取地址无效');
    }
  }

  void _requirePmListRoute(Uri uri) {
    _requireSpaceRoute(uri, doValue: 'pm');
    if (_single(uri, 'subop') != null) {
      throw const ForumParseException('私信列表地址无效');
    }
  }

  void _requirePmThreadRoute(Uri uri, int expectedPeerUserId) {
    _requireSpaceRoute(uri, doValue: 'pm');
    if (_single(uri, 'subop') != 'view' ||
        _positive(_single(uri, 'touid')) != expectedPeerUserId ||
        expectedPeerUserId <= 0) {
      throw const ForumParseException('私信会话地址与对方不一致');
    }
  }

  void _requireProfileRoute(Uri uri, int expectedProfileUserId) {
    _originPolicy.requireMobilePage(uri);
    final String? doValue = _single(uri, 'do');
    if (uri.path != '/home.php' ||
        uri.fragment.isNotEmpty ||
        _single(uri, 'mod') != 'space' ||
        (doValue != null && doValue != 'profile') ||
        _positive(_single(uri, 'uid')) != expectedProfileUserId ||
        expectedProfileUserId <= 0) {
      throw const ForumParseException('个人空间地址与 uid 不一致');
    }
  }

  void _requireActivityRoute(
    Uri uri,
    int expectedProfileUserId,
    CommunityActivityKind expectedKind,
  ) {
    _requireSpaceRoute(uri, doValue: 'thread');
    final String? type = _single(uri, 'type');
    final bool kindMatched = expectedKind == CommunityActivityKind.replies
        ? type == 'reply'
        : type == null || type.isEmpty;
    if (_single(uri, 'view') != 'me' ||
        _positive(_single(uri, 'uid')) != expectedProfileUserId ||
        !kindMatched) {
      throw const ForumParseException('主题或回复地址与目标不一致');
    }
  }

  void _requirePeopleRoute(Uri uri, CommunityPeopleKind expectedKind) {
    _requireSpaceRoute(uri, doValue: 'friend');
    final int targetUserId = _positive(_single(uri, 'uid'));
    if (targetUserId > 0 && targetUserId != _userId) {
      throw const ForumParseException('好友或访客地址 uid 不一致');
    }
    final bool matched = switch (expectedKind) {
      CommunityPeopleKind.friends =>
        _single(uri, 'view') == null && _single(uri, 'type') == null,
      CommunityPeopleKind.online =>
        _single(uri, 'view') == 'online' && _single(uri, 'type') == 'member',
      CommunityPeopleKind.visitors => _single(uri, 'view') == 'visitor',
      CommunityPeopleKind.visited => _single(uri, 'view') == 'trace',
    };
    if (!matched) {
      throw const ForumParseException('好友或访客地址分类不一致');
    }
  }

  void _requireTopicTarget(CommunityTopicTarget target) {
    _originPolicy.requireMobilePage(target.uri);
    final String? mod = _single(target.uri, 'mod');
    final int threadId = mod == 'redirect'
        ? _positive(_single(target.uri, 'ptid'))
        : _positive(_single(target.uri, 'tid'));
    final int postId = _positive(_single(target.uri, 'pid'));
    if (target.uri.path != '/forum.php' ||
        threadId != target.threadId ||
        (mod == 'redirect' &&
            (_single(target.uri, 'goto') != 'findpost' ||
                postId != target.postId)) ||
        (mod != 'redirect' && mod != 'viewthread')) {
      throw const ForumParseException('社区缓存主题目标无效');
    }
  }

  String _cacheKey(String kind, Uri uri) {
    final String digest = sha256
        .convert(utf8.encode(uri.replace(fragment: '').toString()))
        .toString();
    return 'forum:v2:community:$kind:$digest';
  }

  String? _single(Uri uri, String name) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single : null;
  }

  int _positive(String? value) {
    final int result = int.tryParse(value ?? '') ?? 0;
    return result > 0 ? result : 0;
  }

  void _checkUserId() {
    if (_userId <= 0) {
      throw const ForumSessionExpiredException();
    }
  }
}

class CommunityRequestSupersededException extends ForumException {
  const CommunityRequestSupersededException() : super('社区请求已被更新操作替代');
}
