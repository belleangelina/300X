import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

class ForumThreadParser
{
    const ForumThreadParser();

    ForumThreadPage parse(
        String html,
        Uri pageUri,
        ForumBoard board,
        {
        int? expectedTid,
    })
    {
        final dom.Document document = html_parser.parse(html);
        if (document.querySelector('form#loginform') != null ||
                document.body?.classes.contains('pg_logging') == true)
        {
            throw const ForumSessionExpiredException();
        }
        if (document.body?.classes.contains('pg_viewthread') != true)
        {
            final String message = normalizeForumText(
                document.querySelector('.jump_c p, #messagetext, .tip')?.text ?? '',
            );
            throw ForumParseException(message.isEmpty ? '无法识别论坛主题页面' : message);
        }

        final int? tid =
                expectedTid ??
                queryInt(pageUri, 'tid') ??
                _extractTidFromDocument(document);
        if (tid == null)
        {
            throw const ForumParseException('主题页面缺少 tid');
        }

        final _ThreadPagination pagination = _parsePagination(document, pageUri);
        final List<dom.Element> postElements = document.querySelectorAll(
            '.plc.cl[id^="pid"], .plc[id^="pid"]',
        );
        if (postElements.isEmpty)
        {
            throw const ForumParseException('主题页面中没有可识别的楼层');
        }

        final String originalAuthor = normalizeForumText(
            postElements.first.querySelector('.authi .z a')?.text ?? '',
        );
        final List<SourcePost> posts = <SourcePost>[];
        for (int index = 0; index < postElements.length; index++)
        {
            final SourcePost? post = _parsePost(
                postElements[index],
                pageUri,
                tid,
                pagination.current,
                index,
                originalAuthor,
                board,
            );
            if (post != null)
            {
                posts.add(post);
            }
        }
        if (posts.isEmpty)
        {
            throw const ForumParseException('主题楼层缺少可读取正文');
        }

        final dom.Element? titleElement = document.querySelector('.view_tit');
        return ForumThreadPage(
            tid: tid,
            board: board,
            title: normalizeForumText(
                titleElement?.text ?? document.querySelector('title')?.text ?? '未命名主题',
            ),
            typeName: _parseTypeName(titleElement),
            uri: pageUri,
            posts: posts,
            currentPage: pagination.current,
            totalPages: pagination.total,
            nextPageUri: pagination.next,
            originalPosterUri: _parseOriginalPosterUri(document, pageUri, tid),
        );
    }

    String _parseTypeName(dom.Element? titleElement)
    {
        final String value = normalizeForumText(
            titleElement?.querySelector('em')?.text ?? '',
        ).replaceAll(RegExp(r'^[\s\[\]【】()（）]+|[\s\[\]【】()（）]+$'), '');
        return value.isEmpty ? '' : '#$value';
    }

    Uri? _parseOriginalPosterUri(dom.Document document, Uri pageUri, int tid)
    {
        for (final dom.Element anchor in document.querySelectorAll(
            'a[href*="mod=viewthread"][href*="authorid="]',
        ))
        {
            final String? href = anchor.attributes['href'];
            if (href == null || href.isEmpty)
            {
                continue;
            }
            final Uri uri = pageUri.resolve(href);
            if (uri.host == pageUri.host &&
                    queryInt(uri, 'tid') == tid &&
                    uri.queryParameters['authorid']?.isNotEmpty == true)
            {
                return uri.replace(
                    queryParameters: <String, dynamic>{
                        ...uri.queryParameters,
                        'page': '1',
                        'mobile': '2',
                    },
                );
            }
        }
        return null;
    }

    int? _extractTidFromDocument(dom.Document document)
    {
        for (final dom.Element anchor in document.querySelectorAll(
            'a[href*="mod=viewthread"][href*="tid="]',
        ))
        {
            final String? href = anchor.attributes['href'];
            if (href == null)
            {
                continue;
            }
            final int? tid = queryInt(Uri.parse(href), 'tid');
            if (tid != null)
            {
                return tid;
            }
        }
        return null;
    }

