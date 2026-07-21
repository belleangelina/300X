import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:x300/features/library/application/work_index_coordinator.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/work_detail_page.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/search/application/search_cooldown.dart';
import 'package:x300/features/search/data/forum_search_repository.dart';
import 'package:x300/features/search/data/search_cache_repository.dart';
import 'package:x300/features/search/domain/search_models.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';
import 'package:x300/shared/presentation/app_snack_bar.dart';

enum SearchResultMode { aggregated, raw }

class SearchPage extends ConsumerStatefulWidget
{
    const SearchPage({
        required this.kind,
        this.initialKeyword = '',
        this.initialResultMode = SearchResultMode.aggregated,
        this.autoSubmit = false,
        super.key,
    });

    final LibraryKind kind;
    final String initialKeyword;
    final SearchResultMode initialResultMode;
    final bool autoSubmit;

    @override
    ConsumerState<SearchPage> createState()
    {
        return _SearchPageState();
    }
}

class _SearchPageState extends ConsumerState<SearchPage>
{
    final TextEditingController _searchController = TextEditingController();
    final ScrollController _scrollController = ScrollController();
    final List<SourceThread> _sourceThreads = <SourceThread>[];

    late final Timer _cooldownTimer;
    ForumSearchPage? _cursor;
    List<Work> _works = <Work>[];
    Object? _error;
    bool _searched = false;
    bool _loading = false;
    bool _loadingMore = false;
    bool _usingCache = false;
    bool _cacheFromFailure = false;
    bool _waitingForCooldown = false;
    String _loadingMessage = '正在搜索论坛';
    DateTime? _cacheUpdatedAt;
    String _activeKeyword = '';
    late SearchResultMode _resultMode;

