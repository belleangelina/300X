import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/community/presentation/community_pages.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/domain/forum_models.dart'
    hide ForumBoardPage;
import 'package:x300/features/forum/domain/forum_search_models.dart';
import 'package:x300/features/forum/presentation/forum_board_page.dart';
import 'package:x300/features/forum/presentation/forum_read_widgets.dart';
import 'package:x300/features/forum/presentation/forum_search_page.dart';
import 'package:x300/features/forum/presentation/forum_topic_page.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class ForumHomeController
{
    Future<void> Function()? _refreshHandler;
    Future<void> Function()? _backgroundRefreshHandler;

    Future<void> scrollToTopAndRefresh()
    {
        return _refreshHandler?.call() ?? Future<void>.value();
    }

    Future<void> refresh()
    {
        return (_backgroundRefreshHandler ?? _refreshHandler)?.call() ??
            Future<void>.value();
    }

    void attach(
        Future<void> Function() handler, {
        Future<void> Function()? backgroundRefreshHandler,
    })
    {
        _refreshHandler = handler;
        _backgroundRefreshHandler = backgroundRefreshHandler;
    }

    void detach(Future<void> Function() handler)
    {
        if (identical(_refreshHandler, handler))
        {
            _refreshHandler = null;
            _backgroundRefreshHandler = null;
        }
    }
}

class ForumHomePage extends ConsumerStatefulWidget
{
    const ForumHomePage({
        required this.authState,
        required this.onLogin,
        this.controller,
        this.onOpenBoard,
        super.key,
    });

    final AuthState authState;
    final VoidCallback onLogin;
    final ForumHomeController? controller;
    final ValueChanged<ForumBoardNode>? onOpenBoard;

    @override
    ConsumerState<ForumHomePage> createState()
    {
        return _ForumHomePageState();
    }
}

class _ForumHomePageState extends ConsumerState<ForumHomePage>
{
    final ScrollController _scrollController = ScrollController();
    ForumBoardIndex? _index;
    Object? _error;
    bool _loading = false;
    int _generation = 0;
    late final Future<void> Function() _refreshHandler;
    late final Future<void> Function() _backgroundRefreshHandler;

    bool get _authenticated =>
        widget.authState.status == AuthStatus.authenticated &&
        widget.authState.userId > 0;

    @override
    void initState()
    {
        super.initState();
        _refreshHandler = _scrollToTopAndRefresh;
        _backgroundRefreshHandler = () => _load(setBusy: false);
        widget.controller?.attach(
            _refreshHandler,
            backgroundRefreshHandler: _backgroundRefreshHandler,
        );
        if (_authenticated)
        {
            _loading = true;
            unawaited(_load(setBusy: false));
        }
    }

    @override
    void didUpdateWidget(covariant ForumHomePage oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        if (oldWidget.controller != widget.controller)
        {
            oldWidget.controller?.detach(_refreshHandler);
            widget.controller?.attach(
                _refreshHandler,
                backgroundRefreshHandler: _backgroundRefreshHandler,
            );
        }
        final bool identityChanged =
            oldWidget.authState.status != widget.authState.status ||
            oldWidget.authState.userId != widget.authState.userId;
        if (!identityChanged)
        {
            return;
        }
        _generation++;
        _index = null;
        _error = null;
        _loading = _authenticated;
        if (_authenticated)
        {
            unawaited(_load(setBusy: false));
        }
    }

