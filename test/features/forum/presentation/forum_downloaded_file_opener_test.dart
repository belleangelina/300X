import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:x300/features/forum/data/forum_attachment_repository.dart';
import 'package:x300/features/forum/presentation/forum_downloaded_file_opener.dart';

void main() {
  late Directory root;
  late File attachmentFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('x300_file_opener_');
    attachmentFile = File(
      path.join(root.path, 'forum-attachments', 'uid-7', 'safe', '资料.pdf'),
    );
    await attachmentFile.parent.create(recursive: true);
    await attachmentFile.writeAsBytes(<int>[1, 2, 3]);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('Android channel 仅接收已解析的缓存绝对路径和安全 MIME', () async {
    Map<String, Object?>? opened;
    final ForumDownloadedFileOpener opener = ForumDownloadedFileOpener(
      platformOverride: 'android',
      cacheDirectoryOverride: () async => root,
      invokeOverride: (Map<String, Object?> arguments) async {
        opened = arguments;
        return null;
      },
    );

    await opener.open(_downloaded(attachmentFile));

    expect(opened, <String, Object?>{
      'filePath': await attachmentFile.resolveSymbolicLinks(),
      'mimeType': 'application/pdf',
    });
    expect(opened!['filePath'], isNot(startsWith('file:')));
  });

  test('Linux 只把本地 file URI 交给系统关联应用', () async {
    Uri? launched;
    final ForumDownloadedFileOpener opener = ForumDownloadedFileOpener(
      platformOverride: 'linux',
      cacheDirectoryOverride: () async => root,
      launchDesktopOverride: (Uri uri) async {
        launched = uri;
        return true;
      },
    );

    await opener.open(_downloaded(attachmentFile));

    expect(launched?.scheme, 'file');
    expect(launched?.toFilePath(), await attachmentFile.resolveSymbolicLinks());
  });

  test('目录外文件、目录外 symlink、缺失文件和无效 MIME 均不会调用平台', () async {
    int calls = 0;
    final ForumDownloadedFileOpener opener = ForumDownloadedFileOpener(
      platformOverride: 'android',
      cacheDirectoryOverride: () async => root,
      invokeOverride: (Map<String, Object?> arguments) async {
        calls++;
        return null;
      },
    );
    final File outside = File(path.join(root.path, 'outside.pdf'));
    await outside.writeAsBytes(<int>[1]);
    final Link link = Link(path.join(attachmentFile.parent.path, 'link.pdf'));
    await link.create(outside.path);

    final List<ForumDownloadedAttachment> invalid = <ForumDownloadedAttachment>[
      _downloaded(outside),
      _downloaded(
        File(path.relative(attachmentFile.path, from: Directory.current.path)),
      ),
      _downloaded(File(link.path)),
      _downloaded(File(path.join(attachmentFile.parent.path, 'missing.pdf'))),
      ForumDownloadedAttachment(
        file: attachmentFile,
        fileName: '资料.pdf',
        mimeType: '../../bad',
        byteLength: 3,
      ),
    ];
    for (final ForumDownloadedAttachment value in invalid) {
      await expectLater(
        opener.open(value),
        throwsA(isA<ForumDownloadedFileOpenException>()),
      );
    }
    expect(calls, 0);
  });

  test('桌面关联应用拒绝或移动 channel 失败时返回统一错误', () async {
    final ForumDownloadedFileOpener desktop = ForumDownloadedFileOpener(
      platformOverride: 'linux',
      cacheDirectoryOverride: () async => root,
      launchDesktopOverride: (Uri uri) async => false,
    );
    await expectLater(
      desktop.open(_downloaded(attachmentFile)),
      throwsA(isA<ForumDownloadedFileOpenException>()),
    );

    final ForumDownloadedFileOpener unsupported = ForumDownloadedFileOpener(
      platformOverride: 'fuchsia',
      cacheDirectoryOverride: () async => root,
    );
    await expectLater(
      unsupported.open(_downloaded(attachmentFile)),
      throwsA(isA<ForumDownloadedFileOpenException>()),
    );
  });
}

ForumDownloadedAttachment _downloaded(File file) {
  return ForumDownloadedAttachment(
    file: file,
    fileName: path.basename(file.path),
    mimeType: 'application/pdf',
    byteLength: 3,
  );
}
