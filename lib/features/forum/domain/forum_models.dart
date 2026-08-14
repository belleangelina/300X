class ForumViewer {
  const ForumViewer({
    required this.userId,
    this.username = '',
    this.noticeCount = 0,
    this.privateMessageCount = 0,
  });

  final int userId;
  final String username;
  final int noticeCount;
  final int privateMessageCount;
}

class ForumNavigationLinks {
  const ForumNavigationLinks({
    this.searchUri,
    this.favoritesUri,
    this.noticesUri,
    this.messagesUri,
    this.profileUri,
  });

  final Uri? searchUri;
  final Uri? favoritesUri;
  final Uri? noticesUri;
  final Uri? messagesUri;
  final Uri? profileUri;
}

class ForumRouteOption {
  const ForumRouteOption({
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

class ForumPageCursor {
  const ForumPageCursor({
    required this.currentPage,
    required this.totalPages,
    required this.sourceUri,
    this.previousPageUri,
    this.nextPageUri,
  });

  final int currentPage;
  final int totalPages;
  final Uri sourceUri;
  final Uri? previousPageUri;
  final Uri? nextPageUri;
}

class ForumBoardNode {
  const ForumBoardNode({
    required this.id,
    required this.name,
    required this.uri,
    this.parentId,
    this.description = '',
    this.threadCount = 0,
    this.postCount = 0,
    this.todayPostCount = 0,
    this.children = const <ForumBoardNode>[],
  });

  final int id;
  final int? parentId;
  final String name;
  final String description;
  final Uri uri;
  final int threadCount;
  final int postCount;
  final int todayPostCount;
  final List<ForumBoardNode> children;
}

class ForumSection {
  const ForumSection({
    required this.id,
    required this.name,
    required this.boards,
  });

  final int id;
  final String name;
  final List<ForumBoardNode> boards;
}

class ForumBoardIndex {
  const ForumBoardIndex({
    required this.sections,
    required this.unsectionedBoards,
    required this.viewer,
    required this.navigation,
    required this.sourceUri,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final List<ForumSection> sections;
  final List<ForumBoardNode> unsectionedBoards;
  final ForumViewer viewer;
  final ForumNavigationLinks navigation;
  final Uri sourceUri;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;

  ForumBoardNode? boardById(int boardId) {
    ForumBoardNode? find(ForumBoardNode board) {
      if (board.id == boardId) {
        return board;
      }
      for (final ForumBoardNode child in board.children) {
        final ForumBoardNode? result = find(child);
        if (result != null) {
          return result;
        }
      }
      return null;
    }

    for (final ForumSection section in sections) {
      for (final ForumBoardNode board in section.boards) {
        final ForumBoardNode? result = find(board);
        if (result != null) {
          return result;
        }
      }
    }
    for (final ForumBoardNode board in unsectionedBoards) {
      final ForumBoardNode? result = find(board);
      if (result != null) {
        return result;
      }
    }
    return null;
  }
}

enum ForumThreadTargetKind { thread, announcement }

class ForumThreadSummary {
  const ForumThreadSummary({
    required this.id,
    required this.boardId,
    required this.title,
    required this.uri,
    this.typeName = '',
    this.summary = '',
    this.author = '',
    this.authorId,
    this.authorUri,
    this.avatarUri,
    this.timeLabel = '',
    this.views = 0,
    this.replies = 0,
    this.pinned = false,
    this.digest = false,
    this.closed = false,
    this.special = false,
    this.targetKind = ForumThreadTargetKind.thread,
  });

  final int id;
  final int boardId;
  final String title;
  final Uri uri;
  final String typeName;
  final String summary;
  final String author;
  final int? authorId;
  final Uri? authorUri;
  final Uri? avatarUri;
  final String timeLabel;
  final int views;
  final int replies;
  final bool pinned;
  final bool digest;
  final bool closed;
  final bool special;
  final ForumThreadTargetKind targetKind;

  int? get threadId => targetKind == ForumThreadTargetKind.thread ? id : null;
}

class ForumBoardPage {
  const ForumBoardPage({
    required this.board,
    required this.threads,
    required this.filters,
    required this.cursor,
    this.newThreadUri,
    this.favoriteUri,
    this.searchUri,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final ForumBoardNode board;
  final List<ForumThreadSummary> threads;
  final List<ForumRouteOption> filters;
  final ForumPageCursor cursor;
  final Uri? newThreadUri;
  final Uri? favoriteUri;
  final Uri? searchUri;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;
}

class ForumAttachment {
  const ForumAttachment({
    required this.name,
    required this.uri,
    this.id,
    this.description = '',
    this.sizeLabel = '',
    this.isImage = false,
  });

  final int? id;
  final String name;
  final String description;
  final String sizeLabel;
  final Uri uri;
  final bool isImage;
}

class ForumPostComment {
  const ForumPostComment({
    required this.id,
    required this.threadId,
    required this.postId,
    required this.author,
    required this.timeLabel,
    required this.contentBlocks,
    this.authorId,
    this.authorUri,
    this.avatarUri,
  });

  final int id;
  final int threadId;
  final int postId;
  final int? authorId;
  final Uri? authorUri;
  final String author;
  final Uri? avatarUri;
  final String timeLabel;
  final List<ForumPostContentBlock> contentBlocks;
}

class ForumPostRatingScore {
  const ForumPostRatingScore({required this.credit, required this.value});

  final String credit;
  final int value;
}

class ForumPostRatingEntry {
  const ForumPostRatingEntry({
    required this.author,
    required this.scores,
    this.authorId,
    this.authorUri,
    this.avatarUri,
    this.reason = '',
    this.timeLabel = '',
  });

  final int? authorId;
  final Uri? authorUri;
  final String author;
  final Uri? avatarUri;
  final List<ForumPostRatingScore> scores;
  final String reason;
  final String timeLabel;
}

class ForumPostRatingSummary {
  const ForumPostRatingSummary({
    required this.participantCount,
    required this.totals,
    required this.entries,
  });

  final int participantCount;
  final List<ForumPostRatingScore> totals;
  final List<ForumPostRatingEntry> entries;

  bool get hasMore => participantCount > entries.length;
}

sealed class ForumPostContentBlock {
  const ForumPostContentBlock({required this.inlines});

  final List<ForumPostInline> inlines;
}

class ForumPostParagraphBlock extends ForumPostContentBlock {
  const ForumPostParagraphBlock({required super.inlines});
}

class ForumPostQuoteBlock extends ForumPostContentBlock {
  const ForumPostQuoteBlock({required super.inlines});
}

class ForumPostCodeBlock extends ForumPostContentBlock {
  const ForumPostCodeBlock({required super.inlines});
}

sealed class ForumPostInline {
  const ForumPostInline();
}

class ForumPostTextInline extends ForumPostInline {
  const ForumPostTextInline({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.code = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
}

class ForumPostLineBreakInline extends ForumPostInline {
  const ForumPostLineBreakInline();
}

class ForumPostImageInline extends ForumPostInline {
  const ForumPostImageInline({
    required this.uri,
    this.alt = '',
    this.isEmoticon = false,
  });

  final Uri uri;
  final String alt;
  final bool isEmoticon;
}

enum ForumPostLinkKind { internalThread, internalPost, download, external }

class ForumPostLinkInline extends ForumPostInline {
  const ForumPostLinkInline({
    required this.label,
    required this.uri,
    required this.kind,
    this.threadId,
    this.postId,
    this.bold = false,
    this.italic = false,
    this.code = false,
  });

  final String label;
  final Uri uri;
  final ForumPostLinkKind kind;
  final int? threadId;
  final int? postId;
  final bool bold;
  final bool italic;
  final bool code;
}

class ForumPost {
  const ForumPost({
    required this.id,
    required this.threadId,
    required this.floor,
    required this.author,
    required this.timeLabel,
    required this.messageHtml,
    required this.uri,
    this.authorId,
    this.authorUri,
    this.avatarUri,
    this.attachments = const <ForumAttachment>[],
    this.contentBlocks = const <ForumPostContentBlock>[],
    this.comments = const <ForumPostComment>[],
    this.ratingSummary,
    this.quoteUri,
    this.rateUri,
    this.commentUri,
    this.ratingsUri,
    this.editUri,
    this.isOriginalPoster = false,
  });

  final int id;
  final int threadId;
  final int floor;
  final int? authorId;
  final Uri? authorUri;
  final String author;
  final Uri? avatarUri;
  final String timeLabel;
  final String messageHtml;
  final Uri uri;
  final List<ForumAttachment> attachments;
  final List<ForumPostContentBlock> contentBlocks;
  final List<ForumPostComment> comments;
  final ForumPostRatingSummary? ratingSummary;
  final Uri? quoteUri;
  final Uri? rateUri;
  final Uri? commentUri;
  final Uri? ratingsUri;
  final Uri? editUri;
  final bool isOriginalPoster;
}

class ForumThread {
  const ForumThread({
    required this.id,
    required this.boardId,
    required this.title,
    required this.uri,
    this.author = '',
    this.authorId,
    this.typeName = '',
  });

  final int id;
  final int boardId;
  final String title;
  final Uri uri;
  final int? authorId;
  final String author;
  final String typeName;
}

class ForumThreadPage {
  const ForumThreadPage({
    required this.thread,
    required this.posts,
    required this.readingOptions,
    required this.cursor,
    this.replyUri,
    this.favoriteUri,
    this.shareUri,
    this.focusedPostId,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final ForumThread thread;
  final List<ForumPost> posts;
  final List<ForumRouteOption> readingOptions;
  final ForumPageCursor cursor;
  final Uri? replyUri;
  final Uri? favoriteUri;
  final Uri? shareUri;
  final int? focusedPostId;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;

  ForumPost? postById(int postId) {
    for (final ForumPost post in posts) {
      if (post.id == postId) {
        return post;
      }
    }
    return null;
  }
}
