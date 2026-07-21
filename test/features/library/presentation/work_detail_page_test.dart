import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/features/downloads/data/download_repository.dart';
import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/favorites/data/forum_favorite_repository.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/history/data/reading_history_repository.dart';
import 'package:x300/features/history/domain/reading_history_models.dart';
import 'package:x300/features/library/application/work_index_coordinator.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';
import 'package:x300/features/library/presentation/work_detail_page.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/reader/presentation/chapter_reader_page.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';

class _MockForumLibraryRepository extends Mock
        implements ForumLibraryRepository {}

class _MockCoverRepository extends Mock implements CoverRepository {}

class _MockForumFavoriteRepository extends Mock
        implements ForumFavoriteRepository {}

class _MockReadingHistoryRepository extends Mock
        implements ReadingHistoryRepository {}

class _MockDownloadRepository extends Mock implements DownloadRepository {}

class _MockWorkIndexCoordinator extends Mock implements WorkIndexCoordinator {}

void main()
{
    late Work work;
    late _MockForumLibraryRepository libraryRepository;
    late _MockCoverRepository coverRepository;
    late _MockForumFavoriteRepository favoriteRepository;
    late _MockReadingHistoryRepository historyRepository;
    late _MockDownloadRepository downloadRepository;
    late _MockWorkIndexCoordinator indexCoordinator;
    late AppSettingsRepository settingsRepository;

    setUpAll(()
    {
        registerFallbackValue(_work());
        registerFallbackValue(_work().sourceThreads.first);
        registerFallbackValue(_work().chapters.first);
        registerFallbackValue(ForumBoard.comic);
        registerFallbackValue((String message) {});
        registerFallbackValue(WorkIndexCancellation());
    });

    setUp(() async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        settingsRepository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        work = _work();
        libraryRepository = _MockForumLibraryRepository();
        coverRepository = _MockCoverRepository();
        favoriteRepository = _MockForumFavoriteRepository();
        historyRepository = _MockReadingHistoryRepository();
        downloadRepository = _MockDownloadRepository();
        indexCoordinator = _MockWorkIndexCoordinator();
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
            ),
        ).thenAnswer((_) async => _page());
        when(() => coverRepository.resolve(any())).thenAnswer((_) async => null);
        when(
            () => coverRepository.resolve(
                any(),
                finalize: any(named: 'finalize'),
                entryTid: any(named: 'entryTid'),
            ),
        ).thenAnswer((_) async => null);
        when(
            () => coverRepository.resolve(
                any(),
                finalize: any(named: 'finalize'),
                entryTid: any(named: 'entryTid'),
                force: any(named: 'force'),
            ),
        ).thenAnswer((_) async => null);
        when(
            () => favoriteRepository.findForWork(any()),
        ).thenAnswer((_) async => const []);
        when(() => historyRepository.get(any())).thenAnswer((_) async => null);
        when(
            () => downloadRepository.listForWork(any()),
        ).thenAnswer((_) async => const <DownloadTaskEntry>[]);
        when(
            () => historyRepository.save(
                work: any(named: 'work'),
                chapter: any(named: 'chapter'),
                position: any(named: 'position'),
                progress: any(named: 'progress'),
            ),
        ).thenAnswer((_) async {});
        when(() => indexCoordinator.lookup(any())).thenAnswer((_) async => null);
    });

    testWidgets('作品操作只在底部显示一次且目录可切换列表视图', (WidgetTester tester) async
    {
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    forumLibraryRepositoryProvider.overrideWithValue(libraryRepository),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('阅读'), findsOneWidget);
        expect(find.text('收藏'), findsOneWidget);
        expect(find.text('下载'), findsOneWidget);
        expect(find.text('原帖'), findsOneWidget);
        final List<double> actionPositions = <double>[
            tester.getCenter(find.text('原帖')).dx,
            tester.getCenter(find.text('下载')).dx,
            tester.getCenter(find.text('收藏')).dx,
            tester.getCenter(find.text('阅读')).dx,
        ];
        expect(actionPositions[0], lessThan(actionPositions[1]));
        expect(actionPositions[1], lessThan(actionPositions[2]));
        expect(actionPositions[2], lessThan(actionPositions[3]));
        expect(find.byType(CircleAvatar), findsNothing);
        expect(find.text('章节目录 ·2话'), findsOneWidget);
        expect(find.text('正文'), findsOneWidget);

        await tester.tap(find.text('原帖'));
        await tester.pumpAndSettle();
        expect(find.text('打开原帖'), findsOneWidget);
        expect(find.text('即将在系统浏览器中打开原帖，是否继续？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('切换为列表视图'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('切换为倒序'));
        await tester.pumpAndSettle();

        expect(find.byType(CircleAvatar), findsNothing);
        expect(find.text('正文'), findsOneWidget);
        expect(find.text('第二话'), findsOneWidget);
        expect(
            settingsRepository.workDirectoryUsesGrid(
                'comic',
                defaultValue: true,
            ),
            isFalse,
        );
        expect(settingsRepository.workDirectoryAscending('comic'), isFalse);
        verifyNever(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
            ),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        libraryRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(
                        favoriteRepository,
                    ),
                    readingHistoryRepositoryProvider.overrideWithValue(
                        historyRepository,
                    ),
                    workIndexCoordinatorProvider.overrideWithValue(
                        indexCoordinator,
                    ),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.byTooltip('切换为网格视图'), findsOneWidget);
        expect(find.byTooltip('切换为正序'), findsOneWidget);
    });

    testWidgets('从目录点具体章节从头阅读而续读入口恢复进度', (
        WidgetTester tester,
    ) async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final AppSettingsRepository settingsRepository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        final _MockDownloadRepository downloadRepository =
                _MockDownloadRepository();
        when(
            () => downloadRepository.loadOfflineContent(any(), any()),
        ).thenAnswer((_) async => null);
        when(
            () => libraryRepository.loadChapterPage(any(), any()),
        ).thenAnswer((_) async => _page());
        final ReadingHistoryEntry history = ReadingHistoryEntry(
            work: work,
            chapterId: work.chapters.last.id,
            chapterTitle: work.chapters.last.title,
            chapterIndex: 1,
            position: 5,
            progress: 0.6,
            updatedAt: DateTime(2026, 7, 17),
        );
        when(() => historyRepository.get(any())).thenAnswer((_) async => history);

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        libraryRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(
                        favoriteRepository,
                    ),
                    readingHistoryRepositoryProvider.overrideWithValue(
                        historyRepository,
                    ),
                    downloadRepositoryProvider.overrideWithValue(
                        downloadRepository,
                    ),
                    workIndexCoordinatorProvider.overrideWithValue(
                        indexCoordinator,
                    ),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        final Finder firstChapter = find.widgetWithText(OutlinedButton, '正文');
        await tester.ensureVisible(firstChapter);
        await tester.tap(firstChapter);
        await tester.pumpAndSettle();
        ChapterReaderPage reader = tester.widget<ChapterReaderPage>(
            find.byType(ChapterReaderPage),
        );
        expect(reader.chapter.id, work.chapters.first.id);
        expect(reader.restoreProgress, isFalse);
        Navigator.of(tester.element(find.byType(ChapterReaderPage))).pop();
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('上次看到：第二话'));
        await tester.tap(find.text('上次看到：第二话'));
        await tester.pumpAndSettle();
        reader = tester.widget<ChapterReaderPage>(find.byType(ChapterReaderPage));
        expect(reader.chapter.id, work.chapters.last.id);
        expect(reader.restoreProgress, isTrue);
        Navigator.of(tester.element(find.byType(ChapterReaderPage))).pop();
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('续读'));
        await tester.tap(find.text('续读'));
        await tester.pumpAndSettle();
        reader = tester.widget<ChapterReaderPage>(find.byType(ChapterReaderPage));
        expect(reader.chapter.id, work.chapters.last.id);
        expect(reader.restoreProgress, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('详情隐藏楼主与版块并可查看各来源完整标题', (WidgetTester tester) async
    {
        work = _multiSourceWork();
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('楼主甲'), findsNothing);
        expect(find.text('漫画区'), findsNothing);
        expect(find.byTooltip('搜索原始帖子'), findsOneWidget);
        await tester.tap(find.byTooltip('查看完整标题'));
        await tester.pumpAndSettle();

        expect(find.text('完整标题'), findsOneWidget);
        expect(find.text('来源 1 · 楼主：楼主甲'), findsOneWidget);
        expect(find.text('来源 3 · 楼主：楼主乙'), findsOneWidget);
        expect(find.text('多来源漫画 第1话'), findsOneWidget);
    });

    testWidgets('列表按真实章节号显示并移除标题中的重复序号', (WidgetTester tester) async
    {
        work = _numberedSubtitleWork();
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    forumLibraryRepositoryProvider.overrideWithValue(libraryRepository),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('切换为列表视图'));
        await tester.pumpAndSettle();

        expect(find.text('第1话'), findsOneWidget);
        expect(find.text('第2话 严重的缺陷'), findsOneWidget);
        expect(find.text('第2话'), findsNothing);
        expect(find.text('严重的缺陷'), findsNothing);
        expect(find.text('第01话'), findsNothing);
        expect(find.text('02 严重的缺陷'), findsNothing);
    });

    testWidgets('列表把多话合一的小数范围显示为完整章节范围', (WidgetTester tester) async
    {
        work = _rangeChapterWork();
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('切换为列表视图'));
        await tester.pumpAndSettle();

        expect(find.text('第6.2～6.4话'), findsOneWidget);
        expect(find.text('第6.4话'), findsNothing);
    });

    testWidgets('列表把 02-03 显示为一个多话合一条目', (WidgetTester tester) async
    {
        work = _integerRangeChapterWork();
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('切换为列表视图'));
        await tester.pumpAndSettle();

        expect(find.text('第2～3话'), findsOneWidget);
        expect(find.text('第2话 3'), findsNothing);
    });

    testWidgets('无章节号条目不生成虚假序号且章节标题使用同一文本样式', (WidgetTester tester) async
    {
        work = _mixedChapterTitleWork();
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('切换为列表视图'));
        await tester.pumpAndSettle();

        expect(find.text('正文'), findsOneWidget);
        expect(find.text('番外篇'), findsOneWidget);
        expect(find.text('第2话 严重的缺陷'), findsOneWidget);
        expect(find.text('第1话'), findsNothing);
        expect(find.text('严重的缺陷'), findsNothing);
    });

    testWidgets('多楼主作品默认显示智能目录并用筛选按钮切换独立来源', (WidgetTester tester) async
    {
        work = _multiSourceWork();
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(
                    home: WorkDetailPage(work: work, initialSourceTid: 32),
                ),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('来源目录'), findsNothing);
        expect(find.text('智能聚合 ·3话'), findsOneWidget);
        expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
        expect(find.text('楼主甲 · 2话'), findsNothing);
        expect(find.text('楼主乙 · 1话'), findsNothing);
        expect(find.text('第1话'), findsOneWidget);
        expect(find.text('第2话'), findsOneWidget);
        expect(find.text('第9话'), findsOneWidget);

        await tester.tap(find.byTooltip('筛选来源'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('楼主乙 · 1话'));
        await tester.pumpAndSettle();

        expect(find.text('楼主乙 ·1话'), findsOneWidget);
        expect(find.text('第1话'), findsNothing);
        expect(find.text('第2话'), findsNothing);
        expect(find.text('第9话'), findsOneWidget);
    });

    testWidgets('小说按入口选择版本并在单行本目录中按卷分组', (WidgetTester tester) async
    {
        work = _novelEditionWork();
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(
                    home: WorkDetailPage(work: work, initialSourceTid: 62),
                ),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('单行本 ·3章'), findsOneWidget);
        expect(find.text('第一卷'), findsOneWidget);
        expect(find.text('第二卷'), findsOneWidget);
        expect(find.text('第1章 卷一开篇'), findsOneWidget);
        expect(find.text('整卷阅读'), findsOneWidget);
        expect(find.text('Episode 1'), findsNothing);

        await tester.tap(find.byTooltip('筛选来源'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('连载版 · 2章'));
        await tester.pumpAndSettle();

        expect(find.text('连载版 ·2章'), findsOneWidget);
        expect(find.text('Episode 1'), findsOneWidget);
        expect(find.text('Episode 2'), findsOneWidget);
        expect(find.text('第一卷'), findsNothing);
        expect(find.text('第二卷'), findsNothing);
    });

    testWidgets('多译者小说默认显示按版本隔离的智能目录', (WidgetTester tester) async
    {
        work = _multiSourceNovelWork();
        final Chapter downloaded = work.directories[1].chapters.first;
        when(
            () => downloadRepository.listForWork(work.id),
        ).thenAnswer((_) async => <DownloadTaskEntry>[
            DownloadTaskEntry(
                id: '${work.id}::${downloaded.id}',
                work: work,
                chapter: downloaded,
                status: DownloadStatus.completed,
                completedItems: 1,
                totalItems: 1,
                directoryPath: '',
                payloadJson: '',
                errorMessage: '',
                updatedAt: DateTime(2026, 7, 18),
            ),
        ]);
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    downloadRepositoryProvider.overrideWithValue(
                        downloadRepository,
                    ),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(
                    home: WorkDetailPage(work: work, initialSourceTid: 73),
                ),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('智能聚合 · 连载版 ·3章'), findsOneWidget);
        expect(find.text('第一章'), findsOneWidget);
        expect(find.text('第二章'), findsOneWidget);
        expect(find.text('第三章'), findsOneWidget);

        await tester.tap(find.byTooltip('筛选来源'));
        await tester.pumpAndSettle();

        expect(find.text('译者甲 · 连载版 · 2章'), findsOneWidget);
        expect(find.text('译者乙 · 连载版 · 2章'), findsOneWidget);

        await tester.tap(find.text('译者乙 · 连载版 · 2章'));
        await tester.pumpAndSettle();

        expect(find.text('第一章'), findsNothing);
        expect(find.text('第二章'), findsOneWidget);
        expect(find.text('第三章'), findsNothing);
        expect(find.text('第四章'), findsOneWidget);

        await tester.tap(find.text('下载'));
        await tester.pumpAndSettle();

        expect(find.text('选择下载章节'), findsOneWidget);
        expect(find.text('第一章'), findsNothing);
        expect(find.text('第二章'), findsNWidgets(2));
        expect(find.text('第三章'), findsNothing);
        expect(find.text('第四章'), findsNWidgets(2));
        final CheckboxListTile downloadedTile = tester.widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, '第二章'),
        );
        final CheckboxListTile availableTile = tester.widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, '第四章'),
        );
        expect(downloadedTile.value, isTrue);
        expect(downloadedTile.onChanged, isNull);
        expect(find.text('已完成'), findsOneWidget);
        expect(availableTile.value, isFalse);
        expect(availableTile.onChanged, isNotNull);
    });

    testWidgets('小说聚合结果等同单一译者时不显示重复智能目录', (WidgetTester tester) async
    {
        work = _multiSourceNovelWork(smartFill: false);
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('译者甲 · 连载版 ·2章'), findsOneWidget);
        expect(find.textContaining('智能聚合'), findsNothing);

        await tester.tap(find.byTooltip('筛选来源'));
        await tester.pumpAndSettle();

        expect(find.textContaining('智能聚合'), findsNothing);
        expect(find.text('译者乙 · 连载版 · 2章'), findsOneWidget);
    });

    testWidgets('详情刷新失败时保留当前目录', (WidgetTester tester) async
    {
        when(
            () => indexCoordinator.refresh(
                any(),
                onProgress: any(named: 'onProgress'),
                cancellation: any(named: 'cancellation'),
            ),
        ).thenThrow(StateError('网络中断'));
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView).first, const Offset(0, 400));
        await tester.pumpAndSettle();

        expect(find.textContaining('已保留上次索引'), findsOneWidget);
        expect(find.text('正文'), findsOneWidget);
        expect(find.text('第二话'), findsOneWidget);
    });

    testWidgets('作品解析在详情页内展示且退出详情即取消', (WidgetTester tester) async
    {
        final Completer<WorkIndexResult> completer = Completer<WorkIndexResult>();
        late WorkIndexCancellation cancellation;
        final CoverLoadCoordinator coverCoordinator = CoverLoadCoordinator();

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    coverLoadCoordinatorProvider.overrideWithValue(
                        coverCoordinator,
                    ),
                ],
                child: MaterialApp(
                    home: WorkDetailPage(
                        work: work,
                        resolveOnOpen: true,
                        resolver:
                                (WorkIndexCancellation value, WorkIndexProgress onProgress)
                                {
                                    cancellation = value;
                                    onProgress('正在补全搜索目录（1/3）');
                                    return completer.future;
                                },
                    ),
                ),
            ),
        );
        await tester.pump();

        expect(find.text('测试漫画'), findsWidgets);
        expect(find.text('正在补全搜索目录（1/3）'), findsOneWidget);
        expect(find.text('退出当前详情页会取消解析'), findsOneWidget);
        expect(find.text('章节目录 ·2话'), findsNothing);
        final LinearProgressIndicator indicator = tester.widget(
            find.byType(LinearProgressIndicator),
        );
        expect(indicator.value, closeTo(1 / 3, 0.001));
        expect(coverCoordinator.paused, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(cancellation.isCancelled, isTrue);
        completer.complete(WorkIndexResult(work: work));
        await tester.pump();
        expect(coverCoordinator.paused, isFalse);
    });

    testWidgets('原始搜索结果详情显示最终兜底提示', (WidgetTester tester) async
    {
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(
                    home: WorkDetailPage(work: work, rawSourceMode: true),
                ),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('当前显示原始帖子，未进行作品聚合；目录可能不完整。'), findsOneWidget);
        expect(find.text('收藏'), findsOneWidget);
        expect(find.byTooltip('搜索原始帖子'), findsNothing);
        verifyNever(() => indexCoordinator.lookup(any()));
    });

    testWidgets('聚合作品取消收藏时提示匹配的论坛记录数', (
        WidgetTester tester,
    ) async
    {
        final List<CloudFavoriteRecord> records = <CloudFavoriteRecord>[
            _favoriteRecord(1, 10),
            _favoriteRecord(2, 11),
        ];
        when(
            () => favoriteRepository.findForWork(any()),
        ).thenAnswer((_) async => records);
        when(
            () => favoriteRepository.removeWork(any(), any()),
        ).thenAnswer((_) async {});
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                    workIndexCoordinatorProvider.overrideWithValue(indexCoordinator),
                ],
                child: MaterialApp(home: WorkDetailPage(work: work)),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('收藏'), findsOneWidget);
        await tester.tap(find.text('收藏'));
        await tester.pumpAndSettle();

        expect(find.textContaining('2 条论坛收藏'), findsOneWidget);
    });

    testWidgets('正式详情长按封面可主动重新解析且保留当前视觉', (
        WidgetTester tester,
    ) async
    {
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    forumFavoriteRepositoryProvider.overrideWithValue(favoriteRepository),
                    readingHistoryRepositoryProvider.overrideWithValue(historyRepository),
                ],
                child: MaterialApp(
                    home: WorkDetailPage(
                        work: work,
                        initialSourceTid: 10,
                        resolveOnOpen: true,
                        resolver: (
                            WorkIndexCancellation cancellation,
                            WorkIndexProgress onProgress,
                        ) async => WorkIndexResult(work: work),
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.byTooltip('长按重新解析封面'), findsOneWidget);
        await tester.longPress(find.byType(WorkCover));
        await tester.pumpAndSettle();
        expect(find.text('重新解析封面'), findsOneWidget);
        await tester.tap(find.text('重新解析封面'));
        await tester.pumpAndSettle();

        verify(
            () => coverRepository.resolve(
                any(),
                finalize: true,
                entryTid: 10,
                force: true,
            ),
        ).called(1);
        expect(find.text('没有找到可用图片，继续使用文字封面'), findsOneWidget);
    });
}

