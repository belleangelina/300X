import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';
import 'package:x300/shared/presentation/app_snack_bar.dart';
import 'package:x300/shared/presentation/tab_app_bar.dart';

class LibraryHomeController
{
    Future<void> Function()? _refreshHandler;

    Future<void> scrollToTopAndRefresh()
    {
        return _refreshHandler?.call() ?? Future<void>.value();
    }

    void attach(Future<void> Function() handler)
    {
        _refreshHandler = handler;
    }

    void detach(Future<void> Function() handler)
    {
        if (identical(_refreshHandler, handler))
        {
            _refreshHandler = null;
        }
    }
}

class LibraryHomePage extends ConsumerStatefulWidget
{
    const LibraryHomePage({
        required this.kind,
        required this.onOpenWork,
        this.controller,
        this.onSearch,
        super.key,
    });

    final LibraryKind kind;
    final ValueChanged<Work> onOpenWork;
    final LibraryHomeController? controller;
    final VoidCallback? onSearch;

    @override
    ConsumerState<LibraryHomePage> createState()
    {
        return _LibraryHomePageState();
    }
}

class _LibraryHomePageState extends ConsumerState<LibraryHomePage>
    with SingleTickerProviderStateMixin
{
    late final List<_CatalogFeedDefinition> _feeds;
    late final List<GlobalKey<_CatalogFeedViewState>> _feedKeys;
    late final List<_CatalogViewMode> _viewModes;
    late final TabController _tabController;
    late final Future<void> Function() _refreshHandler;
    int _activeFeedIndex = 0;

    @override
    void initState()
    {
        super.initState();
        _feeds = widget.kind == LibraryKind.comic
                ? const <_CatalogFeedDefinition>[
                        _CatalogFeedDefinition(
                            title: '漫画区',
                            kind: LibraryKind.comic,
                            novelSource: NovelSourceFilter.all,
                        ),
                    ]
                : const <_CatalogFeedDefinition>[
                        _CatalogFeedDefinition(
                            title: '轻小说',
                            kind: LibraryKind.novel,
                            novelSource: NovelSourceFilter.lightNovel,
                        ),
                        _CatalogFeedDefinition(
                            title: '文学区',
                            kind: LibraryKind.novel,
                            novelSource: NovelSourceFilter.literature,
                        ),
                    ];
        _feedKeys = List<GlobalKey<_CatalogFeedViewState>>.generate(
            _feeds.length,
            (int index) => GlobalKey<_CatalogFeedViewState>(),
            growable: false,
        );
        final AppSettingsRepository settings = ref.read(
            appSettingsRepositoryProvider,
        );
        _viewModes = _feeds.map((_CatalogFeedDefinition feed)
        {
            return settings.catalogUsesGrid(_viewPreferenceScope(feed))
                    ? _CatalogViewMode.grid
                    : _CatalogViewMode.list;
        }).toList(growable: false);
        _tabController = TabController(length: _feeds.length, vsync: this);
        _tabController.addListener(_handleFeedChanged);
        _refreshHandler = _scrollToTopAndRefresh;
        widget.controller?.attach(_refreshHandler);
    }

    @override
    void didUpdateWidget(covariant LibraryHomePage oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        if (oldWidget.controller != widget.controller)
        {
            oldWidget.controller?.detach(_refreshHandler);
            widget.controller?.attach(_refreshHandler);
        }
    }

    @override
    void dispose()
    {
        widget.controller?.detach(_refreshHandler);
        _tabController.removeListener(_handleFeedChanged);
        _tabController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            appBar: TabAppBar(
                controller: _tabController,
                tabs: _feeds
                        .map((_CatalogFeedDefinition value) => Tab(text: value.title))
                        .toList(growable: false),
                action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                        IconButton(
                            key: const ValueKey<String>('catalog-search'),
                            onPressed: widget.onSearch,
                            icon: const Icon(Icons.search),
                        ),
                    ],
                ),
            ),
            body: TabBarView(
                controller: _tabController,
                children: List<Widget>.generate(_feeds.length, (int index)
                {
                    final _CatalogFeedDefinition feed = _feeds[index];
                    return TickerMode(
                        enabled: index == _activeFeedIndex,
                        child: _CatalogFeedView(
                            key: _feedKeys[index],
                            kind: feed.kind,
                            novelSource: feed.novelSource,
                            viewMode: _viewModes[index],
                            onViewModeChanged: (_CatalogViewMode value) =>
                                    _setViewMode(index, value),
                            onOpenWork: widget.onOpenWork,
                        ),
                    );
                }, growable: false),
            ),
        );
    }

    Future<void> _scrollToTopAndRefresh()
    {
        return _feedKeys[_tabController.index].currentState
                        ?.scrollToTopAndRefresh() ??
                Future<void>.value();
    }

    void _handleFeedChanged()
    {
        if (_activeFeedIndex == _tabController.index)
        {
            return;
        }
        setState(()
        {
            _activeFeedIndex = _tabController.index;
        });
    }

    void _setViewMode(int index, _CatalogViewMode value)
    {
        if (_viewModes[index] == value)
        {
            return;
        }
        setState(()
        {
            _viewModes[index] = value;
        });
        unawaited(
            ref.read(appSettingsRepositoryProvider).saveCatalogUsesGrid(
                _viewPreferenceScope(_feeds[index]),
                value == _CatalogViewMode.grid,
            ),
        );
    }

    String _viewPreferenceScope(_CatalogFeedDefinition feed)
    {
        return '${feed.kind.name}_${feed.novelSource.name}';
    }
}

