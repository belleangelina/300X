import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/forum/application/forum_action_coordinator.dart';
import 'package:x300/features/forum/data/forum_action_repository.dart';
import 'package:x300/features/forum/data/forum_draft_repository.dart';
import 'package:x300/features/forum/data/forum_webview_policy.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';
import 'package:x300/features/forum/presentation/forum_original_page.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class ForumActionPageResult {
  const ForumActionPageResult({
    this.result,
    required this.readbackCompleted,
    this.usedOriginalPage = false,
  });

  final ForumSubmissionResult? result;
  final bool readbackCompleted;
  final bool usedOriginalPage;
}

class ForumActionPage extends ConsumerStatefulWidget {
  const ForumActionPage({
    required this.request,
    required this.title,
    this.draftId,
    super.key,
  });

  final ForumActionRequest request;
  final String title;
  final String? draftId;

  @override
  ConsumerState<ForumActionPage> createState() => _ForumActionPageState();
}

class _ForumActionPageState extends ConsumerState<ForumActionPage> {
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, List<String>> _selections = <String, List<String>>{};
  Map<String, List<String>> _pendingValues = <String, List<String>>{};

  ForumActionRepository? _repository;
  ForumActionCoordinator? _coordinator;
  ForumPreparedAction? _prepared;
  ForumUnresolvedSubmission? _unresolvedSubmission;
  ForumSubmissionResult? _terminalResult;
  String _errorMessage = '';
  String _inlineMessage = '';
  bool _loading = true;
  bool _saving = false;
  bool _confirming = false;
  bool _submitting = false;
  bool _resolvingResult = false;
  bool _checkingUnresolved = false;
  bool _acknowledgingUnresolved = false;
  bool _requestChangeDeferred = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare(loadDraft: true));
  }

  @override
  void didUpdateWidget(covariant ForumActionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sameRequest(oldWidget.request, widget.request) &&
        oldWidget.draftId == widget.draftId) {
      return;
    }
    if (_operationLocked) {
      _requestChangeDeferred = true;
      return;
    }
    _switchToLatestRequest();
  }

  void _switchToLatestRequest() {
    final ForumPreparedAction? previous = _prepared;
    if (previous != null && !_submitting) {
      _repository?.discard(previous);
    }
    _generation++;
    _disposeControllers();
    _repository = null;
    _coordinator = null;
    _prepared = null;
    _unresolvedSubmission = null;
    _terminalResult = null;
    _errorMessage = '';
    _inlineMessage = '';
    _pendingValues = <String, List<String>>{};
    _requestChangeDeferred = false;
    unawaited(_prepare(loadDraft: true));
  }

  @override
  void dispose() {
    _generation++;
    final ForumPreparedAction? prepared = _prepared;
    if (prepared != null && !_submitting) {
      _repository?.discard(prepared);
    }
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_operationLocked,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && _operationLocked) {
          _showMessage('提交与回读完成前不能离开此页');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: <Widget>[
            if (_canOpenOriginalPage)
              IconButton(
                key: const Key('forum-action-original-page'),
                tooltip: '论坛原页',
                onPressed: _operationLocked ? null : _openOriginalPage,
                icon: const Icon(Icons.open_in_browser_outlined),
              ),
            if (_canSaveDraft)
              IconButton(
                key: const Key('forum-action-save-draft'),
                tooltip: '保存草稿',
                onPressed: _saving || _operationLocked ? null : _saveDraft,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppLoadingView(message: '正在读取最新论坛表单');
    }
    if (_errorMessage.isNotEmpty || _prepared == null) {
      return Column(
        children: <Widget>[
          Expanded(
            child: AppErrorView(
              message: _errorMessage.isEmpty ? '论坛表单不可用' : _errorMessage,
              onRetry: _unresolvedSubmission == null ? _retryPrepare : null,
            ),
          ),
          if (_unresolvedSubmission != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FilledButton.icon(
                      key: const Key('forum-action-unresolved-readback'),
                      onPressed: _operationLocked ? null : _readbackUnresolved,
                      icon: _checkingUnresolved
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        _checkingUnresolved ? '正在回读' : '回读目标页面',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const Key('forum-action-unresolved-acknowledge'),
                      onPressed: _operationLocked
                          ? null
                          : _acknowledgeUnresolved,
                      child: Text(
                        _acknowledgingUnresolved
                            ? '正在解除封存'
                            : '我已人工核对，允许重新读取',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_canOpenOriginalRequest)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openOriginalPage,
                    icon: const Icon(Icons.open_in_browser_outlined),
                    label: const Text('使用论坛原页'),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    final ForumPreparedAction prepared = _prepared!;
    final DynamicForumForm form = prepared.form;
    final bool blocked = _hasBlockingField(form);
    return Column(
      children: <Widget>[
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: <Widget>[
                if (_inlineMessage.isNotEmpty)
                  _MessageBanner(message: _inlineMessage),
                for (final DynamicForumField field in form.fields)
                  _buildField(field, form),
                if (form.declaresAttachments)
                  const _MessageBanner(
                    message: '当前论坛表单包含附件入口；附件上传尚未完成移动实机契约验证，本页不会选择或提交附件。',
                    warning: true,
                  ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: _buildPrimaryButton(blocked),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton(bool blocked) {
    final ForumSubmissionResult? terminal = _terminalResult;
    if (terminal != null) {
      if (terminal.status == ForumSubmissionStatus.tokenExpired ||
          terminal.status == ForumSubmissionStatus.explicitFailure) {
        return FilledButton.icon(
          key: const Key('forum-action-refresh-form'),
          onPressed: _submitting
              ? null
              : () => _prepare(loadDraft: false, preserveValues: true),
          icon: const Icon(Icons.refresh),
          label: const Text('重新读取表单'),
        );
      }
      return FilledButton.icon(
        key: const Key('forum-action-return'),
        onPressed: () => Navigator.of(context).pop(
          ForumActionPageResult(result: terminal, readbackCompleted: false),
        ),
        icon: const Icon(Icons.arrow_back),
        label: const Text('返回并刷新目标页面'),
      );
    }
    return FilledButton.icon(
      key: const Key('forum-action-submit'),
      onPressed: blocked || _operationLocked ? null : _confirmAndSubmit,
      icon: _submitting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send_outlined),
      label: Text(_submitting ? '正在提交' : _submitLabel(widget.request.kind)),
    );
  }

  Widget _buildField(DynamicForumField field, DynamicForumForm form) {
    final Widget content = switch (field.type) {
      DynamicForumFieldType.text => _textField(field),
      DynamicForumFieldType.multiline => _multilineField(field),
      DynamicForumFieldType.select => _choiceField(field),
      DynamicForumFieldType.checkbox => _checkboxField(field),
      DynamicForumFieldType.radio => _radioField(field),
      DynamicForumFieldType.verification => _verificationField(field, form),
      DynamicForumFieldType.file => _unsupportedField(
          field,
          '附件字段暂不可用',
        ),
      DynamicForumFieldType.unsupported => _unsupportedField(
          field,
          '论坛返回了尚未支持的动态字段',
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: content,
    );
  }

  Widget _textField(DynamicForumField field) {
    return TextFormField(
      key: ValueKey<String>('forum-action-${field.name}'),
      controller: _controllers[field.name],
      readOnly: _operationLocked,
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
      ),
      maxLength: field.maximumLength,
      validator: (String? value) => _validateText(field, value ?? ''),
    );
  }

  Widget _multilineField(DynamicForumField field) {
    final TextEditingController controller = _controllers[field.name]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_isMessageField(field))
          _BbCodeToolbar(
            controller: controller,
            enabled: !_operationLocked,
          ),
        TextFormField(
          key: ValueKey<String>('forum-action-${field.name}'),
          controller: controller,
          readOnly: _operationLocked,
          decoration: InputDecoration(
            labelText: field.label,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
          minLines: _isMessageField(field) ? 8 : 3,
          maxLines: null,
          maxLength: field.maximumLength,
          validator: (String? value) => _validateText(field, value ?? ''),
        ),
      ],
    );
  }

  Widget _choiceField(DynamicForumField field) {
    if (field.multiple) {
      return _checkboxField(field);
    }
    final List<String> selected = _selections[field.name] ?? <String>[];
    final Set<String> options = field.options
        .map((DynamicForumFieldOption option) => option.value)
        .toSet();
    final String? value = selected.length == 1 && options.contains(selected.single)
        ? selected.single
        : null;
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('forum-action-${field.name}'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<String>>[
        for (final DynamicForumFieldOption option in field.options)
          DropdownMenuItem<String>(
            value: option.value,
            child: Text(option.label),
          ),
      ],
      onChanged: _operationLocked
          ? null
          : (String? next) {
              setState(() {
                _selections[field.name] = next == null
                    ? <String>[]
                    : <String>[next];
              });
            },
      validator: (String? next) =>
          field.isRequired && (next == null || next.trim().isEmpty)
          ? '${field.label}不能为空'
          : null,
    );
  }

  Widget _checkboxField(DynamicForumField field) {
    final Set<String> selected = (_selections[field.name] ?? <String>[]).toSet();
    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
      ),
      child: Column(
        children: <Widget>[
          for (final DynamicForumFieldOption option in field.options)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(option.label),
              value: selected.contains(option.value),
              onChanged: _operationLocked
                  ? null
                  : (bool? checked) {
                      setState(() {
                        final List<String> values = _selections.putIfAbsent(
                          field.name,
                          () => <String>[],
                        );
                        if (checked ?? false) {
                          if (!values.contains(option.value)) {
                            values.add(option.value);
                          }
                        } else {
                          values.remove(option.value);
                        }
                      });
                    },
            ),
          if (field.options.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('论坛未返回可选择项'),
            ),
        ],
      ),
    );
  }

  Widget _radioField(DynamicForumField field) {
    final String? selected = (_selections[field.name] ?? <String>[]).firstOrNull;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
      ),
      child: RadioGroup<String>(
        groupValue: selected,
        onChanged: _operationLocked
            ? (String? _) {}
            : (String? next) {
                setState(() {
                  _selections[field.name] = next == null
                      ? <String>[]
                      : <String>[next];
                });
              },
        child: Column(
          children: <Widget>[
            for (final DynamicForumFieldOption option in field.options)
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(option.label),
                value: option.value,
                enabled: !_operationLocked,
              ),
          ],
        ),
      ),
    );
  }

  Widget _verificationField(
    DynamicForumField field,
    DynamicForumForm form,
  ) {
    final ForumCaptchaDescriptor? captcha = form.captcha;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (captcha != null && captcha.fieldName == field.name) ...<Widget>[
          _ForumCaptchaImage(
            uri: captcha.imageUri,
            referer: form.sourceUri.toString(),
            userId: _prepared!.userId,
            height: 72,
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          key: ValueKey<String>('forum-action-${field.name}'),
          controller: _controllers[field.name],
          readOnly: _operationLocked,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: field.label,
            border: const OutlineInputBorder(),
          ),
          validator: (String? value) => _validateText(field, value ?? ''),
        ),
      ],
    );
  }

  Widget _unsupportedField(DynamicForumField field, String message) {
    return _MessageBanner(
      message: '${field.label}：$message${field.isRequired ? '，因此当前不能提交' : ''}',
      warning: true,
    );
  }

  Future<void> _prepare({
    required bool loadDraft,
    bool preserveValues = false,
  }) async {
    final int generation = ++_generation;
    if (preserveValues) {
      final Map<String, List<String>> current = _draftValues();
      if (current.isNotEmpty) {
        _pendingValues = current;
      }
    }
    final Map<String, List<String>> preserved = preserveValues
        ? _pendingValues
        : const <String, List<String>>{};
    final ForumPreparedAction? oldPrepared = _prepared;
    if (oldPrepared != null && !_submitting) {
      _repository?.discard(oldPrepared);
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = '';
        _inlineMessage = '';
        _terminalResult = null;
        _unresolvedSubmission = null;
        _submitting = false;
        _resolvingResult = false;
      });
    }

    final ForumActionRepository repository = ref.read(
      forumActionRepositoryProvider,
    );
    final ForumActionCoordinator coordinator = ForumActionCoordinator(
      repository,
    );
    final ForumActionState state = await coordinator.prepare(widget.request);
    if (!mounted || generation != _generation) {
      final ForumPreparedAction? abandoned = state.prepared;
      if (abandoned != null) {
        repository.discard(abandoned);
      }
      return;
    }
    if (state.phase != ForumActionPhase.ready || state.prepared == null) {
      if (state.sessionExpired) {
        ref.read(authControllerProvider.notifier).markSessionExpired();
      }
      setState(() {
        _repository = repository;
        _coordinator = coordinator;
        _prepared = null;
        _unresolvedSubmission = state.unresolvedSubmission;
        _loading = false;
        _errorMessage = state.errorMessage.isEmpty
            ? '论坛表单不可用'
            : state.errorMessage;
      });
      return;
    }
    final String expectedDraftContext = widget.draftId?.trim() ?? '';
    if (expectedDraftContext != state.prepared!.draftContext) {
      repository.discard(state.prepared!);
      setState(() {
        _repository = repository;
        _coordinator = coordinator;
        _prepared = null;
        _loading = false;
        _errorMessage = '草稿上下文与论坛操作目标不一致，当前不会恢复或提交草稿';
      });
      return;
    }

    Map<String, List<String>> restored = preserved;
    String draftMessage = '';
    if (loadDraft && widget.draftId != null) {
      try {
        final ForumActionDraft? draft = await ref
            .read(forumDraftRepositoryProvider)
            .load(widget.draftId!);
        if (!mounted || generation != _generation) {
          repository.discard(state.prepared!);
          return;
        }
        if (draft != null && _matchesDraft(draft, state.prepared!)) {
          restored = draft.values;
          draftMessage = '已恢复本账号草稿；提交前已重新读取最新论坛表单。';
        }
      } on Object {
        draftMessage = '草稿读取失败，已使用论坛当前表单内容。';
      }
    }

    _disposeControllers();
    _initializeValues(state.prepared!.form, restored);
    setState(() {
      _formKey = GlobalKey<FormState>();
      _pendingValues = <String, List<String>>{};
      _repository = repository;
      _coordinator = coordinator;
      _prepared = state.prepared;
      _unresolvedSubmission = null;
      _loading = false;
      _errorMessage = '';
      _inlineMessage = draftMessage;
    });
  }

  void _initializeValues(
    DynamicForumForm form,
    Map<String, List<String>> restored,
  ) {
    for (final DynamicForumField field in form.fields) {
      final List<String> initial = field.type == DynamicForumFieldType.verification
          ? const <String>[]
          : restored[field.name] ?? field.initialValues;
      switch (field.type) {
        case DynamicForumFieldType.text:
        case DynamicForumFieldType.multiline:
        case DynamicForumFieldType.verification:
          _controllers[field.name] = TextEditingController(
            text: initial.firstOrNull ?? '',
          );
        case DynamicForumFieldType.select:
        case DynamicForumFieldType.checkbox:
        case DynamicForumFieldType.radio:
          final Set<String> allowed = field.options
              .map((DynamicForumFieldOption option) => option.value)
              .toSet();
          _selections[field.name] = initial
              .where(allowed.contains)
              .toList(growable: true);
        case DynamicForumFieldType.file:
        case DynamicForumFieldType.unsupported:
          _selections[field.name] = <String>[];
      }
    }
  }

  Future<void> _saveDraft() async {
    final ForumPreparedAction? prepared = _prepared;
    final String? draftId = widget.draftId;
    if (prepared == null || draftId == null || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(forumDraftRepositoryProvider).save(
            draftId,
            ForumActionDraft(
              userId: prepared.userId,
              kind: prepared.request.kind,
              target: prepared.request.target,
              values: _draftValues(),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      if (mounted) {
        _showMessage('草稿已保存');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('草稿保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _confirmAndSubmit() async {
    final ForumActionCoordinator? coordinator = _coordinator;
    final ForumPreparedAction? prepared = _prepared;
    if (coordinator == null || prepared == null || _operationLocked) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final String? selectionError = _validateSelections();
    if (selectionError != null) {
      setState(() => _inlineMessage = selectionError);
      return;
    }
    final int generation = _generation;
    final Map<String, Object?> submittedValues =
        Map<String, Object?>.unmodifiable(_submissionValues());
    final ForumActionRepository? submittedRepository = _repository;
    if (submittedRepository == null) {
      return;
    }
    final String? submittedDraftId = widget.draftId;
    final ForumDraftRepository? submittedDraftRepository =
        submittedDraftId == null
        ? null
        : ref.read(forumDraftRepositoryProvider);
    setState(() => _confirming = true);
    final bool confirmed;
    try {
      confirmed = await _showConfirmation();
    } on Object {
      if (mounted) {
        setState(() => _confirming = false);
        _applyDeferredRequestIfPossible();
      }
      rethrow;
    }
    if (!confirmed || !mounted || generation != _generation) {
      if (mounted) {
        setState(() => _confirming = false);
        _applyDeferredRequestIfPossible();
      }
      return;
    }
    setState(() {
      _confirming = false;
      _submitting = true;
      _inlineMessage = '';
    });
    final ForumActionState state = await coordinator.confirm(submittedValues);
    if (!mounted || generation != _generation) {
      return;
    }
    if (state.sessionExpired) {
      ref.read(authControllerProvider.notifier).markSessionExpired();
    }
    final ForumSubmissionResult? result = state.result;
    if (result == null) {
      if (state.unresolvedSubmission != null) {
        _pendingValues = _draftValues();
      }
      setState(() {
        _submitting = false;
        _prepared = null;
        _coordinator = null;
        _unresolvedSubmission = state.unresolvedSubmission;
        _inlineMessage = '';
        _errorMessage = state.errorMessage.isEmpty
            ? '论坛操作失败；若提交已开始，请先回读目标页面，勿重复提交。'
            : state.errorMessage;
      });
      _applyDeferredRequestIfPossible();
      return;
    }
    if (result.canRetryPrepared) {
      setState(() {
        _submitting = false;
        _inlineMessage = result.message;
      });
      _applyDeferredRequestIfPossible();
      return;
    }
    setState(() {
      _submitting = false;
      _terminalResult = result;
      _inlineMessage = result.message;
      _resolvingResult = result.requiresReadback;
    });
    if (result.status == ForumSubmissionStatus.success ||
        result.status == ForumSubmissionStatus.resultUnknown) {
      await _readbackAndFinish(
        result,
        submittedPrepared: prepared,
        submittedRepository: submittedRepository,
        submittedDraftId: submittedDraftId,
        submittedDraftRepository: submittedDraftRepository,
      );
    } else {
      _applyDeferredRequestIfPossible();
    }
  }

  Future<void> _readbackAndFinish(
    ForumSubmissionResult result, {
    required ForumPreparedAction submittedPrepared,
    required ForumActionRepository submittedRepository,
    String? submittedDraftId,
    ForumDraftRepository? submittedDraftRepository,
  }) async {
    final int submittedUserId = submittedPrepared.userId;
    bool readbackCompleted = false;
    try {
      await submittedRepository.readback(submittedPrepared.readback);
      readbackCompleted = true;
    } on ForumSessionExpiredException {
      ref.read(authControllerProvider.notifier).markSessionExpired();
      readbackCompleted = false;
    } on Object {
      readbackCompleted = false;
    }
    if (!mounted) {
      return;
    }
    if (result.status == ForumSubmissionStatus.success &&
        result.userId == submittedUserId &&
        submittedDraftId != null &&
        submittedDraftRepository != null) {
      try {
        await submittedDraftRepository.delete(
          submittedDraftId,
          userId: submittedUserId,
        );
      } on Object {
        // 服务端已经明确成功，草稿清理失败不能改变提交结果。
      }
    }
    if (!mounted) {
      return;
    }
    final bool leave = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => AlertDialog(
            title: Text(
              result.status == ForumSubmissionStatus.success
                  ? '论坛已确认成功'
                  : '提交结果未知',
            ),
            content: Text(
              result.status == ForumSubmissionStatus.success
                  ? '${result.message}\n${readbackCompleted ? '已回读目标页面。' : '目标页面回读失败，返回后请手动刷新。'}'
                  : '${result.message}\n${readbackCompleted ? '已读取目标页面，但无法可靠判定本次写入结果。' : '目标页面暂时无法回读。'}\n请勿直接重复提交。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('返回并刷新'),
              ),
            ],
          ),
        ) ??
        true;
    if (!mounted || !leave) {
      return;
    }
    setState(() => _resolvingResult = false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(
      ForumActionPageResult(
        result: result,
        readbackCompleted: readbackCompleted,
      ),
    );
  }

  Future<bool> _showConfirmation() async {
    final ForumActionKind kind = widget.request.kind;
    final bool destructive = const <ForumActionKind>{
      ForumActionKind.deletePost,
      ForumActionKind.report,
      ForumActionKind.removeFavorite,
    }.contains(kind);
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(destructive ? '确认执行不可撤销操作？' : '确认提交到论坛？'),
            content: Text(
              destructive
                  ? '该操作可能无法撤销。页面只会提交一次；响应丢失时不会自动重发。'
                  : '将使用刚刚读取的移动表单提交一次。响应丢失时不会自动重发。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('forum-action-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认提交'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Map<String, Object?> _submissionValues() {
    final DynamicForumForm form = _prepared!.form;
    return <String, Object?>{
      for (final DynamicForumField field in form.fields)
        field.name: switch (field.type) {
          DynamicForumFieldType.text ||
          DynamicForumFieldType.multiline ||
          DynamicForumFieldType.verification =>
            _controllers[field.name]?.text ?? '',
          DynamicForumFieldType.select ||
          DynamicForumFieldType.checkbox ||
          DynamicForumFieldType.radio =>
            List<String>.unmodifiable(
              _selections[field.name] ?? const <String>[],
            ),
          DynamicForumFieldType.file || DynamicForumFieldType.unsupported =>
            null,
        },
    };
  }

  Map<String, List<String>> _draftValues() {
    final DynamicForumForm? form = _prepared?.form;
    if (form == null) {
      return const <String, List<String>>{};
    }
    final Map<String, List<String>> result = <String, List<String>>{};
    for (final DynamicForumField field in form.fields) {
      switch (field.type) {
        case DynamicForumFieldType.text:
        case DynamicForumFieldType.multiline:
          result[field.name] = <String>[
            _controllers[field.name]?.text ?? '',
          ];
        case DynamicForumFieldType.select:
        case DynamicForumFieldType.checkbox:
        case DynamicForumFieldType.radio:
          result[field.name] = List<String>.from(
            _selections[field.name] ?? const <String>[],
          );
        case DynamicForumFieldType.verification:
        case DynamicForumFieldType.file:
        case DynamicForumFieldType.unsupported:
          break;
      }
    }
    return result;
  }

  bool _matchesDraft(
    ForumActionDraft draft,
    ForumPreparedAction prepared,
  ) {
    final ForumActionTarget expected = prepared.request.target;
    final ForumActionTarget actual = draft.target;
    return draft.userId == prepared.userId &&
        draft.kind == prepared.request.kind &&
        actual.boardId == expected.boardId &&
        actual.threadId == expected.threadId &&
        actual.postId == expected.postId;
  }

  bool _hasBlockingField(DynamicForumForm form) {
    return form.fields.any(
      (DynamicForumField field) =>
          field.type == DynamicForumFieldType.unsupported ||
          (field.type == DynamicForumFieldType.file && field.isRequired),
    );
  }

  bool get _canSaveDraft {
    if (widget.draftId == null || _prepared == null) {
      return false;
    }
    return _prepared!.form.fields.any(
      (DynamicForumField field) =>
          field.type == DynamicForumFieldType.text ||
          field.type == DynamicForumFieldType.multiline,
    );
  }

  bool get _operationLocked =>
      _confirming ||
      _submitting ||
      _resolvingResult ||
      _checkingUnresolved ||
      _acknowledgingUnresolved;

  void _applyDeferredRequestIfPossible() {
    if (_requestChangeDeferred && !_operationLocked) {
      _switchToLatestRequest();
    }
  }

  void _retryPrepare() {
    unawaited(_prepare(
      loadDraft: _pendingValues.isEmpty,
      preserveValues: _pendingValues.isNotEmpty,
    ));
  }

  bool get _canOpenOriginalPage =>
      forumOriginalPageSupported &&
      _prepared != null &&
      const ForumWebViewPolicy().isRegisteredInitialUri(
        _prepared!.form.sourceUri,
      );

  bool get _canOpenOriginalRequest =>
      _unresolvedSubmission == null &&
      forumOriginalPageSupported &&
      const ForumWebViewPolicy().isRegisteredInitialUri(widget.request.entryUri);

  Future<void> _readbackUnresolved() async {
    final ForumActionRepository? repository = _repository;
    final ForumUnresolvedSubmission? submission = _unresolvedSubmission;
    if (repository == null || submission == null || _operationLocked) {
      return;
    }
    setState(() => _checkingUnresolved = true);
    try {
      await repository.readbackUnresolved(submission);
      if (mounted && identical(_unresolvedSubmission, submission)) {
        setState(() {
          _errorMessage =
              '已完成目标资源回读。请根据目标页状态人工核对本次操作是否生效；确认后再显式解除封存。';
        });
      }
    } on ForumSessionExpiredException {
      ref.read(authControllerProvider.notifier).markSessionExpired();
      if (mounted) {
        setState(() => _errorMessage = '登录状态已失效，无法回读目标资源');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorMessage = '目标资源回读失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _checkingUnresolved = false);
        _applyDeferredRequestIfPossible();
      }
    }
  }

  Future<void> _acknowledgeUnresolved() async {
    final ForumActionRepository? repository = _repository;
    final ForumUnresolvedSubmission? submission = _unresolvedSubmission;
    if (repository == null || submission == null || _operationLocked) {
      return;
    }
    setState(() => _acknowledgingUnresolved = true);
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('确认解除防重复封存？'),
            content: const Text(
              '只有在你已人工核对目标资源、确认允许再次操作时才能继续。解除后只会重新读取表单，仍需再次确认才会提交。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('forum-action-unresolved-confirm-acknowledge'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认已核对'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted || !identical(_unresolvedSubmission, submission)) {
      if (mounted) {
        setState(() => _acknowledgingUnresolved = false);
        _applyDeferredRequestIfPossible();
      }
      return;
    }
    try {
      await repository.acknowledgeUnresolved(submission);
      if (!mounted || !identical(_unresolvedSubmission, submission)) {
        return;
      }
      setState(() {
        _acknowledgingUnresolved = false;
        _unresolvedSubmission = null;
      });
      if (_requestChangeDeferred) {
        _applyDeferredRequestIfPossible();
        return;
      }
      await _prepare(
        loadDraft: _pendingValues.isEmpty,
        preserveValues: _pendingValues.isNotEmpty,
      );
    } on ForumSessionExpiredException {
      ref.read(authControllerProvider.notifier).markSessionExpired();
      if (mounted) {
        setState(() {
          _acknowledgingUnresolved = false;
          _errorMessage = '登录状态已失效，未解除提交封存';
        });
        _applyDeferredRequestIfPossible();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _acknowledgingUnresolved = false;
          _errorMessage = '解除提交封存失败：$error';
        });
        _applyDeferredRequestIfPossible();
      }
    }
  }

  Future<void> _openOriginalPage() async {
    if (_operationLocked || !_canOpenOriginalRequest) {
      return;
    }
    final bool leave = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('切换到论坛原页？'),
            content: const Text('未保存的原生表单输入不会带入论坛原页。返回后将关闭本页并刷新目标内容。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('打开论坛原页'),
              ),
            ],
          ),
        ) ??
        false;
    if (!leave || !mounted) {
      return;
    }
    final Uri initialUri = _prepared?.form.sourceUri ?? widget.request.entryUri;
    final bool? finished = await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ForumOriginalPage(
          initialUri: initialUri,
          label: '${widget.title} · 论坛原页',
        ),
      ),
    );
    if (!mounted || finished != true) {
      return;
    }
    Navigator.of(context).pop(
      const ForumActionPageResult(
        readbackCompleted: false,
        usedOriginalPage: true,
      ),
    );
  }

  String? _validateText(DynamicForumField field, String value) {
    final bool empty = value.trim().isEmpty;
    if ((field.isRequired ||
            field.type == DynamicForumFieldType.verification) &&
        empty) {
      return '${field.label}不能为空';
    }
    if (empty) {
      return null;
    }
    if (field.minimumLength != null && value.length < field.minimumLength!) {
      return '${field.label}长度不足';
    }
    if (field.maximumLength != null && value.length > field.maximumLength!) {
      return '${field.label}超过长度限制';
    }
    if (value.isNotEmpty &&
        (field.minimumValue != null || field.maximumValue != null)) {
      final num? number = num.tryParse(value);
      if (number == null) {
        return '${field.label}必须是数字';
      }
      if (field.minimumValue != null && number < field.minimumValue!) {
        return '${field.label}低于论坛允许范围';
      }
      if (field.maximumValue != null && number > field.maximumValue!) {
        return '${field.label}超过论坛允许范围';
      }
    }
    return null;
  }

  String? _validateSelections() {
    final DynamicForumForm? form = _prepared?.form;
    if (form == null) {
      return '论坛表单不可用，请重新读取';
    }
    for (final DynamicForumField field in form.fields) {
      if (!field.isRequired ||
          (field.type != DynamicForumFieldType.checkbox &&
              field.type != DynamicForumFieldType.radio &&
              !(field.type == DynamicForumFieldType.select &&
                  field.multiple))) {
        continue;
      }
      final List<String> selected = _selections[field.name] ?? const <String>[];
      if (selected.every((String value) => value.trim().isEmpty)) {
        return '${field.label}不能为空';
      }
    }
    return null;
  }

  bool _isMessageField(DynamicForumField field) {
    final String name = field.name.toLowerCase();
    return name == 'message' || name.endsWith('[message]');
  }

  bool _sameRequest(ForumActionRequest left, ForumActionRequest right) {
    final ForumActionTarget leftTarget = left.target;
    final ForumActionTarget rightTarget = right.target;
    return left.kind == right.kind &&
        left.entryUri == right.entryUri &&
        left.readbackUri == right.readbackUri &&
        leftTarget.boardId == rightTarget.boardId &&
        leftTarget.threadId == rightTarget.threadId &&
        leftTarget.postId == rightTarget.postId &&
        leftTarget.favoriteId == rightTarget.favoriteId;
  }

  String _submitLabel(ForumActionKind kind) {
    return switch (kind) {
      ForumActionKind.newThread => '确认发主题',
      ForumActionKind.reply || ForumActionKind.quoteReply => '确认回复',
      ForumActionKind.editPost => '确认保存编辑',
      ForumActionKind.deletePost => '确认删除',
      ForumActionKind.vote => '确认投票',
      ForumActionKind.comment => '确认点评',
      ForumActionKind.rate => '确认评分',
      ForumActionKind.report => '确认举报',
      ForumActionKind.favoriteThread || ForumActionKind.favoriteBoard =>
        '确认收藏',
      ForumActionKind.removeFavorite => '确认取消收藏',
      ForumActionKind.shareThread => '确认分享',
    };
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _disposeControllers() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _selections.clear();
  }
}

