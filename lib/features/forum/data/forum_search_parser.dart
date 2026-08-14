import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/forum/domain/forum_search_models.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';

class ForumThreadSearchParser {
  const ForumThreadSearchParser({
    this.originPolicy = const ForumOriginPolicy(),
  });

  final ForumOriginPolicy originPolicy;

  ForumThreadSearchForm parseForm(String html, Uri pageUri) {
    originPolicy.requireMobilePage(pageUri);
    _requireSearchUri(pageUri);
    final dom.Document document = html_parser.parse(html);
    _throwIfSessionExpired(document);
    _requireMobileTemplate(document);

    final dom.Element form = _findSearchForm(document, pageUri);
    final String method = (form.attributes['method'] ?? 'get')
        .trim()
        .toLowerCase();
    if (method != 'post') {
      throw const ForumParseException('论坛搜索表单不是 POST 表单');
    }
    final Uri actionUri = _resolveSearchAction(form, pageUri);
    final List<dom.Element> textFields = form
        .querySelectorAll('input[name]')
        .where(_isTextField)
        .toList(growable: false);
    if (textFields.length != 1) {
      throw const ForumParseException('论坛搜索表单的关键字输入框无法识别');
    }
    final dom.Element keywordField = textFields.single;
    final String keywordFieldName = (keywordField.attributes['name'] ?? '')
        .trim();
    if (keywordFieldName.isEmpty) {
      throw const ForumParseException('论坛搜索关键字字段缺少名称');
    }

    final Map<String, List<String>> hiddenFields = <String, List<String>>{};
    for (final dom.Element input in form.querySelectorAll(
      'input[type="hidden"][name]',
    )) {
      if (_isDisabled(input)) {
        continue;
      }
      final String name = (input.attributes['name'] ?? '').trim();
      if (name.isEmpty || name == keywordFieldName) {
        continue;
      }
      hiddenFields
          .putIfAbsent(name, () => <String>[])
          .add(input.attributes['value'] ?? '');
    }

    final List<ForumThreadSearchScopeOption> scopeOptions = _parseScopeOptions(
      form,
    );
    final int? boardId = _parseBoardScope(
      hiddenFields,
      pageUri,
      requireReturnedScope: pageUri.queryParameters['mod'] == 'curforum',
    );
    if (pageUri.queryParameters['mod'] == 'forum' && boardId != null) {
      throw const ForumParseException('全站论坛搜索表单意外返回了 srhfid');
    }
    return ForumThreadSearchForm(
      sourceUri: pageUri,
      actionUri: actionUri,
      keywordFieldName: keywordFieldName,
      initialKeyword: normalizeForumText(
        keywordField.attributes['value'] ?? '',
      ),
      hiddenFields: Map<String, List<String>>.unmodifiable(
        hiddenFields.map(
          (String key, List<String> value) => MapEntry<String, List<String>>(
            key,
            List<String>.unmodifiable(value),
          ),
        ),
      ),
      scopeOptions: List<ForumThreadSearchScopeOption>.unmodifiable(
        scopeOptions,
      ),
      boardId: boardId,
    );
  }

