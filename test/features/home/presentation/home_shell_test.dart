import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:remixicon/remixicon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/community/data/community_repository.dart';
import 'package:x300/features/community/domain/community_models.dart';
import 'package:x300/features/community/presentation/community_pages.dart';
import 'package:x300/features/downloads/application/download_manager.dart';
import 'package:x300/features/favorites/data/favorite_target_repository.dart';
import 'package:x300/features/favorites/domain/favorite_target_models.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/favorites/presentation/favorite_target_page.dart';
import 'package:x300/features/favorites/presentation/favorites_home_page.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/domain/forum_announcement_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart' as forum_domain;
import 'package:x300/features/forum/presentation/forum_announcement_page.dart';
import 'package:x300/features/forum/presentation/forum_board_page.dart';
import 'package:x300/features/forum/presentation/forum_home_page.dart';
import 'package:x300/features/home/presentation/home_shell.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/profile/presentation/profile_page.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';
import 'package:x300/features/settings/domain/app_settings.dart';
import 'package:x300/features/settings/presentation/settings_page.dart';

class _MockDownloadManager extends Mock implements DownloadManager {}

class _MockForumLibraryRepository extends Mock
    implements ForumLibraryRepository {}

class _MockCacheMaintenanceRepository extends Mock
    implements CacheMaintenanceRepository {}

class _MockForumReadRepository extends Mock implements ForumReadRepository {}

class _MockCommunityRepository extends Mock implements CommunityRepository {}

class _MockFavoriteTargetRepository extends Mock
    implements FavoriteTargetRepository {}

