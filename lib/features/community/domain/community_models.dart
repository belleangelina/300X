enum CommunityReadEffect { none, marksNoticeListRead, marksConversationRead }

class CommunityPageCursor {
  const CommunityPageCursor({
    required this.sourceUri,
    required this.currentPage,
    required this.totalPages,
    this.previousPageUri,
    this.nextPageUri,
  });

  final Uri sourceUri;
  final int currentPage;
  final int totalPages;
  final Uri? previousPageUri;
  final Uri? nextPageUri;
}

class CommunityTopicTarget {
  const CommunityTopicTarget({
    required this.threadId,
    required this.uri,
    this.postId,
    this.title = '',
    this.boardId = 0,
  });

  final int threadId;
  final int? postId;
  final int boardId;
  final String title;
  final Uri uri;
}

class CommunityProfileTarget {
  const CommunityProfileTarget({
    required this.userId,
    required this.uri,
    this.username = '',
    this.avatarUri,
  });

  final int userId;
  final String username;
  final Uri uri;
  final Uri? avatarUri;
}

class CommunityNoticeCategory {
  const CommunityNoticeCategory({required this.key, required this.label});

  final String key;
  final String label;
}

class CommunityNotice {
  const CommunityNotice({
    required this.id,
    required this.category,
    required this.title,
    required this.message,
    required this.timeLabel,
    this.unread = false,
    this.avatarUri,
    this.topicTarget,
    this.profileTarget,
  });

  final int id;
  final CommunityNoticeCategory category;
  final String title;
  final String message;
  final String timeLabel;
  final bool unread;
  final Uri? avatarUri;
  final CommunityTopicTarget? topicTarget;
  final CommunityProfileTarget? profileTarget;

  bool get canOpen => topicTarget != null || profileTarget != null;
}

class CommunityNoticePage {
  const CommunityNoticePage({
    required this.items,
    required this.categories,
    required this.cursor,
    this.navigation = const <CommunitySectionLink>[],
    this.readEffect = CommunityReadEffect.marksNoticeListRead,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final List<CommunityNotice> items;
  final List<CommunityNoticeCategory> categories;
  final CommunityPageCursor cursor;
  final List<CommunitySectionLink> navigation;
  final CommunityReadEffect readEffect;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;
}

class CommunityPmConversation {
  const CommunityPmConversation({
    required this.peerUserId,
    required this.peerUsername,
    required this.preview,
    required this.timeLabel,
    required this.uri,
    this.avatarUri,
    this.unread = false,
  });

  final int peerUserId;
  final String peerUsername;
  final Uri? avatarUri;
  final String preview;
  final String timeLabel;
  final Uri uri;
  final bool unread;
}

class CommunityPmListPage {
  const CommunityPmListPage({
    required this.items,
    required this.cursor,
    this.navigation = const <CommunitySectionLink>[],
    this.composeUri,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final List<CommunityPmConversation> items;
  final CommunityPageCursor cursor;
  final List<CommunitySectionLink> navigation;
  final Uri? composeUri;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;
}

enum CommunitySectionKind { notices, messages, profile }

class CommunitySectionLink {
  const CommunitySectionLink({
    required this.kind,
    required this.label,
    required this.uri,
    this.selected = false,
  });

  final CommunitySectionKind kind;
  final String label;
  final Uri uri;
  final bool selected;
}

class CommunityPmMessage {
  const CommunityPmMessage({
    required this.message,
    required this.timeLabel,
    required this.sentByViewer,
    this.avatarUri,
  });

  final String message;
  final String timeLabel;
  final bool sentByViewer;
  final Uri? avatarUri;
}

class CommunityPmThreadPage {
  const CommunityPmThreadPage({
    required this.peerUserId,
    required this.messages,
    required this.cursor,
    required this.hasSendCapability,
    this.readEffect = CommunityReadEffect.marksConversationRead,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final int peerUserId;
  final List<CommunityPmMessage> messages;
  final CommunityPageCursor cursor;
  final bool hasSendCapability;
  final CommunityReadEffect readEffect;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;
}

class CommunityPmFormContract {
  const CommunityPmFormContract({
    required this.context,
    required this.method,
    required this.actionPath,
    required this.actionQueryKeys,
    required this.fieldNames,
    required this.hasFormhash,
  });

  final String context;
  final String method;
  final String actionPath;
  final List<String> actionQueryKeys;
  final List<String> fieldNames;
  final bool hasFormhash;
}

enum CommunityProfileEntryKind {
  topics,
  replies,
  messages,
  friends,
  favorites,
  unknown,
}

class CommunityProfileEntry {
  const CommunityProfileEntry({
    required this.label,
    required this.uri,
    required this.kind,
  });

  final String label;
  final Uri uri;
  final CommunityProfileEntryKind kind;

  bool get supported => canOpenFor(profileUserId: 0, viewerUserId: 0);

  bool canOpenFor({
    required int profileUserId,
    required int viewerUserId,
  }) {
    return switch (kind) {
      CommunityProfileEntryKind.topics ||
      CommunityProfileEntryKind.replies ||
      CommunityProfileEntryKind.messages ||
      CommunityProfileEntryKind.friends => true,
      CommunityProfileEntryKind.favorites =>
        profileUserId > 0 && profileUserId == viewerUserId,
      CommunityProfileEntryKind.unknown => false,
    };
  }
}

class CommunityProfile {
  const CommunityProfile({
    required this.userId,
    required this.username,
    required this.sourceUri,
    required this.entries,
    required this.details,
    this.avatarUri,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final int userId;
  final String username;
  final Uri? avatarUri;
  final Uri sourceUri;
  final List<CommunityProfileEntry> entries;
  final List<String> details;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;
}

enum CommunityActivityKind { topics, replies }

class CommunityActivityItem {
  const CommunityActivityItem({
    required this.title,
    required this.summary,
    required this.timeLabel,
    required this.target,
    this.author = '',
    this.avatarUri,
    this.views = 0,
    this.replies = 0,
  });

  final String title;
  final String summary;
  final String timeLabel;
  final String author;
  final Uri? avatarUri;
  final int views;
  final int replies;
  final CommunityTopicTarget target;
}

class CommunityActivityPage {
  const CommunityActivityPage({
    required this.kind,
    required this.profileUserId,
    required this.items,
    required this.cursor,
    required this.tabs,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final CommunityActivityKind kind;
  final int profileUserId;
  final List<CommunityActivityItem> items;
  final CommunityPageCursor cursor;
  final List<CommunityProfileEntry> tabs;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;
}

enum CommunityPeopleKind { friends, online, visitors, visited }

class CommunityPerson {
  const CommunityPerson({
    required this.profile,
    required this.description,
    this.timeLabel = '',
    this.conversationUri,
  });

  final CommunityProfileTarget profile;
  final String description;
  final String timeLabel;
  final Uri? conversationUri;
}

class CommunityPeopleTab {
  const CommunityPeopleTab({
    required this.kind,
    required this.label,
    required this.uri,
    this.selected = false,
  });

  final CommunityPeopleKind kind;
  final String label;
  final Uri uri;
  final bool selected;
}

class CommunityPeoplePage {
  const CommunityPeoplePage({
    required this.kind,
    required this.people,
    required this.tabs,
    required this.cursor,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final CommunityPeopleKind kind;
  final List<CommunityPerson> people;
  final List<CommunityPeopleTab> tabs;
  final CommunityPageCursor cursor;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;
}
