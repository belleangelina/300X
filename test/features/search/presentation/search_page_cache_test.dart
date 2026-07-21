import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/favorites/data/forum_favorite_repository.dart';
import 'package:x300/features/history/data/reading_history_repository.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/data/work_aggregator.dart';
import 'package:x300/features/library/data/work_index_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';
import 'package:x300/features/library/presentation/work_detail_page.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/search/application/search_cooldown.dart';
import 'package:x300/features/search/data/forum_search_repository.dart';
import 'package:x300/features/search/data/search_cache_repository.dart';
import 'package:x300/features/search/domain/search_models.dart';
import 'package:x300/features/search/presentation/search_page.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';

class _MockForumSearchRepository extends Mock
    implements ForumSearchRepository
{
}

class _MockForumLibraryRepository extends Mock
    implements ForumLibraryRepository
{
}

class _MockCoverRepository extends Mock implements CoverRepository
{
}

class _MockForumFavoriteRepository extends Mock
    implements ForumFavoriteRepository
{
}

class _MockReadingHistoryRepository extends Mock
    implements ReadingHistoryRepository
{
}

void main()
{
    setUpAll(()
    {
        registerFallbackValue(_work());
        registerFallbackValue(_work().sourceThreads.first);
        registerFallbackValue(<SourceThread>[]);
    });

    testWidgets('论坛搜索失败时显示明确标记的本机缓存', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final SearchCacheRepository cache = SearchCacheRepository(database);
        final Work work = _work();
        await cache.save(
            kind: LibraryKind.comic,
            keyword: '缓存词',
            works: <Work>[work],
            updatedAt: DateTime(2026, 7, 10, 20),
        );
        final _MockForumSearchRepository forum =
            _MockForumSearchRepository();
        final _MockCoverRepository cover = _MockCoverRepository();
        when(() => cover.resolve(any())).thenAnswer((_) async => null);
        when(
            () => forum.search(
                keyword: '缓存词',
                kind: LibraryKind.comic,
            ),
        ).thenThrow(StateError('网络不可用'));

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumSearchRepositoryProvider.overrideWithValue(forum),
                    coverRepositoryProvider.overrideWithValue(cover),
                    searchCooldownProvider.overrideWithValue(
                        SearchCooldown(),
                    ),
                ],
                child: const MaterialApp(
                    home: SearchPage(kind: LibraryKind.comic),
                ),
            ),
        );
        await tester.enterText(find.byType(TextField), '缓存词');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('缓存漫画'), findsWidgets);
        expect(find.textContaining('当前显示本机搜索缓存'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('搜索框加载指示器保持正圆', (WidgetTester tester) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final _MockForumSearchRepository forum =
            _MockForumSearchRepository();
        final Completer<ForumSearchPage> pending =
            Completer<ForumSearchPage>();
        when(
            () => forum.search(
                keyword: '加载中',
                kind: LibraryKind.comic,
            ),
        ).thenAnswer((_) => pending.future);
        when(() => forum.aggregateThreads(any()))
            .thenReturn(const <Work>[]);

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumSearchRepositoryProvider.overrideWithValue(forum),
                    searchCooldownProvider.overrideWithValue(SearchCooldown()),
                ],
                child: const MaterialApp(
                    home: SearchPage(kind: LibraryKind.comic),
                ),
            ),
        );
        await tester.enterText(find.byType(TextField), '加载中');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();

        final Finder indicator = find.descendant(
            of: find.byType(AppBar),
            matching: find.byType(CircularProgressIndicator),
        );
        final Size size = tester.getSize(indicator);
        expect(size.width, size.height);

        pending.complete(
            const ForumSearchPage(
                kind: LibraryKind.comic,
                keyword: '加载中',
                searchId: 'loading',
                sourceThreads: <SourceThread>[],
                currentPage: 1,
                totalPages: 1,
            ),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('首屏仅一章时仍复用 searchid 补全并持久化目录', (
        WidgetTester tester,
    ) async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final AppSettingsRepository settings = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        const WorkAggregator aggregator = WorkAggregator();
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final _MockForumSearchRepository forum =
            _MockForumSearchRepository();
        final _MockForumLibraryRepository library =
            _MockForumLibraryRepository();
        final _MockCoverRepository cover = _MockCoverRepository();
        final _MockForumFavoriteRepository favorite =
            _MockForumFavoriteRepository();
        final _MockReadingHistoryRepository history =
            _MockReadingHistoryRepository();
        final List<SourceThread> firstThreads = <SourceThread>[
            _searchThread(201, '测试长篇 01-开始'),
        ];
        final List<SourceThread> secondThreads = <SourceThread>[
            _searchThread(202, '测试长篇 02-继续'),
            _searchThread(203, '测试长篇 03-结尾'),
        ];
        final ForumSearchPage firstPage = ForumSearchPage(
            kind: LibraryKind.comic,
            keyword: '测试长篇',
            searchId: '123',
            sourceThreads: firstThreads,
            currentPage: 1,
            totalPages: 2,
            nextPageUri: Uri.parse(
                'https://bbs.yamibo.com/search.php?searchid=123&page=2',
            ),
        );
        final ForumSearchPage secondPage = ForumSearchPage(
            kind: LibraryKind.comic,
            keyword: '测试长篇',
            searchId: '123',
            sourceThreads: secondThreads,
            currentPage: 2,
            totalPages: 2,
        );
        when(
            () => forum.search(
                keyword: '测试长篇',
                kind: LibraryKind.comic,
            ),
        ).thenAnswer((_) async => firstPage);
        when(() => forum.loadNext(firstPage))
            .thenAnswer((_) async => secondPage);
        when(() => forum.aggregateThreads(any()))
            .thenAnswer((Invocation invocation)
            {
                return aggregator.aggregate(
                    invocation.positionalArguments.first
                        as List<SourceThread>,
                );
            });
        when(
            () => library.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
            ),
        ).thenAnswer((_) async => _threadPage());
        when(() => cover.resolve(any())).thenAnswer((_) async => null);
        when(() => favorite.findForWork(any()))
            .thenAnswer((_) async => const []);
        when(() => history.get(any())).thenAnswer((_) async => null);

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumSearchRepositoryProvider.overrideWithValue(forum),
                    searchCooldownProvider.overrideWithValue(SearchCooldown()),
                    forumLibraryRepositoryProvider.overrideWithValue(library),
                    coverRepositoryProvider.overrideWithValue(cover),
                    forumFavoriteRepositoryProvider.overrideWithValue(favorite),
                    readingHistoryRepositoryProvider.overrideWithValue(history),
                    appSettingsRepositoryProvider.overrideWithValue(settings),
                ],
                child: const MaterialApp(
                    home: SearchPage(kind: LibraryKind.comic),
                ),
            ),
        );
        await tester.enterText(find.byType(TextField), '测试长篇');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('2 个章节'), findsNothing);
        await tester.tap(find.byType(WorkListTile));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final WorkDetailPage detail = tester.widget<WorkDetailPage>(
            find.byType(WorkDetailPage),
        );
        expect(detail.work.id, 'forum-thread:201');
        expect(detail.resolveOnOpen, isTrue);
        final WorkIndexRecord? indexed =
                await WorkIndexRepository(
                    database,
                ).loadBySourceTid(203, LibraryKind.comic);
        expect(indexed, isNotNull);
        expect(indexed!.work.chapters, hasLength(3));
        expect(
            indexed.work.chapters.map((Chapter value) => value.sourceTid),
            <int>[201, 202, 203],
        );
        verify(() => forum.loadNext(firstPage)).called(1);
        verify(
            () => forum.search(
                keyword: '测试长篇',
                kind: LibraryKind.comic,
            ),
        ).called(1);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('详情页搜索入口优先显示精确缓存并默认原始结果', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final SearchCacheRepository cache = SearchCacheRepository(database);
        final _MockForumSearchRepository forum = _MockForumSearchRepository();
        final _MockCoverRepository cover = _MockCoverRepository();
        when(() => cover.resolve(any())).thenAnswer((_) async => null);
        await cache.save(
            kind: LibraryKind.comic,
            keyword: '缓存漫画',
            works: <Work>[_work()],
            updatedAt: DateTime(2026, 7, 17, 12),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumSearchRepositoryProvider.overrideWithValue(forum),
                    coverRepositoryProvider.overrideWithValue(cover),
                    searchCooldownProvider.overrideWithValue(SearchCooldown()),
                ],
                child: const MaterialApp(
                    home: SearchPage(
                        kind: LibraryKind.comic,
                        initialKeyword: '缓存漫画',
                        initialResultMode: SearchResultMode.raw,
                        autoSubmit: true,
                    ),
                ),
            ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('当前显示本机搜索缓存 · 07-17 12:00'), findsOneWidget);
        expect(find.textContaining('网络不可用'), findsNothing);
        expect(find.byType(WorkListTile), findsOneWidget);
        final TabController selector = DefaultTabController.of(
            tester.element(
                find.byKey(const Key('search-result-mode-bottom-bar')),
            ),
        );
        expect(selector.index, SearchResultMode.raw.index);
        verifyNever(
            () => forum.search(
                keyword: '缓存漫画',
                kind: LibraryKind.comic,
            ),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('详情页搜索入口在冷却结束后自动请求且保留原始模式', (
        WidgetTester tester,
    ) async
    {
        DateTime now = DateTime(2026, 7, 17, 12);
        final SearchCooldown cooldown = SearchCooldown(now: () => now);
        expect(cooldown.tryBegin(), isTrue);
        cooldown.accepted();
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final _MockForumSearchRepository forum = _MockForumSearchRepository();
        final _MockCoverRepository cover = _MockCoverRepository();
        when(() => cover.resolve(any())).thenAnswer((_) async => null);
        final SourceThread thread = _searchThread(401, '等待作品 01-开始');
        final ForumSearchPage page = ForumSearchPage(
            kind: LibraryKind.comic,
            keyword: '等待作品',
            searchId: '789',
            sourceThreads: <SourceThread>[thread],
            currentPage: 1,
            totalPages: 1,
        );
        when(
            () => forum.search(
                keyword: '等待作品',
                kind: LibraryKind.comic,
            ),
        ).thenAnswer((_) async => page);
        when(() => forum.aggregateThreads(any())).thenAnswer(
            (Invocation invocation) => const WorkAggregator().aggregate(
                invocation.positionalArguments.first as List<SourceThread>,
            ),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumSearchRepositoryProvider.overrideWithValue(forum),
                    coverRepositoryProvider.overrideWithValue(cover),
                    searchCooldownProvider.overrideWithValue(cooldown),
                ],
                child: const MaterialApp(
                    home: SearchPage(
                        kind: LibraryKind.comic,
                        initialKeyword: '等待作品',
                        initialResultMode: SearchResultMode.raw,
                        autoSubmit: true,
                    ),
                ),
            ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.textContaining('秒后自动搜索'), findsOneWidget);
        verifyNever(
            () => forum.search(
                keyword: '等待作品',
                kind: LibraryKind.comic,
            ),
        );

        now = now.add(const Duration(seconds: 11));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        verify(
            () => forum.search(
                keyword: '等待作品',
                kind: LibraryKind.comic,
            ),
        ).called(1);
        expect(find.byType(WorkListTile), findsOneWidget);
        final TabController selector = DefaultTabController.of(
            tester.element(
                find.byKey(const Key('search-result-mode-bottom-bar')),
            ),
        );
        expect(selector.index, SearchResultMode.raw.index);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('搜索可切换原始帖子并打开未聚合详情', (
        WidgetTester tester,
    ) async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final AppSettingsRepository settings = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        const WorkAggregator aggregator = WorkAggregator();
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final _MockForumSearchRepository forum = _MockForumSearchRepository();
        final _MockCoverRepository cover = _MockCoverRepository();
        final _MockForumFavoriteRepository favorite =
                _MockForumFavoriteRepository();
        final _MockReadingHistoryRepository history =
                _MockReadingHistoryRepository();
        final List<SourceThread> threads = <SourceThread>[
            _searchThread(301, '兜底作品 01-开始'),
            _searchThread(302, '兜底作品 02-继续'),
        ];
        final ForumSearchPage page = ForumSearchPage(
            kind: LibraryKind.comic,
            keyword: '兜底作品',
            searchId: '456',
            sourceThreads: threads,
            currentPage: 1,
            totalPages: 1,
        );
        when(
            () => forum.search(
                keyword: '兜底作品',
                kind: LibraryKind.comic,
            ),
        ).thenAnswer((_) async => page);
        when(() => forum.aggregateThreads(any())).thenAnswer((Invocation invocation)
        {
            return aggregator.aggregate(
                invocation.positionalArguments.first as List<SourceThread>,
            );
        });
        when(() => cover.resolve(any())).thenAnswer((_) async => null);
        when(() => favorite.findForWork(any())).thenAnswer((_) async => const []);
        when(() => history.get(any())).thenAnswer((_) async => null);

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumSearchRepositoryProvider.overrideWithValue(forum),
                    searchCooldownProvider.overrideWithValue(SearchCooldown()),
                    coverRepositoryProvider.overrideWithValue(cover),
                    forumFavoriteRepositoryProvider.overrideWithValue(favorite),
                    readingHistoryRepositoryProvider.overrideWithValue(history),
                    appSettingsRepositoryProvider.overrideWithValue(settings),
                ],
                child: const MaterialApp(
                    home: SearchPage(kind: LibraryKind.comic),
                ),
            ),
        );
        await tester.enterText(find.byType(TextField), '兜底作品');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('智能聚合'), findsOneWidget);
        expect(find.text('原始结果'), findsOneWidget);
        expect(find.text('最终兜底'), findsNothing);
        expect(find.byType(WorkListTile), findsOneWidget);
        final Finder bottomModes = find.byKey(
            const Key('search-result-mode-bottom-bar'),
        );
        expect(
            tester.getBottomRight(bottomModes).dy,
            tester.getBottomRight(find.byType(Scaffold)).dy,
        );
        expect(
            find.descendant(of: bottomModes, matching: find.byType(Icon)),
            findsNothing,
        );
        final TabBar resultModes = tester.widget<TabBar>(
            find.descendant(of: bottomModes, matching: find.byType(TabBar)),
        );
        expect(
            resultModes.labelColor,
            Theme.of(tester.element(bottomModes)).colorScheme.primary,
        );
        expect(resultModes.unselectedLabelColor, Colors.black87);

        await tester.tap(find.text('原始结果'));
        await tester.pump();

        expect(find.byType(WorkListTile), findsNWidgets(2));
        expect(find.text('[汉化][作者]兜底作品 01-开始'), findsNWidgets(2));
        expect(find.text('[汉化][作者]兜底作品 02-继续'), findsNWidgets(2));

        await tester.tap(find.text('[汉化][作者]兜底作品 01-开始').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final WorkDetailPage detail = tester.widget<WorkDetailPage>(
            find.byType(WorkDetailPage),
        );
        expect(detail.rawSourceMode, isTrue);
        expect(detail.work.title, '[汉化][作者]兜底作品 01-开始');
        expect(
            find.text('当前显示原始帖子，未进行作品聚合；目录可能不完整。'),
            findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });
}

Work _work()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2',
    );
    return Work(
        id: 'comic:101',
        kind: LibraryKind.comic,
        title: '缓存漫画',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 101,
                board: ForumBoard.comic,
                title: '缓存漫画',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'comic:101:1',
                title: '正文',
                sourceUri: uri,
                sourceTid: 101,
            ),
        ],
    );
}

SourceThread _searchThread(int tid, String title)
{
    return SourceThread(
        tid: tid,
        board: ForumBoard.comic,
        typeId: 69,
        typeName: '#長篇連載',
        title: '[汉化][作者]$title',
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
        ),
    );
}

ForumThreadPage _threadPage()
{
    return ForumThreadPage(
        tid: 201,
        board: ForumBoard.comic,
        title: '测试长篇 01-开始',
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=201&mobile=2',
        ),
        posts: const <SourcePost>[
            SourcePost(
                pid: 2001,
                tid: 201,
                page: 1,
                floor: 1,
                author: '作者',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: <PostContentBlock>[
                    PostTextBlock(text: '测试简介'),
                ],
                links: <ThreadLink>[],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}
