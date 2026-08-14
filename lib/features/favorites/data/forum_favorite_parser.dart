import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/domain/library_models.dart';

class ForumFavoriteParser
{
    const ForumFavoriteParser({
        this.originPolicy = const ForumOriginPolicy(),
        this.authParser = const AuthPageParser(),
    });

    final ForumOriginPolicy originPolicy;
    final AuthPageParser authParser;

    ForumFavoriteListPage parseList(
        String html,
        Uri pageUri, {
        required int expectedUserId,
    })
    {
        _validateListUri(pageUri, expectedUserId);
        final dom.Document document = html_parser.parse(html);
        _throwIfSessionExpired(document);
        _validateIdentity(html, expectedUserId);
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
            expectedUserId,
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
        CloudFavoriteRecord record, {
        required Uri apiUri,
        required int expectedUserId,
    })
    {
        _validateMetadataUri(apiUri, record.threadId);
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
        final int? userId = int.tryParse(
            variablesValue['member_uid']?.toString() ?? '',
        );
        if (expectedUserId <= 0 || userId != expectedUserId)
        {
            throw const ForumSessionExpiredException();
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

    ForumFavoriteForm parseActionForm(
        String html,
        Uri pageUri, {
        required int expectedUserId,
        int? expectedThreadId,
        int? expectedFavoriteId,
    })
    {
        _validateActionUri(
            pageUri,
            expectedUserId: expectedUserId,
            expectedThreadId: expectedThreadId,
            expectedFavoriteId: expectedFavoriteId,
        );
        final dom.Document document = html_parser.parse(html);
        _throwIfSessionExpired(document);
        _validateIdentity(html, expectedUserId);
        final dom.Element? form = document.querySelector(
            'form[action*="ac=favorite"]',
        );
        final String action = form?.attributes['action']?.trim() ?? '';
        if (form == null ||
            action.isEmpty ||
            form.attributes['method']?.toLowerCase() != 'post')
        {
            throw ForumParseException(_messageOrFallback(
                document,
                '无法读取论坛收藏确认表单',
            ));
        }
        final Uri actionUri = pageUri.resolve(action);
        _validateActionUri(
            actionUri,
            expectedUserId: expectedUserId,
            expectedThreadId: expectedThreadId,
            expectedFavoriteId: expectedFavoriteId,
        );
        final Map<String, List<String>> hiddenFields =
            <String, List<String>>{};
        for (final dom.Element input in form.querySelectorAll(
            'input[type="hidden"][name]',
        ))
        {
            final String name = input.attributes['name']?.trim() ?? '';
            if (name.isNotEmpty)
            {
                hiddenFields.putIfAbsent(name, () => <String>[]).add(
                    input.attributes['value'] ?? '',
                );
            }
        }
        final bool deleting = expectedFavoriteId != null;
        _validateActionFields(
            hiddenFields,
            expectedUserId: expectedUserId,
            expectedThreadId: expectedThreadId,
            expectedFavoriteId: expectedFavoriteId,
            deleting: deleting,
        );
        final Map<String, dynamic> fields = <String, dynamic>{
            for (final MapEntry<String, List<String>> entry
                in hiddenFields.entries)
                entry.key: entry.value.single,
        };
        final dom.Element? description = form.querySelector(
            'textarea[name="description"]',
        );
        if (description != null)
        {
            fields['description'] = description.text;
        }
        return ForumFavoriteForm(
            actionUri: _withoutFormHash(actionUri),
            fields: fields,
        );
    }

    void ensureSubmissionSession(
        String html,
        Uri pageUri, {
        required int expectedUserId,
        int? expectedThreadId,
        int? expectedFavoriteId,
    })
    {
        _validateSubmissionUri(
            pageUri,
            expectedUserId: expectedUserId,
            expectedThreadId: expectedThreadId,
            expectedFavoriteId: expectedFavoriteId,
        );
        final dom.Document document = html_parser.parse(html);
        _throwIfSessionExpired(document);
        _validateIdentity(html, expectedUserId);
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
        originPolicy.requireMobilePage(threadUri);
        originPolicy.requireMobilePage(deleteUri);
        final int? tid = queryInt(threadUri, 'tid');
        final int? favoriteId = queryInt(deleteUri, 'favid');
        if (threadUri.path != '/forum.php' ||
            threadUri.queryParameters['mod'] != 'viewthread' ||
            tid == null ||
            deleteUri.path != '/home.php' ||
            deleteUri.queryParameters['mod'] != 'spacecp' ||
            deleteUri.queryParameters['ac'] != 'favorite' ||
            deleteUri.queryParameters['op'] != 'delete' ||
            favoriteId == null)
        {
            throw const ForumParseException('论坛收藏记录地址无效');
        }
        return CloudFavoriteRecord(
            favoriteId: favoriteId,
            threadId: tid,
            title: normalizeForumText(threadAnchor?.text ?? ''),
            threadUri: threadUri,
            deleteDialogUri: _withoutFormHash(deleteUri),
        );
    }

    _FavoritePagination _parsePagination(
        dom.Document document,
        Uri pageUri,
        int expectedUserId,
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
        Uri? nextUri;
        if (nextHref != null)
        {
            nextUri = pageUri.resolve(nextHref);
            _validateListUri(
                nextUri,
                expectedUserId,
            );
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

    void _validateListUri(Uri uri, int expectedUserId)
    {
        originPolicy.requireMobilePage(uri);
        if (uri.path != '/home.php' ||
            uri.queryParameters['mod'] != 'space' ||
            uri.queryParameters['do'] != 'favorite' ||
            uri.queryParameters['type'] != 'thread')
        {
            throw const ForumParseException('论坛收藏列表地址无效');
        }
        _validateOptionalUserId(uri, 'uid', expectedUserId);
    }

    void _validateMetadataUri(Uri uri, int expectedThreadId)
    {
        originPolicy.ensureAllowed(uri);
        if (uri.path != '/api/mobile/index.php' ||
            uri.queryParameters['version'] != '4' ||
            uri.queryParameters['module'] != 'viewthread' ||
            queryInt(uri, 'tid') != expectedThreadId)
        {
            throw const ForumActionSecurityException(
                '论坛主题元数据地址无效',
            );
        }
    }

    void _validateActionUri(
        Uri uri, {
        required int expectedUserId,
        int? expectedThreadId,
        int? expectedFavoriteId,
    })
    {
        originPolicy.requireMobilePage(uri);
        if (!originPolicy.hasNoAliasedQueryParameters(
            uri,
            const <String>{
                'mod', 'action', 'ac', 'op', 'type', 'fid', 'tid', 'pid',
                'id', 'favid', 'uid', 'spaceuid', 'mobile', 'formhash',
                'favoritesubmit', 'deletesubmit',
            },
        ))
        {
            throw const ForumActionSecurityException(
                '论坛收藏操作地址包含保留参数数组别名',
            );
        }
        for (final String name in const <String>{
            'mod', 'action', 'ac', 'op', 'type', 'fid', 'tid', 'pid', 'id',
            'favid', 'uid', 'spaceuid', 'mobile', 'formhash',
            'favoritesubmit', 'deletesubmit',
        })
        {
            if ((uri.queryParametersAll[name] ?? const <String>[]).length > 1)
            {
                throw const ForumActionSecurityException(
                    '论坛收藏操作地址包含重复保留参数',
                );
            }
        }
        final Set<String> allowed = expectedFavoriteId == null
            ? const <String>{
                'mod', 'ac', 'type', 'id', 'uid', 'spaceuid', 'mobile',
                'formhash',
            }
            : const <String>{
                'mod', 'ac', 'op', 'type', 'favid', 'uid', 'spaceuid',
                'mobile', 'formhash',
            };
        if (!uri.queryParametersAll.keys.every(allowed.contains))
        {
            throw const ForumActionSecurityException(
                '论坛收藏操作地址包含未登记参数',
            );
        }
        if (uri.path != '/home.php' ||
            uri.queryParameters['mod'] != 'spacecp' ||
            uri.queryParameters['ac'] != 'favorite')
        {
            throw const ForumActionSecurityException(
                '论坛收藏操作地址无效',
            );
        }
        _validateOptionalUserId(uri, 'uid', expectedUserId);
        _validateOptionalUserId(uri, 'spaceuid', expectedUserId);
        if (expectedFavoriteId != null)
        {
            if (uri.queryParameters['op'] != 'delete' ||
                (uri.queryParameters['type'] != null &&
                    uri.queryParameters['type'] != 'thread') ||
                queryInt(uri, 'favid') != expectedFavoriteId)
            {
                throw const ForumActionSecurityException(
                    '论坛取消收藏目标不一致',
                );
            }
            return;
        }
        if (expectedThreadId == null ||
            uri.queryParameters['type'] != 'thread' ||
            queryInt(uri, 'id') != expectedThreadId)
        {
            throw const ForumActionSecurityException(
                '论坛添加收藏目标不一致',
            );
        }
    }

    void _validateActionFields(
        Map<String, List<String>> fields, {
        required int expectedUserId,
        required int? expectedThreadId,
        required int? expectedFavoriteId,
        required bool deleting,
    })
    {
        const Set<String> reserved = <String>{
            'uid', 'spaceuid', 'fid', 'tid', 'pid', 'id', 'favid',
            'mod', 'action', 'ac', 'op', 'type', 'mobile',
            'formhash', 'handlekey', 'referer',
            'favoritesubmit', 'favoritesubmit_btn',
            'deletesubmit', 'deletesubmitbtn',
        };
        for (final MapEntry<String, List<String>> entry in fields.entries)
        {
            final String lower = entry.key.toLowerCase();
            final int bracket = lower.indexOf('[');
            final String name = bracket < 0 ? lower : lower.substring(0, bracket);
            if (reserved.contains(name) && name != lower)
            {
                throw ForumActionSecurityException(
                    '论坛收藏表单使用了保留字段数组别名：${entry.key}',
                );
            }
            if (entry.value.length != 1)
            {
                throw ForumActionSecurityException(
                    '论坛收藏表单字段不唯一：${entry.key}',
                );
            }
            if (const <String>{
                'mod', 'action', 'ac', 'op', 'type', 'mobile',
            }.contains(name))
            {
                throw ForumActionSecurityException(
                    '论坛收藏表单重复声明路由字段：${entry.key}',
                );
            }
        }
        for (final String name in const <String>['uid', 'spaceuid'])
        {
            final String? value = fields[name]?.singleOrNull;
            if (value != null && int.tryParse(value) != expectedUserId)
            {
                throw const ForumSessionExpiredException();
            }
        }
        if ((fields['formhash']?.singleOrNull ?? '').isEmpty)
        {
            throw const ForumParseException('论坛收藏表单缺少唯一 formhash');
        }
        final Set<String> expectedSubmit = deleting
            ? const <String>{'deletesubmit', 'deletesubmitbtn'}
            : const <String>{'favoritesubmit', 'favoritesubmit_btn'};
        final List<MapEntry<String, List<String>>> submit = fields.entries
            .where((MapEntry<String, List<String>> entry) =>
                expectedSubmit.contains(entry.key.toLowerCase()))
            .toList(growable: false);
        if (submit.length != 1 || submit.single.value.single.trim().isEmpty)
        {
            throw const ForumParseException('论坛收藏表单缺少唯一提交标记');
        }
        final Set<String> otherSubmit = deleting
            ? const <String>{'favoritesubmit', 'favoritesubmit_btn'}
            : const <String>{'deletesubmit', 'deletesubmitbtn'};
        if (fields.keys.any(
            (String name) => otherSubmit.contains(name.toLowerCase()),
        ))
        {
            throw const ForumActionSecurityException('论坛收藏表单包含其他操作提交标记');
        }
        _validateHiddenTarget(fields, 'id', expectedThreadId, deleting: deleting);
        _validateHiddenTarget(
            fields,
            'favid',
            expectedFavoriteId,
            deleting: !deleting,
        );
        for (final String name in const <String>['fid', 'tid', 'pid'])
        {
            if (fields.containsKey(name))
            {
                throw ForumActionSecurityException('论坛收藏表单包含无关目标字段：$name');
            }
        }
    }

    void _validateHiddenTarget(
        Map<String, List<String>> fields,
        String name,
        int? expected, {
        required bool deleting,
    })
    {
        final String? value = fields[name]?.singleOrNull;
        if (value == null)
        {
            return;
        }
        if (deleting || expected == null || int.tryParse(value) != expected)
        {
            throw ForumActionSecurityException('论坛收藏表单目标字段不一致：$name');
        }
    }

    void _validateSubmissionUri(
        Uri uri, {
        required int expectedUserId,
        int? expectedThreadId,
        int? expectedFavoriteId,
    })
    {
        originPolicy.requireMobilePage(uri);
        _validateOptionalUserId(uri, 'uid', expectedUserId);
        _validateOptionalUserId(uri, 'spaceuid', expectedUserId);
        final String? mod = uri.queryParameters['mod'];
        if (uri.path == '/home.php' &&
            mod == 'spacecp' &&
            uri.queryParameters['ac'] == 'favorite')
        {
            _validateActionUri(
                uri,
                expectedUserId: expectedUserId,
                expectedThreadId: expectedThreadId,
                expectedFavoriteId: expectedFavoriteId,
            );
            return;
        }
        if (uri.path == '/home.php' &&
            mod == 'space' &&
            uri.queryParameters['do'] == 'favorite' &&
            uri.queryParameters['type'] == 'thread')
        {
            return;
        }
        if (uri.path == '/forum.php' &&
            mod == 'viewthread' &&
            expectedThreadId != null &&
            queryInt(uri, 'tid') == expectedThreadId)
        {
            return;
        }
        throw const ForumActionSecurityException('论坛收藏提交结果地址无效');
    }

    void _validateIdentity(String html, int expectedUserId)
    {
        if (expectedUserId <= 0 ||
            authParser.currentUserId(html) != expectedUserId)
        {
            throw const ForumSessionExpiredException();
        }
    }

    void _validateOptionalUserId(
        Uri uri,
        String parameter,
        int expectedUserId,
    )
    {
        final String? value = uri.queryParameters[parameter];
        if (value != null && int.tryParse(value) != expectedUserId)
        {
            throw const ForumSessionExpiredException();
        }
    }

    Uri _withoutFormHash(Uri uri)
    {
        if (!uri.queryParameters.keys.any(
            (String key) => key.toLowerCase() == 'formhash',
        ))
        {
            return uri;
        }
        return uri.replace(
            queryParameters: <String, String>{
                for (final MapEntry<String, String> entry
                    in uri.queryParameters.entries)
                    if (entry.key.toLowerCase() != 'formhash')
                        entry.key: entry.value,
            },
        );
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
