import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_attachment_repository.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/forum/presentation/forum_downloaded_file_opener.dart';

final NotifierProvider<
  ForumAttachmentDownloadController,
  Map<String, ForumAttachmentDownloadState>
>
forumAttachmentDownloadControllerProvider =
    NotifierProvider<
      ForumAttachmentDownloadController,
      Map<String, ForumAttachmentDownloadState>
    >(ForumAttachmentDownloadController.new);

enum ForumAttachmentDownloadPhase { downloading, ready, failed }

class ForumAttachmentDownloadState {
  const ForumAttachmentDownloadState({
    required this.phase,
    this.received = 0,
    this.total,
    this.message = '',
    this.downloaded,
  });

  final ForumAttachmentDownloadPhase phase;
  final int received;
  final int? total;
  final String message;
  final ForumDownloadedAttachment? downloaded;

  double? get progress {
    final int? value = total;
    return value != null && value > 0 ? received / value : null;
  }
}

class ForumAttachmentDownloadController
    extends Notifier<Map<String, ForumAttachmentDownloadState>> {
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};
  final Map<String, int> _generations = <String, int>{};
  ForumAttachmentRepository? _repository;

  @override
  Map<String, ForumAttachmentDownloadState> build() {
    for (final CancelToken token in _cancelTokens.values) {
      token.cancel('论坛账号已切换');
    }
    _cancelTokens.clear();
    _generations.clear();
    ref.onDispose(() {
      for (final CancelToken token in _cancelTokens.values) {
        token.cancel('附件下载页面已关闭');
      }
      _generations.clear();
    });
    return const <String, ForumAttachmentDownloadState>{};
  }

  static String keyFor(Uri uri) {
    return sha256.convert(utf8.encode(uri.toString())).toString();
  }

  Future<void> downloadAndOpen(
    ForumAttachment attachment, {
    required Uri topicSourceUri,
  }) async {
    final ForumAttachmentRepository repository = ref.read(
      forumAttachmentRepositoryProvider,
    );
    if (!identical(repository, _repository)) {
      for (final CancelToken token in _cancelTokens.values) {
        token.cancel('论坛账号已切换');
      }
      _cancelTokens.clear();
      _generations.clear();
      state = const <String, ForumAttachmentDownloadState>{};
      _repository = repository;
    }
    final String key = keyFor(attachment.uri);
    if (_cancelTokens.containsKey(key)) {
      return;
    }
    final ForumAttachmentDownloadState? current = state[key];
    final ForumDownloadedAttachment? downloaded = current?.downloaded;
    if (downloaded != null && await downloaded.file.exists()) {
      await _open(key, downloaded);
      return;
    }

    final int generation = (_generations[key] ?? 0) + 1;
    _generations[key] = generation;
    final CancelToken cancelToken = CancelToken();
    _cancelTokens[key] = cancelToken;
    _set(
      key,
      const ForumAttachmentDownloadState(
        phase: ForumAttachmentDownloadPhase.downloading,
      ),
    );
    try {
      int lastReported = 0;
      final ForumDownloadedAttachment result = await repository.download(
        attachment,
        topicSourceUri: topicSourceUri,
        cancelToken: cancelToken,
        onProgress: (int received, int? total) {
          final bool shouldReport =
              received == total || received - lastReported >= 64 * 1024;
          if (shouldReport && _isCurrent(key, generation)) {
            lastReported = received;
            _set(
              key,
              ForumAttachmentDownloadState(
                phase: ForumAttachmentDownloadPhase.downloading,
                received: received,
                total: total,
              ),
            );
          }
        },
      );
      if (!_isCurrent(key, generation)) {
        return;
      }
      _cancelTokens.remove(key);
      _set(
        key,
        ForumAttachmentDownloadState(
          phase: ForumAttachmentDownloadPhase.ready,
          received: result.byteLength,
          total: result.byteLength,
          message: '下载完成',
          downloaded: result,
        ),
      );
      await _open(key, result);
    } on Object catch (error) {
      if (!_isCurrent(key, generation)) {
        return;
      }
      _cancelTokens.remove(key);
      _set(
        key,
        ForumAttachmentDownloadState(
          phase: ForumAttachmentDownloadPhase.failed,
          message: _messageFor(error),
        ),
      );
    }
  }

  void cancel(Uri uri) {
    final String key = keyFor(uri);
    _generations[key] = (_generations[key] ?? 0) + 1;
    _cancelTokens.remove(key)?.cancel('用户取消附件下载');
    _set(
      key,
      const ForumAttachmentDownloadState(
        phase: ForumAttachmentDownloadPhase.failed,
        message: '下载已取消，点按重试',
      ),
    );
  }

  Future<void> _open(String key, ForumDownloadedAttachment downloaded) async {
    try {
      await ref.read(forumDownloadedFileOpenerProvider).open(downloaded);
      _set(
        key,
        ForumAttachmentDownloadState(
          phase: ForumAttachmentDownloadPhase.ready,
          received: downloaded.byteLength,
          total: downloaded.byteLength,
          message: '下载完成',
          downloaded: downloaded,
        ),
      );
    } on Object {
      _set(
        key,
        ForumAttachmentDownloadState(
          phase: ForumAttachmentDownloadPhase.failed,
          received: downloaded.byteLength,
          total: downloaded.byteLength,
          message: '文件已下载，但没有可用的打开方式',
          downloaded: downloaded,
        ),
      );
    }
  }

  bool _isCurrent(String key, int generation) {
    return _generations[key] == generation;
  }

  void _set(String key, ForumAttachmentDownloadState value) {
    state = <String, ForumAttachmentDownloadState>{...state, key: value};
  }

  String _messageFor(Object error) {
    if (error is ForumSessionExpiredException) {
      return '登录状态已失效，请重新登录';
    }
    if (error is ForumAttachmentDownloadException) {
      return error.message;
    }
    if (error is DioException && CancelToken.isCancel(error)) {
      return '下载已取消，点按重试';
    }
    if (error is ForumConnectionException) {
      return '附件下载失败，请稍后重试';
    }
    return '附件处理失败，请重试';
  }
}
