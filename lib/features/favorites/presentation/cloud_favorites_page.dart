import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:x300/shared/presentation/tab_app_bar.dart';
import 'package:x300/shared/presentation/catalog_controls.dart';

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
  static const List<String> _titles = <String>['漫画收藏', '小说收藏'];
  late final TabController _tabController;
  final List<CloudFavoriteEntry> _entries = <CloudFavoriteEntry>[];
  final Set<String> _busyWorkIds = <String>{};
  List<ForumCategory> _categories = <ForumCategory>[];

  List<FavoriteWork> _works = <FavoriteWork>[];
  Object? _error;
  bool _loading = false;
  bool _usingCache = false;
  bool _initialLoadStarted = false;
  DateTime? _cacheUpdatedAt;
  int _activeTab = 0;
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
      _error = null;
      _usingCache = false;
      _cacheUpdatedAt = null;
      _busyWorkIds.clear();
      _loading = false;
      _categories = <ForumCategory>[];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TabAppBar(
        controller: _tabController,
        tabs: _titles.map((String title) => Tab(text: title)).toList(),
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
              works: _worksForTab(index),
              rawWorks: _rawWorks
                  .where(
                    (item) =>
                        item.work.kind ==
                        (index == 0 ? LibraryKind.comic : LibraryKind.novel),
                  )
                  .toList(),
              categories: _categories
                  .where(
                    (category) =>
                        category.board.kind ==
                        (index == 0 ? LibraryKind.comic : LibraryKind.novel),
                  )
                  .toList(),
              status: _buildStatus(),
              usingCache: _usingCache,
              cacheUpdatedAt: _cacheUpdatedAt,
              busyWorkIds: _busyWorkIds,
              onRefresh: _load,
              onRemove: _remove,
              onOpenWork: _openWork,
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

  List<FavoriteWork> _worksForTab(int index) {
    final LibraryKind kind = index == 0 ? LibraryKind.comic : LibraryKind.novel;
    return _works.where((FavoriteWork item) => item.work.kind == kind).toList();
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
      _error = null;
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
      List<ForumCategory> categories = _categories;
      try {
        categories = await repository.loadCategories();
      } on Object {
        // Cached source metadata still provides category choices offline.
      }
      if (!_isCurrent(generation)) {
        return;
      }
      CloudFavoritePage page = await repository.loadInitial();
      final List<CloudFavoriteEntry> entries = <CloudFavoriteEntry>[
        ...page.entries,
      ];
      final Set<Uri> visited = <Uri>{};
      while (page.hasMore && _isCurrent(generation)) {
        if (!visited.add(page.nextPageUri!)) {
          throw StateError('收藏分页重复，请重试');
        }
        page = await repository.loadNext(page);
        entries.addAll(page.entries);
      }
      if (!mounted || !_isCurrent(generation)) {
        return;
      }
      final Set<int> seenIds = <int>{};
      final List<FavoriteWork> works = repository.aggregateEntries(
        entries.where((entry) => seenIds.add(entry.record.favoriteId)).toList(),
      );
      await _saveCache(works);
      if (!mounted || !_isCurrent(generation)) {
        return;
      }
      setState(() {
        _categories = categories;
        final Set<int> seen = <int>{};
        _entries.addAll(
          entries.where((entry) => seen.add(entry.record.favoriteId)),
        );
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
    required this.works,
    required this.rawWorks,
    required this.categories,
    required this.status,
    required this.usingCache,
    required this.cacheUpdatedAt,
    required this.busyWorkIds,
    required this.onRefresh,
    required this.onRemove,
    required this.onOpenWork,
    super.key,
  });

  final int index;
  final String title;
  final bool active;
  final List<FavoriteWork> works;
  final List<FavoriteWork> rawWorks;
  final List<ForumCategory> categories;
  final Widget? status;
  final bool usingCache;
  final DateTime? cacheUpdatedAt;
  final Set<String> busyWorkIds;
  final Future<void> Function() onRefresh;
  final ValueChanged<FavoriteWork> onRemove;
  final OpenFavoriteWork onOpenWork;

  @override
  State<_FavoritesTabView> createState() => _FavoritesTabViewState();
}

class _FavoritesTabViewState extends State<_FavoritesTabView>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();
  bool _grid = false;
  bool _raw = false;
  bool _gridChanging = false;
  String _category = '';
  int _startPage = 1;
  int _lastLoadedPage = 1;
  int _reset = 0;

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
    if (widget.status == null) {
      if (_category.isNotEmpty &&
          !_categoryChoices.any((c) => c.$1 == _category)) {
        _category = '';
        _startPage = 1;
        _lastLoadedPage = 1;
        _reset++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToTop();
        });
      }
      final int total = _totalPages;
      if (_startPage > total) {
        _startPage = total;
        _lastLoadedPage = total;
        _reset++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToTop();
        });
      } else if (_lastLoadedPage > total) {
        _lastLoadedPage = total;
      }
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  String _categoryKey(SourceThread thread) {
    if (thread.typeId != null && thread.typeId != 0) {
      return '${thread.board.fid}:${thread.typeId}';
    }
    return thread.typeName.isEmpty
        ? ''
        : '${thread.board.fid}:${thread.typeName}';
  }

  List<(String, String)> get _categoryChoices {
    final Map<String, String> choices = <String, String>{};
    for (final ForumCategory category in widget.categories) {
      choices['${category.board.fid}:${category.typeId}'] = category.name;
    }
    for (final FavoriteWork item in widget.rawWorks) {
      for (final SourceThread thread in item.work.sourceThreads) {
        final String key = _categoryKey(thread);
        if (key.isNotEmpty && thread.typeName.isNotEmpty) {
          choices.putIfAbsent(key, () => thread.typeName);
        }
      }
    }
    // Category IDs are scoped to a forum board, including the two novel boards.
    return choices.entries.map((entry) {
      String name = entry.value;
      if (choices.values.where((value) => value == name).length > 1) {
        final int fid = int.parse(entry.key.split(':').first);
        name = '$name（${ForumBoard.fromFid(fid)!.label}）';
      }
      return (entry.key, name);
    }).toList();
  }

  List<FavoriteWork> get _filteredWorks {
    final List<FavoriteWork> works = _raw ? widget.rawWorks : widget.works;
    if (_category.isEmpty) {
      return works;
    }
    return works
        .where(
          (item) => item.work.sourceThreads.any(
            (thread) => _categoryKey(thread) == _category,
          ),
        )
        .toList();
  }

  int get _totalPages {
    final int pages = (_filteredWorks.length / _pageSize).ceil();
    return pages < 1 ? 1 : pages;
  }

  List<FavoriteWork> get _visibleWorks => _filteredWorks
      .skip((_startPage - 1) * _pageSize)
      .take((_lastLoadedPage - _startPage + 1) * _pageSize)
      .toList();

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _resetPages() {
    _startPage = 1;
    _lastLoadedPage = 1;
    _reset++;
    _scrollToTop();
  }

  void _handleScroll() {
    if (widget.active &&
        !_gridChanging &&
        widget.status == null &&
        _lastLoadedPage < _totalPages &&
        _scrollController.position.extentAfter < 500) {
      setState(() => _lastLoadedPage++);
    }
  }

  void _fillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.active ||
          widget.status != null ||
          _gridChanging ||
          _lastLoadedPage >= _totalPages) {
        return;
      }
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent == 0) {
        setState(() => _lastLoadedPage++);
      }
    });
  }

  Future<void> _refresh() async {
    setState(_resetPages);
    await widget.onRefresh();
  }

  void _toggleGrid() {
    setState(() {
      _grid = !_grid;
      _gridChanging = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _gridChanging = false);
      }
    });
  }

  Future<void> _jumpToPage() async {
    if (widget.status != null) {
      return;
    }
    int? targetPage = _startPage;
    final int total = _totalPages;
    final String loadedPages = _startPage == _lastLoadedPage
        ? '已加载第 $_startPage 页 / 共 $total 页'
        : '已加载第 $_startPage–$_lastLoadedPage 页 / 共 $total 页';
    final int? selected = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final bool valid =
              targetPage != null && targetPage! >= 1 && targetPage! <= total;
          return AlertDialog(
            title: const Text('跳转页面'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(loadedPages),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: _startPage.toString(),
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(labelText: '跳转页码（1–$total）'),
                  onChanged: (String value) => setDialogState(() {
                    targetPage = int.tryParse(value);
                  }),
                  onFieldSubmitted: (String value) {
                    final int? page = int.tryParse(value);
                    if (page != null && page >= 1 && page <= total) {
                      Navigator.pop(context, page);
                    }
                  },
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.pop(context, targetPage)
                    : null,
                child: const Text('跳转'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || selected == null || selected == _startPage) {
      return;
    }
    setState(() {
      _scrollToTop();
      _startPage = selected;
      _lastLoadedPage = selected;
      _reset++;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _fillViewport();
    final List<(String, String)> choices = _categoryChoices;
    final String categoryLabel =
        choices.where((c) => c.$1 == _category).map((c) => c.$2).firstOrNull ??
        '全部';
    return Column(
      children: <Widget>[
        CatalogControlBar(
          key: ValueKey<String>('favorite-controls-${widget.index}'),
          children: <Widget>[
            CatalogControlSelector<String>(
              key: ValueKey<String>('favorite-category-filter-${widget.index}'),
              label: categoryLabel,
              selected: _category,
              choices: <(String, String)>[('', '全部'), ...choices],
              onSelected: (String value) {
                if (value == _category) return;
                setState(() {
                  _category = value;
                  _resetPages();
                });
              },
            ),
            CatalogControlAction(
              key: ValueKey<String>('favorite-page-jump-${widget.index}'),
              tooltip: '跳页',
              onTap: () => unawaited(_jumpToPage()),
              child: const Text('跳页'),
            ),
            CatalogControlAction(
              key: ValueKey<String>('favorite-view-toggle-${widget.index}'),
              tooltip: _grid ? '切换为列表' : '切换为网格',
              onTap: _toggleGrid,
              child: Text(_grid ? '网格' : '列表'),
            ),
            CatalogControlAction(
              key: ValueKey<String>('favorite-mode-toggle-${widget.index}'),
              tooltip: _raw ? '切换为聚合' : '切换为原帖',
              onTap: () => setState(() {
                _raw = !_raw;
                _resetPages();
              }),
              child: Text(_raw ? '原帖' : '聚合'),
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
    final List<FavoriteWork> works = _visibleWorks;
    final Widget content;
    if (works.isEmpty) {
      content = RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyView(
                message: _category.isNotEmpty
                    ? '当前筛选没有收藏'
                    : '暂无${widget.title}',
                onRefresh: () => unawaited(_refresh()),
              ),
            ),
          ],
        ),
      );
    } else {
      content = RefreshIndicator(
        onRefresh: _refresh,
        child: _grid ? _buildGrid(works) : _buildList(works),
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
              onPressed: () => unawaited(_refresh()),
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

  PageStorageKey<String> _scrollKey(String layout) => PageStorageKey<String>(
    'favorites-$layout-${widget.index}-$_raw-$_category-$_reset',
  );

  Widget _buildList(List<FavoriteWork> works) {
    return ListView.separated(
      key: _scrollKey('list'),
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: works.length,
      separatorBuilder: (BuildContext context, int index) => Divider(
        height: 1,
        indent: 12,
        endIndent: 12,
        color: Colors.grey.withValues(alpha: 0.2),
      ),
      itemBuilder: (BuildContext context, int index) {
        final FavoriteWork item = works[index];
        return WorkListTile(
          work: item.work,
          onTap: () => widget.onOpenWork(item.work, raw: _raw),
          trailing: _favoriteAction(item),
        );
      },
    );
  }

  Widget _buildGrid(List<FavoriteWork> works) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth < 600
            ? 3
            : constraints.maxWidth < 900
            ? 4
            : 5;
        return CustomScrollView(
          key: _scrollKey('grid'),
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
                delegate: SliverChildBuilderDelegate((context, index) {
                  final FavoriteWork item = works[index];
                  return WorkGridCard(
                    work: item.work,
                    onTap: () => widget.onOpenWork(item.work, raw: _raw),
                  );
                }, childCount: works.length),
              ),
            ),
          ],
        );
      },
    );
  }
}
