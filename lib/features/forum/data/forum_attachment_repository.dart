import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

final Provider<ForumAttachmentRepository> forumAttachmentRepositoryProvider =
    Provider<ForumAttachmentRepository>(
      (Ref ref) => ForumAttachmentRepository(
        ref.watch(forumClientProvider),
        ref.watch(authControllerProvider).value?.userId ?? 0,
      ),
    );

typedef ForumAttachmentCacheDirectory = Future<Directory> Function();
typedef ForumAttachmentProgress = void Function(int received, int? total);

class ForumAttachmentDownloadException extends ForumException {
  const ForumAttachmentDownloadException(super.message);
}

class ForumDownloadedAttachment {
  const ForumDownloadedAttachment({
    required this.file,
    required this.fileName,
    required this.mimeType,
    required this.byteLength,
  });

  final File file;
  final String fileName;
  final String mimeType;
  final int byteLength;
}

class ForumAttachmentRepository {
  ForumAttachmentRepository(
    this._client,
    this._userId, {
    ForumAttachmentCacheDirectory? cacheDirectory,
    this.maximumBytes = defaultMaximumBytes,
    this.authParser = const AuthPageParser(),
  }) : _cacheDirectory = cacheDirectory ?? getTemporaryDirectory;

  static const int defaultMaximumBytes = 256 * 1024 * 1024;
  static const Set<String> _sensitiveKeys = <String>{
    'auth',
    'authorization',
    'cookie',
    'formhash',
    'hash',
    'key',
    'password',
    'sid',
    'sign',
    'signature',
    'token',
  };
  static final RegExp _safeExtension = RegExp(r'^\.[a-z0-9]{1,10}$');
  static final RegExp _windowsReservedName = RegExp(
    r'^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$',
    caseSensitive: false,
  );

  final ForumClient _client;
  final int _userId;
  final ForumAttachmentCacheDirectory _cacheDirectory;
  final int maximumBytes;
  final AuthPageParser authParser;
  static final Map<String, Future<ForumDownloadedAttachment>> _pending =
      <String, Future<ForumDownloadedAttachment>>{};
  static final Map<int, Set<CancelToken>> _activeTokens =
      <int, Set<CancelToken>>{};
  static final Map<int, Set<Future<ForumDownloadedAttachment>>> _activeTasks =
      <int, Set<Future<ForumDownloadedAttachment>>>{};
  static final Map<int, int> _accountGenerations = <int, int>{};
  static final Set<int> _clearingAccounts = <int>{};
  static final Map<int, Future<void>> _accountClearTasks =
      <int, Future<void>>{};
  static Future<void>? _allClearTask;
  static bool _clearingAll = false;

  Future<ForumDownloadedAttachment> download(
    ForumAttachment attachment, {
    required Uri topicSourceUri,
    ForumAttachmentProgress? onProgress,
    CancelToken? cancelToken,
  }) {
    _requireAccount();
    if (_clearingAll || _clearingAccounts.contains(_userId)) {
      return Future<ForumDownloadedAttachment>.error(
        const ForumAttachmentDownloadException('论坛附件缓存正在清理'),
      );
    }
    final Uri attachmentUri = _requireAttachmentUri(attachment.uri);
    final Uri referer = _requireTopicUri(topicSourceUri);
    final String key = 'uid:$_userId:${_cacheKey(attachmentUri)}';
    final Future<ForumDownloadedAttachment>? pending = _pending[key];
    if (pending != null) {
      return pending;
    }
    final int generation = _accountGenerations[_userId] ?? 0;
    final CancelToken operationToken = CancelToken();
    if (cancelToken != null) {
      if (cancelToken.isCancelled) {
        operationToken.cancel('附件下载已取消');
      } else {
        unawaited(
          cancelToken.whenCancel.then(
            (DioException error) => operationToken.cancel(error.error),
          ),
        );
      }
    }
    late final Future<ForumDownloadedAttachment> future;
    future =
        _download(
          attachment,
          attachmentUri: attachmentUri,
          topicSourceUri: referer,
          generation: generation,
          onProgress: onProgress,
          cancelToken: operationToken,
        ).whenComplete(() {
          if (identical(_pending[key], future)) {
            _pending.remove(key);
          }
          _activeTokens[_userId]?.remove(operationToken);
          _activeTasks[_userId]?.remove(future);
        });
    _pending[key] = future;
    _activeTokens
        .putIfAbsent(_userId, () => <CancelToken>{})
        .add(operationToken);
    _activeTasks
        .putIfAbsent(_userId, () => <Future<ForumDownloadedAttachment>>{})
        .add(future);
    return future;
  }

