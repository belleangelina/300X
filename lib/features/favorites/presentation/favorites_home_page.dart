import 'package:flutter/material.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/favorites/presentation/cloud_favorites_page.dart';
import 'package:x300/features/favorites/presentation/raw_favorites_page.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/tab_app_bar.dart';

class FavoritesHomeController {
  Future<void> Function()? _refreshHandler;

  Future<void> scrollToTopAndRefresh() {
    return _refreshHandler?.call() ?? Future<void>.value();
  }

  void attach(Future<void> Function() handler) {
    _refreshHandler = handler;
  }

  void detach(Future<void> Function() handler) {
    if (identical(_refreshHandler, handler)) {
      _refreshHandler = null;
    }
  }
}

class FavoritesHomePage extends StatefulWidget {
  const FavoritesHomePage({
    required this.authState,
    required this.onLogin,
    required this.onOpenWork,
    this.controller,
    this.allFavoritesBuilder,
    this.onRefreshAll,
    this.onOpenFavoriteThread,
    this.onOpenFavoriteBoard,
    this.onOpenFavoriteTarget,
    super.key,
  });

  final AuthState authState;
  final VoidCallback onLogin;
  final ValueChanged<Work> onOpenWork;
  final FavoritesHomeController? controller;
  final WidgetBuilder? allFavoritesBuilder;
  final Future<void> Function()? onRefreshAll;
  final ValueChanged<RawFavoriteItem>? onOpenFavoriteThread;
  final ValueChanged<RawFavoriteItem>? onOpenFavoriteBoard;
  final ValueChanged<RawFavoriteItem>? onOpenFavoriteTarget;

  @override
  State<FavoritesHomePage> createState() {
    return _FavoritesHomePageState();
  }
}

class _FavoritesHomePageState extends State<FavoritesHomePage>
    with SingleTickerProviderStateMixin {
  final List<CloudFavoritesPageController> _pageControllers =
      <CloudFavoritesPageController>[
        CloudFavoritesPageController(),
        CloudFavoritesPageController(),
      ];
  late final TabController _tabController;
  final RawFavoritesPageController _rawPageController =
      RawFavoritesPageController();
  late final Future<void> Function() _refreshHandler;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _refreshHandler = _refreshActivePage;
    widget.controller?.attach(_refreshHandler);
  }

  @override
  void didUpdateWidget(covariant FavoritesHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach(_refreshHandler);
      widget.controller?.attach(_refreshHandler);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach(_refreshHandler);
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TabAppBar(
        controller: _tabController,
        tabs: const <Tab>[
          Tab(text: '漫画'),
          Tab(text: '小说'),
          Tab(text: '全部'),
        ],
      ),
      body: widget.authState.status != AuthStatus.authenticated
          ? AppEmptyView(
              message: widget.authState.sessionExpired
                  ? '登录状态已失效，请重新登录后查看收藏'
                  : '登录后查看收藏',
              actionLabel: '登录',
              onRefresh: widget.onLogin,
            )
          : TabBarView(
              controller: _tabController,
              children: <Widget>[
                TickerMode(
                  enabled: _activeIndex == 0,
                  child: CloudFavoritesPage(
                    key: const Key('favorites-comic-page'),
                    kind: LibraryKind.comic,
                    controller: _pageControllers[0],
                    embedded: true,
                    onOpenWork: widget.onOpenWork,
                  ),
                ),
                TickerMode(
                  enabled: _activeIndex == 1,
                  child: CloudFavoritesPage(
                    key: const Key('favorites-novel-page'),
                    kind: LibraryKind.novel,
                    controller: _pageControllers[1],
                    embedded: true,
                    onOpenWork: widget.onOpenWork,
                  ),
                ),
                TickerMode(
                  enabled: _activeIndex == 2,
                  child: Builder(
                    builder: widget.allFavoritesBuilder ?? _buildAllFavorites,
                  ),
                ),
              ],
            ),
    );
  }

  void _handleTabChanged() {
    if (_activeIndex == _tabController.index) {
      return;
    }
    setState(() {
      _activeIndex = _tabController.index;
    });
  }

  Future<void> _refreshActivePage() {
    if (widget.authState.status != AuthStatus.authenticated) {
      return Future<void>.value();
    }
    if (_tabController.index < _pageControllers.length) {
      return _pageControllers[_tabController.index].scrollToTopAndRefresh();
    }
    return widget.onRefreshAll?.call() ??
        _rawPageController.scrollToTopAndRefresh();
  }

  Widget _buildAllFavorites(BuildContext context) {
    return RawFavoritesPage(
      controller: _rawPageController,
      onOpenThread: widget.onOpenFavoriteThread,
      onOpenBoard: widget.onOpenFavoriteBoard,
      onOpenTarget: widget.onOpenFavoriteTarget,
    );
  }
}