    SourcePost? _parsePost(
        dom.Element element,
        Uri pageUri,
        int tid,
        int page,
        int index,
        String originalAuthor,
        ForumBoard board,
    )
    {
        final Match? pidMatch = RegExp(r'^pid(\d+)$').firstMatch(element.id);
        final int? pid = int.tryParse(pidMatch?.group(1) ?? '');
        final dom.Element? message = element.querySelector('.message');
        if (pid == null || message == null)
        {
            return null;
        }

        final String author = normalizeForumText(
            element.querySelector('.authi .z a')?.text ?? '',
        );
        final String floorText = normalizeForumText(
            element.querySelector('.authi li.mtit .y')?.text ?? '',
        );
        final int floor =
                int.tryParse(RegExp(r'(\d+)').firstMatch(floorText)?.group(1) ?? '') ??
                index + 1;
        final bool isOriginalPoster =
                index == 0 || (author.isNotEmpty && author == originalAuthor);
        final _PostContentCollector collector = _PostContentCollector(
            pageUri,
            retainSubstantiveQuotes:
                    board.kind == LibraryKind.novel && isOriginalPoster,
        );
        collector.collect(message);
        for (final dom.Element attachments in element.querySelectorAll(
            'ul.img_one',
        ))
        {
            collector.collect(attachments);
        }

        return SourcePost(
            pid: pid,
            tid: tid,
            page: page,
            floor: floor,
            author: author,
            timeLabel: directText(element.querySelector('.authi li.mtime')),
            isOriginalPoster: isOriginalPoster,
            blocks: collector.blocks,
            links: _parseLinks(message, pageUri, tid),
        );
    }

    List<ThreadLink> _parseLinks(
        dom.Element message,
        Uri pageUri,
        int currentTid,
    )
    {
        final List<ThreadLink> result = <ThreadLink>[];
        final Set<String> seen = <String>{};
        for (final dom.Element anchor in message.querySelectorAll('a[href]'))
        {
            if (_isExcludedLink(anchor, message))
            {
                continue;
            }
            final String? href = anchor.attributes['href'];
            if (href == null || href.trim().isEmpty)
            {
                continue;
            }
            final Uri uri = pageUri.resolve(href.trim());
            if (uri.scheme != 'https' && uri.scheme != 'http')
            {
                continue;
            }

            final String label = normalizeForumText(anchor.text);
            if (_isDirectoryLink(uri, label, pageUri))
            {
                final String key = 'directory:${uri.toString()}';
                if (seen.add(key))
                {
                    result.add(
                        ThreadLink(label: label, uri: uri, kind: ThreadLinkKind.directory),
                    );
                }
                continue;
            }

            final int? tid =
                    queryInt(uri, 'tid') ??
                    queryInt(uri, 'ptid') ??
                    _friendlyThreadId(uri.path);
            final int? pid = queryInt(uri, 'pid') ?? _fragmentPostId(uri.fragment);
            if (tid == null && pid == null)
            {
                continue;
            }

            final ThreadLinkKind kind = _linkKind(
                label,
                tid ?? currentTid,
                pid,
                currentTid,
            );
            final String key = '${tid ?? currentTid}:${pid ?? 0}:$label';
            if (!seen.add(key))
            {
                continue;
            }
            result.add(
                ThreadLink(
                    label: label.isEmpty ? '原帖链接' : label,
                    uri: uri,
                    kind: kind,
                    tid: tid ?? currentTid,
                    pid: pid,
                ),
            );
        }
        return result;
    }

    bool _isExcludedLink(dom.Element anchor, dom.Element message)
    {
        dom.Element? current = anchor;
        while (current != null && !identical(current, message))
        {
            if (current.classes.any(
                (String value) => const <String>{
                    'quote',
                    'pstatus',
                    'locked',
                    'attach_info',
                    'signature',
                    'sign',
                }.contains(value),
            ))
            {
                return true;
            }
            current = current.parent;
        }
        return false;
    }

