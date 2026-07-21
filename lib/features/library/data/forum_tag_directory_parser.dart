import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/domain/thread_models.dart';

class ForumTagDirectoryPage
{
    const ForumTagDirectoryPage({required this.links, this.nextPageUri});

    final List<ThreadLink> links;
    final Uri? nextPageUri;
}

class ForumTagDirectoryParser
{
    const ForumTagDirectoryParser();

    ForumTagDirectoryPage parse(String html, Uri pageUri)
    {
        final dom.Document document = html_parser.parse(html);
        if (document.querySelector('form#loginform') != null ||
                document.body?.classes.contains('pg_logging') == true)
        {
            throw const ForumSessionExpiredException();
        }

        final Map<int, ({ThreadLink link, int score})> selected =
                <int, ({ThreadLink link, int score})>{};
        for (final dom.Element anchor in document.querySelectorAll(
            '.threadlist a[href], '
            '.tl .bm_c tr th a[href], '
            'table.tl tr th a.xst[href], '
            '.tl a.xst[href]',
        ))
        {
            final String? href = anchor.attributes['href'];
            if (href == null || href.trim().isEmpty)
            {
                continue;
            }
            final Uri uri = pageUri.resolve(href.trim());
            final int? tid = queryInt(uri, 'tid') ?? _friendlyThreadId(uri.path);
            final String label = normalizeForumText(
                anchor.querySelector('.threadlist_tit em')?.text ??
                        anchor.querySelector('.threadlist_tit')?.text ??
                        anchor.text,
            );
            if (uri.host != pageUri.host || tid == null || label.isEmpty)
            {
                continue;
            }
            final int score = _labelScore(anchor, label);
            final ({ThreadLink link, int score})? current = selected[tid];
            if (current != null && current.score >= score)
            {
                continue;
            }
            selected[tid] = (
                link: ThreadLink(
                    label: label,
                    uri: uri,
                    kind: ThreadLinkKind.chapter,
                    tid: tid,
                ),
                score: score,
            );
        }

        final bool recognizable =
                document.body?.classes.contains('pg_tag') == true ||
                document.querySelector('.threadlist, .tl .bm_c, table.tl') != null;
        if (selected.isEmpty && !recognizable)
        {
            final String message = normalizeForumText(
                document.querySelector('.jump_c p, #messagetext, .tip')?.text ?? '',
            );
            throw ForumParseException(message.isEmpty ? '无法识别论坛作品目录页' : message);
        }

        return ForumTagDirectoryPage(
            links: selected.values.map((value) => value.link).toList(growable: false),
            nextPageUri: _nextPageUri(document, pageUri),
        );
    }

    int _labelScore(dom.Element anchor, String label)
    {
        final bool titleAnchor =
                anchor.classes.contains('xst') ||
                anchor.querySelector('.threadlist_tit') != null ||
                anchor.parent?.classes.contains('threadlist_tit') == true;
        return (titleAnchor ? 1000 : 0) + (label.length > 200 ? 200 : label.length);
    }

    Uri? _nextPageUri(dom.Document document, Uri pageUri)
    {
        final String? href = document
                .querySelector('.pg a.nxt[href]')
                ?.attributes['href'];
        if (href == null)
        {
            return null;
        }
        final Uri uri = pageUri.resolve(href);
        if (uri.scheme != pageUri.scheme ||
                uri.host != pageUri.host ||
                uri.port != pageUri.port ||
                uri.path != pageUri.path ||
                uri.queryParameters['mod'] != 'tag' ||
                uri.queryParameters['id'] != pageUri.queryParameters['id'])
        {
            return null;
        }
        return uri;
    }

    int? _friendlyThreadId(String path)
    {
        return int.tryParse(
            RegExp(r'(?:^|/)thread-(\d+)(?:-|\.html|$)').firstMatch(path)?.group(1) ??
                    '',
        );
    }
}
