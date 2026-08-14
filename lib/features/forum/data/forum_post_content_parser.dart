import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';

class ForumPostContentParseResult {
  const ForumPostContentParseResult({
    required this.blocks,
    required this.sanitizedHtml,
  });

  final List<ForumPostContentBlock> blocks;
  final String sanitizedHtml;
}

class ForumPostContentParser {
  const ForumPostContentParser({this.originPolicy = const ForumOriginPolicy()});

  final ForumOriginPolicy originPolicy;

  ForumPostContentParseResult parse(dom.Element message, Uri pageUri) {
    originPolicy.ensureAllowed(pageUri);
    final _ForumPostContentCollector collector = _ForumPostContentCollector(
      this,
      pageUri,
    );
    collector.collect(message);
    final String source = message.innerHtml.trim().isEmpty
        ? message.outerHtml
        : message.innerHtml;
    return ForumPostContentParseResult(
      blocks: List<ForumPostContentBlock>.unmodifiable(collector.blocks),
      sanitizedHtml: _sanitizeLegacyHtml(source, pageUri),
    );
  }

  Uri? resolveSameOriginResource(Uri pageUri, String? value) {
    return _resolveSameOrigin(pageUri, value);
  }

  ForumPostImageInline? _parseImage(dom.Element image, Uri pageUri) {
    final String source =
        image.attributes['zoomfile'] ??
        image.attributes['file'] ??
        image.attributes['data-original'] ??
        image.attributes['src'] ??
        '';
    final Uri? uri = _resolveSameOrigin(pageUri, source);
    if (uri == null) {
      return null;
    }
    final String path = uri.path.toLowerCase();
    return ForumPostImageInline(
      uri: uri,
      alt: normalizeForumText(
        image.attributes['alt'] ?? image.attributes['title'] ?? '',
      ),
      isEmoticon:
          image.attributes.containsKey('smilieid') ||
          image.classes.any(
            (String value) =>
                value.toLowerCase().contains('smilie') ||
                value.toLowerCase().contains('smiley'),
          ) ||
          path.contains('/static/image/smiley/'),
    );
  }

  ForumPostLinkInline? _parseLink(
    dom.Element anchor,
    Uri pageUri,
    _ForumInlineStyle style,
  ) {
    final String label = normalizeForumText(anchor.text);
    if (label.isEmpty) {
      return null;
    }
    final _ForumContentUri? target = _resolveLink(
      pageUri,
      anchor.attributes['href'],
    );
    if (target == null) {
      return null;
    }
    return ForumPostLinkInline(
      label: label,
      uri: target.uri,
      kind: target.kind,
      threadId: target.threadId,
      postId: target.postId,
      bold: style.bold,
      italic: style.italic,
      code: style.code,
    );
  }

