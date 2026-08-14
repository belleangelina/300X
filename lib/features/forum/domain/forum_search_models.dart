import 'package:x300/features/forum/domain/forum_models.dart';

class ForumThreadSearchScopeOption {
  const ForumThreadSearchScopeOption({
    required this.fieldName,
    required this.value,
    required this.label,
    required this.selected,
  });

  final String fieldName;
  final String value;
  final String label;
  final bool selected;
}

class ForumThreadSearchForm {
  const ForumThreadSearchForm({
    required this.sourceUri,
    required this.actionUri,
    required this.keywordFieldName,
    required this.hiddenFields,
    required this.scopeOptions,
    this.initialKeyword = '',
    this.boardId,
  });

  final Uri sourceUri;
  final Uri actionUri;
  final String keywordFieldName;
  final String initialKeyword;
  final Map<String, List<String>> hiddenFields;
  final List<ForumThreadSearchScopeOption> scopeOptions;
  final int? boardId;

  List<String> get selectedScopeLabels => scopeOptions
      .where((ForumThreadSearchScopeOption value) => value.selected)
      .map((ForumThreadSearchScopeOption value) => value.label)
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
}

class ForumThreadSearchHit {
  const ForumThreadSearchHit({
    required this.threadId,
    required this.boardId,
    required this.title,
    required this.uri,
    this.postId,
    this.authorId,
    this.authorUri,
    this.author = '',
    this.avatarUri,
    this.timeLabel = '',
    this.summary = '',
    this.boardName = '',
    this.views = 0,
    this.replies = 0,
  });

  final int threadId;
  final int boardId;
  final int? postId;
  final String title;
  final Uri uri;
  final int? authorId;
  final Uri? authorUri;
  final String author;
  final Uri? avatarUri;
  final String timeLabel;
  final String summary;
  final String boardName;
  final int views;
  final int replies;
}

class ForumThreadSearchPage {
  const ForumThreadSearchPage({
    required this.keyword,
    required this.hits,
    required this.cursor,
    required this.sourceUri,
    this.searchId = '',
    this.boardId,
    this.scopeLabels = const <String>[],
    this.totalResults,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final String keyword;
  final String searchId;
  final int? boardId;
  final List<String> scopeLabels;
  final List<ForumThreadSearchHit> hits;
  final ForumPageCursor cursor;
  final Uri sourceUri;
  final int? totalResults;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;

  bool get hasMore => cursor.nextPageUri != null;
}
