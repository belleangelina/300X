import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/favorites/data/favorite_cache_repository.dart';
import 'package:x300/features/favorites/data/forum_favorite_repository.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/favorites/presentation/cloud_favorites_page.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';

class _MockForumFavoriteRepository extends Mock
    implements ForumFavoriteRepository
{
}

class _EmptyCoverRepository extends Fake implements CoverRepository
{
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

void main()
{
    setUpAll(()
    {
        registerFallbackValue(<CloudFavoriteEntry>[]);
        registerFallbackValue(<CloudFavoriteRecord>[]);
        registerFallbackValue(_favorite().work);
        registerFallbackValue(CloudFavoritePage(
            entries: const <CloudFavoriteEntry>[],
            ignoredCount: 0,
            currentPage: 1,
            totalPages: 1,
        ));
    });

    testWidgets('论坛收藏失败时显示只读缓存且不显示删除按钮', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final FavoriteCacheRepository cache = FavoriteCacheRepository(
            database,
            101,
        );
        final FavoriteWork favorite = _favorite();
        await cache.save(
            <FavoriteWork>[favorite],
            updatedAt: DateTime(2026, 7, 10, 20),
        );
        final _MockForumFavoriteRepository forum =
            _MockForumFavoriteRepository();
        when(() => forum.loadInitial()).thenThrow(StateError('网络不可用'));

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    favoriteCacheRepositoryProvider.overrideWithValue(cache),
                    forumFavoriteRepositoryProvider.overrideWithValue(forum),
                    coverRepositoryProvider.overrideWithValue(
                        _EmptyCoverRepository(),
                    ),
                ],
                child: const MaterialApp(home: CloudFavoritesPage()),
            ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('缓存收藏'), findsWidgets);
        expect(find.textContaining('当前显示只读收藏缓存'), findsOneWidget);
        expect(find.byIcon(Icons.favorite), findsNothing);
        expect(find.byIcon(Icons.cloud_off_outlined), findsWidgets);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('拆分后的小说收藏只显示小说缓存', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final FavoriteCacheRepository cache = FavoriteCacheRepository(
            database,
            101,
        );
        await cache.save(<FavoriteWork>[
            _favorite(),
            _favorite(kind: LibraryKind.novel),
        ]);
        final _MockForumFavoriteRepository forum =
                _MockForumFavoriteRepository();
        when(() => forum.loadInitial()).thenThrow(StateError('网络不可用'));

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    favoriteCacheRepositoryProvider.overrideWithValue(cache),
                    forumFavoriteRepositoryProvider.overrideWithValue(forum),
                    coverRepositoryProvider.overrideWithValue(
                        _EmptyCoverRepository(),
                    ),
                ],
                child: const MaterialApp(
                    home: CloudFavoritesPage(kind: LibraryKind.novel),
                ),
            ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('小说收藏'), findsOneWidget);
        expect(find.text('缓存小说收藏'), findsWidgets);
        expect(find.text('缓存收藏'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('小说收藏不足一屏时自动加载后续论坛分页', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final FavoriteCacheRepository cache = FavoriteCacheRepository(
            database,
            101,
        );
        final _MockForumFavoriteRepository forum =
                _MockForumFavoriteRepository();
        final CloudFavoriteEntry first = _entry(
            tid: 556020,
            title: '第一页小说收藏',
        );
        final CloudFavoriteEntry target = _entry(
            tid: 521519,
            title: '一周一次买下同班同学的那些事',
        );
        final CloudFavoritePage firstPage = CloudFavoritePage(
            entries: <CloudFavoriteEntry>[first],
            ignoredCount: 2,
            currentPage: 1,
            totalPages: 2,
            nextPageUri: Uri.parse(
                'https://bbs.yamibo.com/home.php?mod=space&do=favorite&page=2',
            ),
        );
        final CloudFavoritePage secondPage = CloudFavoritePage(
            entries: <CloudFavoriteEntry>[target],
            ignoredCount: 0,
            currentPage: 2,
            totalPages: 2,
        );
        when(() => forum.loadInitial()).thenAnswer((_) async => firstPage);
        when(
            () => forum.loadNext(any()),
        ).thenAnswer((_) async => secondPage);
        when(
            () => forum.aggregateEntries(any()),
        ).thenAnswer((Invocation invocation)
        {
            final List<CloudFavoriteEntry> entries =
                    invocation.positionalArguments.first
                    as List<CloudFavoriteEntry>;
            return entries.map(_favoriteFromEntry).toList(growable: false);
        });

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    favoriteCacheRepositoryProvider.overrideWithValue(cache),
                    forumFavoriteRepositoryProvider.overrideWithValue(forum),
                    coverRepositoryProvider.overrideWithValue(
                        _EmptyCoverRepository(),
                    ),
                ],
                child: const MaterialApp(
                    home: CloudFavoritesPage(kind: LibraryKind.novel),
                ),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('第一页小说收藏'), findsWidgets);
        expect(find.text('一周一次买下同班同学的那些事'), findsWidgets);
        expect(find.textContaining('已隐藏'), findsNothing);
        verify(() => forum.loadNext(firstPage)).called(1);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('收藏页可切换到逐帖原始收藏且只取消当前条目', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final FavoriteCacheRepository cache = FavoriteCacheRepository(
            database,
            101,
        );
        final _MockForumFavoriteRepository forum =
                _MockForumFavoriteRepository();
        final CloudFavoriteEntry first = _entry(
            tid: 600001,
            title: '测试作品 第1章',
        );
        final CloudFavoriteEntry second = _entry(
            tid: 600002,
            title: '测试作品 第2章',
        );
        final CloudFavoritePage page = CloudFavoritePage(
            entries: <CloudFavoriteEntry>[first, second],
            ignoredCount: 0,
            currentPage: 1,
            totalPages: 1,
        );
        when(() => forum.loadInitial()).thenAnswer((_) async => page);
        when(() => forum.aggregateEntries(any())).thenReturn(<FavoriteWork>[
            FavoriteWork(
                work: Work(
                    id: 'novel:test-work',
                    kind: LibraryKind.novel,
                    title: '测试作品',
                    sourceThreads: <SourceThread>[
                        first.sourceThread,
                        second.sourceThread,
                    ],
                    chapters: <Chapter>[
                        Chapter(
                            id: 'novel:600001',
                            title: '第1章',
                            sourceUri: first.sourceThread.uri,
                            sourceTid: first.sourceThread.tid,
                        ),
                        Chapter(
                            id: 'novel:600002',
                            title: '第2章',
                            sourceUri: second.sourceThread.uri,
                            sourceTid: second.sourceThread.tid,
                        ),
                    ],
                ),
                records: <CloudFavoriteRecord>[first.record, second.record],
            ),
        ]);
        when(
            () => forum.removeWork(any(), any()),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    favoriteCacheRepositoryProvider.overrideWithValue(cache),
                    forumFavoriteRepositoryProvider.overrideWithValue(forum),
                    coverRepositoryProvider.overrideWithValue(
                        _EmptyCoverRepository(),
                    ),
                ],
                child: const MaterialApp(
                    home: CloudFavoritesPage(kind: LibraryKind.novel),
                ),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('智能聚合'), findsOneWidget);
        expect(find.text('原始收藏'), findsOneWidget);
        expect(find.text('测试作品'), findsWidgets);
        expect(find.text('测试作品 第1章'), findsNothing);
        final Finder bottomModes = find.byKey(
            const Key('favorite-result-mode-bottom-bar'),
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

        await tester.tap(find.text('原始收藏'));
        await tester.pumpAndSettle();

        expect(find.text('测试作品 第1章'), findsWidgets);
        expect(find.text('测试作品 第2章'), findsWidgets);
        final Finder removeTooltip = find.byTooltip('取消收藏').first;
        final IconButton removeButton = tester.widget<IconButton>(
            find.ancestor(
                of: removeTooltip,
                matching: find.byType(IconButton),
            ).first,
        );
        removeButton.onPressed!();
        removeButton.onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();

        final VerificationResult result = verify(
            () => forum.removeWork(captureAny(), captureAny()),
        )..called(1);
        final Work removedWork = result.captured[0] as Work;
        final List<CloudFavoriteRecord> removedRecords =
                result.captured[1] as List<CloudFavoriteRecord>;
        expect(removedWork.sourceThreads, hasLength(1));
        expect(removedRecords, hasLength(1));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('取消收藏结果未知时回读后人工解除不重提且 busy 释放', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final FavoriteCacheRepository cache = FavoriteCacheRepository(
            database,
            101,
        );
        final _MockForumFavoriteRepository forum =
            _MockForumFavoriteRepository();
        final CloudFavoriteEntry entry = _entry(
            tid: 600101,
            title: '待核对收藏',
        );
        final FavoriteWork item = _favoriteFromEntry(entry);
        final CloudFavoritePage page = CloudFavoritePage(
            entries: <CloudFavoriteEntry>[entry],
            ignoredCount: 0,
            currentPage: 1,
            totalPages: 1,
        );
        final ForumUnresolvedSubmission blocked =
            _blockedRemoval(entry.record);
        when(() => forum.loadInitial()).thenAnswer((_) async => page);
        when(() => forum.aggregateEntries(any())).thenReturn(
            <FavoriteWork>[item],
        );
        when(() => forum.removeWork(any(), any())).thenThrow(
            ForumSubmissionBlockedException(blocked),
        );
        when(
            () => forum.readbackUnresolved(blocked, any()),
        ).thenAnswer(
            (_) async => ForumFavoriteReadbackResult(
                records: <CloudFavoriteRecord>[entry.record],
                trustedOutcomeConfirmed: false,
            ),
        );
        when(() => forum.acknowledgeUnresolved(blocked)).thenAnswer(
            (_) async {},
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    favoriteCacheRepositoryProvider.overrideWithValue(cache),
                    forumFavoriteRepositoryProvider.overrideWithValue(forum),
                    coverRepositoryProvider.overrideWithValue(
                        _EmptyCoverRepository(),
                    ),
                ],
                child: const MaterialApp(home: CloudFavoritesPage()),
            ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('取消收藏'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();
        expect(find.text('取消收藏结果待核对'), findsOneWidget);
        await tester.tap(
            find.byKey(const ValueKey<String>('cloud-favorite-readback')),
        );
        await tester.pumpAndSettle();
        expect(find.text('仍无法确认取消结果'), findsOneWidget);
        await tester.tap(
            find.byKey(
                const ValueKey<String>(
                    'cloud-favorite-confirm-acknowledge',
                ),
            ),
        );
        await tester.pumpAndSettle();

        verify(() => forum.removeWork(any(), any())).called(1);
        verify(() => forum.readbackUnresolved(blocked, any())).called(1);
        verify(() => forum.acknowledgeUnresolved(blocked)).called(1);
        final IconButton removeButton = tester.widget<IconButton>(
            find.ancestor(
                of: find.byTooltip('取消收藏'),
                matching: find.byType(IconButton),
            ),
        );
        expect(removeButton.onPressed, isNotNull);
        expect(find.textContaining('本次未发起新提交'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('刷新旧响应晚返回时不覆盖新页面或新缓存', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final FavoriteCacheRepository cache = FavoriteCacheRepository(
            database,
            101,
        );
        final _MockForumFavoriteRepository forum =
            _MockForumFavoriteRepository();
        final Completer<CloudFavoritePage> stale =
            Completer<CloudFavoritePage>();
        final Completer<CloudFavoritePage> current =
            Completer<CloudFavoritePage>();
        var calls = 0;
        when(() => forum.loadInitial()).thenAnswer((_) =>
            calls++ == 0 ? stale.future : current.future,
        );
        when(() => forum.aggregateEntries(any())).thenAnswer(
            (Invocation invocation) =>
                (invocation.positionalArguments.first
                        as List<CloudFavoriteEntry>)
                    .map(_favoriteFromEntry)
                    .toList(growable: false),
        );
        final CloudFavoritesPageController controller =
            CloudFavoritesPageController();

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    favoriteCacheRepositoryProvider.overrideWithValue(cache),
                    forumFavoriteRepositoryProvider.overrideWithValue(forum),
                    coverRepositoryProvider.overrideWithValue(
                        _EmptyCoverRepository(),
                    ),
                ],
                child: MaterialApp(
                    home: CloudFavoritesPage(controller: controller),
                ),
            ),
        );
        await tester.pump();
        final Future<void> refresh = controller.scrollToTopAndRefresh();
        await tester.pump();
        current.complete(_page(202, '新刷新结果'));
        await refresh;
        await tester.pumpAndSettle();

        expect(find.text('新刷新结果'), findsWidgets);
        stale.complete(_page(201, '过期刷新结果'));
        await tester.pumpAndSettle();

        expect(find.text('新刷新结果'), findsWidgets);
        expect(find.text('过期刷新结果'), findsNothing);
        final FavoriteCacheSnapshot? snapshot = await cache.load();
        expect(snapshot?.works.single.work.title, '新刷新结果');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });

    testWidgets('加载下一页与刷新交错时旧分页不追加也不写回缓存', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final FavoriteCacheRepository cache = FavoriteCacheRepository(
            database,
            101,
        );
        final _MockForumFavoriteRepository forum =
            _MockForumFavoriteRepository();
        final Completer<CloudFavoritePage> staleNext =
            Completer<CloudFavoritePage>();
        final List<CloudFavoriteEntry> initialEntries =
            List<CloudFavoriteEntry>.generate(
                30,
                (int index) => _entry(
                    tid: 3000 + index,
                    title: '旧列表 $index',
                ),
            );
        final CloudFavoritePage initial = CloudFavoritePage(
            entries: initialEntries,
            ignoredCount: 0,
            currentPage: 1,
            totalPages: 2,
            nextPageUri: Uri.parse(
                'https://bbs.yamibo.com/home.php?mod=space&do=favorite&'
                'type=thread&page=2&mobile=2',
            ),
        );
        var initialCalls = 0;
        when(() => forum.loadInitial()).thenAnswer((_) async =>
            initialCalls++ == 0 ? initial : _page(9001, '刷新后的唯一结果'),
        );
        when(() => forum.loadNext(initial)).thenAnswer((_) => staleNext.future);
        when(() => forum.aggregateEntries(any())).thenAnswer(
            (Invocation invocation) =>
                (invocation.positionalArguments.first
                        as List<CloudFavoriteEntry>)
                    .map(_favoriteFromEntry)
                    .toList(growable: false),
        );
        final CloudFavoritesPageController controller =
            CloudFavoritesPageController();

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    favoriteCacheRepositoryProvider.overrideWithValue(cache),
                    forumFavoriteRepositoryProvider.overrideWithValue(forum),
                    coverRepositoryProvider.overrideWithValue(
                        _EmptyCoverRepository(),
                    ),
                ],
                child: MaterialApp(
                    home: CloudFavoritesPage(controller: controller),
                ),
            ),
        );
        await tester.pumpAndSettle();
        final ListView list = tester.widget<ListView>(find.byType(ListView));
        list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
        await tester.pump();
        verify(() => forum.loadNext(initial)).called(1);

        final Future<void> refresh = controller.scrollToTopAndRefresh();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await refresh;
        await tester.pump();
        expect(find.text('刷新后的唯一结果'), findsWidgets);

        staleNext.complete(_page(9002, '过期分页结果'));
        await tester.pumpAndSettle();

        expect(find.text('刷新后的唯一结果'), findsWidgets);
        expect(find.text('过期分页结果'), findsNothing);
        final FavoriteCacheSnapshot? snapshot = await cache.load();
        expect(snapshot?.works.single.work.title, '刷新后的唯一结果');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await database.close();
    });
}