    bool _isDirectoryLink(Uri uri, String label, Uri pageUri)
    {
        return uri.scheme == pageUri.scheme &&
                uri.host == pageUri.host &&
                uri.port == pageUri.port &&
                uri.path.endsWith('/misc.php') &&
                uri.queryParameters['mod'] == 'tag' &&
                uri.queryParameters['id']?.isNotEmpty == true &&
                RegExp(r'(目录|目錄|索引|合集|合輯)').hasMatch(label);
    }

    ThreadLinkKind _linkKind(
        String label,
        int targetTid,
        int? pid,
        int currentTid,
    )
    {
        if (RegExp(r'(上一|前一|上篇|上章|上话|上話)').hasMatch(label))
        {
            return ThreadLinkKind.previous;
        }
        if (RegExp(r'(下一|后一|後一|下篇|下章|下话|下話)').hasMatch(label))
        {
            return ThreadLinkKind.next;
        }
        if (pid != null ||
                RegExp(
                    r'(第\s*[零〇一二三四五六七八九十百两兩\d]+\s*(?:话|話|章|回|节|節|卷)|\d+(?:\.\d+)?\s*(?:话|話|章|回|节|節|卷)|ch(?:apter)?\.?\s*\d|序章|终章|終章|最终|最終|番外|特典|附录|附錄)',
                    caseSensitive: false,
                ).hasMatch(label))
        {
            return ThreadLinkKind.chapter;
        }
        if (targetTid == currentTid)
        {
            return ThreadLinkKind.chapter;
        }
        return ThreadLinkKind.related;
    }

    int? _friendlyThreadId(String path)
    {
        return int.tryParse(
            RegExp(r'(?:thread|forum)-(\d+)').firstMatch(path)?.group(1) ?? '',
        );
    }

    int? _fragmentPostId(String fragment)
    {
        return int.tryParse(
            RegExp(r'pid(\d+)').firstMatch(fragment)?.group(1) ?? '',
        );
    }

    _ThreadPagination _parsePagination(dom.Document document, Uri pageUri)
    {
        final dom.Element? pageElement = document.querySelector('.pg');
        if (pageElement == null)
        {
            return const _ThreadPagination(current: 1, total: 1);
        }
        final int current =
                int.tryParse(
                    pageElement
                                    .querySelector('input[name="custompage"]')
                                    ?.attributes['value'] ??
                            '',
                ) ??
                1;
        int total = current;
        final String? lastHref = pageElement
                .querySelector('a.last[href*="page="]')
                ?.attributes['href'];
        if (lastHref != null)
        {
            total = queryInt(pageUri.resolve(lastHref), 'page') ?? total;
        }
        final String? nextHref = pageElement
                .querySelector('a.nxt[href]')
                ?.attributes['href'];
        return _ThreadPagination(
            current: current,
            total: total,
            next: nextHref == null ? null : pageUri.resolve(nextHref),
        );
    }
}

class _PostContentCollector
{
    _PostContentCollector(this.pageUri, {required this.retainSubstantiveQuotes});

    final Uri pageUri;
    final bool retainSubstantiveQuotes;
    final List<PostContentBlock> blocks = <PostContentBlock>[];
    final Set<Uri> _seenImages = <Uri>{};
    final Set<String> _seenSubstantiveQuotes = <String>{};
    final StringBuffer _text = StringBuffer();
    bool _heading = false;
    bool _substantiveQuote = false;

    void collect(dom.Element message)
    {
        for (final dom.Node node in message.nodes)
        {
            _visit(node, false, false);
        }
        _flushText();
    }

