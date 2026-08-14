import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:x300/features/forum/data/forum_action_contract.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

class ForumActionResponseParser {
  const ForumActionResponseParser({
    this.contract = const ForumActionContract(),
  });

  final ForumActionContract contract;

  ForumSubmissionResult parse(
    String source,
    Uri responseUri,
    ForumPreparedAction prepared,
  ) {
    contract.validateSubmissionFinal(prepared, responseUri);
    final Object? decoded = _decode(source);
    final Map<String, dynamic> root = _map(decoded);
    final Map<String, dynamic> messageMap = _map(root['Message']);
    final Map<String, dynamic> variables = _map(root['Variables']);
    final bool isJsonObject = decoded is Map;
    final String serverCode = _firstNonEmpty(<Object?>[
      messageMap['messageval'],
      messageMap['code'],
      if (!isJsonObject) _htmlCode(source),
    ]);
    final String serverMessage = _firstNonEmpty(<Object?>[
      messageMap['messagestr'],
      messageMap['message'],
      if (!isJsonObject) _htmlMessage(source),
    ]);
    ForumSubmissionStatus? status = _classifyFailure(serverCode);
    status ??= _classifyFailure(serverMessage);
    if (status == null &&
        _isVerifiedSuccessCode(prepared.request.kind, serverCode)) {
      status = ForumSubmissionStatus.success;
    }
    status ??= _isSuccessRedirect(prepared, responseUri)
        ? ForumSubmissionStatus.success
        : ForumSubmissionStatus.resultUnknown;

    return ForumSubmissionResult(
      status: status,
      userId: prepared.userId,
      message: _messageFor(status, serverMessage),
      serverCode: serverCode,
      responseUri: responseUri,
      threadId: _positiveInt(
        variables['tid'] ?? root['tid'] ?? responseUri.queryParameters['tid'],
      ),
      postId: _positiveInt(
        variables['pid'] ?? root['pid'] ?? responseUri.queryParameters['pid'],
      ),
      readback: prepared.readback,
      submissionAttempted: true,
    );
  }

  bool _isSuccessRedirect(ForumPreparedAction prepared, Uri responseUri) {
    return contract.isVerifiedSuccessRedirect(prepared, responseUri);
  }

  ForumSubmissionStatus? _classifyFailure(String value) {
    final String normalized = value.toLowerCase().trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.contains('formhash') ||
        normalized.contains('token') ||
        normalized.contains('submit_invalid') ||
        normalized.contains('请求来路不正确') ||
        normalized.contains('請求來路不正確') ||
        normalized.contains('页面已过期') ||
        normalized.contains('頁面已過期')) {
      return ForumSubmissionStatus.tokenExpired;
    }
    if (normalized.contains('nopermission') ||
        normalized.contains('postperm') ||
        normalized.contains('group_nopermission') ||
        normalized.contains('没有权限') ||
        normalized.contains('沒有權限') ||
        normalized.contains('无权') ||
        normalized.contains('無權')) {
      return ForumSubmissionStatus.permissionDenied;
    }
    if (normalized.contains('失败') ||
        normalized.contains('失敗') ||
        normalized.contains('错误') ||
        normalized.contains('錯誤') ||
        normalized.contains('未成功') ||
        normalized.endsWith('_empty') ||
        normalized.endsWith('_invalid') ||
        normalized.endsWith('_error') ||
        normalized.endsWith('_failed') ||
        normalized.contains('不能为空') ||
        normalized.contains('不能為空') ||
        normalized.contains('不存在') ||
        normalized.contains('已关闭') ||
        normalized.contains('已關閉')) {
      return ForumSubmissionStatus.explicitFailure;
    }
    return null;
  }

  bool _isVerifiedSuccessCode(ForumActionKind kind, String value) {
    final String code = value.toLowerCase().trim();
    return switch (kind) {
      ForumActionKind.newThread => code == 'post_newthread_succeed',
      _ => false,
    };
  }

  String _messageFor(ForumSubmissionStatus status, String serverMessage) {
    if (serverMessage.isNotEmpty) {
      return serverMessage;
    }
    return switch (status) {
      ForumSubmissionStatus.success => '论坛已确认接收操作，仍需回读后更新本地状态',
      ForumSubmissionStatus.explicitFailure => '论坛明确拒绝了本次操作',
      ForumSubmissionStatus.permissionDenied => '没有权限执行该操作',
      ForumSubmissionStatus.tokenExpired => '操作表单已过期，请重新读取表单后再次确认',
      ForumSubmissionStatus.resultUnknown => '提交结果未知，请先回读目标资源，勿重复提交',
    };
  }

  Object? _decode(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        entry.key.toString(): entry.value,
    };
  }

  String _htmlCode(String source) {
    final Document document = html_parser.parse(source);
    for (final Element element in document.querySelectorAll(
      '#messagetext[data-message-code], '
      '#messagetext [data-message-code], '
      '.showmessage[data-message-code], '
      '.showmessage [data-message-code], '
      '.alert_error[data-message-code], '
      '.alert_info[data-message-code]',
    )) {
      if (_isTrustedMessageElement(element)) {
        return element.attributes['data-message-code'] ?? '';
      }
    }
    return '';
  }

  String _htmlMessage(String source) {
    final Document document = html_parser.parse(source);
    for (final Element element in document.querySelectorAll(
      '#messagetext p, #messagetext, .alert_error, .alert_info, '
      '.showmessage, .tip .message, .tip',
    )) {
      if (_isTrustedMessageElement(element)) {
        return _normalizeText(element.text);
      }
    }
    return '';
  }

  bool _isTrustedMessageElement(Element element) {
    bool insideMessageContainer = false;
    Element? current = element;
    while (current != null) {
      if (_isFormOrControl(current)) {
        return false;
      }
      if (_isMessageContainer(current)) {
        insideMessageContainer = true;
        if (current.querySelector(
              'form, input, textarea, select, button',
            ) !=
            null) {
          return false;
        }
      }
      current = current.parent;
    }
    return insideMessageContainer;
  }

  bool _isMessageContainer(Element element) {
    return element.id == 'messagetext' ||
        element.classes.contains('showmessage') ||
        element.classes.contains('alert_error') ||
        element.classes.contains('alert_info') ||
        element.classes.contains('tip');
  }

  bool _isFormOrControl(Element element) {
    return const <String>{
      'form',
      'input',
      'textarea',
      'select',
      'button',
    }.contains(element.localName);
  }

  String _firstNonEmpty(List<Object?> values) {
    for (final Object? value in values) {
      final String normalized = _normalizeText(value?.toString() ?? '');
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  int? _positiveInt(Object? value) {
    final int? parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String _normalizeText(String source) {
    return source.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