CloudFavoritePage _page(int tid, String title)
{
    return CloudFavoritePage(
        entries: <CloudFavoriteEntry>[_entry(tid: tid, title: title)],
        ignoredCount: 0,
        currentPage: 1,
        totalPages: 1,
    );
}

CloudFavoriteEntry _entry({required int tid, required String title})
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
    final CloudFavoriteRecord record = CloudFavoriteRecord(
        favoriteId: 1000 + tid,
        threadId: tid,
        title: title,
        threadUri: uri,
        deleteDialogUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&'
            'favid=${1000 + tid}',
        ),
    );
    return CloudFavoriteEntry(
        record: record,
        sourceThread: SourceThread(
            tid: tid,
            board: ForumBoard.lightNovel,
            title: title,
            uri: uri,
        ),
    );
}

FavoriteWork _favoriteFromEntry(CloudFavoriteEntry entry)
{
    final SourceThread thread = entry.sourceThread;
    return FavoriteWork(
        work: Work(
            id: 'novel:${thread.tid}',
            kind: LibraryKind.novel,
            title: thread.title,
            sourceThreads: <SourceThread>[thread],
            chapters: <Chapter>[
                Chapter(
                    id: 'novel:${thread.tid}:1',
                    title: '正文',
                    sourceUri: thread.uri,
                    sourceTid: thread.tid,
                ),
            ],
        ),
        records: <CloudFavoriteRecord>[entry.record],
    );
}