  ForumThreadSearchPage parseResults(
    String html,
    Uri pageUri, {
    required String expectedKeyword,
    int? expectedBoardId,
  }) {
    originPolicy.requireMobilePage(pageUri);
    _requireSearchUri(pageUri);
    final dom.Document document = html_parser.parse(html);
    _throwIfSessionExpired(document);
    _requireMobileTemplate(document);

    final dom.Element? resultBox = document.querySelector('.threadlist_box');
    final dom.Element? threadList = resultBox?.querySelector('.threadlist');
    if (resultBox == null || threadList == null) {
      throw ForumParseException(
        _messageOrFallback(document, '论坛未返回可识别的移动搜索结果'),
      );
    }

    final _ResultScope scope = _parseResultScope(document, pageUri);
    if (scope.boardId != expectedBoardId) {
      throw const ForumParseException('论坛搜索结果的 srhfid 与当前版块不一致');
    }
    final List<ForumThreadSearchHit> hits = <ForumThreadSearchHit>[];
    final Set<String> seen = <String>{};
    final List<dom.Element> items = threadList.querySelectorAll('li.list');
    for (final dom.Element item in items) {
      final ForumThreadSearchHit? hit = _parseHit(item, pageUri, scope.boardId);
      if (hit == null) {
        throw const ForumParseException('论坛搜索结果中存在无法识别的主题');
      }
      final String key = '${hit.threadId}:${hit.postId ?? 0}';
      if (seen.add(key)) {
        hits.add(hit);
      }
    }
    if (items.isNotEmpty && hits.isEmpty) {
      throw const ForumParseException('论坛搜索结果中没有可识别的主题');
    }

    final String keyword = _resultKeyword(document, expectedKeyword);
    if (keyword.isEmpty) {
      throw const ForumParseException('论坛搜索结果缺少关键字');
    }
    final _SearchPagination pagination = _parsePagination(document, pageUri);
    final String searchId =
        pageUri.queryParameters['searchid'] ??
        pagination.next?.queryParameters['searchid'] ??
        pagination.previous?.queryParameters['searchid'] ??
        '';
    return ForumThreadSearchPage(
      keyword: keyword,
      searchId: searchId,
      boardId: scope.boardId,
      scopeLabels: List<String>.unmodifiable(scope.labels),
      hits: List<ForumThreadSearchHit>.unmodifiable(hits),
      cursor: ForumPageCursor(
        currentPage: pagination.current,
        totalPages: pagination.total,
        sourceUri: pageUri,
        previousPageUri: pagination.previous,
        nextPageUri: pagination.next,
      ),
      sourceUri: pageUri,
      totalResults: _parseTotalResults(resultBox),
    );
  }

  dom.Element _findSearchForm(dom.Document document, Uri pageUri) {
    for (final dom.Element form in document.querySelectorAll('form[action]')) {
      try {
        _resolveSearchAction(form, pageUri);
        return form;
      } on ForumParseException {
        continue;
      }
    }
    throw const ForumParseException('无法读取论坛移动搜索表单');
  }

  Uri _resolveSearchAction(dom.Element form, Uri pageUri) {
    final Uri? uri = originPolicy.resolveAllowed(
      pageUri,
      form.attributes['action'],
    );
    if (uri == null) {
      throw const ForumParseException('论坛搜索表单地址无效');
    }
    _requireSearchUri(uri);
    final String? mod = uri.queryParameters['mod'];
    if (mod == 'forum') {
      return uri;
    }
    if (mod == 'curforum') {
      final int? actionBoardId = queryInt(uri, 'srhfid');
      final int? entryBoardId = queryInt(pageUri, 'srhfid');
      if (actionBoardId == null || actionBoardId <= 0) {
        throw const ForumParseException('当前版块搜索表单 action 缺少 srhfid');
      }
      if (entryBoardId != null && entryBoardId != actionBoardId) {
        throw const ForumParseException('当前版块搜索表单 action 与入口 fid 不一致');
      }
      return uri;
    }
    throw const ForumParseException('论坛搜索表单 action 无效');
  }

  List<ForumThreadSearchScopeOption> _parseScopeOptions(dom.Element form) {
    final List<ForumThreadSearchScopeOption> result =
        <ForumThreadSearchScopeOption>[];
    for (final dom.Element select in form.querySelectorAll('select[name]')) {
      if (_isDisabled(select)) {
        continue;
      }
      final String name = (select.attributes['name'] ?? '').trim();
      final List<dom.Element> options = select.querySelectorAll('option');
      final bool hasSelected = options.any(
        (dom.Element option) => option.attributes.containsKey('selected'),
      );
      for (int index = 0; index < options.length; index++) {
        final dom.Element option = options[index];
        if (_isDisabled(option) || name.isEmpty) {
          continue;
        }
        result.add(
          ForumThreadSearchScopeOption(
            fieldName: name,
            value: option.attributes['value'] ?? option.text,
            label: normalizeForumText(option.text),
            selected:
                option.attributes.containsKey('selected') ||
                (!hasSelected && index == 0),
          ),
        );
      }
    }
    for (final dom.Element input in form.querySelectorAll(
      'input[type="radio"][name], input[type="checkbox"][name]',
    )) {
      if (_isDisabled(input)) {
        continue;
      }
      final String name = (input.attributes['name'] ?? '').trim();
      if (name.isEmpty) {
        continue;
      }
      result.add(
        ForumThreadSearchScopeOption(
          fieldName: name,
          value: input.attributes['value'] ?? 'on',
          label: _controlLabel(input, form),
          selected: input.attributes.containsKey('checked'),
        ),
      );
    }
    return result;
  }

