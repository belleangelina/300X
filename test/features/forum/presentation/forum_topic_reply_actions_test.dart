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
    ).thenThrow(const ForumParseException('测试仅检查原生操作请求'));
  });

  testWidgets('主题回复校验入口 reppost 但保持线程级 target 并在返回后刷新', (
    WidgetTester tester,
  ) async {
    final Uri replyUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=41'
      '&tid=100&reppost=777&page=2&mobile=2',
    );
    final domain.ForumThreadPage page = _topicPage(replyUri: replyUri);
    _stubPage(reads, page);

    await tester.pumpWidget(_app(reads, actions));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-reply-thread')), findsOneWidget);
    await tester.tap(find.byKey(const Key('forum-reply-thread')));
    await tester.pumpAndSettle();

    final ForumActionPage actionPage = tester.widget<ForumActionPage>(
      find.byType(ForumActionPage),
    );
    expect(actionPage.request.kind, ForumActionKind.reply);
    expect(actionPage.request.target.boardId, 41);
    expect(actionPage.request.target.threadId, 100);
    expect(actionPage.request.target.postId, isNull);
    expect(actionPage.request.entryUri, replyUri);
    expect(
      actionPage.request.readbackUri,
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&mobile=2',
      ),
    );
    expect(actionPage.draftId, 'reply:100');

    Navigator.of(
      tester.element(find.byType(ForumActionPage)),
    ).pop(const ForumActionPageResult(readbackCompleted: false));
    await tester.pumpAndSettle();

    verify(
      () => reads.loadThread(
        _threadUri,
        expectedThreadId: 100,
        expectedBoardId: 41,
        focusedPostId: null,
      ),
    ).called(2);
  });

  testWidgets('楼层引用不受原页平台门禁限制并使用 repquote 目标', (WidgetTester tester) async {
    final Uri quoteUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=41'
      '&tid=100&repquote=202&page=2&extra=page%3D2&mobile=2',
    );
    final domain.ForumThreadPage page = _topicPage(quoteUri: quoteUri);
    _stubPage(reads, page);

    await tester.pumpWidget(_app(reads, actions));
    await tester.pumpAndSettle();

    expect(find.text('引用'), findsOneWidget);
    await tester.tap(find.text('引用'));
    await tester.pumpAndSettle();

    final ForumActionPage actionPage = tester.widget<ForumActionPage>(
      find.byType(ForumActionPage),
    );
    expect(actionPage.request.kind, ForumActionKind.quoteReply);
    expect(actionPage.request.target.threadId, 100);
    expect(actionPage.request.target.postId, 202);
    expect(actionPage.request.entryUri, quoteUri);
    expect(
      actionPage.request.readbackUri,
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&mobile=2',
      ),
    );
    expect(actionPage.draftId, 'quote-reply:202');
  });

  testWidgets('目标参数无效的当前响应不展示回复能力', (WidgetTester tester) async {
    final domain.ForumThreadPage invalidPage = _topicPage(
      replyUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=post&action=reply'
        '&fid=41&tid=100&mobile=2',
      ),
      quoteUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=post&action=reply'
        '&fid=41&tid=100&repquote=999&page=2&extra=page%3D2&mobile=2',
      ),
    );
    _stubPage(reads, invalidPage);

    await tester.pumpWidget(_app(reads, actions));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-reply-thread')), findsNothing);
    expect(find.text('引用'), findsNothing);
  });

  testWidgets('缓存页即使带合法入口也不展示回复能力', (WidgetTester tester) async {
    final domain.ForumThreadPage cachedPage = _topicPage(
      replyUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=post&action=reply'
        '&fid=41&tid=100&reppost=201&page=2&mobile=2',
      ),
      quoteUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=post&action=reply'
        '&fid=41&tid=100&repquote=202&page=2&extra=page%3D2&mobile=2',
      ),
      isFromCache: true,
    );
    _stubPage(reads, cachedPage);

    await tester.pumpWidget(_app(reads, actions));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-reply-thread')), findsNothing);
    expect(find.text('引用'), findsNothing);
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
  Uri? replyUri,
  Uri? quoteUri,
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
        quoteUri: quoteUri,
      ),
    ],
    readingOptions: const <domain.ForumRouteOption>[],
    cursor: domain.ForumPageCursor(
      currentPage: 2,
      totalPages: 2,
      sourceUri: _threadUri,
    ),
    replyUri: replyUri,
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
  kind: ForumActionKind.reply,
  target: const ForumActionTarget(boardId: 41, threadId: 100, postId: 201),
  entryUri: Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=post&action=reply'
    '&fid=41&tid=100&reppost=201&page=2&mobile=2',
  ),
  readbackUri: _threadUri,
);