  _ForumContentUri? _resolveLink(Uri pageUri, String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final Uri uri;
    try {
      uri = pageUri.resolve(value.trim());
    } on FormatException {
      return null;
    }
    if ((uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }

    if (originPolicy.isAllowed(uri)) {
      final Uri sanitized = _withoutSensitiveParameters(uri);
      if (_isDownloadUri(sanitized)) {
        return _ForumContentUri(
          uri: sanitized,
          kind: ForumPostLinkKind.download,
        );
      }
      final _ForumInternalTarget? target = _internalTarget(sanitized);
      if (target == null) {
        return null;
      }
      if (target.postId != null) {
        return _ForumContentUri(
          uri: sanitized,
          kind: ForumPostLinkKind.internalPost,
          threadId: target.threadId,
          postId: target.postId,
        );
      }
      return _ForumContentUri(
        uri: sanitized,
        kind: ForumPostLinkKind.internalThread,
        threadId: target.threadId,
      );
    }

    if (uri.host.toLowerCase() == pageUri.host.toLowerCase() ||
        _hasSensitiveParameters(uri)) {
      return null;
    }
    return _ForumContentUri(uri: uri, kind: ForumPostLinkKind.external);
  }

  Uri? _resolveSameOrigin(Uri pageUri, String? value) {
    final Uri? uri = originPolicy.resolveAllowed(pageUri, value);
    return uri == null ? null : _withoutSensitiveParameters(uri);
  }

  bool _isDownloadUri(Uri uri) {
    if (uri.path.toLowerCase().startsWith('/data/attachment/')) {
      return true;
    }
    if (uri.path.toLowerCase() != '/forum.php') {
      return false;
    }
    final String mod = _parameter(uri, 'mod').toLowerCase();
    return (mod == 'attachment' || mod == 'image') &&
        (queryInt(uri, 'aid') ?? 0) > 0;
  }

  _ForumInternalTarget? _internalTarget(Uri uri) {
    final String path = uri.path.toLowerCase();
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
    ).firstMatch(path);
    final int? rewrittenThreadId = int.tryParse(rewritten?.group(1) ?? '');
    if (rewrittenThreadId != null && rewrittenThreadId > 0) {
      return _ForumInternalTarget(
        threadId: rewrittenThreadId,
        postId: fragmentPostId,
      );
    }

    final String mod = _parameter(uri, 'mod').toLowerCase();
    final String goto = _parameter(uri, 'goto').toLowerCase();
    if (path == '/forum.php' && mod == 'viewthread') {
      final int? threadId = queryInt(uri, 'tid');
      if (threadId == null || threadId <= 0) {
        return null;
      }
      final int? postId = queryInt(uri, 'pid') ?? fragmentPostId;
      return _ForumInternalTarget(
        threadId: threadId,
        postId: postId != null && postId > 0 ? postId : null,
      );
    }
    final bool findPost =
        (path == '/forum.php' && mod == 'redirect' && goto == 'findpost') ||
        (path == '/redirect.php' && goto == 'findpost');
    if (!findPost) {
      return null;
    }
    final int? postId = queryInt(uri, 'pid') ?? fragmentPostId;
    if (postId == null || postId <= 0) {
      return null;
    }
    final int? threadId = queryInt(uri, 'ptid') ?? queryInt(uri, 'tid');
    return _ForumInternalTarget(
      threadId: threadId != null && threadId > 0 ? threadId : null,
      postId: postId,
    );
  }

  bool _hasSensitiveParameters(Uri uri) {
    if (uri.userInfo.isNotEmpty) {
      return true;
    }
    for (final String component in _decode(uri.query).split(RegExp(r'[&;]'))) {
      final String name = _queryName(component);
      if (_isSensitiveName(name)) {
        return true;
      }
    }
    final String path = _decode(uri.path).toLowerCase();
    return _hasSensitiveFragment(uri.fragment) ||
        RegExp(r';(?:jsessionid|phpsessid|sessionid|sid)=').hasMatch(path);
  }

  Uri _withoutSensitiveParameters(Uri uri) {
    final List<String> parameters = uri.query
        .split(RegExp(r'[&;]'))
        .where(
          (String component) =>
              component.isNotEmpty && !_isSensitiveName(_queryName(component)),
        )
        .toList(growable: false);
    final String fragment = _hasSensitiveFragment(uri.fragment)
        ? ''
        : uri.fragment;
    return uri.replace(query: parameters.join('&'), fragment: fragment);
  }

  bool _hasSensitiveFragment(String value) {
    final String fragment = _decode(value);
    for (final String component in fragment.split(RegExp(r'[?&;]'))) {
      if (component.contains('=') && _isSensitiveName(_queryName(component))) {
        return true;
      }
    }
    return false;
  }

  String _queryName(String component) {
    final int separator = component.indexOf('=');
    final String source = separator < 0
        ? component
        : component.substring(0, separator);
    return _decode(
      source,
    ).toLowerCase().replaceFirst(RegExp(r'^(?:amp;)+'), '');
  }

  bool _isSensitiveName(String name) {
    return const <String>{
          'formhash',
          'loginhash',
          'auth',
          'authkey',
          'authorization',
          'api_key',
          'apikey',
          'bearer',
          'client_secret',
          'code',
          'token',
          'access_token',
          'id_token',
          'oauth_token',
          'refresh_token',
          'jwt',
          'password',
          'passwd',
          'cookie',
          'credential',
          'phpsessid',
          'session',
          'sessionid',
          'sid',
          'signature',
          'sig',
          'samlrequest',
          'samlresponse',
          'secret',
          'ticket',
          'x-amz-credential',
          'x-amz-security-token',
          'x-amz-signature',
          'x-goog-credential',
          'x-goog-signature',
        }.contains(name) ||
        name.endsWith('_token');
  }

  String _decode(String value) {
    try {
      return Uri.decodeQueryComponent(value);
    } on FormatException {
      return value;
    }
  }

  String _parameter(Uri uri, String name) {
    for (final String component in uri.query.split('&')) {
      final int separator = component.indexOf('=');
      if (separator < 0 || _queryName(component) != name) {
        continue;
      }
      return _decode(component.substring(separator + 1));
    }
    return '';
  }

