import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/forum/data/forum_action_repository.dart';
import 'package:x300/features/forum/data/forum_draft_repository.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';
import 'package:x300/features/forum/presentation/forum_action_page.dart';

class _MockActionRepository extends Mock implements ForumActionRepository {}

class _MockDraftRepository extends Mock implements ForumDraftRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int actionPagePopCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == 'forum-action-test') {
      actionPagePopCount++;
    }
    super.didPop(route, previousRoute);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(_request);
    registerFallbackValue(_prepared);
    registerFallbackValue(_readback);
    registerFallbackValue(_unresolved);
    registerFallbackValue(
      ForumActionDraft(
        userId: 42,
        kind: ForumActionKind.newThread,
        target: _request.target,
        values: const <String, List<String>>{},
        updatedAt: DateTime.utc(2026, 8, 13),
      ),
    );
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(<ForumAttachmentSelection>[]);
  });

  testWidgets('恢复结构化草稿、提供 BBCode 工具并显式保存', (
    WidgetTester tester,
  ) async {
    final _MockActionRepository actions = _MockActionRepository();
    final _MockDraftRepository drafts = _MockDraftRepository();
    _stubPrepared(actions);
    when(() => drafts.load('new-thread-30')).thenAnswer(
      (_) async => ForumActionDraft(
        userId: 42,
        kind: ForumActionKind.newThread,
        target: _request.target,
        values: const <String, List<String>>{
          'subject': <String>['草稿标题'],
          'message': <String>['草稿正文'],
          'typeid': <String>['7'],
        },
        updatedAt: DateTime.utc(2026, 8, 13),
      ),
    );
    when(() => drafts.save(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      _app(actions, drafts, themeMode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();

    expect(find.text('已恢复本账号草稿；提交前已重新读取最新论坛表单。'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '草稿标题'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '草稿正文'), findsOneWidget);
    expect(find.byKey(const Key('forum-bbcode-b')), findsOneWidget);
    final Finder message = find.byKey(const ValueKey<String>('forum-action-message'));
    await tester.tap(message);
    await tester.pump();
    final EditableText editable = tester.widget<EditableText>(
      find.descendant(of: message, matching: find.byType(EditableText)),
    );
    editable.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: editable.controller.text.length,
    );
    await tester.tap(find.byKey(const Key('forum-bbcode-b')));
    await tester.tap(find.byKey(const Key('forum-action-save-draft')));
    await tester.pumpAndSettle();

    final ForumActionDraft saved = verify(
      () => drafts.save('new-thread-30', captureAny()),
    ).captured.single as ForumActionDraft;
    expect(saved.values['message'], <String>['[b]草稿正文[/b]']);
    expect(saved.values, isNot(contains('formhash')));
    expect(saved.values, isNot(contains('seccodeverify')));
  });

  testWidgets('必填校验、二次确认及连续点击只调用一次提交', (
    WidgetTester tester,
  ) async {
    final _MockActionRepository actions = _MockActionRepository();
    final _MockDraftRepository drafts = _MockDraftRepository();
    _stubPrepared(actions);
    when(() => drafts.load(any())).thenAnswer((_) async => null);
    final Completer<ForumSubmissionResult> submitted =
        Completer<ForumSubmissionResult>();
    when(
      () => actions.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) => submitted.future);
    when(() => actions.readback(_readback)).thenAnswer((_) async => _receipt);
    when(
      () => drafts.delete(any(), userId: any(named: 'userId')),
    ).thenAnswer((_) async {});
    final ValueNotifier<ForumActionRequest> request =
        ValueNotifier<ForumActionRequest>(_request);
    final _RecordingNavigatorObserver observer =
        _RecordingNavigatorObserver();

    await tester.pumpWidget(
      _pushedApp(actions, drafts, request: request, observer: observer),
    );
    await tester.tap(find.byKey(const Key('forum-action-launch')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('forum-action-subject')),
      '',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('forum-action-message')),
      '',
    );
    await tester.tap(find.byKey(const Key('forum-action-submit')));
    await tester.pump();
    expect(find.text('主题不能为空'), findsOneWidget);
    expect(find.byKey(const Key('forum-action-confirm')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('forum-action-subject')),
      '测试主题',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('forum-action-message')),
      '测试正文',
    );
    final FilledButton submit = tester.widget<FilledButton>(
      find.byKey(const Key('forum-action-submit')),
    );
    submit.onPressed!();
    submit.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('确认提交到论坛？'), findsOneWidget);
    expect(find.text('将使用刚刚读取的移动表单提交一次。响应丢失时不会自动重发。'), findsOneWidget);
    tester
        .widget<TextFormField>(
          find.byKey(const ValueKey<String>('forum-action-message')),
        )
        .controller!
        .text = '确认框显示后被修改';
    await tester.tap(find.byKey(const Key('forum-action-confirm')));
    await tester.pump();

    expect(find.text('正在提交'), findsOneWidget);
    request.value = ForumActionRequest(
      kind: ForumActionKind.newThread,
      target: const ForumActionTarget(boardId: 30),
      entryUri: _entryUri,
      readbackUri: _readbackUri,
    );
    await tester.pump();
    expect(find.text('正在提交'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('提交与回读完成前不能离开此页'), findsOneWidget);
    expect(find.byType(ForumActionPage), findsOneWidget);
    final Map<String, Object?> submittedValues = verify(
      () => actions.submit(
        _prepared,
        captureAny(),
        attachments: any(named: 'attachments'),
      ),
    ).captured.single as Map<String, Object?>;
    expect(submittedValues['message'], '测试正文');
    verify(() => actions.prepare(_request)).called(1);
    submitted.complete(_success);
    await tester.pumpAndSettle();
    expect(find.text('论坛已确认成功'), findsOneWidget);
    verify(() => actions.readback(_readback)).called(1);
    await tester.tap(find.text('返回并刷新'));
    await tester.pumpAndSettle();
    expect(observer.actionPagePopCount, 1);
    verify(() => drafts.delete('new-thread-30', userId: 42)).called(1);
  });

  testWidgets('表单刷新首次失败后重试仍恢复用户输入', (
    WidgetTester tester,
  ) async {
    final _MockActionRepository actions = _MockActionRepository();
    final _MockDraftRepository drafts = _MockDraftRepository();
    int prepareCount = 0;
    when(() => actions.prepare(_request)).thenAnswer((_) async {
      prepareCount++;
      if (prepareCount == 1) {
        return _prepared;
      }
      if (prepareCount == 2) {
        throw const ForumConnectionException('首次刷新失败');
      }
      return _refreshedPrepared;
    });
    when(() => actions.discard(any())).thenReturn(null);
    when(() => drafts.load(any())).thenAnswer((_) async => null);
    when(
      () => actions.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) async => _tokenExpired);

    await tester.pumpWidget(_app(actions, drafts));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('forum-action-subject')),
      '刷新前标题',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('forum-action-message')),
      '刷新前正文',
    );
    tester
        .widget<CheckboxListTile>(
          find.widgetWithText(CheckboxListTile, '漫画'),
        )
        .onChanged!(true);
    await tester.pump();
    tester
        .widget<FilledButton>(find.byKey(const Key('forum-action-submit')))
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-action-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('forum-action-refresh-form')));
    await tester.pumpAndSettle();
    expect(find.text('首次刷新失败'), findsOneWidget);
    await tester.tap(find.text('点击重试'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '刷新前标题'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '刷新前正文'), findsOneWidget);
    final CheckboxListTile comic = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '漫画'),
    );
    expect(comic.value, isTrue);
    expect(prepareCount, 3);
    verify(() => drafts.load('new-thread-30')).called(1);
  });

  testWidgets('确认期间切换请求并取消后改为准备最新请求', (
    WidgetTester tester,
  ) async {
    final _MockActionRepository actions = _MockActionRepository();
    final _MockDraftRepository drafts = _MockDraftRepository();
    _stubPrepared(actions);
    when(() => actions.prepare(_requestB)).thenAnswer((_) async => _preparedB);
    when(() => drafts.load(any())).thenAnswer((_) async => null);
    final ValueNotifier<ForumActionRequest> request =
        ValueNotifier<ForumActionRequest>(_request);

    await tester.pumpWidget(
      _pushedApp(
        actions,
        drafts,
        request: request,
        observer: _RecordingNavigatorObserver(),
      ),
    );
    await tester.tap(find.byKey(const Key('forum-action-launch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-action-submit')));
    await tester.pumpAndSettle();

    request.value = _requestB;
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'B 初始主题'), findsOneWidget);
    verify(() => actions.prepare(_requestB)).called(1);
    verifyNever(
      () => actions.submit(
        any(),
        any(),
        attachments: any(named: 'attachments'),
      ),
    );
  });

  testWidgets('提交期间切换请求且本地可重试时改为准备最新请求', (
    WidgetTester tester,
  ) async {
    final _MockActionRepository actions = _MockActionRepository();
    final _MockDraftRepository drafts = _MockDraftRepository();
    _stubPrepared(actions);
    when(() => actions.prepare(_requestB)).thenAnswer((_) async => _preparedB);
    when(() => drafts.load(any())).thenAnswer((_) async => null);
    final Completer<ForumSubmissionResult> submitted =
        Completer<ForumSubmissionResult>();
    when(
      () => actions.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) => submitted.future);
    final ValueNotifier<ForumActionRequest> request =
        ValueNotifier<ForumActionRequest>(_request);

    await tester.pumpWidget(
      _pushedApp(
        actions,
        drafts,
        request: request,
        observer: _RecordingNavigatorObserver(),
      ),
    );
    await tester.tap(find.byKey(const Key('forum-action-launch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-action-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-action-confirm')));
    await tester.pump();

    request.value = _requestB;
    await tester.pump();
    submitted.complete(_retryableFailure);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'B 初始主题'), findsOneWidget);
    verify(() => actions.prepare(_requestB)).called(1);
    verifyNever(() => actions.readback(any()));
  });

  testWidgets('切换请求后提交异常与非回读终态都会准备最新请求', (
    WidgetTester tester,
  ) async {
    for (final bool resultIsNull in <bool>[true, false]) {
      final _MockActionRepository actions = _MockActionRepository();
      final _MockDraftRepository drafts = _MockDraftRepository();
      _stubPrepared(actions);
      when(() => actions.prepare(_requestB)).thenAnswer(
        (_) async => _preparedB,
      );
      when(() => drafts.load(any())).thenAnswer((_) async => null);
      final Completer<ForumSubmissionResult> submitted =
          Completer<ForumSubmissionResult>();
      when(
        () => actions.submit(
          _prepared,
          any(),
          attachments: any(named: 'attachments'),
        ),
      ).thenAnswer((_) => submitted.future);
      final ValueNotifier<ForumActionRequest> request =
          ValueNotifier<ForumActionRequest>(_request);

      await tester.pumpWidget(
        _pushedApp(
          actions,
          drafts,
          request: request,
          observer: _RecordingNavigatorObserver(),
        ),
      );
      await tester.tap(find.byKey(const Key('forum-action-launch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forum-action-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forum-action-confirm')));
      await tester.pump();

      request.value = _requestB;
      await tester.pump();
      if (resultIsNull) {
        submitted.completeError(const ForumConnectionException('提交失败'));
      } else {
        submitted.complete(_tokenExpired);
      }
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'B 初始主题'), findsOneWidget);
      verify(() => actions.prepare(_requestB)).called(1);
      request.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('账号和目标切换后终态只清理提交时账号的原草稿', (
    WidgetTester tester,
  ) async {
    final _MockActionRepository actions = _MockActionRepository();
    final _MockDraftRepository oldDrafts = _MockDraftRepository();
    final _MockDraftRepository newDrafts = _MockDraftRepository();
    _stubPrepared(actions);
    when(() => oldDrafts.load(any())).thenAnswer((_) async => null);
    when(
      () => oldDrafts.delete(any(), userId: any(named: 'userId')),
    ).thenAnswer((_) async {});
    final Completer<ForumSubmissionResult> submitted =
        Completer<ForumSubmissionResult>();
    when(
      () => actions.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) => submitted.future);
    when(() => actions.readback(_readback)).thenAnswer((_) async => _receipt);

    await tester.pumpWidget(_app(actions, oldDrafts));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-action-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-action-confirm')));
    await tester.pump();

    await tester.pumpWidget(
      _app(
        actions,
        newDrafts,
        request: _requestB,
        draftId: 'new-thread-30',
      ),
    );
    await tester.pump();
    submitted.complete(_success);
    await tester.pumpAndSettle();

    expect(find.text('论坛已确认成功'), findsOneWidget);
    verify(() => actions.readback(_readback)).called(1);
    verify(() => oldDrafts.delete('new-thread-30', userId: 42)).called(1);
    verifyNever(
      () => newDrafts.delete(any(), userId: any(named: 'userId')),
    );
    verifyNever(() => actions.prepare(_requestB));
  });

  testWidgets('提交结果未知只回读并提示勿重发', (
    WidgetTester tester,
  ) async {
    final _MockActionRepository actions = _MockActionRepository();
    final _MockDraftRepository drafts = _MockDraftRepository();
    _stubPrepared(actions);
    when(() => drafts.load(any())).thenAnswer((_) async => null);
    when(
      () => actions.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) async => _unknown);
    when(() => actions.readback(_readback)).thenAnswer((_) async => _receipt);

    await tester.pumpWidget(_app(actions, drafts));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-action-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-action-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('提交结果未知'), findsOneWidget);
    expect(find.textContaining('请勿直接重复提交'), findsOneWidget);
    expect(find.byKey(const Key('forum-action-submit')), findsNothing);
    verify(
      () => actions.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).called(1);
    verifyNever(
      () => drafts.delete(any(), userId: any(named: 'userId')),
    );
  });

  testWidgets('提交前会话失效后移除旧表单并禁止再次提交', (
    WidgetTester tester,
  ) async {
    final _MockActionRepository actions = _MockActionRepository();
    final _MockDraftRepository drafts = _MockDraftRepository();
    final _MockAuthRepository auth = _MockAuthRepository();
    _stubPrepared(actions);
    when(() => drafts.load(any())).thenAnswer((_) async => null);
    when(auth.restoreSession).thenAnswer(
      (_) async => const AuthState.authenticated('测试账号', userId: 42),
    );
    when(
      () => actions.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenThrow(const ForumSessionExpiredException());

    await tester.pumpWidget(_app(actions, drafts, auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-action-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-action-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('登录状态已失效'), findsOneWidget);
    expect(find.byKey(const Key('forum-action-submit')), findsNothing);
    expect(find.text('点击重试'), findsOneWidget);
    verify(
      () => actions.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).called(1);
  });

  testWidgets('进程恢复发现封存时只允许回读，人工确认后才重新读取表单', (
    WidgetTester tester,
  ) async {
    final _MockActionRepository actions = _MockActionRepository();
    final _MockDraftRepository drafts = _MockDraftRepository();
    int prepareCount = 0;
    when(() => actions.prepare(_request)).thenAnswer((_) async {
      prepareCount++;
      if (prepareCount == 1) {
        throw ForumSubmissionBlockedException(_unresolved);
      }
      return _refreshedPrepared;
    });
    when(
      () => actions.readbackUnresolved(_unresolved),
    ).thenAnswer((_) async => _receipt);
    when(
      () => actions.acknowledgeUnresolved(_unresolved),
    ).thenAnswer((_) async {});
    when(() => drafts.load(any())).thenAnswer((_) async => null);

    await tester.pumpWidget(_app(actions, drafts));
    await tester.pumpAndSettle();

    expect(find.textContaining('尚未人工核对的提交记录'), findsOneWidget);
    expect(find.byKey(const Key('forum-action-submit')), findsNothing);
    expect(
      find.byKey(const Key('forum-action-unresolved-readback')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('forum-action-unresolved-readback')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已完成目标资源回读'), findsOneWidget);
    verify(() => actions.readbackUnresolved(_unresolved)).called(1);

    await tester.tap(
      find.byKey(const Key('forum-action-unresolved-acknowledge')),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认解除防重复封存？'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('forum-action-unresolved-confirm-acknowledge')),
    );
    await tester.pumpAndSettle();

    verify(() => actions.acknowledgeUnresolved(_unresolved)).called(1);
    expect(find.byKey(const Key('forum-action-submit')), findsOneWidget);
    expect(prepareCount, 2);
    verifyNever(
      () => actions.submit(
        any(),
        any(),
        attachments: any(named: 'attachments'),
      ),
    );
  });
}

void _stubPrepared(_MockActionRepository repository) {
  when(() => repository.prepare(_request)).thenAnswer((_) async => _prepared);
  when(() => repository.discard(any())).thenReturn(null);
}

Widget _app(
  ForumActionRepository actions,
  ForumDraftRepository drafts, {
  ThemeMode themeMode = ThemeMode.light,
  AuthRepository? auth,
  ForumActionRequest? request,
  String? draftId = 'new-thread-30',
}) {
  return ProviderScope(
    overrides: [
      forumActionRepositoryProvider.overrideWithValue(actions),
      forumDraftRepositoryProvider.overrideWithValue(drafts),
      if (auth != null) authRepositoryProvider.overrideWithValue(auth),
    ],
    child: MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.purple),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      home: ForumActionPage(
        request: request ?? _request,
        title: '发主题',
        draftId: draftId,
      ),
    ),
  );
}

Widget _pushedApp(
  ForumActionRepository actions,
  ForumDraftRepository drafts, {
  required ValueNotifier<ForumActionRequest> request,
  required NavigatorObserver observer,
}) {
  return ProviderScope(
    overrides: [
      forumActionRepositoryProvider.overrideWithValue(actions),
      forumDraftRepositoryProvider.overrideWithValue(drafts),
    ],
    child: MaterialApp(
      navigatorObservers: <NavigatorObserver>[observer],
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: FilledButton(
            key: const Key('forum-action-launch'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<ForumActionPageResult>(
                settings: const RouteSettings(name: 'forum-action-test'),
                builder: (BuildContext context) => ValueListenableBuilder<
                  ForumActionRequest
                >(
                  valueListenable: request,
                  builder: (
                    BuildContext context,
                    ForumActionRequest value,
                    Widget? child,
                  ) => ForumActionPage(
                    request: value,
                    title: '发主题',
                    draftId: 'new-thread-${value.target.boardId}',
                  ),
                ),
              ),
            ),
            child: const Text('打开发主题页'),
          ),
        ),
      ),
    ),
  );
}

