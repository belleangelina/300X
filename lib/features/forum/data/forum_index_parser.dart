import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';

class ForumIndexParser
{
    const ForumIndexParser();

    ForumBoardIndex parse({
        required String mobileHtml,
        required Uri mobileUri,
        required String apiJson,
        required Uri apiUri,
        required int expectedUserId,
    })
    {
        final dom.Document document = html_parser.parse(mobileHtml);
        _validateMobileIndex(document, mobileUri);
        _validateApiIndexUri(apiUri);
        _validateMobileIdentity(mobileHtml, expectedUserId);
        final _MobileIndex mobile = _parseMobileIndex(document, mobileUri);
        final Map<String, dynamic> variables;
        try
        {
            variables = _variables(apiJson);
        }
        on ForumParseException
        {
            return _mobileOnlyIndex(mobile, mobileUri, expectedUserId);
        }
        final ForumViewer viewer = _parseViewer(variables);
        if (expectedUserId <= 0 || viewer.userId != expectedUserId)
        {
            throw const ForumSessionExpiredException();
        }

        final List<ForumBoardNode> roots = _maps(variables['forumlist'])
            .map(
                (Map<String, dynamic> value) => _parseBoard(
                    value,
                    mobileUri,
                    mobile.boardsById,
                ),
            )
            .whereType<ForumBoardNode>()
            .toList();
        final Set<int> parsedBoardIds = <int>{};
        void collectBoardIds(ForumBoardNode board)
        {
            parsedBoardIds.add(board.id);
            for (final ForumBoardNode child in board.children)
            {
                collectBoardIds(child);
            }
        }
        roots.forEach(collectBoardIds);
        for (final _MobileBoard board in mobile.boardsById.values)
        {
            if (parsedBoardIds.add(board.id))
            {
                roots.add(ForumBoardNode(
                    id: board.id,
                    name: board.name,
                    uri: board.uri,
                ));
            }
        }
        final Map<int, ForumBoardNode> rootsById = <int, ForumBoardNode>{
            for (final ForumBoardNode board in roots) board.id: board,
        };
        final Set<int> sectioned = <int>{};
        final List<ForumSection> sections = <ForumSection>[];
        for (final Map<String, dynamic> value in _maps(variables['catlist']))
        {
            final List<ForumBoardNode> boards = <ForumBoardNode>[];
            for (final Object? rawBoard in _values(value['forums']))
            {
                final int boardId = _integer(
                    rawBoard is Map ? _map(rawBoard)['fid'] : rawBoard,
                );
                final ForumBoardNode? board = rootsById[boardId];
                if (board != null && sectioned.add(boardId))
                {
                    boards.add(board);
                }
            }
            _sortBoards(boards, mobile.orderByBoardId);
            if (boards.isEmpty)
            {
                continue;
            }
            sections.add(ForumSection(
                id: _integer(value['fid']),
                name: normalizeForumText(value['name']?.toString() ?? ''),
                boards: List<ForumBoardNode>.unmodifiable(boards),
            ));
        }

        final List<ForumBoardNode> unsectioned = roots
            .where((ForumBoardNode board) => !sectioned.contains(board.id))
            .toList(growable: false);
        _sortBoards(unsectioned, mobile.orderByBoardId);
        if (sections.isEmpty && unsectioned.isEmpty)
        {
            throw const ForumParseException('移动论坛首页没有可识别的版块');
        }
        return ForumBoardIndex(
            sections: List<ForumSection>.unmodifiable(sections),
            unsectionedBoards: List<ForumBoardNode>.unmodifiable(unsectioned),
            viewer: viewer,
            navigation: mobile.navigation,
            sourceUri: mobileUri,
        );
    }

    void _validateMobileIdentity(String html, int expectedUserId)
    {
        final int? userId = int.tryParse(
            RegExp(
                r'''\bdiscuz_uid\s*=\s*['"]([1-9]\d*)['"]''',
            ).firstMatch(html)?.group(1) ?? '',
        );
        if (expectedUserId <= 0 || userId != expectedUserId)
        {
            throw const ForumSessionExpiredException();
        }
    }

    ForumBoardIndex _mobileOnlyIndex(
        _MobileIndex mobile,
        Uri sourceUri,
        int userId,
    )
    {
        final List<ForumBoardNode> boards = mobile.boardsById.values
            .map(
                (_MobileBoard board) => ForumBoardNode(
                    id: board.id,
                    name: board.name,
                    uri: board.uri,
                ),
            )
            .toList(growable: false);
        return ForumBoardIndex(
            sections: const <ForumSection>[],
            unsectionedBoards: List<ForumBoardNode>.unmodifiable(boards),
            viewer: ForumViewer(userId: userId),
            navigation: mobile.navigation,
            sourceUri: sourceUri,
        );
    }