class _BbCodeToolbar extends StatelessWidget {
  const _BbCodeToolbar({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: <Widget>[
          _button('粗体', 'b'),
          _button('引用', 'quote'),
          _button('代码', 'code'),
          _button('链接', 'url'),
          _button('图片', 'img'),
        ],
      ),
    );
  }

  Widget _button(String label, String tag) {
    return OutlinedButton(
      key: ValueKey<String>('forum-bbcode-$tag'),
      onPressed: enabled ? () => _wrapSelection(tag) : null,
      child: Text(label),
    );
  }

  void _wrapSelection(String tag) {
    final TextEditingValue value = controller.value;
    final TextSelection selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final int start = selection.start.clamp(0, value.text.length);
    final int end = selection.end.clamp(0, value.text.length);
    final String selected = value.text.substring(start, end);
    final String opening = '[$tag]';
    final String closing = '[/$tag]';
    final String replacement = '$opening$selected$closing';
    controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(
        offset: start + opening.length + selected.length,
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, this.warning = false});

  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning ? colors.errorContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: warning
              ? colors.onErrorContainer
              : colors.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _ForumCaptchaImage extends ConsumerStatefulWidget {
  const _ForumCaptchaImage({
    required this.uri,
    required this.referer,
    required this.userId,
    required this.height,
  });

  final Uri uri;
  final String referer;
  final int userId;
  final double height;

  @override
  ConsumerState<_ForumCaptchaImage> createState() =>
      _ForumCaptchaImageState();
}

class _ForumCaptchaImageState extends ConsumerState<_ForumCaptchaImage> {
  Future<Uint8List>? _future;

  @override
  void didUpdateWidget(covariant _ForumCaptchaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri || oldWidget.userId != widget.userId) {
      _future = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _future ??= ref.read(forumClientProvider).withActiveAccount<Uint8List>(
          widget.userId,
          () => ref.read(forumClientProvider).getBytes(
                widget.uri,
                referer: widget.referer,
              ),
        );
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return Image.memory(
            snapshot.data!,
            height: widget.height,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          );
        }
        if (snapshot.hasError) {
          return SizedBox(
            height: widget.height,
            child: Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _future = null),
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载验证码'),
              ),
            ),
          );
        }
        return SizedBox(
          height: widget.height,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }
}
