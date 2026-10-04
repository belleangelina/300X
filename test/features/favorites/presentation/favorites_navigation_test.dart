import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:remixicon/remixicon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/app/app_theme.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/favorites/data/favorite_cache_repository.dart';
import 'package:x300/features/favorites/data/forum_favorite_repository.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/favorites/presentation/cloud_favorites_page.dart';
import 'package:x300/features/home/presentation/home_shell.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/work_detail_page.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';
import 'package:x300/features/settings/domain/app_settings.dart';
import 'package:x300/shared/presentation/catalog_controls.dart';
import 'package:x300/shared/presentation/tab_app_bar.dart';

class _Client extends Mock implements ForumClient {}

class _Maintenance extends Mock implements CacheMaintenanceRepository {}

class _Catalog extends Fake implements ForumLibraryRepository {
  @override
  Future<WorkCatalogPage> loadCatalog({
    required LibraryKind kind,
    required CatalogSection section,
    NovelSourceFilter novelSource = NovelSourceFilter.all,
    int page = 1,
    int? typeId,
  }) async => const WorkCatalogPage(
    works: <Work>[],
    sourceThreads: <SourceThread>[],
    categories: <ForumCategory>[],
    pages: <ForumBoard, ForumCatalogPage>{},
  );
}

class _Covers extends Fake implements CoverRepository {
  @override
  Uri? peek(CoverRequest request) => null;

  @override
  Future<Uri?> resolve(
    Work work, {
    bool finalize = false,
    int? entryTid,
    bool force = false,
  }) async => null;
}

// Only forum transport is synthetic. Aggregation, SQL cache, cards and routing
// use the production implementations, including in the native integration run.
class _Favorites extends ForumFavoriteRepository {
  _Favorites() : super(_Client());

  int initialLoads = 0;
  int nextLoads = 0;
  Completer<CloudFavoritePage>? pending;
  bool splitPages = false;
  final List<CloudFavoriteEntry> entries = <CloudFavoriteEntry>[
    ..._entries(ForumBoard.comic),
    ..._entries(ForumBoard.lightNovel),
    ..._entries(ForumBoard.literature, count: 2),
  ];

  @override
  Future<CloudFavoritePage> loadInitial() async {
    initialLoads++;
    if (pending != null) {
      return pending!.future;
    }
    return _page(
      splitPages
          ? entries
                .where(
                  (item) => item.sourceThread.board.kind == LibraryKind.comic,
                )
                .toList()
          : entries,
      first: true,
    );
  }

  @override
  Future<CloudFavoritePage> loadNext(CloudFavoritePage cursor) async {
    nextLoads++;
    return _page(
      entries
          .where((item) => item.sourceThread.board.kind == LibraryKind.novel)
          .toList(),
      first: false,
    );
  }

  CloudFavoritePage _page(
    List<CloudFavoriteEntry> values, {
    required bool first,
  }) {
    return CloudFavoritePage(
      entries: List<CloudFavoriteEntry>.of(values),
      ignoredCount: 0,
      currentPage: first ? 1 : 2,
      totalPages: splitPages ? 2 : 1,
      nextPageUri: splitPages && first
          ? Uri.parse('https://example.invalid/page-2')
          : null,
    );
  }

  @override
  Future<List<CloudFavoriteRecord>> findForWork(Work work) async => entries
      .where(
        (item) => work.sourceThreads.any(
          (thread) => thread.tid == item.record.threadId,
        ),
      )
      .map((item) => item.record)
      .toList();
}

List<CloudFavoriteEntry> _entries(ForumBoard board, {int count = 20}) {
  return List<CloudFavoriteEntry>.generate(count, (int index) {
    final int tid = board.fid * 1000 + index;
    final String label = board == ForumBoard.comic
        ? '漫画'
        : board == ForumBoard.lightNovel
        ? '轻小说'
        : '文学区';
    final String suffix = String.fromCharCode(65 + index);
    final String title = '合成$label作品$suffix';
    final Uri uri = Uri.parse('https://example.invalid/thread-$tid');
    return CloudFavoriteEntry(
      record: CloudFavoriteRecord(
        favoriteId: tid,
        threadId: tid,
        title: title,
        threadUri: uri,
        deleteDialogUri: Uri.parse('https://example.invalid/favorite-$tid'),
      ),
      sourceThread: SourceThread(
        tid: tid,
        board: board,
        title: title,
        uri: uri,
      ),
    );
  });
}

void main() => registerFavoritesNavigationTests();

