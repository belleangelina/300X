import 'package:html/dom.dart' as dom;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_page_classifier.dart';
import 'package:x300/features/forum/data/forum_post_content_parser.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';

class ForumTopicParser {
  const ForumTopicParser({
    this.originPolicy = const ForumOriginPolicy(),
    this.pageClassifier = const ForumPageClassifier(),
  });

  final ForumOriginPolicy originPolicy;
  final ForumPageClassifier pageClassifier;

  ForumThreadPage parse(
    String html,
    Uri pageUri, {
    int? expectedThreadId,
    int? expectedBoardId,
    int? focusedPostId,
  }) {
    final dom.Document document = pageClassifier.requireKind(
      html,
      pageUri,
      ForumMobilePageKind.topic,
    );
    if (document.querySelector('.viewthread') == null ||
        document.querySelector('.view_tit') == null) {
      throw const ForumParseException('主题移动模板结构已变更');
    }

    final int? sourceThreadId = queryInt(pageUri, 'tid');
    final int? documentThreadId = _documentThreadId(document, pageUri);
    final int? threadId =
        expectedThreadId ?? sourceThreadId ?? documentThreadId;
    if (threadId == null || threadId <= 0) {
      throw const ForumParseException('主题页缺少 tid');
    }
    for (final int? actual in <int?>[sourceThreadId, documentThreadId]) {
      if (actual != null && actual != threadId) {
        throw const ForumParseException('主题页 tid 不一致');
      }
    }

    final int? documentBoardId = _documentBoardId(document, pageUri);
    final int? boardId = expectedBoardId ?? documentBoardId;
    if (boardId == null || boardId <= 0) {
      throw const ForumParseException('主题页缺少 fid');
    }
    if (documentBoardId != null && documentBoardId != boardId) {
      throw const ForumParseException('主题页 fid 不一致');
    }

    final dom.Element titleElement = document.querySelector('.view_tit')!;
    final String typeName = _typeName(titleElement);
    final String title = _threadTitle(titleElement, typeName);
    if (title.isEmpty) {
      throw const ForumParseException('主题页缺少标题');
    }

    final ForumPageCursor cursor = _parseCursor(document, pageUri, threadId);
    final int? originalAuthorId = _originalAuthorId(
      document,
      pageUri,
      threadId,
    );
    final List<dom.Element> postElements = document.querySelectorAll(
      '.plc.cl[id^="pid"], .plc[id^="pid"]',
    );
    if (postElements.isEmpty) {
      throw const ForumParseException('主题页中没有可识别的楼层');
    }
    final List<ForumPost> posts = <ForumPost>[];
    final Set<int> seenPostIds = <int>{};
    for (final dom.Element element in postElements) {
      final ForumPost post = _parsePost(
        element,
        pageUri,
        boardId,
        threadId,
        originalAuthorId,
      );
      if (!seenPostIds.add(post.id)) {
        throw const ForumParseException('主题页包含重复 pid');
      }
      posts.add(post);
    }

    final int? resolvedFocus =
        focusedPostId ??
        queryInt(pageUri, 'pid') ??
        _fragmentPostId(pageUri.fragment);
    if (resolvedFocus != null && !seenPostIds.contains(resolvedFocus)) {
      throw ForumParseException('主题页未返回指定楼层 pid=$resolvedFocus');
    }
    ForumPost? originalPost;
    for (final ForumPost post in posts) {
      if (post.floor == 1 ||
          (originalAuthorId != null && post.authorId == originalAuthorId)) {
        originalPost = post;
        break;
      }
    }

    return ForumThreadPage(
      thread: ForumThread(
        id: threadId,
        boardId: boardId,
        title: title,
        uri: pageUri,
        author: originalPost?.author ?? '',
        authorId: originalAuthorId ?? originalPost?.authorId,
        typeName: typeName,
      ),
      posts: List<ForumPost>.unmodifiable(posts),
      readingOptions: _parseReadingOptions(document, pageUri, threadId),
      cursor: cursor,
      replyUri: _findThreadAction(
        document,
        pageUri,
        '.foot.foot_reply a[href*="mod=post"][href*="action=reply"]'
        '[href*="tid="], '
        '.viewt-reply[href*="mod=post"][href*="action=reply"]'
        '[href*="tid="]',
        (Uri uri) =>
            uri.path == '/forum.php' &&
            _singleParameter(uri, 'mod') == 'post' &&
            _singleParameter(uri, 'action') == 'reply' &&
            _singlePositiveInteger(uri, 'tid') == threadId &&
            _singlePositiveInteger(uri, 'fid') == boardId &&
            (_singlePositiveInteger(uri, 'page') ?? 0) > 0 &&
            (_singlePositiveInteger(uri, 'reppost') ?? 0) > 0 &&
            _hasOnlyParameters(
              uri,
              const <String>{
                'mod', 'action', 'fid', 'tid', 'page', 'reppost', 'mobile',
              },
            ) &&
            !uri.queryParametersAll.containsKey('repquote'),
      ),
      favoriteUri: _findThreadAction(
        document,
        pageUri,
        '.foot.foot_reply a[href*="ac=favorite"][href*="type=thread"], '
        '.foot.foot_reply .favbtn[href*="type=thread"]',
        (Uri uri) =>
            _isSpaceControl(uri, 'favorite', 'thread') &&
            _hasOnlyParameters(
              uri,
              const <String>{'mod', 'ac', 'type', 'id', 'mobile'},
            ) &&
            _singlePositiveInteger(uri, 'id') == threadId,
      ),
      shareUri: _findThreadAction(
        document,
        pageUri,
        '.foot.foot_reply a[href*="ac=share"][href*="type=thread"]',
        (Uri uri) =>
            _isSpaceControl(uri, 'share', 'thread') &&
            _hasOnlyParameters(
              uri,
              const <String>{'mod', 'ac', 'type', 'id', 'mobile'},
            ) &&
            _singlePositiveInteger(uri, 'id') == threadId,
      ),
      focusedPostId: resolvedFocus,
    );
  }

