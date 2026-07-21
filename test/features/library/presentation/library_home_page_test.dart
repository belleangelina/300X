import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/library_home_page.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';

class _MockForumLibraryRepository extends Mock
    implements ForumLibraryRepository
{
}

class _MockCoverRepository extends Mock implements CoverRepository
{
}

void main()
{
    late AppSettingsRepository settingsRepository;

    setUpAll(()
    {
        registerFallbackValue(CatalogSection.updated);
        registerFallbackValue(NovelSourceFilter.all);
        registerFallbackValue(_work());
        registerFallbackValue(<SourceThread>[]);
        registerFallbackValue(
            _page(
                ForumBoard.comic,
                typeId: 69,
                category: '#長篇連載',
            ),
        );
    });

    setUp(() async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        settingsRepository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
    });

    testWidgets('漫画主页使用单一分区并组合分类与排序请求', (
        WidgetTester tester,
    ) async
    {
        final _MockForumLibraryRepository repository =
            _MockForumLibraryRepository();
        final _MockCoverRepository coverRepository = _MockCoverRepository();
        final LibraryHomeController controller = LibraryHomeController();
        when(() => coverRepository.resolve(any())).thenAnswer((_) async => null);
        when(
            () => repository.loadCatalog(
                kind: LibraryKind.comic,
                section: any(named: 'section'),
                novelSource: any(named: 'novelSource'),
                page: any(named: 'page'),
                typeId: any(named: 'typeId'),
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final int page = invocation.namedArguments[#page] as int;
            return _page(
                ForumBoard.comic,
                typeId: 69,
                category: '#長篇連載',
                work: _work(),
                currentPage: page,
                totalPages: 5,
            );
        });

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    forumLibraryRepositoryProvider.overrideWithValue(repository),
                    coverRepositoryProvider.overrideWithValue(coverRepository),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: LibraryHomePage(
                        kind: LibraryKind.comic,
                        controller: controller,
                        onOpenWork: (Work work) {},
                    ),
                ),
            ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('漫画区'), findsOneWidget);
        expect(find.text('推荐'), findsNothing);
        expect(find.text('更新'), findsNothing);
        expect(find.text('分类'), findsNothing);
        expect(find.text('排行'), findsNothing);
        verify(
            () => repository.loadCatalog(
                kind: LibraryKind.comic,
                section: CatalogSection.updated,
                novelSource: NovelSourceFilter.all,
                page: 1,
                typeId: null,
            ),
        ).called(1);

        expect(find.byType(WorkListTile), findsOneWidget);
        expect(find.byType(WorkGridCard), findsNothing);
        expect(find.text('列表'), findsOneWidget);
        final Rect cover = tester.getRect(find.byType(WorkCover));
        final Rect metadata = tester.getRect(find.textContaining('0 浏览'));
        expect(metadata.bottom, moreOrLessEquals(cover.bottom));
        final Rect viewButton = tester.getRect(
            find.byKey(const ValueKey<String>('catalog-view-toggle')),
        );
        final Rect searchButton = tester.getRect(
            find.byKey(const ValueKey<String>('catalog-search')),
        );
        final Rect pageButton = tester.getRect(
            find.byKey(const ValueKey<String>('catalog-page-jump')),
        );
        final Rect categoryButton = tester.getRect(
            find.byKey(const ValueKey<String>('catalog-category-filter')),
        );
        final Rect sortButton = tester.getRect(
            find.byKey(const ValueKey<String>('catalog-sort-filter')),
        );
        expect(viewButton.width, moreOrLessEquals(pageButton.width));
        expect(pageButton.width, moreOrLessEquals(categoryButton.width));
        expect(categoryButton.width, moreOrLessEquals(sortButton.width));
        expect(viewButton.center.dy, moreOrLessEquals(pageButton.center.dy));
        expect(pageButton.center.dy, moreOrLessEquals(categoryButton.center.dy));
        expect(categoryButton.center.dy, moreOrLessEquals(sortButton.center.dy));
        expect(searchButton.bottom, lessThanOrEqualTo(viewButton.top));
        expect(categoryButton.left, lessThan(pageButton.left));
        expect(pageButton.left, lessThan(viewButton.left));
        expect(viewButton.left, lessThan(sortButton.left));

        await tester.tap(
            find.byKey(const ValueKey<String>('catalog-view-toggle')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WorkListTile), findsNothing);
        expect(find.byType(WorkGridCard), findsOneWidget);
        expect(find.text('网格'), findsOneWidget);

        await tester.tap(
            find.byKey(const ValueKey<String>('catalog-page-jump')),
        );
        await tester.pumpAndSettle();
        expect(find.text('跳转页面'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField), '3');
        await tester.pump();
        await tester.tap(find.text('跳转'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('3页'), findsOneWidget);
        verify(
            () => repository.loadCatalog(
                kind: LibraryKind.comic,
                section: CatalogSection.updated,
                novelSource: NovelSourceFilter.all,
                page: 3,
                typeId: null,
            ),
        ).called(1);

        await controller.scrollToTopAndRefresh();
        await tester.pump();
        verify(
            () => repository.loadCatalog(
                kind: LibraryKind.comic,
                section: CatalogSection.updated,
                novelSource: NovelSourceFilter.all,
                page: 3,
                typeId: null,
            ),
        ).called(1);

        final Future<void> refresh = tester.state<RefreshIndicatorState>(
            find.byType(RefreshIndicator),
        ).show();
        await tester.pump();
        await tester.pumpAndSettle();
        await refresh;
        verify(
            () => repository.loadCatalog(
                kind: LibraryKind.comic,
                section: CatalogSection.updated,
                novelSource: NovelSourceFilter.all,
                page: 1,
                typeId: null,
            ),
        ).called(1);

        await tester.tap(
            find.byKey(const ValueKey<String>('catalog-category-filter')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(CheckedPopupMenuItem<int>), findsNWidgets(2));
        await tester.tap(
            find.widgetWithText(
                CheckedPopupMenuItem<int>,
                '#長篇連載',
            ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(
            find.byKey(const ValueKey<String>('catalog-sort-filter')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('热度'), findsOneWidget);
        expect(find.byType(CheckedPopupMenuItem<CatalogSection>), findsNothing);

        verify(
            () => repository.loadCatalog(
                kind: LibraryKind.comic,
                section: CatalogSection.ranking,
                novelSource: NovelSourceFilter.all,
                page: 1,
                typeId: 69,
            ),
        ).called(1);

        await controller.scrollToTopAndRefresh();
        await tester.pump();
        verify(
            () => repository.loadCatalog(
                kind: LibraryKind.comic,
                section: CatalogSection.ranking,
                novelSource: NovelSourceFilter.all,
                page: 1,
                typeId: 69,
            ),
        ).called(1);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
    });

    testWidgets('主页记住视图模式且短网格自动补页', (
        WidgetTester tester,
    ) async
    {
        final _MockForumLibraryRepository repository =
                _MockForumLibraryRepository();
        final _MockCoverRepository coverRepository = _MockCoverRepository();
        when(() => coverRepository.resolve(any())).thenAnswer((_) async => null);
        when(
            () => repository.loadCatalog(
                kind: LibraryKind.comic,
                section: any(named: 'section'),
                novelSource: any(named: 'novelSource'),
                page: any(named: 'page'),
                typeId: any(named: 'typeId'),
            ),
        ).thenAnswer((_) async => _page(
            ForumBoard.comic,
            typeId: 69,
            category: '#長篇連載',
            work: _work(301),
            currentPage: 40,
            totalPages: 100,
            hasMore: true,
        ));
        when(
            () => repository.loadNextCatalog(
                cursor: any(named: 'cursor'),
                section: any(named: 'section'),
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final WorkCatalogPage cursor = invocation.namedArguments[
                #cursor
            ] as WorkCatalogPage;
            final int current = cursor.pages.values.first.currentPage;
            return _page(
                ForumBoard.comic,
                typeId: 69,
                category: '#長篇連載',
                work: _work(current + 262),
                currentPage: current + 1,
                totalPages: 100,
                hasMore: current < 41,
            );
        });
        when(
            () => repository.aggregateThreads(any()),
        ).thenReturn(<Work>[_work(301), _work(302), _work(303)]);

        Widget page() => ProviderScope(
            overrides: [
                forumLibraryRepositoryProvider.overrideWithValue(repository),
                coverRepositoryProvider.overrideWithValue(coverRepository),
                appSettingsRepositoryProvider.overrideWithValue(
                    settingsRepository,
                ),
            ],
            child: MaterialApp(
                home: LibraryHomePage(
                    kind: LibraryKind.comic,
                    onOpenWork: (Work work) {},
                ),
            ),
        );

        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        await tester.tap(
            find.byKey(const ValueKey<String>('catalog-view-toggle')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(WorkGridCard), findsNWidgets(3));
        expect(find.text('40+2页'), findsOneWidget);
        verify(
            () => repository.loadNextCatalog(
                cursor: any(named: 'cursor'),
                section: CatalogSection.updated,
            ),
        ).called(2);

        await tester.tap(
            find.byKey(const ValueKey<String>('catalog-page-jump')),
        );
        await tester.pumpAndSettle();
        expect(find.text('页码（1–100）'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();

        expect(find.byType(WorkGridCard), findsWidgets);
        expect(find.text('网格'), findsOneWidget);
    });

    testWidgets('小说以轻小说区为首并分别保留分类和排序状态', (
        WidgetTester tester,
    ) async
    {
        final _MockForumLibraryRepository repository =
            _MockForumLibraryRepository();
        when(
            () => repository.loadCatalog(
                kind: LibraryKind.novel,
                section: any(named: 'section'),
                novelSource: any(named: 'novelSource'),
                page: any(named: 'page'),
                typeId: any(named: 'typeId'),
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final NovelSourceFilter source = invocation.namedArguments[
                #novelSource
            ] as NovelSourceFilter;
            return source == NovelSourceFilter.literature
                    ? _page(
                        ForumBoard.literature,
                        typeId: 101,
                        category: '原创',
                    )
                    : _page(
                        ForumBoard.lightNovel,
                        typeId: 201,
                        category: '连载',
                    );
        });

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    forumLibraryRepositoryProvider.overrideWithValue(repository),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: LibraryHomePage(
                        kind: LibraryKind.novel,
                        onOpenWork: (Work work) {},
                    ),
                ),
            ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('文学区'), findsOneWidget);
        expect(find.text('轻小说'), findsOneWidget);
        final List<String?> tabTitles = tester
                .widgetList<Tab>(find.byType(Tab))
                .map((Tab value) => value.text)
                .toList(growable: false);
        expect(tabTitles, <String?>['轻小说', '文学区']);

        await tester.tap(
            find
                    .byKey(
                        const ValueKey<String>('catalog-category-filter'),
                    )
                    .hitTestable(),
        );
        await tester.pumpAndSettle();
        await tester.tap(
            find.widgetWithText(CheckedPopupMenuItem<int>, '连载'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(
            find
                    .byKey(const ValueKey<String>('catalog-sort-filter'))
                    .hitTestable(),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.text('文学区'));
        await tester.pumpAndSettle();
        Finder category = find.descendant(
            of: find
                .byKey(const ValueKey<String>('catalog-category-filter'))
                .hitTestable(),
            matching: find.text('全部'),
        );
        Finder sort = find.descendant(
            of: find
                .byKey(const ValueKey<String>('catalog-sort-filter'))
                .hitTestable(),
            matching: find.text('最新'),
        );
        expect(category, findsOneWidget);
        expect(sort, findsOneWidget);

        await tester.tap(find.text('轻小说'));
        await tester.pumpAndSettle();
        category = find.descendant(
            of: find
                .byKey(const ValueKey<String>('catalog-category-filter'))
                .hitTestable(),
            matching: find.text('连载'),
        );
        sort = find.descendant(
            of: find
                .byKey(const ValueKey<String>('catalog-sort-filter'))
                .hitTestable(),
            matching: find.text('热度'),
        );
        expect(category, findsOneWidget);
        expect(sort, findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
    });
}

WorkCatalogPage _page(
    ForumBoard board, {
    required int typeId,
    required String category,
    Work? work,
    int currentPage = 1,
    int totalPages = 1,
    bool hasMore = false,
})
{
    return WorkCatalogPage(
        works: <Work>[?work],
        sourceThreads: <SourceThread>[?work?.primarySourceThread],
        categories: <ForumCategory>[
            ForumCategory(
                board: board,
                typeId: typeId,
                name: category,
                uri: Uri.parse(
                    'https://bbs.yamibo.com/forum.php?mod=forumdisplay'
                    '&fid=${board.fid}&typeid=$typeId',
                ),
            ),
        ],
        pages: <ForumBoard, ForumCatalogPage>{
            board: ForumCatalogPage(
                board: board,
                threads: <SourceThread>[?work?.primarySourceThread],
                pinnedThreads: const <SourceThread>[],
                categories: const <ForumCategory>[],
                currentPage: currentPage,
                totalPages: totalPages,
                nextPageUri: hasMore
                    ? Uri.parse(
                        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&'
                        'fid=${board.fid}&page=${currentPage + 1}',
                    )
                    : null,
            ),
        },
    );
}

Work _work([int tid = 301])
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
    final SourceThread source = SourceThread(
        tid: tid,
        board: ForumBoard.comic,
        title: '测试漫画 第1话',
        uri: uri,
        typeName: '#長篇連載',
    );
    return Work(
        id: 'comic:$tid',
        kind: LibraryKind.comic,
        title: '测试漫画',
        sourceThreads: <SourceThread>[source],
        chapters: <Chapter>[
            Chapter(
                id: 'comic:$tid:1',
                title: '第1话',
                sourceUri: uri,
                sourceTid: tid,
            ),
        ],
        typeName: '#長篇連載',
    );
}