final Uri _entryUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=30&mobile=2',
);
final Uri _actionUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=30&topicsubmit=yes&mobile=2',
);
final Uri _readbackUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&mobile=2',
);
final Uri _entryUriB = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=31&mobile=2',
);
final Uri _actionUriB = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=31&topicsubmit=yes&mobile=2',
);
final Uri _readbackUriB = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=31&mobile=2',
);
final ForumActionRequest _request = ForumActionRequest(
  kind: ForumActionKind.newThread,
  target: const ForumActionTarget(boardId: 30),
  entryUri: _entryUri,
  readbackUri: _readbackUri,
);
final ForumActionRequest _requestB = ForumActionRequest(
  kind: ForumActionKind.newThread,
  target: const ForumActionTarget(boardId: 31),
  entryUri: _entryUriB,
  readbackUri: _readbackUriB,
);
final ForumReadbackDescriptor _readback = ForumReadbackDescriptor(
  kind: ForumReadbackKind.boardThreads,
  uri: _readbackUri,
  target: _request.target,
  description: '刷新目标版块',
);
final ForumPreparedAction _prepared = ForumPreparedAction(
  token: 'single-use',
  userId: 42,
  request: _request,
  form: DynamicForumForm(
    sourceUri: _entryUri,
    actionUri: _actionUri,
    hiddenFields: const <String, List<String>>{
      'formhash': <String>['memory-only'],
      'fid': <String>['30'],
    },
    submitFields: const <String, List<String>>{
      'topicsubmit': <String>['yes'],
    },
    fields: const <DynamicForumField>[
      DynamicForumField(
        name: 'subject',
        label: '主题',
        type: DynamicForumFieldType.text,
        isRequired: true,
        multiple: false,
        initialValues: <String>['初始主题'],
        options: <DynamicForumFieldOption>[],
      ),
      DynamicForumField(
        name: 'message',
        label: '正文',
        type: DynamicForumFieldType.multiline,
        isRequired: true,
        multiple: false,
        initialValues: <String>['初始正文'],
        options: <DynamicForumFieldOption>[],
      ),
      DynamicForumField(
        name: 'typeid',
        label: '分类',
        type: DynamicForumFieldType.select,
        isRequired: true,
        multiple: false,
        initialValues: <String>['7'],
        options: <DynamicForumFieldOption>[
          DynamicForumFieldOption(value: '0', label: '请选择'),
          DynamicForumFieldOption(value: '7', label: '交流', selected: true),
        ],
      ),
      DynamicForumField(
        name: 'tags[]',
        label: '标签',
        type: DynamicForumFieldType.checkbox,
        isRequired: false,
        multiple: true,
        initialValues: <String>[],
        options: <DynamicForumFieldOption>[
          DynamicForumFieldOption(value: 'comic', label: '漫画'),
          DynamicForumFieldOption(value: 'novel', label: '小说'),
        ],
      ),
      DynamicForumField(
        name: 'Filedata',
        label: '附件',
        type: DynamicForumFieldType.file,
        isRequired: false,
        multiple: true,
        initialValues: <String>[],
        options: <DynamicForumFieldOption>[],
      ),
    ],
    attachmentFields: const <ForumAttachmentField>[
      ForumAttachmentField(
        fieldName: 'Filedata',
        multiple: true,
        allowedExtensions: <String>['.jpg'],
      ),
    ],
    preparedAt: DateTime.utc(2026, 8, 13),
  ),
  readback: _readback,
  draftContext: 'new-thread-30',
);
final ForumPreparedAction _refreshedPrepared = ForumPreparedAction(
  token: 'refreshed-single-use',
  userId: 42,
  request: _request,
  form: _prepared.form,
  readback: _readback,
  draftContext: 'new-thread-30',
);
final ForumReadbackDescriptor _readbackB = ForumReadbackDescriptor(
  kind: ForumReadbackKind.boardThreads,
  uri: _readbackUriB,
  target: _requestB.target,
  description: '刷新 B 版块',
);
final ForumPreparedAction _preparedB = ForumPreparedAction(
  token: 'single-use-b',
  userId: 42,
  request: _requestB,
  form: DynamicForumForm(
    sourceUri: _entryUriB,
    actionUri: _actionUriB,
    hiddenFields: const <String, List<String>>{
      'formhash': <String>['memory-only-b'],
      'fid': <String>['31'],
    },
    submitFields: const <String, List<String>>{
      'topicsubmit': <String>['yes'],
    },
    fields: <DynamicForumField>[
      const DynamicForumField(
        name: 'subject',
        label: '主题',
        type: DynamicForumFieldType.text,
        isRequired: true,
        multiple: false,
        initialValues: <String>['B 初始主题'],
        options: <DynamicForumFieldOption>[],
      ),
      ..._prepared.form.fields.skip(1),
    ],
    attachmentFields: _prepared.form.attachmentFields,
    preparedAt: DateTime.utc(2026, 8, 13),
  ),
  readback: _readbackB,
  draftContext: 'new-thread-31',
);
final ForumSubmissionResult _success = ForumSubmissionResult(
  status: ForumSubmissionStatus.success,
  userId: 42,
  message: '主题发布成功',
  readback: _readback,
  submissionAttempted: true,
);
final ForumSubmissionResult _tokenExpired = ForumSubmissionResult(
  status: ForumSubmissionStatus.tokenExpired,
  userId: 42,
  message: '操作表单已过期',
  readback: _readback,
  submissionAttempted: true,
);
final ForumSubmissionResult _retryableFailure = ForumSubmissionResult(
  status: ForumSubmissionStatus.explicitFailure,
  userId: 42,
  message: '本地校验未通过',
  readback: _readback,
  canRetryPrepared: true,
);
final ForumSubmissionResult _unknown = ForumSubmissionResult(
  status: ForumSubmissionStatus.resultUnknown,
  userId: 42,
  message: '提交结果未知，请勿重复提交',
  readback: _readback,
  submissionAttempted: true,
);
final ForumUnresolvedSubmission _unresolved = ForumUnresolvedSubmission(
  attemptId: 'attempted-before-crash',
  userId: 42,
  request: _request,
  readback: _readback,
  status: ForumSubmissionTombstoneStatus.attempted,
  recordedAt: DateTime.utc(2026, 8, 13),
  draftContext: 'new-thread:30',
);
final ForumReadbackReceipt _receipt = ForumReadbackReceipt(
  userId: 42,
  descriptor: _readback,
  sourceUri: _readbackUri,
  contentDigest: 'digest',
  receivedAt: DateTime.utc(2026, 8, 13),
);
