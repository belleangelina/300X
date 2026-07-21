import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/domain/library_models.dart';

class ForumFavoriteParser
{
    const ForumFavoriteParser();

    ForumFavoriteListPage parseList(String html, Uri pageUri)
    {
        final dom.Document document = html_parser.parse(html);
        _throwIfSessionExpired(document);
        if (document.body?.classes.contains('pg_space') != true)
        {
            throw ForumParseException(_messageOrFallback(
                document,
                '无法识别论坛收藏列表',
            ));
        }

        final List<CloudFavoriteRecord> records = document
            .querySelectorAll('li.sclist')
            .map(
                (dom.Element element) => _parseRecord(element, pageUri),
            )
            .whereType<CloudFavoriteRecord>()
            .toList(growable: false);
        final bool hasContainer = document.querySelector('.findbox') != null;
        if (records.isEmpty && !hasContainer)
        {
            throw const ForumParseException('收藏页面中没有可识别的列表');
        }

        final _FavoritePagination pagination = _parsePagination(
            document,
            pageUri,
        );
        return ForumFavoriteListPage(
            records: records,
            currentPage: pagination.current,
            totalPages: pagination.total,
            nextPageUri: pagination.next,
        );
    }

    SourceThread? parseThreadMetadata(
        String json,
        CloudFavoriteRecord record,
    )
    {
        final Object? decoded;
        try
        {
            decoded = jsonDecode(json);
        }
        on FormatException
        {
            throw const ForumParseException('无法识别论坛主题元数据');
        }
        if (decoded is! Map<String, dynamic>)
        {
            throw const ForumParseException('论坛主题元数据格式无效');
        }
        final Object? messageValue = decoded['Message'];
        if (messageValue is Map && messageValue.isNotEmpty)
        {
            final String messageKey = messageValue['messageval']?.toString() ?? '';
            final String message = messageValue['messagestr']?.toString() ?? '';
            if (messageKey.contains('login') || message.contains('登录'))
            {
                throw const ForumSessionExpiredException();
            }
            throw ForumParseException(
                normalizeForumText(message).isEmpty
                    ? '论坛主题暂时无法读取'
                    : normalizeForumText(message),
            );
        }
        final Object? variablesValue = decoded['Variables'];
        if (variablesValue is! Map<String, dynamic>)
        {
            throw const ForumParseException('论坛主题元数据缺少 Variables');
        }
        final Object? threadValue = variablesValue['thread'];
        if (threadValue is! Map<String, dynamic>)
        {
            throw const ForumParseException('论坛主题元数据缺少 thread');
        }
        final int? fid = int.tryParse(threadValue['fid']?.toString() ?? '');
        final ForumBoard? board = fid == null ? null : ForumBoard.fromFid(fid);
        if (board == null)
        {
            return null;
        }
        final int tid = int.tryParse(threadValue['tid']?.toString() ?? '') ??
            record.threadId;
        if (tid != record.threadId)
        {
            throw const ForumParseException('论坛主题元数据 tid 不一致');
        }
        final String timeLabel = normalizeForumText(
            threadValue['lastpost']?.toString() ?? '',
        );
        final String apiTitle = normalizeForumText(
            threadValue['subject']?.toString() ?? '',
        );
        return SourceThread(
            tid: tid,
            board: board,
            typeId: int.tryParse(threadValue['typeid']?.toString() ?? ''),
            title: record.title.isEmpty ? apiTitle : record.title,
            author: normalizeForumText(
                threadValue['author']?.toString() ?? '',
            ),
            timeLabel: timeLabel,
            postedAt: parseForumTime(timeLabel),
            views: parseForumCount(
                threadValue['views']?.toString() ?? '',
            ),
            replies: parseForumCount(
                threadValue['replies']?.toString() ?? '',
            ),
            uri: record.threadUri,
        );
    }

    ForumFavoriteForm parseActionForm(String html, Uri pageUri)
    {
        final dom.Document document = html_parser.parse(html);
        _throwIfSessionExpired(document);
        final dom.Element? form = document.querySelector(
            'form[action*="ac=favorite"]',
        );
        final String action = form?.attributes['action']?.trim() ?? '';
        if (form == null || action.isEmpty)
        {
            throw ForumParseException(_messageOrFallback(
                document,
                '无法读取论坛收藏确认表单',
            ));
        }
        final Uri actionUri = pageUri.resolve(action);
        if (actionUri.host != pageUri.host)
        {
            throw const ForumParseException('论坛收藏表单地址无效');
        }
        final Map<String, dynamic> fields = <String, dynamic>{};
        for (final dom.Element input in form.querySelectorAll(
            'input[type="hidden"][name]',
        ))
        {
            final String name = input.attributes['name']?.trim() ?? '';
            if (name.isNotEmpty)
            {
                fields[name] = input.attributes['value'] ?? '';
            }
        }
        final dom.Element? description = form.querySelector(
            'textarea[name="description"]',
        );
        if (description != null)
        {
            fields['description'] = description.text;
        }
        if ((fields['formhash']?.toString() ?? '').isEmpty ||
            (!fields.containsKey('favoritesubmit') &&
                !fields.containsKey('deletesubmit')))
        {
            throw const ForumParseException('论坛收藏表单缺少必要字段');
        }
        return ForumFavoriteForm(
            actionUri: actionUri,
            fields: fields,
        );
    }

    void ensureSubmissionSession(String html)
    {
        final dom.Document document = html_parser.parse(html);
        _throwIfSessionExpired(document);
    }

    CloudFavoriteRecord? _parseRecord(
        dom.Element element,
        Uri pageUri,
    )
    {
        final dom.Element? threadAnchor = element.querySelector(
            'a[href*="mod=viewthread"][href*="tid="]',
        );
        final dom.Element? deleteAnchor = element.querySelector(
            'a[href*="ac=favorite"][href*="op=delete"][href*="favid="]',
        );
        final String? threadHref = threadAnchor?.attributes['href'];
        final String? deleteHref = deleteAnchor?.attributes['href'];
        if (threadHref == null || deleteHref == null)
        {
            return null;
        }
        final Uri threadUri = pageUri.resolve(threadHref);
        final Uri deleteUri = pageUri.resolve(deleteHref);
        final int? tid = queryInt(threadUri, 'tid');
        final int? favoriteId = queryInt(deleteUri, 'favid');
        if (tid == null || favoriteId == null)
        {
            return null;
        }
        return CloudFavoriteRecord(
            favoriteId: favoriteId,
            threadId: tid,
            title: normalizeForumText(threadAnchor?.text ?? ''),
            threadUri: threadUri,
            deleteDialogUri: deleteUri,
        );
    }

    _FavoritePagination _parsePagination(
        dom.Document document,
        Uri pageUri,
    )
    {
        final dom.Element? pageElement = document.querySelector('.pg');
        if (pageElement == null)
        {
            return const _FavoritePagination(current: 1, total: 1);
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
        final String title = pageElement.querySelector('label span')
                ?.attributes['title'] ??
            '';
        total = int.tryParse(
                RegExp(r'(\d+)').firstMatch(title)?.group(1) ?? '',
            ) ??
            total;
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
        return _FavoritePagination(
            current: current,
            total: total,
            next: nextUri,
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

    String _messageOrFallback(dom.Document document, String fallback)
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

class _FavoritePagination
{
    const _FavoritePagination({
        required this.current,
        required this.total,
        this.next,
    });

    final int current;
    final int total;
    final Uri? next;
}
