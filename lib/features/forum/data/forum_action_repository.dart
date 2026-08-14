import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/forum/data/dynamic_forum_form_parser.dart';
import 'package:x300/features/forum/data/forum_action_contract.dart';
import 'package:x300/features/forum/data/forum_action_response_parser.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

final Provider<ForumActionRepository> forumActionRepositoryProvider =
    Provider<ForumActionRepository>(
      (Ref ref) => ForumActionRepository(
        ref.watch(forumClientProvider),
        ref.watch(authControllerProvider).value?.userId ?? 0,
        ForumSubmissionTombstoneRepository(
          ref.watch(appDatabaseProvider),
        ),
      ),
    );

class ForumActionRepository {
  ForumActionRepository(
    this._client,
    this._userId,
    this.tombstones, {
    this.formParser = const DynamicForumFormParser(),
    this.responseParser = const ForumActionResponseParser(),
    this.contract = const ForumActionContract(),
    this.authParser = const AuthPageParser(),
  });

  final ForumClient _client;
  final int _userId;
  final ForumSubmissionTombstoneRepository tombstones;
  final DynamicForumFormParser formParser;
  final ForumActionResponseParser responseParser;
  final ForumActionContract contract;
  final AuthPageParser authParser;
  final Random _random = Random.secure();
  final Map<String, ForumPreparedAction> _unused =
      <String, ForumPreparedAction>{};
  int _sequence = 0;

  Future<ForumPreparedAction> prepare(ForumActionRequest request) {
    return _withActiveAccount(() async {
      contract.validateEntry(request, request.entryUri);
      contract.validateAccountUri(request.entryUri, _userId);
      final ForumReadbackDescriptor readback = _readback(request);
      contract.validateReadbackUri(readback, readback.uri);
      contract.validateAccountUri(readback.uri, _userId);
      final String draftContext = _draftContext(request);
      final ForumUnresolvedSubmission? unresolved = await tombstones.find(
        userId: _userId,
        request: request,
        readback: readback,
        draftContext: draftContext,
      );
      if (unresolved != null) {
        throw ForumSubmissionBlockedException(unresolved);
      }
      final Response<String> response = await _client.getText(request.entryUri);
      contract.validateEntry(request, response.realUri);
      contract.validateAccountUri(response.realUri, _userId);
      final DynamicForumForm form = formParser.parse(
        response.data ?? '',
        response.realUri,
        expectedUserId: _userId,
        request: request,
      );
      final String token = _newToken();
      final ForumPreparedAction prepared = ForumPreparedAction(
        token: token,
        userId: _userId,
        request: request,
        form: form,
        readback: readback,
        draftContext: draftContext,
      );
      _unused[token] = prepared;
      return prepared;
    });
  }

