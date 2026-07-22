import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:remixicon/remixicon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/downloads/application/download_manager.dart';
import 'package:x300/features/home/presentation/home_shell.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/profile/presentation/profile_page.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';
import 'package:x300/features/settings/presentation/settings_page.dart';

class _MockDownloadManager extends Mock implements DownloadManager
{
}

class _MockForumLibraryRepository extends Mock
    implements ForumLibraryRepository
{
}

class _MockCacheMaintenanceRepository extends Mock
    implements CacheMaintenanceRepository
{
}

void main()
{
    late AppSettingsRepository settingsRepository;
    late _MockDownloadManager downloadManager;
    late _MockForumLibraryRepository libraryRepository;
    late _MockCacheMaintenanceRepository cacheMaintenanceRepository;

    setUp(() async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        settingsRepository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        downloadManager = _MockDownloadManager();
        libraryRepository = _MockForumLibraryRepository();
        cacheMaintenanceRepository = _MockCacheMaintenanceRepository();
        when(() => downloadManager.start()).thenAnswer((_) async {});
        when(
            () => cacheMaintenanceRepository.measureUsage(),
        ).thenAnswer(
            (_) async => const CacheUsageSnapshot(
                temporaryBytes: 0,
                coverBytes: 0,
            ),
        );
        for (final (LibraryKind, NovelSourceFilter) query in <
            (LibraryKind, NovelSourceFilter)
        >[
            (LibraryKind.comic, NovelSourceFilter.all),
            (LibraryKind.novel, NovelSourceFilter.lightNovel),
            (LibraryKind.novel, NovelSourceFilter.literature),
        ])
        {
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

    test('主页仅在足够宽的横屏窗口启用双栏布局', ()
    {
        expect(usesWideHomeLayout(const Size(1280, 800)), isTrue);
        expect(usesWideHomeLayout(const Size(720, 600)), isTrue);
        expect(usesWideHomeLayout(const Size(800, 1280)), isFalse);
        expect(usesWideHomeLayout(const Size(719, 600)), isFalse);
        expect(usesWideHomeLayout(const Size(720, 720)), isFalse);
    });

    testWidgets('横屏个人页在右侧打开二级页面', (
        WidgetTester tester,
    ) async
    {
        _setSurfaceSize(tester, const Size(1280, 800));
        await tester.pumpWidget(_homeApp(
            settingsRepository,
            downloadManager,
            libraryRepository,
            cacheMaintenanceRepository,
        ));
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

    testWidgets('竖屏平板使用底栏并全页打开二级页面', (
        WidgetTester tester,
    ) async
    {
        _setSurfaceSize(tester, const Size(800, 1280));
        await tester.pumpWidget(_homeApp(
            settingsRepository,
            downloadManager,
            libraryRepository,
            cacheMaintenanceRepository,
        ));
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
    CacheMaintenanceRepository cacheMaintenanceRepository,
)
{
    return ProviderScope(
        overrides: [
            appSettingsRepositoryProvider.overrideWithValue(
                settingsRepository,
            ),
            downloadManagerProvider.overrideWithValue(downloadManager),
            forumLibraryRepositoryProvider.overrideWithValue(
                libraryRepository,
            ),
            cacheMaintenanceRepositoryProvider.overrideWithValue(
                cacheMaintenanceRepository,
            ),
            currentUserAvatarUriProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
            home: HomeShell(username: '测试账号'),
        ),
    );
}

void _setSurfaceSize(WidgetTester tester, Size size)
{
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
}
