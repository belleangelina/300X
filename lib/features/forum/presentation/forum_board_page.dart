import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/community/presentation/community_pages.dart';
import 'package:x300/features/favorites/data/forum_board_favorite_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/domain/forum_models.dart' as domain;
import 'package:x300/features/forum/presentation/forum_announcement_page.dart';
import 'package:x300/features/forum/presentation/forum_action_page.dart';
import 'package:x300/features/forum/domain/forum_search_models.dart';
import 'package:x300/features/forum/presentation/forum_read_widgets.dart';
import 'package:x300/features/forum/presentation/forum_search_page.dart';
import 'package:x300/features/forum/presentation/forum_topic_page.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class ForumBoardPage extends ConsumerStatefulWidget
{
    const ForumBoardPage({
        required this.board,
        this.onOpenThread,
        this.onOpenAuthor,
        super.key,
    });

    final domain.ForumBoardNode board;
    final ValueChanged<domain.ForumThreadSummary>? onOpenThread;
    final ValueChanged<domain.ForumThreadSummary>? onOpenAuthor;

    @override
    ConsumerState<ForumBoardPage> createState()
    {
        return _ForumBoardPageState();
    }
}

class _ForumBoardPageState extends ConsumerState<ForumBoardPage>
{
    final ScrollController _scrollController = ScrollController();
    final List<domain.ForumThreadSummary> _threads =
        <domain.ForumThreadSummary>[];
    domain.ForumBoardPage? _page;
    late Uri _routeUri;
    Object? _error;
    bool _loading = true;
    bool _loadingMore = false;
    bool _favoriteBusy = false;
    int _generation = 0;

    @override
    void initState()
    {
        super.initState();
        _routeUri = widget.board.uri;
        unawaited(_load(_routeUri, reset: true, setBusy: false));
    }

    @override
    void didUpdateWidget(covariant ForumBoardPage oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        if (oldWidget.board.id == widget.board.id &&
            oldWidget.board.uri == widget.board.uri)
        {
            return;
        }
        _routeUri = widget.board.uri;
        _page = null;
        _threads.clear();
        _error = null;
        _loading = true;
        _loadingMore = false;
        _generation++;
        unawaited(_load(_routeUri, reset: true, setBusy: false));
    }

    @override
    void dispose()
    {
        _scrollController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        final domain.ForumBoardPage? page = _page;
        return Scaffold(
            appBar: AppBar(
                title: Text(page?.board.name ?? widget.board.name),
                actions: <Widget>[
                    if (page?.favoriteUri != null && !page!.isFromCache)
                        IconButton(
                            key: const Key('forum-favorite-board'),
                            tooltip: '收藏版块',
                            onPressed: _favoriteBusy
                                ? null
                                : () => _addBoardFavorite(page),
                            icon: const Icon(Icons.bookmark_add_outlined),
                        ),
                    if (page?.searchUri != null)
                        IconButton(
                            tooltip: '搜索本版',
                            onPressed: () => _openSearch(page!.searchUri!),
                            icon: const Icon(Icons.search),
                        ),
                ],
            ),
            body: _buildBody(),
            floatingActionButton: page?.newThreadUri == null ||
                    page!.isFromCache
                ? null
                : FloatingActionButton.extended(
                    key: const Key('forum-new-thread'),
                    onPressed: () => _openNewThread(page),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('发主题'),
                ),
        );
    }

