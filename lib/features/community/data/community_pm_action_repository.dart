import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/community/data/community_pm_action_parser.dart';
import 'package:x300/features/community/domain/community_pm_action_models.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';

final Provider<CommunityPmActionRepository>
communityPmActionRepositoryProvider = Provider<CommunityPmActionRepository>(
  (Ref ref) => CommunityPmActionRepository(
    ref.watch(forumClientProvider),
    ref.watch(authControllerProvider).value?.userId ?? 0,
    ForumSubmissionTombstoneRepository(ref.watch(appDatabaseProvider)),
  ),
);

class CommunityPmSubmissionBlockedException extends ForumException {
  const CommunityPmSubmissionBlockedException({
    required this.request,
    required this.tombstone,
    required this.key,
  }) : super('检测到该私信有结果未知、尚未人工核对的提交记录；请先回读会话，勿重复发送');

  final CommunityPmSendRequest request;
  final SubmissionTombstoneRecord tombstone;
  final SubmissionTombstoneKey key;
}

class CommunityPmActionRepository {
  CommunityPmActionRepository(
    this._client,
    this._userId,
    this._tombstones, {
    this.parser = const CommunityPmActionParser(),
    this.originPolicy = const ForumOriginPolicy(),
    this.authParser = const AuthPageParser(),
  });

  final ForumClient _client;
  final int _userId;
  final ForumSubmissionTombstoneRepository _tombstones;
  final CommunityPmActionParser parser;
  final ForumOriginPolicy originPolicy;
  final AuthPageParser authParser;
  final Random _random = Random.secure();
  final Map<String, CommunityPmPreparedSend> _unused =
      <String, CommunityPmPreparedSend>{};
  int _sequence = 0;

  Future<CommunityPmPreparedSend> prepare(CommunityPmSendRequest request) {
    _checkUser();
    parser.validateEntryUri(request, request.entryUri);
    return _client.withActiveAccount<CommunityPmPreparedSend>(
      _userId,
      () async {
        if (request.context == CommunityPmSendContext.conversation ||
            request.expectedPeerUsername.trim().isNotEmpty) {
          await _throwIfUnresolved(
            request,
            username: request.expectedPeerUsername,
          );
        }
        final Response<String> response = await _client.getText(
          request.entryUri,
        );
        parser.validateEntryUri(request, response.realUri);
        final CommunityPmSendForm form = parser.parse(
          response.data ?? '',
          response.realUri,
          expectedViewerUserId: _userId,
          request: request,
        );
        final String token = _newToken();
        final CommunityPmPreparedSend prepared = CommunityPmPreparedSend(
          token: token,
          userId: _userId,
          request: request,
          form: form,
        );
        _unused[token] = prepared;
        return prepared;
      },
    );
  }

  Future<CommunityPmSubmissionResult> submit(
    CommunityPmPreparedSend prepared, {
    required String message,
    String username = '',
  }) async {
    if (!_isRegistered(prepared)) {
      return _failure('该私信确认已使用，请重新读取表单');
    }
    final String normalizedMessage = message.trim();
    final String normalizedUsername = username.trim();
    if (normalizedMessage.isEmpty) {
      return _failure('私信内容不能为空', canRetryPrepared: true);
    }
    if (prepared.form.acceptsUsername && normalizedUsername.isEmpty) {
      return _failure('收件人不能为空', canRetryPrepared: true);
    }
    if (!prepared.form.acceptsUsername && normalizedUsername.isNotEmpty) {
      return _failure('当前会话表单不接受可变收件人');
    }
    if (prepared.form.formHash.trim().isEmpty) {
      return _failure('私信表单已过期，请重新读取', canRetryPrepared: true);
    }

    final Map<String, dynamic> fields = <String, dynamic>{
      'formhash': prepared.form.formHash,
      ...prepared.form.fixedFields,
      'message': message,
      if (prepared.form.acceptsUsername) 'username': normalizedUsername,
    };
    try {
      return await _client.withActiveAccount<CommunityPmSubmissionResult>(
        _userId,
        () async {
          if (!_consume(prepared)) {
            return _failure('该私信确认已使用，请重新读取表单');
          }
          final SubmissionTombstoneKey key = _tombstoneKey(
            prepared.request,
            username: normalizedUsername,
          );
          final String? attemptId = await _tombstones.claimAttemptedKey(
            userId: _userId,
            key: key,
            deleteDraft: true,
          );
          if (attemptId == null) {
            await _throwIfUnresolved(
              prepared.request,
              username: normalizedUsername,
            );
            throw StateError('私信提交封存冲突，请先回读会话');
          }
          try {
            final Response<String> response = await _client.postForm(
              prepared.form.actionUri,
              fields: fields,
              referer: prepared.form.sourceUri.toString(),
            );
            _validatePostResponse(response, prepared);
            return _unknown();
          } on ForumSessionExpiredException {
            return _unknown(requiresSessionRefresh: true);
          } on Object {
            return _unknown();
          }
        },
      );
    } on ForumSessionExpiredException {
      return _failure('登录状态已失效，请重新登录后重新读取表单', requiresSessionRefresh: true);
    }
  }

  void discard(CommunityPmPreparedSend prepared) {
    if (_isRegistered(prepared)) {
      _unused.remove(prepared.token);
    }
  }

  Future<void> acknowledgeUnresolved(
    CommunityPmSubmissionBlockedException blocked,
  ) {
    _checkUser();
    return _client.withActiveAccount<void>(_userId, () async {
      final SubmissionTombstoneKey expected = blocked.key;
      final SubmissionTombstoneRecord record = blocked.tombstone;
      if (record.userId != _userId ||
          !_sameKey(record.key, expected) ||
          !_keyMatchesRequest(expected, blocked.request)) {
        throw StateError('私信提交封存不属于当前账号或会话');
      }
      if (!await _tombstones.acknowledgeKey(record)) {
        throw StateError('私信提交封存记录已变化，请先重新回读');
      }
    });
  }