class _CatalogFeedDefinition
{
    const _CatalogFeedDefinition({
        required this.title,
        required this.kind,
        required this.novelSource,
    });

    final String title;
    final LibraryKind kind;
    final NovelSourceFilter novelSource;
}

enum _CatalogViewMode
{
    list,
    grid,
}

class _CatalogFeedView extends ConsumerStatefulWidget
{
    const _CatalogFeedView({
        required this.kind,
        required this.novelSource,
        required this.viewMode,
        required this.onViewModeChanged,
        required this.onOpenWork,
        super.key,
    });

    final LibraryKind kind;
    final NovelSourceFilter novelSource;
    final _CatalogViewMode viewMode;
    final ValueChanged<_CatalogViewMode> onViewModeChanged;
    final ValueChanged<Work> onOpenWork;

    @override
    ConsumerState<_CatalogFeedView> createState()
    {
        return _CatalogFeedViewState();
    }
}

class _CatalogFeedViewState extends ConsumerState<_CatalogFeedView>
    with AutomaticKeepAliveClientMixin
{
    final ScrollController _scrollController = ScrollController();
    final List<SourceThread> _sourceThreads = <SourceThread>[];
    final List<ForumCategory> _categories = <ForumCategory>[];
    List<Work> _works = <Work>[];
    WorkCatalogPage? _cursor;
    Object? _error;
    bool _loading = true;
    bool _loadingMore = false;
    int _generation = 0;
    int? _categoryTypeId;
    CatalogSection _sort = CatalogSection.updated;
    int _startPage = 1;
    int _lastLoadedPage = 1;
    int _totalPages = 1;

    @override
    bool get wantKeepAlive => true;

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
    void didUpdateWidget(covariant _CatalogFeedView oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        if (oldWidget.viewMode != widget.viewMode &&
            widget.viewMode == _CatalogViewMode.grid)
        {
            _scheduleGridFill();
        }
    }

    @override
    Widget build(BuildContext context)
    {
        super.build(context);
        return Column(
            children: <Widget>[
                _CatalogControls(
                    viewMode: widget.viewMode,
                    categories: _categories,
                    categoryTypeId: _categoryTypeId,
                    sort: _sort,
                    pageLabel: _pageLabel,
                    onViewModeChanged: widget.onViewModeChanged,
                    onPageTap: _jumpToPage,
                    onCategoryChanged: _setCategory,
                    onSortChanged: _setSort,
                ),
                Expanded(child: _buildContent()),
            ],
        );
    }

    Widget _buildContent()
    {
        if (_loading)
        {
            return const AppLoadingView(message: '正在读取论坛目录');
        }
        if (_error != null && _works.isEmpty)
        {
            return AppErrorView(
                message: _error.toString(),
                onRetry: () => _load(reset: true),
            );
        }
        if (_works.isEmpty)
        {
            return AppEmptyView(
                message: '当前筛选没有可阅读主题',
                onRefresh: _refreshFirstPage,
            );
        }
        return RefreshIndicator(
            onRefresh: _refreshFirstPage,
            child: widget.viewMode == _CatalogViewMode.list
                    ? _buildList()
                    : _buildGrid(),
        );
    }

    Widget _buildList()
    {
        return ListView.separated(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _works.length + (_loadingMore ? 1 : 0),
            separatorBuilder: (BuildContext context, int index) => Divider(
                height: 1,
                indent: 12,
                endIndent: 12,
                color: Colors.grey.withValues(alpha: 0.2),
            ),
            itemBuilder: (BuildContext context, int index)
            {
                if (index >= _works.length)
                {
                    return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    );
                }
                final Work work = _works[index];
                return WorkListTile(
                    work: work,
                    rank: _sort == CatalogSection.ranking ? index + 1 : null,
                    onTap: () => widget.onOpenWork(work),
                );
            },
        );
    }

    Widget _buildGrid()
    {
        return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints)
            {
                final int columns = constraints.maxWidth < 600
                        ? 3
                        : constraints.maxWidth < 900
                        ? 4
                        : 5;
                return CustomScrollView(
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
                                delegate: SliverChildBuilderDelegate(
                                    (BuildContext context, int index)
                                    {
                                        final Work work = _works[index];
                                        return WorkGridCard(
                                            work: work,
                                            onTap: () => widget.onOpenWork(work),
                                        );
                                    },
                                    childCount: _works.length,
                                ),
                            ),
                        ),
                        if (_loadingMore)
                            const SliverToBoxAdapter(
                                child: Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Center(
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                        ),
                                    ),
                                ),
                            ),
                    ],
                );
            },
        );
    }

    Future<void> scrollToTopAndRefresh() async
    {
        if (_scrollController.hasClients && _scrollController.offset > 0)
        {
            await _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
            );
        }
        await _load(reset: true);
    }

    Future<void> _refreshFirstPage() async
    {
        if (_scrollController.hasClients)
        {
            _scrollController.jumpTo(0);
        }
        setState(()
        {
            _startPage = 1;
            _lastLoadedPage = 1;
        });
        await _load(reset: true);
    }

    Future<void> _setCategory(int? typeId) async
    {
        if (typeId == _categoryTypeId)
        {
            return;
        }
        setState(()
        {
            _categoryTypeId = typeId;
        });
        await _resetFromControls();
    }

    Future<void> _setSort(CatalogSection value) async
    {
        if (value == _sort)
        {
            return;
        }
        setState(()
        {
            _sort = value;
        });
        await _resetFromControls();
    }

    Future<void> _resetFromControls() async
    {
        if (_scrollController.hasClients)
        {
            _scrollController.jumpTo(0);
        }
        setState(()
        {
            _startPage = 1;
            _lastLoadedPage = 1;
            _totalPages = 1;
        });
        await _load(reset: true);
    }

    Future<void> _load({required bool reset}) async
    {
        final int generation = reset ? ++_generation : _generation;
        if (reset)
        {
            setState(()
            {
                _loading = true;
                _loadingMore = false;
                _error = null;
                _cursor = null;
                _works = <Work>[];
                _sourceThreads.clear();
            });
        }
        try
        {
            final ForumLibraryRepository repository = ref.read(
                forumLibraryRepositoryProvider,
            );
            final WorkCatalogPage page = await repository.loadCatalog(
                kind: widget.kind,
                section: _sort,
                novelSource: widget.novelSource,
                page: _startPage,
                typeId: _categoryTypeId,
            );
            if (!mounted || generation != _generation)
            {
                return;
            }
            setState(()
            {
                _cursor = page;
                _sourceThreads.addAll(page.sourceThreads);
                _mergeCategories(page.categories);
                _works = page.works;
                _updatePageRange(page, reset: true);
                _loading = false;
                _error = null;
            });
            _scheduleGridFill();
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
                _error = error;
            });
        }
    }

    Future<void> _loadMore() async
    {
        final WorkCatalogPage? cursor = _cursor;
        if (_loadingMore || cursor == null || !cursor.hasMore)
        {
            return;
        }
        final int generation = _generation;
        setState(()
        {
            _loadingMore = true;
        });
        try
        {
            final ForumLibraryRepository repository = ref.read(
                forumLibraryRepositoryProvider,
            );
            final WorkCatalogPage page = await repository.loadNextCatalog(
                cursor: cursor,
                section: _sort,
            );
            if (!mounted || generation != _generation)
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
                _mergeCategories(page.categories);
                _works = repository.aggregateThreads(_sourceThreads);
                _updatePageRange(page, reset: false);
                _loadingMore = false;
            });
            _scheduleGridFill();
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
                _error = error;
            });
            ScaffoldMessenger.of(
                context,
            ).showSnackBar(AppSnackBar(content: Text('加载下一页失败：$error')));
        }
    }

    void _mergeCategories(Iterable<ForumCategory> categories)
    {
        final Set<int> known = _categories
                .map((ForumCategory value) => value.typeId)
                .toSet();
        _categories.addAll(
            categories.where((ForumCategory value) => known.add(value.typeId)),
        );
    }

    void _handleScroll()
    {
        if (_scrollController.position.extentAfter < 500)
        {
            _loadMore();
        }
    }

    String get _pageLabel
    {
        if (_startPage == _lastLoadedPage)
        {
            return '$_startPage页';
        }
        return '$_startPage+${_lastLoadedPage - _startPage}页';
    }

    void _scheduleGridFill()
    {
        WidgetsBinding.instance.addPostFrameCallback((_)
        {
            if (!mounted ||
                widget.viewMode != _CatalogViewMode.grid ||
                !_scrollController.hasClients ||
                _scrollController.position.maxScrollExtent > 0)
            {
                return;
            }
            unawaited(_loadMore());
        });
    }

    void _updatePageRange(WorkCatalogPage page, {required bool reset})
    {
        if (page.pages.isEmpty)
        {
            return;
        }
        int currentPage = page.pages.values.first.currentPage;
        int totalPages = page.pages.values.first.totalPages;
        for (final ForumCatalogPage value in page.pages.values.skip(1))
        {
            if (value.currentPage > currentPage)
            {
                currentPage = value.currentPage;
            }
            if (value.totalPages > totalPages)
            {
                totalPages = value.totalPages;
            }
        }
        if (reset)
        {
            _startPage = currentPage;
            _lastLoadedPage = currentPage;
        }
        else if (currentPage > _lastLoadedPage)
        {
            _lastLoadedPage = currentPage;
        }
        _totalPages = totalPages;
    }

    Future<void> _jumpToPage() async
    {
        int? targetPage = _startPage;
        final int? selected = await showDialog<int>(
            context: context,
            builder: (BuildContext context)
            {
                return StatefulBuilder(
                    builder: (
                        BuildContext context,
                        void Function(void Function()) setDialogState,
                    )
                    {
                        final bool valid = targetPage != null &&
                                targetPage! >= 1 &&
                                targetPage! <= _totalPages;
                        return AlertDialog(
                            title: const Text('跳转页面'),
                            content: TextFormField(
                                initialValue: _startPage.toString(),
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                    labelText: '页码（1–$_totalPages）',
                                ),
                                onChanged: (String value)
                                {
                                    setDialogState(()
                                    {
                                        targetPage = int.tryParse(value);
                                    });
                                },
                                onFieldSubmitted: (String value)
                                {
                                    final int? page = int.tryParse(value);
                                    if (page != null &&
                                            page >= 1 &&
                                            page <= _totalPages)
                                    {
                                        Navigator.pop(context, page);
                                    }
                                },
                            ),
                            actions: <Widget>[
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('取消'),
                                ),
                                FilledButton(
                                    onPressed: valid
                                            ? () => Navigator.pop(
                                                context,
                                                targetPage,
                                            )
                                            : null,
                                    child: const Text('跳转'),
                                ),
                            ],
                        );
                    },
                );
            },
        );
        if (!mounted || selected == null || selected == _startPage)
        {
            return;
        }
        if (_scrollController.hasClients)
        {
            _scrollController.jumpTo(0);
        }
        setState(()
        {
            _startPage = selected;
            _lastLoadedPage = selected;
        });
        await _load(reset: true);
    }
}

