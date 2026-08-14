import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

sealed class FavoriteTargetContent {
  const FavoriteTargetContent({required this.sourceUri});

  final Uri sourceUri;
}

class FavoriteGroupBoardTarget extends FavoriteTargetContent {
  const FavoriteGroupBoardTarget({
    required this.board,
    required super.sourceUri,
  });

  final ForumBoardNode board;
}

class FavoriteGroupPage extends FavoriteTargetContent {
  const FavoriteGroupPage({
    required this.groupId,
    required this.title,
    required this.boards,
    required this.currentPage,
    required super.sourceUri,
    this.nextPageUri,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final int groupId;
  final String title;
  final List<ForumBoardNode> boards;
  final int currentPage;
  final Uri? nextPageUri;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;

  bool get hasNext => nextPageUri != null && !isFromCache;
}

class FavoriteNativeLink {
  const FavoriteNativeLink({required this.label, required this.item});

  final String label;
  final RawFavoriteItem item;
}

class FavoriteBlogComment {
  const FavoriteBlogComment({
    required this.blocks,
    this.author = '',
    this.timeLabel = '',
  });

  final List<ForumPostContentBlock> blocks;
  final String author;
  final String timeLabel;
}

class FavoriteBlog extends FavoriteTargetContent {
  const FavoriteBlog({
    required this.blogId,
    required this.ownerUserId,
    required this.title,
    required this.metadata,
    required this.contentBlocks,
    required this.comments,
    required this.nativeLinks,
    required this.externalImageUris,
    required super.sourceUri,
  });

  final int blogId;
  final int ownerUserId;
  final String title;
  final String metadata;
  final List<ForumPostContentBlock> contentBlocks;
  final List<FavoriteBlogComment> comments;
  final List<FavoriteNativeLink> nativeLinks;
  final List<Uri> externalImageUris;
}

class FavoriteAlbumImage {
  const FavoriteAlbumImage({
    required this.imageUri,
    required this.photoUri,
    this.alt = '',
  });

  final Uri imageUri;
  final Uri photoUri;
  final String alt;
}

class FavoriteAlbum extends FavoriteTargetContent {
  const FavoriteAlbum({
    required this.albumId,
    required this.ownerUserId,
    required this.title,
    required this.description,
    required this.images,
    required super.sourceUri,
  });

  final int albumId;
  final int ownerUserId;
  final String title;
  final String description;
  final List<FavoriteAlbumImage> images;
}
