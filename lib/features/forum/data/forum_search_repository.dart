import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_search_parser.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/forum/domain/forum_search_models.dart';

final Provider<ForumThreadSearchRepository>
forumThreadSearchRepositoryProvider = Provider<ForumThreadSearchRepository>(
  (Ref ref) => ForumThreadSearchRepository(
    ref.watch(forumClientProvider),
    ref.watch(forumLocalRepositoryProvider),
    ref.watch(authControllerProvider).value?.userId ?? 0,
  ),
);

class ForumThreadSearchRepository {
  ForumThreadSearchRepository(
    this._client,
    this._localRepository,
    this._userId, [
    this._parser = const ForumThreadSearchParser(),
    this._originPolicy = const ForumOriginPolicy(),
    this._authParser = const AuthPageParser(),
  ]);

  static final Uri defaultFormUri = ForumClient.baseUri.resolve(
    'search.php?mod=forum&mobile=2',
  );

  final ForumClient _client;
  final ForumLocalRepository _localRepository;
  final int _userId;
  final ForumThreadSearchParser _parser;
  final ForumOriginPolicy _originPolicy;
  final AuthPageParser _authParser;
  int _generation = 0;

  Future<ForumThreadSearchForm> loadForm([Uri? sourceUri]) async {
    _checkUserId();
    final Uri uri = sourceUri ?? defaultFormUri;
    _requireMobileSearchUri(uri);
    late ForumThreadSearchForm form;
    await _client.withActiveAccount<void>(_userId, () async {
      final Response<String> response = await _client.getText(uri);
      final String html = response.data ?? '';
      _validateIdentity(html);
      form = await _parseForm(html, response.realUri);
      _ensureFormScope(form, _expectedBoardId(uri));
    });
    return form;
  }

