class RawFavoriteCategory {
  const RawFavoriteCategory({
    required this.key,
    required this.label,
    required this.uri,
    this.selected = false,
  });

  final String key;
  final String label;
  final Uri uri;
  final bool selected;
}

enum RawFavoriteTargetKind {
  thread,
  board,
  groupBoard,
  groupCategory,
  blog,
  album,
  userSpace,
  community,
  unknown,
}

class RawFavoriteItem {
  const RawFavoriteItem({
    required this.categoryKey,
    required this.title,
    required this.targetKind,
    this.favoriteId,
    this.targetUri,
    this.deleteDialogUri,
    this.threadId,
    this.boardId,
    this.userId,
    this.groupId,
    this.contentId,
    this.description = '',
  });

  final int? favoriteId;
  final String categoryKey;
  final String title;
  final String description;
  final Uri? targetUri;
  final Uri? deleteDialogUri;
  final RawFavoriteTargetKind targetKind;
  final int? threadId;
  final int? boardId;
  final int? userId;
  final int? groupId;
  final int? contentId;

  int? get targetId => switch (targetKind) {
    RawFavoriteTargetKind.thread => threadId,
    RawFavoriteTargetKind.board || RawFavoriteTargetKind.groupBoard => boardId,
    RawFavoriteTargetKind.groupCategory => groupId,
    RawFavoriteTargetKind.blog || RawFavoriteTargetKind.album => contentId,
    RawFavoriteTargetKind.userSpace => userId,
    RawFavoriteTargetKind.community || RawFavoriteTargetKind.unknown => null,
  };

  String get identityKey => favoriteId == null
      ? '$categoryKey:${targetUri ?? title}'
      : 'favorite:$favoriteId';
}

class RawFavoriteCategoryCursor {
  const RawFavoriteCategoryCursor({
    required this.categoryKey,
    required this.sourceUri,
    this.nextPageUri,
  });

  final String categoryKey;
  final Uri sourceUri;
  final Uri? nextPageUri;
}

class RawFavoritePage {
  const RawFavoritePage({
    required this.categories,
    required this.items,
    required this.selectedCategoryKey,
    required this.currentPage,
    required this.totalPages,
    required this.sourceUri,
    this.previousPageUri,
    this.nextPageUri,
    this.mergedCursors = const <String, RawFavoriteCategoryCursor>{},
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final List<RawFavoriteCategory> categories;
  final List<RawFavoriteItem> items;
  final String selectedCategoryKey;
  final int currentPage;
  final int totalPages;
  final Uri sourceUri;
  final Uri? previousPageUri;
  final Uri? nextPageUri;
  final Map<String, RawFavoriteCategoryCursor> mergedCursors;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;

  bool get hasNext =>
      nextPageUri != null ||
      mergedCursors.values.any(
        (RawFavoriteCategoryCursor cursor) => cursor.nextPageUri != null,
      );
}