  Future<ForumSubmissionResult> submit(
    ForumPreparedAction prepared,
    Map<String, Object?> values, {
    List<ForumAttachmentSelection> attachments =
        const <ForumAttachmentSelection>[],
  }) {
    final ForumPreparedAction? registered = _unused[prepared.token];
    if (!identical(registered, prepared) || prepared.userId != _userId) {
      return Future<ForumSubmissionResult>.value(
        _result(
          prepared,
          ForumSubmissionStatus.explicitFailure,
          '该操作确认已使用或不属于当前会话，请重新读取表单',
        ),
      );
    }
    return _withActiveAccount(() async {
      contract.validateEntry(prepared.request, prepared.form.sourceUri);
      contract.validateAccountUri(prepared.form.sourceUri, _userId);
      contract.validateAccountFields(prepared.form.hiddenFields, _userId);
      contract.validateHiddenFields(
        prepared.request,
        prepared.form.hiddenFields,
      );
      contract.validateSubmitFields(
        prepared.request,
        prepared.form.submitFields,
      );
      contract.validateFormAction(
        prepared.request,
        prepared.form.actionUri,
        prepared.form.hiddenFields,
      );
      contract.validateAccountUri(prepared.form.actionUri, _userId);
      final _Payload payload = _buildPayload(prepared, values, attachments);
      if (payload.failure != null) {
        return payload.failure!;
      }
      if (!_consume(prepared)) {
        return _result(
          prepared,
          ForumSubmissionStatus.explicitFailure,
          '该操作确认已使用，请重新读取表单',
        );
      }
      final String? attemptId = await tombstones.claimAttempted(
        userId: _userId,
        prepared: prepared,
      );
      if (attemptId == null) {
        final ForumUnresolvedSubmission? unresolved = await tombstones.find(
          userId: _userId,
          request: prepared.request,
          readback: prepared.readback,
          draftContext: prepared.draftContext,
        );
        if (unresolved != null) {
          throw ForumSubmissionBlockedException(unresolved);
        }
        throw StateError('论坛提交封存冲突');
      }
      try {
        final Response<String> response = await _client.postForm(
          prepared.form.actionUri,
          fields: payload.fields!,
          referer: prepared.form.sourceUri.toString(),
        );
        contract.validateSubmissionFinal(prepared, response.realUri);
        _validateIdentity(response.data ?? '', _userId);
        final ForumSubmissionResult result = responseParser.parse(
          response.data ?? '',
          response.realUri,
          prepared,
        );
        if (result.status == ForumSubmissionStatus.success ||
            result.status == ForumSubmissionStatus.explicitFailure ||
            result.status == ForumSubmissionStatus.permissionDenied ||
            result.status == ForumSubmissionStatus.tokenExpired) {
          await tombstones.resolveTrustedOutcome(
            userId: _userId,
            prepared: prepared,
            attemptId: attemptId,
            deleteDraft: result.status == ForumSubmissionStatus.success,
          );
        }
        return result;
      } on ForumSessionExpiredException {
        return _result(
          prepared,
          ForumSubmissionStatus.resultUnknown,
          '提交已发出但账号身份无法确认，结果未知；请重新登录并先回读目标资源，勿重复提交',
          submissionAttempted: true,
          requiresSessionRefresh: true,
        );
      } on Object {
        return _result(
          prepared,
          ForumSubmissionStatus.resultUnknown,
          '提交已发出但响应无法安全确认，结果未知；请先回读目标资源，勿重复提交',
          submissionAttempted: true,
        );
      }
    });
  }

