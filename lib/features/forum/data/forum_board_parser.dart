import 'package:html/dom.dart' as dom;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_page_classifier.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';

class ForumBoardParser {
  const ForumBoardParser({
    this.originPolicy = const ForumOriginPolicy(),
    this.pageClassifier = const ForumPageClassifier(),
  });

  final ForumOriginPolicy originPolicy;
  final ForumPageClassifier pageClassifier;

  ForumBoardPage parse(String html, Uri pageUri, {int? expectedBoardId}) {
    final dom.Document document = pageClassifier.requireKind(
      html,
      pageUri,
      ForumMobilePageKind.board,
    );
    final int? sourceBoardId = queryInt(pageUri, 'fid');
    final int? documentBoardId = _documentBoardId(document, pageUri);
    final int? boardId = expectedBoardId ?? sourceBoardId ?? documentBoardId;
    if (boardId == null || boardId <= 0) {
      throw const ForumParseException('版块页缺少 fid');
    }
    for (final int? actual in <int?>[sourceBoardId, documentBoardId]) {
      if (actual != null && actual != boardId) {
        throw const ForumParseException('版块页 fid 不一致');
      }
    }

    final dom.Element? threadList = document.querySelector('.threadlist');
    if (threadList == null) {
      throw const ForumParseException('版块移动页缺少主题列表');
    }
    final List<ForumThreadSummary> threads = <ForumThreadSummary>[];
    final Set<String> seenTargets = <String>{};
    for (final dom.Element element in threadList.querySelectorAll(
      'li.list_top, li.list',
    )) {
      final ForumThreadSummary? thread = _parseThread(
        element,
        pageUri,
        boardId,
      );
      if (thread != null &&
          seenTargets.add('${thread.targetKind.name}:${thread.id}')) {
        threads.add(thread);
      }
    }
    if (threads.isEmpty &&
        threadList.querySelector('.emp, .empty, .nothread') == null &&
        document.querySelector('.nothread') == null) {
      throw const ForumParseException('版块页中没有可识别的主题列表');
    }

    final String boardName = _boardName(document, pageUri, boardId);
    if (boardName.isEmpty) {
      throw const ForumParseException('版块页缺少版块名称');
    }
    final ForumPageCursor cursor = _parseCursor(document, pageUri, boardId);
    return ForumBoardPage(
      board: ForumBoardNode(
        id: boardId,
        name: boardName,
        description: normalizeForumText(
          document
                  .querySelector('.forum_desc, .forum-description, .bm_c .xg2')
                  ?.text ??
              '',
        ),
        uri: _boardHomeUri(document, pageUri, boardId) ?? pageUri,
      ),
      threads: List<ForumThreadSummary>.unmodifiable(threads),
      filters: _parseFilters(document, pageUri, boardId),
      cursor: cursor,
      newThreadUri: _findActionUri(
        document,
        pageUri,
        'a[href*="mod=post"][href*="action=newthread"]',
        (Uri uri) =>
            uri.path == '/forum.php' &&
            _singleParameter(uri, 'mod') == 'post' &&
            _singleParameter(uri, 'action') == 'newthread' &&
            _singlePositiveInteger(uri, 'fid') == boardId &&
            _hasOnlyParameters(
              uri,
              const <String>{'mod', 'action', 'fid', 'mobile'},
            ) &&
            _isMobileAction(uri),
      ),
      favoriteUri: _findActionUri(
        document,
        pageUri,
        'a[href*="ac=favorite"][href*="type=forum"]',
        (Uri uri) =>
            uri.path == '/home.php' &&
            _singleParameter(uri, 'mod') == 'spacecp' &&
            _singleParameter(uri, 'ac') == 'favorite' &&
            _singleParameter(uri, 'type') == 'forum' &&
            _singlePositiveInteger(uri, 'id') == boardId &&
            (_singleParameter(uri, 'handlekey') ?? '').isNotEmpty &&
            _hasOnlyParameters(
              uri,
              const <String>{
                'mod', 'ac', 'type', 'id', 'handlekey', 'mobile',
              },
            ) &&
            _isMobileAction(uri),
      ),
      searchUri: _findActionUri(
        document,
        pageUri,
        'a[href*="mod=curforum"][href*="srhfid="]',
        (Uri uri) =>
            uri.path == '/search.php' &&
            _singleParameter(uri, 'mod') == 'curforum' &&
            _singlePositiveInteger(uri, 'srhfid') == boardId &&
            _hasOnlyParameters(
              uri,
              const <String>{'mod', 'srhfid', 'mobile'},
            ) &&
            _isMobileAction(uri),
      ),
    );
  }

