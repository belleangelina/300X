import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';
import 'package:x300/app/app_navigation.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/auth/presentation/login_page.dart';
import 'package:x300/features/downloads/application/download_manager.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/library_home_page.dart';
import 'package:x300/features/library/presentation/work_detail_page.dart';
import 'package:x300/features/profile/presentation/profile_page.dart';
import 'package:x300/features/search/presentation/search_page.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';
import 'package:x300/features/update/application/update_controller.dart';
import 'package:x300/features/update/application/update_download_controller.dart';
import 'package:x300/features/update/presentation/update_dialog.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class HomeShell extends ConsumerStatefulWidget
{
    const HomeShell({
        required this.authState,
        this.restoringAuth = false,
        super.key,
    });

    final AuthState authState;
    final bool restoringAuth;

    @override
    ConsumerState<HomeShell> createState()
    {
        return _HomeShellState();
    }
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver, RouteAware
{
    final LibraryHomeController _comicHomeController = LibraryHomeController();
    final LibraryHomeController _novelHomeController = LibraryHomeController();
    int _index = 0;
    Work? _selectedWork;
    int? _selectedSourceTid;
    ProfileDetailDestination? _selectedProfileDetail;
    Timer? _automaticMaintenanceTimer;
    bool _showingUpdate = false;
    bool _routeSubscribed = false;
    AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

    static const List<_Destination> _destinations = <_Destination>[
        _Destination(
            label: '漫画',
            icon: Remix.home_2_line,
            selectedIcon: Remix.home_2_fill,
        ),
        _Destination(
            label: '小说',
            icon: Remix.book_open_line,
            selectedIcon: Remix.book_open_fill,
        ),
        _Destination(
            label: '我的',
            icon: Remix.user_3_line,
            selectedIcon: Remix.user_3_fill,
        ),
    ];

    @override
    void initState()
    {
        super.initState();
        WidgetsBinding.instance.addObserver(this);
        unawaited(ref.read(downloadManagerProvider).start());
        unawaited(
            ref
                .read(updateDownloadControllerProvider.notifier)
                .cleanInstalledUpdate(),
        );
        WidgetsBinding.instance.addPostFrameCallback((Duration _)
        {
            if (!mounted)
            {
                return;
            }
            unawaited(
                ref.read(updateControllerProvider.notifier).checkAutomatically(),
            );
            _automaticMaintenanceTimer = Timer(const Duration(seconds: 5), ()
            {
                unawaited(
                    ref
                        .read(cacheMaintenanceRepositoryProvider)
                        .maintainAutomatically(),
                );
            });
        });
    }

    @override
    void dispose()
    {
        if (_routeSubscribed)
        {
            x300RouteObserver.unsubscribe(this);
        }
        WidgetsBinding.instance.removeObserver(this);
        _automaticMaintenanceTimer?.cancel();
        super.dispose();
    }

    @override
    void didChangeDependencies()
    {
        super.didChangeDependencies();
        if (_routeSubscribed)
        {
            return;
        }
        final ModalRoute<dynamic>? route = ModalRoute.of(context);
        if (route is PageRoute<dynamic>)
        {
            x300RouteObserver.subscribe(this, route);
            _routeSubscribed = true;
        }
    }

    @override
    void didChangeAppLifecycleState(AppLifecycleState state)
    {
        _lifecycleState = state;
        if (state == AppLifecycleState.resumed)
        {
            unawaited(_showPendingUpdate());
            unawaited(_showReadyDownload());
        }
    }

    @override
    void didPopNext()
    {
        unawaited(_showPendingUpdate());
        unawaited(_showReadyDownload());
    }

    @override
    Widget build(BuildContext context)
    {
        ref.listen<UpdateState>(updateControllerProvider, (
            UpdateState? previous,
            UpdateState next,
        )
        {
            if (next.pending != null && previous?.pending != next.pending)
            {
                WidgetsBinding.instance.addPostFrameCallback((Duration _)
                {
                    unawaited(_showPendingUpdate());
                });
            }
        });
        ref.listen<UpdateDownloadState>(updateDownloadControllerProvider, (
            UpdateDownloadState? previous,
            UpdateDownloadState next,
        )
        {
            if (next.readyToInstall && previous?.readyToInstall != true)
            {
                WidgetsBinding.instance.addPostFrameCallback((Duration _)
                {
                    unawaited(_showReadyDownload());
                });
            }
        });
        final Widget content = widget.restoringAuth
            ? const AppLoadingView(message: '正在恢复登录状态')
            : IndexedStack(
                index: _index,
                children: <Widget>[
                    TickerMode(
                        enabled: _index == 0,
                        child: LibraryHomePage(
                            kind: LibraryKind.comic,
                            authState: widget.authState,
                            onLogin: _openLogin,
                            controller: _comicHomeController,
                            onOpenWork: _openWork,
                            onSearch: () => _openSearch(LibraryKind.comic),
                        ),
                    ),
                    TickerMode(
                        enabled: _index == 1,
                        child: LibraryHomePage(
                            kind: LibraryKind.novel,
                            authState: widget.authState,
                            onLogin: _openLogin,
                            controller: _novelHomeController,
                            onOpenWork: _openWork,
                            onSearch: () => _openSearch(LibraryKind.novel),
                        ),
                    ),
                    TickerMode(
                        enabled: _index == 2,
                        child: ProfilePage(
                            authState: widget.authState,
                            onLogin: _openLogin,
                            onLogout: _logout,
                            onOpenDetail: _openProfileDetail,
                        ),
                    ),
                ],
            );

        return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints)
            {
                final Widget shell;
                if (usesWideHomeLayout(
                    Size(constraints.maxWidth, constraints.maxHeight),
                ))
                {
                    shell = _buildWide(content);
                }
                else
                {
                    shell = _buildNarrow(content);
                }
                final UpdateDownloadState download = ref.watch(
                    updateDownloadControllerProvider,
                );
                if (!download.downloading && !download.verifying)
                {
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
                                        title: Text(
                                            download.verifying
                                                ? '正在校验更新'
                                                : '正在下载更新',
                                        ),
                                        subtitle: LinearProgressIndicator(
                                            value: download.verifying
                                                ? null
                                                : download.progress,
                                        ),
                                        trailing: TextButton(
                                            onPressed: () =>
                                                showUpdateDownloadDialog(
                                                    context,
                                                    ref,
                                                ),
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

    Future<void> _showPendingUpdate() async
    {
        if (_showingUpdate ||
            !mounted ||
            _lifecycleState != AppLifecycleState.resumed ||
            ModalRoute.of(context)?.isCurrent != true ||
            _selectedWork != null ||
            _selectedProfileDetail != null)
        {
            return;
        }
        final manifest = ref.read(updateControllerProvider).pending;
        if (manifest == null)
        {
            return;
        }
        _showingUpdate = true;
        try
        {
            final bool ignored = await showUpdateDialog(context, ref, manifest);
            if (!mounted)
            {
                return;
            }
            if (ignored)
            {
                await ref
                    .read(updateControllerProvider.notifier)
                    .ignorePending();
            }
            else
            {
                ref.read(updateControllerProvider.notifier).dismissPending();
            }
        }
        finally
        {
            _showingUpdate = false;
        }
    }

    Future<void> _showReadyDownload() async
    {
        if (!mounted ||
            _lifecycleState != AppLifecycleState.resumed ||
            ModalRoute.of(context)?.isCurrent != true ||
            _selectedWork != null ||
            _selectedProfileDetail != null ||
            !ref.read(updateDownloadControllerProvider).readyToInstall)
        {
            return;
        }
        await showUpdateDownloadDialog(context, ref);
    }

    Widget _buildNarrow(Widget content)
    {
        return Scaffold(
            body: content,
            bottomNavigationBar: BottomNavigationBar(
                currentIndex: _index,
                onTap: _select,
                type: BottomNavigationBarType.fixed,
                showSelectedLabels: false,
                showUnselectedLabels: false,
                items: _destinations
                        .map(
                            (_Destination destination) => BottomNavigationBarItem(
                                icon: Icon(destination.icon),
                                activeIcon: Icon(destination.selectedIcon),
                                label: destination.label,
                            ),
                        )
                        .toList(growable: false),
            ),
        );
    }

    Widget _buildWide(Widget content)
    {
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
                                        icon: Icon(destination.icon),
                                        selectedIcon: Icon(destination.selectedIcon),
                                        label: Text(destination.label),
                                    ),
                                )
                                .toList(growable: false),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 450, child: content),
                    const VerticalDivider(width: 1),
                    Expanded(
                        child: _buildWideDetail(),
                    ),
                ],
            ),
        );
    }

    Widget _buildWideDetail()
    {
        if (_index == 2)
        {
            final ProfileDetailDestination? destination =
                _selectedProfileDetail;
            if (destination == null)
            {
                return const Center(
                    child: Text(
                        '选择功能后在这里显示详情',
                        style: TextStyle(color: Colors.grey),
                    ),
                );
            }
            return KeyedSubtree(
                key: ValueKey<String>('profile-detail-${destination.name}'),
                child: buildProfileDetailPage(destination),
            );
        }
        if (_selectedWork == null)
        {
            return const Center(
                child: Text(
                    '选择作品后在这里显示详情',
                    style: TextStyle(color: Colors.grey),
                ),
            );
        }
        return WorkDetailPage(
            key: ValueKey<String>(_selectedWork!.id),
            work: _selectedWork!,
            embedded: true,
            initialSourceTid: _selectedSourceTid,
            resolveOnOpen: true,
        );
    }

    void _select(int value)
    {
        if (value == _index)
        {
            if (value == 0)
            {
                unawaited(_comicHomeController.scrollToTopAndRefresh());
            }
            else if (value == 1)
            {
                unawaited(_novelHomeController.scrollToTopAndRefresh());
            }
            return;
        }
        setState(()
        {
            _index = value;
            _selectedWork = null;
            _selectedSourceTid = null;
            _selectedProfileDetail = null;
        });
        unawaited(_showPendingUpdate());
    }

    void _openWork(Work work)
    {
        final int initialSourceTid = work.primarySourceTid;
        _showWork(work, initialSourceTid: initialSourceTid);
    }

    void _showWork(Work work, {required int initialSourceTid})
    {
        if (usesWideHomeLayout(MediaQuery.sizeOf(context)))
        {
            setState(()
            {
                _selectedWork = work;
                _selectedSourceTid = initialSourceTid;
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

    void _openProfileDetail(ProfileDetailDestination destination)
    {
        if (usesWideHomeLayout(MediaQuery.sizeOf(context)))
        {
            setState(()
            {
                _selectedProfileDetail = destination;
            });
            return;
        }
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    buildProfileDetailPage(destination),
            ),
        );
    }

    void _openSearch(LibraryKind kind)
    {
        if (widget.authState.status != AuthStatus.authenticated)
        {
            _openLogin();
            return;
        }
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => SearchPage(kind: kind),
            ),
        );
    }

    Future<void> _openLogin() async
    {
        await Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => LoginPage(
                    authState: widget.authState,
                ),
            ),
        );
    }

    Future<void> _logout() async
    {
        await ref.read(cacheMaintenanceRepositoryProvider).clearAccountCaches();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await ref.read(authControllerProvider.notifier).logout();
    }
}

bool usesWideHomeLayout(Size size)
{
    return size.width >= 720 && size.width > size.height;
}

class _Destination
{
    const _Destination({
        required this.label,
        required this.icon,
        required this.selectedIcon,
    });

    final String label;
    final IconData icon;
    final IconData selectedIcon;
}