    @override
    void dispose()
    {
        widget.controller?.detach(_refreshHandler);
        _scrollController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            appBar: AppBar(
                title: const Text('论坛'),
                actions: <Widget>[
                    if (_hasCommunityNavigation)
                        PopupMenuButton<_CommunityDestination>(
                            key: const Key('forum-community-menu'),
                            tooltip: '社区与账号',
                            onSelected: _openCommunity,
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<_CommunityDestination>>[
                                    if (_index?.navigation.noticesUri != null)
                                        PopupMenuItem<_CommunityDestination>(
                                            value: _CommunityDestination.notices,
                                            child: Text(
                                                _index!.viewer.noticeCount > 0
                                                    ? '通知 (${_index!.viewer.noticeCount})'
                                                    : '通知',
                                            ),
                                        ),
                                    if (_index?.navigation.messagesUri != null)
                                        PopupMenuItem<_CommunityDestination>(
                                            value: _CommunityDestination.messages,
                                            child: Text(
                                                _index!.viewer
                                                            .privateMessageCount >
                                                        0
                                                    ? '私信 (${_index!.viewer.privateMessageCount})'
                                                    : '私信',
                                            ),
                                        ),
                                    if (_index?.navigation.profileUri != null)
                                        const PopupMenuItem<
                                            _CommunityDestination
                                        >(
                                            value: _CommunityDestination.profile,
                                            child: Text('个人资料'),
                                        ),
                                ],
                            icon: const Icon(Icons.account_circle_outlined),
                        ),
                    if (_index?.navigation.searchUri != null)
                        IconButton(
                            tooltip: '搜索论坛',
                            onPressed: () => _openSearch(
                                _index!.navigation.searchUri!,
                            ),
                            icon: const Icon(Icons.search),
                        ),
                ],
            ),
            body: _buildBody(),
        );
    }

    Widget _buildBody()
    {
        if (!_authenticated)
        {
            final String message = widget.authState.sessionExpired
                ? '登录状态已失效，请重新登录后查看论坛'
                : widget.authState.status == AuthStatus.authenticated
                    ? '无法确认论坛账号，请重新登录'
                    : '登录后查看论坛';
            return AppEmptyView(
                message: message,
                onRefresh: widget.onLogin,
                actionLabel: '登录',
            );
        }
        if (_loading && _index == null)
        {
            return const AppLoadingView(message: '正在加载论坛');
        }
        if (_error != null && _index == null)
        {
            return AppErrorView(
                message: _error.toString(),
                onRetry: () => _load(setBusy: true),
            );
        }
        final ForumBoardIndex? index = _index;
        if (index == null)
        {
            return AppEmptyView(
                message: '暂无可见版块',
                onRefresh: () => _load(setBusy: true),
            );
        }
        final List<_ForumIndexEntry> entries = _entries(index);
        final Widget list = RefreshIndicator(
            onRefresh: () => _load(setBusy: false),
            child: ListView.builder(
                key: const PageStorageKey<String>('forum-board-index'),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: entries.length,
                itemBuilder: (BuildContext context, int position)
                {
                    final _ForumIndexEntry entry = entries[position];
                    if (entry.heading != null)
                    {
                        return _SectionHeading(entry.heading!);
                    }
                    return _BoardTile(
                        board: entry.board!,
                        depth: entry.depth,
                        onTap: () => _openBoard(entry.board!),
                    );
                },
            ),
        );
        if (!index.isFromCache)
        {
            return list;
        }
        return Column(
            children: <Widget>[
                ForumCacheBanner(updatedAt: index.cacheUpdatedAt),
                Expanded(child: list),
            ],
        );
    }

    Future<void> _scrollToTopAndRefresh() async
    {
        if (_scrollController.hasClients)
        {
            await _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
            );
        }
        await _load(setBusy: _index == null);
    }

    Future<void> _load({required bool setBusy}) async
    {
        if (!_authenticated)
        {
            return;
        }
        final int generation = ++_generation;
        if (setBusy && mounted)
        {
            setState(()
            {
                _loading = true;
                _error = null;
            });
        }
        try
        {
            final ForumBoardIndex result = await ref
                .read(forumReadRepositoryProvider)
                .loadIndex();
            if (!mounted || generation != _generation)
            {
                return;
            }
            setState(()
            {
                _index = result;
                _error = null;
                _loading = false;
            });
        }
        on ForumRequestSupersededException
        {
            if (mounted && generation == _generation && _index == null)
            {
                setState(()
                {
                    _loading = false;
                });
            }
        }
        on ForumSessionExpiredException
        {
            if (mounted && generation == _generation)
            {
                setState(()
                {
                    _loading = false;
                });
                ref.read(authControllerProvider.notifier).markSessionExpired();
            }
        }
        on Object catch (error)
        {
            if (!mounted || generation != _generation)
            {
                return;
            }
            setState(()
            {
                _error = error;
                _loading = false;
            });
        }
    }

    List<_ForumIndexEntry> _entries(ForumBoardIndex index)
    {
        final List<_ForumIndexEntry> result = <_ForumIndexEntry>[];
        for (final ForumSection section in index.sections)
        {
            result.add(_ForumIndexEntry.heading(section.name));
            for (final ForumBoardNode board in section.boards)
            {
                _appendBoard(result, board, 0);
            }
        }
        if (index.unsectionedBoards.isNotEmpty)
        {
            result.add(const _ForumIndexEntry.heading('其他'));
            for (final ForumBoardNode board in index.unsectionedBoards)
            {
                _appendBoard(result, board, 0);
            }
        }
        return result;
    }

    void _appendBoard(
        List<_ForumIndexEntry> target,
        ForumBoardNode board,
        int depth,
    )
    {
        target.add(_ForumIndexEntry.board(board, depth));
        for (final ForumBoardNode child in board.children)
        {
            _appendBoard(target, child, depth + 1);
        }
    }

    void _openBoard(ForumBoardNode board)
    {
        final ValueChanged<ForumBoardNode>? onOpenBoard = widget.onOpenBoard;
        if (onOpenBoard != null)
        {
            onOpenBoard(board);
            return;
        }
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => ForumBoardPage(board: board),
            ),
        );
    }

    void _openSearch(Uri formUri)
    {
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => ForumSearchPage(
                    formUri: formUri,
                    onOpenResult: _openSearchResult,
                ),
            ),
        );
    }

    bool get _hasCommunityNavigation
    {
        final ForumNavigationLinks? navigation = _index?.navigation;
        return navigation?.noticesUri != null ||
            navigation?.messagesUri != null ||
            navigation?.profileUri != null;
    }

    void _openCommunity(_CommunityDestination destination)
    {
        final ForumBoardIndex? index = _index;
        if (index == null)
        {
            return;
        }
        final Widget? page = switch (destination)
        {
            _CommunityDestination.notices
                when index.navigation.noticesUri != null =>
                CommunityNoticesScreen(uri: index.navigation.noticesUri!),
            _CommunityDestination.messages
                when index.navigation.messagesUri != null =>
                CommunityMessagesScreen(uri: index.navigation.messagesUri!),
            _CommunityDestination.profile
                when index.navigation.profileUri != null &&
                    widget.authState.userId > 0 => CommunityProfileScreen(
                uri: index.navigation.profileUri!,
                profileUserId: widget.authState.userId,
            ),
            _ => null,
        };
        if (page == null)
        {
            return;
        }
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => page,
            ),
        );
    }

    void _openSearchResult(ForumThreadSearchHit hit)
    {
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => ForumTopicPage(
                    thread: ForumThreadSummary(
                        id: hit.threadId,
                        boardId: hit.boardId,
                        title: hit.title,
                        uri: hit.uri,
                        summary: hit.summary,
                        author: hit.author,
                        avatarUri: hit.avatarUri,
                        timeLabel: hit.timeLabel,
                        views: hit.views,
                        replies: hit.replies,
                    ),
                    focusedPostId: hit.postId,
                ),
            ),
        );
    }
}

