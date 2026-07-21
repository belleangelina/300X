import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:x300/features/favorites/data/favorite_cache_repository.dart';
import 'package:x300/features/favorites/data/forum_favorite_repository.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/work_detail_page.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';
import 'package:x300/shared/presentation/app_snack_bar.dart';

enum _FavoriteResultMode { aggregated, raw }

class CloudFavoritesPage extends ConsumerStatefulWidget
{
    const CloudFavoritesPage({this.kind, super.key});

    final LibraryKind? kind;

    @override
    ConsumerState<CloudFavoritesPage> createState()
    {
        return _CloudFavoritesPageState();
    }
}

class _CloudFavoritesPageState extends ConsumerState<CloudFavoritesPage>
{
    final ScrollController _scrollController = ScrollController();
    final List<CloudFavoriteEntry> _entries = <CloudFavoriteEntry>[];
    final Set<String> _busyWorkIds = <String>{};

    CloudFavoritePage? _cursor;
    List<FavoriteWork> _works = <FavoriteWork>[];
    Object? _error;
    bool _loading = true;
    bool _loadingMore = false;
    bool _usingCache = false;
    DateTime? _cacheUpdatedAt;
    _FavoriteResultMode _resultMode = _FavoriteResultMode.aggregated;

    @override
    void initState()
    {
        super.initState();
        _scrollController.addListener(_handleScroll);
        _load(reset: true);
    }

    @override
    void dispose()
    {
        _scrollController
            ..removeListener(_handleScroll)
            ..dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        return DefaultTabController(
            length: 2,
            initialIndex: _resultMode.index,
            child: Scaffold(
                appBar: AppBar(title: Text(_title)),
                body: _buildBody(),
                bottomNavigationBar: _showResultModeSelector
                    ? _buildResultModeSelector()
                    : null,
            ),
        );
    }