ForumUnresolvedSubmission _blockedRemoval(CloudFavoriteRecord record)
{
    final ForumActionTarget target = ForumActionTarget(
        threadId: record.threadId,
        favoriteId: record.favoriteId,
    );
    final Uri readback = Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=space&do=favorite&view=me&'
        'type=thread&mobile=2',
    );
    return ForumUnresolvedSubmission(
        attemptId: 'legacy-remove-attempt',
        userId: 101,
        request: ForumActionRequest(
            kind: ForumActionKind.removeFavorite,
            target: target,
            entryUri: record.deleteDialogUri,
            readbackUri: readback,
        ),
        readback: ForumReadbackDescriptor(
            kind: ForumReadbackKind.threadFavorites,
            uri: readback,
            target: target,
            description: '回读收藏列表',
        ),
        status: ForumSubmissionTombstoneStatus.attempted,
        recordedAt: DateTime.utc(2026, 8, 13),
    );
}

FavoriteWork _favorite({LibraryKind kind = LibraryKind.comic})
{
    final bool novel = kind == LibraryKind.novel;
    final int tid = novel ? 102 : 101;
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
    return FavoriteWork(
        work: Work(
            id: '${kind.name}:$tid',
            kind: kind,
            title: novel ? '缓存小说收藏' : '缓存收藏',
            sourceThreads: <SourceThread>[
                SourceThread(
                    tid: tid,
                    board: novel ? ForumBoard.lightNovel : ForumBoard.comic,
                    title: novel ? '缓存小说收藏' : '缓存收藏',
                    uri: uri,
                ),
            ],
            chapters: <Chapter>[
                Chapter(
                    id: '${kind.name}:$tid:1',
                    title: '正文',
                    sourceUri: uri,
                    sourceTid: tid,
                ),
            ],
        ),
        records: <CloudFavoriteRecord>[
            CloudFavoriteRecord(
                favoriteId: 1000 + tid,
                threadId: tid,
                title: novel ? '缓存小说收藏' : '缓存收藏',
                threadUri: uri,
                deleteDialogUri: Uri.parse(
                    'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&favid=${1000 + tid}',
                ),
            ),
        ],
    );
}