void main() {
  late AppSettingsRepository settingsRepository;
  late _MockDownloadManager downloadManager;
  late _MockForumLibraryRepository libraryRepository;
  late _MockCacheMaintenanceRepository cacheMaintenanceRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settingsRepository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
    );
    await settingsRepository.save(
      const AppSettings(automaticUpdateChecks: false),
    );
    downloadManager = _MockDownloadManager();
    libraryRepository = _MockForumLibraryRepository();
    cacheMaintenanceRepository = _MockCacheMaintenanceRepository();
    when(() => downloadManager.start()).thenAnswer((_) async {});
    when(() => cacheMaintenanceRepository.measureUsage()).thenAnswer(
      (_) async => const CacheUsageSnapshot(temporaryBytes: 0, coverBytes: 0),
    );
    for (final (LibraryKind, NovelSourceFilter) query
        in <(LibraryKind, NovelSourceFilter)>[
          (LibraryKind.comic, NovelSourceFilter.all),
          (LibraryKind.novel, NovelSourceFilter.lightNovel),
          (LibraryKind.novel, NovelSourceFilter.literature),
        ]) {
      when(
        () => libraryRepository.loadCatalog(
          kind: query.$1,
          section: CatalogSection.updated,
          novelSource: query.$2,
          page: 1,
          typeId: null,
        ),
      ).thenAnswer((_) async => _emptyCatalogPage);
    }
  });

  setUpAll(() {
    registerFallbackValue(
      Uri.parse('https://bbs.yamibo.com/forum.php?mobile=2'),
    );
  });

  test('主页仅在足够宽的横屏窗口启用双栏布局', () {
    expect(usesWideHomeLayout(const Size(1280, 800)), isTrue);
    expect(usesWideHomeLayout(const Size(720, 600)), isTrue);
    expect(usesWideHomeLayout(const Size(800, 1280)), isFalse);
    expect(usesWideHomeLayout(const Size(719, 600)), isFalse);
    expect(usesWideHomeLayout(const Size(720, 720)), isFalse);
  });

  testWidgets('横屏个人页在右侧打开二级页面', (WidgetTester tester) async {
    _setSurfaceSize(tester, const Size(1280, 800));
    await tester.pumpWidget(
      _homeApp(
        settingsRepository,
        downloadManager,
        libraryRepository,
        cacheMaintenanceRepository,
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.tap(find.text('更多设置'));
    await tester.pump();

    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('profile-detail-settings')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('四主入口按首次访问初始化并保留论坛刷新入口', (WidgetTester tester) async {
    _setSurfaceSize(tester, const Size(1280, 800));
    var forumBuilds = 0;
    var forumRefreshes = 0;
    await tester.pumpWidget(
      _homeApp(
        settingsRepository,
        downloadManager,
        libraryRepository,
        cacheMaintenanceRepository,
        authState: const AuthState.unauthenticated(),
        forumBuilder: (BuildContext context) {
          forumBuilds++;
          return const Scaffold(body: Text('论坛内容'));
        },
        onRefreshForum: () async => forumRefreshes++,
      ),
    );
    await tester.pump();

    final NavigationRail rail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );
    expect(
      rail.destinations
          .map((NavigationRailDestination value) => (value.label as Text).data)
          .toList(growable: false),
      <String?>['漫画/小说', '论坛', '收藏', '我的'],
    );
    expect(forumBuilds, 0);
    expect(find.byType(FavoritesHomePage), findsNothing);
    expect(find.byType(ProfilePage), findsNothing);

    await tester.tap(find.text('论坛'));
    await tester.pump();
    expect(forumBuilds, 1);
    expect(find.text('论坛内容'), findsOneWidget);

    await tester.tap(find.text('论坛'));
    await tester.pump();
    expect(forumRefreshes, 1);

    await tester.tap(find.text('收藏'));
    await tester.pump();
    expect(find.byType(FavoritesHomePage), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump();
    expect(find.byType(ProfilePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('默认论坛入口使用原生论坛页并保留登录引导', (WidgetTester tester) async {
    _setSurfaceSize(tester, const Size(390, 780));
    await tester.pumpWidget(
      _homeApp(
        settingsRepository,
        downloadManager,
        libraryRepository,
        cacheMaintenanceRepository,
        authState: const AuthState.unauthenticated(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Remix.chat_3_line));
    await tester.pumpAndSettle();

    expect(find.byType(ForumHomePage), findsOneWidget);
    expect(find.text('登录后查看论坛'), findsOneWidget);
    expect(find.text('论坛页面正在接入移动网页数据'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('回到前台时只刷新已初始化的论坛摘要', (WidgetTester tester) async {
    _setSurfaceSize(tester, const Size(390, 780));
    final _MockForumReadRepository forumRepository = _MockForumReadRepository();
    final Uri sourceUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mobile=2',
    );
    when(() => forumRepository.loadIndex()).thenAnswer(
      (_) async => forum_domain.ForumBoardIndex(
        sections: const <forum_domain.ForumSection>[],
        unsectionedBoards: const <forum_domain.ForumBoardNode>[],
        viewer: const forum_domain.ForumViewer(userId: 42, noticeCount: 1),
        navigation: const forum_domain.ForumNavigationLinks(),
        sourceUri: sourceUri,
      ),
    );
    await tester.pumpWidget(
      _homeApp(
        settingsRepository,
        downloadManager,
        libraryRepository,
        cacheMaintenanceRepository,
        authState: const AuthState.authenticated('测试账号', userId: 42),
        forumRepository: forumRepository,
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    verifyNever(() => forumRepository.loadIndex());

    await tester.tap(find.byIcon(Remix.chat_3_line));
    await tester.pumpAndSettle();
    verify(() => forumRepository.loadIndex()).called(1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    verify(() => forumRepository.loadIndex()).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('切换主入口不重建已初始化的内部状态', (WidgetTester tester) async {
    _setSurfaceSize(tester, const Size(1280, 800));
    await tester.pumpWidget(
      _homeApp(
        settingsRepository,
        downloadManager,
        libraryRepository,
        cacheMaintenanceRepository,
        authState: const AuthState.unauthenticated(),
        forumBuilder: (BuildContext context) => const _StatefulForumProbe(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('论坛'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('forum-probe-increment')));
    await tester.pump();
    expect(find.text('论坛状态 1'), findsOneWidget);

    await tester.tap(find.text('收藏'));
    await tester.pump();
    await tester.tap(find.text('论坛'));
    await tester.pump();

    expect(find.text('论坛状态 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('横屏切换主入口保留论坛右栏详情状态', (WidgetTester tester) async {
    _setSurfaceSize(tester, const Size(1280, 800));
    final _MockForumReadRepository forumRepository = _MockForumReadRepository();
    final Uri boardUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=41&mobile=2',
    );
    final forum_domain.ForumBoardNode board = forum_domain.ForumBoardNode(
      id: 41,
      name: '保活版块',
      uri: boardUri,
    );
    when(() => forumRepository.loadIndex()).thenAnswer(
      (_) async => forum_domain.ForumBoardIndex(
        sections: <forum_domain.ForumSection>[
          forum_domain.ForumSection(
            id: 1,
            name: '测试分区',
            boards: <forum_domain.ForumBoardNode>[board],
          ),
        ],
        unsectionedBoards: const <forum_domain.ForumBoardNode>[],
        viewer: const forum_domain.ForumViewer(userId: 42),
        navigation: const forum_domain.ForumNavigationLinks(),
        sourceUri: Uri.parse('https://bbs.yamibo.com/forum.php?mobile=2'),
      ),
    );
    when(
      () => forumRepository.loadBoard(
        boardUri,
        expectedBoardId: 41,
      ),
    ).thenAnswer(
      (_) async => forum_domain.ForumBoardPage(
        board: board,
        threads: const <forum_domain.ForumThreadSummary>[],
        filters: const <forum_domain.ForumRouteOption>[],
        cursor: forum_domain.ForumPageCursor(
          currentPage: 1,
          totalPages: 1,
          sourceUri: boardUri,
        ),
      ),
    );

    await tester.pumpWidget(
      _homeApp(
        settingsRepository,
        downloadManager,
        libraryRepository,
        cacheMaintenanceRepository,
        authState: const AuthState.authenticated('测试账号', userId: 42),
        forumRepository: forumRepository,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('论坛'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('forum-board-41')));
    await tester.pumpAndSettle();
    verify(
      () => forumRepository.loadBoard(boardUri, expectedBoardId: 41),
    ).called(1);
    clearInteractions(forumRepository);

    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.tap(find.text('论坛'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('forum-detail-board-41')),
      findsOneWidget,
    );
    verifyNever(
      () => forumRepository.loadBoard(boardUri, expectedBoardId: 41),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('横屏论坛从版块连续在右栏打开公告原生页', (WidgetTester tester) async {
    _setSurfaceSize(tester, const Size(1280, 800));
    final _MockForumReadRepository forumRepository = _MockForumReadRepository();
    final Uri boardUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=41&mobile=2',
    );
    final Uri announcementUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=announcement&id=9',
    );
    final forum_domain.ForumBoardNode board = forum_domain.ForumBoardNode(
      id: 41,
      name: '测试版块',
      uri: boardUri,
    );
    when(() => forumRepository.loadIndex()).thenAnswer(
      (_) async => forum_domain.ForumBoardIndex(
        sections: <forum_domain.ForumSection>[
          forum_domain.ForumSection(
            id: 1,
            name: '测试分区',
            boards: <forum_domain.ForumBoardNode>[board],
          ),
        ],
        unsectionedBoards: const <forum_domain.ForumBoardNode>[],
        viewer: const forum_domain.ForumViewer(userId: 42),
        navigation: const forum_domain.ForumNavigationLinks(),
        sourceUri: Uri.parse('https://bbs.yamibo.com/forum.php?mobile=2'),
      ),
    );
    when(
      () => forumRepository.loadBoard(
        any(),
        expectedBoardId: any(named: 'expectedBoardId'),
      ),
    ).thenAnswer(
      (_) async => forum_domain.ForumBoardPage(
        board: board,
        threads: <forum_domain.ForumThreadSummary>[
          forum_domain.ForumThreadSummary(
            id: 9,
            boardId: 41,
            title: '站务公告',
            uri: announcementUri,
            targetKind: forum_domain.ForumThreadTargetKind.announcement,
          ),
        ],
        filters: const <forum_domain.ForumRouteOption>[],
        cursor: forum_domain.ForumPageCursor(
          currentPage: 1,
          totalPages: 1,
          sourceUri: boardUri,
        ),
      ),
    );
    when(
      () => forumRepository.loadAnnouncement(
        any(),
        expectedAnnouncementId: any(named: 'expectedAnnouncementId'),
      ),
    ).thenAnswer(
      (_) async => ForumAnnouncement(
        id: 9,
        title: '站务公告',
        metadataLabel: '2026-08-13',
        contentBlocks: const <forum_domain.ForumPostContentBlock>[
          forum_domain.ForumPostParagraphBlock(
            inlines: <forum_domain.ForumPostInline>[
              forum_domain.ForumPostTextInline(text: '公告原生正文'),
            ],
          ),
        ],
        messageHtml: '<p>公告原生正文</p>',
        sourceUri: announcementUri,
      ),
    );

    await tester.pumpWidget(
      _homeApp(
        settingsRepository,
        downloadManager,
        libraryRepository,
        cacheMaintenanceRepository,
        authState: const AuthState.authenticated('测试账号', userId: 42),
        forumRepository: forumRepository,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('论坛'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('forum-board-41')));
    await tester.pumpAndSettle();

    expect(find.byType(ForumBoardPage), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('forum-announcement-9')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ForumAnnouncementPage), findsOneWidget);
    expect(find.text('公告原生正文'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('forum-detail-announcement-9')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('横屏全部收藏把异构目标原生页接到右栏', (WidgetTester tester) async {
    _setSurfaceSize(tester, const Size(1280, 800));
    final _MockFavoriteTargetRepository targetRepository =
        _MockFavoriteTargetRepository();
    final RawFavoriteItem item = RawFavoriteItem(
      categoryKey: 'album',
      title: '相册收藏',
      targetKind: RawFavoriteTargetKind.album,
      targetUri: Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=space&do=album&uid=7&id=92&mobile=2',
      ),
      userId: 7,
      contentId: 92,
    );
    when(() => targetRepository.load(item)).thenAnswer(
      (_) async => FavoriteAlbum(
        albumId: 92,
        ownerUserId: 7,
        title: '相册标题',
        description: '相册说明',
        images: const <FavoriteAlbumImage>[],
        sourceUri: item.targetUri!,
      ),
    );
    await tester.pumpWidget(
      _homeApp(
        settingsRepository,
        downloadManager,
        libraryRepository,
        cacheMaintenanceRepository,
        authState: const AuthState.unauthenticated(),
        favoriteTargetRepository: targetRepository,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('收藏'));
    await tester.pump();

    final FavoritesHomePage favorites = tester.widget<FavoritesHomePage>(
      find.byType(FavoritesHomePage),
    );
    favorites.onOpenFavoriteTarget!(item);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FavoriteTargetPage), findsOneWidget);
    expect(
      find.byKey(ValueKey<String>('favorite-target-${item.identityKey}')),
      findsOneWidget,
    );
    expect(find.text('相册标题'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('横屏用户空间收藏在右栏打开原生资料页', (WidgetTester tester) async {
    _setSurfaceSize(tester, const Size(1280, 800));
    final _MockCommunityRepository communityRepository =
        _MockCommunityRepository();
    final Uri profileUri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&uid=77&mobile=2',
    );
    final RawFavoriteItem item = RawFavoriteItem(
      favoriteId: 75,
      categoryKey: 'space',
      title: '用户收藏',
      targetKind: RawFavoriteTargetKind.userSpace,
      targetUri: profileUri,
      userId: 77,
    );
    when(
      () => communityRepository.loadProfile(
        profileUri,
        expectedProfileUserId: 77,
      ),
    ).thenAnswer(
      (_) async => CommunityProfile(
        userId: 77,
        username: '资料用户',
        sourceUri: profileUri,
        entries: const <CommunityProfileEntry>[],
        details: const <String>['uid 77'],
      ),
    );
    await tester.pumpWidget(
      _homeApp(
        settingsRepository,
        downloadManager,
        libraryRepository,
        cacheMaintenanceRepository,
        authState: const AuthState.unauthenticated(),
        communityRepository: communityRepository,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('收藏'));
    await tester.pump();

    final FavoritesHomePage favorites = tester.widget<FavoritesHomePage>(
      find.byType(FavoritesHomePage),
    );
    favorites.onOpenFavoriteTarget!(item);
    await tester.pumpAndSettle();

    expect(find.byType(CommunityProfileScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('favorite-profile-77')),
      findsOneWidget,
    );
    expect(find.text('资料用户'), findsNWidgets(2));
    verify(
      () => communityRepository.loadProfile(
        profileUri,
        expectedProfileUserId: 77,
      ),
    ).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('竖屏平板使用底栏并全页打开二级页面', (WidgetTester tester) async {
    _setSurfaceSize(tester, const Size(800, 1280));
    await tester.pumpWidget(
      _homeApp(
        settingsRepository,
        downloadManager,
        libraryRepository,
        cacheMaintenanceRepository,
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    await tester.tap(find.byIcon(Remix.user_3_line));
    await tester.pump();
    await tester.tap(find.text('更多设置'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfilePage), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

const WorkCatalogPage _emptyCatalogPage = WorkCatalogPage(
  works: <Work>[],
  sourceThreads: <SourceThread>[],
  categories: <ForumCategory>[],
  pages: <ForumBoard, ForumCatalogPage>{},
);

Widget _homeApp(
  AppSettingsRepository settingsRepository,
  DownloadManager downloadManager,
  ForumLibraryRepository libraryRepository,
  CacheMaintenanceRepository cacheMaintenanceRepository, {
  AuthState authState = const AuthState.authenticated('测试账号'),
  WidgetBuilder? forumBuilder,
  Future<void> Function()? onRefreshForum,
  ForumReadRepository? forumRepository,
  CommunityRepository? communityRepository,
  FavoriteTargetRepository? favoriteTargetRepository,
}) {
  return ProviderScope(
    overrides: [
      appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      downloadManagerProvider.overrideWithValue(downloadManager),
      forumLibraryRepositoryProvider.overrideWithValue(libraryRepository),
      cacheMaintenanceRepositoryProvider.overrideWithValue(
        cacheMaintenanceRepository,
      ),
      currentUserAvatarUriProvider.overrideWithValue(null),
      if (forumRepository != null)
        forumReadRepositoryProvider.overrideWithValue(forumRepository),
      if (communityRepository != null)
        communityRepositoryProvider.overrideWithValue(communityRepository),
      if (favoriteTargetRepository != null)
        favoriteTargetRepositoryProvider.overrideWithValue(
          favoriteTargetRepository,
        ),
    ],
    child: MaterialApp(
      home: HomeShell(
        authState: authState,
        forumBuilder: forumBuilder,
        onRefreshForum: onRefreshForum,
      ),
    ),
  );
}

void _setSurfaceSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

class _StatefulForumProbe extends StatefulWidget {
  const _StatefulForumProbe();

  @override
  State<_StatefulForumProbe> createState() => _StatefulForumProbeState();
}

class _StatefulForumProbeState extends State<_StatefulForumProbe> {
  int _value = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          Text('论坛状态 $_value'),
          TextButton(
            key: const Key('forum-probe-increment'),
            onPressed: () => setState(() => _value++),
            child: const Text('累加'),
          ),
        ],
      ),
    );
  }
}