  Future<void> _throwIfUnresolved(
    CommunityPmSendRequest request, {
    String username = '',
  }) async {
    final SubmissionTombstoneKey key = _tombstoneKey(
      request,
      username: username,
    );
    final SubmissionTombstoneRecord? tombstone = await _tombstones.findKey(
      userId: _userId,
      key: key,
    );
    if (tombstone != null) {
      throw CommunityPmSubmissionBlockedException(
        request: request,
        tombstone: tombstone,
        key: key,
      );
    }
  }

  SubmissionTombstoneKey _tombstoneKey(
    CommunityPmSendRequest request, {
    String username = '',
  }) {
    final bool conversation =
        request.context == CommunityPmSendContext.conversation;
    final int peerUserId = conversation ? request.expectedPeerUserId : 0;
    final String recipientFingerprint = conversation
        ? ''
        : _recipientFingerprint(username);
    return SubmissionTombstoneKey(
      action: conversation
          ? 'communityPmSend:conversation'
          : 'communityPmSend:compose:$recipientFingerprint',
      threadId: peerUserId > 0 ? peerUserId : null,
      draftContext: conversation
          ? 'community-pm:conversation:$peerUserId'
          : 'community-pm:compose',
    );
  }

  String _recipientFingerprint(String username) {
    final String normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw ArgumentError.value(username, 'username', '私信收件人不能为空');
    }
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  bool _keyMatchesRequest(
    SubmissionTombstoneKey key,
    CommunityPmSendRequest request,
  ) {
    if (request.context == CommunityPmSendContext.conversation) {
      return _sameKey(key, _tombstoneKey(request));
    }
    return key.action.startsWith('communityPmSend:compose:') &&
        key.draftContext == 'community-pm:compose' &&
        key.boardId == null &&
        key.threadId == null &&
        key.postId == null &&
        key.favoriteId == null;
  }

  bool _sameKey(SubmissionTombstoneKey first, SubmissionTombstoneKey second) {
    return first.action == second.action &&
        first.boardId == second.boardId &&
        first.threadId == second.threadId &&
        first.postId == second.postId &&
        first.favoriteId == second.favoriteId &&
        first.draftContext == second.draftContext;
  }

  void _validatePostResponse(
    Response<String> response,
    CommunityPmPreparedSend prepared,
  ) {
    final Uri uri = response.realUri;
    originPolicy.requireMobilePage(uri);
    final List<String> mobileValues =
        uri.queryParametersAll['mobile'] ?? const <String>[];
    if (mobileValues.length != 1 || mobileValues.single != '2') {
      throw const ForumParseException('私信提交返回了非标准移动地址');
    }
    for (final String name in const <String>['uid', 'spaceuid']) {
      final List<String> values =
          uri.queryParametersAll[name] ?? const <String>[];
      if (values.isNotEmpty &&
          (values.length != 1 || int.tryParse(values.single) != _userId)) {
        throw const ForumSessionExpiredException();
      }
    }
    final String source = response.data ?? '';
    final dom.Document document = html_parser.parse(source);
    if (document.querySelector('form#loginform') != null ||
        document.body?.classes.contains('pg_logging') == true) {
      throw const ForumSessionExpiredException();
    }
    final int? responseUserId = authParser.currentUserId(source);
    if (responseUserId != null && responseUserId != _userId) {
      throw const ForumSessionExpiredException();
    }
    final bool recognized =
        uri == prepared.form.actionUri ||
        (uri.path == '/home.php' &&
            uri.queryParameters['mod'] == 'space' &&
            uri.queryParameters['do'] == 'pm' &&
            (uri.queryParameters['subop'] == null ||
                (uri.queryParameters['subop'] == 'view' &&
                    int.tryParse(uri.queryParameters['touid'] ?? '') ==
                        prepared.form.peerUserId)));
    if (!recognized) {
      throw const ForumParseException('私信提交返回地址无法安全确认');
    }
  }

  bool _isRegistered(CommunityPmPreparedSend prepared) {
    return identical(_unused[prepared.token], prepared) &&
        prepared.userId == _userId;
  }

  bool _consume(CommunityPmPreparedSend prepared) {
    if (!_isRegistered(prepared)) {
      return false;
    }
    _unused.remove(prepared.token);
    return true;
  }

  CommunityPmSubmissionResult _failure(
    String message, {
    bool canRetryPrepared = false,
    bool requiresSessionRefresh = false,
  }) {
    return CommunityPmSubmissionResult(
      status: CommunityPmSubmissionStatus.explicitFailure,
      message: message,
      submissionAttempted: false,
      canRetryPrepared: canRetryPrepared,
      requiresSessionRefresh: requiresSessionRefresh,
    );
  }

  CommunityPmSubmissionResult _unknown({bool requiresSessionRefresh = false}) {
    return CommunityPmSubmissionResult(
      status: CommunityPmSubmissionStatus.resultUnknown,
      message: requiresSessionRefresh
          ? '私信提交已发出，但账号身份随后失效，结果未知。请重新登录并回读会话，应用不会重发。'
          : '私信提交已发出，但成功响应尚未经过真实写入验证，结果未知。请回读会话确认，应用不会重发。',
      submissionAttempted: true,
      requiresSessionRefresh: requiresSessionRefresh,
    );
  }

  String _newToken() {
    _sequence++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_sequence-'
        '${_random.nextInt(1 << 32)}';
  }

  void _checkUser() {
    if (_userId <= 0) {
      throw const ForumSessionExpiredException();
    }
  }
}