Work _work()
{
    final Uri firstUri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&mobile=2',
    );
    final Uri secondUri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=11&mobile=2',
    );
    return Work(
        id: 'forum-work:test',
        kind: LibraryKind.comic,
        title: '测试漫画',
        author: '作者',
        typeName: '连载',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 10,
                board: ForumBoard.comic,
                title: '测试漫画 第一话',
                uri: firstUri,
            ),
            SourceThread(
                tid: 11,
                board: ForumBoard.comic,
                title: '测试漫画 第二话',
                uri: secondUri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'forum-thread:10',
                title: '正文',
                sourceUri: firstUri,
                sourceTid: 10,
            ),
            Chapter(
                id: 'forum-thread:11',
                title: '第二话',
                sourceUri: secondUri,
                sourceTid: 11,
            ),
        ],
    );
}

CloudFavoriteRecord _favoriteRecord(int favoriteId, int threadId)
{
    return CloudFavoriteRecord(
        favoriteId: favoriteId,
        threadId: threadId,
        title: '测试漫画',
        threadUri: Uri.parse(
            'https://bbs.yamibo.com/thread-$threadId-1-1.html',
        ),
        deleteDialogUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&'
            'op=delete&favid=$favoriteId',
        ),
    );
}

Work _numberedSubtitleWork()
{
    final SourceThread first = SourceThread(
        tid: 20,
        board: ForumBoard.comic,
        title: '测试漫画01',
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=20&mobile=2',
        ),
    );
    final SourceThread second = SourceThread(
        tid: 21,
        board: ForumBoard.comic,
        title: '测试漫画02 严重的缺陷',
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=21&mobile=2',
        ),
    );
    return Work(
        id: 'forum-work:numbered-subtitle',
        kind: LibraryKind.comic,
        title: '测试漫画',
        sourceThreads: <SourceThread>[first, second],
        chapters: <Chapter>[
            Chapter(
                id: 'forum-thread:20',
                title: '01',
                sourceUri: first.uri,
                sourceTid: first.tid,
                order: 1,
            ),
            Chapter(
                id: 'forum-thread:21',
                title: '02 严重的缺陷',
                sourceUri: second.uri,
                sourceTid: second.tid,
                order: 2,
            ),
        ],
    );
}