  String _sanitizeLegacyHtml(String source, Uri pageUri) {
    final dom.DocumentFragment fragment = html_parser.parseFragment(source);
    _removeComments(fragment);
    for (final dom.Element element
        in fragment
            .querySelectorAll(_excludedSelector)
            .toList(growable: false)) {
      element.remove();
    }
    for (final dom.Element element
        in fragment.querySelectorAll('*').toList(growable: false)) {
      final String tag = element.localName ?? '';
      if (tag == 'a') {
        final _ForumContentUri? target = _resolveLink(
          pageUri,
          element.attributes['href'],
        );
        if (target == null) {
          element.attributes.remove('href');
        } else {
          element.attributes['href'] = target.uri.toString();
        }
      } else if (tag == 'img') {
        final ForumPostImageInline? image = _parseImage(element, pageUri);
        if (image == null) {
          element.remove();
          continue;
        }
        element.attributes['src'] = image.uri.toString();
        element.attributes['alt'] = image.alt;
      }
      for (final Object name in element.attributes.keys.toList()) {
        if (!_allowedAttribute(tag, name.toString().toLowerCase())) {
          element.attributes.remove(name);
        }
      }
    }
    return fragment.outerHtml.trim();
  }

  void _removeComments(dom.Node node) {
    for (final dom.Node child in node.nodes.toList(growable: false)) {
      if (child is dom.Comment) {
        child.remove();
      } else {
        _removeComments(child);
      }
    }
  }

  bool _allowedAttribute(String tag, String name) {
    if (name == 'class') {
      return true;
    }
    if (tag == 'a') {
      return name == 'href' || name == 'title';
    }
    if (tag == 'img') {
      return const <String>{
        'src',
        'alt',
        'id',
        'width',
        'height',
        'smilieid',
      }.contains(name);
    }
    return false;
  }
}

const String _excludedSelector =
    'script, style, noscript, form, input, button, select, option, textarea, '
    'iframe, frame, frameset, object, embed, applet, portal, template, base, '
    'link, meta, svg';

class _ForumPostContentCollector {
  _ForumPostContentCollector(this.parser, this.pageUri);

  final ForumPostContentParser parser;
  final Uri pageUri;
  final List<ForumPostContentBlock> blocks = <ForumPostContentBlock>[];
  _ForumInlineBuffer _current = _ForumInlineBuffer();

  void collect(dom.Element message) {
    for (final dom.Node node in message.nodes) {
      _visit(node, const _ForumInlineStyle());
    }
    _flushParagraph();
  }

  void _visit(dom.Node node, _ForumInlineStyle style) {
    if (node is dom.Text) {
      _current.addText(node.data, style);
      return;
    }
    if (node is! dom.Element || _isExcluded(node)) {
      return;
    }
    if (_isQuote(node)) {
      _flushParagraph();
      final List<ForumPostInline> inlines = _collectFlat(node, style);
      if (inlines.isNotEmpty) {
        blocks.add(ForumPostQuoteBlock(inlines: inlines));
      }
      return;
    }
    if (_isCodeBlock(node)) {
      _flushParagraph();
      final List<ForumPostInline> inlines = _collectCode(node);
      if (inlines.isNotEmpty) {
        blocks.add(ForumPostCodeBlock(inlines: inlines));
      }
      return;
    }

    final String tag = node.localName ?? '';
    if (tag == 'br') {
      _current.addLineBreak();
      return;
    }
    if (tag == 'hr') {
      _flushParagraph();
      return;
    }
    if (tag == 'img') {
      _addImage(node, _current);
      return;
    }

    final _ForumInlineStyle childStyle = style.forElement(node);
    if (tag == 'a') {
      final ForumPostLinkInline? link = parser._parseLink(
        node,
        pageUri,
        childStyle,
      );
      if (link != null && node.querySelector('img') == null) {
        _current.add(link);
      } else {
        for (final dom.Node child in node.nodes) {
          _visit(child, childStyle);
        }
      }
      return;
    }

    final bool block = _isBlock(node);
    if (block) {
      _flushParagraph();
      if (tag == 'li') {
        _current.addText('• ', childStyle);
      }
    }
    for (final dom.Node child in node.nodes) {
      _visit(child, childStyle);
    }
    if (block) {
      _flushParagraph();
    }
  }