  ForumThreadSummary? _parseThread(
    dom.Element element,
    Uri pageUri,
    int boardId,
  ) {
    dom.Element? anchor;
    ForumThreadTargetKind? targetKind;
    Uri? targetUri;
    int? targetId;
    for (final dom.Element candidate in element.querySelectorAll('a[href]')) {
      final Uri? allowed = originPolicy.resolveAllowed(
        pageUri,
        candidate.attributes['href'],
      );
      if (allowed == null) {
        continue;
      }
      final bool isThread = _parameter(allowed, 'mod') == 'viewthread' &&
          queryInt(allowed, 'tid') != null;
      final bool isAnnouncement =
          _parameter(allowed, 'mod') == 'announcement' &&
          queryInt(allowed, 'id') != null;
      if (!isThread && !isAnnouncement) {
        continue;
      }
      final Uri? navigable = isThread
          ? originPolicy.resolveMobile(pageUri, candidate.attributes['href'])
          : allowed;
      if (navigable == null) {
        continue;
      }
      if (candidate.querySelector('.threadlist_tit') != null ||
          element.classes.contains('list_top')) {
        anchor = candidate;
        targetKind = isThread
            ? ForumThreadTargetKind.thread
            : ForumThreadTargetKind.announcement;
        targetUri = navigable;
        targetId = queryInt(navigable, isThread ? 'tid' : 'id');
        break;
      }
    }
    if (anchor == null ||
        targetKind == null ||
        targetUri == null ||
        targetId == null ||
        targetId <= 0) {
      return null;
    }
    if (targetKind == ForumThreadTargetKind.announcement) {
      targetUri = Uri(
        scheme: targetUri.scheme,
        host: targetUri.host,
        port: targetUri.hasPort ? targetUri.port : null,
        path: '/forum.php',
        queryParameters: <String, String>{
          'mod': 'announcement',
          'id': '$targetId',
          'mobile': '2',
        },
      );
    }
    final String title = normalizeForumText(
      element.querySelector('.threadlist_tit em')?.text ??
          element.querySelector('.threadlist_tit')?.text ??
          anchor.querySelector('em')?.text ??
          anchor.text,
    );
    if (title.isEmpty) {
      return null;
    }

    final dom.Element? typeAnchor = element.querySelector(
      '.threadlist_foot li.mr a[href]',
    );
    final dom.Element? authorAnchor = element.querySelector(
      '.threadlist_top .muser a.mmc[href]',
    );
    final Uri? authorUri = _profileUri(
      pageUri,
      authorAnchor?.attributes['href'],
    );
    final List<dom.Element> counters = element.querySelectorAll(
      '.threadlist_foot li:not(.mr)',
    );
    final String stateText = normalizeForumText(
      element
          .querySelectorAll('[title], [alt]')
          .map(
            (dom.Element value) =>
                '${value.attributes['title'] ?? ''} '
                '${value.attributes['alt'] ?? ''}',
          )
          .join(' '),
    );
    return ForumThreadSummary(
      id: targetId,
      boardId: boardId,
      title: title,
      uri: targetUri,
      typeName: normalizeForumText(typeAnchor?.text ?? ''),
      summary: normalizeForumText(
        element.querySelector('.threadlist_mes')?.text ?? '',
      ),
      author: normalizeForumText(
        element.querySelector('.threadlist_top .muser a.mmc')?.text ?? '',
      ),
      authorId: authorUri == null ? null : queryInt(authorUri, 'uid'),
      authorUri: authorUri,
      avatarUri: originPolicy.resolveAllowed(
        pageUri,
        element.querySelector('.threadlist_top a.mimg img')?.attributes['src'],
      ),
      timeLabel: directText(element.querySelector('.threadlist_top .mtime')),
      views: counters.isEmpty ? 0 : parseForumCount(counters[0].text),
      replies: counters.length < 2 ? 0 : parseForumCount(counters[1].text),
      pinned: element.classes.contains('list_top'),
      digest:
          element.querySelector(
            '.digest, [class*="digest"], [title*="精华"], [alt*="精华"]',
          ) !=
          null,
      closed:
          element.querySelector(
            '.lock, .locked, [class*="lock"], [title*="关闭"], [alt*="关闭"]',
          ) !=
          null,
      special:
          element.querySelector(
                '.poll, [class*="special"], [title*="投票"], [alt*="投票"]',
              ) !=
              null ||
          stateText.contains('投票'),
      targetKind: targetKind,
    );
  }

