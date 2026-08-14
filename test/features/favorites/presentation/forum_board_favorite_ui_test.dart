import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/favorites/data/forum_board_favorite_repository.dart';
import 'package:x300/features/favorites/data/raw_favorite_repository.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/favorites/presentation/raw_favorites_page.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart' as domain;
import 'package:x300/features/forum/presentation/forum_board_page.dart';

class _MockForumReadRepository extends Mock implements ForumReadRepository {}

class _MockBoardFavoriteRepository extends Mock
    implements ForumBoardFavoriteRepository {}

class _MockRawFavoriteRepository extends Mock
    implements RawFavoriteRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(_boardItem);
    registerFallbackValue(Uri.parse('https://bbs.yamibo.com/?mobile=2'));
  });

  testWidgets('版块页确认后才收藏且同步双击只发起一次', (tester) async {
    final _MockForumReadRepository read = _MockForumReadRepository();
    final _MockBoardFavoriteRepository favorite =
        _MockBoardFavoriteRepository();
    when(
      () => read.loadBoard(any(), expectedBoardId: any(named: 'expectedBoardId')),
    ).thenAnswer((_) async => _boardPage());
    when(
      () => favorite.add(
        boardId: 41,
        entryUri: _addUri,
        refererUri: _boardUri,
      ),
    ).thenAnswer((_) async => true);

    await tester.pumpWidget(_boardApp(read, favorite, _boardPage()));
    await tester.pumpAndSettle();
    final IconButton button = tester.widget<IconButton>(
      find.byKey(const Key('forum-favorite-board')),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pump();

    expect(find.text('论坛的版块收藏入口会在请求时立即写入。确认收藏“测试版块”？'), findsOneWidget);
    verifyNever(
      () => favorite.add(
        boardId: any(named: 'boardId'),
        entryUri: any(named: 'entryUri'),
        refererUri: any(named: 'refererUri'),
      ),
    );
    await tester.tap(find.text('确认收藏'));
    await tester.pumpAndSettle();

    verify(
      () => favorite.add(
        boardId: 41,
        entryUri: _addUri,
        refererUri: _boardUri,
      ),
    ).called(1);
  });

  testWidgets('缓存版块页即使残留操作 URI 也不暴露收藏按钮', (tester) async {
    final _MockForumReadRepository read = _MockForumReadRepository();
    final _MockBoardFavoriteRepository favorite =
        _MockBoardFavoriteRepository();
    final domain.ForumBoardPage cached = _boardPage(isFromCache: true);
    when(
      () => read.loadBoard(any(), expectedBoardId: any(named: 'expectedBoardId')),
    ).thenAnswer((_) async => cached);

    await tester.pumpWidget(_boardApp(read, favorite, cached));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-favorite-board')), findsNothing);
    verifyNever(
      () => favorite.add(
        boardId: any(named: 'boardId'),
        entryUri: any(named: 'entryUri'),
        refererUri: any(named: 'refererUri'),
      ),
    );
  });

  testWidgets('blocked 流程只回读，失败后人工解除不重发收藏', (tester) async {
    final _MockForumReadRepository read = _MockForumReadRepository();
    final _MockBoardFavoriteRepository favorite =
        _MockBoardFavoriteRepository();
    final ForumBoardFavoriteBlockedException blocked = _blockedAdd();
    when(
      () => read.loadBoard(any(), expectedBoardId: any(named: 'expectedBoardId')),
    ).thenAnswer((_) async => _boardPage());
    when(
      () => favorite.add(
        boardId: 41,
        entryUri: _addUri,
        refererUri: _boardUri,
      ),
    ).thenThrow(blocked);
    when(() => favorite.readback(blocked)).thenAnswer((_) async => false);
    when(() => favorite.acknowledge(blocked)).thenAnswer((_) async {});

    await tester.pumpWidget(_boardApp(read, favorite, _boardPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-favorite-board')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认收藏'));
    await tester.pumpAndSettle();
    expect(find.text('收藏结果尚未确认'), findsOneWidget);

    await tester.tap(find.text('重新回读'));
    await tester.pumpAndSettle();
    expect(find.text('仍无法确认'), findsOneWidget);
    await tester.tap(find.text('已人工核对，解除'));
    await tester.pumpAndSettle();

    verify(() => favorite.readback(blocked)).called(1);
    verify(() => favorite.acknowledge(blocked)).called(1);
    verify(
      () => favorite.add(
        boardId: 41,
        entryUri: _addUri,
        refererUri: _boardUri,
      ),
    ).called(1);
  });

  testWidgets('全部收藏取消版块需确认、同步双击单次，缓存时禁用', (tester) async {
    final _MockRawFavoriteRepository raw = _MockRawFavoriteRepository();
    final _MockBoardFavoriteRepository favorite =
        _MockBoardFavoriteRepository();
    when(() => raw.loadInitial()).thenAnswer((_) async => _rawPage());
    when(() => favorite.remove(_boardItem)).thenAnswer((_) async => true);

    await tester.pumpWidget(_rawApp(raw, favorite));
    await tester.pumpAndSettle();
    final IconButton button = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('raw-remove-board-favorite-71')),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    verifyNever(() => favorite.remove(any()));
    await tester.tap(find.text('确认取消'));
    await tester.pumpAndSettle();
    verify(() => favorite.remove(_boardItem)).called(1);
  });

  testWidgets('取消版块 blocked 只回读并人工解除，不重复 remove', (tester) async {
    final _MockRawFavoriteRepository raw = _MockRawFavoriteRepository();
    final _MockBoardFavoriteRepository favorite =
        _MockBoardFavoriteRepository();
    final ForumBoardFavoriteBlockedException blocked = _blockedRemove();
    when(() => raw.loadInitial()).thenAnswer((_) async => _rawPage());
    when(() => favorite.remove(_boardItem)).thenThrow(blocked);
    when(() => favorite.readback(blocked)).thenAnswer((_) async => false);
    when(() => favorite.acknowledge(blocked)).thenAnswer((_) async {});

    await tester.pumpWidget(_rawApp(raw, favorite));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('raw-remove-board-favorite-71')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('确认取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('取消结果尚未确认'), findsOneWidget);

    await tester.tap(find.text('重新回读'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('已人工核对，解除'));
    await tester.pumpAndSettle();

    verify(() => favorite.readback(blocked)).called(1);
    verify(() => favorite.acknowledge(blocked)).called(1);
    verify(() => favorite.remove(_boardItem)).called(1);
  });

  testWidgets('全部收藏缓存页不提供版块取消能力', (tester) async {
    final _MockRawFavoriteRepository raw = _MockRawFavoriteRepository();
    final _MockBoardFavoriteRepository favorite =
        _MockBoardFavoriteRepository();
    when(() => raw.loadInitial()).thenAnswer(
      (_) async => _rawPage(isFromCache: true),
    );
    await tester.pumpWidget(_rawApp(raw, favorite));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('raw-remove-board-favorite-71')),
      findsNothing,
    );
    verifyNever(() => favorite.remove(any()));
  });
}