  List<ForumPostInline> _collectFlat(
    dom.Element element,
    _ForumInlineStyle style,
  ) {
    final _ForumInlineBuffer buffer = _ForumInlineBuffer();

    void visit(dom.Node node, _ForumInlineStyle currentStyle) {
      if (node is dom.Text) {
        buffer.addText(node.data, currentStyle);
        return;
      }
      if (node is! dom.Element || _isExcluded(node)) {
        return;
      }
      final String tag = node.localName ?? '';
      if (tag == 'br') {
        buffer.addLineBreak();
        return;
      }
      if (tag == 'img') {
        _addImage(node, buffer);
        return;
      }
      final _ForumInlineStyle childStyle = currentStyle.forElement(node);
      if (tag == 'a') {
        final ForumPostLinkInline? link = parser._parseLink(
          node,
          pageUri,
          childStyle,
        );
        if (link != null && node.querySelector('img') == null) {
          buffer.add(link);
        } else {
          for (final dom.Node child in node.nodes) {
            visit(child, childStyle);
          }
        }
        return;
      }
      final bool block = _isBlock(node) || _isQuote(node) || _isCodeBlock(node);
      if (block) {
        buffer.addBoundary();
        if (tag == 'li') {
          buffer.addText('• ', childStyle);
        }
      }
      for (final dom.Node child in node.nodes) {
        visit(child, childStyle);
      }
      if (block) {
        buffer.addBoundary();
      }
    }

    for (final dom.Node node in element.nodes) {
      visit(node, style);
    }
    return buffer.finish();
  }

  List<ForumPostInline> _collectCode(dom.Element element) {
    final StringBuffer text = StringBuffer();

    void newline() {
      if (text.isNotEmpty && !text.toString().endsWith('\n')) {
        text.write('\n');
      }
    }

    void visit(dom.Node node) {
      if (node is dom.Text) {
        text.write(node.data.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
        return;
      }
      if (node is! dom.Element || _isExcluded(node)) {
        return;
      }
      final String tag = node.localName ?? '';
      if (tag == 'br') {
        text.write('\n');
        return;
      }
      final bool block = node != element && _isBlock(node);
      if (block) {
        newline();
      }
      for (final dom.Node child in node.nodes) {
        visit(child);
      }
      if (block) {
        newline();
      }
    }

    for (final dom.Node node in element.nodes) {
      visit(node);
    }
    final String value = text
        .toString()
        .replaceAll('\u00a0', ' ')
        .replaceFirst(RegExp(r'^\n+'), '')
        .replaceFirst(RegExp(r'\n+$'), '');
    if (value.isEmpty) {
      return const <ForumPostInline>[];
    }
    final List<ForumPostInline> result = <ForumPostInline>[];
    final List<String> lines = value.split('\n');
    for (int index = 0; index < lines.length; index += 1) {
      if (lines[index].isNotEmpty) {
        result.add(ForumPostTextInline(text: lines[index], code: true));
      }
      if (index + 1 < lines.length) {
        result.add(const ForumPostLineBreakInline());
      }
    }
    return List<ForumPostInline>.unmodifiable(result);
  }

  void _addImage(dom.Element element, _ForumInlineBuffer buffer) {
    final ForumPostImageInline? image = parser._parseImage(element, pageUri);
    if (image != null) {
      buffer.add(image);
      return;
    }
    final String alt = normalizeForumText(element.attributes['alt'] ?? '');
    if (alt.isNotEmpty) {
      buffer.addText(alt, const _ForumInlineStyle());
    }
  }

  void _flushParagraph() {
    final List<ForumPostInline> inlines = _current.finish();
    if (inlines.isNotEmpty) {
      blocks.add(ForumPostParagraphBlock(inlines: inlines));
    }
    _current = _ForumInlineBuffer();
  }

  bool _isExcluded(dom.Element element) {
    return const <String>{
      'script',
      'style',
      'noscript',
      'form',
      'input',
      'button',
      'select',
      'option',
      'textarea',
      'iframe',
      'frame',
      'frameset',
      'object',
      'embed',
      'applet',
      'portal',
      'template',
      'base',
      'link',
      'meta',
      'svg',
    }.contains(element.localName);
  }

  bool _isQuote(dom.Element element) {
    return element.localName == 'blockquote' ||
        element.classes.contains('quote');
  }

  bool _isCodeBlock(dom.Element element) {
    return element.localName == 'pre' ||
        element.classes.contains('blockcode') ||
        (element.localName == 'div' && element.classes.contains('code'));
  }

  bool _isBlock(dom.Element element) {
    return const <String>{
      'address',
      'article',
      'aside',
      'center',
      'dd',
      'div',
      'dl',
      'dt',
      'figcaption',
      'figure',
      'footer',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'header',
      'li',
      'main',
      'nav',
      'ol',
      'p',
      'section',
      'table',
      'tbody',
      'td',
      'tfoot',
      'th',
      'thead',
      'tr',
      'ul',
    }.contains(element.localName);
  }
}

class _ForumInlineBuffer {
  final List<ForumPostInline> _values = <ForumPostInline>[];

