import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/favorites/data/raw_favorite_repository.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/favorites/presentation/raw_favorites_page.dart';
import 'package:x300/shared/presentation/app_error_view.dart';

class _MockRawFavoriteRepository extends Mock
    implements RawFavoriteRepository {}

void main() {
  testWidgets('全部收藏使用 49px 分类筛选和异构连续列表', (WidgetTester tester) async {
    final _MockRawFavoriteRepository repository = _MockRawFavoriteRepository();
    final List<RawFavoriteItem> openedThreads = <RawFavoriteItem>[];
    final List<RawFavoriteItem> openedBoards = <RawFavoriteItem>[];
    final List<RawFavoriteItem> openedTargets = <RawFavoriteItem>[];
    when(() => repository.loadInitial()).thenAnswer(
      (_) async => _page(
        selectedCategoryKey: RawFavoriteRepository.allCategoryKey,
        items: _items,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rawFavoriteRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RawFavoritesPage(
              onOpenThread: openedThreads.add,
              onOpenBoard: openedBoards.add,
              onOpenTarget: openedTargets.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const Key('raw-favorite-category-filter')))
          .height,
      49,
    );
    expect(find.byKey(const Key('raw-favorites-list')), findsOneWidget);
    expect(find.text('主题收藏'), findsOneWidget);
    expect(find.text('版块收藏'), findsOneWidget);
    expect(find.text('群组收藏'), findsOneWidget);
    expect(find.text('未来收藏'), findsOneWidget);

    await tester.tap(find.text('主题收藏'));
    await tester.tap(find.text('版块收藏'));
    await tester.tap(find.text('群组收藏'));
    expect(openedThreads.single.threadId, 501);
    expect(openedBoards.single.boardId, 30);
    expect(openedTargets.single.boardId, 80);

    final ListTile communityTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('群组收藏'), matching: find.byType(ListTile)),
    );
    final ListTile unknownTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('未来收藏'), matching: find.byType(ListTile)),
    );
    expect(communityTile.onTap, isNotNull);
    expect(unknownTile.onTap, isNull);
  });

  testWidgets('分类选择重新发现服务端分类并刷新列表', (WidgetTester tester) async {
    final _MockRawFavoriteRepository repository = _MockRawFavoriteRepository();
    when(() => repository.loadInitial()).thenAnswer(
      (_) async => _page(
        selectedCategoryKey: RawFavoriteRepository.allCategoryKey,
        items: _items,
      ),
    );
    when(() => repository.loadInitial(categoryKey: 'forum')).thenAnswer(
      (_) async => _page(
        selectedCategoryKey: 'forum',
        items: <RawFavoriteItem>[_items[1]],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rawFavoriteRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: RawFavoritesPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('raw-favorite-category-filter')));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(CheckedPopupMenuItem<String>, '全部'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, '版块'));
    await tester.pumpAndSettle();

    verify(() => repository.loadInitial(categoryKey: 'forum')).called(1);
    expect(find.text('版块收藏'), findsOneWidget);
    expect(find.text('主题收藏'), findsNothing);
  });

  testWidgets('用户空间收藏交给原生目标路由', (WidgetTester tester) async {
    final _MockRawFavoriteRepository repository = _MockRawFavoriteRepository();
    final RawFavoriteItem profile = RawFavoriteItem(
      favoriteId: 75,
      categoryKey: 'space',
      title: '用户收藏',
      targetKind: RawFavoriteTargetKind.userSpace,
      targetUri: Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=space&uid=77&mobile=2',
      ),
      userId: 77,
    );
    RawFavoriteItem? opened;
    when(() => repository.loadInitial()).thenAnswer(
      (_) async => _page(
        selectedCategoryKey: RawFavoriteRepository.allCategoryKey,
        items: <RawFavoriteItem>[profile],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rawFavoriteRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RawFavoritesPage(
              onOpenTarget: (RawFavoriteItem value) => opened = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户收藏'));

    expect(opened?.targetKind, RawFavoriteTargetKind.userSpace);
    expect(opened?.userId, 77);
    expect(find.text('暂不支持'), findsNothing);
  });

  testWidgets('翻页失败保留已有列表并在底部重试', (WidgetTester tester) async {
    final _MockRawFavoriteRepository repository = _MockRawFavoriteRepository();
    final RawFavoritePage first = _page(
      selectedCategoryKey: RawFavoriteRepository.allCategoryKey,
      items: <RawFavoriteItem>[
        ..._items,
        ...List<RawFavoriteItem>.generate(
          24,
          (int index) => RawFavoriteItem(
            favoriteId: 100 + index,
            categoryKey: 'future',
            title: '填充收藏 $index',
            targetKind: RawFavoriteTargetKind.unknown,
          ),
        ),
      ],
      totalPages: 2,
    );
    when(() => repository.loadInitial()).thenAnswer((_) async => first);
    when(() => repository.loadNext(first)).thenThrow(StateError('网络错误'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rawFavoriteRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: RawFavoritesPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('填充收藏 23'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(
      find.byKey(const Key('raw-favorites-list')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('raw-favorites-load-more-retry')),
      findsOneWidget,
    );
    expect(find.byType(AppErrorView), findsNothing);
    await tester.drag(
      find.byKey(const Key('raw-favorites-list')),
      const Offset(0, 4000),
    );
    await tester.pumpAndSettle();
    expect(find.text('主题收藏'), findsOneWidget);
  });
}

RawFavoritePage _page({
  required String selectedCategoryKey,
  required List<RawFavoriteItem> items,
  int totalPages = 1,
}) {
  return RawFavoritePage(
    categories: <RawFavoriteCategory>[
      RawFavoriteCategory(key: 'thread', label: '主题', uri: _uri('thread')),
      RawFavoriteCategory(key: 'forum', label: '版块', uri: _uri('forum')),
      RawFavoriteCategory(key: 'group', label: '群组', uri: _uri('group')),
      RawFavoriteCategory(key: 'all', label: '全部', uri: _uri('all')),
    ],
    items: items,
    selectedCategoryKey: selectedCategoryKey,
    currentPage: 1,
    totalPages: totalPages,
    sourceUri: _uri('all'),
    nextPageUri: totalPages > 1
        ? _uri('all').replace(
            queryParameters: <String, String>{
              ..._uri('all').queryParameters,
              'page': '2',
            },
          )
        : null,
  );
}

Uri _uri(String type) {
  return Uri.parse(
    'https://bbs.yamibo.com/home.php?'
    'mod=space&do=favorite&type=$type&mobile=2',
  );
}

final List<RawFavoriteItem> _items = <RawFavoriteItem>[
  RawFavoriteItem(
    favoriteId: 71,
    categoryKey: 'thread',
    title: '主题收藏',
    targetKind: RawFavoriteTargetKind.thread,
    targetUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?'
      'mod=viewthread&tid=501&mobile=2',
    ),
    threadId: 501,
  ),
  RawFavoriteItem(
    favoriteId: 72,
    categoryKey: 'forum',
    title: '版块收藏',
    targetKind: RawFavoriteTargetKind.board,
    targetUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?'
      'mod=forumdisplay&fid=30&mobile=2',
    ),
    boardId: 30,
  ),
  RawFavoriteItem(
    favoriteId: 73,
    categoryKey: 'group',
    title: '群组收藏',
    targetKind: RawFavoriteTargetKind.groupBoard,
    targetUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=group&fid=80&mobile=2',
    ),
    boardId: 80,
  ),
  const RawFavoriteItem(
    favoriteId: 74,
    categoryKey: 'future',
    title: '未来收藏',
    targetKind: RawFavoriteTargetKind.unknown,
  ),
];
