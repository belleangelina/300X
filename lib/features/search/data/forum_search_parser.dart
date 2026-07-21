import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/library/data/forum_catalog_parser.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/search/domain/search_models.dart';

class ForumSearchParser
{
    const ForumSearchParser([
        this._catalogParser = const ForumCatalogParser(),
    ]);

    final ForumCatalogParser _catalogParser;

    ForumSearchForm parseForm(String html, Uri pageUri)
    {
        final dom.Document document = html_parser.parse(html);
        _throwIfSessionExpired(document);
        final dom.Element? form = document.querySelector(
            'form[action*="search.php?mod=forum"]',
        );
        final String formHash = form
                ?.querySelector('input[name="formhash"]')
                ?.attributes['value']
                ?.trim() ??
            '';
        final String action = form?.attributes['action']?.trim() ?? '';
        if (formHash.isEmpty || action.isEmpty)
        {
            throw const ForumParseException('无法读取论坛搜索表单');
        }
        final Uri actionUri = pageUri.resolve(action);
        if (actionUri.host != pageUri.host)
        {
            throw const ForumParseException('论坛搜索表单地址无效');
        }
        return ForumSearchForm(
            actionUri: actionUri,
            formHash: formHash,
        );
    }

    ForumSearchPage parseResults(
        String html,
        Uri pageUri,
        LibraryKind kind,
    )
    {
        final dom.Document document = html_parser.parse(html);
        _throwIfSessionExpired(document);
        final String? searchId = pageUri.queryParameters['searchid'];
        if (searchId == null || searchId.isEmpty)
        {
            throw ForumParseException(_messageOrFallback(
                document,
                '论坛未接受本次搜索，请稍后重试',
            ));
        }
        if (document.body?.classes.contains('pg_forum') != true)
        {
            throw ForumParseException(_messageOrFallback(
                document,
                '无法识别论坛搜索结果',
            ));
        }

        final List<SourceThread> threads = <SourceThread>[];
        for (final dom.Element element in document.querySelectorAll(
            '.threadlist > ul > li.list',
        ))
        {
            final ForumBoard? board = _parseBoard(element, pageUri);
            if (board == null || board.kind != kind)
            {
                continue;
            }
            final SourceThread? thread = _catalogParser.parseThreadElement(
                element,
                pageUri,
                board,
                pinned: false,
            );
            if (thread != null && !thread.administrative)
            {
                threads.add(thread);
            }
        }

        final bool hasResultContainer = document.querySelector(
                '.threadlist_box, .threadlist',
            ) !=
            null;
        if (threads.isEmpty && !hasResultContainer)
        {
            throw ForumParseException(_messageOrFallback(
                document,
                '搜索结果页面中没有可识别的主题列表',
            ));
        }

        final _SearchPagination pagination = _parsePagination(
            document,
            pageUri,
        );
        final String keyword = normalizeForumText(
            document.querySelector('input[name="srchtxt"]')
                    ?.attributes['value'] ??
                pageUri.queryParameters['kw'] ??
                '',
        );
        return ForumSearchPage(
            kind: kind,
            keyword: keyword,
            searchId: searchId,
            sourceThreads: threads,
            currentPage: pagination.current,
            totalPages: pagination.total,
            nextPageUri: pagination.next,
        );
    }

    void _throwIfSessionExpired(dom.Document document)
    {
        if (document.querySelector('form#loginform') != null ||
            document.body?.classes.contains('pg_logging') == true)
        {
            throw const ForumSessionExpiredException();
        }
    }

    ForumBoard? _parseBoard(dom.Element element, Uri pageUri)
    {
        final String? href = element
            .querySelector('.threadlist_foot li.mr a[href*="fid="]')
            ?.attributes['href'];
        if (href == null)
        {
            return null;
        }
        final int? fid = queryInt(pageUri.resolve(href), 'fid');
        return fid == null ? null : ForumBoard.fromFid(fid);
    }

    _SearchPagination _parsePagination(
        dom.Document document,
        Uri pageUri,
    )
    {
        final dom.Element? pageElement = document.querySelector('.pg');
        if (pageElement == null)
        {
            return const _SearchPagination(current: 1, total: 1);
        }
        final int current = int.tryParse(
                pageElement.querySelector('input[name="custompage"]')
                        ?.attributes['value'] ??
                    '',
            ) ??
            int.tryParse(normalizeForumText(
                pageElement.querySelector('strong')?.text ?? '',
            )) ??
            1;
        int total = current;
        final String? lastHref = pageElement
            .querySelector('a.last[href*="page="]')
            ?.attributes['href'];
        if (lastHref != null)
        {
            total = queryInt(pageUri.resolve(lastHref), 'page') ?? total;
        }
        if (total == current)
        {
            final String title = pageElement.querySelector('label span')
                    ?.attributes['title'] ??
                '';
            total = int.tryParse(
                    RegExp(r'(\d+)').firstMatch(title)?.group(1) ?? '',
                ) ??
                total;
        }
        final String? nextHref = pageElement
            .querySelector('a.nxt[href]')
            ?.attributes['href'];
        Uri? nextUri = nextHref == null
            ? null
            : pageUri.resolve(nextHref);
        if (nextUri?.host != pageUri.host)
        {
            nextUri = null;
        }
        return _SearchPagination(
            current: current,
            total: total,
            next: nextUri,
        );
    }

    String _messageOrFallback(
        dom.Document document,
        String fallback,
    )
    {
        final String message = normalizeForumText(
            document.querySelector(
                    '.jump_c p, #messagetext p, #messagetext, .tip',
                )
                ?.text ??
                '',
        );
        return message.isEmpty ? fallback : message;
    }
}

class _SearchPagination
{
    const _SearchPagination({
        required this.current,
        required this.total,
        this.next,
    });

    final int current;
    final int total;
    final Uri? next;
}