  void add(ForumPostInline value) {
    _values.add(value);
  }

  void addText(String value, _ForumInlineStyle style) {
    String normalized = value
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[\t\r\n\f\v ]+'), ' ');
    if (_values.isEmpty || _values.last is ForumPostLineBreakInline) {
      normalized = normalized.replaceFirst(RegExp(r'^ +'), '');
    }
    if (normalized.isEmpty) {
      return;
    }
    final ForumPostInline? last = _values.isEmpty ? null : _values.last;
    if (last is ForumPostTextInline &&
        last.bold == style.bold &&
        last.italic == style.italic &&
        last.code == style.code) {
      _values[_values.length - 1] = ForumPostTextInline(
        text: '${last.text}$normalized',
        bold: style.bold,
        italic: style.italic,
        code: style.code,
      );
      return;
    }
    _values.add(
      ForumPostTextInline(
        text: normalized,
        bold: style.bold,
        italic: style.italic,
        code: style.code,
      ),
    );
  }

  void addLineBreak() {
    _values.add(const ForumPostLineBreakInline());
  }

  void addBoundary() {
    if (_values.isNotEmpty && _values.last is! ForumPostLineBreakInline) {
      addLineBreak();
    }
  }

  List<ForumPostInline> finish() {
    while (_values.isNotEmpty &&
        (_values.first is ForumPostLineBreakInline ||
            _isWhitespace(_values.first))) {
      _values.removeAt(0);
    }
    while (_values.isNotEmpty &&
        (_values.last is ForumPostLineBreakInline ||
            _isWhitespace(_values.last))) {
      _values.removeLast();
    }
    if (_values.isNotEmpty && _values.first is ForumPostTextInline) {
      final ForumPostTextInline first = _values.first as ForumPostTextInline;
      _values[0] = ForumPostTextInline(
        text: first.text.replaceFirst(RegExp(r'^ +'), ''),
        bold: first.bold,
        italic: first.italic,
        code: first.code,
      );
    }
    if (_values.isNotEmpty && _values.last is ForumPostTextInline) {
      final ForumPostTextInline last = _values.last as ForumPostTextInline;
      _values[_values.length - 1] = ForumPostTextInline(
        text: last.text.replaceFirst(RegExp(r' +$'), ''),
        bold: last.bold,
        italic: last.italic,
        code: last.code,
      );
    }
    return List<ForumPostInline>.unmodifiable(_values);
  }

  bool _isWhitespace(ForumPostInline value) {
    return value is ForumPostTextInline && value.text.trim().isEmpty;
  }
}

class _ForumInlineStyle {
  const _ForumInlineStyle({
    this.bold = false,
    this.italic = false,
    this.code = false,
  });

  final bool bold;
  final bool italic;
  final bool code;

  _ForumInlineStyle forElement(dom.Element element) {
    final String tag = element.localName ?? '';
    final String style = element.attributes['style']?.toLowerCase() ?? '';
    return _ForumInlineStyle(
      bold:
          bold ||
          tag == 'b' ||
          tag == 'strong' ||
          RegExp(r'font-weight\s*:\s*(?:bold|[6-9]00)').hasMatch(style),
      italic:
          italic ||
          tag == 'i' ||
          tag == 'em' ||
          RegExp(r'font-style\s*:\s*italic').hasMatch(style),
      code: code || tag == 'code' || tag == 'kbd' || tag == 'samp',
    );
  }
}

class _ForumContentUri {
  const _ForumContentUri({
    required this.uri,
    required this.kind,
    this.threadId,
    this.postId,
  });

  final Uri uri;
  final ForumPostLinkKind kind;
  final int? threadId;
  final int? postId;
}

class _ForumInternalTarget {
  const _ForumInternalTarget({this.threadId, this.postId});

  final int? threadId;
  final int? postId;
}