Widget _boardApp(
  ForumReadRepository read,
  ForumBoardFavoriteRepository favorite,
  domain.ForumBoardPage page,
) {
  return ProviderScope(
    overrides: [
      forumReadRepositoryProvider.overrideWithValue(read),
      forumBoardFavoriteRepositoryProvider.overrideWithValue(favorite),
    ],
    child: MaterialApp(home: ForumBoardPage(board: page.board)),
  );
}

Widget _rawApp(
  RawFavoriteRepository raw,
  ForumBoardFavoriteRepository favorite,
) {
  return ProviderScope(
    overrides: [
      rawFavoriteRepositoryProvider.overrideWithValue(raw),
      forumBoardFavoriteRepositoryProvider.overrideWithValue(favorite),
    ],
    child: const MaterialApp(home: Scaffold(body: RawFavoritesPage())),
  );
}

domain.ForumBoardPage _boardPage({bool isFromCache = false}) {
  return domain.ForumBoardPage(
    board: domain.ForumBoardNode(
      id: 41,
      name: '测试版块',
      uri: _boardUri,
    ),
    threads: const <domain.ForumThreadSummary>[],
    filters: const <domain.ForumRouteOption>[],
    cursor: domain.ForumPageCursor(
      currentPage: 1,
      totalPages: 1,
      sourceUri: _boardUri,
    ),
    favoriteUri: _addUri,
    isFromCache: isFromCache,
  );
}

RawFavoritePage _rawPage({bool isFromCache = false}) {
  return RawFavoritePage(
    categories: <RawFavoriteCategory>[
      RawFavoriteCategory(
        key: 'forum',
        label: '版块',
        uri: ForumBoardFavoriteRepository.listUri,
      ),
    ],
    items: <RawFavoriteItem>[_boardItem],
    selectedCategoryKey: 'forum',
    currentPage: 1,
    totalPages: 1,
    sourceUri: ForumBoardFavoriteRepository.listUri,
    isFromCache: isFromCache,
  );
}

ForumBoardFavoriteBlockedException _blockedAdd() {
  return ForumBoardFavoriteBlockedException(
    record: SubmissionTombstoneRecord(
      attemptId: 'attempt-1',
      userId: 42,
      key: const SubmissionTombstoneKey(
        action: 'favoriteBoard',
        boardId: 41,
        draftContext: '',
      ),
      status: ForumSubmissionTombstoneStatus.attempted,
      recordedAt: DateTime.utc(2026, 8, 13),
    ),
    boardId: 41,
    shouldBeFavorite: true,
  );
}

ForumBoardFavoriteBlockedException _blockedRemove() {
  return ForumBoardFavoriteBlockedException(
    record: SubmissionTombstoneRecord(
      attemptId: 'attempt-remove-1',
      userId: 42,
      key: const SubmissionTombstoneKey(
        action: 'removeFavorite',
        boardId: 30,
        favoriteId: 71,
        draftContext: '',
      ),
      status: ForumSubmissionTombstoneStatus.attempted,
      recordedAt: DateTime.utc(2026, 8, 13),
    ),
    boardId: 30,
    favoriteId: 71,
    shouldBeFavorite: false,
  );
}

final Uri _boardUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=41&mobile=2',
);
final Uri _addUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&type=forum&id=41&handlekey=opaque-board-control&mobile=2',
);
final RawFavoriteItem _boardItem = RawFavoriteItem(
  favoriteId: 71,
  categoryKey: 'forum',
  title: '版块收藏',
  targetKind: RawFavoriteTargetKind.board,
  targetUri: Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&mobile=2',
  ),
  deleteDialogUri: Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&op=delete&favid=71&mobile=2',
  ),
  boardId: 30,
);