  ForumPost _parsePost(
    dom.Element element,
    Uri pageUri,
    int boardId,
    int threadId,
    int? originalAuthorId,
  ) {
    final Match? idMatch = RegExp(r'^pid(\d+)$').firstMatch(element.id);
    final int? postId = int.tryParse(idMatch?.group(1) ?? '');
    if (postId == null || postId <= 0) {
      throw const ForumParseException('主题楼层缺少有效 pid');
    }
    final String floorLabel = normalizeForumText(
      element.querySelector('.authi li.mtit .y')?.text ?? '',
    );
    final int? floor = int.tryParse(
      RegExp(r'(\d+)').firstMatch(floorLabel)?.group(1) ?? '',
    );
    if (floor == null || floor <= 0) {
      throw ForumParseException('楼层 pid=$postId 缺少楼层号');
    }
    final dom.Element? message = element.querySelector(
      '.message, .locked, .post-message, .tip',
    );
    if (message == null) {
      throw ForumParseException('楼层 pid=$postId 缺少正文或权限提示');
    }

    final dom.Element? authorAnchor = element.querySelector('.authi .z a');
    final Uri? authorUri = _profileUri(
      pageUri,
      authorAnchor?.attributes['href'],
    );
    final int? authorId = authorUri == null ? null : queryInt(authorUri, 'uid');
    final ForumPostContentParser contentParser = ForumPostContentParser(
      originPolicy: originPolicy,
    );
    final ForumPostContentParseResult content = contentParser.parse(
      message,
      pageUri,
    );
    final ({ForumPostRatingSummary? summary, Uri? uri}) rating = _parseRatings(
      element,
      pageUri,
      threadId,
      postId,
      contentParser,
    );
    return ForumPost(
      id: postId,
      threadId: threadId,
      floor: floor,
      author: normalizeForumText(authorAnchor?.text ?? ''),
      authorId: authorId,
      authorUri: authorUri,
      avatarUri: contentParser.resolveSameOriginResource(
        pageUri,
        element.querySelector('.avatar img')?.attributes['src'],
      ),
      timeLabel: directText(element.querySelector('.authi li.mtime')),
      messageHtml: content.sanitizedHtml,
      uri: _postUri(element, pageUri, threadId, postId),
      attachments: _parseAttachments(element, pageUri),
      contentBlocks: content.blocks,
      comments: _parseComments(
        element,
        pageUri,
        threadId,
        postId,
        contentParser,
      ),
      ratingSummary: rating.summary,
      quoteUri: _findPostAction(
        element,
        pageUri,
        '.replybtn a[href*="mod=post"][href*="action=reply"], '
        '.threadlist_foot a[href*="mod=post"][href*="action=reply"]',
        (Uri uri) =>
            uri.path == '/forum.php' &&
            _singleParameter(uri, 'mod') == 'post' &&
            _singleParameter(uri, 'action') == 'reply' &&
            _singlePositiveInteger(uri, 'tid') == threadId &&
            _hasOnlyParameters(
              uri,
              const <String>{
                'mod', 'action', 'fid', 'tid', 'page', 'repquote', 'extra',
                'mobile',
              },
            ) &&
            _singlePositiveInteger(uri, 'fid') == boardId &&
            _matchesPageExtra(uri) &&
            _singlePositiveInteger(uri, 'repquote') == postId,
      ),
      rateUri: _findPostAction(
        element,
        pageUri,
        '.threadlist_foot a[href*="mod=misc"][href*="action=rate"]',
        (Uri uri) =>
            uri.path == '/forum.php' &&
            _singleParameter(uri, 'mod') == 'misc' &&
            _singleParameter(uri, 'action') == 'rate' &&
            _singlePositiveInteger(uri, 'tid') == threadId &&
            _hasOnlyParameters(
              uri,
              const <String>{'mod', 'action', 'tid', 'pid', 'mobile'},
            ) &&
            _singlePositiveInteger(uri, 'pid') == postId,
      ),
      commentUri: _findPostAction(
        element,
        pageUri,
        '.threadlist_foot a[href*="mod=misc"][href*="action=comment"]',
        (Uri uri) =>
            uri.path == '/forum.php' &&
            _singleParameter(uri, 'mod') == 'misc' &&
            _singleParameter(uri, 'action') == 'comment' &&
            _singlePositiveInteger(uri, 'tid') == threadId &&
            _hasOnlyParameters(
              uri,
              const <String>{'mod', 'action', 'tid', 'pid', 'mobile'},
            ) &&
            _singlePositiveInteger(uri, 'pid') == postId,
      ),
      ratingsUri: rating.uri,
      editUri: _findPostAction(
        element,
        pageUri,
        'em.mgl > a[href*="mod=post"][href*="action=edit"], '
        'div.manage_popup > a.button[href*="mod=post"][href*="action=edit"]',
        (Uri uri) =>
            uri.path == '/forum.php' &&
            _singleParameter(uri, 'mod') == 'post' &&
            _singleParameter(uri, 'action') == 'edit' &&
            _singlePositiveInteger(uri, 'fid') == boardId &&
            _singlePositiveInteger(uri, 'tid') == threadId &&
            _singlePositiveInteger(uri, 'pid') == postId &&
            _singlePositiveInteger(uri, 'page') != null &&
            _hasOnlyParameters(
              uri,
              const <String>{
                'mod', 'action', 'fid', 'tid', 'pid', 'page', 'mobile',
              },
            ),
      ),
      isOriginalPoster:
          floor == 1 ||
          (originalAuthorId != null && authorId == originalAuthorId),
    );
  }

