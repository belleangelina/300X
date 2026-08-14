import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_action_repository.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

final Provider<ForumActionCoordinator> forumActionCoordinatorProvider =
    Provider<ForumActionCoordinator>(
      (Ref ref) =>
          ForumActionCoordinator(ref.watch(forumActionRepositoryProvider)),
    );

enum ForumActionPhase { idle, preparing, ready, submitting, completed, failed }

class ForumActionState {
  const ForumActionState({
    required this.phase,
    this.prepared,
    this.result,
    this.unresolvedSubmission,
    this.errorMessage = '',
    this.sessionExpired = false,
  });

  const ForumActionState.idle() : this(phase: ForumActionPhase.idle);

  final ForumActionPhase phase;
  final ForumPreparedAction? prepared;
  final ForumSubmissionResult? result;
  final ForumUnresolvedSubmission? unresolvedSubmission;
  final String errorMessage;
  final bool sessionExpired;
}

class ForumActionCoordinator {
  ForumActionCoordinator(this._repository);

  final ForumActionRepository _repository;
  ForumActionState _state = const ForumActionState.idle();
  Future<ForumActionState>? _submission;

  ForumActionState get state => _state;

  Future<ForumActionState> prepare(ForumActionRequest request) async {
    if (_state.phase == ForumActionPhase.preparing ||
        _state.phase == ForumActionPhase.submitting) {
      throw StateError('已有论坛操作正在进行');
    }
    final ForumPreparedAction? previous = _state.prepared;
    if (previous != null) {
      _repository.discard(previous);
    }
    _submission = null;
    _state = const ForumActionState(phase: ForumActionPhase.preparing);
    try {
      final ForumPreparedAction prepared = await _repository.prepare(request);
      _state = ForumActionState(
        phase: ForumActionPhase.ready,
        prepared: prepared,
      );
    } on ForumSubmissionBlockedException catch (error) {
      _state = ForumActionState(
        phase: ForumActionPhase.failed,
        errorMessage: error.message,
        unresolvedSubmission: error.submission,
      );
    } on ForumSessionExpiredException catch (error) {
      _state = ForumActionState(
        phase: ForumActionPhase.failed,
        errorMessage: error.message,
        sessionExpired: true,
      );
    } on ForumException catch (error) {
      _state = ForumActionState(
        phase: ForumActionPhase.failed,
        errorMessage: error.message,
      );
    } on Object {
      _state = const ForumActionState(
        phase: ForumActionPhase.failed,
        errorMessage: '准备论坛操作时发生未知错误',
      );
    }
    return _state;
  }

  Future<ForumActionState> confirm(
    Map<String, Object?> values, {
    List<ForumAttachmentSelection> attachments =
        const <ForumAttachmentSelection>[],
  }) {
    if (_state.phase == ForumActionPhase.ready &&
        _state.result?.canRetryPrepared == true) {
      _submission = null;
    }
    final Future<ForumActionState>? existing = _submission;
    if (existing != null) {
      return existing;
    }
    if (_state.phase == ForumActionPhase.completed) {
      return Future<ForumActionState>.value(_state);
    }
    final ForumPreparedAction? prepared = _state.prepared;
    if (_state.phase != ForumActionPhase.ready || prepared == null) {
      throw StateError('论坛操作尚未准备完成');
    }
    _state = ForumActionState(
      phase: ForumActionPhase.submitting,
      prepared: prepared,
    );
    final Future<ForumActionState> submission = _submitOnce(
      prepared,
      Map<String, Object?>.unmodifiable(values),
      List<ForumAttachmentSelection>.unmodifiable(attachments),
    );
    _submission = submission;
    return submission;
  }

  void reset() {
    if (_state.phase == ForumActionPhase.submitting) {
      throw StateError('提交期间不能重置论坛操作');
    }
    final ForumPreparedAction? prepared = _state.prepared;
    if (prepared != null) {
      _repository.discard(prepared);
    }
    _submission = null;
    _state = const ForumActionState.idle();
  }

  Future<ForumActionState> _submitOnce(
    ForumPreparedAction prepared,
    Map<String, Object?> values,
    List<ForumAttachmentSelection> attachments,
  ) async {
    try {
      final ForumSubmissionResult result = await _repository.submit(
        prepared,
        values,
        attachments: attachments,
      );
      _state = ForumActionState(
        phase: result.canRetryPrepared
            ? ForumActionPhase.ready
            : ForumActionPhase.completed,
        prepared: prepared,
        result: result,
        errorMessage: result.canRetryPrepared ? result.message : '',
        sessionExpired: result.requiresSessionRefresh,
      );
    } on ForumSubmissionBlockedException catch (error) {
      _repository.discard(prepared);
      _state = ForumActionState(
        phase: ForumActionPhase.failed,
        errorMessage: error.message,
        unresolvedSubmission: error.submission,
      );
    } on ForumSessionExpiredException catch (error) {
      _repository.discard(prepared);
      _state = ForumActionState(
        phase: ForumActionPhase.failed,
        errorMessage: error.message,
        sessionExpired: true,
      );
    } on ForumException catch (error) {
      _repository.discard(prepared);
      _state = ForumActionState(
        phase: ForumActionPhase.failed,
        errorMessage: error.message,
      );
    } on Object {
      _repository.discard(prepared);
      _state = ForumActionState(
        phase: ForumActionPhase.failed,
        errorMessage: '提交论坛操作时发生未知错误，请先回读目标资源',
      );
    }
    return _state;
  }
}