  Future<void> clear() async {
    await clearAccountCache(_userId, cacheDirectory: _cacheDirectory);
  }

  static Future<void> clearAccountCache(
    int userId, {
    ForumAttachmentCacheDirectory? cacheDirectory,
  }) {
    if (userId <= 0) {
      return Future<void>.value();
    }
    final Future<void>? allClear = _allClearTask;
    if (allClear != null) {
      return allClear;
    }
    final Future<void>? pending = _accountClearTasks[userId];
    if (pending != null) {
      return pending;
    }
    late final Future<void> future;
    future =
        _performClearAccount(
          userId,
          cacheDirectory ?? getTemporaryDirectory,
        ).whenComplete(() {
          if (identical(_accountClearTasks[userId], future)) {
            _accountClearTasks.remove(userId);
          }
        });
    _accountClearTasks[userId] = future;
    return future;
  }

  static Future<void> _performClearAccount(
    int userId,
    ForumAttachmentCacheDirectory cacheDirectory,
  ) async {
    _clearingAccounts.add(userId);
    _accountGenerations[userId] = (_accountGenerations[userId] ?? 0) + 1;
    try {
      for (final CancelToken token in List<CancelToken>.of(
        _activeTokens[userId] ?? const <CancelToken>{},
      )) {
        token.cancel('论坛附件缓存已清理');
      }
      await _waitForTasks(userId);
      final Directory directory = await _accountDirectory(
        userId,
        cacheDirectory,
      );
      await _deleteCacheEntity(directory.path);
    } finally {
      _clearingAccounts.remove(userId);
    }
  }

  static Future<void> clearAllCaches({
    ForumAttachmentCacheDirectory? cacheDirectory,
  }) {
    final Future<void>? pending = _allClearTask;
    if (pending != null) {
      return pending;
    }
    late final Future<void> future;
    future = _performClearAll(cacheDirectory ?? getTemporaryDirectory)
        .whenComplete(() {
          if (identical(_allClearTask, future)) {
            _allClearTask = null;
          }
        });
    _allClearTask = future;
    return future;
  }

  static Future<void> _performClearAll(
    ForumAttachmentCacheDirectory cacheDirectory,
  ) async {
    _clearingAll = true;
    final Set<int> userIds = <int>{
      ..._activeTokens.keys,
      ..._accountGenerations.keys,
    };
    for (final int userId in userIds) {
      _accountGenerations[userId] = (_accountGenerations[userId] ?? 0) + 1;
      for (final CancelToken token in List<CancelToken>.of(
        _activeTokens[userId] ?? const <CancelToken>{},
      )) {
        token.cancel('论坛附件缓存已清理');
      }
    }
    try {
      await Future.wait<void>(List<Future<void>>.of(_accountClearTasks.values));
      for (final int userId in userIds) {
        await _waitForTasks(userId);
      }
      final Directory root = await cacheDirectory();
      final Directory directory = Directory(
        path.join(path.canonicalize(root.absolute.path), 'forum-attachments'),
      );
      await _deleteCacheEntity(directory.path);
    } finally {
      _clearingAll = false;
    }
  }

  static Future<void> _waitForTasks(int userId) async {
    while ((_activeTasks[userId]?.isNotEmpty ?? false)) {
      final List<Future<ForumDownloadedAttachment>> tasks =
          List<Future<ForumDownloadedAttachment>>.of(_activeTasks[userId]!);
      await Future.wait<void>(
        tasks.map((Future<ForumDownloadedAttachment> task) async {
          try {
            await task;
          } on Object {
            return;
          }
        }),
      );
    }
  }