  List<ForumAttachment> _parseAttachments(dom.Element post, Uri pageUri) {
    final List<ForumAttachment> result = <ForumAttachment>[];
    final Set<String> seen = <String>{};
    final ForumPostContentParser contentParser = ForumPostContentParser(
      originPolicy: originPolicy,
    );

    for (final dom.Element image in post.querySelectorAll(
      '.message img, .img_one img, .attachlist img, .attachment img',
    )) {
      final String source =
          image.attributes['zoomfile'] ??
          image.attributes['file'] ??
          image.attributes['data-original'] ??
          image.attributes['src'] ??
          '';
      final Uri? uri = contentParser.resolveSameOriginResource(pageUri, source);
      if (!_isAttachmentUri(uri)) {
        continue;
      }
      final int? attachmentId = _attachmentId(uri!, image.id);
      final String key = '${attachmentId ?? 0}:${uri.toString()}';
      if (!seen.add(key)) {
        continue;
      }
      final dom.Element context = image.parent ?? image;
      result.add(
        ForumAttachment(
          id: attachmentId,
          name: _attachmentName(image.attributes['alt'], uri),
          description: normalizeForumText(
            context.querySelector('.attach_info, .description')?.text ?? '',
          ),
          sizeLabel: _sizeLabel(context.text),
          uri: uri,
          isImage: true,
        ),
      );
    }

    for (final dom.Element anchor in post.querySelectorAll(
      '.attachlist a[href], .attachment a[href], '
      'a[href*="mod=attachment"], a[href*="aid="]',
    )) {
      final String? href = anchor.attributes['href'];
      final Uri? uri = contentParser.resolveSameOriginResource(pageUri, href);
      if (!_isAttachmentUri(uri)) {
        continue;
      }
      final int? attachmentId = _attachmentId(uri!, anchor.id);
      final String key = '${attachmentId ?? 0}:${uri.toString()}';
      if (!seen.add(key)) {
        continue;
      }
      final dom.Element context = anchor.parent ?? anchor;
      result.add(
        ForumAttachment(
          id: attachmentId,
          name: _attachmentName(anchor.text, uri),
          description: normalizeForumText(
            context.querySelector('.attach_info, .description')?.text ?? '',
          ),
          sizeLabel: _sizeLabel(context.text),
          uri: uri,
          isImage: _looksLikeImage(uri),
        ),
      );
    }
    return List<ForumAttachment>.unmodifiable(result);
  }

  List<ForumRouteOption> _parseReadingOptions(
    dom.Document document,
    Uri pageUri,
    int threadId,
  ) {
    final List<ForumRouteOption> result = <ForumRouteOption>[];
    final Set<String> seenKeys = <String>{};
    for (final dom.Element anchor in document.querySelectorAll(
      'a[href*="mod=viewthread"][href*="tid="]',
    )) {
      final Uri? uri = originPolicy.resolveMobile(
        pageUri,
        anchor.attributes['href'],
      );
      if (uri == null || queryInt(uri, 'tid') != threadId) {
        continue;
      }
      if (_parameter(uri, 'authorid').isEmpty &&
          _parameter(uri, 'ordertype').isEmpty) {
        continue;
      }
      final String label = normalizeForumText(anchor.text);
      if (label.isEmpty) {
        continue;
      }
      final String key = _readingKey(uri);
      if (!seenKeys.add(key)) {
        continue;
      }
      result.add(
        ForumRouteOption(
          key: key,
          label: label,
          uri: uri,
          selected: _isSelected(anchor) || key == _readingKey(pageUri),
        ),
      );
    }
    return List<ForumRouteOption>.unmodifiable(result);
  }

