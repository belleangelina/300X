import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';
import 'package:x300/app/app_navigation.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/auth/presentation/login_page.dart';
import 'package:x300/features/community/presentation/community_pages.dart';
import 'package:x300/features/downloads/application/download_manager.dart';
import 'package:x300/features/favorites/data/favorite_target_contract.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/favorites/presentation/favorites_home_page.dart';
import 'package:x300/features/favorites/presentation/favorite_target_page.dart';
import 'package:x300/features/forum/domain/forum_models.dart' as forum_domain;
import 'package:x300/features/forum/presentation/forum_announcement_page.dart';
import 'package:x300/features/forum/presentation/forum_board_page.dart';
import 'package:x300/features/forum/presentation/forum_home_page.dart';
import 'package:x300/features/forum/presentation/forum_topic_page.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/library_home_page.dart';
import 'package:x300/features/library/presentation/work_detail_page.dart';
import 'package:x300/features/profile/presentation/profile_page.dart';
import 'package:x300/features/search/presentation/search_page.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';
import 'package:x300/features/update/application/update_controller.dart';
import 'package:x300/features/update/application/update_download_controller.dart';
import 'package:x300/features/update/presentation/update_dialog.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({
    required this.authState,
    this.forumBuilder,
    this.allFavoritesBuilder,
    this.onRefreshForum,
    this.onRefreshAllFavorites,
    super.key,
  });

  final AuthState authState;
  final WidgetBuilder? forumBuilder;
  final WidgetBuilder? allFavoritesBuilder;
  final Future<void> Function()? onRefreshForum;
  final Future<void> Function()? onRefreshAllFavorites;

  @override
  ConsumerState<HomeShell> createState() {
    return _HomeShellState();
  }
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver, RouteAware {
  final LibraryHomeController _libraryHomeController = LibraryHomeController();
  final ForumHomeController _forumHomeController = ForumHomeController();
  final FavoritesHomeController _favoritesHomeController =
      FavoritesHomeController();
  final Set<int> _initializedDestinations = <int>{0};
  int _index = 0;
  Work? _selectedLibraryWork;
  int? _selectedLibrarySourceTid;
  forum_domain.ForumBoardNode? _selectedForumBoard;
  forum_domain.ForumThreadSummary? _selectedForumThread;
  int? _selectedForumFocusedPostId;
  Work? _selectedFavoriteWork;
  int? _selectedFavoriteSourceTid;
  forum_domain.ForumBoardNode? _selectedFavoriteForumBoard;
  forum_domain.ForumThreadSummary? _selectedFavoriteForumThread;
  int? _selectedFavoriteForumFocusedPostId;
  RawFavoriteItem? _selectedFavoriteTarget;
  ProfileDetailDestination? _selectedProfileDetail;
  Timer? _automaticMaintenanceTimer;
  bool _showingUpdate = false;
  bool _routeSubscribed = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  static const List<_Destination> _destinations = <_Destination>[
    _Destination(
      id: 'library',
      label: '漫画/小说',
      icon: Remix.home_2_line,
      selectedIcon: Remix.home_2_fill,
    ),
    _Destination(
      id: 'forum',
      label: '论坛',
      icon: Remix.chat_3_line,
      selectedIcon: Remix.chat_3_fill,
    ),
    _Destination(
      id: 'favorites',
      label: '收藏',
      icon: Remix.bookmark_line,
      selectedIcon: Remix.bookmark_fill,
    ),
    _Destination(
      id: 'profile',
      label: '我的',
      icon: Remix.user_3_line,
      selectedIcon: Remix.user_3_fill,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(downloadManagerProvider).start());
    unawaited(
      ref
          .read(updateDownloadControllerProvider.notifier)
          .cleanInstalledUpdate(),
    );
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref.read(updateControllerProvider.notifier).checkAutomatically(),
      );
      _automaticMaintenanceTimer = Timer(const Duration(seconds: 5), () {
        unawaited(
          ref.read(cacheMaintenanceRepositoryProvider).maintainAutomatically(),
        );
      });
    });
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      x300RouteObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _automaticMaintenanceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) {
      return;
    }
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      x300RouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_showPendingUpdate());
      unawaited(_showReadyDownload());
      _refreshForumSummary();
    }
  }

  @override
  void didPopNext() {
    unawaited(_showPendingUpdate());
    unawaited(_showReadyDownload());
    _refreshForumSummary();
  }

  void _refreshForumSummary() {
    if (!_initializedDestinations.contains(1) ||
        widget.authState.status != AuthStatus.authenticated ||
        widget.authState.userId <= 0) {
      return;
    }
    unawaited(_forumHomeController.refresh());
    unawaited(widget.onRefreshForum?.call());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateState>(updateControllerProvider, (
      UpdateState? previous,
      UpdateState next,
    ) {
      if (next.pending != null && previous?.pending != next.pending) {
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          unawaited(_showPendingUpdate());
        });
      }
    });
    ref.listen<UpdateDownloadState>(updateDownloadControllerProvider, (
      UpdateDownloadState? previous,
      UpdateDownloadState next,
    ) {
      if (next.readyToInstall && previous?.readyToInstall != true) {
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          unawaited(_showReadyDownload());
        });
      }
    });
    final Widget content = IndexedStack(
      index: _index,
      children: List<Widget>.generate(
        _destinations.length,
        _buildDestination,
        growable: false,
      ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget shell;
        if (usesWideHomeLayout(
          Size(constraints.maxWidth, constraints.maxHeight),
        )) {
          shell = _buildWide(content);
        } else {
          shell = _buildNarrow(content);
        }
        final UpdateDownloadState download = ref.watch(
          updateDownloadControllerProvider,
        );
        if (!download.downloading && !download.verifying) {
          return shell;
        }
        return Stack(
          children: <Widget>[
            shell,
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  color: Theme.of(context).colorScheme.surface,
                  child: ListTile(
                    title: Text(download.verifying ? '正在校验更新' : '正在下载更新'),
                    subtitle: LinearProgressIndicator(
                      value: download.verifying ? null : download.progress,
                    ),
                    trailing: TextButton(
                      onPressed: () => showUpdateDownloadDialog(context, ref),
                      child: const Text('查看'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPendingUpdate() async {
    if (_showingUpdate ||
        !mounted ||
        _lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true ||
        _hasVisibleDetail) {
      return;
    }
    final manifest = ref.read(updateControllerProvider).pending;
    if (manifest == null) {
      return;
    }
    _showingUpdate = true;
    try {
      final bool ignored = await showUpdateDialog(context, ref, manifest);
      if (!mounted) {
        return;
      }
      if (ignored) {
        await ref.read(updateControllerProvider.notifier).ignorePending();
      } else {
        ref.read(updateControllerProvider.notifier).dismissPending();
      }
    } finally {
      _showingUpdate = false;
    }
  }

  Future<void> _showReadyDownload() async {
    if (!mounted ||
        _lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true ||
        _hasVisibleDetail ||
        !ref.read(updateDownloadControllerProvider).readyToInstall) {
      return;
    }
    await showUpdateDownloadDialog(context, ref);
  }

  Widget _buildNarrow(Widget content) {
    return Scaffold(
      body: content,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _select,
        type: BottomNavigationBarType.fixed,
        items: _destinations
            .map(
              (_Destination destination) => BottomNavigationBarItem(
                icon: Icon(
                  destination.icon,
                  key: Key('home-tab-${destination.id}'),
                ),
                activeIcon: Icon(
                  destination.selectedIcon,
                  key: Key('home-tab-${destination.id}'),
                ),
                label: destination.label,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildWide(Widget content) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            destinations: _destinations
                .map(
                  (_Destination destination) => NavigationRailDestination(
                    icon: Icon(
                      destination.icon,
                      key: Key('home-tab-${destination.id}'),
                    ),
                    selectedIcon: Icon(
                      destination.selectedIcon,
                      key: Key('home-tab-${destination.id}'),
                    ),
                    label: Text(destination.label),
                  ),
                )
                .toList(growable: false),
          ),
          const VerticalDivider(width: 1),
          SizedBox(width: 450, child: content),
          const VerticalDivider(width: 1),
          Expanded(child: _buildWideDetail()),
        ],
      ),
    );
  }

  Widget _buildWideDetail() {
    final Widget libraryDetail = _selectedLibraryWork == null
        ? const Center(
            child: Text('选择作品后在这里显示详情', style: TextStyle(color: Colors.grey)),
          )
        : WorkDetailPage(
            key: ValueKey<String>(_selectedLibraryWork!.id),
            work: _selectedLibraryWork!,
            embedded: true,
            initialSourceTid: _selectedLibrarySourceTid,
            resolveOnOpen: true,
          );
    final Widget forumDetail = _buildWideForumDetail(
          board: _selectedForumBoard,
          thread: _selectedForumThread,
          focusedPostId: _selectedForumFocusedPostId,
        ) ??
        const Center(
          child: Text(
            '选择版块或主题后在这里显示详情',
            style: TextStyle(color: Colors.grey),
          ),
        );
    final RawFavoriteItem? target = _selectedFavoriteTarget;
    final Widget favoriteDetail;
    if (target != null) {
      final Uri? targetUri = target.targetUri;
      final int profileUserId = target.userId ?? 0;
      favoriteDetail = target.targetKind == RawFavoriteTargetKind.userSpace &&
              targetUri != null &&
              profileUserId > 0
          ? CommunityProfileScreen(
              key: ValueKey<String>('favorite-profile-$profileUserId'),
              uri: targetUri,
              profileUserId: profileUserId,
              onOpenFavoriteThread: _openFavoriteThread,
              onOpenFavoriteBoard: _openFavoriteBoard,
              onOpenFavoriteTarget: _openFavoriteTarget,
            )
          : FavoriteTargetPage(
              key: ValueKey<String>('favorite-target-${target.identityKey}'),
              item: target,
              onOpenBoard: _openForumBoard,
              onOpenThread: _openForumThread,
              onOpenTarget: _openFavoriteTarget,
            );
    } else {
      favoriteDetail = _buildWideForumDetail(
            board: _selectedFavoriteForumBoard,
            thread: _selectedFavoriteForumThread,
            focusedPostId: _selectedFavoriteForumFocusedPostId,
          ) ??
          (_selectedFavoriteWork == null
              ? const Center(
                  child: Text(
                    '选择收藏后在这里显示详情',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : WorkDetailPage(
                  key: ValueKey<String>(
                    'favorite-work-${_selectedFavoriteWork!.id}',
                  ),
                  work: _selectedFavoriteWork!,
                  embedded: true,
                  initialSourceTid: _selectedFavoriteSourceTid,
                  resolveOnOpen: true,
                ));
    }
    final ProfileDetailDestination? profile = _selectedProfileDetail;
    final Widget profileDetail = profile == null
        ? const Center(
            child: Text(
              '选择功能后在这里显示详情',
              style: TextStyle(color: Colors.grey),
            ),
          )
        : KeyedSubtree(
            key: ValueKey<String>('profile-detail-${profile.name}'),
            child: buildProfileDetailPage(profile),
          );
    final List<Widget> details = <Widget>[
      libraryDetail,
      forumDetail,
      favoriteDetail,
      profileDetail,
    ];
    return IndexedStack(
      index: _index,
      children: List<Widget>.generate(
        details.length,
        (int index) => TickerMode(
          enabled: _index == index,
          child: details[index],
        ),
        growable: false,
      ),
    );
  }

  Widget? _buildWideForumDetail({
    required forum_domain.ForumBoardNode? board,
    required forum_domain.ForumThreadSummary? thread,
    required int? focusedPostId,
  }) {
    if (thread != null) {
      if (thread.targetKind ==
          forum_domain.ForumThreadTargetKind.announcement) {
        return ForumAnnouncementPage(
          key: ValueKey<String>('forum-detail-announcement-${thread.id}'),
          announcement: thread,
        );
      }
      return ForumTopicPage(
        key: ValueKey<String>(
          'forum-detail-thread-${thread.id}-'
          '${focusedPostId ?? 0}',
        ),
        thread: thread,
        focusedPostId: focusedPostId,
      );
    }
    if (board == null) {
      return null;
    }
    return ForumBoardPage(
      key: ValueKey<String>('forum-detail-board-${board.id}'),
      board: board,
      onOpenThread: _openForumThread,
    );
  }

  void _select(int value) {
    if (value == _index) {
      if (value == 0) {
        unawaited(_libraryHomeController.scrollToTopAndRefresh());
      } else if (value == 1) {
        unawaited(_forumHomeController.scrollToTopAndRefresh());
        unawaited(widget.onRefreshForum?.call());
      } else if (value == 2) {
        unawaited(_favoritesHomeController.scrollToTopAndRefresh());
      }
      return;
    }
    setState(() {
      _index = value;
      _initializedDestinations.add(value);
    });
    unawaited(_showPendingUpdate());
  }

  Widget _buildDestination(int index) {
    if (!_initializedDestinations.contains(index)) {
      return const SizedBox.shrink();
    }
    final Widget child = switch (index) {
      0 => LibraryHomePage(
        kind: LibraryKind.comic,
        combined: true,
        authState: widget.authState,
        onLogin: _openLogin,
        controller: _libraryHomeController,
        onOpenWork: _openWork,
        onSearchForKind: _openSearch,
      ),
      1 => Builder(builder: widget.forumBuilder ?? _buildForum),
      2 => FavoritesHomePage(
        authState: widget.authState,
        onLogin: _openLogin,
        onOpenWork: _openWork,
        controller: _favoritesHomeController,
        allFavoritesBuilder: widget.allFavoritesBuilder,
        onRefreshAll: widget.onRefreshAllFavorites,
        onOpenFavoriteThread: _openFavoriteThread,
        onOpenFavoriteBoard: _openFavoriteBoard,
        onOpenFavoriteTarget: _openFavoriteTarget,
      ),
      _ => ProfilePage(
        authState: widget.authState,
        onLogin: _openLogin,
        onLogout: _logout,
        onOpenDetail: _openProfileDetail,
      ),
    };
    return TickerMode(enabled: _index == index, child: child);
  }

  Widget _buildForum(BuildContext context) {
    return ForumHomePage(
      authState: widget.authState,
      onLogin: _openLogin,
      controller: _forumHomeController,
      onOpenBoard: _openForumBoard,
      onOpenFavoriteThread: _openFavoriteThread,
      onOpenFavoriteBoard: _openFavoriteBoard,
      onOpenFavoriteTarget: _openFavoriteTarget,
    );
  }

  void _openWork(Work work) {
    final int initialSourceTid = work.primarySourceTid;
    _showWork(work, initialSourceTid: initialSourceTid);
  }

  void _showWork(Work work, {required int initialSourceTid}) {
    if (usesWideHomeLayout(MediaQuery.sizeOf(context))) {
      setState(() {
        if (_index == 2) {
          _selectedFavoriteWork = work;
          _selectedFavoriteSourceTid = initialSourceTid;
          _selectedFavoriteForumBoard = null;
          _selectedFavoriteForumThread = null;
          _selectedFavoriteForumFocusedPostId = null;
          _selectedFavoriteTarget = null;
        } else {
          _selectedLibraryWork = work;
          _selectedLibrarySourceTid = initialSourceTid;
        }
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => WorkDetailPage(
          work: work,
          initialSourceTid: initialSourceTid,
          resolveOnOpen: true,
        ),
      ),
    );
  }

  void _openForumBoard(forum_domain.ForumBoardNode board) {
    if (usesWideHomeLayout(MediaQuery.sizeOf(context))) {
      setState(() {
        if (_index == 2) {
          _selectedFavoriteWork = null;
          _selectedFavoriteSourceTid = null;
          _selectedFavoriteForumBoard = board;
          _selectedFavoriteForumThread = null;
          _selectedFavoriteForumFocusedPostId = null;
          _selectedFavoriteTarget = null;
        } else {
          _selectedForumBoard = board;
          _selectedForumThread = null;
          _selectedForumFocusedPostId = null;
        }
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ForumBoardPage(board: board),
      ),
    );
  }

  void _openForumThread(
    forum_domain.ForumThreadSummary thread, {
    int? focusedPostId,
  }) {
    if (usesWideHomeLayout(MediaQuery.sizeOf(context))) {
      setState(() {
        if (_index == 2) {
          _selectedFavoriteWork = null;
          _selectedFavoriteSourceTid = null;
          _selectedFavoriteForumBoard = null;
          _selectedFavoriteForumThread = thread;
          _selectedFavoriteForumFocusedPostId = focusedPostId;
          _selectedFavoriteTarget = null;
        } else {
          _selectedForumBoard = null;
          _selectedForumThread = thread;
          _selectedForumFocusedPostId = focusedPostId;
        }
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ForumTopicPage(thread: thread, focusedPostId: focusedPostId),
      ),
    );
  }

  void _openFavoriteThread(RawFavoriteItem item) {
    final int? threadId = item.threadId;
    final Uri? uri = item.targetUri;
    if (threadId == null || uri == null) {
      _showInvalidFavorite();
      return;
    }
    _openForumThread(
      forum_domain.ForumThreadSummary(
        id: threadId,
        boardId: item.boardId ?? 0,
        title: item.title,
        summary: item.description,
        uri: uri,
      ),
    );
  }

  void _openFavoriteBoard(RawFavoriteItem item) {
    final int? boardId = item.boardId;
    final Uri? uri = item.targetUri;
    if (boardId == null || uri == null) {
      _showInvalidFavorite();
      return;
    }
    _openForumBoard(
      forum_domain.ForumBoardNode(
        id: boardId,
        name: item.title,
        description: item.description,
        uri: uri,
      ),
    );
  }

  void _openFavoriteTarget(RawFavoriteItem item) {
    if (item.targetUri == null || item.targetId == null) {
      _showInvalidFavorite();
      return;
    }
    if (item.targetKind == RawFavoriteTargetKind.userSpace) {
      final FavoriteTargetDescriptor? descriptor =
          const FavoriteTargetContract().describe(item.targetUri!);
      if (descriptor == null ||
          descriptor.kind != RawFavoriteTargetKind.userSpace ||
          descriptor.targetId != item.userId) {
        _showInvalidFavorite();
        return;
      }
    }
    if (usesWideHomeLayout(MediaQuery.sizeOf(context))) {
      setState(() {
        _selectedFavoriteWork = null;
        _selectedFavoriteSourceTid = null;
        _selectedFavoriteForumBoard = null;
        _selectedFavoriteForumThread = null;
        _selectedFavoriteForumFocusedPostId = null;
        _selectedFavoriteTarget = item;
      });
      return;
    }
    if (item.targetKind == RawFavoriteTargetKind.userSpace) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => CommunityProfileScreen(
            uri: item.targetUri!,
            profileUserId: item.userId!,
            onOpenFavoriteThread: _openFavoriteThread,
            onOpenFavoriteBoard: _openFavoriteBoard,
            onOpenFavoriteTarget: _openFavoriteTarget,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => FavoriteTargetPage(
          item: item,
          onOpenBoard: _openForumBoard,
          onOpenThread: _openForumThread,
          onOpenTarget: _openFavoriteTarget,
        ),
      ),
    );
  }

  void _showInvalidFavorite() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('该收藏缺少可用的论坛地址')));
  }

  void _openProfileDetail(ProfileDetailDestination destination) {
    if (usesWideHomeLayout(MediaQuery.sizeOf(context))) {
      setState(() {
        _selectedProfileDetail = destination;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => buildProfileDetailPage(destination),
      ),
    );
  }

  void _openSearch(LibraryKind kind) {
    if (widget.authState.status != AuthStatus.authenticated) {
      _openLogin();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SearchPage(kind: kind),
      ),
    );
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            LoginPage(authState: widget.authState),
      ),
    );
  }

  Future<void> _logout() async {
    final int userId = widget.authState.userId;
    await ref.read(authControllerProvider.notifier).logout();
    await ref
        .read(cacheMaintenanceRepositoryProvider)
        .clearAccountCaches(userId);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  bool get _hasVisibleDetail => switch (_index) {
    0 => _selectedLibraryWork != null,
    1 => _selectedForumBoard != null || _selectedForumThread != null,
    2 =>
      _selectedFavoriteWork != null ||
          _selectedFavoriteForumBoard != null ||
          _selectedFavoriteForumThread != null ||
          _selectedFavoriteTarget != null,
    3 => _selectedProfileDetail != null,
    _ => false,
  };
}

bool usesWideHomeLayout(Size size) {
  return size.width >= 720 && size.width > size.height;
}

class _Destination {
  const _Destination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
