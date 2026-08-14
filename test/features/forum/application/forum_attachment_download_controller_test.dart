import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/forum/application/forum_attachment_download_controller.dart';
import 'package:x300/features/forum/data/forum_attachment_repository.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/forum/presentation/forum_downloaded_file_opener.dart';

class _MockAttachmentRepository extends Mock
    implements ForumAttachmentRepository {}

class _MockFileOpener extends Mock implements ForumDownloadedFileOpener {}

void main() {
  late _MockAttachmentRepository repository;
  late _MockFileOpener opener;
  late ProviderContainer container;
  late ForumAttachment attachment;
  late Uri topicUri;
  late Directory root;
  late File downloadedFile;
  late ForumDownloadedAttachment downloaded;

  setUpAll(() {
    registerFallbackValue(
      ForumAttachment(
        name: 'fallback',
        uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=attachment&aid=1'),
      ),
    );
    registerFallbackValue(Uri.parse('https://bbs.yamibo.com/'));
    registerFallbackValue(CancelToken());
    registerFallbackValue(
      ForumDownloadedAttachment(
        file: File('/tmp/fallback'),
        fileName: 'fallback',
        mimeType: 'application/octet-stream',
        byteLength: 0,
      ),
    );
  });

  setUp(() {
    repository = _MockAttachmentRepository();
    opener = _MockFileOpener();
    container = ProviderContainer(
      overrides: [
        forumAttachmentRepositoryProvider.overrideWithValue(repository),
        forumDownloadedFileOpenerProvider.overrideWithValue(opener),
      ],
    );
    addTearDown(container.dispose);
    attachment = ForumAttachment(
      name: '资料.pdf',
      uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=attachment&aid=7'),
    );
    topicUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9&mobile=2',
    );
    root = Directory.systemTemp.createTempSync('x300_attachment_controller_');
    downloadedFile = File('${root.path}/forum-attachments/uid-1/资料.pdf');
    downloadedFile.parent.createSync(recursive: true);
    downloadedFile.writeAsBytesSync(const <int>[1, 2, 3]);
    downloaded = ForumDownloadedAttachment(
      file: downloadedFile,
      fileName: '资料.pdf',
      mimeType: 'application/pdf',
      byteLength: 131072,
    );
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
  });

  test('同目标只启动一次下载，进度完成后调用本地 opener', () async {
    when(
      () => repository.download(
        any(),
        topicSourceUri: any(named: 'topicSourceUri'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((Invocation invocation) async {
      final ForumAttachmentProgress progress =
          invocation.namedArguments[#onProgress] as ForumAttachmentProgress;
      progress(65536, 131072);
      progress(131072, 131072);
      return downloaded;
    });
    when(() => opener.open(any())).thenAnswer((_) async {});
    final ForumAttachmentDownloadController controller = container.read(
      forumAttachmentDownloadControllerProvider.notifier,
    );

    final Future<void> first = controller.downloadAndOpen(
      attachment,
      topicSourceUri: topicUri,
    );
    final Future<void> second = controller.downloadAndOpen(
      attachment,
      topicSourceUri: topicUri,
    );
    await Future.wait(<Future<void>>[first, second]);

    verify(
      () => repository.download(
        attachment,
        topicSourceUri: topicUri,
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(1);
    verify(() => opener.open(downloaded)).called(1);
    final ForumAttachmentDownloadState state = container.read(
      forumAttachmentDownloadControllerProvider,
    )[ForumAttachmentDownloadController.keyFor(attachment.uri)]!;
    expect(state.phase, ForumAttachmentDownloadPhase.ready);
    expect(state.progress, 1);
  });

  test('取消递增世代，旧完成结果不得覆盖 UI 或打开文件', () async {
    final Completer<ForumDownloadedAttachment> completer =
        Completer<ForumDownloadedAttachment>();
    when(
      () => repository.download(
        any(),
        topicSourceUri: any(named: 'topicSourceUri'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) => completer.future);
    final ForumAttachmentDownloadController controller = container.read(
      forumAttachmentDownloadControllerProvider.notifier,
    );
    final Future<void> operation = controller.downloadAndOpen(
      attachment,
      topicSourceUri: topicUri,
    );
    await Future<void>.delayed(Duration.zero);

    controller.cancel(attachment.uri);
    completer.complete(downloaded);
    await operation;

    final ForumAttachmentDownloadState state = container.read(
      forumAttachmentDownloadControllerProvider,
    )[ForumAttachmentDownloadController.keyFor(attachment.uri)]!;
    expect(state.phase, ForumAttachmentDownloadPhase.failed);
    expect(state.message, contains('已取消'));
    verifyNever(() => opener.open(any()));
  });

  test('打开失败保留已下载文件，重试不再次下载', () async {
    when(
      () => repository.download(
        any(),
        topicSourceUri: any(named: 'topicSourceUri'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => downloaded);
    when(
      () => opener.open(any()),
    ).thenThrow(const ForumDownloadedFileOpenException());
    final ForumAttachmentDownloadController controller = container.read(
      forumAttachmentDownloadControllerProvider.notifier,
    );

    await controller.downloadAndOpen(attachment, topicSourceUri: topicUri);
    await controller.downloadAndOpen(attachment, topicSourceUri: topicUri);

    verify(
      () => repository.download(
        attachment,
        topicSourceUri: topicUri,
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(1);
    verify(() => opener.open(downloaded)).called(2);
    final ForumAttachmentDownloadState state = container.read(
      forumAttachmentDownloadControllerProvider,
    )[ForumAttachmentDownloadController.keyFor(attachment.uri)]!;
    expect(state.downloaded, downloaded);
    expect(state.message, contains('没有可用'));
  });

  test('本地文件被清理后点按会重新下载', () async {
    when(
      () => repository.download(
        any(),
        topicSourceUri: any(named: 'topicSourceUri'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => downloaded);
    when(() => opener.open(any())).thenAnswer((_) async {});
    final ForumAttachmentDownloadController controller = container.read(
      forumAttachmentDownloadControllerProvider.notifier,
    );

    await controller.downloadAndOpen(attachment, topicSourceUri: topicUri);
    await downloadedFile.delete();
    await controller.downloadAndOpen(attachment, topicSourceUri: topicUri);

    verify(
      () => repository.download(
        attachment,
        topicSourceUri: topicUri,
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(2);
  });
}