    Widget _buildBody()
    {
        final List<FavoriteWork> works = _visibleWorks;
        final bool hasAvailableWorks = _visibleAggregatedWorks.isNotEmpty ||
                _visibleRawWorks.isNotEmpty;
        if (_loading)
        {
            return AppLoadingView(message: '正在同步$_title');
        }
        if (_error != null && !hasAvailableWorks)
        {
            return AppErrorView(
                message: _error.toString(),
                onRetry: () => _load(reset: true),
            );
        }
        if (!hasAvailableWorks)
        {
            return AppEmptyView(
                message: '暂无$_title',
                onRefresh: () => _load(reset: true),
            );
        }
        final Widget list = works.isEmpty
                ? AppEmptyView(
                    message: _resultMode == _FavoriteResultMode.aggregated
                            ? '没有可聚合的收藏，请切换到原始收藏'
                            : '暂无原始收藏',
                    onRefresh: () => _load(reset: true),
                )
                : RefreshIndicator(
                    onRefresh: () => _load(reset: true),
                    child: ListView.separated(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: works.length + (_loadingMore ? 1 : 0),
                separatorBuilder: (BuildContext context, int index) =>
                    Divider(
                        height: 1,
                        indent: 12,
                        endIndent: 12,
                        color: Colors.grey.withValues(alpha: 0.2),
                    ),
                itemBuilder: (BuildContext context, int index)
                {
                    if (index < works.length)
                    {
                        final FavoriteWork item = works[index];
                        final bool busy = _busyWorkIds.contains(
                            item.work.id,
                        );
                        return WorkListTile(
                            work: item.work,
                            onTap: () => _openWork(
                                item.work,
                                raw: _resultMode == _FavoriteResultMode.raw,
                            ),
                            trailing: _usingCache
                                ? const Tooltip(
                                    message: '离线缓存不可修改',
                                    child: Icon(Icons.cloud_off_outlined),
                                )
                                : busy
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                    ),
                                )
                                : IconButton(
                                    tooltip: '取消收藏',
                                    onPressed: () => _remove(item),
                                    icon: const Icon(Icons.favorite),
                                ),
                        );
                    }
                    return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    );
                },
                    ),
                );
        if (!_usingCache)
        {
            return list;
        }
        final DateTime? updatedAt = _cacheUpdatedAt;
        final String time = updatedAt == null
            ? ''
            : ' · ${DateFormat('MM-dd HH:mm').format(updatedAt)}';
        return Column(
            children: <Widget>[
                Material(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                        ),
                        child: Row(
                            children: <Widget>[
                                const Icon(
                                    Icons.cloud_off_outlined,
                                    size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        '论坛不可用，当前显示只读收藏缓存$time',
                                        style: const TextStyle(fontSize: 12),
                                    ),
                                ),
                            ],
                        ),
                    ),
                ),
                Expanded(child: list),
            ],
        );
    }

    Widget _buildResultModeSelector()
    {
        return Material(
            key: const Key('favorite-result-mode-bottom-bar'),
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
                top: false,
                child: TabBar(
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorColor: Theme.of(context).colorScheme.primary,
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : Colors.black87,
                    tabs: const <Tab>[
                        Tab(text: '智能聚合'),
                        Tab(text: '原始收藏'),
                    ],
                    onTap: (int index)
                    {
                        final _FavoriteResultMode mode =
                                _FavoriteResultMode.values[index];
                        if (mode == _resultMode)
                        {
                            return;
                        }
                        setState(()
                        {
                            _resultMode = mode;
                        });
                    },
                ),
            ),
        );
    }

    bool get _showResultModeSelector =>
        !_loading &&
        (_visibleAggregatedWorks.isNotEmpty || _visibleRawWorks.isNotEmpty);

    Future<void> _load({required bool reset}) async
    {
        if (reset)
        {
            setState(()
            {
                _loading = true;
                _loadingMore = false;
                _error = null;
                _cursor = null;
                _entries.clear();
                _works = <FavoriteWork>[];
                _busyWorkIds.clear();
                _usingCache = false;
                _cacheUpdatedAt = null;
            });
        }
        try
        {
            final ForumFavoriteRepository repository = ref.read(
                forumFavoriteRepositoryProvider,
            );
            CloudFavoritePage page = await repository.loadInitial();
            final List<CloudFavoriteEntry> entries = <CloudFavoriteEntry>[
                ...page.entries,
            ];
            while (!_hasRequestedEntries(entries) && page.hasMore)
            {
                page = await repository.loadNext(page);
                entries.addAll(page.entries);
            }
            final List<FavoriteWork> works = repository.aggregateEntries(
                <CloudFavoriteEntry>[
                    ..._entries,
                    ...entries,
                ],
            );
            await _saveCache(works);
            if (!mounted)
            {
                return;
            }
            setState(()
            {
                _cursor = page;
                _entries.addAll(entries);
                _works = works;
                _loading = false;
                _error = null;
                _usingCache = false;
                _cacheUpdatedAt = null;
            });
            _scheduleFillViewport();
        }
        on Object catch (error)
        {
            final FavoriteCacheSnapshot? cached = await _loadCache();
            if (!mounted)
            {
                return;
            }
            setState(()
            {
                _loading = false;
                _error = error;
                _works = cached?.works ?? <FavoriteWork>[];
                _usingCache = cached != null;
                _cacheUpdatedAt = cached?.updatedAt;
            });
        }
    }

    Future<void> _loadMore() async
    {
        final CloudFavoritePage? cursor = _cursor;
        if (_loadingMore || cursor == null || !cursor.hasMore)
        {
            return;
        }
        setState(()
        {
            _loadingMore = true;
        });
        try
        {
            final ForumFavoriteRepository repository = ref.read(
                forumFavoriteRepositoryProvider,
            );
            CloudFavoritePage page = await repository.loadNext(cursor);
            final List<CloudFavoriteEntry> entries = <CloudFavoriteEntry>[
                ...page.entries,
            ];
            while (!_hasRequestedEntries(entries) && page.hasMore)
            {
                page = await repository.loadNext(page);
                entries.addAll(page.entries);
            }
            if (!mounted)
            {
                return;
            }
            final Set<int> knownFavoriteIds = _entries
                .map(
                    (CloudFavoriteEntry value) => value.record.favoriteId,
                )
                .toSet();
            setState(()
            {
                _cursor = page;
                _entries.addAll(
                    entries.where(
                        (CloudFavoriteEntry value) => knownFavoriteIds.add(
                            value.record.favoriteId,
                        ),
                    ),
                );
                _works = repository.aggregateEntries(_entries);
                _loadingMore = false;
            });
            _scheduleFillViewport();
            await _saveCache(_works);
        }
        on Object catch (error)
        {
            if (!mounted)
            {
                return;
            }
            setState(()
            {
                _loadingMore = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
                AppSnackBar(content: Text('加载下一页失败：$error')),
            );
        }
    }

    Future<void> _remove(FavoriteWork item) async
    {
        if (_usingCache)
        {
            return;
        }
        final bool confirmed = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                    title: const Text('取消云端收藏'),
                    content: Text(
                        item.records.length == 1
                                ? '确定取消收藏“${item.work.title}”吗？'
                                : '将取消与“${item.work.title}”匹配的 '
                                        '${item.records.length} 条论坛收藏，是否继续？',
                    ),
                    actions: <Widget>[
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                        ),
                        FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('确定'),
                        ),
                    ],
                ),
            ) ??
            false;
        if (!confirmed || !mounted)
        {
            return;
        }
        setState(()
        {
            _busyWorkIds.add(item.work.id);
        });
        try
        {
            await ref.read(forumFavoriteRepositoryProvider).removeWork(
                item.work,
                item.records,
            );
            if (!mounted)
            {
                return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
                const AppSnackBar(content: Text('已取消云端收藏')),
            );
            await _load(reset: true);
        }
        on Object catch (error)
        {
            if (!mounted)
            {
                return;
            }
            setState(()
            {
                _busyWorkIds.remove(item.work.id);
            });
            ScaffoldMessenger.of(context).showSnackBar(
                AppSnackBar(content: Text('取消收藏失败：$error')),
            );
        }
    }

    Future<void> _saveCache(List<FavoriteWork> works) async
    {
        try
        {
            await ref.read(favoriteCacheRepositoryProvider).save(works);
        }
        on Object
        {
            return;
        }
    }

    Future<FavoriteCacheSnapshot?> _loadCache() async
    {
        try
        {
            return await ref.read(favoriteCacheRepositoryProvider).load();
        }
        on Object
        {
            return null;
        }
    }

    void _handleScroll()
    {
        if (_scrollController.position.extentAfter < 500)
        {
            _loadMore();
        }
    }

    void _scheduleFillViewport()
    {
        WidgetsBinding.instance.addPostFrameCallback((_)
        {
            if (!mounted ||
                !_scrollController.hasClients ||
                _scrollController.position.maxScrollExtent > 0)
            {
                return;
            }
            unawaited(_loadMore());
        });
    }

    void _openWork(Work work, {required bool raw})
    {
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => WorkDetailPage(
                    work: work,
                    resolveOnOpen: !raw,
                    rawSourceMode: raw,
                ),
            ),
        );
    }

    String get _title => switch (widget.kind)
    {
        LibraryKind.comic => '漫画收藏',
        LibraryKind.novel => '小说收藏',
        null => '云端收藏',
    };

    List<FavoriteWork> get _visibleWorks
    {
        return _resultMode == _FavoriteResultMode.raw
                ? _visibleRawWorks
                : _visibleAggregatedWorks;
    }

    List<FavoriteWork> get _visibleAggregatedWorks => _forCurrentKind(_works);

    List<FavoriteWork> get _visibleRawWorks => _forCurrentKind(_rawWorks);

    List<FavoriteWork> _forCurrentKind(List<FavoriteWork> works)
    {
        final LibraryKind? kind = widget.kind;
        if (kind == null)
        {
            return works;
        }
        return works
            .where((FavoriteWork value) => value.work.kind == kind)
            .toList(growable: false);
    }

    List<FavoriteWork> get _rawWorks
    {
        if (!_usingCache)
        {
            return _entries.map(_rawFavoriteFromEntry).toList(growable: false);
        }
        final List<FavoriteWork> values = <FavoriteWork>[];
        for (final FavoriteWork favorite in _works)
        {
            final Map<int, SourceThread> threads = <int, SourceThread>{
                for (final SourceThread thread in favorite.work.sourceThreads)
                    thread.tid: thread,
            };
            for (final CloudFavoriteRecord record in favorite.records)
            {
                final SourceThread? thread = threads[record.threadId];
                if (thread != null)
                {
                    values.add(_rawFavorite(record, thread));
                }
            }
        }
        return values;
    }

    FavoriteWork _rawFavoriteFromEntry(CloudFavoriteEntry entry)
    {
        return _rawFavorite(entry.record, entry.sourceThread);
    }

    FavoriteWork _rawFavorite(
        CloudFavoriteRecord record,
        SourceThread thread,
    )
    {
        final Chapter chapter = Chapter(
            id: 'forum-thread:${thread.tid}',
            title: '正文',
            sourceUri: thread.uri,
            sourceTid: thread.tid,
        );
        return FavoriteWork(
            work: Work(
                id: 'forum-thread:${thread.tid}',
                kind: thread.board.kind,
                title: record.title.isEmpty ? thread.title : record.title,
                summary: thread.summary,
                author: thread.author,
                typeName: thread.typeName,
                sourceThreads: <SourceThread>[thread],
                chapters: <Chapter>[chapter],
                directories: <WorkDirectory>[
                    WorkDirectory(
                        id: 'raw:${thread.tid}',
                        owner: thread.author,
                        sourceTids: <int>[thread.tid],
                        chapters: <Chapter>[chapter],
                    ),
                ],
            ),
            records: <CloudFavoriteRecord>[record],
        );
    }

    bool _hasRequestedEntries(List<CloudFavoriteEntry> entries)
    {
        final LibraryKind? kind = widget.kind;
        return entries.isNotEmpty && (kind == null || entries.any(
            (CloudFavoriteEntry value) => value.sourceThread.board.kind == kind,
        ));
    }
}
