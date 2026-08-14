import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/community/data/community_pm_action_repository.dart';
import 'package:x300/features/community/data/community_pm_draft_repository.dart';
import 'package:x300/features/community/domain/community_pm_action_models.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class CommunityPmSendPage extends ConsumerStatefulWidget {
  const CommunityPmSendPage({required this.request, super.key});

  final CommunityPmSendRequest request;

  @override
  ConsumerState<CommunityPmSendPage> createState() =>
      _CommunityPmSendPageState();
}

class _CommunityPmSendPageState extends ConsumerState<CommunityPmSendPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  CommunityPmActionRepository? _actionRepository;
  CommunityPmDraftRepository? _draftRepository;
  CommunityPmPreparedSend? _prepared;
  CommunityPmSubmissionResult? _result;
  CommunityPmSubmissionBlockedException? _blocked;
  CommunityPmSendRequest? _terminalRequest;
  Object? _error;
  bool _loading = true;
  bool _confirming = false;
  bool _submitting = false;
  bool _returningForReadback = false;
  bool _acknowledgingBlocked = false;
  bool _requestChangeDeferred = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareAndRestore());
  }

  @override
  void didUpdateWidget(covariant CommunityPmSendPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sameRequest(oldWidget.request, widget.request)) {
      return;
    }
    if (_operationLocked || _result?.submissionAttempted == true) {
      _requestChangeDeferred = true;
      return;
    }
    _switchToLatestRequest();
  }

  void _switchToLatestRequest() {
    final CommunityPmPreparedSend? previous = _prepared;
    if (previous != null) {
      _actionRepository?.discard(previous);
    }
    _generation++;
    _prepared = null;
    _result = null;
    _blocked = null;
    _terminalRequest = null;
    _error = null;
    _loading = true;
    _returningForReadback = false;
    _requestChangeDeferred = false;
    _usernameController.clear();
    _messageController.clear();
    unawaited(_prepareAndRestore());
  }

  @override
  void dispose() {
    final CommunityPmPreparedSend? prepared = _prepared;
    if (prepared != null && !_submitting) {
      _actionRepository?.discard(prepared);
    }
    _usernameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CommunityPmSendRequest displayRequest = _displayRequest;
    final bool locked = _operationLocked;
    final bool pendingReadback =
        _result?.submissionAttempted == true || _blocked != null;
    return PopScope(
      canPop: !locked && (!pendingReadback || _returningForReadback),
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && locked) {
          _showMessage('私信提交完成前不能离开此页');
        } else if (!didPop && pendingReadback) {
          _showMessage('请使用“返回并回读”刷新目标页面，勿重复提交');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            displayRequest.context == CommunityPmSendContext.compose
                ? '发送私信'
                : '回复私信',
          ),
          actions: <Widget>[
            if (_prepared != null && _result == null)
              IconButton(
                key: const ValueKey<String>('community-pm-save-draft'),
                tooltip: '保存草稿',
                onPressed: locked ? null : _saveDraft,
                icon: const Icon(Icons.save_outlined),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppLoadingView(message: '正在读取当前私信表单');
    }
    if (_error != null) {
      return AppErrorView(message: '$_error', onRetry: _prepareAndRestore);
    }
    final CommunityPmSubmissionBlockedException? blocked = _blocked;
    if (blocked != null) {
      return _buildBlocked(blocked);
    }
    final CommunityPmSubmissionResult? result = _result;
    if (result != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.warning_amber_rounded, size: 48),
              const SizedBox(height: 16),
              Text(
                result.message,
                textAlign: TextAlign.center,
                key: const ValueKey<String>('community-pm-result-message'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey<String>('community-pm-readback'),
                onPressed: _returnForReadback,
                icon: const Icon(Icons.refresh),
                label: Text(
                  _displayRequest.context == CommunityPmSendContext.conversation
                      ? '返回并回读会话'
                      : '返回并刷新私信',
                ),
              ),
            ],
          ),
        ),
      );
    }
    final CommunityPmPreparedSend? prepared = _prepared;
    if (prepared == null) {
      return const AppErrorView(message: '当前私信表单不可用');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Material(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('仅提交当前移动页声明的标准字段。提交后若响应无法确认，应用不会自动重发，请回读会话。'),
          ),
        ),
        const SizedBox(height: 16),
        if (prepared.form.acceptsUsername) ...<Widget>[
          TextField(
            key: const ValueKey<String>('community-pm-username'),
            controller: _usernameController,
            enabled: !_operationLocked,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '收件人',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ] else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(_fixedPeerLabel(prepared)),
            subtitle: const Text('收件人由当前会话 touid 固定'),
          ),
        TextField(
          key: const ValueKey<String>('community-pm-message'),
          controller: _messageController,
          enabled: !_operationLocked,
          minLines: 6,
          maxLines: 14,
          decoration: const InputDecoration(
            labelText: '私信内容',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const ValueKey<String>('community-pm-confirm-send'),
          onPressed: _submitting || _confirming ? null : _confirmAndSubmit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(_submitting ? '正在提交' : '确认发送'),
        ),
      ],
    );
  }

  Widget _buildBlocked(CommunityPmSubmissionBlockedException blocked) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, size: 48),
            const SizedBox(height: 16),
            Text(
              blocked.message,
              textAlign: TextAlign.center,
              key: const ValueKey<String>('community-pm-blocked-message'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey<String>('community-pm-blocked-readback'),
              onPressed: _returnForReadback,
              icon: const Icon(Icons.refresh),
              label: const Text('返回并回读会话'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey<String>('community-pm-blocked-acknowledge'),
              onPressed: _acknowledgingBlocked
                  ? null
                  : () => _acknowledgeBlocked(blocked),
              child: Text(_acknowledgingBlocked ? '正在解除封存' : '我已人工核对，允许重新读取'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _prepareAndRestore() async {
    final CommunityPmSendRequest request = widget.request;
    final String draftId = _draftId(request);
    final int generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _blocked = null;
      });
    }
    try {
      final CommunityPmActionRepository actionRepository = ref.read(
        communityPmActionRepositoryProvider,
      );
      final CommunityPmDraftRepository draftRepository = ref.read(
        communityPmDraftRepositoryProvider,
      );
      _actionRepository = actionRepository;
      _draftRepository = draftRepository;
      final CommunityPmPreparedSend prepared = await actionRepository.prepare(
        request,
      );
      CommunityPmDraft? draft;
      try {
        draft = await draftRepository.load(draftId);
      } on ForumSessionExpiredException {
        actionRepository.discard(prepared);
        rethrow;
      } on Object {
        // 本地草稿不可用不应阻断已验证的最新服务端表单。
      }
      if (!mounted || generation != _generation) {
        actionRepository.discard(prepared);
        return;
      }
      final bool draftMatches =
          draft != null &&
          draft.context == request.context &&
          draft.peerUserId == request.expectedPeerUserId;
      _usernameController.text = draftMatches
          ? draft.username
          : (prepared.form.initialUsername.isNotEmpty
                ? prepared.form.initialUsername
                : request.expectedPeerUsername);
      _messageController.text = draftMatches ? draft.message : '';
      setState(() {
        _prepared = prepared;
        _loading = false;
      });
    } on CommunityPmSubmissionBlockedException catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _blocked = error;
        });
      }
    } on ForumSessionExpiredException catch (error) {
      if (mounted && generation == _generation) {
        ref.read(authControllerProvider.notifier).markSessionExpired();
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _saveDraft() async {
    final CommunityPmPreparedSend? prepared = _prepared;
    if (prepared == null || _operationLocked) {
      return;
    }
    final CommunityPmSendRequest request = prepared.request;
    final String draftId = _draftId(request);
    try {
      final CommunityPmDraftRepository? repository = _draftRepository;
      if (repository == null) {
        return;
      }
      final bool hasDraftContent =
          _messageController.text.isNotEmpty ||
          (prepared.form.acceptsUsername &&
              _usernameController.text.trim().isNotEmpty);
      if (!hasDraftContent) {
        await repository.delete(draftId);
      } else {
        await repository.save(
          draftId,
          CommunityPmDraft(
            userId: prepared.userId,
            context: request.context,
            peerUserId: request.expectedPeerUserId,
            username: _usernameController.text.trim(),
            message: _messageController.text,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('私信草稿已按当前账号保存')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('草稿保存失败：$error')));
      }
    }
  }

  Future<void> _confirmAndSubmit() async {
    final CommunityPmPreparedSend? prepared = _prepared;
    if (prepared == null || _submitting || _confirming) {
      return;
    }
    final CommunityPmSendRequest submittedRequest = prepared.request;
    final String submittedMessage = _messageController.text;
    final String submittedUsername = prepared.form.acceptsUsername
        ? _usernameController.text
        : '';
    final String recipient = prepared.form.acceptsUsername
        ? submittedUsername.trim()
        : _fixedPeerLabel(prepared);
    setState(() {
      _confirming = true;
    });
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('确认发送私信？'),
            content: Text('收件人：$recipient\n\n提交只会执行一次；若响应中断，结果会保持未知且不会自动重发。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey<String>('community-pm-dialog-submit'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('发送一次'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted) {
      return;
    }
    if (!confirmed || !_isCurrentPrepared(prepared)) {
      setState(() {
        _confirming = false;
      });
      _applyDeferredRequestIfPossible();
      return;
    }
    setState(() {
      _confirming = false;
      _submitting = true;
    });
    final CommunityPmActionRepository? actionRepository = _actionRepository;
    if (actionRepository == null) {
      setState(() {
        _submitting = false;
        _error = '私信提交器不可用';
      });
      _applyDeferredRequestIfPossible();
      return;
    }
    final CommunityPmSubmissionResult result;
    try {
      result = await actionRepository.submit(
        prepared,
        message: submittedMessage,
        username: submittedUsername,
      );
    } on CommunityPmSubmissionBlockedException catch (error) {
      if (mounted && _isCurrentPrepared(prepared)) {
        setState(() {
          _submitting = false;
          _blocked = error;
        });
      }
      return;
    } on Object catch (error) {
      if (mounted && _isCurrentPrepared(prepared)) {
        setState(() {
          _submitting = false;
          _error = error;
        });
      }
      return;
    }
    if (!mounted || !_isCurrentPrepared(prepared)) {
      return;
    }
    if (result.requiresSessionRefresh) {
      ref.read(authControllerProvider.notifier).markSessionExpired();
    }
    setState(() {
      _submitting = false;
      if (result.submissionAttempted || !result.canRetryPrepared) {
        _result = result;
        _terminalRequest = submittedRequest;
      }
    });
    if (!result.submissionAttempted && _requestChangeDeferred) {
      _switchToLatestRequest();
      return;
    }
    if (!result.submissionAttempted && result.canRetryPrepared && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  bool _isCurrentPrepared(CommunityPmPreparedSend value) {
    return identical(_prepared, value);
  }

  String _fixedPeerLabel(CommunityPmPreparedSend prepared) {
    final String value = prepared.request.expectedPeerUsername.trim();
    return value.isNotEmpty ? value : '用户 ${prepared.form.peerUserId}';
  }

  String _draftId(CommunityPmSendRequest request) {
    return request.context == CommunityPmSendContext.conversation
        ? 'community-pm:conversation:${request.expectedPeerUserId}'
        : 'community-pm:compose';
  }

  bool _sameRequest(
    CommunityPmSendRequest first,
    CommunityPmSendRequest second,
  ) {
    return first.context == second.context &&
        first.entryUri == second.entryUri &&
        first.expectedPeerUserId == second.expectedPeerUserId &&
        first.expectedPeerUsername == second.expectedPeerUsername;
  }

  CommunityPmSendRequest get _displayRequest =>
      _terminalRequest ?? _prepared?.request ?? widget.request;

  bool get _operationLocked =>
      _confirming || _submitting || _acknowledgingBlocked;

  void _applyDeferredRequestIfPossible() {
    if (_requestChangeDeferred &&
        !_operationLocked &&
        _result?.submissionAttempted != true) {
      _switchToLatestRequest();
    }
  }

  Future<void> _returnForReadback() async {
    if (!mounted || _returningForReadback) {
      return;
    }
    setState(() {
      _returningForReadback = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      Navigator.of(
        context,
      ).pop(_result?.submissionAttempted == true || _blocked != null);
    }
  }

  Future<void> _acknowledgeBlocked(
    CommunityPmSubmissionBlockedException blocked,
  ) async {
    if (!mounted || _acknowledgingBlocked) {
      return;
    }
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('解除私信防重封存？'),
            content: const Text(
              '仅在你已回读会话并人工核对提交结果后继续。'
              '解除后只会重新读取表单，不会自动发送。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey<String>(
                  'community-pm-blocked-confirm-acknowledge',
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('我已人工核对，允许重新读取'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted || !identical(_blocked, blocked)) {
      return;
    }
    setState(() {
      _acknowledgingBlocked = true;
    });
    try {
      final CommunityPmActionRepository? repository = _actionRepository;
      if (repository == null) {
        throw StateError('私信提交器不可用');
      }
      await repository.acknowledgeUnresolved(blocked);
      if (!mounted || !identical(_blocked, blocked)) {
        return;
      }
      setState(() {
        _acknowledgingBlocked = false;
        _blocked = null;
      });
      await _prepareAndRestore();
    } on Object catch (error) {
      if (mounted && identical(_blocked, blocked)) {
        setState(() {
          _acknowledgingBlocked = false;
          _error = error;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
