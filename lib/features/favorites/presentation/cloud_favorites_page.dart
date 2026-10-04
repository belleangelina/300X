import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
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
import 'package:x300/shared/presentation/catalog_controls.dart';
import 'package:x300/shared/presentation/tab_app_bar.dart';

typedef OpenFavoriteWork = void Function(Work work, {required bool raw});

class CloudFavoritesPage extends ConsumerStatefulWidget {
  const CloudFavoritesPage({
    required this.authState,
    required this.onLogin,
    this.onOpenWork,
    this.active = true,
    super.key,
  });

  final AuthState authState;
  final VoidCallback onLogin;
  final OpenFavoriteWork? onOpenWork;
  final bool active;

  @override
  ConsumerState<CloudFavoritesPage> createState() => _CloudFavoritesPageState();
}

class _CloudFavoritesPageState extends ConsumerState<CloudFavoritesPage>
    with SingleTickerProviderStateMixin {
  static const List<String> _titles = <String>['漫画', '小说', '原始收藏'];
  late final TabController _tabController;
  final List<CloudFavoriteEntry> _entries = <CloudFavoriteEntry>[];
  final Set<String> _busyWorkIds = <String>{};
  final List<bool> _gridModes = <bool>[false, false, false];

  CloudFavoritePage? _cursor;
  List<FavoriteWork> _works = <FavoriteWork>[];
  Object? _error;
  bool _loading = false;
  bool _loadingMore = false;
  bool _usingCache = false;
  bool _initialLoadStarted = false;
  bool _paginationFailed = false;
  DateTime? _cacheUpdatedAt;
  int _activeTab = 0;
  int _rawFilter = 0;
  int _generation = 0;

  bool get _authenticated =>
      widget.authState.status == AuthStatus.authenticated;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _titles.length, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant CloudFavoritesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authState.status != widget.authState.status ||
        oldWidget.authState.username != widget.authState.username) {
      // In-flight responses from the previous account must not restore its list.
      _generation++;
      _entries.clear();
      _works = <FavoriteWork>[];
      _cursor = null;
      _error = null;
      _usingCache = false;
      _cacheUpdatedAt = null;
      _busyWorkIds.clear();
      _loading = false;
      _loadingMore = false;
      _paginationFailed = false;
      _initialLoadStarted = false;
    }
    _ensureLoaded();
  }

  @override
  void dispose() {
    _generation++;
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (widget.active && _authenticated && !_initialLoadStarted) {
      unawaited(_load());
    }
  }

  bool _isCurrent(int generation) =>
      mounted && _authenticated && generation == _generation;

  void _handleTabChanged() {
    if (_activeTab != _tabController.index) {
      setState(() {
        _activeTab = _tabController.index;
      });
    }
  }

  void _toggleView(int index) {
    setState(() {
      _gridModes[index] = !_gridModes[index];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TabAppBar(
        controller: _tabController,
        tabs: _titles.map((String title) => Tab(text: title)).toList(),
        action: _activeTab < 2
            ? IconButton(
                key: ValueKey<String>('favorite-view-toggle-$_activeTab'),
                tooltip: _gridModes[_activeTab] ? '切换为列表' : '切换为网格',
                onPressed: () => _toggleView(_activeTab),
                icon: Icon(
                  _gridModes[_activeTab]
                      ? Icons.view_list_outlined
                      : Icons.grid_view_outlined,
                ),
              )
            : null,
      ),
      body: TabBarView(
        controller: _tabController,
        children: List<Widget>.generate(_titles.length, (int index) {
          return TickerMode(
            enabled: widget.active && _activeTab == index,
            child: _FavoritesTabView(
              key: ValueKey<int>(index),
              index: index,
              title: _titles[index],
              active: widget.active && _activeTab == index,
              grid: _gridModes[index],
              onToggleView: () => _toggleView(index),
              works: _worksForTab(index),
              status: _buildStatus(),
              loadingMore: _loadingMore,
              hasMore:
                  !_usingCache &&
                  !_paginationFailed &&
                  (_cursor?.hasMore ?? false),
              usingCache: _usingCache,
              cacheUpdatedAt: _cacheUpdatedAt,
              busyWorkIds: _busyWorkIds,
              rawFilter: _rawFilter,
              onRawFilterChanged: (int value) {
                setState(() {
                  _rawFilter = value;
                });
              },
              onRefresh: _load,
              onLoadMore: _loadMore,
              onRemove: _remove,
              onOpenWork: (Work work) => _openWork(work, raw: index == 2),
            ),
          );
        }),
      ),
    );
  }

  Widget? _buildStatus() {
    if (!_authenticated) {
      return AppEmptyView(
        message: widget.authState.sessionExpired ? '登录状态已失效，请重新登录' : '登录后查看收藏',
        actionLabel: widget.authState.sessionExpired ? '重新登录' : '登录',
        onRefresh: widget.onLogin,
      );
    }
    if (_loading) {
      return const AppLoadingView(message: '正在同步收藏');
    }
    if (_error != null && !_usingCache && _works.isEmpty) {
      return AppErrorView(message: _error.toString(), onRetry: _load);
    }
    return null;
  }

  LibraryKind? get _requestedKind {
    if (_activeTab == 0) {
      return LibraryKind.comic;
    }
    if (_activeTab == 1) {
      return LibraryKind.novel;
    }
    return switch (_rawFilter) {
      1 => LibraryKind.comic,
      2 => LibraryKind.novel,
      _ => null,
    };
  }

  List<FavoriteWork> _worksForTab(int index) {
    final LibraryKind? kind = index == 0
        ? LibraryKind.comic
        : index == 1
        ? LibraryKind.novel
        : switch (_rawFilter) {
            1 => LibraryKind.comic,
            2 => LibraryKind.novel,
            _ => null,
          };
    final List<FavoriteWork> works = index == 2 ? _rawWorks : _works;
    return kind == null
        ? works
        : works.where((FavoriteWork item) => item.work.kind == kind).toList();
  }

  bool _hasRequestedEntries(List<CloudFavoriteEntry> entries) {
    final LibraryKind? kind = _requestedKind;
    return entries.any(
      (CloudFavoriteEntry item) =>
          kind == null || item.sourceThread.board.kind == kind,
    );
  }

  void _openWork(Work work, {required bool raw}) {
    final OpenFavoriteWork? callback = widget.onOpenWork;
    if (callback != null) {
      callback(work, raw: raw);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            WorkDetailPage(work: work, resolveOnOpen: !raw, rawSourceMode: raw),
      ),
    );
  }

  Future<void> _load() async {
    if (!_authenticated) {
      widget.onLogin();
      return;
    }
    final int generation = ++_generation;
    _initialLoadStarted = true;
    setState(() {
      _loading = true;
      _paginationFailed = false;
      _loadingMore = false;
      _error = null;
      _cursor = null;
      _entries.clear();
      _works = <FavoriteWork>[];
      _busyWorkIds.clear();
      _usingCache = false;
      _cacheUpdatedAt = null;
    });
    try {
      final ForumFavoriteRepository repository = ref.read(
        forumFavoriteRepositoryProvider,
      );
      CloudFavoritePage page = await repository.loadInitial();
      final List<CloudFavoriteEntry> entries = <CloudFavoriteEntry>[
        ...page.entries,
      ];
      while (!_hasRequestedEntries(entries) &&
          page.hasMore &&
          _isCurrent(generation)) {
        page = await repository.loadNext(page);
        entries.addAll(page.entries);
      }
      if (!mounted || !_isCurrent(generation)) {
        return;
      }
      final List<FavoriteWork> works = repository.aggregateEntries(
        <CloudFavoriteEntry>[..._entries, ...entries],
      );
      await _saveCache(works);
      if (!mounted || !_isCurrent(generation)) {
        return;
      }
      setState(() {
        _cursor = page;
        _entries.addAll(entries);
        _works = works;
        _loading = false;
        _error = null;
        _usingCache = false;
        _cacheUpdatedAt = null;
      });
    } on Object catch (error) {
      if (!mounted || !_isCurrent(generation)) {
        return;
      }
      final FavoriteCacheSnapshot? cached = await _loadCache();
      if (!mounted || !_isCurrent(generation)) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error;
        _works = cached?.works ?? <FavoriteWork>[];
        _usingCache = cached != null;
        _cacheUpdatedAt = cached?.updatedAt;
      });
    }
  }

  Future<void> _loadMore() async {
    final int generation = _generation;
    final CloudFavoritePage? cursor = _cursor;
    if (_loading ||
        _loadingMore ||
        _usingCache ||
        cursor == null ||
        !cursor.hasMore) {
      return;
    }
    setState(() {
      _loadingMore = true;
    });
    try {
      final ForumFavoriteRepository repository = ref.read(
        forumFavoriteRepositoryProvider,
      );
      CloudFavoritePage page = await repository.loadNext(cursor);
      final List<CloudFavoriteEntry> entries = <CloudFavoriteEntry>[
        ...page.entries,
      ];
      while (!_hasRequestedEntries(entries) &&
          page.hasMore &&
          _isCurrent(generation)) {
        page = await repository.loadNext(page);
        entries.addAll(page.entries);
      }
      if (!mounted || !_isCurrent(generation)) {
        return;
      }
      final Set<int> knownFavoriteIds = _entries
          .map((CloudFavoriteEntry value) => value.record.favoriteId)
          .toSet();
      setState(() {
        _cursor = page;
        _entries.addAll(
          entries.where(
            (CloudFavoriteEntry value) =>
                knownFavoriteIds.add(value.record.favoriteId),
          ),
        );
        _works = repository.aggregateEntries(_entries);
        _loadingMore = false;
      });
      await _saveCache(_works);
    } on Object catch (error) {
      if (!mounted || !_isCurrent(generation)) {
        return;
      }
      setState(() {
        _loadingMore = false;
        _paginationFailed = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(AppSnackBar(content: Text('加载下一页失败：$error')));
    }
  }

  Future<void> _remove(FavoriteWork item) async {
    final int generation = _generation;
    if (_usingCache || !_authenticated) {
      return;
    }
    final bool confirmed =
        await showDialog<bool>(
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
    if (!confirmed || !mounted || !_isCurrent(generation)) {
      return;
    }
    setState(() {
      _busyWorkIds.add(item.work.id);
    });
    try {
      await ref
          .read(forumFavoriteRepositoryProvider)
          .removeWork(item.work, item.records);
      if (!mounted || !_isCurrent(generation)) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const AppSnackBar(content: Text('已取消云端收藏')));
      await _load();
    } on Object catch (error) {
      if (!mounted || !_isCurrent(generation)) {
        return;
      }
      setState(() {
        _busyWorkIds.remove(item.work.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(AppSnackBar(content: Text('取消收藏失败：$error')));
    }
  }

  Future<void> _saveCache(List<FavoriteWork> works) async {
    try {
      await ref.read(favoriteCacheRepositoryProvider).save(works);
    } on Object {
      return;
    }
  }

  Future<FavoriteCacheSnapshot?> _loadCache() async {
    try {
      return await ref.read(favoriteCacheRepositoryProvider).load();
    } on Object {
      return null;
    }
  }

  List<FavoriteWork> get _rawWorks {
    if (!_usingCache) {
      return _entries.map(_rawFavoriteFromEntry).toList(growable: false);
    }
    final List<FavoriteWork> values = <FavoriteWork>[];
    for (final FavoriteWork favorite in _works) {
      final Map<int, SourceThread> threads = <int, SourceThread>{
        for (final SourceThread thread in favorite.work.sourceThreads)
          thread.tid: thread,
      };
      for (final CloudFavoriteRecord record in favorite.records) {
        final SourceThread? thread = threads[record.threadId];
        if (thread != null) {
          values.add(_rawFavorite(record, thread));
        }
      }
    }
    return values;
  }

  FavoriteWork _rawFavoriteFromEntry(CloudFavoriteEntry entry) {
    return _rawFavorite(entry.record, entry.sourceThread);
  }

  FavoriteWork _rawFavorite(CloudFavoriteRecord record, SourceThread thread) {
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
}

class _FavoritesTabView extends StatefulWidget {
  const _FavoritesTabView({
    required this.index,
    required this.title,
    required this.active,
    required this.grid,
    required this.onToggleView,
    required this.works,
    required this.status,
    required this.loadingMore,
    required this.hasMore,
    required this.usingCache,
    required this.cacheUpdatedAt,
    required this.busyWorkIds,
    required this.rawFilter,
    required this.onRawFilterChanged,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onRemove,
    required this.onOpenWork,
    super.key,
  });

  final int index;
  final String title;
  final bool active;
  final bool grid;
  final VoidCallback onToggleView;
  final List<FavoriteWork> works;
  final Widget? status;
  final bool loadingMore;
  final bool hasMore;
  final bool usingCache;
  final DateTime? cacheUpdatedAt;
  final Set<String> busyWorkIds;
  final int rawFilter;
  final ValueChanged<int> onRawFilterChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final ValueChanged<FavoriteWork> onRemove;
  final ValueChanged<Work> onOpenWork;

  @override
  State<_FavoritesTabView> createState() => _FavoritesTabViewState();
}

class _FavoritesTabViewState extends State<_FavoritesTabView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant _FavoritesTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grid != widget.grid) {
      _gridChanging = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _gridChanging = false;
          });
        }
      });
    }
    if (oldWidget.rawFilter != widget.rawFilter &&
        widget.index == 2 &&
        _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (widget.active &&
        widget.hasMore &&
        !_gridChanging &&
        _scrollController.position.extentAfter < 500) {
      unawaited(widget.onLoadMore());
    }
  }

  bool _gridChanging = false;

  void _fillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.active ||
          widget.status != null ||
          !widget.hasMore ||
          widget.loadingMore ||
          _gridChanging) {
        return;
      }
      if (!_scrollController.hasClients ||
          _scrollController.position.maxScrollExtent == 0) {
        unawaited(widget.onLoadMore());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _fillViewport();
    return Column(
      children: <Widget>[
        if (widget.index == 2)
          CatalogControlBar(
            children: <Widget>[
              CatalogControlSelector<int>(
                key: const Key('favorite-kind-filter'),
                label: const <String>['全部', '漫画', '小说'][widget.rawFilter],
                selected: widget.rawFilter,
                choices: const <(int, String)>[(0, '全部'), (1, '漫画'), (2, '小说')],
                onSelected: widget.onRawFilterChanged,
              ),
              CatalogControlAction(
                key: const ValueKey<String>('favorite-view-toggle-2'),
                tooltip: widget.grid ? '切换为列表' : '切换为网格',
                onTap: widget.onToggleView,
                child: Text(widget.grid ? '网格' : '列表'),
              ),
              CatalogControlAction(
                tooltip: '刷新收藏',
                onTap: () => unawaited(widget.onRefresh()),
                child: const Text('刷新'),
              ),
            ],
          ),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    final Widget? status = widget.status;
    if (status != null) {
      return status;
    }
    final Widget content;
    if (widget.works.isEmpty) {
      content = widget.hasMore
          ? const AppLoadingView(message: '正在读取后续收藏')
          : RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: <Widget>[
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: AppEmptyView(
                      message: widget.index == 2
                          ? '暂无符合筛选条件的原始收藏'
                          : '暂无${widget.title}收藏，可在原始收藏中查看逐帖记录',
                      onRefresh: () => unawaited(widget.onRefresh()),
                    ),
                  ),
                ],
              ),
            );
    } else {
      content = RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: widget.grid ? _buildGrid() : _buildList(),
      );
    }
    if (!widget.usingCache) {
      return content;
    }
    final DateTime? updatedAt = widget.cacheUpdatedAt;
    final String time = updatedAt == null
        ? ''
        : ' · ${DateFormat('MM-dd HH:mm').format(updatedAt)}';
    return Column(
      children: <Widget>[
        Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.cloud_off_outlined),
            title: Text('当前显示只读收藏缓存$time'),
            trailing: TextButton(
              onPressed: () => unawaited(widget.onRefresh()),
              child: const Text('重试'),
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _favoriteAction(FavoriteWork item) {
    if (widget.usingCache) {
      return const Tooltip(
        message: '离线缓存不可修改',
        child: Icon(Icons.cloud_off_outlined),
      );
    }
    if (widget.busyWorkIds.contains(item.work.id)) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return IconButton(
      tooltip: '取消收藏',
      onPressed: () => widget.onRemove(item),
      icon: const Icon(Icons.favorite),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      key: PageStorageKey<String>('favorites-list-${widget.index}'),
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: widget.works.length + (widget.loadingMore ? 1 : 0),
      separatorBuilder: (BuildContext context, int index) => Divider(
        height: 1,
        indent: 12,
        endIndent: 12,
        color: Colors.grey.withValues(alpha: 0.2),
      ),
      itemBuilder: (BuildContext context, int index) {
        if (index == widget.works.length) {
          return _loadingIndicator();
        }
        final FavoriteWork item = widget.works[index];
        return WorkListTile(
          work: item.work,
          onTap: () => widget.onOpenWork(item.work),
          trailing: _favoriteAction(item),
        );
      },
    );
  }

  Widget _loadingIndicator() => const Padding(
    padding: EdgeInsets.all(20),
    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth < 600
            ? 3
            : constraints.maxWidth < 900
            ? 4
            : 5;
        return CustomScrollView(
          key: PageStorageKey<String>('favorites-grid-${widget.index}'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate((
                  BuildContext context,
                  int index,
                ) {
                  final FavoriteWork item = widget.works[index];
                  return Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: WorkGridCard(
                          work: item.work,
                          onTap: () => widget.onOpenWork(item.work),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          shape: const CircleBorder(),
                          child: _favoriteAction(item),
                        ),
                      ),
                    ],
                  );
                }, childCount: widget.works.length),
              ),
            ),
            if (widget.loadingMore)
              SliverToBoxAdapter(child: _loadingIndicator()),
          ],
        );
      },
    );
  }
}
