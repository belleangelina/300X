import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/community/data/community_pm_action_repository.dart';
import 'package:x300/features/community/data/community_pm_draft_repository.dart';
import 'package:x300/features/community/data/community_repository.dart';
import 'package:x300/features/community/domain/community_pm_action_models.dart';
import 'package:x300/features/community/domain/community_models.dart';
import 'package:x300/features/community/presentation/community_pages.dart';
import 'package:x300/features/community/presentation/community_pm_send_page.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

class _MockForumClient extends Mock implements ForumClient {}

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockCommunityRepository extends Mock implements CommunityRepository {}

class _MockTombstones extends Mock
    implements ForumSubmissionTombstoneRepository {}

class _FakePmActionRepository extends CommunityPmActionRepository {
  _FakePmActionRepository() : super(_MockForumClient(), 42, _MockTombstones());

  final Completer<CommunityPmSubmissionResult> submission =
      Completer<CommunityPmSubmissionResult>();
  int prepareCalls = 0;
  int submitCalls = 0;
  String submittedMessage = '';
  String submittedUsername = '';
  CommunityPmSubmissionBlockedException? prepareBlocked;
  int acknowledgeCalls = 0;

  @override
  Future<CommunityPmPreparedSend> prepare(
    CommunityPmSendRequest request,
  ) async {
    prepareCalls++;
    final CommunityPmSubmissionBlockedException? blocked = prepareBlocked;
    if (blocked != null) {
      throw blocked;
    }
    return CommunityPmPreparedSend(
      token: 'one-use',
      userId: 42,
      request: request,
      form: CommunityPmSendForm(
        context: request.context,
        sourceUri: request.entryUri,
        actionUri: _actionUri,
        viewerUserId: 42,
        peerUserId: request.expectedPeerUserId,
        privateMessageId: request.context == CommunityPmSendContext.compose
            ? 0
            : 123,
        formHash: 'memory-only-secret',
        fixedFields: request.context == CommunityPmSendContext.compose
            ? const <String, String>{
                'pmsubmit': 'yes',
                'referer': 'home.php?mod=space&do=pm&mobile=2',
              }
            : const <String, String>{'pmsubmit': 'yes', 'touid': '77'},
        acceptsUsername: request.context == CommunityPmSendContext.compose,
        initialUsername: request.expectedPeerUsername,
      ),
    );
  }

  @override
  Future<CommunityPmSubmissionResult> submit(
    CommunityPmPreparedSend prepared, {
    required String message,
    String username = '',
  }) {
    submitCalls++;
    submittedMessage = message;
    submittedUsername = username;
    return submission.future;
  }

  @override
  void discard(CommunityPmPreparedSend prepared) {}

  @override
  Future<void> acknowledgeUnresolved(
    CommunityPmSubmissionBlockedException blocked,
  ) async {
    acknowledgeCalls++;
    if (!identical(prepareBlocked, blocked)) {
      throw StateError('封存已变化');
    }
    prepareBlocked = null;
  }
}

class _FakePmDraftRepository extends CommunityPmDraftRepository {
  _FakePmDraftRepository() : super(_MockAppDatabase(), _MockForumClient(), 42);

  CommunityPmDraft? draft;
  int deleteCalls = 0;
  String? deletedDraftId;

  @override
  Future<CommunityPmDraft?> load(String draftId) async => draft;

  @override
  Future<void> save(String draftId, CommunityPmDraft draft) async {
    this.draft = draft;
  }

  @override
  Future<void> delete(String draftId) async {
    deleteCalls++;
    deletedDraftId = draftId;
    draft = null;
  }
}