Work _rangeChapterWork()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=519002&mobile=2',
    );
    return Work(
        id: 'forum-work:range-chapter',
        kind: LibraryKind.comic,
        title: '多话合一漫画',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 519002,
                board: ForumBoard.comic,
                title: '多话合一漫画 6.2~6.4',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'forum-thread:519002',
                title: '6.2~6.4',
                sourceUri: uri,
                sourceTid: 519002,
                order: 6.2,
            ),
        ],
    );
}

Work _integerRangeChapterWork()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573648&mobile=2',
    );
    return Work(
        id: 'forum-work:integer-range-chapter',
        kind: LibraryKind.comic,
        title: '魔法少女与前邪恶女干部',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 573648,
                board: ForumBoard.comic,
                title: '魔法少女与前邪恶女干部 02-03',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'forum-thread:573648',
                title: '02-03',
                sourceUri: uri,
                sourceTid: 573648,
                order: 2,
            ),
        ],
    );
}

Work _multiSourceWork()
{
    final SourceThread first = SourceThread(
        tid: 30,
        board: ForumBoard.comic,
        title: '多来源漫画 第1话',
        author: '楼主甲',
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=30&mobile=2',
        ),
    );
    final SourceThread second = SourceThread(
        tid: 31,
        board: ForumBoard.comic,
        title: '多来源漫画 第2话',
        author: '楼主甲',
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=31&mobile=2',
        ),
    );
    final SourceThread other = SourceThread(
        tid: 32,
        board: ForumBoard.comic,
        title: '多来源漫画 第9话',
        author: '楼主乙',
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=32&mobile=2',
        ),
    );
    final List<Chapter> firstChapters = <Chapter>[
        Chapter(
            id: 'forum-thread:30',
            title: '第1话',
            sourceUri: first.uri,
            sourceTid: first.tid,
            order: 1,
        ),
        Chapter(
            id: 'forum-thread:31',
            title: '第2话',
            sourceUri: second.uri,
            sourceTid: second.tid,
            order: 2,
        ),
    ];
    final List<Chapter> otherChapters = <Chapter>[
        Chapter(
            id: 'forum-thread:32',
            title: '第9话',
            sourceUri: other.uri,
            sourceTid: other.tid,
            order: 9,
        ),
    ];
    return Work(
        id: 'forum-work:multi-source',
        kind: LibraryKind.comic,
        title: '多来源漫画',
        author: '楼主甲',
        sourceThreads: <SourceThread>[first, second, other],
        chapters: <Chapter>[...firstChapters, ...otherChapters],
        directories: <WorkDirectory>[
            WorkDirectory(
                id: 'owner:a',
                owner: '楼主甲',
                sourceTids: const <int>[30, 31],
                chapters: firstChapters,
            ),
            WorkDirectory(
                id: 'owner:b',
                owner: '楼主乙',
                sourceTids: const <int>[32],
                chapters: otherChapters,
            ),
        ],
    );
}