    @override
    void initState()
    {
        super.initState();
        _searchController.text = widget.initialKeyword;
        _resultMode = widget.initialResultMode;
        _scrollController.addListener(_handleScroll);
        _cooldownTimer = Timer.periodic(
            const Duration(milliseconds: 250),
            _handleCooldownTick,
        );
        if (widget.autoSubmit && widget.initialKeyword.trim().isNotEmpty)
        {
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => unawaited(_initializeAutomaticSearch()),
            );
        }
    }

    @override
    void dispose()
    {
        _cooldownTimer.cancel();
        _searchController.dispose();
        _scrollController
            ..removeListener(_handleScroll)
            ..dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        final SearchCooldown cooldown = ref.watch(searchCooldownProvider);
        final int remainingSeconds = cooldown.remainingSeconds;
        return DefaultTabController(
            length: 2,
            initialIndex: _resultMode.index,
            child: Scaffold(
                appBar: AppBar(
                    automaticallyImplyLeading: false,
                    titleSpacing: 8,
                    title: SizedBox(
                        height: 40,
                        child: TextField(
                            controller: _searchController,
                            autofocus: !widget.autoSubmit,
                            maxLength: 40,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                                hintText: widget.kind == LibraryKind.comic ? '搜索漫画' : '搜索小说',
                                counterText: '',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                border: const OutlineInputBorder(),
                                prefixIcon: SizedBox(
                                    width: 48,
                                    child: IconButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        icon: const Icon(Icons.arrow_back),
                                    ),
                                ),
                                suffixIcon: SizedBox(
                                    width: 48,
                                    child: _buildSearchAction(remainingSeconds),
                                ),
                            ),
                            onSubmitted: (String value) => _submit(),
                        ),
                    ),
                ),
                body: _buildBody(),
                bottomNavigationBar: _showResultModeSelector
                    ? _buildResultModeSelector()
                    : null,
            ),
        );
    }

    Widget _buildSearchAction(int remainingSeconds)
    {
        if (_loading)
        {
            return const Center(
                child: SizedBox.square(
                    key: Key('search-loading-indicator'),
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                ),
            );
        }
        if (remainingSeconds > 0)
        {
            return Tooltip(
                message: '新搜索需等待 $remainingSeconds 秒',
                child: Center(
                    child: Text(
                        '${remainingSeconds}s',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                ),
            );
        }
        return IconButton(onPressed: _submit, icon: const Icon(Icons.search));
    }

    Widget _buildBody()
    {
        if (_loading)
        {
            return AppLoadingView(message: _loadingMessage);
        }
        if (_error != null && _works.isEmpty && _sourceThreads.isEmpty)
        {
            return AppErrorView(message: _error.toString(), onRetry: _submit);
        }
        if (!_searched)
        {
            return Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                        Icon(
                            Icons.search,
                            size: 44,
                            color: Colors.grey.withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 12),
                        Text(
                            widget.kind == LibraryKind.comic
                                    ? '输入作品名搜索漫画区'
                                    : '输入作品名同时搜索轻小说和文学区',
                            style: const TextStyle(color: Colors.grey),
                        ),
                    ],
                ),
            );
        }
        if (_waitingForCooldown)
        {
            final SearchCooldown cooldown = ref.read(searchCooldownProvider);
            final String message = cooldown.inFlight
                    ? '已有搜索正在进行，完成后将自动搜索'
                    : '论坛限制搜索频率，${cooldown.remainingSeconds} 秒后自动搜索';
            return Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                        const Icon(Icons.schedule, size: 40, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(message, style: const TextStyle(color: Colors.grey)),
                    ],
                ),
            );
        }
        final List<Work> visibleWorks = _visibleWorks;
        if (_works.isEmpty && _sourceThreads.isEmpty)
        {
            return AppEmptyView(message: '没有找到相关作品', onRefresh: _submit);
        }
        return Column(
            children: <Widget>[
                if (_usingCache) _buildCacheNotice(),
                Expanded(
                    child: visibleWorks.isEmpty
                            ? AppEmptyView(
                                    message: _resultMode == SearchResultMode.aggregated
                                            ? '没有可聚合的作品，请切换到原始帖子'
                                            : '没有找到原始帖子',
                                )
                            : ListView.separated(
                                    controller: _scrollController,
                                    itemCount: visibleWorks.length + (_loadingMore ? 1 : 0),
                                    separatorBuilder: (BuildContext context, int index) =>
                                            Divider(
                                                height: 1,
                                                indent: 12,
                                                endIndent: 12,
                                                color: Colors.grey.withValues(alpha: 0.2),
                                            ),
                                    itemBuilder: (BuildContext context, int index)
                                    {
                                        if (index >= visibleWorks.length)
                                        {
                                            return const Padding(
                                                padding: EdgeInsets.all(20),
                                                child: Center(
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                ),
                                            );
                                        }
                                        final Work work = visibleWorks[index];
                                        return WorkListTile(
                                            work: work,
                                            onTap: () => _resultMode == SearchResultMode.aggregated
                                                    ? _openWork(work)
                                                    : _openRawWork(work),
                                        );
                                    },
                                ),
                ),
            ],
        );
    }

    Widget _buildResultModeSelector()
    {
        return Material(
            key: const Key('search-result-mode-bottom-bar'),
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
                        Tab(text: '原始结果'),
                    ],
                    onTap: (int index)
                    {
                        final SearchResultMode mode =
                                SearchResultMode.values[index];
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
        _searched &&
        !_waitingForCooldown &&
        (_works.isNotEmpty || _sourceThreads.isNotEmpty);

    List<Work> get _visibleWorks
    {
        if (_resultMode == SearchResultMode.aggregated)
        {
            return _works;
        }
        return _sourceThreads.map(_rawWorkForThread).toList(growable: false);
    }

    Work _rawWorkForThread(SourceThread thread)
    {
        final Chapter chapter = Chapter(
            id: 'forum-thread:${thread.tid}',
            title: '正文',
            sourceUri: thread.uri,
            sourceTid: thread.tid,
        );
        return Work(
            id: 'forum-thread:${thread.tid}',
            kind: thread.board.kind,
            title: thread.title,
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
        );
    }

    List<SourceThread> _sourceThreadsFromWorks(List<Work> works)
    {
        final Map<int, SourceThread> threads = <int, SourceThread>{};
        for (final Work work in works)
        {
            for (final SourceThread thread in work.sourceThreads)
            {
                threads.putIfAbsent(thread.tid, () => thread);
            }
        }
        return threads.values.toList(growable: false);
    }

    Widget _buildCacheNotice()
    {
        final DateTime? updatedAt = _cacheUpdatedAt;
        final String time = updatedAt == null
                ? ''
                : ' · ${DateFormat('MM-dd HH:mm').format(updatedAt)}';
        return Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                    children: <Widget>[
                        const Icon(Icons.cloud_off_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                _cacheFromFailure ? '网络不可用，当前显示本机搜索缓存$time' : '当前显示本机搜索缓存$time',
                                style: const TextStyle(fontSize: 12),
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    Future<void> _initializeAutomaticSearch() async
    {
        final String keyword = widget.initialKeyword.trim();
        final SearchCacheSnapshot? cached = await _loadSearchCache(keyword);
        if (!mounted)
        {
            return;
        }
        if (cached != null)
        {
            setState(()
            {
                _searched = true;
                _error = null;
                _cursor = null;
                _works = cached.works;
                _sourceThreads
                    ..clear()
                    ..addAll(_sourceThreadsFromWorks(cached.works));
                _usingCache = true;
                _cacheFromFailure = false;
                _cacheUpdatedAt = cached.updatedAt;
                _activeKeyword = keyword;
            });
            return;
        }

        final SearchCooldown cooldown = ref.read(searchCooldownProvider);
        if (cooldown.inFlight || cooldown.remainingSeconds > 0)
        {
            setState(()
            {
                _searched = true;
                _waitingForCooldown = true;
                _activeKeyword = keyword;
            });
            return;
        }
        await _submit();
    }

    void _handleCooldownTick(Timer timer)
    {
        if (!mounted)
        {
            return;
        }
        final SearchCooldown cooldown = ref.read(searchCooldownProvider);
        if (_waitingForCooldown &&
                !cooldown.inFlight &&
                cooldown.remainingSeconds == 0)
        {
            setState(()
            {
                _waitingForCooldown = false;
            });
            unawaited(_submit());
            return;
        }
        setState(()
        {
        });
    }

    Future<void> _submit() async
    {
        final String keyword = _searchController.text.trim();
        if (keyword.isEmpty)
        {
            setState(()
            {
                _searched = false;
                _error = null;
                _cursor = null;
                _works = <Work>[];
                _sourceThreads.clear();
                _usingCache = false;
                _cacheFromFailure = false;
                _waitingForCooldown = false;
                _cacheUpdatedAt = null;
                _activeKeyword = '';
                _resultMode = widget.initialResultMode;
            });
            return;
        }

        final SearchCooldown cooldown = ref.read(searchCooldownProvider);
        if (!cooldown.tryBegin())
        {
            final String message = cooldown.inFlight
                    ? '搜索正在进行中'
                    : '论坛限制新搜索频率，请在 ${cooldown.remainingSeconds} 秒后重试';
            if (mounted)
            {
                setState(()
                {
                });
                ScaffoldMessenger.of(
                    context,
                ).showSnackBar(AppSnackBar(content: Text(message)));
            }
            return;
        }

        setState(()
        {
            _waitingForCooldown = false;
            _loading = true;
            _loadingMessage = '正在搜索论坛';
            _loadingMore = false;
            _searched = true;
            _error = null;
            _cursor = null;
            _works = <Work>[];
            _sourceThreads.clear();
            _usingCache = false;
            _cacheFromFailure = false;
            _cacheUpdatedAt = null;
            _activeKeyword = keyword;
        });
        try
        {
            final ForumSearchRepository repository = ref.read(
                forumSearchRepositoryProvider,
            );
            final ForumSearchPage page = await repository.search(
                keyword: keyword,
                kind: widget.kind,
            );
            cooldown.accepted();
            final List<SourceThread> sourceThreads = <SourceThread>[
                ...page.sourceThreads,
            ];
            final List<Work> works = repository.aggregateThreads(sourceThreads);
            await _saveSearchCache(keyword, works);
            if (!mounted)
            {
                return;
            }
            setState(()
            {
                _cursor = page;
                _sourceThreads.addAll(sourceThreads);
                _works = works;
                _loading = false;
                _usingCache = false;
                _cacheFromFailure = false;
                _cacheUpdatedAt = null;
            });
        }
        on Object catch (error)
        {
            cooldown.failed();
            final SearchCacheSnapshot? cached = await _loadSearchCache(keyword);
            if (!mounted)
            {
                return;
            }
            setState(()
            {
                _loading = false;
                _error = error;
                _works = cached?.works ?? <Work>[];
                _sourceThreads.addAll(
                    _sourceThreadsFromWorks(cached?.works ?? const <Work>[]),
                );
                _usingCache = cached != null;
                _cacheFromFailure = cached != null;
                _cacheUpdatedAt = cached?.updatedAt;
            });
        }
    }

    Future<void> _loadMore() async
    {
        final ForumSearchPage? cursor = _cursor;
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
            final ForumSearchRepository repository = ref.read(
                forumSearchRepositoryProvider,
            );
            final ForumSearchPage page = await repository.loadNext(cursor);
            if (!mounted)
            {
                return;
            }
            final Set<int> knownThreads = _sourceThreads
                    .map((SourceThread value) => value.tid)
                    .toSet();
            setState(()
            {
                _cursor = page;
                _sourceThreads.addAll(
                    page.sourceThreads.where(
                        (SourceThread value) => knownThreads.add(value.tid),
                    ),
                );
                _works = repository.aggregateThreads(_sourceThreads);
                _loadingMore = false;
            });
            await _saveSearchCache(_activeKeyword, _works);
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
            ScaffoldMessenger.of(
                context,
            ).showSnackBar(AppSnackBar(content: Text('加载下一页失败：$error')));
        }
    }

    Future<void> _saveSearchCache(String keyword, List<Work> works) async
    {
        try
        {
            await ref
                    .read(searchCacheRepositoryProvider)
                    .save(kind: widget.kind, keyword: keyword, works: works);
        }
        on Object
        {
            return;
        }
    }

    Future<SearchCacheSnapshot?> _loadSearchCache(String keyword) async
    {
        try
        {
            return await ref
                    .read(searchCacheRepositoryProvider)
                    .load(kind: widget.kind, keyword: keyword);
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

    void _openWork(Work work)
    {
        if (_loadingMore)
        {
            ScaffoldMessenger.of(
                context,
            ).showSnackBar(const AppSnackBar(content: Text('正在加载更多搜索结果，请稍候')));
            return;
        }
        final int initialSourceTid = work.primarySourceTid;
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => WorkDetailPage(
                    work: work,
                    initialSourceTid: initialSourceTid,
                    resolveOnOpen: true,
                    resolver:
                            (
                                WorkIndexCancellation cancellation,
                                WorkIndexProgress onProgress,
                            ) => _resolveSearchWork(work, cancellation, onProgress),
                ),
            ),
        );
    }

    void _openRawWork(Work work)
    {
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => WorkDetailPage(
                    work: work,
                    initialSourceTid: work.primarySourceTid,
                    rawSourceMode: true,
                ),
            ),
        );
    }

    Future<WorkIndexResult> _resolveSearchWork(
        Work work,
        WorkIndexCancellation cancellation,
        WorkIndexProgress onProgress,
    ) async
    {
        cancellation.throwIfCancelled();
        final WorkIndexCoordinator coordinator = ref.read(
            workIndexCoordinatorProvider,
        );
        Work target = work;
        final ForumSearchPage? initialCursor = _cursor;
        final bool activeSearch = !_usingCache && initialCursor != null;
        final bool completeSearch =
                activeSearch && coordinator.shouldCompleteActiveSearch(work);
        if (activeSearch)
        {
            final ForumSearchRepository repository = ref.read(
                forumSearchRepositoryProvider,
            );
            ForumSearchPage cursor = initialCursor;
            final List<SourceThread> sourceThreads = <SourceThread>[
                ..._sourceThreads,
            ];
            final Set<int> knownThreads = sourceThreads
                    .map((SourceThread value) => value.tid)
                    .toSet();
            while (completeSearch && cursor.hasMore)
            {
                cancellation.throwIfCancelled();
                onProgress('正在补全搜索目录（${cursor.currentPage}/${cursor.totalPages}）');
                cursor = await repository.loadNext(cursor);
                cancellation.throwIfCancelled();
                sourceThreads.addAll(
                    cursor.sourceThreads.where(
                        (SourceThread value) => knownThreads.add(value.tid),
                    ),
                );
            }
            final List<Work> works = repository.aggregateThreads(sourceThreads);
            final Work? matched = coordinator.findMatchingWork(work, works);
            target = matched == null ? work : _withWorkId(matched, work.id);
            cancellation.throwIfCancelled();
            if (mounted)
            {
                setState(()
                {
                    _cursor = cursor;
                    _sourceThreads
                        ..clear()
                        ..addAll(sourceThreads);
                    _works = works;
                });
            }
            await _saveSearchCache(_activeKeyword, works);
            cancellation.throwIfCancelled();
        }
        onProgress('正在解析楼主帖子和帖内目录');
        return activeSearch
                ? coordinator.rebuildFromActiveSearch(
                        target,
                        onProgress: onProgress,
                        cancellation: cancellation,
                    )
                : coordinator.ensure(
                        target,
                        allowNewSearch: false,
                        onProgress: onProgress,
                        cancellation: cancellation,
                    );
    }

    Work _withWorkId(Work work, String workId)
    {
        return Work(
            id: workId,
            kind: work.kind,
            title: work.title,
            summary: work.summary,
            author: work.author,
            typeName: work.typeName,
            sourceThreads: work.sourceThreads,
            chapters: work.chapters,
            directories: work.directories,
        );
    }
}