  Future<ForumDownloadedAttachment> _download(
    ForumAttachment attachment, {
    required Uri attachmentUri,
    required Uri topicSourceUri,
    required int generation,
    required ForumAttachmentProgress? onProgress,
    required CancelToken? cancelToken,
  }) async {
    return _client.withActiveAccount<ForumDownloadedAttachment>(
      _userId,
      () async {
        final Response<String> identity = await _client.getText(
          ForumClient.baseUri.resolve('forum.php?mobile=2'),
          retryCount: 0,
        );
        if (authParser.currentUserId(identity.data ?? '') != _userId) {
          throw const ForumSessionExpiredException();
        }
        return _client.consumeByteStream<ForumDownloadedAttachment>(
          attachmentUri,
          referer: topicSourceUri.toString(),
          cancelToken: cancelToken,
          allowRedirect: (Uri uri) =>
              _isForumUri(uri) &&
              _isAttachmentRoute(uri) &&
              _sameAttachmentTarget(attachmentUri, uri),
          consume: (ForumByteStreamResponse response) => _consume(
            attachment,
            attachmentUri: attachmentUri,
            response: response,
            generation: generation,
            onProgress: onProgress,
            cancelToken: cancelToken,
          ),
        );
      },
    );
  }

  Future<ForumDownloadedAttachment> _consume(
    ForumAttachment attachment, {
    required Uri attachmentUri,
    required ForumByteStreamResponse response,
    required int generation,
    required ForumAttachmentProgress? onProgress,
    required CancelToken? cancelToken,
  }) async {
    final Uri finalUri = _requireAttachmentUri(response.finalUri);
    if (!_sameAttachmentTarget(attachmentUri, finalUri)) {
      throw const ForumAttachmentDownloadException('论坛附件跳转目标不一致');
    }
    final int? declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > maximumBytes) {
      throw const ForumAttachmentDownloadException('论坛附件超过大小限制');
    }
    final String mimeType = _safeMimeType(
      response.headers.value(HttpHeaders.contentTypeHeader),
    );
    if (mimeType == 'text/html' || mimeType == 'application/xhtml+xml') {
      throw const ForumSessionExpiredException();
    }
    final String fileName = _safeFileName(
      attachment,
      response.headers.value('content-disposition'),
      mimeType,
    );
    final Directory directory = await _downloadDirectory();
    await directory.create(recursive: true);
    final String identity = _cacheKey(attachmentUri);
    final Directory temporaryDirectory = await directory.createTemp(
      '.$identity-',
    );
    final File temporary = File(
      path.join(temporaryDirectory.path, 'payload.part'),
    );
    IOSink? sink;
    int received = 0;
    try {
      sink = temporary.openWrite(mode: FileMode.writeOnly);
      await for (final Uint8List chunk in response.stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: attachmentUri.path),
            reason: '附件下载已取消',
          );
        }
        received += chunk.length;
        if (received > maximumBytes) {
          throw const ForumAttachmentDownloadException('论坛附件超过大小限制');
        }
        sink.add(chunk);
        onProgress?.call(received, declaredLength);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (declaredLength != null && received != declaredLength) {
        throw const ForumAttachmentDownloadException('论坛附件内容长度不一致');
      }
      if (generation != (_accountGenerations[_userId] ?? 0)) {
        throw const ForumAttachmentDownloadException('论坛附件下载已失效');
      }
      final File namedFile = await temporary.rename(
        path.join(temporaryDirectory.path, fileName),
      );
      final String temporaryName = path.basename(temporaryDirectory.path);
      final Directory completedDirectory = Directory(
        path.join(
          directory.path,
          temporaryName.startsWith('.')
              ? temporaryName.substring(1)
              : temporaryName,
        ),
      );
      await temporaryDirectory.rename(completedDirectory.path);
      final File completed = File(
        path.join(completedDirectory.path, path.basename(namedFile.path)),
      );
      return ForumDownloadedAttachment(
        file: completed,
        fileName: fileName,
        mimeType: mimeType,
        byteLength: received,
      );
    } on Object {
      await sink?.close();
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Uri _requireAttachmentUri(Uri uri) {
    if (!_isForumUri(uri) || !_isAttachmentRoute(uri)) {
      throw const ForumAttachmentDownloadException('论坛附件地址不安全');
    }
    return uri;
  }

  Uri _requireTopicUri(Uri uri) {
    if (!_isForumUri(uri) || !_isTopicRoute(uri)) {
      throw const ForumAttachmentDownloadException('论坛附件来源页面不安全');
    }
    return uri.replace(fragment: '');
  }

  bool _isForumUri(Uri uri) {
    return uri.scheme == 'https' &&
        uri.host == ForumClient.baseUri.host &&
        uri.port == ForumClient.baseUri.port &&
        uri.userInfo.isEmpty &&
        !_hasSensitiveParts(uri);
  }

  bool _isAttachmentRoute(Uri uri) {
    if (uri.fragment.isNotEmpty) {
      return false;
    }
    final String lowerPath = uri.path.toLowerCase();
    if (lowerPath.startsWith('/data/attachment/')) {
      final List<String> segments = uri.pathSegments;
      return uri.path.startsWith('/data/attachment/') &&
          segments.length >= 3 &&
          segments[0] == 'data' &&
          segments[1] == 'attachment' &&
          segments
              .skip(2)
              .every(
                (String value) =>
                    value.isNotEmpty &&
                    value != '.' &&
                    value != '..' &&
                    !value.contains('/') &&
                    !value.contains('\\') &&
                    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value),
              ) &&
          uri.query.isEmpty;
    }
    if (lowerPath != '/forum.php') {
      return false;
    }
    final String? mod = _single(uri, 'mod')?.toLowerCase();
    final int? aid = int.tryParse(_single(uri, 'aid') ?? '');
    final String? mobile = _single(uri, 'mobile');
    return (mod == 'attachment' || mod == 'image') &&
        aid != null &&
        aid > 0 &&
        (mobile == null || mobile == '2') &&
        uri.queryParametersAll.keys.every(
          (String key) => const <String>{'mod', 'aid', 'mobile'}.contains(key),
        );
  }

  bool _isTopicRoute(Uri uri) {
    final String lowerPath = uri.path.toLowerCase();
    if (RegExp(
      r'^/thread-[1-9][0-9]*(?:-[0-9]+)*\.html$',
    ).hasMatch(lowerPath)) {
      return _single(uri, 'mobile') == '2';
    }
    if (lowerPath != '/forum.php') {
      return false;
    }
    final String? mod = _single(uri, 'mod')?.toLowerCase();
    final int? threadId = int.tryParse(
      _single(uri, mod == 'redirect' ? 'ptid' : 'tid') ?? '',
    );
    final String? mobile = _single(uri, 'mobile');
    return threadId != null &&
        threadId > 0 &&
        mobile == '2' &&
        (mod == 'viewthread' ||
            (mod == 'redirect' &&
                _single(uri, 'goto')?.toLowerCase() == 'findpost'));
  }

  bool _sameAttachmentTarget(Uri request, Uri response) {
    if (request.path.toLowerCase().startsWith('/data/attachment/')) {
      return response.path == request.path;
    }
    final int? requestedId = int.tryParse(_single(request, 'aid') ?? '');
    final int? responseId = int.tryParse(_single(response, 'aid') ?? '');
    return requestedId != null && requestedId == responseId;
  }

  bool _hasSensitiveParts(Uri uri) {
    if (uri.fragment.isNotEmpty &&
        _sensitiveKeys.any(
          (String key) => uri.fragment.toLowerCase().contains(key),
        )) {
      return true;
    }
    return uri.queryParametersAll.keys.any((String key) {
      final String lower = key.toLowerCase();
      final int bracket = lower.indexOf('[');
      final String base = bracket < 0 ? lower : lower.substring(0, bracket);
      return _sensitiveKeys.contains(base);
    });
  }

  String? _single(Uri uri, String name) {
    final List<String> matchingKeys = uri.queryParametersAll.keys
        .where((String key) => key.toLowerCase() == name)
        .toList(growable: false);
    if (matchingKeys.length != 1 || matchingKeys.single != name) {
      return null;
    }
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    if (values.length != 1) {
      return null;
    }
    return values.single;
  }

  Future<Directory> _downloadDirectory() async {
    return _accountDirectory(_userId, _cacheDirectory);
  }

  static Future<Directory> _accountDirectory(
    int userId,
    ForumAttachmentCacheDirectory cacheDirectory,
  ) async {
    final Directory root = await cacheDirectory();
    final String rootPath = path.canonicalize(root.absolute.path);
    final Directory directory = Directory(
      path.join(rootPath, 'forum-attachments', 'uid-$userId'),
    );
    if (!path.isWithin(rootPath, directory.absolute.path)) {
      throw const ForumAttachmentDownloadException('论坛附件缓存目录不安全');
    }
    return directory;
  }

  static Future<void> _deleteCacheEntity(String entityPath) async {
    final FileSystemEntityType type = await FileSystemEntity.type(
      entityPath,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    if (type == FileSystemEntityType.link) {
      await Link(entityPath).delete();
      return;
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(entityPath).delete(recursive: true);
      return;
    }
    await File(entityPath).delete();
  }

  String _cacheKey(Uri uri) {
    final Uri normalized = uri.replace(fragment: '');
    return sha256.convert(utf8.encode(normalized.toString())).toString();
  }

  String _safeFileName(
    ForumAttachment attachment,
    String? contentDisposition,
    String mimeType,
  ) {
    final String? dispositionName = _contentDispositionName(contentDisposition);
    final String fallback = attachment.name.trim().isEmpty
        ? _pathFileName(attachment.uri)
        : attachment.name;
    String value = dispositionName ?? fallback;
    if (_containsSensitiveFileName(value)) {
      value = '附件${_safeFileExtension(value)}';
    }
    value = value
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (value.isEmpty || value == '.' || value == '..') {
      value = '附件';
    }
    if (_windowsReservedName.hasMatch(value)) {
      value = '_$value';
    }
    if (value.length > 120) {
      final String extension = _safeFileExtension(value);
      value = '${value.substring(0, 120 - extension.length)}$extension';
    }
    if (_safeFileExtension(value).isEmpty) {
      final String extension = _extensionForMimeType(mimeType);
      if (extension.isNotEmpty) {
        value = '$value$extension';
      }
    }
    return value;
  }

  String? _contentDispositionName(String? header) {
    if (header == null || header.length > 4096) {
      return null;
    }
    final Match? encoded = RegExp(
      r'''(?:^|;)\s*filename\*\s*=\s*UTF-8'[^']*'([^;]*)''',
      caseSensitive: false,
    ).firstMatch(header);
    if (encoded != null) {
      try {
        return Uri.decodeComponent(encoded.group(1)!.trim());
      } on FormatException {
        return null;
      }
    }
    final Match? quoted = RegExp(
      r'''(?:^|;)\s*filename\s*=\s*"([^"]*)"''',
      caseSensitive: false,
    ).firstMatch(header);
    if (quoted != null) {
      return quoted.group(1);
    }
    final Match? plain = RegExp(
      r'''(?:^|;)\s*filename\s*=\s*([^;]*)''',
      caseSensitive: false,
    ).firstMatch(header);
    return plain?.group(1)?.trim();
  }

  String _pathFileName(Uri uri) {
    final String value = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (value.isEmpty || value.toLowerCase() == 'forum.php') {
      return '附件';
    }
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return '附件';
    }
  }

  String _safeFileExtension(String value) {
    final String extension = path.extension(value).toLowerCase();
    return _safeExtension.hasMatch(extension) ? extension : '';
  }

  bool _containsSensitiveFileName(String value) {
    final String lower = value.toLowerCase();
    return _sensitiveKeys.any(
      (String key) => RegExp(
        '(?:^|[^a-z0-9])${RegExp.escape(key)}(?:[^a-z0-9]|\$)',
      ).hasMatch(lower),
    );
  }

  String _safeMimeType(String? value) {
    final String mimeType = value?.split(';').first.trim().toLowerCase() ?? '';
    return RegExp(
          r'^[a-z0-9][a-z0-9!#&^_.+\-]*/[a-z0-9][a-z0-9!#&^_.+\-]*$',
        ).hasMatch(mimeType)
        ? mimeType
        : 'application/octet-stream';
  }

  String _extensionForMimeType(String mimeType) {
    return const <String, String>{
          'application/epub+zip': '.epub',
          'application/pdf': '.pdf',
          'application/vnd.rar': '.rar',
          'application/x-7z-compressed': '.7z',
          'application/zip': '.zip',
          'audio/mpeg': '.mp3',
          'image/gif': '.gif',
          'image/jpeg': '.jpg',
          'image/png': '.png',
          'image/webp': '.webp',
          'text/plain': '.txt',
          'video/mp4': '.mp4',
        }[mimeType] ??
        '';
  }

  void _requireAccount() {
    if (_userId <= 0) {
      throw const ForumSessionExpiredException();
    }
    if (maximumBytes <= 0) {
      throw StateError('maximumBytes must be positive');
    }
  }
}