Work _mixedChapterTitleWork()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=40&mobile=2',
    );
    return Work(
        id: 'forum-work:mixed-titles',
        kind: LibraryKind.comic,
        title: '混合章节标题',
        sourceThreads: <SourceThread>[
            SourceThread(tid: 40, board: ForumBoard.comic, title: '混合章节标题', uri: uri),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'forum-thread:40',
                title: '正文',
                sourceUri: uri,
                sourceTid: 40,
            ),
            Chapter(
                id: 'forum-thread:41',
                title: '番外篇',
                sourceUri: uri,
                sourceTid: 41,
                order: 900000,
            ),
            Chapter(
                id: 'forum-thread:42',
                title: '02 严重的缺陷',
                sourceUri: uri,
                sourceTid: 42,
                order: 2,
            ),
        ],
    );
}

Work _novelEditionWork()
{
    final List<SourceThread> threads = <SourceThread>[
        SourceThread(
            tid: 60,
            board: ForumBoard.lightNovel,
            title: '[轻小说]【WEB版】测试小说',
            author: '译者',
            uri: Uri.parse('https://bbs.yamibo.com/thread-60-1-1.html'),
        ),
        SourceThread(
            tid: 61,
            board: ForumBoard.lightNovel,
            title: '[轻小说]【文库版】测试小说 第一卷',
            author: '译者',
            uri: Uri.parse('https://bbs.yamibo.com/thread-61-1-1.html'),
        ),
        SourceThread(
            tid: 62,
            board: ForumBoard.lightNovel,
            title: '[轻小说]【文库版】测试小说 第二卷',
            author: '译者',
            uri: Uri.parse('https://bbs.yamibo.com/thread-62-1-1.html'),
        ),
    ];
    final List<Chapter> chapters = <Chapter>[
        Chapter(
            id: 'forum-post:60:601',
            title: 'Episode 1',
            sourceUri: threads[0].uri,
            sourceTid: 60,
            sourcePid: 601,
            order: 1,
            novelEdition: NovelEdition.serial,
        ),
        Chapter(
            id: 'forum-post:60:602',
            title: 'Episode 2',
            sourceUri: threads[0].uri,
            sourceTid: 60,
            sourcePid: 602,
            order: 2,
            novelEdition: NovelEdition.serial,
        ),
        Chapter(
            id: 'forum-post:61:611',
            title: '第1章 卷一开篇',
            sourceUri: threads[1].uri,
            sourceTid: 61,
            sourcePid: 611,
            order: 10001,
            novelEdition: NovelEdition.book,
            volumeTitle: '第一卷',
            volumeOrder: 1,
        ),
        Chapter(
            id: 'forum-post:61:612',
            title: '第2章 卷一结尾',
            sourceUri: threads[1].uri,
            sourceTid: 61,
            sourcePid: 612,
            order: 10002,
            novelEdition: NovelEdition.book,
            volumeTitle: '第一卷',
            volumeOrder: 1,
        ),
        Chapter(
            id: 'forum-thread:62',
            title: '整卷阅读',
            sourceUri: threads[2].uri,
            sourceTid: 62,
            order: 20000,
            novelEdition: NovelEdition.book,
            volumeTitle: '第二卷',
            volumeOrder: 2,
        ),
    ];
    return Work(
        id: 'forum-work:novel-editions',
        kind: LibraryKind.novel,
        title: '测试小说',
        author: '译者',
        sourceThreads: threads,
        chapters: chapters,
        directories: <WorkDirectory>[
            WorkDirectory(
                id: 'owner:translator',
                owner: '译者',
                sourceTids: const <int>[60, 61, 62],
                chapters: chapters,
            ),
        ],
    );
}

