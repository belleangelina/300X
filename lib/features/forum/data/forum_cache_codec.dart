import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/domain/forum_announcement_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

class ForumCacheCodec {
  const ForumCacheCodec();

  static const int version = 2;

  Map<String, dynamic> encodeIndex(ForumBoardIndex value) {
    return <String, dynamic>{
      'version': version,
      'kind': 'index',
      'sourceUri': _encodeForumUri(value.sourceUri),
      'viewer': <String, dynamic>{
        'userId': value.viewer.userId,
        'username': value.viewer.username,
        'noticeCount': value.viewer.noticeCount,
        'privateMessageCount': value.viewer.privateMessageCount,
      },
      'navigation': <String, dynamic>{
        'searchUri': _encodeOptionalForumUri(value.navigation.searchUri),
        'favoritesUri': _encodeOptionalForumUri(value.navigation.favoritesUri),
        'noticesUri': _encodeOptionalForumUri(value.navigation.noticesUri),
        'messagesUri': _encodeOptionalForumUri(value.navigation.messagesUri),
        'profileUri': _encodeOptionalForumUri(value.navigation.profileUri),
      },
      'sections': value.sections
          .map(
            (ForumSection section) => <String, dynamic>{
              'id': section.id,
              'name': section.name,
              'boards': section.boards
                  .map(_encodeBoard)
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
      'unsectionedBoards': value.unsectionedBoards
          .map(_encodeBoard)
          .toList(growable: false),
    };
  }

  ForumBoardIndex decodeIndex(Map<String, dynamic> value) {
    _expect(value, 'index');
    final Map<String, dynamic> viewer = _map(value['viewer']);
    final Map<String, dynamic> navigation = _map(value['navigation']);
    return ForumBoardIndex(
      sections: _list(value['sections'])
          .map(_map)
          .map(
            (Map<String, dynamic> section) => ForumSection(
              id: _integer(section['id']),
              name: _string(section['name']),
              boards: _list(
                section['boards'],
              ).map(_map).map(_decodeBoard).toList(growable: false),
            ),
          )
          .toList(growable: false),
      unsectionedBoards: _list(
        value['unsectionedBoards'],
      ).map(_map).map(_decodeBoard).toList(growable: false),
      viewer: ForumViewer(
        userId: _integer(viewer['userId']),
        username: _string(viewer['username']),
        noticeCount: _integer(viewer['noticeCount']),
        privateMessageCount: _integer(viewer['privateMessageCount']),
      ),
      navigation: ForumNavigationLinks(
        searchUri: _optionalUri(navigation['searchUri']),
        favoritesUri: _optionalUri(navigation['favoritesUri']),
        noticesUri: _optionalUri(navigation['noticesUri']),
        messagesUri: _optionalUri(navigation['messagesUri']),
        profileUri: _optionalUri(navigation['profileUri']),
      ),
      sourceUri: _uri(value['sourceUri']),
    );
  }

  Map<String, dynamic> encodeBoardPage(ForumBoardPage value) {
    return <String, dynamic>{
      'version': version,
      'kind': 'board',
      'board': _encodeBoard(value.board),
      'threads': value.threads
          .map(_encodeThreadSummary)
          .toList(growable: false),
      'filters': value.filters.map(_encodeOption).toList(growable: false),
      'cursor': _encodeCursor(value.cursor),
    };
  }

  ForumBoardPage decodeBoardPage(Map<String, dynamic> value) {
    _expect(value, 'board');
    return ForumBoardPage(
      board: _decodeBoard(_map(value['board'])),
      threads: _list(
        value['threads'],
      ).map(_map).map(_decodeThreadSummary).toList(growable: false),
      filters: _list(
        value['filters'],
      ).map(_map).map(_decodeOption).toList(growable: false),
      cursor: _decodeCursor(_map(value['cursor'])),
    );
  }

  Map<String, dynamic> encodeThreadPage(ForumThreadPage value) {
    return <String, dynamic>{
      'version': version,
      'kind': 'thread',
      'thread': <String, dynamic>{
        'id': value.thread.id,
        'boardId': value.thread.boardId,
        'title': value.thread.title,
        'uri': _encodeForumUri(value.thread.uri),
        'authorId': value.thread.authorId,
        'author': value.thread.author,
        'typeName': value.thread.typeName,
      },
      'posts': value.posts
          .map(
            (ForumPost post) => <String, dynamic>{
              'id': post.id,
              'threadId': post.threadId,
              'floor': post.floor,
              'authorId': post.authorId,
              'authorUri': _encodeProfileUri(post.authorUri, post.authorId),
              'author': post.author,
              'avatarUri': _encodeOptionalForumUri(post.avatarUri),
              'timeLabel': post.timeLabel,
              'messageHtml': _sanitizeLegacyHtml(post.messageHtml),
              'contentBlocks': post.contentBlocks
                  .map(_encodeContentBlock)
                  .toList(growable: false),
              'comments': post.comments
                  .map(_encodeComment)
                  .toList(growable: false),
              'ratingSummary': post.ratingSummary == null
                  ? null
                  : _encodeRatingSummary(post.ratingSummary!),
              'uri': _encodeForumUri(post.uri),
              'attachments': post.attachments
                  .map(
                    (ForumAttachment attachment) => <String, dynamic>{
                      'id': attachment.id,
                      'name': attachment.name,
                      'description': attachment.description,
                      'sizeLabel': attachment.sizeLabel,
                      'uri': _encodeForumContentUri(attachment.uri),
                      'isImage': attachment.isImage,
                    },
                  )
                  .toList(growable: false),
              'isOriginalPoster': post.isOriginalPoster,
            },
          )
          .toList(growable: false),
      'readingOptions': value.readingOptions
          .map(_encodeOption)
          .toList(growable: false),
      'cursor': _encodeCursor(value.cursor),
      'focusedPostId': value.focusedPostId,
    };
  }

  ForumThreadPage decodeThreadPage(Map<String, dynamic> value) {
    _expect(value, 'thread');
    final Map<String, dynamic> thread = _map(value['thread']);
    return ForumThreadPage(
      thread: ForumThread(
        id: _integer(thread['id']),
        boardId: _integer(thread['boardId']),
        title: _string(thread['title']),
        uri: _uri(thread['uri']),
        authorId: _optionalInteger(thread['authorId']),
        author: _string(thread['author']),
        typeName: _string(thread['typeName']),
      ),
      posts: _list(
        value['posts'],
      ).map(_map).map(_decodePost).toList(growable: false),
      readingOptions: _list(
        value['readingOptions'],
      ).map(_map).map(_decodeOption).toList(growable: false),
      cursor: _decodeCursor(_map(value['cursor'])),
      focusedPostId: _optionalInteger(value['focusedPostId']),
    );
  }

  Map<String, dynamic> encodeAnnouncement(ForumAnnouncement value) {
    return <String, dynamic>{
      'version': version,
      'kind': 'announcement',
      'id': value.id,
      'title': value.title,
      'metadataLabel': value.metadataLabel,
      'contentBlocks': value.contentBlocks
          .map(_encodeContentBlock)
          .toList(growable: false),
      'messageHtml': _sanitizeLegacyHtml(value.messageHtml),
      'sourceUri': _encodeForumUri(value.sourceUri),
    };
  }

  ForumAnnouncement decodeAnnouncement(Map<String, dynamic> value) {
    _expect(value, 'announcement');
    return ForumAnnouncement(
      id: _integer(value['id']),
      title: _string(value['title']),
      metadataLabel: _string(value['metadataLabel']),
      contentBlocks: _list(
        value['contentBlocks'],
      ).map(_map).map(_decodeContentBlock).toList(growable: false),
      messageHtml: _string(value['messageHtml']),
      sourceUri: _uri(value['sourceUri']),
    );
  }

  Map<String, dynamic> _encodeBoard(ForumBoardNode value) {
    return <String, dynamic>{
      'id': value.id,
      'parentId': value.parentId,
      'name': value.name,
      'description': value.description,
      'uri': _encodeForumUri(value.uri),
      'threadCount': value.threadCount,
      'postCount': value.postCount,
      'todayPostCount': value.todayPostCount,
      'children': value.children.map(_encodeBoard).toList(growable: false),
    };
  }

  ForumBoardNode _decodeBoard(Map<String, dynamic> value) {
    return ForumBoardNode(
      id: _integer(value['id']),
      parentId: _optionalInteger(value['parentId']),
      name: _string(value['name']),
      description: _string(value['description']),
      uri: _uri(value['uri']),
      threadCount: _integer(value['threadCount']),
      postCount: _integer(value['postCount']),
      todayPostCount: _integer(value['todayPostCount']),
      children: _list(
        value['children'],
      ).map(_map).map(_decodeBoard).toList(growable: false),
    );
  }

  Map<String, dynamic> _encodeThreadSummary(ForumThreadSummary value) {
    return <String, dynamic>{
      'id': value.id,
      'boardId': value.boardId,
      'title': value.title,
      'uri': _encodeForumUri(value.uri),
      'typeName': value.typeName,
      'summary': value.summary,
      'author': value.author,
      'authorId': value.authorId,
      'authorUri': _encodeProfileUri(value.authorUri, value.authorId),
      'avatarUri': _encodeOptionalForumUri(value.avatarUri),
      'timeLabel': value.timeLabel,
      'views': value.views,
      'replies': value.replies,
      'pinned': value.pinned,
      'digest': value.digest,
      'closed': value.closed,
      'special': value.special,
      'targetKind': value.targetKind.name,
    };
  }

  ForumThreadSummary _decodeThreadSummary(Map<String, dynamic> value) {
    return ForumThreadSummary(
      id: _integer(value['id']),
      boardId: _integer(value['boardId']),
      title: _string(value['title']),
      uri: _uri(value['uri']),
      typeName: _string(value['typeName']),
      summary: _string(value['summary']),
      author: _string(value['author']),
      authorId: _optionalInteger(value['authorId']),
      authorUri: _decodeProfileUri(
        value['authorUri'],
        _optionalInteger(value['authorId']),
      ),
      avatarUri: _optionalUri(value['avatarUri']),
      timeLabel: _string(value['timeLabel']),
      views: _integer(value['views']),
      replies: _integer(value['replies']),
      pinned: _boolean(value['pinned']),
      digest: _boolean(value['digest']),
      closed: _boolean(value['closed']),
      special: _boolean(value['special']),
      targetKind: ForumThreadTargetKind.values.byName(
        _string(value['targetKind']).isEmpty
            ? ForumThreadTargetKind.thread.name
            : _string(value['targetKind']),
      ),
    );
  }

  Map<String, dynamic> _encodeOption(ForumRouteOption value) {
    return <String, dynamic>{
      'key': value.key,
      'label': value.label,
      'uri': _encodeForumUri(value.uri),
      'selected': value.selected,
    };
  }

  ForumRouteOption _decodeOption(Map<String, dynamic> value) {
    return ForumRouteOption(
      key: _string(value['key']),
      label: _string(value['label']),
      uri: _uri(value['uri']),
      selected: _boolean(value['selected']),
    );
  }

  Map<String, dynamic> _encodeCursor(ForumPageCursor value) {
    return <String, dynamic>{
      'currentPage': value.currentPage,
      'totalPages': value.totalPages,
      'sourceUri': _encodeForumUri(value.sourceUri),
      'previousPageUri': _encodeOptionalForumUri(value.previousPageUri),
      'nextPageUri': _encodeOptionalForumUri(value.nextPageUri),
    };
  }

  ForumPageCursor _decodeCursor(Map<String, dynamic> value) {
    return ForumPageCursor(
      currentPage: _integer(value['currentPage']),
      totalPages: _integer(value['totalPages']),
      sourceUri: _uri(value['sourceUri']),
      previousPageUri: _optionalUri(value['previousPageUri']),
      nextPageUri: _optionalUri(value['nextPageUri']),
    );
  }

  ForumPost _decodePost(Map<String, dynamic> value) {
    final int id = _integer(value['id']);
    final int threadId = _integer(value['threadId']);
    final List<ForumPostComment> comments = _list(value['comments'])
        .map(_map)
        .map(_decodeComment)
        .toList(growable: false);
    if (comments.any(
      (ForumPostComment comment) =>
          comment.id <= 0 ||
          comment.threadId != threadId ||
          comment.postId != id ||
          comment.contentBlocks.isEmpty,
    )) {
      throw const ForumParseException('论坛缓存点评目标不一致');
    }
    return ForumPost(
      id: id,
      threadId: threadId,
      floor: _integer(value['floor']),
      authorId: _optionalInteger(value['authorId']),
      authorUri: _decodeProfileUri(
        value['authorUri'],
        _optionalInteger(value['authorId']),
      ),
      author: _string(value['author']),
      avatarUri: _optionalUri(value['avatarUri']),
      timeLabel: _string(value['timeLabel']),
      messageHtml: _string(value['messageHtml']),
      contentBlocks: _list(
        value['contentBlocks'],
      ).map(_map).map(_decodeContentBlock).toList(growable: false),
      comments: comments,
      ratingSummary: value['ratingSummary'] == null
          ? null
          : _decodeRatingSummary(_map(value['ratingSummary'])),
      uri: _uri(value['uri']),
      attachments: _list(value['attachments'])
          .map(_map)
          .map(
            (Map<String, dynamic> attachment) => ForumAttachment(
              id: _optionalInteger(attachment['id']),
              name: _string(attachment['name']),
              description: _string(attachment['description']),
              sizeLabel: _string(attachment['sizeLabel']),
              uri: _uri(attachment['uri']),
              isImage: _boolean(attachment['isImage']),
            ),
          )
          .toList(growable: false),
      isOriginalPoster: _boolean(value['isOriginalPoster']),
    );
  }

  Map<String, dynamic> _encodeComment(ForumPostComment value) {
    return <String, dynamic>{
      'id': value.id,
      'threadId': value.threadId,
      'postId': value.postId,
      'authorId': value.authorId,
      'authorUri': _encodeProfileUri(value.authorUri, value.authorId),
      'author': value.author,
      'avatarUri': _encodeOptionalForumUri(value.avatarUri),
      'timeLabel': value.timeLabel,
      'contentBlocks': value.contentBlocks
          .map(_encodeContentBlock)
          .toList(growable: false),
    };
  }

  ForumPostComment _decodeComment(Map<String, dynamic> value) {
    return ForumPostComment(
      id: _integer(value['id']),
      threadId: _integer(value['threadId']),
      postId: _integer(value['postId']),
      authorId: _optionalInteger(value['authorId']),
      authorUri: _decodeProfileUri(
        value['authorUri'],
        _optionalInteger(value['authorId']),
      ),
      author: _string(value['author']),
      avatarUri: _optionalUri(value['avatarUri']),
      timeLabel: _string(value['timeLabel']),
      contentBlocks: _list(
        value['contentBlocks'],
      ).map(_map).map(_decodeContentBlock).toList(growable: false),
    );
  }

  Map<String, dynamic> _encodeRatingSummary(ForumPostRatingSummary value) {
    return <String, dynamic>{
      'participantCount': value.participantCount,
      'totals': value.totals.map(_encodeRatingScore).toList(growable: false),
      'entries': value.entries
          .map(
            (ForumPostRatingEntry entry) => <String, dynamic>{
              'authorId': entry.authorId,
              'authorUri': _encodeProfileUri(entry.authorUri, entry.authorId),
              'author': entry.author,
              'avatarUri': _encodeOptionalForumUri(entry.avatarUri),
              'scores': entry.scores
                  .map(_encodeRatingScore)
                  .toList(growable: false),
              'reason': entry.reason,
              'timeLabel': entry.timeLabel,
            },
          )
          .toList(growable: false),
    };
  }

  ForumPostRatingSummary _decodeRatingSummary(Map<String, dynamic> value) {
    final int participantCount = _integer(value['participantCount']);
    final List<ForumPostRatingScore> totals = _list(
      value['totals'],
    ).map(_map).map(_decodeRatingScore).toList(growable: false);
    final List<ForumPostRatingEntry> entries = _list(value['entries'])
        .map(_map)
        .map(
          (Map<String, dynamic> entry) => ForumPostRatingEntry(
            authorId: _optionalInteger(entry['authorId']),
            authorUri: _decodeProfileUri(
              entry['authorUri'],
              _optionalInteger(entry['authorId']),
            ),
            author: _string(entry['author']),
            avatarUri: _optionalUri(entry['avatarUri']),
            scores: _list(
              entry['scores'],
            ).map(_map).map(_decodeRatingScore).toList(growable: false),
            reason: _string(entry['reason']),
            timeLabel: _string(entry['timeLabel']),
          ),
        )
        .toList(growable: false);
    if (participantCount <= 0 ||
        totals.isEmpty ||
        participantCount < entries.length ||
        entries.any(
          (ForumPostRatingEntry entry) =>
              entry.authorId == null ||
              entry.author.isEmpty ||
              entry.scores.length != totals.length ||
              !entry.scores.asMap().entries.every(
                (MapEntry<int, ForumPostRatingScore> score) =>
                    score.value.credit == totals[score.key].credit,
              ),
        )) {
      throw const ForumParseException('论坛缓存评分摘要无效');
    }
    return ForumPostRatingSummary(
      participantCount: participantCount,
      totals: totals,
      entries: entries,
    );
  }

  Map<String, dynamic> _encodeRatingScore(ForumPostRatingScore value) {
    return <String, dynamic>{'credit': value.credit, 'value': value.value};
  }

  ForumPostRatingScore _decodeRatingScore(Map<String, dynamic> value) {
    final String credit = _string(value['credit']);
    if (credit.isEmpty) {
      throw const ForumParseException('论坛缓存评分积分类型无效');
    }
    return ForumPostRatingScore(
      credit: credit,
      value: _integer(value['value']),
    );
  }

  Map<String, dynamic> _encodeContentBlock(ForumPostContentBlock value) {
    final String kind = switch (value) {
      ForumPostParagraphBlock() => 'paragraph',
      ForumPostQuoteBlock() => 'quote',
      ForumPostCodeBlock() => 'code',
    };
    return <String, dynamic>{
      'kind': kind,
      'inlines': value.inlines.map(_encodeInline).toList(growable: false),
    };
  }

  Map<String, dynamic> _encodeInline(ForumPostInline value) {
    return switch (value) {
      ForumPostTextInline() => <String, dynamic>{
        'kind': 'text',
        'text': value.text,
        'bold': value.bold,
        'italic': value.italic,
        'code': value.code,
      },
      ForumPostLineBreakInline() => <String, dynamic>{'kind': 'lineBreak'},
      ForumPostImageInline() => <String, dynamic>{
        'kind': 'image',
        'uri': _encodeForumContentUri(value.uri),
        'alt': value.alt,
        'isEmoticon': value.isEmoticon,
      },
      ForumPostLinkInline() => _encodeLink(value),
    };
  }

  Map<String, dynamic> _encodeLink(ForumPostLinkInline value) {
    final Uri? uri = _safeLinkUri(value.uri, value.kind);
    final bool invalidTarget =
        uri != null &&
        !_linkTargetMatches(
          uri,
          value.kind,
          threadId: value.threadId,
          postId: value.postId,
        );
    if (uri == null || invalidTarget) {
      return <String, dynamic>{
        'kind': 'text',
        'text': value.label,
        'bold': value.bold,
        'italic': value.italic,
        'code': value.code,
      };
    }
    final bool internal =
        value.kind == ForumPostLinkKind.internalThread ||
        value.kind == ForumPostLinkKind.internalPost;
    return <String, dynamic>{
      'kind': 'link',
      'label': value.label,
      'uri': uri.toString(),
      'linkKind': value.kind.name,
      'threadId': internal ? value.threadId : null,
      'postId': value.kind == ForumPostLinkKind.internalPost
          ? value.postId
          : null,
      'bold': value.bold,
      'italic': value.italic,
      'code': value.code,
    };
  }

  ForumPostContentBlock _decodeContentBlock(Map<String, dynamic> value) {
    final List<ForumPostInline> inlines = _list(
      value['inlines'],
    ).map(_map).map(_decodeInline).toList(growable: false);
    return switch (_string(value['kind'])) {
      'paragraph' => ForumPostParagraphBlock(inlines: inlines),
      'quote' => ForumPostQuoteBlock(inlines: inlines),
      'code' => ForumPostCodeBlock(inlines: inlines),
      _ => throw const ForumParseException('论坛缓存正文块无法识别'),
    };
  }

  ForumPostInline _decodeInline(Map<String, dynamic> value) {
    return switch (_string(value['kind'])) {
      'text' => ForumPostTextInline(
        text: _string(value['text']),
        bold: _boolean(value['bold']),
        italic: _boolean(value['italic']),
        code: _boolean(value['code']),
      ),
      'lineBreak' => const ForumPostLineBreakInline(),
      'image' => ForumPostImageInline(
        uri: _forumContentUri(value['uri']),
        alt: _string(value['alt']),
        isEmoticon: _boolean(value['isEmoticon']),
      ),
      'link' => _decodeLink(value),
      _ => throw const ForumParseException('论坛缓存正文节点无法识别'),
    };
  }

  ForumPostLinkInline _decodeLink(Map<String, dynamic> value) {
    final ForumPostLinkKind kind = switch (_string(value['linkKind'])) {
      'internalThread' => ForumPostLinkKind.internalThread,
      'internalPost' => ForumPostLinkKind.internalPost,
      'download' => ForumPostLinkKind.download,
      'external' => ForumPostLinkKind.external,
      _ => throw const ForumParseException('论坛缓存正文链接无法识别'),
    };
    final int? threadId = _optionalInteger(value['threadId']);
    final int? postId = _optionalInteger(value['postId']);
    final Uri? uri = _safeLinkUri(Uri.tryParse(_string(value['uri'])), kind);
    final bool invalidTarget =
        uri != null &&
        !_linkTargetMatches(uri, kind, threadId: threadId, postId: postId);
    if (uri == null || invalidTarget) {
      throw const ForumParseException('论坛缓存正文 URI 不安全');
    }
    return ForumPostLinkInline(
      label: _string(value['label']),
      uri: uri,
      kind: kind,
      threadId: threadId,
      postId: postId,
      bold: _boolean(value['bold']),
      italic: _boolean(value['italic']),
      code: _boolean(value['code']),
    );
  }

  String _encodeForumContentUri(Uri value) {
    return _forumContentUri(value).toString();
  }

  String _encodeForumUri(Uri value) {
    if (!_isForumUri(value)) {
      throw const ForumParseException('论坛缓存 URI 不安全');
    }
    return _withoutSensitiveParts(value).toString();
  }

  String? _encodeOptionalForumUri(Uri? value) {
    return value == null ? null : _encodeForumUri(value);
  }

  String? _encodeProfileUri(Uri? value, int? expectedUserId) {
    if (value == null) {
      return null;
    }
    final Uri uri = _withoutSensitiveParts(value);
    if (!_isProfileUri(uri, expectedUserId)) {
      throw const ForumParseException('论坛缓存个人资料 URI 与作者不一致');
    }
    return uri.toString();
  }

  Uri? _decodeProfileUri(Object? value, int? expectedUserId) {
    if (_string(value).isEmpty) {
      return null;
    }
    final Uri? uri = _optionalUri(value);
    if (uri == null || !_isProfileUri(uri, expectedUserId)) {
      throw const ForumParseException('论坛缓存个人资料 URI 与作者不一致');
    }
    return uri;
  }

  bool _isProfileUri(Uri uri, int? expectedUserId) {
    if (expectedUserId == null ||
        expectedUserId <= 0 ||
        !_isForumUri(uri) ||
        uri.path != '/home.php' ||
        uri.fragment.isNotEmpty ||
        _singleParameter(uri, 'mod') != 'space' ||
        (_singleParameter(uri, 'do') != null &&
            _singleParameter(uri, 'do') != 'profile') ||
        _singleParameter(uri, 'mobile') != '2' ||
        _singlePositiveInteger(uri, 'uid') != expectedUserId) {
      return false;
    }
    const Set<String> allowed = <String>{'mod', 'do', 'uid', 'mobile'};
    return uri.queryParametersAll.entries.every(
      (MapEntry<String, List<String>> entry) =>
          allowed.contains(entry.key) && entry.value.length == 1,
    );
  }

  Uri _forumContentUri(Object? value) {
    final Uri? source = value is Uri ? value : Uri.tryParse(_string(value));
    if (source == null || !_isForumUri(source)) {
      throw const ForumParseException('论坛缓存正文 URI 不安全');
    }
    return _withoutSensitiveParts(source);
  }

  Uri? _safeLinkUri(Uri? value, ForumPostLinkKind kind) {
    if (value == null ||
        !const <String>{'http', 'https'}.contains(value.scheme) ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty) {
      return null;
    }
    if (kind == ForumPostLinkKind.external) {
      return _isForumUri(value) || _hasSensitiveParts(value) ? null : value;
    }
    if (!_isForumUri(value)) {
      return null;
    }
    final Uri uri = _withoutSensitiveParts(value);
    if (kind == ForumPostLinkKind.download && !_isAttachmentUri(uri)) {
      return null;
    }
    return uri;
  }

  bool _linkTargetMatches(
    Uri uri,
    ForumPostLinkKind kind, {
    required int? threadId,
    required int? postId,
  }) {
    if (kind == ForumPostLinkKind.external ||
        kind == ForumPostLinkKind.download) {
      return threadId == null && postId == null;
    }
    final ({int? threadId, int? postId})? target = _internalTarget(uri);
    if (target == null || target.threadId != threadId) {
      return false;
    }
    return kind == ForumPostLinkKind.internalThread
        ? threadId != null && postId == null && target.postId == null
        : postId != null && target.postId == postId;
  }

  ({int? threadId, int? postId})? _internalTarget(Uri uri) {
    final int? fragmentPostId = int.tryParse(
      RegExp(
            r'(?:^|[?&])(?:pid|post[_-]?)(\d+)(?:$|[&])',
            caseSensitive: false,
          ).firstMatch(uri.fragment)?.group(1) ??
          '',
    );
    final Match? rewritten = RegExp(
      r'(?:^|/)thread-(\d+)(?:-\d+)*\.html$',
      caseSensitive: false,
    ).firstMatch(uri.path);
    final int? rewrittenThreadId = int.tryParse(rewritten?.group(1) ?? '');
    if (rewrittenThreadId != null && rewrittenThreadId > 0) {
      return (threadId: rewrittenThreadId, postId: fragmentPostId);
    }

    final String mod = _singleParameter(uri, 'mod')?.toLowerCase() ?? '';
    final String goto = _singleParameter(uri, 'goto')?.toLowerCase() ?? '';
    if (uri.path == '/forum.php' && mod == 'viewthread') {
      final int? threadId = _singlePositiveInteger(uri, 'tid');
      if (threadId == null) {
        return null;
      }
      return (
        threadId: threadId,
        postId: _singlePositiveInteger(uri, 'pid') ?? fragmentPostId,
      );
    }
    final bool findPost =
        (uri.path == '/forum.php' && mod == 'redirect' && goto == 'findpost') ||
        (uri.path == '/redirect.php' && goto == 'findpost');
    if (!findPost) {
      return null;
    }
    final int? postId = _singlePositiveInteger(uri, 'pid') ?? fragmentPostId;
    if (postId == null) {
      return null;
    }
    return (
      threadId:
          _singlePositiveInteger(uri, 'ptid') ??
          _singlePositiveInteger(uri, 'tid'),
      postId: postId,
    );
  }

  String? _singleParameter(Uri uri, String name) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single : null;
  }

  int? _singlePositiveInteger(Uri uri, String name) {
    final int? value = int.tryParse(_singleParameter(uri, name) ?? '');
    return value != null && value > 0 ? value : null;
  }

  bool _isForumUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'bbs.yamibo.com' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;

  bool _isAttachmentUri(Uri uri) {
    if (uri.path.toLowerCase().startsWith('/data/attachment/')) {
      return true;
    }
    final String mod = uri.queryParameters['mod']?.toLowerCase() ?? '';
    return uri.path.toLowerCase() == '/forum.php' &&
        (mod == 'attachment' || mod == 'image') &&
        (_optionalInteger(uri.queryParameters['aid']) ?? 0) > 0;
  }

  Uri _withoutSensitiveParts(Uri uri) {
    final List<String> query = uri.query
        .split(RegExp(r'[&;]'))
        .where(
          (String component) =>
              component.isNotEmpty && !_isSensitiveKey(_queryName(component)),
        )
        .toList(growable: false);
    return uri.replace(
      query: query.join('&'),
      fragment: _hasSensitiveFragment(uri.fragment) ? '' : uri.fragment,
    );
  }

  bool _hasSensitiveParts(Uri uri) {
    return uri.query
            .split(RegExp(r'[&;]'))
            .any(
              (String component) => _isSensitiveKey(_queryName(component)),
            ) ||
        _hasSensitiveFragment(uri.fragment) ||
        RegExp(
          r';(?:jsessionid|phpsessid|sessionid|sid)=',
          caseSensitive: false,
        ).hasMatch(uri.path);
  }

  bool _hasSensitiveFragment(String value) {
    return _decode(value)
        .split(RegExp(r'[?&;]'))
        .any(
          (String component) =>
              component.contains('=') && _isSensitiveKey(_queryName(component)),
        );
  }

  String _queryName(String component) {
    final int separator = component.indexOf('=');
    final String source = separator < 0
        ? component
        : component.substring(0, separator);
    return _decode(source).toLowerCase();
  }

  String _decode(String value) {
    try {
      return Uri.decodeQueryComponent(value);
    } on FormatException {
      return value;
    }
  }

  bool _isSensitiveKey(String key) {
    final String normalized = key.toLowerCase();
    return const <String>{
          'formhash',
          'loginhash',
          'auth',
          'authkey',
          'authorization',
          'api_key',
          'apikey',
          'client_secret',
          'code',
          'token',
          'access_token',
          'id_token',
          'oauth_token',
          'refresh_token',
          'password',
          'passwd',
          'cookie',
          'credential',
          'session',
          'sessionid',
          'sid',
          'signature',
          'sig',
          'secret',
          'ticket',
          'x-amz-credential',
          'x-amz-security-token',
          'x-amz-signature',
        }.contains(normalized) ||
        normalized.endsWith('_token');
  }

  String _sanitizeLegacyHtml(String value) {
    final dom.DocumentFragment fragment = html_parser.parseFragment(value);
    for (final dom.Element element
        in fragment
            .querySelectorAll(
              'script, style, noscript, form, input, button, select, textarea, '
              'iframe, object, embed',
            )
            .toList(growable: false)) {
      element.remove();
    }
    for (final dom.Element element
        in fragment.querySelectorAll('*').toList(growable: false)) {
      element.attributes.clear();
    }
    return fragment.outerHtml.trim();
  }

  void _expect(Map<String, dynamic> value, String kind) {
    if (_integer(value['version']) != version || value['kind'] != kind) {
      throw const ForumParseException('论坛缓存版本无法识别');
    }
  }

  List<Object?> _list(Object? value) =>
      value is List ? value : const <Object?>[];

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        entry.key.toString(): entry.value,
    };
  }

  String _string(Object? value) => value?.toString() ?? '';

  int _integer(Object? value) {
    return value is num ? value.toInt() : int.tryParse(_string(value)) ?? 0;
  }

  int? _optionalInteger(Object? value) {
    final int parsed = _integer(value);
    return parsed > 0 ? parsed : null;
  }

  bool _boolean(Object? value) => value == true || value == 1;

  Uri _uri(Object? value) {
    final Uri? parsed = _optionalUri(value);
    if (parsed == null) {
      throw const ForumParseException('论坛缓存 URI 无效');
    }
    return parsed;
  }

  Uri? _optionalUri(Object? value) {
    final String source = _string(value);
    if (source.isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(source);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'bbs.yamibo.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        _hasSensitiveParts(uri)) {
      throw const ForumParseException('论坛缓存 URI 不安全');
    }
    return uri;
  }
}