class _CatalogControls extends StatelessWidget
{
    const _CatalogControls({
        required this.viewMode,
        required this.categories,
        required this.categoryTypeId,
        required this.sort,
        required this.pageLabel,
        required this.onViewModeChanged,
        required this.onPageTap,
        required this.onCategoryChanged,
        required this.onSortChanged,
    });

    static const int _allCategories = -1;

    final _CatalogViewMode viewMode;
    final List<ForumCategory> categories;
    final int? categoryTypeId;
    final CatalogSection sort;
    final String pageLabel;
    final ValueChanged<_CatalogViewMode> onViewModeChanged;
    final VoidCallback onPageTap;
    final ValueChanged<int?> onCategoryChanged;
    final ValueChanged<CatalogSection> onSortChanged;

    @override
    Widget build(BuildContext context)
    {
        final String categoryLabel = categoryTypeId == null
                ? '全部'
                : categories
                        .where(
                            (ForumCategory value) =>
                                    value.typeId == categoryTypeId,
                        )
                        .map((ForumCategory value) => value.name)
                        .firstOrNull ??
                '全部';
        return SizedBox(
            height: 49,
            child: Column(
                children: <Widget>[
                    Expanded(
                        child: Row(
                            children: <Widget>[
                                Expanded(
                                    child: _CatalogSelector<int>(
                                        key: const ValueKey<String>(
                                            'catalog-category-filter',
                                        ),
                                        label: categoryLabel,
                                        selected: categoryTypeId ??
                                                _allCategories,
                                        choices: <(int, String)>[
                                            (_allCategories, '全部'),
                                            ...categories.map(
                                                (ForumCategory value) => (
                                                    value.typeId,
                                                    value.name,
                                                ),
                                            ),
                                        ],
                                        onSelected: (int value) =>
                                                onCategoryChanged(
                                            value == _allCategories
                                                    ? null
                                                    : value,
                                        ),
                                    ),
                                ),
                                Expanded(
                                    child: _CatalogAction(
                                        key: const ValueKey<String>(
                                            'catalog-page-jump',
                                        ),
                                        tooltip: '跳页',
                                        onTap: onPageTap,
                                        child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(pageLabel),
                                        ),
                                    ),
                                ),
                                Expanded(
                                    child: _CatalogAction(
                                        key: const ValueKey<String>(
                                            'catalog-view-toggle',
                                        ),
                                        tooltip: viewMode ==
                                                _CatalogViewMode.list
                                                ? '切换为网格'
                                                : '切换为列表',
                                        onTap: () => onViewModeChanged(
                                            viewMode == _CatalogViewMode.list
                                                    ? _CatalogViewMode.grid
                                                    : _CatalogViewMode.list,
                                        ),
                                        child: Text(
                                            viewMode == _CatalogViewMode.list
                                                    ? '列表'
                                                    : '网格',
                                        ),
                                    ),
                                ),
                                Expanded(
                                    child: _CatalogAction(
                                        key: const ValueKey<String>(
                                            'catalog-sort-filter',
                                        ),
                                        tooltip: sort == CatalogSection.ranking
                                                ? '切换为最新'
                                                : '切换为热度',
                                        onTap: () => onSortChanged(
                                            sort == CatalogSection.ranking
                                                    ? CatalogSection.updated
                                                    : CatalogSection.ranking,
                                        ),
                                        child: Text(
                                            sort == CatalogSection.ranking
                                                ? '热度'
                                                : '最新',
                                        ),
                                    ),
                                ),
                            ],
                        ),
                    ),
                    Divider(
                        height: 1,
                        indent: 12,
                        endIndent: 12,
                        color: Colors.grey.withValues(alpha: 0.2),
                    ),
                ],
            ),
        );
    }
}

