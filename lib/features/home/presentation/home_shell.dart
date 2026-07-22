import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/downloads/application/download_manager.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/library_home_page.dart';
import 'package:x300/features/library/presentation/work_detail_page.dart';
import 'package:x300/features/profile/presentation/profile_page.dart';
import 'package:x300/features/search/presentation/search_page.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';

class HomeShell extends ConsumerStatefulWidget
{
    const HomeShell({required this.username, super.key});

    final String username;

    @override
    ConsumerState<HomeShell> createState()
    {
        return _HomeShellState();
    }
}

class _HomeShellState extends ConsumerState<HomeShell>
{
    final LibraryHomeController _comicHomeController = LibraryHomeController();
    final LibraryHomeController _novelHomeController = LibraryHomeController();
    int _index = 0;
    Work? _selectedWork;
    int? _selectedSourceTid;
    ProfileDetailDestination? _selectedProfileDetail;
    Timer? _automaticMaintenanceTimer;

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
        unawaited(ref.read(downloadManagerProvider).start());
        WidgetsBinding.instance.addPostFrameCallback((Duration _)
        {
            if (!mounted)
            {
                return;
            }
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
        _automaticMaintenanceTimer?.cancel();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        final Widget content = IndexedStack(
            index: _index,
            children: <Widget>[
                TickerMode(
                    enabled: _index == 0,
                    child: LibraryHomePage(
                        kind: LibraryKind.comic,
                        controller: _comicHomeController,
                        onOpenWork: _openWork,
                        onSearch: () => _openSearch(LibraryKind.comic),
                    ),
                ),
                TickerMode(
                    enabled: _index == 1,
                    child: LibraryHomePage(
                        kind: LibraryKind.novel,
                        controller: _novelHomeController,
                        onOpenWork: _openWork,
                        onSearch: () => _openSearch(LibraryKind.novel),
                    ),
                ),
                TickerMode(
                    enabled: _index == 2,
                    child: ProfilePage(
                        username: widget.username,
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
                return shell;
            },
        );
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
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => SearchPage(kind: kind),
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