  Future<ForumThreadSearchPage> search({
    required String keyword,
    Uri? formUri,
  }) {
    _checkUserId();
    final String normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty) {
      throw ArgumentError.value(keyword, 'keyword', '搜索词不能为空');
    }
    final Uri sourceUri = formUri ?? defaultFormUri;
    _requireMobileSearchUri(sourceUri);
    final int? sourceBoardId = _expectedBoardId(sourceUri);
    final String cacheKey = _initialCacheKey(sourceUri, normalizedKeyword);
    final int generation = ++_generation;
    return _loadWithCache(
      cacheKey: cacheKey,
      expectedKeyword: normalizedKeyword,
      expectedBoardId: sourceBoardId,
      loadRemote: () => _searchRemote(
        sourceUri,
        normalizedKeyword,
        expectedBoardId: sourceBoardId,
      ),
      isCurrent: () => generation == _generation,
    );
  }

  Future<ForumThreadSearchPage> loadNext(ForumThreadSearchPage cursor) {
    _checkUserId();
    final Uri? uri = cursor.cursor.nextPageUri;
    if (uri == null) {
      return Future<ForumThreadSearchPage>.value(cursor);
    }
    _requireMobileSearchUri(uri);
    final int generation = ++_generation;
    return _loadWithCache(
      cacheKey: _pageCacheKey(uri, cursor.keyword),
      expectedKeyword: cursor.keyword,
      expectedBoardId: cursor.boardId,
      loadRemote: () => _loadResultPage(
        uri,
        expectedKeyword: cursor.keyword,
        expectedBoardId: cursor.boardId,
      ),
      isCurrent: () => generation == _generation,
    );
  }

  Future<ForumThreadSearchPage> _searchRemote(
    Uri formUri,
    String keyword, {
    required int? expectedBoardId,
  }) async {
    final ForumThreadSearchForm form = await loadForm(formUri);
    _validateForm(form);
    _ensureFormScope(form, expectedBoardId);
    final Response<String> response = await _client.postForm(
      form.actionUri,
      referer: form.sourceUri.toString(),
      fields: _submissionFields(form, keyword),
    );
    final String html = response.data ?? '';
    _validateIdentity(html);
    return _parseResults(
      html,
      response.realUri,
      expectedKeyword: keyword,
      expectedBoardId: expectedBoardId,
    );
  }

  Future<ForumThreadSearchPage> _loadResultPage(
    Uri uri, {
    required String expectedKeyword,
    int? expectedBoardId,
  }) async {
    final Response<String> response = await _client.getText(uri);
    final String html = response.data ?? '';
    _validateIdentity(html);
    return _parseResults(
      html,
      response.realUri,
      expectedKeyword: expectedKeyword,
      expectedBoardId: expectedBoardId,
    );
  }

  Future<ForumThreadSearchPage> _loadWithCache({
    required String cacheKey,
    required String expectedKeyword,
    required Future<ForumThreadSearchPage> Function() loadRemote,
    required bool Function() isCurrent,
    int? expectedBoardId,
  }) async {
    try {
      late ForumThreadSearchPage page;
      await _client.withActiveAccount<void>(_userId, () async {
        page = await loadRemote();
        _ensureCurrent(isCurrent);
        try {
          await _localRepository.saveCache(
            userId: _userId,
            key: cacheKey,
            payload: _encodePage(page),
          );
        } on ForumSearchRequestSupersededException {
          rethrow;
        } on ForumSessionExpiredException {
          rethrow;
        } on Object {
          // 搜索结果已成功取得时，本地缓存失败不覆盖在线结果。
        }
      });
      return page;
    } on ForumConnectionException catch (error, stackTrace) {
      _ensureCurrent(isCurrent);
      try {
        final ForumCacheSnapshot? snapshot = await _client.withActiveAccount(
          _userId,
          () => _localRepository.loadCache(userId: _userId, key: cacheKey),
        );
        if (snapshot != null) {
          _ensureCurrent(isCurrent);
          final ForumThreadSearchPage page = _decodePage(snapshot.payload);
          if (page.keyword != expectedKeyword ||
              page.boardId != expectedBoardId) {
            throw const ForumParseException('论坛搜索缓存范围不一致');
          }
          return _markCached(page, snapshot.updatedAt);
        }
      } on ForumSearchRequestSupersededException {
        rethrow;
      } on ForumSessionExpiredException {
        rethrow;
      } on Object {
        // 损坏或不兼容缓存按不存在处理，并保留原连接错误。
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _ensureCurrent(bool Function() isCurrent) {
    if (!isCurrent()) {
      throw const ForumSearchRequestSupersededException();
    }
  }

  Map<String, dynamic> _submissionFields(
    ForumThreadSearchForm form,
    String keyword,
  ) {
    final Map<String, List<String>> values = <String, List<String>>{};
    for (final MapEntry<String, List<String>> field
        in form.hiddenFields.entries) {
      values[field.key] = List<String>.of(field.value);
    }
    if (values.containsKey(form.keywordFieldName)) {
      throw const ForumParseException('论坛搜索关键字字段与隐藏字段冲突');
    }
    values[form.keywordFieldName] = <String>[keyword];
    for (final ForumThreadSearchScopeOption option in form.scopeOptions.where(
      (ForumThreadSearchScopeOption value) => value.selected,
    )) {
      values.putIfAbsent(option.fieldName, () => <String>[]).add(option.value);
    }
    return values.map(
      (String name, List<String> fieldValues) => MapEntry<String, dynamic>(
        name,
        fieldValues.length == 1
            ? fieldValues.single
            : List<String>.unmodifiable(fieldValues),
      ),
    );
  }

  Future<ForumThreadSearchForm> _parseForm(String html, Uri pageUri) {
    final ForumThreadSearchParser parser = _parser;
    return Isolate.run(
      () => parser.parseForm(html, pageUri),
      debugName: 'x300-forum-thread-search-form-parser',
    );
  }

  Future<ForumThreadSearchPage> _parseResults(
    String html,
    Uri pageUri, {
    required String expectedKeyword,
    int? expectedBoardId,
  }) {
    final ForumThreadSearchParser parser = _parser;
    return Isolate.run(
      () => parser.parseResults(
        html,
        pageUri,
        expectedKeyword: expectedKeyword,
        expectedBoardId: expectedBoardId,
      ),
      debugName: 'x300-forum-thread-search-result-parser',
    );
  }

  void _validateForm(ForumThreadSearchForm form) {
    _originPolicy.ensureAllowed(form.sourceUri);
    _originPolicy.ensureAllowed(form.actionUri);
    if (form.actionUri.path != '/search.php' ||
        form.actionUri.queryParameters['mod'] != 'forum') {
      throw const ForumParseException('论坛搜索表单 action 无效');
    }
  }

  void _ensureFormScope(ForumThreadSearchForm form, int? expectedBoardId) {
    if (form.boardId != expectedBoardId) {
      throw const ForumParseException('论坛搜索表单的 srhfid 与搜索入口不一致');
    }
  }

  int? _expectedBoardId(Uri uri) {
    final int? boardId = int.tryParse(uri.queryParameters['srhfid'] ?? '');
    if (uri.queryParameters['mod'] == 'forum') {
      if (boardId != null && boardId > 0) {
        throw const ForumParseException('全站论坛搜索地址不应携带 srhfid');
      }
      return null;
    }
    if (boardId == null || boardId <= 0) {
      throw const ForumParseException('当前版块搜索地址缺少 srhfid');
    }
    return boardId;
  }

  void _validateIdentity(String html) {
    if (_authParser.currentUserId(html) != _userId) {
      throw const ForumSessionExpiredException();
    }
  }

  void _requireMobileSearchUri(Uri uri) {
    _originPolicy.requireMobilePage(uri);
    if (uri.path != '/search.php' ||
        !const <String>{
          'forum',
          'curforum',
        }.contains(uri.queryParameters['mod'])) {
      throw const ForumParseException('论坛移动搜索地址无效');
    }
  }

  void _checkUserId() {
    if (_userId <= 0) {
      throw const ForumSessionExpiredException();
    }
  }

  String _initialCacheKey(Uri formUri, String keyword) {
    return _cacheKey('initial', '${formUri.replace(fragment: '')}|$keyword');
  }

  String _pageCacheKey(Uri uri, String keyword) {
    return _cacheKey('page', '${uri.replace(fragment: '')}|$keyword');
  }

  String _cacheKey(String kind, String value) {
    final String digest = sha256.convert(utf8.encode(value)).toString();
    return 'forum:v2:search:$kind:$digest';
  }

  Map<String, dynamic> _encodePage(ForumThreadSearchPage page) {
    return <String, dynamic>{
      'keyword': page.keyword,
      'searchId': page.searchId,
      'boardId': page.boardId,
      'scopeLabels': page.scopeLabels,
      'totalResults': page.totalResults,
      'sourceUri': page.sourceUri.toString(),
      'cursor': <String, dynamic>{
        'currentPage': page.cursor.currentPage,
        'totalPages': page.cursor.totalPages,
        'sourceUri': page.cursor.sourceUri.toString(),
        'previousPageUri': page.cursor.previousPageUri?.toString(),
        'nextPageUri': page.cursor.nextPageUri?.toString(),
      },
      'hits': page.hits
          .map(
            (ForumThreadSearchHit hit) => <String, dynamic>{
              'threadId': hit.threadId,
              'boardId': hit.boardId,
              'postId': hit.postId,
              'title': hit.title,
              'uri': hit.uri.toString(),
              'authorId': hit.authorId,
              'authorUri': _encodeProfileUri(hit.authorUri, hit.authorId),
              'author': hit.author,
              'avatarUri': hit.avatarUri?.toString(),
              'timeLabel': hit.timeLabel,
              'summary': hit.summary,
              'boardName': hit.boardName,
              'views': hit.views,
              'replies': hit.replies,
            },
          )
          .toList(growable: false),
    };
  }

  ForumThreadSearchPage _decodePage(Map<String, dynamic> value) {
    final Map<String, dynamic> cursorValue = Map<String, dynamic>.from(
      value['cursor'] as Map,
    );
    final Uri sourceUri = Uri.parse(value['sourceUri'] as String);
    _originPolicy.ensureAllowed(sourceUri);
    final Uri cursorSourceUri = Uri.parse(cursorValue['sourceUri'] as String);
    _originPolicy.ensureAllowed(cursorSourceUri);
    final Uri? previousPageUri = _optionalUri(
      cursorValue['previousPageUri'],
      mobileSearch: true,
    );
    final Uri? nextPageUri = _optionalUri(
      cursorValue['nextPageUri'],
      mobileSearch: true,
    );
    final List<ForumThreadSearchHit> hits = (value['hits'] as List<dynamic>)
        .map((dynamic raw) {
          final Map<String, dynamic> hit = Map<String, dynamic>.from(
            raw as Map,
          );
          final Uri uri = Uri.parse(hit['uri'] as String);
          _originPolicy.requireMobilePage(uri);
          final Uri? avatarUri = _optionalUri(hit['avatarUri']);
          final int threadId = (hit['threadId'] as num).toInt();
          final int boardId = (hit['boardId'] as num).toInt();
          final int? authorId = (hit['authorId'] as num?)?.toInt();
          final Uri? authorUri = _decodeProfileUri(
            hit['authorUri'],
            authorId,
          );
          if (threadId <= 0 || boardId <= 0 || uri.path != '/forum.php') {
            throw const ForumParseException('论坛搜索缓存标识无效');
          }
          return ForumThreadSearchHit(
            threadId: threadId,
            boardId: boardId,
            postId: (hit['postId'] as num?)?.toInt(),
            title: hit['title'] as String,
            uri: uri,
            authorId: authorId,
            authorUri: authorUri,
            author: hit['author'] as String,
            avatarUri: avatarUri,
            timeLabel: hit['timeLabel'] as String,
            summary: hit['summary'] as String,
            boardName: hit['boardName'] as String,
            views: (hit['views'] as num).toInt(),
            replies: (hit['replies'] as num).toInt(),
          );
        })
        .toList(growable: false);
    final int currentPage = (cursorValue['currentPage'] as num).toInt();
    final int totalPages = (cursorValue['totalPages'] as num).toInt();
    if (currentPage <= 0 || totalPages < currentPage) {
      throw const ForumParseException('论坛搜索缓存分页无效');
    }
    return ForumThreadSearchPage(
      keyword: value['keyword'] as String,
      searchId: value['searchId'] as String,
      boardId: (value['boardId'] as num?)?.toInt(),
      scopeLabels: List<String>.unmodifiable(
        (value['scopeLabels'] as List<dynamic>).whereType<String>(),
      ),
      hits: List<ForumThreadSearchHit>.unmodifiable(hits),
      cursor: ForumPageCursor(
        currentPage: currentPage,
        totalPages: totalPages,
        sourceUri: cursorSourceUri,
        previousPageUri: previousPageUri,
        nextPageUri: nextPageUri,
      ),
      sourceUri: sourceUri,
      totalResults: (value['totalResults'] as num?)?.toInt(),
    );
  }

  Uri? _optionalUri(Object? value, {bool mobileSearch = false}) {
    if (value == null) {
      return null;
    }
    final Uri uri = Uri.parse(value as String);
    if (mobileSearch) {
      _requireMobileSearchUri(uri);
    } else {
      _originPolicy.ensureAllowed(uri);
    }
    return uri;
  }

  String? _encodeProfileUri(Uri? uri, int? expectedUserId) {
    if (uri == null) {
      return null;
    }
    _requireProfileUri(uri, expectedUserId);
    return uri.toString();
  }

  Uri? _decodeProfileUri(Object? value, int? expectedUserId) {
    if (value == null) {
      return null;
    }
    final Uri uri = Uri.parse(value as String);
    _requireProfileUri(uri, expectedUserId);
    return uri;
  }

  void _requireProfileUri(Uri uri, int? expectedUserId) {
    _originPolicy.requireMobilePage(uri);
    final List<String> uidValues =
        uri.queryParametersAll['uid'] ?? const <String>[];
    final int? userId = uidValues.length == 1
        ? int.tryParse(uidValues.single)
        : null;
    final List<String> modValues =
        uri.queryParametersAll['mod'] ?? const <String>[];
    final List<String> doValues =
        uri.queryParametersAll['do'] ?? const <String>[];
    if (expectedUserId == null ||
        expectedUserId <= 0 ||
        uri.path != '/home.php' ||
        modValues.length != 1 ||
        modValues.single != 'space' ||
        (doValues.isNotEmpty &&
            (doValues.length != 1 || doValues.single != 'profile')) ||
        userId != expectedUserId ||
        !uri.queryParametersAll.entries.every(
          (MapEntry<String, List<String>> entry) =>
              const <String>{'mod', 'do', 'uid', 'mobile'}.contains(entry.key) &&
              entry.value.length == 1,
        )) {
      throw const ForumParseException('论坛搜索缓存作者 URI 与 uid 不一致');
    }
  }

  ForumThreadSearchPage _markCached(
    ForumThreadSearchPage page,
    DateTime updatedAt,
  ) {
    return ForumThreadSearchPage(
      keyword: page.keyword,
      searchId: page.searchId,
      boardId: page.boardId,
      scopeLabels: page.scopeLabels,
      hits: page.hits,
      cursor: page.cursor,
      sourceUri: page.sourceUri,
      totalResults: page.totalResults,
      isFromCache: true,
      cacheUpdatedAt: updatedAt,
    );
  }
}

class ForumSearchRequestSupersededException extends ForumException {
  const ForumSearchRequestSupersededException() : super('论坛搜索请求已被更新操作替代');
}