class _CatalogAction extends StatelessWidget
{
    const _CatalogAction({
        required this.tooltip,
        required this.onTap,
        required this.child,
        super.key,
    });

    final String tooltip;
    final VoidCallback onTap;
    final Widget child;

    @override
    Widget build(BuildContext context)
    {
        return Tooltip(
            message: tooltip,
            child: InkWell(
                onTap: onTap,
                child: Center(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: child,
                    ),
                ),
            ),
        );
    }
}

class _CatalogSelector<T> extends StatelessWidget
{
    const _CatalogSelector({
        required this.label,
        required this.selected,
        required this.choices,
        required this.onSelected,
        super.key,
    });

    final String label;
    final T selected;
    final List<(T, String)> choices;
    final ValueChanged<T> onSelected;

    @override
    Widget build(BuildContext context)
    {
        return PopupMenuButton<T>(
            initialValue: selected,
            position: PopupMenuPosition.under,
            onSelected: onSelected,
            itemBuilder: (BuildContext context) => choices
                    .map(((T, String) choice) => CheckedPopupMenuItem<T>(
                        value: choice.$1,
                        checked: choice.$1 == selected,
                        child: Text(choice.$2),
                    ))
                    .toList(growable: false),
            child: Center(
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                            Flexible(
                                child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                            ),
                        ],
                    ),
                ),
            ),
        );
    }
}
