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
import 'package:x300/features/settings/presentation/settings_page.dart';
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
  bool failLoads = false;
  final List<CloudFavoriteEntry> entries = <CloudFavoriteEntry>[
    ..._entries(ForumBoard.comic),
    ..._entries(ForumBoard.lightNovel),
    ..._entries(ForumBoard.literature, count: 2),
  ];

  @override
  Future<CloudFavoritePage> loadInitial() async {
    initialLoads++;
    if (failLoads) throw StateError('合成离线状态');
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
    final String suffix = index < 26
        ? String.fromCharCode(65 + index)
        : '${String.fromCharCode(64 + index ~/ 26)}${String.fromCharCode(65 + index % 26)}';
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
        typeId: index.isEven ? 1 : 2,
        typeName: index.isEven ? '分类甲' : '分类乙',
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
    when(maintenance.measureUsage).thenAnswer(
      (_) async => const CacheUsageSnapshot(
        temporaryBytes: 2048,
        coverBytes: 1024 * 1024,
      ),
    );
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

  testWidgets('个人页单卡片、无头像说明和设置简短文案可交互', (tester) async {
    _setSize(tester, const Size(390, 844));
    for (final ThemeData theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(app(theme: theme));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      final Finder board = find.byKey(const Key('profile-board'));
      expect(board, findsOneWidget);
      expect(
        find.descendant(of: board, matching: find.byType(ListTile)),
        findsNWidgets(6),
      );
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, '合成测试账号'))
            .subtitle,
        isNull,
      );
      final String brightness = theme.brightness.name;
      await snapshot(tester, 'profile-board-$brightness');
      await tester.tap(find.text('显示主题'));
      await tester.pumpAndSettle();
      expect(find.text('设置主题'), findsOneWidget);
      Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('更多设置'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.textContaining('当前大小：约 2.0 KB'), findsOneWidget);
      expect(find.textContaining('搜索、收藏及正文图片'), findsOneWidget);
      expect(find.textContaining('封面可重新加载'), findsOneWidget);
      expect(find.text('下次打开作品时重建'), findsOneWidget);
      expect(find.text('关闭后使用默认字号'), findsOneWidget);
      expect(find.text('每 24 小时最多检查一次'), findsOneWidget);
      expect(find.text('GitCode 官方镜像'), findsOneWidget);
      await snapshot(tester, 'settings-general-$brightness');
      final Finder textScale = find.widgetWithText(SwitchListTile, '字体大小跟随系统');
      final bool previous = tester.widget<SwitchListTile>(textScale).value;
      await tester.tap(textScale);
      await tester.pumpAndSettle();
      expect(settings.load().useSystemTextScale, !previous);
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, '清除临时缓存'),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('阅读历史和离线下载不会被删除'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(board, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('收藏双页签、操作栏、独立布局与原帖详情可交互', (tester) async {
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
    expect(find.widgetWithText(Tab, '漫画收藏'), findsOneWidget);
    expect(find.widgetWithText(Tab, '小说收藏'), findsOneWidget);
    expect(find.widgetWithText(Tab, '全部'), findsNothing);
    expect(find.byType(CatalogControlBar), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_outlined), findsNothing);
    expect(
      find.descendant(
        of: find.byType(TabAppBar),
        matching: find.byKey(const Key('favorite-view-toggle-0')),
      ),
      findsNothing,
    );
    expect(favorites.initialLoads, 1);
    expect(_visibleKinds(tester), everyElement(LibraryKind.comic));
    await snapshot(tester, 'favorites-comic-controls-light');

    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    final double comicOffset = _position(tester).pixels;
    expect(comicOffset, greaterThan(0));
    await tester.tap(find.widgetWithText(Tab, '小说收藏'));
    await tester.pumpAndSettle();
    expect(_visibleKinds(tester), everyElement(LibraryKind.novel));
    await tester.tap(find.byKey(const Key('favorite-view-toggle-1')));
    await tester.pumpAndSettle();
    expect(find.text('网格'), findsOneWidget);
    expect(find.byType(WorkGridCard), findsWidgets);
    expect(find.byIcon(Icons.favorite), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pumpAndSettle();
    final double novelOffset = _position(tester, grid: true).pixels;
    expect(novelOffset, greaterThan(0));
    await tester.tap(find.widgetWithText(Tab, '漫画收藏'));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(comicOffset, 1));
    expect(find.text('列表'), findsOneWidget);
    await tester.tap(find.byKey(const Key('favorite-view-toggle-0')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsNothing);
    await snapshot(tester, 'favorites-comic-grid-light');
    await tester.tap(find.byKey(const Key('favorite-view-toggle-0')));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(comicOffset, 1));
    await tester.tap(find.widgetWithText(Tab, '小说收藏'));
    await tester.pumpAndSettle();
    expect(_position(tester, grid: true).pixels, closeTo(novelOffset, 1));
    await tester.pumpWidget(app(theme: AppTheme.dark));
    await tester.pumpAndSettle();
    await snapshot(tester, 'favorites-novel-grid-dark');
    await tester.tap(find.byKey(const Key('favorite-mode-toggle-1')));
    await tester.pumpAndSettle();
    expect(find.text('原帖'), findsOneWidget);
    expect(find.byType(WorkGridCard), findsWidgets);
    expect(
      tester
          .widgetList<WorkGridCard>(find.byType(WorkGridCard))
          .map((card) => card.work.kind),
      everyElement(LibraryKind.novel),
    );
    await tester.tap(find.byKey(const Key('favorite-view-toggle-1')));
    await tester.pumpAndSettle();
    expect(_visibleKinds(tester), everyElement(LibraryKind.novel));
    final double rawOffset = _position(tester).pixels;
    await snapshot(tester, 'favorites-novel-original-list-dark');
    await tester.tap(find.byIcon(Remix.user_3_line));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Remix.heart_line));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(rawOffset, 1));
    expect(find.text('原帖'), findsOneWidget);
    expect(favorites.initialLoads, 1);

    _setSize(tester, const Size(1280, 800));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WorkListTile).hitTestable().first);
    await tester.pumpAndSettle();
    WorkDetailPage detail = tester.widget(find.byType(WorkDetailPage));
    expect(detail.embedded, isTrue);
    expect(detail.rawSourceMode, isTrue);
    expect(detail.resolveOnOpen, isFalse);
    await snapshot(tester, 'favorites-wide-original-detail');
    _setSize(tester, const Size(390, 844));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WorkListTile).hitTestable().first);
    await tester.pumpAndSettle();
    detail = tester.widget(find.byType(WorkDetailPage));
    expect(detail.embedded, isFalse);
    expect(detail.rawSourceMode, isTrue);
    expect(detail.resolveOnOpen, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(favorites.initialLoads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('两个空收藏页签保留操作栏并支持下拉刷新', (tester) async {
    _setSize(tester, const Size(390, 844));
    favorites.entries.clear();
    await tester.pumpWidget(app(shell: false));
    await tester.pumpAndSettle();
    expect(find.text('暂无漫画收藏'), findsOneWidget);
    expect(find.byType(CatalogControlBar), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(favorites.initialLoads, 2);
    await tester.tap(find.widgetWithText(Tab, '小说收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-view-toggle-1')));
    await tester.pumpAndSettle();
    expect(find.text('暂无小说收藏'), findsOneWidget);
    expect(find.text('网格'), findsOneWidget);
    await tester.tap(find.byKey(const Key('favorite-mode-toggle-1')));
    await tester.pumpAndSettle();
    expect(find.text('原帖'), findsOneWidget);
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
    expect(favorites.nextLoads, 1);
    await tester.tap(find.widgetWithText(Tab, '小说收藏'));
    await tester.pumpAndSettle();
    expect(favorites.nextLoads, 1);
    expect(_visibleKinds(tester), everyElement(LibraryKind.novel));
    expect(find.text('合成轻小说作品A'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('未登录保留双页签和操作栏，登录后恢复当前原帖模式', (tester) async {
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
    expect(find.byType(CatalogControlBar), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, '小说收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-mode-toggle-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(logins, 1);
    await tester.pumpWidget(app(shell: false));
    await tester.pumpAndSettle();
    expect(favorites.initialLoads, 1);
    expect(find.byType(CatalogControlBar), findsOneWidget);
    expect(find.text('原帖'), findsOneWidget);
    expect(_visibleKinds(tester), everyElement(LibraryKind.novel));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('分类与跳页只作用于当前类型，范围和输入校验与主页一致', (tester) async {
    _setSize(tester, const Size(390, 844));
    favorites.entries.addAll(_entries(ForumBoard.comic, count: 45).skip(20));
    await tester.pumpWidget(app(shell: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-page-jump-0')));
    await tester.pumpAndSettle();
    expect(find.text('已加载第 1 页 / 共 3 页'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '4');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '跳转'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0);
    expect(find.text('合成漫画作品U'), findsWidgets);
    expect(find.text('合成漫画作品A'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -2200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-page-jump-0')));
    await tester.pumpAndSettle();
    expect(find.text('已加载第 2–3 页 / 共 3 页'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
      '2',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-category-filter-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类甲').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<WorkListTile>(find.byType(WorkListTile))
          .map((tile) => tile.work.sourceThreads.first.typeId),
      everyElement(1),
    );
    await tester.tap(find.byKey(const Key('favorite-page-jump-0')));
    await tester.pumpAndSettle();
    expect(find.text('已加载第 1 页 / 共 2 页'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '小说收藏'));
    await tester.pumpAndSettle();
    expect(find.text('全部'), findsOneWidget);
    expect(_visibleKinds(tester), everyElement(LibraryKind.novel));
    await tester.tap(find.byKey(const Key('favorite-category-filter-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类甲（文学区）'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<WorkListTile>(find.byType(WorkListTile))
          .map((tile) => tile.work.primaryBoard),
      everyElement(ForumBoard.literature),
    );
    await tester.tap(find.widgetWithText(Tab, '漫画收藏'));
    await tester.pumpAndSettle();
    expect(find.text('分类甲'), findsOneWidget);
    expect(favorites.initialLoads, 1);
    expect(tester.takeException(), isNull);
    await snapshot(tester, 'favorites-filtered-controls');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('离线收藏仍支持分类、原帖网格和跳页但保持只读', (tester) async {
    _setSize(tester, const Size(390, 844));
    await FavoriteCacheRepository(
      database,
    ).save(favorites.aggregateEntries(favorites.entries));
    favorites.failLoads = true;
    await tester.pumpWidget(app(shell: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前显示只读收藏缓存'), findsOneWidget);
    await tester.tap(find.byKey(const Key('favorite-category-filter-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类甲').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-mode-toggle-0')));
    await tester.pumpAndSettle();
    expect(_visibleKinds(tester), everyElement(LibraryKind.comic));
    expect(find.byTooltip('取消收藏'), findsNothing);
    await tester.tap(find.byKey(const Key('favorite-page-jump-0')));
    await tester.pumpAndSettle();
    expect(find.text('已加载第 1 页 / 共 1 页'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-view-toggle-0')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkGridCard), findsWidgets);
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.text('原帖'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await snapshot(tester, 'favorites-offline-original-grid');
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