    Widget _buildBody()
    {
        if (_loading && _page == null)
        {
            return const AppLoadingView(message: '正在加载版块');
        }
        if (_error != null && _page == null)
        {
            return AppErrorView(
                message: _error.toString(),
                onRetry: () => _load(_routeUri, reset: true, setBusy: true),
            );
        }
        final domain.ForumBoardPage? page = _page;
        if (page == null)
        {
            return AppEmptyView(
                message: '暂无主题',
                onRefresh: () => _load(_routeUri, reset: true, setBusy: true),
            );
        }
        final Widget content = RefreshIndicator(
            onRefresh: () => _load(_routeUri, reset: true, setBusy: false),
            child: ListView(
                key: PageStorageKey<String>('forum-board-${widget.board.id}'),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                    if (page.filters.isNotEmpty)
                        _FilterBar(
                            options: page.filters,
                            onSelected: (domain.ForumRouteOption option)
                            {
                                _routeUri = option.uri;
                                unawaited(_load(
                                    option.uri,
                                    reset: true,
                                    setBusy: true,
                                ));
                            },
                        ),
                    if (_error != null)
                        _InlineWarning(
                            message: '刷新失败，已保留当前内容：$_error',
                        ),
                    if (_threads.isEmpty)
                        const SizedBox(
                            height: 320,
                            child: AppEmptyView(message: '暂无主题'),
                        ),
                    for (final domain.ForumThreadSummary thread in _threads)
                        _ThreadTile(
                            thread: thread,
                            onTap: () => _openThread(thread),
                            onOpenAuthor: thread.authorUri == null ||
                                    (thread.authorId ?? 0) <= 0
                                ? null
                                : () => _openAuthor(thread),
                        ),
                    _PageTail(
                        cursor: page.cursor,
                        loading: _loadingMore,
                        onNext: page.cursor.nextPageUri == null
                            ? null
                            : _loadMore,
                    ),
                ],
            ),
        );
        if (!page.isFromCache)
        {
            return content;
        }
        return Column(
            children: <Widget>[
                ForumCacheBanner(updatedAt: page.cacheUpdatedAt),
                Expanded(child: content),
            ],
        );
    }

    Future<void> _load(
        Uri uri, {
        required bool reset,
        required bool setBusy,
    }) async
    {
        final int generation = ++_generation;
        if (setBusy && mounted)
        {
            setState(()
            {
                _loading = true;
                _loadingMore = false;
                _error = null;
                if (reset)
                {
                    _page = null;
                    _threads.clear();
                }
            });
        }
        try
        {
            final domain.ForumBoardPage result = await ref
                .read(forumReadRepositoryProvider)
                .loadBoard(uri, expectedBoardId: widget.board.id);
            if (!mounted || generation != _generation)
            {
                return;
            }
            setState(()
            {
                _page = result;
                _threads
                    ..clear()
                    ..addAll(result.threads);
                _loading = false;
                _loadingMore = false;
                _error = null;
            });
            if (_scrollController.hasClients)
            {
                _scrollController.jumpTo(0);
            }
        }
        on ForumRequestSupersededException
        {
            if (mounted && generation == _generation)
            {
                setState(()
                {
                    _loading = false;
                    _loadingMore = false;
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
                    _loadingMore = false;
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
                _loading = false;
                _loadingMore = false;
                _error = error;
            });
        }
    }

    Future<void> _loadMore() async
    {
        final domain.ForumBoardPage? cursor = _page;
        if (_loadingMore || cursor?.cursor.nextPageUri == null)
        {
            return;
        }
        final int generation = ++_generation;
        setState(()
        {
            _loadingMore = true;
        });
        try
        {
            final domain.ForumBoardPage result = await ref
                .read(forumReadRepositoryProvider)
                .loadNextBoard(cursor!);
            if (!mounted || generation != _generation)
            {
                return;
            }
            final Set<String> known = _threads
                .map(
                    (domain.ForumThreadSummary value) =>
                        '${value.targetKind.name}:${value.id}',
                )
                .toSet();
            setState(()
            {
                _page = result;
                _threads.addAll(
                    result.threads.where(
                        (domain.ForumThreadSummary value) => known.add(
                            '${value.targetKind.name}:${value.id}',
                        ),
                    ),
                );
                _loadingMore = false;
                _error = null;
            });
        }
        on ForumRequestSupersededException
        {
            if (mounted && generation == _generation)
            {
                setState(()
                {
                    _loadingMore = false;
                });
            }
        }
        on ForumSessionExpiredException
        {
            if (mounted && generation == _generation)
            {
                setState(()
                {
                    _loadingMore = false;
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
                _loadingMore = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('加载下一页失败：$error')),
            );
        }
    }

    void _openThread(domain.ForumThreadSummary thread)
    {
        final ValueChanged<domain.ForumThreadSummary>? onOpenThread =
            widget.onOpenThread;
        if (onOpenThread != null)
        {
            onOpenThread(thread);
            return;
        }
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => thread.targetKind ==
                        domain.ForumThreadTargetKind.announcement
                    ? ForumAnnouncementPage(announcement: thread)
                    : ForumTopicPage(thread: thread),
            ),
        );
    }

    void _openAuthor(domain.ForumThreadSummary thread)
    {
        final Uri? uri = thread.authorUri;
        final int userId = thread.authorId ?? 0;
        if (uri == null || userId <= 0)
        {
            return;
        }
        final ValueChanged<domain.ForumThreadSummary>? callback =
            widget.onOpenAuthor;
        if (callback != null)
        {
            callback(thread);
            return;
        }
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => CommunityProfileScreen(
                    uri: uri,
                    profileUserId: userId,
                ),
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

    void _openSearchResult(ForumThreadSearchHit hit)
    {
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => ForumTopicPage(
                    thread: domain.ForumThreadSummary(
                        id: hit.threadId,
                        boardId: hit.boardId,
                        title: hit.title,
                        uri: hit.uri,
                        summary: hit.summary,
                        author: hit.author,
                        authorId: hit.authorId,
                        authorUri: hit.authorUri,
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

    Future<void> _openNewThread(domain.ForumBoardPage page) async
    {
        final Uri? entryUri = page.newThreadUri;
        if (entryUri == null || page.isFromCache)
        {
            return;
        }
        final ForumActionPageResult? result = await Navigator.of(context).push(
            MaterialPageRoute<ForumActionPageResult>(
                builder: (BuildContext context) => ForumActionPage(
                    request: ForumActionRequest(
                        kind: ForumActionKind.newThread,
                        target: ForumActionTarget(boardId: page.board.id),
                        entryUri: entryUri,
                        readbackUri: page.board.uri,
                    ),
                    title: '在“${page.board.name}”发主题',
                    draftId: 'new-thread:${page.board.id}',
                ),
            ),
        );
        if (!mounted || result == null)
        {
            return;
        }
        await _load(_routeUri, reset: true, setBusy: true);
    }

    Future<void> _addBoardFavorite(domain.ForumBoardPage page) async
    {
        if (_favoriteBusy || page.isFromCache || page.favoriteUri == null)
        {
            return;
        }
        setState(() => _favoriteBusy = true);
        try
        {
            final bool? confirmed = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                    title: const Text('收藏版块'),
                    content: Text(
                        '论坛的版块收藏入口会在请求时立即写入。确认收藏“${page.board.name}”？',
                    ),
                    actions: <Widget>[
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                        ),
                        FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('确认收藏'),
                        ),
                    ],
                ),
            );
            if (confirmed != true || !mounted)
            {
                return;
            }
            final bool changed = await ref
                .read(forumBoardFavoriteRepositoryProvider)
                .add(
                    boardId: page.board.id,
                    entryUri: page.favoriteUri!,
                    refererUri: page.cursor.sourceUri,
                );
            if (!mounted)
            {
                return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(changed ? '版块已收藏' : '该版块已经在收藏中')),
            );
            await _load(_routeUri, reset: true, setBusy: true);
        }
        on ForumBoardFavoriteBlockedException catch (blocked)
        {
            if (mounted)
            {
                await _resolveFavoriteBlocked(blocked);
            }
        }
        on ForumSessionExpiredException
        {
            if (mounted)
            {
                ref.read(authControllerProvider.notifier).markSessionExpired();
            }
        }
        on Object catch (error)
        {
            if (mounted)
            {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                );
            }
        }
        finally
        {
            if (mounted)
            {
                setState(() => _favoriteBusy = false);
            }
        }
    }

    Future<void> _resolveFavoriteBlocked(
        ForumBoardFavoriteBlockedException blocked,
    ) async
    {
        final bool? readback = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
                title: const Text('收藏结果尚未确认'),
                content: const Text('请求可能已在论坛执行。请勿重复点击，可先完整回读版块收藏列表。'),
                actions: <Widget>[
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('稍后处理'),
                    ),
                    FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('重新回读'),
                    ),
                ],
            ),
        );
        if (readback != true || !mounted)
        {
            return;
        }
        try
        {
            final ForumBoardFavoriteRepository repository = ref.read(
                forumBoardFavoriteRepositoryProvider,
            );
            if (await repository.readback(blocked))
            {
                if (mounted)
                {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('收藏列表已确认操作结果')),
                    );
                    await _load(_routeUri, reset: true, setBusy: true);
                }
                return;
            }
            if (!mounted)
            {
                return;
            }
            final bool? acknowledge = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                    title: const Text('仍无法确认'),
                    content: const Text(
                        '只有在你已到论坛网页人工核对结果后，才能解除防重复封存。解除不会再次请求收藏。',
                    ),
                    actions: <Widget>[
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('保留封存'),
                        ),
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('已人工核对，解除'),
                        ),
                    ],
                ),
            );
            if (acknowledge == true)
            {
                await repository.acknowledge(blocked);
            }
        }
        on ForumSessionExpiredException
        {
            if (mounted)
            {
                ref.read(authControllerProvider.notifier).markSessionExpired();
            }
        }
        on Object catch (error)
        {
            if (mounted)
            {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                );
            }
        }
    }

}