  ForumThreadSearchHit? _parseHit(
    dom.Element item,
    Uri pageUri,
    int? scopedBoardId,
  ) {
    final dom.Element? titleElement = item.querySelector('.threadlist_tit');
    final dom.Element? anchor =
        _enclosingAnchor(titleElement) ??
        item.querySelector('a[href*="tid="], a[href*="ptid="]');
    final Uri? targetUri = originPolicy.resolveMobile(
      pageUri,
      anchor?.attributes['href'],
    );
    if (targetUri == null || targetUri.path != '/forum.php') {
      return null;
    }
    final String? mod = targetUri.queryParameters['mod'];
    if (mod != 'viewthread' && mod != 'redirect') {
      return null;
    }
    final int? threadId =
        queryInt(targetUri, 'tid') ?? queryInt(targetUri, 'ptid');
    if (threadId == null || threadId <= 0) {
      return null;
    }
    final String title = normalizeForumText(
      titleElement?.querySelector('em')?.text ??
          titleElement?.text ??
          anchor?.text ??
          '',
    );
    if (title.isEmpty) {
      return null;
    }

    final dom.Element? boardAnchor = item.querySelector(
      '.threadlist_foot li.mr a[href*="fid="]',
    );
    final Uri? boardUri = originPolicy.resolveMobile(
      pageUri,
      boardAnchor?.attributes['href'],
    );
    final int? returnedBoardId = boardUri == null
        ? null
        : queryInt(boardUri, 'fid');
    if (returnedBoardId != null &&
        scopedBoardId != null &&
        returnedBoardId != scopedBoardId) {
      return null;
    }
    final int? boardId = returnedBoardId ?? scopedBoardId;
    if (boardId == null || boardId <= 0) {
      return null;
    }

    final dom.Element? authorAnchor = item.querySelector(
      '.threadlist_top .muser a.mmc[href]',
    );
    final Uri? authorUri = _profileUri(
      pageUri,
      authorAnchor?.attributes['href'],
    );
    final List<dom.Element> counters = item.querySelectorAll(
      '.threadlist_foot li:not(.mr)',
    );
    return ForumThreadSearchHit(
      threadId: threadId,
      boardId: boardId,
      postId: _postId(targetUri),
      title: title,
      uri: targetUri,
      authorId: authorUri == null ? null : queryInt(authorUri, 'uid'),
      authorUri: authorUri,
      author: normalizeForumText(authorAnchor?.text ?? ''),
      avatarUri: originPolicy.resolveAllowed(
        pageUri,
        item.querySelector('.threadlist_top a.mimg img')?.attributes['src'],
      ),
      timeLabel: directText(item.querySelector('.threadlist_top .mtime')),
      summary: normalizeForumText(
        item.querySelector('.threadlist_mes')?.text ?? '',
      ),
      boardName: normalizeForumText(
        boardAnchor?.text ?? '',
      ).replaceFirst(RegExp(r'^#\s*'), ''),
      views: counters.isEmpty ? 0 : parseForumCount(counters[0].text),
      replies: counters.length < 2 ? 0 : parseForumCount(counters[1].text),
    );
  }

  _SearchPagination _parsePagination(dom.Document document, Uri pageUri) {
    final dom.Element? page = document.querySelector('.pg');
    final int sourcePage = queryInt(pageUri, 'page') ?? 1;
    if (page == null) {
      return _SearchPagination(current: sourcePage, total: sourcePage);
    }
    final int current =
        int.tryParse(
          page.querySelector('input[name="custompage"]')?.attributes['value'] ??
              '',
        ) ??
        int.tryParse(
          normalizeForumText(page.querySelector('strong')?.text ?? ''),
        ) ??
        sourcePage;
    int total = current;
    final dom.Element? last = page.querySelector('a.last[href]');
    if (last != null) {
      total = queryInt(_resolvePaginationUri(pageUri, last), 'page') ?? total;
    }
    final String title =
        page.querySelector('label span')?.attributes['title'] ?? '';
    total =
        int.tryParse(RegExp(r'(\d+)').firstMatch(title)?.group(1) ?? '') ??
        total;
    if (total < current) {
      total = current;
    }
    final dom.Element? previous = page.querySelector('a.prev[href]');
    final dom.Element? next = page.querySelector('a.nxt[href]');
    return _SearchPagination(
      current: current,
      total: total,
      previous: previous == null
          ? null
          : _resolvePaginationUri(pageUri, previous),
      next: next == null ? null : _resolvePaginationUri(pageUri, next),
    );
  }