  ForumPageCursor _parseCursor(
    dom.Document document,
    Uri pageUri,
    int threadId,
  ) {
    final dom.Element? pagination = document.querySelector('.pg');
    int currentPage =
        int.tryParse(
          pagination
                  ?.querySelector('input[name="custompage"]')
                  ?.attributes['value'] ??
              '',
        ) ??
        int.tryParse(
          normalizeForumText(pagination?.querySelector('strong')?.text ?? ''),
        ) ??
        queryInt(pageUri, 'page') ??
        1;
    if (currentPage <= 0) {
      currentPage = 1;
    }
    int totalPages = currentPage;
    final dom.Element? last = pagination?.querySelector(
      'a.last[href*="page="]',
    );
    if (last != null) {
      final Uri lastUri = _requireTopicPageLink(last, pageUri, threadId);
      totalPages = queryInt(lastUri, 'page') ?? totalPages;
    }
    final String totalLabel =
        pagination?.querySelector('label span')?.attributes['title'] ?? '';
    totalPages =
        int.tryParse(RegExp(r'(\d+)').firstMatch(totalLabel)?.group(1) ?? '') ??
        totalPages;
    if (totalPages < currentPage) {
      totalPages = currentPage;
    }
    return ForumPageCursor(
      currentPage: currentPage,
      totalPages: totalPages,
      sourceUri: pageUri,
      previousPageUri: _optionalTopicPageLink(
        _previousAnchor(pagination),
        pageUri,
        threadId,
      ),
      nextPageUri: _optionalTopicPageLink(
        pagination?.querySelector('a.nxt[href]'),
        pageUri,
        threadId,
      ),
    );
  }

  Uri? _optionalTopicPageLink(dom.Element? anchor, Uri pageUri, int threadId) {
    return anchor == null
        ? null
        : _requireTopicPageLink(anchor, pageUri, threadId);
  }

  Uri _requireTopicPageLink(dom.Element anchor, Uri pageUri, int threadId) {
    final Uri? uri = originPolicy.resolveMobile(
      pageUri,
      anchor.attributes['href'],
    );
    if (uri == null ||
        queryInt(uri, 'tid') != threadId ||
        _parameter(uri, 'mod') != 'viewthread' ||
        (queryInt(uri, 'page') ?? 0) <= 0) {
      throw const ForumParseException('主题分页地址无效');
    }
    return uri;
  }

  dom.Element? _previousAnchor(dom.Element? pagination) {
    final dom.Element? byClass = pagination?.querySelector(
      'a.prev[href], a[class*="prev"][href]',
    );
    if (byClass != null) {
      return byClass;
    }
    for (final dom.Element anchor
        in pagination?.querySelectorAll('a[href]') ?? const <dom.Element>[]) {
      if (normalizeForumText(anchor.text).contains('上一页')) {
        return anchor;
      }
    }
    return null;
  }

  Uri? _findThreadAction(
    dom.Document document,
    Uri pageUri,
    String selector,
    bool Function(Uri uri) matches,
  ) {
    for (final dom.Element anchor in document.querySelectorAll(selector)) {
      if (_isInsidePost(anchor)) {
        continue;
      }
      final Uri? uri = _resolveAction(pageUri, anchor);
      if (uri != null && matches(uri)) {
        return uri;
      }
    }
    return null;
  }

  Uri? _findPostAction(
    dom.Element post,
    Uri pageUri,
    String selector,
    bool Function(Uri uri) matches,
  ) {
    final int? postId = int.tryParse(
      RegExp(r'^pid(\d+)$').firstMatch(post.id)?.group(1) ?? '',
    );
    if (postId == null) {
      return null;
    }
    for (final dom.Element anchor in post.querySelectorAll(selector)) {
      if (!_isTrustedPostActionAnchor(anchor, post, postId)) {
        continue;
      }
      final Uri? uri = _resolveAction(pageUri, anchor);
      if (uri != null && matches(uri)) {
        return uri;
      }
    }
    return null;
  }

  Uri? _resolveAction(Uri pageUri, dom.Element anchor) {
    final String? href = anchor.attributes['href'];
    final Uri? uri = originPolicy.resolveAllowed(pageUri, href);
    if (href != null && href.trim().isNotEmpty && uri == null) {
      throw const ForumActionSecurityException();
    }
    if (uri == null) {
      return null;
    }
    return _hasUniqueActionParameters(uri) &&
            _singleParameter(uri, 'mobile') == '2'
        ? uri
        : null;
  }