  List<ForumRouteOption> _parseFilters(
    dom.Document document,
    Uri pageUri,
    int boardId,
  ) {
    final List<ForumRouteOption> result = <ForumRouteOption>[];
    final Set<String> seenKeys = <String>{};
    for (final dom.Element anchor in document.querySelectorAll('a[href]')) {
      final Uri? uri = originPolicy.resolveMobile(
        pageUri,
        anchor.attributes['href'],
      );
      if (uri == null || !_isBoardRoute(uri, boardId)) {
        continue;
      }
      final bool declaresFilter = const <String>{
        'filter',
        'orderby',
        'typeid',
        'digest',
        'specialtype',
      }.any((String name) => _parameter(uri, name).isNotEmpty);
      if (!declaresFilter && !_isInsideFilterNavigation(anchor)) {
        continue;
      }
      if (_parameter(uri, 'page').isNotEmpty) {
        continue;
      }
      final String label = normalizeForumText(anchor.text);
      if (label.isEmpty) {
        continue;
      }
      final String key = _filterKey(uri);
      if (!seenKeys.add(key)) {
        continue;
      }
      result.add(
        ForumRouteOption(
          key: key,
          label: label,
          uri: uri,
          selected: _isSelected(anchor) || key == _filterKey(pageUri),
        ),
      );
    }
    return List<ForumRouteOption>.unmodifiable(result);
  }

  ForumPageCursor _parseCursor(
    dom.Document document,
    Uri pageUri,
    int boardId,
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
      final Uri lastUri = _requireBoardPageLink(last, pageUri, boardId);
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
      previousPageUri: _optionalBoardPageLink(
        _previousAnchor(pagination),
        pageUri,
        boardId,
      ),
      nextPageUri: _optionalBoardPageLink(
        pagination?.querySelector('a.nxt[href]'),
        pageUri,
        boardId,
      ),
    );
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

  Uri? _optionalBoardPageLink(dom.Element? anchor, Uri pageUri, int boardId) {
    return anchor == null
        ? null
        : _requireBoardPageLink(anchor, pageUri, boardId);
  }

  Uri _requireBoardPageLink(dom.Element anchor, Uri pageUri, int boardId) {
    final Uri? uri = originPolicy.resolveMobile(
      pageUri,
      anchor.attributes['href'],
    );
    if (uri == null ||
        !_isBoardRoute(uri, boardId) ||
        (queryInt(uri, 'page') ?? 0) <= 0) {
      throw const ForumParseException('版块分页地址无效');
    }
    return uri;
  }

  Uri? _findActionUri(
    dom.Document document,
    Uri pageUri,
    String selector,
    bool Function(Uri uri) matches,
  ) {
    for (final dom.Element anchor in document.querySelectorAll(selector)) {
      if (_isInsideThreadList(anchor)) {
        continue;
      }
      final String? href = anchor.attributes['href'];
      final Uri? uri = originPolicy.resolveAllowed(pageUri, href);
      if (href != null && href.trim().isNotEmpty && uri == null) {
        throw const ForumActionSecurityException();
      }
      if (uri != null && _hasUniqueActionParameters(uri) && matches(uri)) {
        return uri;
      }
    }
    return null;
  }