void main() {
  testWidgets('恢复并显式保存按 uid 隔离的私信草稿', (WidgetTester tester) async {
    final _FakePmActionRepository actions = _FakePmActionRepository();
    final _FakePmDraftRepository drafts = _FakePmDraftRepository();
    drafts.draft = CommunityPmDraft(
      userId: 42,
      context: CommunityPmSendContext.conversation,
      peerUserId: 77,
      username: '用户A',
      message: '恢复的正文',
      updatedAt: DateTime.utc(2026, 8, 13),
    );
    await tester.pumpWidget(_app(actions, drafts));
    await tester.pumpAndSettle();

    final TextField field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('community-pm-message')),
    );
    expect(field.controller?.text, '恢复的正文');
    await tester.enterText(
      find.byKey(const ValueKey<String>('community-pm-message')),
      '修改后的草稿',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('community-pm-save-draft')),
    );
    await tester.pumpAndSettle();

    expect(drafts.draft?.userId, 42);
    expect(drafts.draft?.peerUserId, 77);
    expect(drafts.draft?.message, '修改后的草稿');
  });

  testWidgets('确认后防双击和等价重建，POST 未完成时禁止退出', (WidgetTester tester) async {
    final _FakePmActionRepository actions = _FakePmActionRepository();
    final _FakePmDraftRepository drafts = _FakePmDraftRepository();
    CommunityPmSendRequest currentRequest = _request;
    late StateSetter rebuild;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          communityPmActionRepositoryProvider.overrideWithValue(actions),
          communityPmDraftRepositoryProvider.overrideWithValue(drafts),
        ],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              return CommunityPmSendPage(
                key: const ValueKey<String>('pm-send-page'),
                request: currentRequest,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('community-pm-message')),
      '只提交一次',
    );
    final TextEditingController messageController = tester
        .widget<TextField>(
          find.byKey(const ValueKey<String>('community-pm-message')),
        )
        .controller!;
    await tester.tap(
      find.byKey(const ValueKey<String>('community-pm-confirm-send')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('community-pm-message')),
          )
          .enabled,
      isFalse,
    );
    messageController.text = '弹框后的变更不得提交';
    await tester.tap(
      find.byKey(const ValueKey<String>('community-pm-dialog-submit')),
    );
    await tester.pump();

    expect(actions.submitCalls, 1);
    expect(actions.submittedMessage, '只提交一次');
    expect(find.text('正在提交'), findsOneWidget);
    rebuild(() {
      currentRequest = CommunityPmSendRequest(
        context: CommunityPmSendContext.conversation,
        entryUri: Uri.parse(
          'https://bbs.yamibo.com/home.php?mod=space&do=pm&subop=view&touid=88&mobile=2',
        ),
        expectedPeerUserId: 88,
        expectedPeerUsername: '用户B',
      );
    });
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('pm-send-page')), findsOneWidget);
    expect(actions.prepareCalls, 1);
    expect(actions.submitCalls, 1);
    expect(find.text('用户A'), findsOneWidget);
    expect(find.text('用户B'), findsNothing);

    actions.submission.complete(
      const CommunityPmSubmissionResult(
        status: CommunityPmSubmissionStatus.resultUnknown,
        message: '结果未知，应用不会重发',
        submissionAttempted: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('结果未知'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('community-pm-confirm-send')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('community-pm-readback')),
      findsOneWidget,
    );
    expect(actions.submitCalls, 1);
    expect(drafts.deleteCalls, 0);
    expect(drafts.deletedDraftId, isNull);
    expect(find.text('用户B'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.textContaining('结果未知'), findsOneWidget);
    expect(find.textContaining('返回并回读'), findsWidgets);
  });

  testWidgets('持久化封存展示回读与人工解除，解除只重读表单不自动提交', (WidgetTester tester) async {
    final _FakePmActionRepository actions = _FakePmActionRepository();
    final _FakePmDraftRepository drafts = _FakePmDraftRepository();
    const SubmissionTombstoneKey key = SubmissionTombstoneKey(
      action: 'communityPmSend:conversation',
      threadId: 77,
      draftContext: 'community-pm:conversation:77',
    );
    actions.prepareBlocked = CommunityPmSubmissionBlockedException(
      request: _request,
      key: key,
      tombstone: SubmissionTombstoneRecord(
        attemptId: 'attempted-on-disk',
        userId: 42,
        key: key,
        status: ForumSubmissionTombstoneStatus.attempted,
        recordedAt: DateTime.utc(2026, 8, 13),
      ),
    );
    await tester.pumpWidget(_app(actions, drafts));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('community-pm-blocked-message')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('community-pm-blocked-readback')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('community-pm-blocked-acknowledge')),
      findsOneWidget,
    );
    expect(actions.submitCalls, 0);

    await tester.tap(
      find.byKey(const ValueKey<String>('community-pm-blocked-acknowledge')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('community-pm-blocked-confirm-acknowledge'),
      ),
    );
    await tester.pumpAndSettle();

    expect(actions.acknowledgeCalls, 1);
    expect(actions.prepareCalls, 2);
    expect(actions.submitCalls, 0);
    expect(
      find.byKey(const ValueKey<String>('community-pm-confirm-send')),
      findsOneWidget,
    );
  });

  testWidgets('私信列表的新建入口和会话回复入口接入原生编辑页', (WidgetTester tester) async {
    final _FakePmActionRepository actions = _FakePmActionRepository();
    final _FakePmDraftRepository drafts = _FakePmDraftRepository();
    final _MockCommunityRepository community = _MockCommunityRepository();
    final Uri listUri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&do=pm&mobile=2',
    );
    final Uri composeUri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=spacecp&ac=pm&mobile=2',
    );
    when(() => community.loadPmList(listUri)).thenAnswer(
      (_) async => CommunityPmListPage(
        items: <CommunityPmConversation>[
          CommunityPmConversation(
            peerUserId: 77,
            peerUsername: '用户A',
            preview: '',
            timeLabel: '',
            uri: _entryUri,
          ),
        ],
        cursor: CommunityPageCursor(
          sourceUri: listUri,
          currentPage: 1,
          totalPages: 1,
        ),
        composeUri: composeUri,
      ),
    );
    when(
      () => community.loadPmThread(_entryUri, expectedPeerUserId: 77),
    ).thenAnswer(
      (_) async => CommunityPmThreadPage(
        peerUserId: 77,
        messages: const <CommunityPmMessage>[],
        cursor: CommunityPageCursor(
          sourceUri: _entryUri,
          currentPage: 1,
          totalPages: 1,
        ),
        hasSendCapability: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          communityRepositoryProvider.overrideWithValue(community),
          communityPmActionRepositoryProvider.overrideWithValue(actions),
          communityPmDraftRepositoryProvider.overrideWithValue(drafts),
        ],
        child: MaterialApp(home: CommunityMessagesScreen(uri: listUri)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('community-pm-compose')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('community-pm-username')),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('community-pm-reply')));
    await tester.pumpAndSettle();

    expect(find.text('回复私信'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('community-pm-username')),
      findsNothing,
    );
    expect(actions.prepareCalls, 2);
  });

  testWidgets('新私信确认弹窗固定收件人与正文快照', (WidgetTester tester) async {
    final _FakePmActionRepository actions = _FakePmActionRepository();
    final _FakePmDraftRepository drafts = _FakePmDraftRepository();
    final CommunityPmSendRequest request = CommunityPmSendRequest(
      context: CommunityPmSendContext.compose,
      entryUri: Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=spacecp&ac=pm&mobile=2',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          communityPmActionRepositoryProvider.overrideWithValue(actions),
          communityPmDraftRepositoryProvider.overrideWithValue(drafts),
        ],
        child: MaterialApp(home: CommunityPmSendPage(request: request)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('community-pm-username')),
      '确认时收件人',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('community-pm-message')),
      '确认时正文',
    );
    final TextEditingController usernameController = tester
        .widget<TextField>(
          find.byKey(const ValueKey<String>('community-pm-username')),
        )
        .controller!;
    final TextEditingController messageController = tester
        .widget<TextField>(
          find.byKey(const ValueKey<String>('community-pm-message')),
        )
        .controller!;
    await tester.tap(
      find.byKey(const ValueKey<String>('community-pm-confirm-send')),
    );
    await tester.pumpAndSettle();
    usernameController.text = '弹框后收件人';
    messageController.text = '弹框后正文';
    await tester.tap(
      find.byKey(const ValueKey<String>('community-pm-dialog-submit')),
    );
    await tester.pump();

    expect(actions.submittedUsername, '确认时收件人');
    expect(actions.submittedMessage, '确认时正文');
    actions.submission.complete(
      const CommunityPmSubmissionResult(
        status: CommunityPmSubmissionStatus.resultUnknown,
        message: '结果未知',
        submissionAttempted: true,
      ),
    );
    await tester.pumpAndSettle();
  });
}

Widget _app(_FakePmActionRepository actions, _FakePmDraftRepository drafts) {
  return ProviderScope(
    overrides: [
      communityPmActionRepositoryProvider.overrideWithValue(actions),
      communityPmDraftRepositoryProvider.overrideWithValue(drafts),
    ],
    child: MaterialApp(home: CommunityPmSendPage(request: _request)),
  );
}

final Uri _entryUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=space&do=pm&subop=view&touid=77&mobile=2',
);
final Uri _actionUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=pm&op=send&pmid=123&pmsubmit=yes&daterange=2&mobile=2',
);
final CommunityPmSendRequest _request = CommunityPmSendRequest(
  context: CommunityPmSendContext.conversation,
  entryUri: _entryUri,
  expectedPeerUserId: 77,
  expectedPeerUsername: '用户A',
);