    void _validateApiIndexUri(Uri apiUri)
    {
        if (!_isAllowedForumUri(apiUri) ||
            apiUri.path != '/api/mobile/index.php' ||
            apiUri.queryParameters['version'] != '4' ||
            apiUri.queryParameters['module'] != 'forumindex')
        {
            throw const ForumParseException('论坛移动接口地址无效');
        }
    }

    void _validateMobileIndex(dom.Document document, Uri pageUri)
    {
        if (document.querySelector('form#loginform') != null ||
            document.body?.classes.contains('pg_logging') == true)
        {
            throw const ForumSessionExpiredException();
        }
        if (!_isAllowedForumUri(pageUri) ||
            pageUri.queryParameters['mobile'] != '2' ||
            document.body?.id != 'forum' ||
            document.body?.classes.contains('pg_index') != true)
        {
            throw const ForumParseException('论坛未返回登录后的移动首页');
        }
    }

    _MobileIndex _parseMobileIndex(dom.Document document, Uri pageUri)
    {
        final Map<int, _MobileBoard> boardsById = <int, _MobileBoard>{};
        final Map<int, int> orderByBoardId = <int, int>{};
        for (final dom.Element anchor in document.querySelectorAll(
            'a[href*="mod=forumdisplay"][href*="fid="]',
        ))
        {
            final Uri? uri = _resolveAllowed(pageUri, anchor.attributes['href']);
            final int? boardId = uri == null ? null : queryInt(uri, 'fid');
            if (boardId == null || boardId <= 0)
            {
                continue;
            }
            orderByBoardId.putIfAbsent(boardId, () => orderByBoardId.length);
            boardsById.putIfAbsent(
                boardId,
                () => _MobileBoard(
                    id: boardId,
                    name: normalizeForumText(anchor.text),
                    uri: _ensureMobile(uri!),
                ),
            );
        }
        if (boardsById.isEmpty)
        {
            throw const ForumParseException('移动论坛首页缺少版块入口');
        }
        return _MobileIndex(
            boardsById: boardsById,
            orderByBoardId: orderByBoardId,
            navigation: ForumNavigationLinks(
                searchUri: _findUri(
                    document,
                    pageUri,
                    (Uri value) => value.path.endsWith('/search.php') &&
                        value.queryParameters['mod'] == 'forum',
                ),
                favoritesUri: _findUri(
                    document,
                    pageUri,
                    (Uri value) => value.queryParameters['mod'] == 'space' &&
                        value.queryParameters['do'] == 'favorite',
                ),
                noticesUri: _findUri(
                    document,
                    pageUri,
                    (Uri value) => value.queryParameters['mod'] == 'space' &&
                        value.queryParameters['do'] == 'notice',
                ),
                messagesUri: _findUri(
                    document,
                    pageUri,
                    (Uri value) => value.queryParameters['mod'] == 'space' &&
                        value.queryParameters['do'] == 'pm',
                ),
                profileUri: _findUri(
                    document,
                    pageUri,
                    (Uri value) => value.queryParameters['mod'] == 'space' &&
                        value.queryParameters['do'] == 'profile',
                ),
            ),
        );
    }

    ForumViewer _parseViewer(Map<String, dynamic> variables)
    {
        final Map<String, dynamic> notice = _map(variables['notice']);
        return ForumViewer(
            userId: _integer(variables['member_uid']),
            username: normalizeForumText(
                variables['member_username']?.toString() ?? '',
            ),
            noticeCount: _integer(notice['newprompt']) +
                _integer(notice['newmypost']),
            privateMessageCount: _integer(notice['newpm']),
        );
    }

    ForumBoardNode? _parseBoard(
        Map<String, dynamic> value,
        Uri pageUri,
        Map<int, _MobileBoard> visibleBoards, {
        int? parentId,
    })
    {
        final int boardId = _integer(value['fid']);
        if (boardId <= 0)
        {
            return null;
        }
        final List<ForumBoardNode> children = _maps(value['sublist'])
            .map(
                (Map<String, dynamic> child) => _parseBoard(
                    child,
                    pageUri,
                    visibleBoards,
                    parentId: boardId,
                ),
            )
            .whereType<ForumBoardNode>()
            .toList(growable: false);
        final _MobileBoard? mobileBoard = visibleBoards[boardId];
        if (mobileBoard == null && children.isEmpty)
        {
            return null;
        }
        return ForumBoardNode(
            id: boardId,
            parentId: _positiveInteger(value['fup']) ?? parentId,
            name: normalizeForumText(value['name']?.toString() ?? '').isEmpty
                ? mobileBoard?.name ?? ''
                : normalizeForumText(value['name']?.toString() ?? ''),
            description: normalizeForumText(
                value['description']?.toString() ?? '',
            ),
            uri: mobileBoard?.uri ?? pageUri,
            threadCount: _integer(value['threadcount'] ?? value['threads']),
            postCount: _integer(value['posts']),
            todayPostCount: _integer(value['todayposts']),
            children: List<ForumBoardNode>.unmodifiable(children),
        );
    }