    void _visit(dom.Node node, bool heading, bool substantiveQuote)
    {
        if (node is dom.Text)
        {
            _text.write(node.data);
            _heading = _heading || heading;
            _substantiveQuote = _substantiveQuote || substantiveQuote;
            return;
        }
        if (node is! dom.Element)
        {
            return;
        }

        final bool retainedQuote = _shouldRetainSubstantiveQuote(node);
        if (_shouldExclude(node, retainedQuote: retainedQuote))
        {
            return;
        }
        if (retainedQuote)
        {
            final String body = normalizeForumText(node.text);
            if (!_seenSubstantiveQuotes.add(body))
            {
                return;
            }
            _flushText();
            for (final dom.Node child in node.nodes)
            {
                _visit(child, heading, true);
            }
            _flushText();
            return;
        }

        final String tag = node.localName ?? '';
        if (tag == 'br' || tag == 'hr')
        {
            _flushText();
            return;
        }
        if (tag == 'img')
        {
            _flushText();
            _addImage(node, substantiveQuote);
            return;
        }

        final bool block = const <String>{
            'p',
            'div',
            'li',
            'h1',
            'h2',
            'h3',
            'h4',
            'h5',
            'h6',
            'pre',
        }.contains(tag);
        final bool childHeading = tag.startsWith('h') && tag.length == 2;
        if (block)
        {
            _flushText();
        }
        for (final dom.Node child in node.nodes)
        {
            _visit(child, heading || childHeading, substantiveQuote);
        }
        if (block)
        {
            _flushText();
        }
    }

    bool _shouldRetainSubstantiveQuote(dom.Element element)
    {
        if (!retainSubstantiveQuotes || !element.classes.contains('quote'))
        {
            return false;
        }
        if (element.querySelector(
                    'a[href*="goto=findpost"], '
                    'a[href*="mod=redirect"], '
                    'a[href^="#pid"]',
                ) !=
                null)
        {
            return false;
        }
        final String text = normalizeForumText(
            element.text,
        ).replaceAll(RegExp(r'\s+'), '');
        return text.length >= 600;
    }

    bool _shouldExclude(dom.Element element, {required bool retainedQuote})
    {
        final String tag = element.localName ?? '';
        if (tag == 'script' || tag == 'style' || tag == 'noscript')
        {
            return true;
        }
        return element.classes.any(
            (String value) =>
                    const <String>{
                        'quote',
                        'pstatus',
                        'locked',
                        'attach_info',
                        'signature',
                        'sign',
                    }.contains(value) &&
                    !(value == 'quote' && retainedQuote),
        );
    }

    void _addImage(dom.Element image, bool substantiveQuote)
    {
        if (image.attributes.containsKey('smilieid'))
        {
            return;
        }
        final String source =
                image.attributes['zoomfile'] ??
                image.attributes['file'] ??
                image.attributes['data-original'] ??
                image.attributes['src'] ??
                '';
        final String normalizedSource = source.trim();
        if (normalizedSource.isEmpty ||
                RegExp(
                    r'^(?:(?:https?:)?//)?data:',
                    caseSensitive: false,
                ).hasMatch(normalizedSource) ||
                source.contains('static/image/smiley') ||
                source.contains('/uc_server/data/avatar') ||
                source.contains('noavatar') ||
                source.contains('common_'))
        {
            return;
        }
        final int? width = int.tryParse(image.attributes['width'] ?? '');
        final int? height = int.tryParse(image.attributes['height'] ?? '');
        if ((width != null && width <= 64) || (height != null && height <= 64))
        {
            return;
        }

        final Uri uri = pageUri.resolve(normalizedSource);
        if ((uri.scheme != 'https' && uri.scheme != 'http') ||
                !_seenImages.add(uri))
        {
            return;
        }
        blocks.add(
            PostImageBlock(
                uri: uri,
                alt: normalizeForumText(image.attributes['alt'] ?? ''),
                substantiveQuote: substantiveQuote,
            ),
        );
    }

    void _flushText()
    {
        final String value = normalizeForumText(_text.toString());
        _text.clear();
        if (value.isNotEmpty)
        {
            blocks.add(
                PostTextBlock(
                    text: value,
                    heading: _heading,
                    substantiveQuote: _substantiveQuote,
                ),
            );
        }
        _heading = false;
        _substantiveQuote = false;
    }
}

class _ThreadPagination
{
    const _ThreadPagination({
        required this.current,
        required this.total,
        this.next,
    });

    final int current;
    final int total;
    final Uri? next;
}