  Future<ForumReadbackReceipt> readback(ForumReadbackDescriptor descriptor) {
    return _withActiveAccount(() async {
      contract.validateReadbackUri(descriptor, descriptor.uri);
      contract.validateAccountUri(descriptor.uri, _userId);
      final Response<String> response = await _client.getText(descriptor.uri);
      contract.validateReadbackUri(descriptor, response.realUri);
      contract.validateAccountUri(response.realUri, _userId);
      _validateIdentity(response.data ?? '', _userId);
      return ForumReadbackReceipt(
        userId: _userId,
        descriptor: descriptor,
        sourceUri: response.realUri,
        contentDigest: sha256
            .convert(utf8.encode(response.data ?? ''))
            .toString(),
        receivedAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<ForumReadbackReceipt> readbackUnresolved(
    ForumUnresolvedSubmission submission,
  ) {
    _requireUnresolvedOwner(submission);
    return readback(submission.readback);
  }

  Future<void> acknowledgeUnresolved(
    ForumUnresolvedSubmission submission,
  ) {
    _requireUnresolvedOwner(submission);
    return _withActiveAccount(() async {
      contract.validateEntry(submission.request, submission.request.entryUri);
      contract.validateAccountUri(submission.request.entryUri, _userId);
      contract.validateReadbackUri(submission.readback, submission.readback.uri);
      contract.validateAccountUri(submission.readback.uri, _userId);
      if (!await tombstones.acknowledge(submission)) {
        throw const ForumActionSecurityException('待核对的提交封存记录已变化，请重新进入操作页');
      }
    });
  }

  void discard(ForumPreparedAction prepared) {
    final ForumPreparedAction? registered = _unused[prepared.token];
    if (identical(registered, prepared)) {
      _unused.remove(prepared.token);
    }
  }

  bool _consume(ForumPreparedAction prepared) {
    final ForumPreparedAction? registered = _unused[prepared.token];
    if (!identical(registered, prepared)) {
      return false;
    }
    _unused.remove(prepared.token);
    return true;
  }

  _Payload _buildPayload(
    ForumPreparedAction prepared,
    Map<String, Object?> supplied,
    List<ForumAttachmentSelection> attachments,
  ) {
    final DynamicForumForm form = prepared.form;
    if (form.formHash.isEmpty) {
      return _Payload.failure(
        _result(
          prepared,
          ForumSubmissionStatus.tokenExpired,
          '操作表单已过期，请重新读取表单',
          canRetryPrepared: true,
        ),
      );
    }
    if (attachments.isNotEmpty) {
      return _Payload.failure(
        _result(
          prepared,
          ForumSubmissionStatus.explicitFailure,
          '附件上传契约尚未完成真实移动端验证，当前不会提交附件',
          canRetryPrepared: true,
        ),
      );
    }
    final Set<String> visibleNames = form.fields
        .map((DynamicForumField field) => field.name)
        .toSet();
    final Set<String> fileNames = form.fields
        .where(
          (DynamicForumField field) =>
              field.type == DynamicForumFieldType.file,
        )
        .map((DynamicForumField field) => field.name)
        .toSet();
    if (supplied.keys.any(fileNames.contains)) {
      return _Payload.failure(
        _result(
          prepared,
          ForumSubmissionStatus.explicitFailure,
          '附件上传契约尚未完成真实移动端验证，当前不会提交附件',
          canRetryPrepared: true,
        ),
      );
    }
    contract.validateUserFieldNames(visibleNames);
    for (final String name in supplied.keys) {
      if (!visibleNames.contains(name)) {
        return _Payload.failure(
          _result(
            prepared,
            ForumSubmissionStatus.explicitFailure,
            '提交内容包含论坛表单未声明的字段：$name',
            canRetryPrepared: true,
          ),
        );
      }
    }

    final Map<String, dynamic> fields = <String, dynamic>{};
    for (final MapEntry<String, List<String>> entry
        in form.hiddenFields.entries) {
      fields[entry.key] = _transportValue(entry.value);
    }
    for (final DynamicForumField field in form.fields) {
      if (field.type == DynamicForumFieldType.unsupported) {
        return _Payload.failure(
          _result(
            prepared,
            ForumSubmissionStatus.explicitFailure,
            '论坛表单包含尚未支持的字段：${field.label}',
            canRetryPrepared: true,
          ),
        );
      }
      if (field.type == DynamicForumFieldType.file) {
        if (field.isRequired) {
          return _Payload.failure(
            _result(
              prepared,
              ForumSubmissionStatus.explicitFailure,
              '论坛要求上传附件，但附件契约尚未完成真实验证',
              canRetryPrepared: true,
            ),
          );
        }
        continue;
      }
      final List<String> values = supplied.containsKey(field.name)
          ? _formValues(supplied[field.name])
          : field.initialValues;
      final String? error = _validateField(field, values);
      if (error != null) {
        return _Payload.failure(
          _result(
            prepared,
            ForumSubmissionStatus.explicitFailure,
            error,
            canRetryPrepared: true,
          ),
        );
      }
      if (values.isNotEmpty) {
        fields[field.name] = _transportValue(values);
      }
    }
    for (final MapEntry<String, List<String>> entry
        in form.submitFields.entries) {
      fields[entry.key] = _transportValue(entry.value);
    }
    return _Payload.success(fields);
  }

  String? _validateField(DynamicForumField field, List<String> values) {
    final List<String> nonEmpty = values
        .where((String value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if ((field.isRequired ||
            field.type == DynamicForumFieldType.verification) &&
        nonEmpty.isEmpty) {
      return '${field.label}不能为空';
    }
    if (!field.multiple && values.length > 1) {
      return '${field.label}不能提交多个值';
    }
    final Set<String> options = field.options
        .map((DynamicForumFieldOption option) => option.value)
        .toSet();
    if (options.isNotEmpty &&
        values.any((String value) => !options.contains(value))) {
      return '${field.label}包含论坛未声明的选项';
    }
    for (final String value in values) {
      if (value.trim().isEmpty) {
        continue;
      }
      if (field.minimumLength != null && value.length < field.minimumLength!) {
        return '${field.label}长度不足';
      }
      if (field.maximumLength != null && value.length > field.maximumLength!) {
        return '${field.label}超过长度限制';
      }
      if (field.minimumValue != null || field.maximumValue != null) {
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
    }
    return null;
  }

  List<String> _formValues(Object? value) {
    if (value == null || value == false) {
      return const <String>[];
    }
    if (value is Iterable) {
      return value
          .where((Object? item) => item != null && item != false)
          .map((Object? item) => item.toString())
          .toList(growable: false);
    }
    if (value == true) {
      return const <String>['1'];
    }
    return <String>[value.toString()];
  }

  dynamic _transportValue(List<String> values) {
    return values.length == 1 ? values.single : values;
  }

  ForumReadbackDescriptor _readback(ForumActionRequest request) {
    final (ForumReadbackKind, String) value = switch (request.kind) {
      ForumActionKind.newThread => (
        ForumReadbackKind.boardThreads,
        '刷新目标版块，并核对本账号发布的主题',
      ),
      ForumActionKind.reply || ForumActionKind.quoteReply => (
        ForumReadbackKind.thread,
        '刷新目标主题，并核对本账号的最新回复',
      ),
      ForumActionKind.editPost || ForumActionKind.deletePost => (
        ForumReadbackKind.post,
        '重新定位目标楼层，核对编辑或删除结果',
      ),
      ForumActionKind.vote => (ForumReadbackKind.poll, '刷新目标主题，核对投票状态和票数'),
      ForumActionKind.comment => (ForumReadbackKind.comments, '刷新目标楼层，核对最新点评'),
      ForumActionKind.rate => (ForumReadbackKind.ratings, '重新读取评分记录，核对本账号评分'),
      ForumActionKind.report => (
        ForumReadbackKind.report,
        '举报没有可靠公开回读结果，请勿重复提交',
      ),
      ForumActionKind.favoriteThread || ForumActionKind.removeFavorite => (
        ForumReadbackKind.threadFavorites,
        '刷新主题收藏列表，核对目标记录',
      ),
      ForumActionKind.favoriteBoard => (
        ForumReadbackKind.boardFavorites,
        '刷新版块收藏列表，核对目标记录',
      ),
      ForumActionKind.shareThread => (
        ForumReadbackKind.shares,
        '刷新目标主题或分享列表，核对分享结果',
      ),
    };
    return ForumReadbackDescriptor(
      kind: value.$1,
      uri: request.readbackUri,
      target: request.target,
      description: value.$2,
    );
  }

  String _draftContext(ForumActionRequest request) {
    final ForumActionTarget target = request.target;
    return switch (request.kind) {
      ForumActionKind.newThread when target.boardId != null =>
        'new-thread:${target.boardId}',
      ForumActionKind.reply when target.threadId != null =>
        'reply:${target.threadId}',
      ForumActionKind.quoteReply when target.postId != null =>
        'quote-reply:${target.postId}',
      ForumActionKind.editPost when target.postId != null =>
        'edit-post:${target.postId}',
      _ => '',
    };
  }

  void _requireUnresolvedOwner(ForumUnresolvedSubmission submission) {
    if (submission.userId != _userId) {
      throw const ForumSessionExpiredException();
    }
  }

  void _validateIdentity(String source, int expectedUserId) {
    final int? jsonUserId = _jsonUserId(source);
    final int? htmlUserId = authParser.currentUserId(source);
    if (expectedUserId <= 0 ||
        (jsonUserId == null && htmlUserId == null) ||
        (jsonUserId != null && jsonUserId != expectedUserId) ||
        (htmlUserId != null && htmlUserId != expectedUserId)) {
      throw const ForumSessionExpiredException();
    }
  }

  int? _jsonUserId(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final Object? variables = decoded['Variables'];
    if (variables is! Map) {
      return null;
    }
    return int.tryParse(variables['member_uid']?.toString() ?? '');
  }

  ForumSubmissionResult _result(
    ForumPreparedAction prepared,
    ForumSubmissionStatus status,
    String message, {
    bool submissionAttempted = false,
    bool canRetryPrepared = false,
    bool requiresSessionRefresh = false,
  }) {
    return ForumSubmissionResult(
      status: status,
      userId: prepared.userId,
      message: message,
      readback: prepared.readback,
      submissionAttempted: submissionAttempted,
      canRetryPrepared: canRetryPrepared,
      requiresSessionRefresh: requiresSessionRefresh,
    );
  }

  String _newToken() {
    final String source = <Object>[
      _userId,
      ++_sequence,
      DateTime.now().microsecondsSinceEpoch,
      _random.nextInt(1 << 32),
      _random.nextInt(1 << 32),
    ].join(':');
    return sha256.convert(utf8.encode(source)).toString();
  }

  Future<T> _withActiveAccount<T>(Future<T> Function() operation) {
    if (_userId <= 0) {
      throw const ForumSessionExpiredException();
    }
    return _client.withActiveAccount<T>(_userId, operation);
  }
}

class _Payload {
  const _Payload._({this.fields, this.failure});

  factory _Payload.success(Map<String, dynamic> fields) {
    return _Payload._(fields: fields);
  }

  factory _Payload.failure(ForumSubmissionResult failure) {
    return _Payload._(failure: failure);
  }

  final Map<String, dynamic>? fields;
  final ForumSubmissionResult? failure;
}
