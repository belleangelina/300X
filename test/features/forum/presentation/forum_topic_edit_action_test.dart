import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_action_repository.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart' as domain;
import 'package:x300/features/forum/presentation/forum_action_page.dart';
import 'package:x300/features/forum/presentation/forum_topic_page.dart';

class _MockForumReadRepository extends Mock implements ForumReadRepository {}

class _MockForumActionRepository extends Mock
    implements ForumActionRepository {}

void main() {
  late _MockForumReadRepository reads;
  late _MockForumActionRepository actions;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://bbs.yamibo.com/?mobile=2'));
    registerFallbackValue(_fallbackRequest);
  });

  setUp(() {
    reads = _MockForumReadRepository();
    actions = _MockForumActionRepository();
    when(
      () => actions.prepare(any()),
    ).thenThrow(const ForumParseException('测试仅检查原生编辑请求'));
  });

  testWidgets('当前移动响应的精确编辑能力打开原生表单并按 pid 回读', (
    WidgetTester tester,
  ) async {
    final Uri editUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=41'
      '&tid=100&pid=202&page=2&mobile=2',
    );
    final domain.ForumThreadPage page = _topicPage(editUri: editUri);
    _stubPage(reads, page);

    await tester.pumpWidget(_app(reads, actions));
    await tester.pumpAndSettle();

    final Finder editButton = find.byKey(
      const ValueKey<String>('forum-edit-post-202'),
    );
    expect(editButton, findsOneWidget);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    final ForumActionPage actionPage = tester.widget<ForumActionPage>(
      find.byType(ForumActionPage),
    );
    expect(actionPage.request.kind, ForumActionKind.editPost);
    expect(actionPage.request.target.boardId, 41);
    expect(actionPage.request.target.threadId, 100);
    expect(actionPage.request.target.postId, 202);
    expect(actionPage.request.entryUri, editUri);
    expect(
      actionPage.request.readbackUri,
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost'
        '&ptid=100&pid=202&mobile=2',
      ),
    );
    expect(actionPage.draftId, 'edit-post:202');

    Navigator.of(
      tester.element(find.byType(ForumActionPage)),
    ).pop(const ForumActionPageResult(readbackCompleted: false));
    await tester.pumpAndSettle();

    verify(
      () => reads.loadThread(
        _threadUri,
        expectedThreadId: 100,
        expectedBoardId: 41,
        focusedPostId: 202,
      ),
    ).called(1);
  });

  testWidgets('目标不完整或缓存页不展示原生编辑能力', (
    WidgetTester tester,
  ) async {
    final domain.ForumThreadPage invalid = _topicPage(
      editUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=41'
        '&tid=100&pid=202&mobile=2',
      ),
    );
    _stubPage(reads, invalid);
    await tester.pumpWidget(_app(reads, actions));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsNothing);

    reset(reads);
    final domain.ForumThreadPage cached = _topicPage(
      editUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=41'
        '&tid=100&pid=202&page=2&mobile=2',
      ),
      isFromCache: true,
    );
    _stubPage(reads, cached);
    await tester.pumpWidget(
      KeyedSubtree(key: const ValueKey<String>('cached'), child: _app(reads, actions)),
    );
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsNothing);
  });
}

void _stubPage(
  _MockForumReadRepository repository,
  domain.ForumThreadPage page,
) {
  when(
    () => repository.loadThread(
      any(),
      expectedThreadId: any(named: 'expectedThreadId'),
      expectedBoardId: any(named: 'expectedBoardId'),
      focusedPostId: any(named: 'focusedPostId'),
    ),
  ).thenAnswer((_) async => page);
}

Widget _app(ForumReadRepository reads, ForumActionRepository actions) {
  return ProviderScope(
    overrides: [
      forumReadRepositoryProvider.overrideWithValue(reads),
      forumActionRepositoryProvider.overrideWithValue(actions),
    ],
    child: MaterialApp(home: ForumTopicPage(thread: _thread)),
  );
}

domain.ForumThreadPage _topicPage({
  required Uri editUri,
  bool isFromCache = false,
}) {
  return domain.ForumThreadPage(
    thread: domain.ForumThread(
      id: 100,
      boardId: 41,
      title: '测试主题',
      uri: _threadUri,
      author: '楼主',
    ),
    posts: <domain.ForumPost>[
      domain.ForumPost(
        id: 202,
        threadId: 100,
        floor: 2,
        author: '回复者',
        timeLabel: '2026-08-13',
        messageHtml: '<p>正文</p>',
        uri: _threadUri.replace(fragment: 'pid202'),
        editUri: editUri,
      ),
    ],
    readingOptions: const <domain.ForumRouteOption>[],
    cursor: domain.ForumPageCursor(
      currentPage: 2,
      totalPages: 2,
      sourceUri: _threadUri,
    ),
    isFromCache: isFromCache,
    cacheUpdatedAt: isFromCache ? DateTime(2026, 8, 13) : null,
  );
}

final Uri _threadUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&mobile=2',
);

final domain.ForumThreadSummary _thread = domain.ForumThreadSummary(
  id: 100,
  boardId: 41,
  title: '测试主题',
  uri: _threadUri,
);

final ForumActionRequest _fallbackRequest = ForumActionRequest(
  kind: ForumActionKind.editPost,
  target: const ForumActionTarget(boardId: 41, threadId: 100, postId: 202),
  entryUri: Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=41'
    '&tid=100&pid=202&page=2&mobile=2',
  ),
  readbackUri: Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost'
    '&ptid=100&pid=202&mobile=2',
  ),
);
