import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/forum/data/forum_attachment_repository.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/domain/forum_models.dart' as domain;
import 'package:x300/features/forum/presentation/forum_downloaded_file_opener.dart';
import 'package:x300/features/forum/presentation/forum_topic_page.dart';

class _MockReadRepository extends Mock implements ForumReadRepository {}

class _MockAttachmentRepository extends Mock
    implements ForumAttachmentRepository {}

class _MockFileOpener extends Mock implements ForumDownloadedFileOpener {}

void main() {
  late _MockReadRepository readRepository;
  late _MockAttachmentRepository attachmentRepository;
  late _MockFileOpener opener;
  late Uri topicUri;
  late Uri attachmentUri;
  late domain.ForumAttachment attachment;
  late domain.ForumThreadPage page;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://bbs.yamibo.com/'));
    registerFallbackValue(CancelToken());
    registerFallbackValue(
      domain.ForumAttachment(
        name: 'fallback',
        uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=attachment&aid=1'),
      ),
    );
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
    readRepository = _MockReadRepository();
    attachmentRepository = _MockAttachmentRepository();
    opener = _MockFileOpener();
    topicUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=2&mobile=2',
    );
    attachmentUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=attachment&aid=7',
    );
    attachment = domain.ForumAttachment(
      name: '资料.pdf',
      uri: attachmentUri,
      sizeLabel: '128 KB',
    );
    page = domain.ForumThreadPage(
      thread: domain.ForumThread(
        id: 100,
        boardId: 41,
        title: '测试主题',
        uri: topicUri,
      ),
      posts: <domain.ForumPost>[
        domain.ForumPost(
          id: 201,
          threadId: 100,
          floor: 1,
          author: '作者',
          timeLabel: '',
          messageHtml: '<p>正文</p>',
          uri: topicUri.replace(fragment: 'pid201'),
          attachments: <domain.ForumAttachment>[attachment],
        ),
      ],
      readingOptions: const <domain.ForumRouteOption>[],
      cursor: domain.ForumPageCursor(
        currentPage: 2,
        totalPages: 2,
        sourceUri: topicUri,
      ),
      focusedPostId: 201,
    );
    when(
      () => readRepository.loadThreadAtPost(threadId: 100, postId: 201),
    ).thenAnswer((_) async => page);
  });

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        forumReadRepositoryProvider.overrideWithValue(readRepository),
        forumAttachmentRepositoryProvider.overrideWithValue(
          attachmentRepository,
        ),
        forumDownloadedFileOpenerProvider.overrideWithValue(opener),
      ],
      child: MaterialApp(
        home: ForumTopicPage(
          thread: domain.ForumThreadSummary(
            id: 100,
            boardId: 41,
            title: '测试主题',
            uri: topicUri,
          ),
          focusedPostId: 201,
        ),
      ),
    );
  }

  testWidgets('主题模型附件走认证仓库，显示进度并以当前 sourceUri 打开本地文件', (
    WidgetTester tester,
  ) async {
    final Completer<ForumDownloadedAttachment> completer =
        Completer<ForumDownloadedAttachment>();
    ForumAttachmentProgress? progress;
    when(
      () => attachmentRepository.download(
        any(),
        topicSourceUri: any(named: 'topicSourceUri'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((Invocation invocation) {
      progress =
          invocation.namedArguments[#onProgress] as ForumAttachmentProgress;
      return completer.future;
    });
    when(() => opener.open(any())).thenAnswer((_) async {});

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('资料.pdf'));
    await tester.pump();
    progress!(65536, 131072);
    await tester.pump();

    expect(
      find.byKey(ValueKey<String>('forum-attachment-progress-$attachmentUri')),
      findsOneWidget,
    );
    verify(
      () => attachmentRepository.download(
        attachment,
        topicSourceUri: topicUri,
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(1);

    final ForumDownloadedAttachment downloaded = ForumDownloadedAttachment(
      file: File('/tmp/downloaded.pdf'),
      fileName: '资料.pdf',
      mimeType: 'application/pdf',
      byteLength: 131072,
    );
    completer.complete(downloaded);
    await tester.pumpAndSettle();
    verify(() => opener.open(downloaded)).called(1);
    expect(find.text('下载完成'), findsOneWidget);
  });

  testWidgets('模型附件失败在原位展示且不会退回浏览器下载', (WidgetTester tester) async {
    when(
      () => attachmentRepository.download(
        any(),
        topicSourceUri: any(named: 'topicSourceUri'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenThrow(const ForumAttachmentDownloadException('论坛附件地址不安全'));

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('资料.pdf'));
    await tester.pump();

    expect(find.text('论坛附件地址不安全'), findsOneWidget);
    verifyNever(() => opener.open(any()));
  });
}