class _SectionHeading extends StatelessWidget
{
    const _SectionHeading(this.label);

    final String label;

    @override
    Widget build(BuildContext context)
    {
        return Container(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
                label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                ),
            ),
        );
    }
}

class _BoardTile extends StatelessWidget
{
    const _BoardTile({
        required this.board,
        required this.depth,
        required this.onTap,
    });

    final ForumBoardNode board;
    final int depth;
    final VoidCallback onTap;

    @override
    Widget build(BuildContext context)
    {
        final List<String> counts = <String>[
            if (board.todayPostCount > 0) '今日 ${board.todayPostCount}',
            if (board.threadCount > 0) '主题 ${board.threadCount}',
            if (board.postCount > 0) '帖子 ${board.postCount}',
        ];
        final String subtitle = <String>[
            board.description,
            counts.join(' · '),
        ].where((String value) => value.isNotEmpty).join('\n');
        return Column(
            children: <Widget>[
                ListTile(
                    key: ValueKey<String>('forum-board-${board.id}'),
                    contentPadding: EdgeInsets.only(
                        left: 16 + depth * 20,
                        right: 12,
                    ),
                    dense: depth > 0,
                    title: Text(
                        board.name,
                        style: TextStyle(
                            fontSize: depth > 0 ? 14 : 16,
                            fontWeight: depth > 0
                                ? FontWeight.normal
                                : FontWeight.w600,
                        ),
                    ),
                    subtitle: subtitle.isEmpty
                        ? null
                        : Text(
                            subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, height: 1.4),
                        ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: onTap,
                ),
                Divider(
                    height: 1,
                    indent: 16 + depth * 20,
                    endIndent: 12,
                ),
            ],
        );
    }
}

class _ForumIndexEntry
{
    const _ForumIndexEntry.heading(this.heading)
        : board = null,
          depth = 0;

    const _ForumIndexEntry.board(this.board, this.depth) : heading = null;

    final String? heading;
    final ForumBoardNode? board;
    final int depth;
}

enum _CommunityDestination
{
    notices,
    messages,
    profile,
}
