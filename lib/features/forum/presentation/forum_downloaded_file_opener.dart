import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x300/features/forum/data/forum_attachment_repository.dart';

final Provider<ForumDownloadedFileOpener> forumDownloadedFileOpenerProvider =
    Provider<ForumDownloadedFileOpener>(
      (Ref ref) => const ForumDownloadedFileOpener(),
    );

typedef ForumFileOpenInvoker =
    Future<Object?> Function(Map<String, Object?> arguments);
typedef ForumDesktopFileLauncher = Future<bool> Function(Uri uri);

class ForumDownloadedFileOpenException implements Exception {
  const ForumDownloadedFileOpenException();
}

class ForumDownloadedFileOpener {
  const ForumDownloadedFileOpener({
    @visibleForTesting this.invokeOverride,
    @visibleForTesting this.launchDesktopOverride,
    @visibleForTesting this.platformOverride,
    @visibleForTesting this.cacheDirectoryOverride,
  });

  static const MethodChannel _channel = MethodChannel(
    'com.yamibox300/forum_downloaded_file',
  );
  static final RegExp _mimeTypePattern = RegExp(
    r'^[a-z0-9][a-z0-9!#&^_.+\-]*/[a-z0-9][a-z0-9!#&^_.+\-]*$',
  );

  final ForumFileOpenInvoker? invokeOverride;
  final ForumDesktopFileLauncher? launchDesktopOverride;
  final String? platformOverride;
  final ForumAttachmentCacheDirectory? cacheDirectoryOverride;

  Future<void> open(ForumDownloadedAttachment attachment) async {
    if (!path.isAbsolute(attachment.file.path)) {
      throw const ForumDownloadedFileOpenException();
    }
    final File file = attachment.file.absolute;
    final Directory root =
        await (cacheDirectoryOverride ?? getApplicationCacheDirectory)();
    try {
      final String cacheRoot = await root.resolveSymbolicLinks();
      final String attachmentRoot = await Directory(
        path.join(cacheRoot, 'forum-attachments'),
      ).resolveSymbolicLinks();
      final String filePath = await file.resolveSymbolicLinks();
      if (!path.isAbsolute(filePath) ||
          !path.isWithin(attachmentRoot, filePath) ||
          !await File(filePath).exists() ||
          !_mimeTypePattern.hasMatch(attachment.mimeType)) {
        throw const ForumDownloadedFileOpenException();
      }

      final String platform = platformOverride ?? Platform.operatingSystem;
      if (platform == 'android' || platform == 'ios') {
        try {
          await (invokeOverride ?? _invokePlatform)(<String, Object?>{
            'filePath': filePath,
            'mimeType': attachment.mimeType,
          });
          return;
        } on PlatformException {
          throw const ForumDownloadedFileOpenException();
        } on MissingPluginException {
          throw const ForumDownloadedFileOpenException();
        }
      }
      if (platform == 'linux' || platform == 'macos' || platform == 'windows') {
        final bool launched =
            await (launchDesktopOverride ?? _launchDesktopFile)(
              Uri.file(filePath),
            );
        if (launched) {
          return;
        }
      }
      throw const ForumDownloadedFileOpenException();
    } on FileSystemException {
      throw const ForumDownloadedFileOpenException();
    }
  }

  static Future<Object?> _invokePlatform(Map<String, Object?> arguments) {
    return _channel.invokeMethod<Object?>('open', arguments);
  }

  static Future<bool> _launchDesktopFile(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