void registerFavoritesNavigationTests({bool captureScreenshots = false}) {
  late AppDatabase database;
  late AppSettingsRepository settings;
  late _Favorites favorites;
  late _Maintenance maintenance;
  final GlobalKey captureKey = GlobalKey();

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = AppSettingsRepository(await SharedPreferences.getInstance());
    await settings.save(const AppSettings(automaticUpdateChecks: false));
    favorites = _Favorites();
    maintenance = _Maintenance();
    when(() => maintenance.maintainAutomatically()).thenAnswer((_) async {});
  });

  tearDown(() async {
    await database.close();
  });

  Widget app({
    AuthState auth = const AuthState.authenticated('合成测试账号'),
    ThemeData? theme,
    bool shell = true,
    VoidCallback? onLogin,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        appSettingsRepositoryProvider.overrideWithValue(settings),
        forumFavoriteRepositoryProvider.overrideWithValue(favorites),
        forumLibraryRepositoryProvider.overrideWithValue(_Catalog()),
        coverRepositoryProvider.overrideWithValue(_Covers()),
        cacheMaintenanceRepositoryProvider.overrideWithValue(maintenance),
        currentUserAvatarUriProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        builder: (context, child) =>
            RepaintBoundary(key: captureKey, child: child!),
        home: shell
            ? HomeShell(authState: auth)
            : CloudFavoritesPage(authState: auth, onLogin: onLogin ?? () {}),
      ),
    );
  }

  Future<void> snapshot(WidgetTester tester, String name) async {
    if (!captureScreenshots) {
      return;
    }
    await tester.pumpAndSettle();
    final RenderRepaintBoundary boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.artifacts/validation/screenshots');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  testWidgets('收藏底栏、三个页签、类型筛选、视图记忆和宽窄屏原始详情', (tester) async {
    _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .items,
      hasLength(4),
    );
    expect(favorites.initialLoads, 0);

    await tester.tap(find.byIcon(Remix.heart_line));
    await tester.pumpAndSettle();
    expect(find.byType(TabAppBar), findsOneWidget);
    expect(find.widgetWithText(Tab, '漫画'), findsOneWidget);
    expect(find.widgetWithText(Tab, '小说'), findsOneWidget);
    expect(find.widgetWithText(Tab, '原始收藏'), findsOneWidget);
    expect(favorites.initialLoads, 1);
    expect(_visibleKinds(tester), everyElement(LibraryKind.comic));
    expect(find.byType(CatalogControlBar), findsNothing);
    expect(find.text('刷新'), findsNothing);
    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TabAppBar),
        matching: find.byKey(
          const ValueKey<String>('favorite-view-toggle-0'),
        ),
      ),
      findsOneWidget,
    );
    await snapshot(tester, 'favorites-comic-light');

    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    final double comicOffset = _position(tester).pixels;
    expect(comicOffset, greaterThan(0));
    await tester.tap(find.widgetWithText(Tab, '小说'));
    await tester.pumpAndSettle();
    expect(_visibleKinds(tester), everyElement(LibraryKind.novel));
    expect(find.byType(CatalogControlBar), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('favorite-view-toggle-1')),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.view_list_outlined), findsOneWidget);
    expect(find.byType(WorkGridCard), findsWidgets);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pumpAndSettle();
    final double novelGridOffset = _position(tester, grid: true).pixels;
    expect(novelGridOffset, greaterThan(0));
    await tester.tap(find.widgetWithText(Tab, '漫画'));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(comicOffset, 1));
    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('favorite-view-toggle-0')),
    );
    await tester.pumpAndSettle();
    await snapshot(tester, 'favorites-comic-grid-light');
    await tester.tap(
      find.byKey(const ValueKey<String>('favorite-view-toggle-0')),
    );
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(comicOffset, 1));
    await tester.tap(find.widgetWithText(Tab, '小说'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkGridCard), findsWidgets);
    expect(_position(tester, grid: true).pixels, closeTo(novelGridOffset, 1));
    await tester.pumpWidget(app(theme: AppTheme.dark));
    await tester.pumpAndSettle();
    await snapshot(tester, 'favorites-novel-grid-dark');

    await tester.tap(find.widgetWithText(Tab, '原始收藏'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('favorite-kind-filter')), findsOneWidget);
    expect(find.byType(CatalogControlBar), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_outlined), findsNothing);
    expect(find.byIcon(Icons.view_list_outlined), findsNothing);
    await _filter(tester, '小说');
    expect(_visibleKinds(tester), everyElement(LibraryKind.novel));
    expect(find.text('合成漫画作品A'), findsNothing);
    await _filter(tester, '漫画');
    expect(_visibleKinds(tester), everyElement(LibraryKind.comic));
    await _filter(tester, '全部');
    expect(favorites.initialLoads, 1);
    await tester.tap(
      find.byKey(const ValueKey<String>('favorite-view-toggle-2')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorkGridCard), findsWidgets);
    await tester.pumpWidget(app(theme: AppTheme.dark));
    await tester.pumpAndSettle();
    await snapshot(tester, 'favorites-raw-grid-dark');

    // Visiting other primary destinations keeps the selected favorite tab,
    // filter and view mode, and does not start another complete sync.
    await tester.tap(find.byIcon(Remix.user_3_line));
    await tester.pumpAndSettle();
    expect(find.text('漫画收藏'), findsNothing);
    expect(find.text('小说收藏'), findsNothing);
    await tester.tap(find.byIcon(Remix.heart_line));
    await tester.pumpAndSettle();
    expect(find.byType(WorkGridCard), findsWidgets);
    expect(favorites.initialLoads, 1);

    _setSize(tester, const Size(1280, 800));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).destinations,
      hasLength(4),
    );
    await tester.tap(find.byType(WorkGridCard).first);
    await tester.pumpAndSettle();
    WorkDetailPage detail = tester.widget(find.byType(WorkDetailPage));
    expect(detail.embedded, isTrue);
    expect(detail.rawSourceMode, isTrue);
    expect(detail.resolveOnOpen, isFalse);
    await snapshot(tester, 'favorites-wide-raw-detail');

    _setSize(tester, const Size(390, 844));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WorkGridCard).first);
    await tester.pumpAndSettle();
    detail = tester.widget(find.byType(WorkDetailPage));
    expect(detail.embedded, isFalse);
    expect(detail.rawSourceMode, isTrue);
    expect(detail.resolveOnOpen, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(WorkGridCard), findsWidgets);
    expect(favorites.initialLoads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('漫画和小说空收藏通过下拉刷新且不显示操作栏', (tester) async {
    _setSize(tester, const Size(390, 844));
    favorites.entries.clear();
    await tester.pumpWidget(app(shell: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂无漫画收藏'), findsOneWidget);
    expect(find.byType(CatalogControlBar), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(favorites.initialLoads, 2);

    await tester.tap(find.widgetWithText(Tab, '小说'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('favorite-view-toggle-1')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('暂无小说收藏'), findsOneWidget);
    expect(find.byIcon(Icons.view_list_outlined), findsOneWidget);
    expect(find.byType(CatalogControlBar), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(favorites.initialLoads, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('目标收藏类型仅在后续分页出现时继续加载', (tester) async {
    _setSize(tester, const Size(390, 844));
    favorites.splitPages = true;
    await tester.pumpWidget(app(shell: false));
    await tester.pumpAndSettle();
    expect(favorites.nextLoads, 0);
    await tester.tap(find.widgetWithText(Tab, '小说'));
    await tester.pumpAndSettle();
    expect(favorites.nextLoads, 1);
    expect(_visibleKinds(tester), everyElement(LibraryKind.novel));
    expect(find.text('合成轻小说作品A'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('未登录保留收藏页签和筛选并在登录后自动同步', (tester) async {
    _setSize(tester, const Size(390, 844));
    int logins = 0;
    await tester.pumpWidget(
      app(
        shell: false,
        auth: const AuthState.unauthenticated(),
        onLogin: () => logins++,
      ),
    );
    await tester.pumpAndSettle();
    expect(favorites.initialLoads, 0);
    expect(find.text('登录后查看收藏'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, '原始收藏'));
    await tester.pumpAndSettle();
    await _filter(tester, '小说');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(logins, 1);
    await tester.pumpWidget(app(shell: false));
    await tester.pumpAndSettle();
    expect(favorites.initialLoads, 1);
    expect(_visibleKinds(tester), everyElement(LibraryKind.novel));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('退出登录后丢弃旧账号仍在进行的收藏响应', (tester) async {
    _setSize(tester, const Size(390, 844));
    favorites.pending = Completer<CloudFavoritePage>();
    await tester.pumpWidget(app(shell: false));
    await tester.pump();
    await tester.pumpWidget(
      app(shell: false, auth: const AuthState.unauthenticated()),
    );
    favorites.pending!.complete(
      CloudFavoritePage(
        entries: favorites.entries,
        ignoredCount: 0,
        currentPage: 1,
        totalPages: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorkListTile), findsNothing);
    expect(find.text('登录后查看收藏'), findsOneWidget);
    expect(await FavoriteCacheRepository(database).load(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Iterable<LibraryKind> _visibleKinds(WidgetTester tester) => tester
    .widgetList<WorkListTile>(find.byType(WorkListTile))
    .map((tile) => tile.work.kind);

ScrollPosition _position(WidgetTester tester, {bool grid = false}) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(grid ? CustomScrollView : ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> _filter(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('favorite-kind-filter')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, label));
  await tester.pumpAndSettle();
}
