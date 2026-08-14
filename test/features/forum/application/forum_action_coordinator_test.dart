import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/application/forum_action_coordinator.dart';
import 'package:x300/features/forum/data/forum_action_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

class _MockForumActionRepository extends Mock
    implements ForumActionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(<ForumAttachmentSelection>[]);
  });

  test('协调器合并双击与页面重建式重复 confirm，只调用一次 submit', () async {
    final _MockForumActionRepository repository = _MockForumActionRepository();
    when(() => repository.prepare(_request)).thenAnswer((_) async => _prepared);
    final Completer<ForumSubmissionResult> completion =
        Completer<ForumSubmissionResult>();
    when(
      () => repository.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) => completion.future);
    final ForumActionCoordinator coordinator = ForumActionCoordinator(
      repository,
    );
    expect((await coordinator.prepare(_request)).phase, ForumActionPhase.ready);

    final Future<ForumActionState> first = coordinator.confirm(
      <String, Object?>{'message': '正文'},
    );
    final Future<ForumActionState> second = coordinator.confirm(
      <String, Object?>{'message': '重复点击'},
    );
    expect(identical(first, second), isTrue);
    completion.complete(_successResult);

    expect((await first).phase, ForumActionPhase.completed);
    expect((await second).result?.status, ForumSubmissionStatus.success);
    expect(
      (await coordinator.confirm(<String, Object?>{
        'message': '重建后',
      })).result?.status,
      ForumSubmissionStatus.success,
    );
    verify(
      () => repository.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).called(1);
  });

  test('本地校验失败返回 ready，可修正输入后复用同一 prepared', () async {
    final _MockForumActionRepository repository = _MockForumActionRepository();
    when(() => repository.prepare(_request)).thenAnswer((_) async => _prepared);
    when(
      () => repository.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((Invocation invocation) async {
      final Map<String, Object?> values =
          invocation.positionalArguments[1] as Map<String, Object?>;
      if (values['message'] == '') {
        return ForumSubmissionResult(
          status: ForumSubmissionStatus.explicitFailure,
          userId: 42,
          message: '正文不能为空',
          readback: _readback,
          canRetryPrepared: true,
        );
      }
      return _successResult;
    });
    final ForumActionCoordinator coordinator = ForumActionCoordinator(
      repository,
    );
    await coordinator.prepare(_request);

    final ForumActionState invalid = await coordinator.confirm(
      <String, Object?>{'message': ''},
    );
    expect(invalid.phase, ForumActionPhase.ready);
    expect(invalid.errorMessage, '正文不能为空');

    final ForumActionState corrected = await coordinator.confirm(
      <String, Object?>{'message': '修正'},
    );
    expect(corrected.phase, ForumActionPhase.completed);
    expect(corrected.result?.status, ForumSubmissionStatus.success);
    verify(
      () => repository.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).called(2);
  });

  test('resultUnknown 进入不可重提的 completed，重复 confirm 不调用 submit', () async {
    final _MockForumActionRepository repository = _MockForumActionRepository();
    when(() => repository.prepare(_request)).thenAnswer((_) async => _prepared);
    final ForumSubmissionResult unknown = ForumSubmissionResult(
      status: ForumSubmissionStatus.resultUnknown,
      userId: 42,
      message: '结果未知',
      readback: _readback,
      submissionAttempted: true,
    );
    when(
      () => repository.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) async => unknown);
    final ForumActionCoordinator coordinator = ForumActionCoordinator(
      repository,
    );
    await coordinator.prepare(_request);

    expect(
      (await coordinator.confirm(<String, Object?>{'message': '一次'})).phase,
      ForumActionPhase.completed,
    );
    expect(
      (await coordinator.confirm(<String, Object?>{
        'message': '二次',
      })).result?.status,
      ForumSubmissionStatus.resultUnknown,
    );
    verify(
      () => repository.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).called(1);
  });

  test('未知提交异常进入可重置 failed，不保留可重提 prepared', () async {
    final _MockForumActionRepository repository = _MockForumActionRepository();
    when(() => repository.prepare(_request)).thenAnswer((_) async => _prepared);
    when(
      () => repository.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenThrow(StateError('unexpected'));
    final ForumActionCoordinator coordinator = ForumActionCoordinator(
      repository,
    );
    await coordinator.prepare(_request);

    final ForumActionState failed = await coordinator.confirm(<String, Object?>{
      'message': '一次',
    });
    expect(failed.phase, ForumActionPhase.failed);
    expect(failed.prepared, isNull);
    expect(failed.errorMessage, contains('未知错误'));
    verify(() => repository.discard(_prepared)).called(1);

    coordinator.reset();
    expect(coordinator.state.phase, ForumActionPhase.idle);
  });

  test('prepare 与 POST 前会话失效均保留可机读 sessionExpired', () async {
    final _MockForumActionRepository prepareRepository =
        _MockForumActionRepository();
    when(
      () => prepareRepository.prepare(_request),
    ).thenThrow(const ForumSessionExpiredException());
    final ForumActionCoordinator prepareCoordinator = ForumActionCoordinator(
      prepareRepository,
    );
    final ForumActionState prepareFailed = await prepareCoordinator.prepare(
      _request,
    );
    expect(prepareFailed.phase, ForumActionPhase.failed);
    expect(prepareFailed.sessionExpired, isTrue);

    final _MockForumActionRepository submitRepository =
        _MockForumActionRepository();
    when(
      () => submitRepository.prepare(_request),
    ).thenAnswer((_) async => _prepared);
    when(
      () => submitRepository.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenThrow(const ForumSessionExpiredException());
    final ForumActionCoordinator submitCoordinator = ForumActionCoordinator(
      submitRepository,
    );
    await submitCoordinator.prepare(_request);
    final ForumActionState submitFailed = await submitCoordinator.confirm(
      <String, Object?>{'message': '一次'},
    );
    expect(submitFailed.phase, ForumActionPhase.failed);
    expect(submitFailed.sessionExpired, isTrue);
    expect(submitFailed.prepared, isNull);
  });

  test('POST 后身份无法确认的 resultUnknown 同时标记 sessionExpired', () async {
    final _MockForumActionRepository repository = _MockForumActionRepository();
    when(() => repository.prepare(_request)).thenAnswer((_) async => _prepared);
    when(
      () => repository.submit(
        _prepared,
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer(
      (_) async => ForumSubmissionResult(
        status: ForumSubmissionStatus.resultUnknown,
        userId: 42,
        message: '身份无法确认',
        readback: _readback,
        submissionAttempted: true,
        requiresSessionRefresh: true,
      ),
    );
    final ForumActionCoordinator coordinator = ForumActionCoordinator(
      repository,
    );
    await coordinator.prepare(_request);

    final ForumActionState state = await coordinator.confirm(<String, Object?>{
      'message': '一次',
    });
    expect(state.phase, ForumActionPhase.completed);
    expect(state.result?.status, ForumSubmissionStatus.resultUnknown);
    expect(state.sessionExpired, isTrue);
  });
}

final Uri _entryUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=30&tid=101&mobile=2',
);
final Uri _actionUri = Uri.parse(
  'https://bbs.yamibo.com/api/mobile/index.php?version=4&module=sendreply&tid=101&fid=30',
);
final Uri _readbackUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2',
);
final ForumActionRequest _request = ForumActionRequest(
  kind: ForumActionKind.reply,
  target: const ForumActionTarget(boardId: 30, threadId: 101),
  entryUri: _entryUri,
  readbackUri: _readbackUri,
);
final ForumReadbackDescriptor _readback = ForumReadbackDescriptor(
  kind: ForumReadbackKind.thread,
  uri: _readbackUri,
  target: _request.target,
  description: '回读主题',
);
final ForumPreparedAction _prepared = ForumPreparedAction(
  token: 'one-time',
  userId: 42,
  request: _request,
  form: DynamicForumForm(
    sourceUri: _entryUri,
    actionUri: _actionUri,
    hiddenFields: const <String, List<String>>{
      'formhash': <String>['secret'],
      'tid': <String>['101'],
    },
    submitFields: const <String, List<String>>{
      'replysubmit': <String>['yes'],
    },
    fields: const <DynamicForumField>[],
    attachmentFields: const <ForumAttachmentField>[],
    preparedAt: DateTime.utc(2026, 8, 13),
  ),
  readback: _readback,
);
final ForumSubmissionResult _successResult = ForumSubmissionResult(
  status: ForumSubmissionStatus.success,
  userId: 42,
  message: '成功，需回读',
  readback: _readback,
);