  bool _hasUniqueActionParameters(Uri uri) {
    if (!originPolicy.hasNoAliasedQueryParameters(
      uri,
      const <String>{
        'mod', 'action', 'ac', 'op', 'type', 'mobile', 'fid', 'tid', 'pid',
        'id', 'favid', 'repquote', 'reppost', 'rid',
      },
    )) {
      return false;
    }
    for (final String name in const <String>[
      'mod',
      'action',
      'ac',
      'op',
      'type',
      'mobile',
      'fid',
      'tid',
      'pid',
      'id',
      'favid',
      'repquote',
      'reppost',
      'rid',
    ]) {
      if ((uri.queryParametersAll[name] ?? const <String>[]).length > 1) {
        return false;
      }
    }
    return true;
  }

  bool _hasOnlyParameters(Uri uri, Set<String> allowed) {
    return uri.queryParametersAll.keys.every(allowed.contains);
  }

  bool _matchesPageExtra(Uri uri) {
    final int? page = _singlePositiveInteger(uri, 'page');
    return page != null && _singleParameter(uri, 'extra') == 'page=$page';
  }

  bool _isSpaceControl(Uri uri, String action, String type) {
    return uri.path == '/home.php' &&
        _singleParameter(uri, 'mod') == 'spacecp' &&
        _singleParameter(uri, 'ac') == action &&
        _singleParameter(uri, 'type') == type;
  }

  Uri _postUri(dom.Element post, Uri pageUri, int threadId, int postId) {
    for (final dom.Element anchor in post.querySelectorAll(
      'a[href*="goto=findpost"][href*="pid="]',
    )) {
      final Uri? uri = originPolicy.resolveAllowed(
        pageUri,
        anchor.attributes['href'],
      );
      if (uri != null &&
          queryInt(uri, 'pid') == postId &&
          (queryInt(uri, 'ptid') ?? threadId) == threadId) {
        return uri;
      }
    }
    return pageUri.replace(fragment: 'pid$postId');
  }