class _FilterBar extends StatelessWidget
{
    const _FilterBar({required this.options, required this.onSelected});

    final List<domain.ForumRouteOption> options;
    final ValueChanged<domain.ForumRouteOption> onSelected;

    @override
    Widget build(BuildContext context)
    {
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
                children: options
                    .map(
                        (domain.ForumRouteOption option) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                                label: Text(option.label),
                                selected: option.selected,
                                onSelected: option.selected
                                    ? null
                                    : (bool _) => onSelected(option),
                            ),
                        ),
                    )
                    .toList(growable: false),
            ),
        );
    }
}

class _ThreadTile extends StatelessWidget
{
    const _ThreadTile({
        required this.thread,
        required this.onTap,
        this.onOpenAuthor,
    });

    final domain.ForumThreadSummary thread;
    final VoidCallback onTap;
    final VoidCallback? onOpenAuthor;

    @override
    Widget build(BuildContext context)
    {
        final List<String> states = <String>[
            if (thread.targetKind == domain.ForumThreadTargetKind.announcement)
                '公告',
            if (thread.pinned) '置顶',
            if (thread.digest) '精华',
            if (thread.closed) '已关闭',
            if (thread.special) '特殊主题',
        ];
        final List<String> meta = <String>[
            thread.author,
            thread.timeLabel,
            if (thread.views > 0) '阅读 ${thread.views}',
            if (thread.replies > 0) '回复 ${thread.replies}',
        ].where((String value) => value.isNotEmpty).toList(growable: false);
        return Column(
            children: <Widget>[
                ListTile(
                    key: ValueKey<String>(
                        'forum-${thread.targetKind.name}-${thread.id}',
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                    ),
                    leading: onOpenAuthor == null
                        ? null
                        : IconButton(
                            key: ValueKey<String>(
                                'forum-board-author-${thread.authorId}',
                            ),
                            tooltip: thread.author.isEmpty
                                ? '查看作者资料'
                                : '查看 ${thread.author}',
                            onPressed: onOpenAuthor,
                            icon: const Icon(Icons.account_circle_outlined),
                        ),
                    title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                            if (states.isNotEmpty)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: states
                                            .map(
                                                (String state) => _StateLabel(
                                                    state,
                                                ),
                                            )
                                            .toList(growable: false),
                                    ),
                                ),
                            Text(
                                thread.typeName.isEmpty
                                    ? thread.title
                                    : '【${thread.typeName}】${thread.title}',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                ),
                            ),
                        ],
                    ),
                    subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                            if (thread.summary.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 5),
                                Text(
                                    thread.summary,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                ),
                            ],
                            if (meta.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 5),
                                Text(
                                    meta.join(' · '),
                                    style: const TextStyle(fontSize: 12),
                                ),
                            ],
                        ],
                    ),
                    trailing: Icon(
                        thread.targetKind ==
                                domain.ForumThreadTargetKind.announcement
                            ? Icons.campaign_outlined
                            : Icons.chevron_right,
                        size: 20,
                    ),
                    onTap: onTap,
                ),
                const Divider(height: 1, indent: 16, endIndent: 12),
            ],
        );
    }
}

class _StateLabel extends StatelessWidget
{
    const _StateLabel(this.label);

    final String label;

    @override
    Widget build(BuildContext context)
    {
        return DecoratedBox(
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(label, style: const TextStyle(fontSize: 11)),
            ),
        );
    }
}

class _PageTail extends StatelessWidget
{
    const _PageTail({
        required this.cursor,
        required this.loading,
        required this.onNext,
    });

    final domain.ForumPageCursor cursor;
    final bool loading;
    final VoidCallback? onNext;

    @override
    Widget build(BuildContext context)
    {
        return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                children: <Widget>[
                    Text(
                        '已加载至第 ${cursor.currentPage} / ${cursor.totalPages} 页',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    if (onNext != null) ...<Widget>[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                            onPressed: loading ? null : onNext,
                            icon: loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                    ),
                                )
                                : const Icon(Icons.expand_more),
                            label: Text(loading ? '正在加载' : '加载下一页'),
                        ),
                    ],
                ],
            ),
        );
    }
}

class _InlineWarning extends StatelessWidget
{
    const _InlineWarning({required this.message});

    final String message;

    @override
    Widget build(BuildContext context)
    {
        return Container(
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(message, style: const TextStyle(fontSize: 12)),
        );
    }
}
