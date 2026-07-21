import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/domain/library_models.dart';

class ForumCatalogParser
{
    const ForumCatalogParser();

    ForumCatalogPage parse(
        String html,
        Uri pageUri,
        ForumBoard board,
    )
    {
        final dom.Document document = html_parser.parse(html);
        if (_isLoginPage(document))
        {
            throw const ForumSessionExpiredException();
        }

        final dom.Element? body = document.body;
        if (body?.classes.contains('pg_forumdisplay') != true)
        {
            final String message = normalizeForumText(
                document.querySelector('.jump_c p, #messagetext, .tip')?.text ??
                    '',
            );
            throw ForumParseException(
                message.isEmpty ? '无法识别论坛版块页面' : message,
            );
        }

        final List<ForumCategory> categories = _parseCategories(
            document,
            pageUri,
            board,
        );
        final List<SourceThread> threads = document
            .querySelectorAll('.threadlist > ul > li.list')
            .map(
                (dom.Element element) => parseThreadElement(
                    element,
                    pageUri,
                    board,
                    pinned: false,
                ),
            )
            .whereType<SourceThread>()
            .toList(growable: false);
        final List<SourceThread> pinnedThreads = document
            .querySelectorAll('.threadlist > ul > li.list_top')
            .map(
                (dom.Element element) => parseThreadElement(
                    element,
                    pageUri,
                    board,
                    pinned: true,
                ),
            )
            .whereType<SourceThread>()
            .toList(growable: false);

        if (threads.isEmpty && pinnedThreads.isEmpty)
        {
            final bool explicitlyEmpty = document.querySelector(
                    '.threadlist .emp, .threadlist .empty, .nothread',
                ) !=
                null;
            if (!explicitlyEmpty)
            {
                throw const ForumParseException('版块页面中没有可识别的主题列表');
            }
        }

        final _Pagination pagination = _parsePagination(document, pageUri);
        return ForumCatalogPage(
            board: board,
            threads: threads,
            pinnedThreads: pinnedThreads,
            categories: categories,
            currentPage: pagination.current,
            totalPages: pagination.total,
            nextPageUri: pagination.next,
        );
    }

    bool _isLoginPage(dom.Document document)
    {
        return document.querySelector('form#loginform') != null ||
            document.body?.classes.contains('pg_logging') == true;
    }

    List<ForumCategory> _parseCategories(
        dom.Document document,
        Uri pageUri,
        ForumBoard board,
    )
    {
        final Map<int, ForumCategory> result = <int, ForumCategory>{};
        for (final dom.Element anchor in document.querySelectorAll(
            '#dhnavs_li a[href*="typeid="], '
            '.swiper-wrapper a[href*="typeid="]',
        ))
        {
            final String? href = anchor.attributes['href'];
            if (href == null || href.isEmpty)
            {
                continue;
            }
            final Uri uri = pageUri.resolve(href);
            final int? typeId = queryInt(uri, 'typeid');
            final String name = normalizeForumText(anchor.text);
            if (typeId == null || name.isEmpty || _isAdministrativeType(name))
            {
                continue;
            }
            result.putIfAbsent(
                typeId,
                () => ForumCategory(
                    board: board,
                    typeId: typeId,
                    name: name,
                    uri: uri,
                ),
            );
        }
        return result.values.toList(growable: false);
    }

    SourceThread? parseThreadElement(
        dom.Element element,
        Uri pageUri,
        ForumBoard board, {
        required bool pinned,
    })
    {
        dom.Element? anchor;
        for (final dom.Element candidate in element.querySelectorAll(
            'a[href*="mod=viewthread"][href*="tid="]',
        ))
        {
            if (candidate.querySelector('.threadlist_tit') != null || pinned)
            {
                anchor = candidate;
                break;
            }
        }
        if (anchor == null)
        {
            return null;
        }

        final String? href = anchor.attributes['href'];
        if (href == null || href.isEmpty)
        {
            return null;
        }
        final Uri uri = pageUri.resolve(href);
        final int? tid = queryInt(uri, 'tid');
        if (tid == null)
        {
            return null;
        }

        final String title = normalizeForumText(
            element.querySelector('.threadlist_tit em')?.text ??
                element.querySelector('.threadlist_tit')?.text ??
                element.querySelector('em')?.text ??
                anchor.text,
        );
        if (title.isEmpty)
        {
            return null;
        }

        final dom.Element? typeAnchor = element.querySelector(
            '.threadlist_foot li.mr a[href*="typeid="]',
        );
        final Uri? typeUri = typeAnchor?.attributes['href'] == null
            ? null
            : pageUri.resolve(typeAnchor!.attributes['href']!);
        final String typeName = normalizeForumText(typeAnchor?.text ?? '');
        final List<dom.Element> counters = element.querySelectorAll(
            '.threadlist_foot li:not(.mr)',
        );
        final String timeLabel = directText(
            element.querySelector('.threadlist_top .mtime'),
        );

        return SourceThread(
            tid: tid,
            board: board,
            typeId: typeUri == null ? null : queryInt(typeUri, 'typeid'),
            typeName: typeName,
            title: title,
            summary: normalizeForumText(
                element.querySelector('.threadlist_mes')?.text ?? '',
            ),
            author: normalizeForumText(
                element.querySelector('.threadlist_top .muser a.mmc')?.text ??
                    '',
            ),
            avatarUri: _resolveOptionalUri(
                pageUri,
                element.querySelector('.threadlist_top a.mimg img')
                    ?.attributes['src'],
            ),
            timeLabel: timeLabel,
            postedAt: parseForumTime(timeLabel),
            views: counters.isEmpty ? 0 : parseForumCount(counters[0].text),
            replies: counters.length < 2
                ? 0
                : parseForumCount(counters[1].text),
            pinned: pinned,
            administrative: pinned ||
                    _isAdministrativeTitle(title) ||
                    _isAdministrativeType(typeName),
            uri: uri,
        );
    }

    bool _isAdministrativeType(String typeName)
    {
        return RegExp(r'^[#＃]?\s*公告\s*$').hasMatch(typeName);
    }

    bool _isAdministrativeTitle(String title)
    {
        return RegExp(
            r'(公告|版规|板规|版務|版务|发帖须知|發帖須知|申请专楼|申請專樓|'
            r'举报专帖|關聯任務帖|关联任务帖|问题反馈帖|問題反饋帖|发帖教程|'
            r'發帖教程|长期招生|長期招生|分类依据|分類依據|新人须知|新人須知|'
            r'论坛规则|論壇規則|找回账号|找回帳號|修改密码|修改密碼)',
            caseSensitive: false,
        ).hasMatch(title);
    }

    Uri? _resolveOptionalUri(Uri pageUri, String? value)
    {
        if (value == null || value.trim().isEmpty)
        {
            return null;
        }
        return pageUri.resolve(value.trim());
    }

    _Pagination _parsePagination(dom.Document document, Uri pageUri)
    {
        final dom.Element? pageElement = document.querySelector('.pg');
        if (pageElement == null)
        {
            return const _Pagination(current: 1, total: 1);
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
            final Match? match = RegExp(r'(\d+)').firstMatch(title);
            total = int.tryParse(match?.group(1) ?? '') ?? total;
        }

        final String? nextHref = pageElement
            .querySelector('a.nxt[href]')
            ?.attributes['href'];
        return _Pagination(
            current: current,
            total: total,
            next: nextHref == null ? null : pageUri.resolve(nextHref),
        );
    }
}

class _Pagination
{
    const _Pagination({
        required this.current,
        required this.total,
        this.next,
    });

    final int current;
    final int total;
    final Uri? next;
}