  Uri _resolvePaginationUri(Uri pageUri, dom.Element anchor) {
    final Uri? uri = originPolicy.resolveMobile(
      pageUri,
      anchor.attributes['href'],
    );
    if (uri == null) {
      throw const ForumParseException('论坛搜索分页地址无效');
    }
    _requireSearchUri(uri);
    final String? sourceSearchId = pageUri.queryParameters['searchid'];
    final String? targetSearchId = uri.queryParameters['searchid'];
    if (sourceSearchId != null && targetSearchId != sourceSearchId) {
      throw const ForumParseException('论坛搜索分页 searchid 不一致');
    }
    return uri;
  }

  _ResultScope _parseResultScope(dom.Document document, Uri pageUri) {
    dom.Element? form;
    try {
      form = _findSearchForm(document, pageUri);
    } on ForumParseException {
      return const _ResultScope();
    }
    final Map<String, List<String>> hidden = <String, List<String>>{};
    for (final dom.Element input in form.querySelectorAll(
      'input[type="hidden"][name]',
    )) {
      final String name = (input.attributes['name'] ?? '').trim();
      if (name.isNotEmpty && !_isDisabled(input)) {
        hidden
            .putIfAbsent(name, () => <String>[])
            .add(input.attributes['value'] ?? '');
      }
    }
    final List<ForumThreadSearchScopeOption> options = _parseScopeOptions(form);
    return _ResultScope(
      boardId: _parseBoardScope(hidden, pageUri),
      labels: options
          .where((ForumThreadSearchScopeOption value) => value.selected)
          .map((ForumThreadSearchScopeOption value) => value.label)
          .where((String value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }

  int? _parseBoardScope(
    Map<String, List<String>> hidden,
    Uri pageUri, {
    bool requireReturnedScope = false,
  }) {
    final int? sourceBoardId = queryInt(pageUri, 'srhfid');
    final List<String> returnedValues = hidden['srhfid'] ?? const <String>[];
    final Set<int> returnedIds = returnedValues
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    if (returnedIds.length > 1) {
      throw const ForumParseException('论坛搜索表单返回了冲突的 srhfid');
    }
    final int? returnedBoardId = returnedIds.isEmpty
        ? null
        : returnedIds.single;
    if (requireReturnedScope && returnedBoardId == null) {
      throw const ForumParseException('当前版块搜索表单缺少 srhfid');
    }
    if (sourceBoardId != null &&
        returnedBoardId != null &&
        sourceBoardId != returnedBoardId) {
      throw const ForumParseException('论坛搜索表单 srhfid 不一致');
    }
    final int? resolved = returnedBoardId ?? sourceBoardId;
    return resolved != null && resolved > 0 ? resolved : null;
  }

  String _controlLabel(dom.Element input, dom.Element form) {
    final String id = input.attributes['id'] ?? '';
    if (id.isNotEmpty) {
      for (final dom.Element label in form.querySelectorAll('label[for]')) {
        if (label.attributes['for'] == id) {
          return normalizeForumText(label.text);
        }
      }
    }
    dom.Node? parent = input.parent;
    while (parent is dom.Element && !identical(parent, form)) {
      if (parent.localName == 'label') {
        return normalizeForumText(parent.text);
      }
      parent = parent.parent;
    }
    return normalizeForumText(input.attributes['title'] ?? '');
  }

  dom.Element? _enclosingAnchor(dom.Element? element) {
    dom.Node? current = element;
    while (current is dom.Element) {
      if (current.localName == 'a' && current.attributes.containsKey('href')) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  int? _postId(Uri uri) {
    final int? queryPostId = queryInt(uri, 'pid');
    if (queryPostId != null && queryPostId > 0) {
      return queryPostId;
    }
    final int? fragmentPostId = int.tryParse(
      RegExp(
            r'(?:^|[^a-z])pid(\d+)',
            caseSensitive: false,
          ).firstMatch(uri.fragment)?.group(1) ??
          '',
    );
    return fragmentPostId != null && fragmentPostId > 0 ? fragmentPostId : null;
  }

  Uri? _profileUri(Uri pageUri, String? value) {
    final Uri? uri = originPolicy.resolveMobile(pageUri, value);
    if (uri == null ||
        uri.path != '/home.php' ||
        _single(uri, 'mod') != 'space' ||
        (_single(uri, 'do') != null && _single(uri, 'do') != 'profile') ||
        _positive(uri, 'uid') == null ||
        !uri.queryParametersAll.entries.every(
          (MapEntry<String, List<String>> entry) =>
              const <String>{'mod', 'do', 'uid', 'mobile'}.contains(entry.key) &&
              entry.value.length == 1,
        )) {
      return null;
    }
    return uri;
  }

  String? _single(Uri uri, String name) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single : null;
  }

  int? _positive(Uri uri, String name) {
    final int? value = int.tryParse(_single(uri, name) ?? '');
    return value != null && value > 0 ? value : null;
  }

  int? _parseTotalResults(dom.Element resultBox) {
    final String text = normalizeForumText(
      resultBox.querySelector('h2')?.text ?? '',
    );
    final String? count = RegExp(
      r'([0-9][0-9,.]*(?:\.\d+)?\s*[万千wk]?)\s*个',
      caseSensitive: false,
    ).firstMatch(text)?.group(1);
    return count == null ? null : parseForumCount(count);
  }

  String _resultKeyword(dom.Document document, String expectedKeyword) {
    final String expected = normalizeForumText(expectedKeyword);
    final String returned = normalizeForumText(
      document
              .querySelector(
                '.searchform input[type="text"], '
                '.searchform input[type="search"], '
                '.searchform input:not([type])',
              )
              ?.attributes['value'] ??
          document.querySelector('.threadlist_box .emfont')?.text ??
          '',
    );
    if (expected.isNotEmpty && returned.isNotEmpty && returned != expected) {
      throw const ForumParseException('论坛搜索结果关键字不一致');
    }
    return expected.isNotEmpty ? expected : returned;
  }

  bool _isTextField(dom.Element input) {
    if (_isDisabled(input)) {
      return false;
    }
    final String type = (input.attributes['type'] ?? 'text').toLowerCase();
    return type == 'text' || type == 'search';
  }

  bool _isDisabled(dom.Element element) {
    return element.attributes.containsKey('disabled');
  }

  void _requireMobileTemplate(dom.Document document) {
    final dom.Element? body = document.body;
    final bool mobileForumSearch =
        body?.id == 'search' && body!.classes.contains('pg_forum');
    final bool mobileBoardSearch =
        body?.id == 'search' && body!.classes.contains('pg_curforum');
    if (mobileForumSearch || mobileBoardSearch) {
      return;
    }
    if (body?.id == 'nv_search' ||
        body?.classes.contains('pg_search') == true) {
      throw const ForumParseException('论坛返回了电脑版搜索页面');
    }
    throw const ForumParseException('论坛移动搜索模板已变更');
  }

  void _throwIfSessionExpired(dom.Document document) {
    if (document.querySelector('form#loginform') != null ||
        document.body?.classes.contains('pg_logging') == true) {
      throw const ForumSessionExpiredException();
    }
  }

  void _requireSearchUri(Uri uri) {
    originPolicy.ensureAllowed(uri);
    if (uri.path != '/search.php' ||
        !const <String>{
          'forum',
          'curforum',
        }.contains(uri.queryParameters['mod'])) {
      throw const ForumParseException('论坛搜索地址无效');
    }
  }

  String _messageOrFallback(dom.Document document, String fallback) {
    final String message = normalizeForumText(
      document
              .querySelector('.jump_c p, #messagetext, .tip, .alert_info')
              ?.text ??
          '',
    );
    return message.isEmpty ? fallback : message;
  }
}

class _SearchPagination {
  const _SearchPagination({
    required this.current,
    required this.total,
    this.previous,
    this.next,
  });

  final int current;
  final int total;
  final Uri? previous;
  final Uri? next;
}

class _ResultScope {
  const _ResultScope({this.boardId, this.labels = const <String>[]});

  final int? boardId;
  final List<String> labels;
}
