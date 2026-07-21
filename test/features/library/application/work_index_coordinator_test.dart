import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/library/application/work_index_coordinator.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/data/work_aggregator.dart';
import 'package:x300/features/library/data/work_index_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';
import 'package:x300/features/search/application/search_cooldown.dart';
import 'package:x300/features/search/data/forum_search_repository.dart';
import 'package:x300/features/search/domain/search_models.dart';

class _MockForumLibraryRepository extends Mock
        implements ForumLibraryRepository {}

class _MockForumSearchRepository extends Mock
        implements ForumSearchRepository {}

void main()
{
    const WorkAggregator aggregator = WorkAggregator();
    late AppDatabase database;
    late WorkIndexRepository indexRepository;
    late _MockForumLibraryRepository libraryRepository;
    late _MockForumSearchRepository searchRepository;
    late WorkIndexCoordinator coordinator;

    setUpAll(()
    {
        registerFallbackValue(_thread(1, '测试作品'));
        registerFallbackValue(<SourceThread>[]);
        registerFallbackValue(LibraryKind.comic);
    });

    setUp(()
    {
        database = AppDatabase(NativeDatabase.memory());
        indexRepository = WorkIndexRepository(database);
        libraryRepository = _MockForumLibraryRepository();
        searchRepository = _MockForumSearchRepository();
        coordinator = WorkIndexCoordinator(
            indexRepository,
            libraryRepository,
            searchRepository,
            SearchCooldown(interval: Duration.zero),
        );
        when(
            () => libraryRepository.loadDirectoryThread(
                any(),
                forceReload: any(named: 'forceReload'),
                onPageProgress: any(named: 'onPageProgress'),
            ),
        ).thenAnswer((Invocation invocation)
        {
            final SourceThread thread =
                    invocation.positionalArguments.first as SourceThread;
            final bool forceReload =
                    invocation.namedArguments[#forceReload] as bool;
            return libraryRepository.loadThread(
                thread,
                includeAllOriginalPosterPosts: true,
                forceReload: forceReload,
            );
        });
        when(() => searchRepository.aggregateThreads(any())).thenAnswer(
            (Invocation invocation) => aggregator.aggregate(
                invocation.positionalArguments.first as List<SourceThread>,
            ),
        );
    });

    tearDown(() async
    {
        await database.close();
    });

    test('主页命中已有索引时不请求帖子或搜索', () async
    {
        final Work work = _withSummary(_standalone(_thread(10, '已有作品')), '主页列表摘要');
        final String canonicalKey = aggregator.canonicalKeyForWork(work)!;
        await indexRepository.save(
            canonicalKey: canonicalKey,
            work: _withId(work, aggregator.workIdForCanonicalKey(canonicalKey)),
        );

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(result.work.id, startsWith('forum-work:'));
        expect(result.work.summary, '主页列表摘要');
        expect(
            (await indexRepository.loadByCanonicalKey(
                canonicalKey,
                LibraryKind.comic,
            ))!
                .work
                .summary,
            isEmpty,
        );
        verifyNever(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: any(named: 'forceReload'),
            ),
        );
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('同名小说不会命中漫画目录的来源映射', () async
    {
        final Work comicSeed = _standalone(
            _thread(11, '一周一次买下同班同学的那些事'),
        );
        final Work comicIndex = Work(
            id: comicSeed.id,
            kind: comicSeed.kind,
            title: comicSeed.title,
            summary: comicSeed.summary,
            author: comicSeed.author,
            typeName: comicSeed.typeName,
            sourceThreads: comicSeed.sourceThreads,
            chapters: <Chapter>[
                ...comicSeed.chapters,
                Chapter(
                    id: 'forum-thread:12',
                    title: '小说原作',
                    sourceUri: _threadUri(12),
                    sourceTid: 12,
                ),
            ],
            directories: comicSeed.directories,
        );
        final Work novel = _standalone(
            _thread(
                12,
                '一周一次买下同班同学的那些事',
                board: ForumBoard.lightNovel,
            ),
        );
        final String comicKey = aggregator.canonicalKeyForWork(comicIndex)!;
        final String novelKey = aggregator.canonicalKeyForWork(novel)!;
        await indexRepository.save(
            canonicalKey: comicKey,
            work: comicIndex,
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((_) async => _emptyPage(novel));

        final WorkIndexRecord? beforeIndex = await coordinator.lookup(novel);
        final WorkIndexResult result = await coordinator.ensure(novel);

        expect(beforeIndex, isNull);
        expect(result.work.kind, LibraryKind.novel);
        expect(result.work.primarySourceTid, 12);
        expect(
            await indexRepository.loadByCanonicalKey(
                comicKey,
                LibraryKind.comic,
            ),
            isNotNull,
        );
        expect(
            await indexRepository.loadByCanonicalKey(
                novelKey,
                LibraryKind.novel,
            ),
            isNotNull,
        );
    });

    test('普通小说优先持久化帖内 pid 目录且不搜索', () async
    {
        final Work work = _standalone(
            _thread(20, '没有章节标记的小说', board: ForumBoard.literature),
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((_) async => _directoryPage(work));
        final Completer<void> unsendableState = Completer<void>();
        final List<String> progressMessages = <String>[];

        final WorkIndexResult result = await coordinator.ensure(
            work,
            onProgress: (String message)
            {
                progressMessages.add(message);
                if (message == '正在保存作品索引' &&
                        !unsendableState.isCompleted)
                {
                    unsendableState.complete();
                }
            },
        );

        expect(result.work.chapters, hasLength(2));
        expect(unsendableState.isCompleted, isTrue);
        expect(progressMessages, contains('正在解析当前小说主题'));
        expect(
            result.work.chapters.map((Chapter chapter) => chapter.sourcePid),
            <int?>[201, 202],
        );
        expect(
            await indexRepository.loadBySourceTid(20, LibraryKind.novel),
            isNotNull,
        );
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('普通连载即使标题带章节号也不跨帖搜索', () async
    {
        final SourceThread firstThread = _thread(
            30,
            '测试小说 第1章',
            board: ForumBoard.literature,
        );
        final Work work = _standalone(firstThread);
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((_) async => _emptyPage(work));

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(result.work.chapters, hasLength(1));
        verifyNever(
            () => searchRepository.search(keyword: '测试小说', kind: LibraryKind.novel),
        );
    });

    test('小说跨帖范围链接直接展开一层并按目标楼主分目录', () async
    {
        final SourceThread root = _thread(
            535839,
            '范围小说',
            board: ForumBoard.lightNovel,
            author: '译者甲',
        );
        final Work work = _standalone(root);
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread =
                    invocation.positionalArguments.first as SourceThread;
            if (thread.tid == root.tid)
            {
                return _rangeRootPage(
                    root,
                    targetTid: 529610,
                    rangeLabel: '第1-5话',
                );
            }
            if (thread.tid == 529610)
            {
                return _rangeTargetPage(
                    thread,
                    author: '译者乙',
                    nestedTargetTid: 529611,
                );
            }
            throw StateError('不应继续展开第二层范围链接');
        });

        final WorkIndexResult result = await coordinator.ensure(work);
        final WorkDirectory targetDirectory = result.work.directories.firstWhere(
            (WorkDirectory directory) => directory.owner == '译者乙',
        );

        expect(
            result.work.directories.map((WorkDirectory directory) => directory.owner),
            containsAll(<String>['译者甲', '译者乙']),
        );
        expect(
            targetDirectory.chapters.map((Chapter chapter) => chapter.title),
            <String>['第1话', '第2话', '第3话', '第4话', '第5话'],
        );
        expect(
            targetDirectory.chapters.map((Chapter chapter) => chapter.sourcePid),
            everyElement(isNotNull),
        );
        verify(
            () => libraryRepository.loadThread(
                any(
                    that: predicate<SourceThread>(
                        (SourceThread thread) => thread.tid == 529610,
                    ),
                ),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).called(1);
        verifyNever(
            () => libraryRepository.loadThread(
                any(
                    that: predicate<SourceThread>(
                        (SourceThread thread) => thread.tid == 529611,
                    ),
                ),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        );
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('小说跨帖范围目标无法解析时保留合并范围入口', () async
    {
        final SourceThread root = _thread(
            535840,
            '失效范围小说',
            board: ForumBoard.lightNovel,
            author: '译者',
        );
        final Work work = _standalone(root);
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread =
                    invocation.positionalArguments.first as SourceThread;
            if (thread.tid == root.tid)
            {
                return _rangeRootPage(
                    root,
                    targetTid: 529620,
                    rangeLabel: '第1-5话',
                );
            }
            return _emptyPage(_standalone(thread));
        });

        final WorkIndexResult result = await coordinator.ensure(work);
        final Chapter rangeChapter = result.work.directories
                .expand((WorkDirectory directory) => directory.chapters)
                .singleWhere((Chapter chapter) => chapter.sourceTid == 529620);

        expect(rangeChapter.sourcePid, isNull);
        expect(rangeChapter.title, contains('1-5'));
        verify(
            () => libraryRepository.loadThread(
                any(
                    that: predicate<SourceThread>(
                        (SourceThread thread) => thread.tid == 529620,
                    ),
                ),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).called(1);
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('明确分卷小说搜索卷组并逐卷展开帖内章节', () async
    {
        final SourceThread first = _thread(
            30,
            '[轻小说] 测试小说[第一卷]【完】（第二卷已开坑，见新贴）',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final SourceThread second = _thread(
            31,
            '[轻小说] 测试小说 第二卷',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final Work work = _standalone(first);
        final ForumSearchPage searchPage = ForumSearchPage(
            kind: LibraryKind.novel,
            keyword: '测试小说',
            searchId: 'novel-volume-1',
            sourceThreads: <SourceThread>[first, second],
            currentPage: 1,
            totalPages: 1,
        );
        when(
            () => searchRepository.search(keyword: '测试小说', kind: LibraryKind.novel),
        ).thenAnswer((_) async => searchPage);
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread = invocation.positionalArguments.first as SourceThread;
            return _directoryPageForThread(thread);
        });

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(result.work.title, '测试小说');
        expect(result.work.sourceThreads.map((SourceThread thread) => thread.tid), <int>[
            30,
            31,
        ]);
        expect(result.work.chapters, hasLength(4));
        expect(
            result.work.chapters.map((Chapter chapter) => chapter.novelEdition).toSet(),
            <NovelEdition>{NovelEdition.book},
        );
        expect(
            result.work.chapters.map((Chapter chapter) => chapter.volumeTitle),
            <String>['第一卷', '第一卷', '第二卷', '第二卷'],
        );
        verify(
            () => searchRepository.search(keyword: '测试小说', kind: LibraryKind.novel),
        ).called(1);
    });

    test('裸卷号经搜索确认后与明确卷聚合且 EX 不冒充卷号', () async
    {
        final SourceThread first = _thread(
            505406,
            '[轻小说] [转载][kiki]裸卷小说 01 [日翻/简]',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: 'kiki',
        );
        final SourceThread second = _thread(
            505794,
            '[轻小说] [转载][kiki]裸卷小说 02 [日翻/简]',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: 'kiki',
        );
        final SourceThread third = _thread(
            523062,
            '[轻小说] [自翻][kiki][裸卷小说] 3 【完结】',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: 'kiki',
        );
        final SourceThread fifth = _thread(
            558094,
            '[轻小说] [自翻][kiki][裸卷小说] '
            '第五卷 [更新 010 扭曲]',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: 'kiki',
        );
        final SourceThread extra6 = _thread(
            558096,
            '[轻小说] [自翻][kiki][裸卷小说] EX6',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: 'kiki',
        );
        final SourceThread extra10 = _thread(
            558100,
            '[轻小说] [自翻][kiki][裸卷小说] EX10',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: 'kiki',
        );
        final Work work = _standalone(first);
        when(
            () => searchRepository.search(
                keyword: '裸卷小说',
                kind: LibraryKind.novel,
            ),
        ).thenAnswer((_) async => ForumSearchPage(
                kind: LibraryKind.novel,
                keyword: '裸卷小说',
                searchId: 'novel-bare-volumes',
                sourceThreads: <SourceThread>[
                    first,
                    second,
                    third,
                    fifth,
                    extra6,
                    extra10,
                ],
                currentPage: 1,
                totalPages: 1,
            ));
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            return _directoryPageForThread(
                invocation.positionalArguments.first as SourceThread,
            );
        });

        final WorkIndexResult result = await coordinator.ensure(work);
        final List<Chapter> bookChapters = result.work.directories
                .expand((WorkDirectory directory) => directory.chapters)
                .where(
                    (Chapter chapter) => chapter.novelEdition == NovelEdition.book,
                )
                .toList(growable: false);

        expect(
            bookChapters.map((Chapter chapter) => chapter.sourceTid).toSet(),
            <int>{505406, 505794, 523062, 558094},
        );
        expect(
            bookChapters.map((Chapter chapter) => chapter.volumeOrder).toSet(),
            <double?>{1, 2, 3, 5},
        );
        expect(
            bookChapters.map((Chapter chapter) => chapter.volumeOrder),
            isNot(contains(anyOf(6, 10))),
        );
        verify(
            () => searchRepository.search(
                keyword: '裸卷小说',
                kind: LibraryKind.novel,
            ),
        ).called(1);
    });

    test('主动搜索中的裸卷组复用现有 searchid 而不再搜索', () async
    {
        final List<SourceThread> threads = <SourceThread>[
            _thread(
                505406,
                '[轻小说] [转载][kiki]裸卷作品 01 [日翻/简]',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: 'kiki',
            ),
            _thread(
                505794,
                '[轻小说] [转载][kiki]裸卷作品 02 [日翻/简]',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: 'kiki',
            ),
            _thread(
                558094,
                '[轻小说] [自翻][kiki][裸卷作品] 第五卷',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: 'kiki',
            ),
        ];
        final Work work = aggregator.aggregate(threads).single;
        expect(coordinator.shouldCompleteActiveSearch(work), isTrue);
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: true,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            return _directoryPageForThread(
                invocation.positionalArguments.first as SourceThread,
            );
        });

        final WorkIndexResult result = await coordinator.rebuildFromActiveSearch(
            work,
        );

        expect(
            result.work.chapters.map((Chapter chapter) => chapter.volumeOrder).toSet(),
            <double?>{1, 2, 5},
        );
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('主动搜索选中小说时会合并同作品的跨译者分卷', ()
    {
        final Work selected = _standalone(
            _thread(
                601,
                '[轻小说] 测试小说 第一卷',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: '译者甲',
            ),
        );
        final Work second = _standalone(
            _thread(
                602,
                '[轻小说] 测试小说 第二卷',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: '译者乙',
            ),
        );
        final Work sixth = _standalone(
            _thread(
                606,
                '[轻小说] 测试小说 第六卷',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: '译者丙',
            ),
        );

        final Work? matched = coordinator.findMatchingWork(
            selected,
            <Work>[selected, second, sixth],
        );

        expect(
            matched!.sourceThreads.map((SourceThread thread) => thread.tid).toSet(),
            <int>{601, 602, 606},
        );
    });

    test('主动搜索中的相邻卷号主题与显式卷号一起展开', () async
    {
        final List<Work> candidates = <SourceThread>[
            _thread(
                603,
                '[轻小说] 百日百合3',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: '译者甲',
            ),
            _thread(
                604,
                '[轻小说] 百日百合4 【完】',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: '译者甲',
            ),
            _thread(
                606,
                '[轻小说] 百日百合 第六卷',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: '译者乙',
            ),
            _thread(
                608,
                '[轻小说] 百日百合 第八卷',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: '译者丙',
            ),
        ].map(_standalone).toList(growable: false);
        final Work work = coordinator.findMatchingWork(
            candidates[1],
            candidates,
        )!;
        final List<int> loadedTids = <int>[];
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: true,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread = invocation.positionalArguments.first
                    as SourceThread;
            loadedTids.add(thread.tid);
            return _directoryPageForThread(thread);
        });

        final WorkIndexResult result = await coordinator.rebuildFromActiveSearch(
            work,
        );

        expect(loadedTids.toSet(), <int>{603, 604, 606, 608});
        expect(
            result.work.chapters.map((Chapter chapter) => chapter.volumeOrder).toSet(),
            <double?>{3, 4, 6, 8},
        );
    });

    test('分卷搜索同时保留连载版和单行本但不混合章节', () async
    {
        final SourceThread serial = _thread(
            40,
            '[轻小说]【WEB版】双版本小说',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final SourceThread first = _thread(
            41,
            '[轻小说]【文库版】双版本小说 第一卷',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final SourceThread second = _thread(
            42,
            '[轻小说]【文库版】双版本小说 第二卷',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final Work work = _standalone(first);
        when(
            () => searchRepository.search(keyword: '双版本小说', kind: LibraryKind.novel),
        ).thenAnswer((_) async => ForumSearchPage(
                kind: LibraryKind.novel,
                keyword: '双版本小说',
                searchId: 'novel-editions',
                sourceThreads: <SourceThread>[serial, first, second],
                currentPage: 1,
                totalPages: 1,
            ));
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            return _directoryPageForThread(
                invocation.positionalArguments.first as SourceThread,
            );
        });

        final WorkIndexResult result = await coordinator.ensure(work);
        final WorkDirectory directory = result.work.directories.single;

        expect(
            directory.chapters
                    .where((Chapter chapter) => chapter.novelEdition == NovelEdition.serial),
            hasLength(2),
        );
        expect(
            directory.chapters
                    .where((Chapter chapter) => chapter.novelEdition == NovelEdition.book),
            hasLength(4),
        );
        expect(
            directory.chapters
                    .where((Chapter chapter) => chapter.novelEdition == NovelEdition.book)
                    .map((Chapter chapter) => chapter.volumeTitle)
                    .toSet(),
            <String>{'第一卷', '第二卷'},
        );
    });

    test('显式卷目录沿链接展开且任一卷入口命中同一持久索引', () async
    {
        final SourceThread root = _thread(
            50,
            '[轻小说] 百日百合',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final Work work = _standalone(root);
        when(
            () => searchRepository.search(keyword: '百日百合', kind: LibraryKind.novel),
        ).thenAnswer((_) async => ForumSearchPage(
                kind: LibraryKind.novel,
                keyword: '百日百合',
                searchId: 'novel-volume-links',
                sourceThreads: <SourceThread>[root],
                currentPage: 1,
                totalPages: 1,
            ));
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread = invocation.positionalArguments.first as SourceThread;
            if (thread.tid == 50)
            {
                return _volumeLinkPage(root);
            }
            return _directoryPageForThread(thread);
        });

        final WorkIndexResult firstResult = await coordinator.ensure(work);
        final Work volumeEntry = _standalone(
            _thread(
                51,
                '[轻小说] 百日百合 Vol.2',
                board: ForumBoard.lightNovel,
                typeName: '#轻小说',
                author: '译者',
            ),
        );
        final WorkIndexResult secondResult = await coordinator.ensure(volumeEntry);

        expect(firstResult.work.sourceThreads.map((SourceThread value) => value.tid), <int>[
            50,
            51,
        ]);
        expect(
            firstResult.work.chapters.map((Chapter chapter) => chapter.volumeTitle).toSet(),
            <String>{'Vol.1', 'Vol.2'},
        );
        expect(secondResult.work.id, firstResult.work.id);
        expect(secondResult.work.chapters.length, firstResult.work.chapters.length);
        verify(
            () => searchRepository.search(keyword: '百日百合', kind: LibraryKind.novel),
        ).called(1);
    });

    test('显式卷目录可信于入口番外标题且仍展开实际分卷', () async
    {
        final SourceThread root = _thread(
            50,
            '[轻小说] 目录标题偏差 番外『心跳』',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final SourceThread volume = _thread(
            51,
            '[轻小说] 目录标题偏差 第二卷',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final Work work = _standalone(root);
        when(
            () => searchRepository.search(
                keyword: '目录标题偏差 番外『心跳』',
                kind: LibraryKind.novel,
            ),
        ).thenAnswer((_) async => ForumSearchPage(
                kind: LibraryKind.novel,
                keyword: '目录标题偏差 番外『心跳』',
                searchId: 'novel-volume-mismatched-anchor',
                sourceThreads: <SourceThread>[root],
                currentPage: 1,
                totalPages: 1,
            ));
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread = invocation.positionalArguments.first as SourceThread;
            return thread.tid == root.tid
                    ? _volumeLinkPage(root)
                    : _directoryPageForThread(volume);
        });

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(
            result.work.sourceThreads.map((SourceThread thread) => thread.tid),
            <int>[50, 51],
        );
        expect(
            result.work.directories.single.chapters
                    .where((Chapter chapter) => chapter.sourceTid == 51),
            hasLength(2),
        );
    });

    test('分卷索引只追踪卷帖而不递归展开特典和短篇链接', () async
    {
        final SourceThread root = _thread(
            50,
            '[轻小说] 精简分卷小说',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final SourceThread volume = _thread(
            51,
            '[轻小说] 精简分卷小说 第二卷',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final SourceThread extra = _thread(
            52,
            '[轻小说] 精简分卷小说 日常短篇',
            board: ForumBoard.lightNovel,
            typeName: '#轻小说',
            author: '译者',
        );
        final Work work = _standalone(root);
        when(
            () => searchRepository.search(
                keyword: '精简分卷小说',
                kind: LibraryKind.novel,
            ),
        ).thenAnswer((_) async => ForumSearchPage(
                kind: LibraryKind.novel,
                keyword: '精简分卷小说',
                searchId: 'novel-volume-only',
                sourceThreads: <SourceThread>[root],
                currentPage: 1,
                totalPages: 1,
            ));
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread = invocation.positionalArguments.first as SourceThread;
            return switch (thread.tid)
            {
                50 => _volumeLinkPageWithExtra(root),
                51 => _directoryPageForThread(volume),
                _ => _directoryPageForThread(extra),
            };
        });

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(
            result.work.sourceThreads.map((SourceThread thread) => thread.tid),
            <int>[50, 51],
        );
        verifyNever(
            () => libraryRepository.loadThread(
                any(
                    that: predicate<SourceThread>(
                        (SourceThread thread) => thread.tid == 52,
                    ),
                ),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        );
    });

    test('漫画跨帖范围链接按目标帖实际目录展开', () async
    {
        final SourceThread root = _thread(
            535841,
            '范围漫画',
            author: '楼主甲',
        );
        final Work work = _standalone(root);
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread =
                    invocation.positionalArguments.first as SourceThread;
            return thread.tid == root.tid
                    ? _rangeRootPage(
                        root,
                        targetTid: 529630,
                        rangeLabel: '第1-5话',
                    )
                    : _rangeTargetPage(thread, author: '楼主乙');
        });

        final WorkIndexResult result = await coordinator.ensure(work);
        final List<Chapter> expanded = result.work.chapters
                .where((Chapter chapter) => chapter.sourceTid == 529630)
                .toList(growable: false);

        expect(
            expanded.map((Chapter chapter) => chapter.title),
            <String>['第1话', '第2话', '第3话', '第4话', '第5话'],
        );
        expect(
            expanded.map((Chapter chapter) => chapter.sourcePid),
            everyElement(isNotNull),
        );
        verify(
            () => libraryRepository.loadThread(
                any(
                    that: predicate<SourceThread>(
                        (SourceThread thread) => thread.tid == 529630,
                    ),
                ),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).called(1);
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('主页单章漫画会新建一次搜索并拉完 searchid 分页', () async
    {
        final SourceThread firstThread = _longComicThread(101, '测试长篇 第1话');
        final SourceThread secondThread = _longComicThread(102, '测试长篇 第2话');
        final SourceThread thirdThread = _longComicThread(103, '测试长篇 第3话');
        final Work work = _standalone(firstThread);
        final ForumSearchPage firstPage = ForumSearchPage(
            kind: LibraryKind.comic,
            keyword: '测试长篇',
            searchId: '88',
            sourceThreads: <SourceThread>[firstThread],
            currentPage: 1,
            totalPages: 2,
            nextPageUri: Uri.parse(
                'https://bbs.yamibo.com/search.php?searchid=88&page=2',
            ),
        );
        final ForumSearchPage secondPage = ForumSearchPage(
            kind: LibraryKind.comic,
            keyword: '测试长篇',
            searchId: '88',
            sourceThreads: <SourceThread>[secondThread, thirdThread],
            currentPage: 2,
            totalPages: 2,
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((_) async => _emptyPage(work));
        when(
            () => searchRepository.search(keyword: '测试长篇', kind: LibraryKind.comic),
        ).thenAnswer((_) async => firstPage);
        when(
            () => searchRepository.loadNext(firstPage),
        ).thenAnswer((_) async => secondPage);

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(result.work.id, work.id);
        expect(result.work.chapters, hasLength(3));
        expect(
            result.work.chapters.map((Chapter chapter) => chapter.sourceTid),
            <int>[101, 102, 103],
        );
        expect(
            await indexRepository.loadBySourceTid(103, LibraryKind.comic),
            isNotNull,
        );
        verify(
            () => searchRepository.search(keyword: '测试长篇', kind: LibraryKind.comic),
        ).called(1);
        verify(() => searchRepository.loadNext(firstPage)).called(1);
    });

    test('带空格副标题的长篇从不同章节入口复用完整持久索引', () async
    {
        final SourceThread chapter14 = _longComicThread(
            561912,
            '【提灯喵汉化组】'
            '[原作：みかみてれん×漫画：千種みのり]'
            '女孩们×吸血鬼 14 露露娜大人、瓮中捉鳖',
        );
        final SourceThread chapter21 = _longComicThread(
            563955,
            '【提灯喵汉化组】'
            '[原作：みかみてれん×漫画：千種みのり]'
            '女孩们×吸血鬼 21 露露娜大人、想让人类臣服',
        );
        final Work firstEntry = _standalone(chapter14);
        final Work secondEntry = _standalone(chapter21);
        final SourceThread searchChapter14 = _thread(
            chapter14.tid,
            chapter14.title,
        );
        final SourceThread searchChapter21 = _thread(
            chapter21.tid,
            chapter21.title,
        );
        final ForumSearchPage searchPage = ForumSearchPage(
            kind: LibraryKind.comic,
            keyword: '女孩们×吸血鬼',
            searchId: 'girls-vampire',
            sourceThreads: <SourceThread>[searchChapter14, searchChapter21],
            currentPage: 1,
            totalPages: 1,
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread =
                    invocation.positionalArguments.first as SourceThread;
            return ForumThreadPage(
                tid: thread.tid,
                board: thread.board,
                title: thread.title,
                typeName: '#長篇連載',
                uri: thread.uri,
                posts: const <SourcePost>[],
                currentPage: 1,
                totalPages: 1,
            );
        });
        when(
            () =>
                    searchRepository.search(keyword: '女孩们×吸血鬼', kind: LibraryKind.comic),
        ).thenAnswer((_) async => searchPage);

        final WorkIndexResult from14 = await coordinator.ensure(firstEntry);
        final WorkIndexResult from21 = await coordinator.ensure(secondEntry);

        expect(from14.work.chapters, hasLength(2));
        expect(from21.work.chapters, hasLength(2));
        expect(from21.work.id, from14.work.id);
        expect(
            await indexRepository.loadBySourceTid(563955, LibraryKind.comic),
            isNotNull,
        );
        verify(
            () =>
                    searchRepository.search(keyword: '女孩们×吸血鬼', kind: LibraryKind.comic),
        ).called(1);
        verify(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).called(1);
    });

    test('明确长篇分类即使标题无章节号也会触发跨帖搜索', () async
    {
        final SourceThread thread = _longComicThread(201, 'Love Bullet');
        final Work work = _standalone(thread);
        final ForumSearchPage page = ForumSearchPage(
            kind: LibraryKind.comic,
            keyword: 'Love Bullet',
            searchId: '90',
            sourceThreads: <SourceThread>[thread],
            currentPage: 1,
            totalPages: 1,
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((_) async => _emptyPage(work));
        when(
            () => searchRepository.search(
                keyword: 'Love Bullet',
                kind: LibraryKind.comic,
            ),
        ).thenAnswer((_) async => page);

        await coordinator.ensure(work);

        verify(
            () => searchRepository.search(
                keyword: 'Love Bullet',
                kind: LibraryKind.comic,
            ),
        ).called(1);
    });

    test('非长篇漫画即使标题带章节号也不自动搜索', () async
    {
        final Work work = _standalone(_thread(211, '短篇合集 第1话'));
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((_) async => _emptyPage(work));

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(result.work.chapters, hasLength(1));
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('明确短篇漫画会检查帖页但无强目录证据时保持单帖', () async
    {
        final Work work = _standalone(
            _thread(212, '短篇集作品 第1话', typeId: 68, typeName: '#短篇漫畫'),
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer(
            (_) async => ForumThreadPage(
                tid: 212,
                board: ForumBoard.comic,
                title: '短篇集作品 第1话',
                typeName: '#短篇漫畫',
                uri: _threadUri(212),
                posts: const <SourcePost>[],
                currentPage: 1,
                totalPages: 1,
            ),
        );

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(result.work.chapters, hasLength(1));
        expect(result.work.chapters.single.sourceTid, 212);
        verify(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).called(1);
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('搜索结果缺少分类时按帖子页短篇标签折叠为当前单帖', () async
    {
        final Work work = aggregator.aggregate(<SourceThread>[
            _thread(213, '短篇集作品 第11话'),
            _thread(214, '短篇集作品 第12话'),
        ]).single;
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: true,
            ),
        ).thenAnswer(
            (_) async => ForumThreadPage(
                tid: 214,
                board: ForumBoard.comic,
                title: '短篇集作品 第12话',
                typeName: '#短篇漫畫',
                uri: _threadUri(214),
                posts: const <SourcePost>[],
                currentPage: 1,
                totalPages: 1,
            ),
        );

        final WorkIndexResult result = await coordinator.rebuildFromActiveSearch(work);

        expect(work.chapters, hasLength(2));
        expect(result.work.chapters, hasLength(1));
        expect(result.work.chapters.single.sourceTid, 214);
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('短篇标签有同作品强目录证据时纠正为长篇并复用索引', () async
    {
        final SourceThread seedThread = _thread(
            215,
            '魔法少女与前邪恶女干部 02-03',
            typeId: 68,
            typeName: '#短篇漫畫',
        );
        final Work seed = _standalone(seedThread);
        final ForumThreadPage directoryPage = ForumThreadPage(
            tid: 215,
            board: ForumBoard.comic,
            title: seedThread.title,
            typeName: '#短篇漫畫',
            uri: seedThread.uri,
            posts: <SourcePost>[
                SourcePost(
                    pid: 2150,
                    tid: 215,
                    page: 1,
                    floor: 1,
                    author: '楼主',
                    timeLabel: '',
                    isOriginalPoster: true,
                    blocks: const <PostContentBlock>[PostTextBlock(text: '目录')],
                    links: <ThreadLink>[
                        _threadChapterLink('第1话', 214),
                        _threadChapterLink('02-03', 215),
                    ],
                ),
            ],
            currentPage: 1,
            totalPages: 1,
        );
        final ForumSearchPage searchPage = ForumSearchPage(
            kind: LibraryKind.comic,
            keyword: '魔法少女与前邪恶女干部',
            searchId: 'short-tag-override',
            sourceThreads: <SourceThread>[
                _thread(215, '魔法少女与前邪恶女干部 02-03'),
            ],
            currentPage: 1,
            totalPages: 1,
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((_) async => directoryPage);
        when(
            () => searchRepository.search(
                keyword: '魔法少女与前邪恶女干部',
                kind: LibraryKind.comic,
            ),
        ).thenAnswer((_) async => searchPage);

        final WorkIndexResult result = await coordinator.ensure(seed);
        final Work otherEntry = _standalone(
            _thread(
                214,
                '魔法少女与前邪恶女干部 第1话',
                typeId: 68,
                typeName: '#短篇漫畫',
            ),
        );
        final WorkIndexRecord? reused = await coordinator.lookup(otherEntry);

        expect(result.work.chapters.map((Chapter chapter) => chapter.title), <String>[
            '第1话',
            '02-03',
        ]);
        expect(reused?.work.id, result.work.id);
        verify(
            () => searchRepository.search(
                keyword: '魔法少女与前邪恶女干部',
                kind: LibraryKind.comic,
            ),
        ).called(1);
    });

    test('明确长篇即使命中 Tag 目录也先用一次搜索统一作品', () async
    {
        final SourceThread thread = _longComicThread(221, 'Tag 目录作品');
        final Work work = _standalone(thread);
        final Uri tagUri = Uri.parse(
            'https://bbs.yamibo.com/misc.php?mod=tag&id=99&mobile=2',
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer(
            (_) async => ForumThreadPage(
                tid: thread.tid,
                board: thread.board,
                title: thread.title,
                uri: thread.uri,
                posts: <SourcePost>[
                    SourcePost(
                        pid: 2200,
                        tid: thread.tid,
                        page: 1,
                        floor: 1,
                        author: '楼主',
                        timeLabel: '',
                        isOriginalPoster: true,
                        blocks: const <PostContentBlock>[PostTextBlock(text: '本作目录')],
                        links: <ThreadLink>[
                            ThreadLink(
                                label: '本作目录',
                                uri: tagUri,
                                kind: ThreadLinkKind.directory,
                            ),
                        ],
                    ),
                ],
                currentPage: 1,
                totalPages: 1,
            ),
        );
        when(
            () => libraryRepository.loadTagDirectory(tagUri, forceReload: false),
        ).thenAnswer(
            (_) async => <ThreadLink>[
                _threadChapterLink('Tag 目录作品 第1话', 221),
                _threadChapterLink('Tag 目录作品 第2话', 222),
            ],
        );
        when(
            () =>
                    searchRepository.search(keyword: 'Tag 目录作品', kind: LibraryKind.comic),
        ).thenAnswer(
            (_) async => ForumSearchPage(
                kind: LibraryKind.comic,
                keyword: 'Tag 目录作品',
                searchId: 'tag-directory',
                sourceThreads: <SourceThread>[thread],
                currentPage: 1,
                totalPages: 1,
            ),
        );

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(result.work.chapters, hasLength(2));
        expect(
            result.work.chapters.map((Chapter chapter) => chapter.title),
            <String>['第1话', '第2话'],
        );
        verify(
            () =>
                    searchRepository.search(keyword: 'Tag 目录作品', kind: LibraryKind.comic),
        ).called(1);
    });

    test('排行榜 Tag 后追加的早期裸章节号按真实话数持久化', () async
    {
        final SourceThread thread = _longComicThread(527487, '安达与岛村');
        final Work work = _standalone(thread);
        final Uri tagUri = Uri.parse(
            'https://bbs.yamibo.com/misc.php?mod=tag&id=adachi&mobile=2',
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer(
            (_) async => ForumThreadPage(
                tid: thread.tid,
                board: thread.board,
                title: thread.title,
                uri: thread.uri,
                posts: <SourcePost>[
                    SourcePost(
                        pid: 527400,
                        tid: thread.tid,
                        page: 1,
                        floor: 1,
                        author: '楼主',
                        timeLabel: '',
                        isOriginalPoster: true,
                        blocks: const <PostContentBlock>[PostTextBlock(text: '目录')],
                        links: <ThreadLink>[
                            ThreadLink(
                                label: '本作目录',
                                uri: tagUri,
                                kind: ThreadLinkKind.directory,
                            ),
                            _threadChapterLink('1', 499384),
                            _threadChapterLink('2', 499385),
                            _threadChapterLink('12后', 507904),
                        ],
                    ),
                ],
                currentPage: 1,
                totalPages: 1,
            ),
        );
        when(
            () => libraryRepository.loadTagDirectory(tagUri, forceReload: false),
        ).thenAnswer(
            (_) async => <ThreadLink>[
                _threadChapterLink('安达与岛村 14', 509650),
                _threadChapterLink('安达与岛村 13', 509746),
                _threadChapterLink('安达与岛村 28', 527487),
            ],
        );
        when(
            () => searchRepository.search(keyword: '安达与岛村', kind: LibraryKind.comic),
        ).thenAnswer(
            (_) async => ForumSearchPage(
                kind: LibraryKind.comic,
                keyword: '安达与岛村',
                searchId: 'adachi',
                sourceThreads: <SourceThread>[thread],
                currentPage: 1,
                totalPages: 1,
            ),
        );

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(
            result.work.chapters.map((Chapter chapter) => chapter.title),
            <String>['1', '2', '12后', '13', '14', '28'],
        );
        expect(
            result.work.chapters.map((Chapter chapter) => chapter.order),
            <double?>[1, 2, 12.003, 13, 14, 28],
        );
        verify(
            () => searchRepository.search(keyword: '安达与岛村', kind: LibraryKind.comic),
        ).called(1);
    });

    test('Tag 同序号的不同条目保留且不影响索引更新', () async
    {
        final SourceThread thread = _longComicThread(231, 'Tag 同序号作品');
        final Work work = _standalone(thread);
        final Uri tagUri = Uri.parse(
            'https://bbs.yamibo.com/misc.php?mod=tag&id=100&mobile=2',
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((_) async => _tagDirectoryPage(work, tagUri));
        when(
            () => libraryRepository.loadTagDirectory(tagUri, forceReload: false),
        ).thenAnswer(
            (_) async => <ThreadLink>[
                _threadChapterLink('Tag 同序号作品 第8话', 231),
                _threadChapterLink('属于我们的第一次 CH8 特别篇', 232),
                _threadChapterLink('Tag 同序号作品 第9话', 233),
            ],
        );

        final WorkIndexResult result = await coordinator.ensure(work);

        expect(result.work.chapters, hasLength(3));
        expect(
            result.work.chapters.where((Chapter chapter) => chapter.order == 8),
            hasLength(2),
        );
    });

    test('主动搜索全集按楼主分目录并各自选最高正文章节解析', () async
    {
        final List<SourceThread> threads = <SourceThread>[
            _thread(241, '[汉化][作者]多来源作品 第1话', author: '楼主甲'),
            _thread(242, '[汉化][作者]多来源作品 第8话', author: '楼主甲'),
            _thread(251, '[汉化][作者]多来源作品 第1话', author: '楼主乙'),
            _thread(252, '[汉化][作者]多来源作品 第12话', author: '楼主乙'),
        ];
        final Work work = aggregator.aggregate(threads.reversed.toList()).single;
        final List<int> loadedTids = <int>[];
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: true,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread =
                    invocation.positionalArguments.first as SourceThread;
            loadedTids.add(thread.tid);
            final int ownTid = thread.author == '楼主甲' ? 241 : 251;
            return ForumThreadPage(
                tid: thread.tid,
                board: thread.board,
                title: thread.title,
                uri: thread.uri,
                posts: <SourcePost>[
                    SourcePost(
                        pid: thread.tid * 10,
                        tid: thread.tid,
                        page: 1,
                        floor: 1,
                        author: thread.author,
                        timeLabel: '',
                        isOriginalPoster: true,
                        blocks: const <PostContentBlock>[
                            PostTextBlock(text: '目录'),
                        ],
                        links: <ThreadLink>[
                            _threadChapterLink('多来源作品 第1话', ownTid),
                            _threadChapterLink('多来源作品 番外', 260),
                        ],
                    ),
                ],
                currentPage: 1,
                totalPages: 1,
            );
        });

        final WorkIndexResult result = await coordinator.rebuildFromActiveSearch(
            work,
        );

        expect(loadedTids.toSet(), <int>{242, 252});
        expect(result.work.directories, hasLength(3));
        expect(
            result.work.directories.map((WorkDirectory value) => value.owner).toSet(),
            <String>{'楼主甲', '楼主乙', '未归属来源'},
        );
        expect(
            result.work.directories
                .firstWhere(
                    (WorkDirectory value) => value.owner == '未归属来源',
                )
                .chapters
                .single
                .sourceTid,
            260,
        );
        expect(
            result.work.directories
                .where((WorkDirectory value) => value.owner != '未归属来源')
                .every(
                    (WorkDirectory value) => value.chapters.every(
                        (Chapter chapter) => chapter.sourceTid != 260,
                    ),
                ),
            isTrue,
        );
        expect(
            result.work.directories
                .where((WorkDirectory value) => value.owner != '未归属来源')
                .every(
                    (WorkDirectory value) => !value.sourceTids.contains(260),
                ),
            isTrue,
        );
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('详情刷新搜索失败时保留旧目录和更新时间', () async
    {
        final List<SourceThread> threads = <SourceThread>[
            _longComicThread(301, '不会降级 第1话'),
            _longComicThread(302, '不会降级 第2话'),
            _longComicThread(303, '不会降级 第3话'),
        ];
        final Work grouped = aggregator.aggregate(threads).single;
        final String canonicalKey = aggregator.canonicalKeyForWork(grouped)!;
        final DateTime oldUpdatedAt = DateTime(2026, 7, 12, 8);
        await indexRepository.save(
            canonicalKey: canonicalKey,
            work: grouped,
            updatedAt: oldUpdatedAt,
        );
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: true,
            ),
        ).thenAnswer((_) async => _emptyPage(grouped));
        when(
            () => searchRepository.search(keyword: '不会降级', kind: LibraryKind.comic),
        ).thenThrow(StateError('第二页网络失败'));

        final WorkIndexResult result = await coordinator.refresh(grouped);
        final WorkIndexRecord stored = (await indexRepository.loadByCanonicalKey(
            canonicalKey,
            LibraryKind.comic,
        ))!;

        expect(result.work.chapters, hasLength(3));
        expect(result.warning, contains('已保留上次作品索引'));
        expect(stored.work.chapters, hasLength(3));
        expect(stored.updatedAt, oldUpdatedAt);
    });

    test('同一未索引小说的并发点击共用一次解析任务', () async
    {
        final Work work = _standalone(
            _thread(401, '并发作品', board: ForumBoard.literature),
        );
        final Completer<ForumThreadPage> completer = Completer<ForumThreadPage>();
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((_) => completer.future);

        final Future<WorkIndexResult> first = coordinator.ensure(work);
        final Future<WorkIndexResult> second = coordinator.ensure(work);
        completer.complete(_emptyPage(work));
        final List<WorkIndexResult> results = await Future.wait(
            <Future<WorkIndexResult>>[first, second],
        );

        expect(results.first.work.id, results.last.work.id);
        verify(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).called(1);
    });

    test('详情退出后取消进行中的帖子解析且不写入作品索引', () async
    {
        final Work work = _standalone(
            _thread(451, '可取消作品', board: ForumBoard.literature),
        );
        final Completer<ForumThreadPage> completer = Completer<ForumThreadPage>();
        final WorkIndexCancellation cancellation = WorkIndexCancellation();
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        ).thenAnswer((_) => completer.future);

        final Future<WorkIndexResult> future = coordinator.ensure(
            work,
            cancellation: cancellation,
        );
        await untilCalled(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: false,
            ),
        );
        cancellation.cancel();
        completer.complete(_emptyPage(work));

        await expectLater(
            future,
            throwsA(isA<WorkIndexCancelledException>()),
        );
        expect(
            await indexRepository.loadBySourceTid(451, LibraryKind.novel),
            isNull,
        );
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });

    test('主动搜索刷新替换同序号来源且保留未返回旧章节', () async
    {
        final Work oldWork = aggregator.aggregate(<SourceThread>[
            _thread(501, '合并测试 第1话'),
            _thread(502, '合并测试 第2话'),
            _thread(503, '合并测试 第3话'),
        ]).single;
        final Work newWork = aggregator.aggregate(<SourceThread>[
            _thread(511, '合并测试 第1话'),
            _thread(512, '合并测试 第2话'),
        ]).single;
        final String canonicalKey = aggregator.canonicalKeyForWork(oldWork)!;
        await indexRepository.save(canonicalKey: canonicalKey, work: oldWork);
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                forceReload: true,
            ),
        ).thenAnswer((_) async => _emptyPage(newWork));

        final WorkIndexResult result = await coordinator.rebuildFromActiveSearch(
            newWork,
        );

        expect(result.work.chapters, hasLength(3));
        expect(
            result.work.chapters.map((Chapter chapter) => chapter.sourceTid),
            <int>[511, 512, 503],
        );
        verifyNever(
            () => searchRepository.search(
                keyword: any(named: 'keyword'),
                kind: any(named: 'kind'),
            ),
        );
    });
}

SourceThread _thread(
    int tid,
    String title, {
    ForumBoard board = ForumBoard.comic,
    int? typeId,
    String typeName = '',
    String author = '',
})
{
    return SourceThread(
        tid: tid,
        board: board,
        typeId: typeId,
        typeName: typeName,
        title: title,
        author: author,
        uri: _threadUri(tid),
    );
}

SourceThread _longComicThread(int tid, String title)
{
    return _thread(tid, title, typeId: 69, typeName: '#長篇連載');
}

Work _standalone(SourceThread thread)
{
    return const WorkAggregator().aggregate(<SourceThread>[thread]).single;
}

Work _withId(Work work, String id)
{
    return Work(
        id: id,
        kind: work.kind,
        title: work.title,
        summary: work.summary,
        author: work.author,
        typeName: work.typeName,
        sourceThreads: work.sourceThreads,
        chapters: work.chapters,
    );
}

Work _withSummary(Work work, String summary)
{
    return Work(
        id: work.id,
        kind: work.kind,
        title: work.title,
        summary: summary,
        author: work.author,
        typeName: work.typeName,
        sourceThreads: work.sourceThreads,
        chapters: work.chapters,
    );
}

ForumThreadPage _emptyPage(Work work)
{
    final SourceThread thread = work.sourceThreads.last;
    return ForumThreadPage(
        tid: thread.tid,
        board: thread.board,
        title: thread.title,
        uri: thread.uri,
        posts: const <SourcePost>[],
        currentPage: 1,
        totalPages: 1,
    );
}

ForumThreadPage _directoryPage(Work work)
{
    final SourceThread thread = work.sourceThreads.single;
    return ForumThreadPage(
        tid: thread.tid,
        board: thread.board,
        title: thread.title,
        uri: thread.uri,
        posts: <SourcePost>[
            SourcePost(
                pid: 200,
                tid: thread.tid,
                page: 1,
                floor: 1,
                author: '楼主',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: const <PostContentBlock>[PostTextBlock(text: '目录')],
                links: <ThreadLink>[
                    _chapterLink(thread.tid, 201, '第一章'),
                    _chapterLink(thread.tid, 202, '第二章'),
                ],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}

ForumThreadPage _directoryPageForThread(SourceThread thread)
{
    return ForumThreadPage(
        tid: thread.tid,
        board: thread.board,
        title: thread.title,
        typeName: thread.typeName,
        uri: thread.uri,
        posts: <SourcePost>[
            SourcePost(
                pid: thread.tid * 10,
                tid: thread.tid,
                page: 1,
                floor: 1,
                author: thread.author,
                timeLabel: '',
                isOriginalPoster: true,
                blocks: const <PostContentBlock>[PostTextBlock(text: '目录')],
                links: <ThreadLink>[
                    _chapterLink(thread.tid, thread.tid * 10 + 1, '第一章'),
                    _chapterLink(thread.tid, thread.tid * 10 + 2, '第二章'),
                ],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}

ForumThreadPage _rangeRootPage(
    SourceThread thread, {
    required int targetTid,
    required String rangeLabel,
})
{
    return ForumThreadPage(
        tid: thread.tid,
        board: thread.board,
        title: thread.title,
        typeName: thread.typeName,
        uri: thread.uri,
        posts: <SourcePost>[
            SourcePost(
                pid: thread.tid * 10,
                tid: thread.tid,
                page: 1,
                floor: 1,
                author: thread.author,
                timeLabel: '',
                isOriginalPoster: true,
                blocks: const <PostContentBlock>[PostTextBlock(text: '目录')],
                links: <ThreadLink>[
                    _threadChapterLink(rangeLabel, targetTid),
                    _chapterLink(thread.tid, thread.tid * 10 + 6, '第6话'),
                    _chapterLink(thread.tid, thread.tid * 10 + 7, '第7话'),
                ],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}

ForumThreadPage _rangeTargetPage(
    SourceThread thread, {
    required String author,
    int? nestedTargetTid,
})
{
    return ForumThreadPage(
        tid: thread.tid,
        board: thread.board,
        title: thread.title,
        typeName: thread.typeName,
        uri: thread.uri,
        posts: <SourcePost>[
            SourcePost(
                pid: thread.tid * 10,
                tid: thread.tid,
                page: 1,
                floor: 1,
                author: author,
                timeLabel: '',
                isOriginalPoster: true,
                blocks: const <PostContentBlock>[PostTextBlock(text: '目录')],
                links: <ThreadLink>[
                    for (int chapter = 1; chapter <= 5; chapter++)
                        _chapterLink(
                            thread.tid,
                            thread.tid * 10 + chapter,
                            '第$chapter话',
                        ),
                    if (nestedTargetTid != null)
                        _threadChapterLink('第8-9话', nestedTargetTid),
                ],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}

ForumThreadPage _volumeLinkPage(SourceThread thread)
{
    return ForumThreadPage(
        tid: thread.tid,
        board: thread.board,
        title: thread.title,
        typeName: thread.typeName,
        uri: thread.uri,
        posts: <SourcePost>[
            SourcePost(
                pid: 500,
                tid: thread.tid,
                page: 1,
                floor: 1,
                author: thread.author,
                timeLabel: '',
                isOriginalPoster: true,
                blocks: const <PostContentBlock>[PostTextBlock(text: '目录')],
                links: <ThreadLink>[
                    _threadChapterLink('Vol.1', 50),
                    _threadChapterLink('Vol.2', 51),
                ],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}

ForumThreadPage _volumeLinkPageWithExtra(SourceThread thread)
{
    final ForumThreadPage page = _volumeLinkPage(thread);
    final SourcePost post = page.posts.single;
    return ForumThreadPage(
        tid: page.tid,
        board: page.board,
        title: page.title,
        typeName: page.typeName,
        uri: page.uri,
        posts: <SourcePost>[
            SourcePost(
                pid: post.pid,
                tid: post.tid,
                page: post.page,
                floor: post.floor,
                author: post.author,
                timeLabel: post.timeLabel,
                isOriginalPoster: post.isOriginalPoster,
                blocks: post.blocks,
                links: <ThreadLink>[
                    ...post.links,
                    _threadChapterLink('日常短篇', 52),
                ],
            ),
        ],
        currentPage: page.currentPage,
        totalPages: page.totalPages,
    );
}

ForumThreadPage _tagDirectoryPage(Work work, Uri tagUri)
{
    final SourceThread thread = work.sourceThreads.single;
    return ForumThreadPage(
        tid: thread.tid,
        board: thread.board,
        title: thread.title,
        uri: thread.uri,
        posts: <SourcePost>[
            SourcePost(
                pid: 2300,
                tid: thread.tid,
                page: 1,
                floor: 1,
                author: '楼主',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: const <PostContentBlock>[PostTextBlock(text: '本作目录')],
                links: <ThreadLink>[
                    ThreadLink(
                        label: '本作目录',
                        uri: tagUri,
                        kind: ThreadLinkKind.directory,
                    ),
                ],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}

ThreadLink _chapterLink(int tid, int pid, String label)
{
    return ThreadLink(
        label: label,
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=$pid',
        ),
        kind: ThreadLinkKind.chapter,
        tid: tid,
        pid: pid,
    );
}

ThreadLink _threadChapterLink(String label, int tid)
{
    return ThreadLink(
        label: label,
        uri: _threadUri(tid),
        kind: ThreadLinkKind.chapter,
        tid: tid,
    );
}

Uri _threadUri(int tid)
{
    return Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
}