  bool _isInsideThreadList(dom.Element element) {
    dom.Element? ancestor = element.parent;
    while (ancestor != null) {
      if (ancestor.classes.contains('threadlist')) {
        return true;
      }
      ancestor = ancestor.parent;
    }
    return false;
  }

  bool _isMobileAction(Uri uri) {
    final List<String> mobile =
        uri.queryParametersAll['mobile'] ?? const <String>[];
    return mobile.length == 1 && mobile.single == '2';
  }

  bool _hasUniqueActionParameters(Uri uri) {
    if (!originPolicy.hasNoAliasedQueryParameters(
      uri,
      const <String>{
        'mod', 'action', 'ac', 'op', 'type', 'mobile', 'fid', 'tid', 'pid',
        'id', 'favid', 'srhfid',
        'handlekey',
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
      'srhfid',
      'handlekey',
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

  int? _singlePositiveInteger(Uri uri, String name) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    final int? value = values.length == 1 ? int.tryParse(values.single) : null;
    return value != null && value > 0 ? value : null;
  }

  String? _singleParameter(Uri uri, String name) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single : null;
  }

  Uri? _boardHomeUri(dom.Document document, Uri pageUri, int boardId) {
    for (final dom.Element anchor in document.querySelectorAll(
      '.header h2 a[href], a[href*="mod=forumdisplay"][href*="fid="]',
    )) {
      final Uri? uri = originPolicy.resolveMobile(
        pageUri,
        anchor.attributes['href'],
      );
      if (uri != null &&
          _isBoardRoute(uri, boardId) &&
          _parameter(uri, 'page').isEmpty) {
        return uri;
      }
    }
    return null;
  }

  int? _documentBoardId(dom.Document document, Uri pageUri) {
    for (final dom.Element anchor in document.querySelectorAll(
      '.header h2 a[href*="fid="], '
      'a[href*="action=newthread"][href*="fid="], '
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

  String _boardName(dom.Document document, Uri pageUri, int boardId) {
    for (final dom.Element anchor in document.querySelectorAll(
      '.header h2 a[href*="fid="]',
    )) {
      final Uri? uri = originPolicy.resolveMobile(
        pageUri,
        anchor.attributes['href'],
      );
      if (uri != null && queryInt(uri, 'fid') == boardId) {
        final String name = normalizeForumText(anchor.text);
        if (name.isNotEmpty) {
          return name;
        }
      }
    }
    final String header = normalizeForumText(
      document.querySelector('.header h2')?.text ?? '',
    );
    if (header.isNotEmpty) {
      return header;
    }
    return normalizeForumText(
      document.querySelector('title')?.text ?? '',
    ).split(' - ').first;
  }

  bool _isBoardRoute(Uri uri, int boardId) {
    return originPolicy.isAllowed(uri) &&
        uri.path.endsWith('/forum.php') &&
        _parameter(uri, 'mod') == 'forumdisplay' &&
        queryInt(uri, 'fid') == boardId;
  }

  bool _isInsideFilterNavigation(dom.Element anchor) {
    dom.Element? current = anchor.parent;
    while (current != null) {
      if (current.id == 'dhnavs_li' ||
          current.classes.any(
            (String value) => const <String>{
              'swiper-wrapper',
              'forum_filter',
              'forum-filter',
              'threadfilter',
              'threadtypes',
              'filter',
            }.contains(value),
          )) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  bool _isSelected(dom.Element anchor) {
    return <dom.Element?>[anchor, anchor.parent].whereType<dom.Element>().any(
      (dom.Element value) => value.classes.any(
        (String name) =>
            const <String>{'a', 'active', 'current', 'selected'}.contains(name),
      ),
    );
  }

  String _filterKey(Uri uri) {
    final List<String> components = <String>[];
    for (final String component in uri.query.split('&')) {
      final String name = component.split('=').first;
      if (const <String>{
        'mod',
        'fid',
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
    return components.isEmpty ? 'all' : components.join('&');
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
}