Work _multiSourceNovelWork({bool smartFill = true})
{
    final List<SourceThread> threads = <SourceThread>[
        SourceThread(
            tid: 70,
            board: ForumBoard.lightNovel,
            title: '多译者小说 第一章',
            author: '译者甲',
            uri: Uri.parse('https://bbs.yamibo.com/thread-70-1-1.html'),
        ),
        SourceThread(
            tid: 71,
            board: ForumBoard.lightNovel,
            title: '多译者小说 第三章',
            author: '译者甲',
            uri: Uri.parse('https://bbs.yamibo.com/thread-71-1-1.html'),
        ),
        SourceThread(
            tid: 72,
            board: ForumBoard.lightNovel,
            title: '多译者小说 第二章',
            author: '译者乙',
            uri: Uri.parse('https://bbs.yamibo.com/thread-72-1-1.html'),
        ),
        SourceThread(
            tid: 73,
            board: ForumBoard.lightNovel,
            title: '多译者小说 第四章',
            author: '译者乙',
            uri: Uri.parse('https://bbs.yamibo.com/thread-73-1-1.html'),
        ),
    ];
    final List<Chapter> firstChapters = <Chapter>[
        Chapter(
            id: 'forum-thread:70',
            title: '第一章',
            sourceUri: threads[0].uri,
            sourceTid: 70,
            order: 1,
            novelEdition: NovelEdition.serial,
        ),
        Chapter(
            id: 'forum-thread:71',
            title: '第三章',
            sourceUri: threads[1].uri,
            sourceTid: 71,
            order: 3,
            novelEdition: NovelEdition.serial,
        ),
    ];
    final List<Chapter> secondChapters = <Chapter>[
        Chapter(
            id: 'forum-thread:72',
            title: '第二章',
            sourceUri: threads[2].uri,
            sourceTid: 72,
            order: 2,
            novelEdition: NovelEdition.serial,
        ),
        Chapter(
            id: 'forum-thread:73',
            title: '第四章',
            sourceUri: threads[3].uri,
            sourceTid: 73,
            order: 4,
            novelEdition: NovelEdition.serial,
        ),
    ];
    return Work(
        id: 'forum-work:multi-source-novel',
        kind: LibraryKind.novel,
        title: '多译者小说',
        author: '译者甲',
        sourceThreads: threads,
        chapters: smartFill
                ? <Chapter>[firstChapters[0], secondChapters[0], firstChapters[1]]
                : firstChapters,
        directories: <WorkDirectory>[
            WorkDirectory(
                id: 'owner:translator-a',
                owner: '译者甲',
                sourceTids: const <int>[70, 71],
                chapters: firstChapters,
            ),
            WorkDirectory(
                id: 'owner:translator-b',
                owner: '译者乙',
                sourceTids: const <int>[72, 73],
                chapters: secondChapters,
            ),
        ],
    );
}

ForumThreadPage _page()
{
    return ForumThreadPage(
        tid: 10,
        board: ForumBoard.comic,
        title: '测试漫画 第一话',
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&mobile=2',
        ),
        posts: <SourcePost>[
            SourcePost(
                pid: 100,
                tid: 10,
                page: 1,
                floor: 1,
                author: '作者',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: const <PostContentBlock>[PostTextBlock(text: '测试作品简介')],
                links: const <ThreadLink>[],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}