  int? _documentThreadId(dom.Document document, Uri pageUri) {
    final dom.Element? canonical = document.querySelector(
      'link[rel="canonical"][href]',
    );
    final int? canonicalId = _threadIdFromUri(
      originPolicy.resolveAllowed(pageUri, canonical?.attributes['href']),
    );
    if (canonicalId != null) {
      return canonicalId;
    }
    for (final dom.Element anchor in document.querySelectorAll(
      'a[href*="mod=viewthread"][href*="tid="], '
      'a[href*="action=reply"][href*="tid="]',
    )) {
      if (_isInsidePostContent(anchor)) {
        continue;
      }
      final int? value = _threadIdFromUri(
        originPolicy.resolveAllowed(pageUri, anchor.attributes['href']),
      );
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  bool _isInsidePostContent(dom.Element element) {
    dom.Element? ancestor = element.parent;
    while (ancestor != null) {
      if (ancestor.classes.any(
        (String value) => const <String>{
          'message',
          'post-message',
          'locked',
          'tip',
        }.contains(value),
      )) {
        return true;
      }
      ancestor = ancestor.parent;
    }
    return false;
  }

  bool _isInsidePost(dom.Element element) {
    dom.Element? ancestor = element.parent;
    while (ancestor != null) {
      if (RegExp(r'^pid\d+$').hasMatch(ancestor.id)) {
        return true;
      }
      ancestor = ancestor.parent;
    }
    return false;
  }

  bool _isTrustedPostActionAnchor(
    dom.Element anchor,
    dom.Element post,
    int postId,
  ) {
    if (_isInsidePostContent(anchor) ||
        _isInsidePostInteractionOrAttachment(anchor, post, postId)) {
      return false;
    }
    dom.Element? ancestor = anchor.parent;
    while (ancestor != null && ancestor != post) {
      if (ancestor.classes.contains('threadlist_foot')) {
        return ancestor.parent == post;
      }
      if (ancestor.classes.contains('replybtn')) {
        return ancestor.id == 'replybtn_$postId' &&
            !_isInsidePostContent(anchor);
      }
      if (ancestor.localName == 'em' && ancestor.classes.contains('mgl')) {
        return anchor.parent == ancestor;
      }
      if (ancestor.localName == 'div' &&
          ancestor.classes.contains('manage_popup')) {
        return anchor.parent == ancestor && anchor.classes.contains('button');
      }
      ancestor = ancestor.parent;
    }
    return false;
  }

  bool _isInsidePostInteractionOrAttachment(
    dom.Element element,
    dom.Element post,
    int postId,
  ) {
    dom.Element? ancestor = element.parent;
    while (ancestor != null && ancestor != post) {
      if (ancestor.id == 'comment_$postId' ||
          ancestor.id == 'ratelog_$postId' ||
          ancestor.classes.any(
            (String value) => const <String>{
              'attachlist',
              'attachment',
              'img_one',
              'post_box',
            }.contains(value),
          )) {
        return true;
      }
      ancestor = ancestor.parent;
    }
    return false;
  }

  int? _threadIdFromUri(Uri? uri) {
    if (uri == null) {
      return null;
    }
    return queryInt(uri, 'tid') ??
        int.tryParse(
          RegExp(r'(?:thread|forum)-(\d+)').firstMatch(uri.path)?.group(1) ??
              '',
        );
  }

  int? _documentBoardId(dom.Document document, Uri pageUri) {
    for (final dom.Element anchor in document.querySelectorAll(
      '.header h2 a[href*="fid="], '
      'a[href*="action=reply"][href*="fid="], '
      'a[href*="mod=forumdisplay"][href*="fid="]',
    )) {
      final Uri? uri = originPolicy.resolveAllowed(
        pageUri,
        anchor.attributes['href'],
      );
      final int? boardId = uri == null ? null : queryInt(uri, 'fid');
      if (boardId != null && boardId > 0) {
        return boardId;
      }
    }
    return null;
  }

  int? _originalAuthorId(dom.Document document, Uri pageUri, int threadId) {
    for (final dom.Element anchor in document.querySelectorAll(
      'a[href*="mod=viewthread"][href*="authorid="]',
    )) {
      final Uri? uri = originPolicy.resolveMobile(
        pageUri,
        anchor.attributes['href'],
      );
      final int? authorId = uri == null ? null : queryInt(uri, 'authorid');
      if (uri != null &&
          queryInt(uri, 'tid') == threadId &&
          authorId != null &&
          authorId > 0) {
        return authorId;
      }
    }
    return null;
  }

  String _typeName(dom.Element titleElement) {
    return normalizeForumText(
      titleElement.querySelector('em')?.text ?? '',
    ).replaceAll(RegExp(r'^[\s\[\]【】()（）]+|[\s\[\]【】()（）]+$'), '');
  }

  String _threadTitle(dom.Element titleElement, String typeName) {
    String value = normalizeForumText(titleElement.text);
    final String rawType = normalizeForumText(
      titleElement.querySelector('em')?.text ?? '',
    );
    if (rawType.isNotEmpty && value.startsWith(rawType)) {
      value = value.substring(rawType.length).trim();
    }
    return value.isEmpty && typeName.isNotEmpty ? typeName : value;
  }

  List<ForumPostComment> _parseComments(
    dom.Element post,
    Uri pageUri,
    int threadId,
    int postId,
    ForumPostContentParser contentParser,
  ) {
    final dom.Element? container = post.querySelector('#comment_$postId');
    if (container == null || _isInsidePostContent(container)) {
      return const <ForumPostComment>[];
    }
    final List<ForumPostComment> result = <ForumPostComment>[];
    final Set<int> seenIds = <int>{};
    for (final dom.Element element in container.querySelectorAll(
      '.plc[id^="commentdetail_"]',
    )) {
      final int? commentId = int.tryParse(
        RegExp(r'^commentdetail_(\d+)$').firstMatch(element.id)?.group(1) ?? '',
      );
      final dom.Element? message = element.querySelector('.mtxt');
      if (commentId == null ||
          commentId <= 0 ||
          !seenIds.add(commentId) ||
          message == null) {
        continue;
      }
      final dom.Element? authorAnchor = element.querySelector(
        '.authi .mtit .z a[href*="mod=space"][href*="uid="], '
        '.mtit .z a[href*="mod=space"][href*="uid="]',
      );
      final Uri? authorUri = _profileUri(
        pageUri,
        authorAnchor?.attributes['href'],
      );
      final ForumPostContentParseResult content = contentParser.parse(
        message,
        pageUri,
      );
      if (content.blocks.isEmpty) {
        continue;
      }
      result.add(
        ForumPostComment(
          id: commentId,
          threadId: threadId,
          postId: postId,
          authorId: authorUri == null ? null : queryInt(authorUri, 'uid'),
          authorUri: authorUri,
          author: _safeText(authorAnchor),
          avatarUri: contentParser.resolveSameOriginResource(
            pageUri,
            element.querySelector('.avatar img')?.attributes['src'],
          ),
          timeLabel: directText(element.querySelector('.mtime')),
          contentBlocks: content.blocks,
        ),
      );
    }
    return List<ForumPostComment>.unmodifiable(result);
  }

  ({ForumPostRatingSummary? summary, Uri? uri}) _parseRatings(
    dom.Element post,
    Uri pageUri,
    int threadId,
    int postId,
    ForumPostContentParser contentParser,
  ) {
    final dom.Element? container = post.querySelector('#ratelog_$postId');
    if (container == null || _isInsidePostContent(container)) {
      return (summary: null, uri: null);
    }
    final Uri? ratingsUri = _ratingsUriFromResponse(
      container,
      pageUri,
      threadId,
      postId,
    );
    final dom.Element? grid = container.querySelector('ul.post_box, table.ratl');
    if (grid == null) {
      return (summary: null, uri: ratingsUri);
    }
    final List<dom.Element> rows = grid.children
        .where((dom.Element value) => value.localName == 'li')
        .toList();
    if (rows.isEmpty && grid.localName == 'table') {
      rows.addAll(grid.querySelectorAll('tr'));
    }
    if (rows.isEmpty) {
      return (summary: null, uri: ratingsUri);
    }

    final List<dom.Element> header = _ratingCells(rows.first);
    if (header.length < 3) {
      return (summary: null, uri: ratingsUri);
    }
    final int? participantCount = _lastInteger(_safeText(header.first));
    if (participantCount == null || participantCount <= 0) {
      return (summary: null, uri: ratingsUri);
    }
    final List<ForumPostRatingScore> totals = <ForumPostRatingScore>[];
    for (int index = 1; index < header.length - 1; index++) {
      final ForumPostRatingScore? total = _labeledRatingScore(
        _safeText(header[index]),
      );
      if (total == null) {
        return (summary: null, uri: ratingsUri);
      }
      totals.add(total);
    }
    if (totals.isEmpty) {
      return (summary: null, uri: ratingsUri);
    }

    final List<ForumPostRatingEntry> entries = <ForumPostRatingEntry>[];
    for (final dom.Element row in rows.skip(1)) {
      final List<dom.Element> cells = _ratingCells(row);
      if (cells.length < totals.length + 2) {
        continue;
      }
      final dom.Element? authorAnchor = cells.first.querySelector(
        'a[href*="mod=space"][href*="uid="]',
      );
      final Uri? authorUri = _profileUri(
        pageUri,
        authorAnchor?.attributes['href'],
      );
      final int? authorId = authorUri == null
          ? null
          : queryInt(authorUri, 'uid');
      final String author = _safeText(authorAnchor);
      if (authorId == null || authorId <= 0 || author.isEmpty) {
        continue;
      }
      final List<ForumPostRatingScore> scores = <ForumPostRatingScore>[];
      bool valid = true;
      for (int index = 0; index < totals.length; index++) {
        final int? value = _ratingValue(_safeText(cells[index + 1]));
        if (value == null) {
          valid = false;
          break;
        }
        scores.add(
          ForumPostRatingScore(credit: totals[index].credit, value: value),
        );
      }
      if (!valid) {
        continue;
      }
      entries.add(
        ForumPostRatingEntry(
          authorId: authorId,
          authorUri: authorUri,
          author: author,
          avatarUri: contentParser.resolveSameOriginResource(
            pageUri,
            cells.first.querySelector('img')?.attributes['src'],
          ),
          scores: List<ForumPostRatingScore>.unmodifiable(scores),
          reason: _safeText(cells[totals.length + 1]),
        ),
      );
    }
    if (participantCount < entries.length) {
      return (summary: null, uri: ratingsUri);
    }
    return (
      summary: ForumPostRatingSummary(
        participantCount: participantCount,
        totals: List<ForumPostRatingScore>.unmodifiable(totals),
        entries: List<ForumPostRatingEntry>.unmodifiable(entries),
      ),
      uri: ratingsUri,
    );
  }

  Uri? _ratingsUriFromResponse(
    dom.Element container,
    Uri pageUri,
    int threadId,
    int postId,
  ) {
    final dom.Element? grid = container.querySelector('ul.post_box, table.ratl');
    final dom.Element? header = grid?.children.firstOrNull;
    if (header == null) {
      return null;
    }
    for (final dom.Element anchor in header.querySelectorAll(
      'a.dialog[title*="评分"][href*="action=viewratings"]',
    )) {
      final Uri? uri = _resolveAction(pageUri, anchor);
      if (uri != null &&
          uri.path.toLowerCase() == '/forum.php' &&
          _singleParameter(uri, 'mod') == 'misc' &&
          _singleParameter(uri, 'action') == 'viewratings' &&
          _singleParameter(uri, 'mobile') == '2' &&
          _singlePositiveInteger(uri, 'tid') == threadId &&
          _singlePositiveInteger(uri, 'pid') == postId &&
          uri.fragment.isEmpty &&
          uri.queryParametersAll.keys.every(
            const <String>{'mod', 'action', 'tid', 'pid', 'mobile'}.contains,
          )) {
        return uri;
      }
    }
    return null;
  }

  Uri? _profileUri(Uri pageUri, String? value) {
    final Uri? uri = originPolicy.resolveMobile(pageUri, value);
    if (uri == null ||
        uri.path != '/home.php' ||
        _singleParameter(uri, 'mod') != 'space' ||
        (_singleParameter(uri, 'do') != null &&
            _singleParameter(uri, 'do') != 'profile') ||
        _singlePositiveInteger(uri, 'uid') == null ||
        !_hasOnlyParameters(
          uri,
          const <String>{'mod', 'do', 'uid', 'mobile'},
        )) {
      return null;
    }
    return uri;
  }

  List<dom.Element> _ratingCells(dom.Element row) {
    return row.children
        .where(
          (dom.Element value) => const <String>{
            'div',
            'th',
            'td',
          }.contains(value.localName),
        )
        .toList(growable: false);
  }

  ForumPostRatingScore? _labeledRatingScore(String value) {
    final Match? match = RegExp(r'([+-]?)\s*(\d+)\s*$').firstMatch(value);
    final String credit = match == null
        ? ''
        : value.substring(0, match.start).trim();
    final int? score = match == null
        ? null
        : int.tryParse('${match.group(1)}${match.group(2)}');
    return credit.isEmpty || score == null
        ? null
        : ForumPostRatingScore(credit: credit, value: score);
  }

  int? _ratingValue(String value) {
    final Match? match = RegExp(r'([+-]?)\s*(\d+)\s*$').firstMatch(value);
    return match == null
        ? null
        : int.tryParse('${match.group(1)}${match.group(2)}');
  }

  int? _lastInteger(String value) {
    final List<Match> matches = RegExp(r'\d+').allMatches(value).toList();
    return matches.isEmpty ? null : int.tryParse(matches.last.group(0)!);
  }

  String _safeText(dom.Node? node) {
    if (node == null) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    void visit(dom.Node current) {
      if (current is dom.Text) {
        buffer.write(current.data);
        return;
      }
      if (current is dom.Element &&
          const <String>{
            'script',
            'style',
            'noscript',
            'form',
            'button',
            'input',
            'select',
            'textarea',
            'iframe',
            'object',
            'embed',
          }.contains(current.localName)) {
        return;
      }
      for (final dom.Node child in current.nodes) {
        visit(child);
      }
    }

    visit(node);
    return normalizeForumText(buffer.toString());
  }

  String? _singleParameter(Uri uri, String name) {
    final List<String> values = uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single.toLowerCase() : null;
  }

  int? _singlePositiveInteger(Uri uri, String name) {
    final String? value = _singleParameter(uri, name);
    final int? parsed = value == null ? null : int.tryParse(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  bool _isAttachmentUri(Uri? uri) {
    if (uri == null || !originPolicy.isAllowed(uri)) {
      return false;
    }
    return uri.path.contains('/data/attachment/') ||
        _parameter(uri, 'mod') == 'attachment' ||
        (_parameter(uri, 'mod') == 'image' && queryInt(uri, 'aid') != null);
  }

  int? _attachmentId(Uri uri, String elementId) {
    return queryInt(uri, 'aid') ??
        int.tryParse(
          RegExp(r'(?:aimg_|aid)(\d+)').firstMatch(elementId)?.group(1) ?? '',
        );
  }

  String _attachmentName(String? label, Uri uri) {
    final String normalized = normalizeForumText(label ?? '');
    if (normalized.isNotEmpty) {
      return normalized;
    }
    if (uri.pathSegments.isNotEmpty) {
      return Uri.decodeComponent(uri.pathSegments.last);
    }
    return '附件';
  }

  String _sizeLabel(String value) {
    return normalizeForumText(
      RegExp(
            r'\d+(?:\.\d+)?\s*(?:Bytes?|KB|MB|GB|KiB|MiB|GiB)',
            caseSensitive: false,
          ).firstMatch(value)?.group(0) ??
          '',
    );
  }

  bool _looksLikeImage(Uri uri) {
    return RegExp(
      r'\.(?:avif|bmp|gif|jpe?g|png|webp)$',
      caseSensitive: false,
    ).hasMatch(uri.path);
  }

  bool _isSelected(dom.Element anchor) {
    return <dom.Element?>[anchor, anchor.parent].whereType<dom.Element>().any(
      (dom.Element value) => value.classes.any(
        (String name) =>
            const <String>{'a', 'active', 'current', 'selected'}.contains(name),
      ),
    );
  }

  String _readingKey(Uri uri) {
    final List<String> components = <String>[];
    for (final String component in uri.query.split('&')) {
      final String name = component.split('=').first;
      if (const <String>{
        'mod',
        'tid',
        'mobile',
        'page',
        'extra',
      }.contains(name)) {
        continue;
      }
      if (component.isNotEmpty) {
        components.add(component);
      }
    }
    components.sort();
    return components.join('&');
  }

  String _parameter(Uri uri, String name) {
    for (final String component in uri.query.split('&')) {
      final int separator = component.indexOf('=');
      if (separator < 0 || component.substring(0, separator) != name) {
        continue;
      }
      final String value = component.substring(separator + 1);
      try {
        return Uri.decodeQueryComponent(value);
      } on FormatException {
        return value;
      }
    }
    return '';
  }

  int? _fragmentPostId(String fragment) {
    return int.tryParse(
      RegExp(r'pid(\d+)').firstMatch(fragment)?.group(1) ?? '',
    );
  }
}