    Map<String, dynamic> _variables(String source)
    {
        final Object? decoded;
        try
        {
            decoded = jsonDecode(source);
        }
        on FormatException
        {
            throw const ForumParseException('论坛移动接口无法解析');
        }
        final Map<String, dynamic> root = _map(decoded);
        final Map<String, dynamic> message = _map(root['Message']);
        if (message.isNotEmpty)
        {
            final String code = message['messageval']?.toString() ?? '';
            if (code.toLowerCase().contains('login'))
            {
                throw const ForumSessionExpiredException();
            }
            throw ForumParseException(
                normalizeForumText(
                    message['messagestr']?.toString() ?? '',
                ).isEmpty
                    ? '论坛移动接口返回错误'
                    : normalizeForumText(
                        message['messagestr']?.toString() ?? '',
                    ),
            );
        }
        final Map<String, dynamic> variables = _map(root['Variables']);
        if (variables.isEmpty)
        {
            throw const ForumParseException('论坛移动接口缺少 Variables');
        }
        return variables;
    }

    Uri? _findUri(
        dom.Document document,
        Uri pageUri,
        bool Function(Uri value) matches,
    )
    {
        for (final dom.Element anchor in document.querySelectorAll('a[href]'))
        {
            final Uri? uri = _resolveAllowed(pageUri, anchor.attributes['href']);
            if (uri != null && matches(uri))
            {
                return _ensureMobile(uri);
            }
        }
        return null;
    }

    Uri? _resolveAllowed(Uri pageUri, String? value)
    {
        if (value == null || value.trim().isEmpty)
        {
            return null;
        }
        final Uri uri;
        try
        {
            uri = pageUri.resolve(value.trim());
        }
        on FormatException
        {
            return null;
        }
        return _isAllowedForumUri(uri) ? uri : null;
    }

    bool _isAllowedForumUri(Uri uri)
    {
        return uri.scheme == 'https' &&
            uri.host == 'bbs.yamibo.com' &&
            uri.port == 443 &&
            uri.userInfo.isEmpty;
    }

    Uri _ensureMobile(Uri uri)
    {
        return uri.replace(queryParameters: <String, String>{
            ...uri.queryParameters,
            'mobile': '2',
        });
    }

    void _sortBoards(
        List<ForumBoardNode> boards,
        Map<int, int> orderByBoardId,
    )
    {
        boards.sort((ForumBoardNode left, ForumBoardNode right)
        {
            final int leftOrder = orderByBoardId[left.id] ?? 1 << 30;
            final int rightOrder = orderByBoardId[right.id] ?? 1 << 30;
            return leftOrder.compareTo(rightOrder);
        });
    }

    List<Map<String, dynamic>> _maps(Object? value)
    {
        if (value is List)
        {
            return value
                .map(_map)
                .where((Map<String, dynamic> item) => item.isNotEmpty)
                .toList(growable: false);
        }
        if (value is Map)
        {
            return value.values
                .map(_map)
                .where((Map<String, dynamic> item) => item.isNotEmpty)
                .toList(growable: false);
        }
        return const <Map<String, dynamic>>[];
    }

    Map<String, dynamic> _map(Object? value)
    {
        if (value is! Map)
        {
            return const <String, dynamic>{};
        }
        return <String, dynamic>{
            for (final MapEntry<Object?, Object?> entry in value.entries)
                entry.key.toString(): entry.value,
        };
    }

    List<Object?> _values(Object? value)
    {
        if (value is List)
        {
            return value;
        }
        if (value is Map)
        {
            return value.values.toList(growable: false);
        }
        return value == null ? const <Object?>[] : <Object?>[value];
    }

    int _integer(Object? value)
    {
        if (value is num)
        {
            return value.toInt();
        }
        return int.tryParse(
                value?.toString().replaceAll(',', '').trim() ?? '',
            ) ??
            0;
    }

    int? _positiveInteger(Object? value)
    {
        final int parsed = _integer(value);
        return parsed > 0 ? parsed : null;
    }
}

class _MobileIndex
{
    const _MobileIndex({
        required this.boardsById,
        required this.orderByBoardId,
        required this.navigation,
    });

    final Map<int, _MobileBoard> boardsById;
    final Map<int, int> orderByBoardId;
    final ForumNavigationLinks navigation;
}

class _MobileBoard
{
    const _MobileBoard({
        required this.id,
        required this.name,
        required this.uri,
    });

    final int id;
    final String name;
    final Uri uri;
}
