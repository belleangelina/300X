import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/forum/application/forum_attachment_download_controller.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/forum/presentation/forum_read_widgets.dart';
import 'package:x300/features/reader/data/reader_media_repository.dart';
import 'package:x300/shared/presentation/forum_image.dart';

class _MockReaderMediaRepository extends Mock
    implements ReaderMediaRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://bbs.yamibo.com/image.png'));
  });

  testWidgets('结构化正文展示样式、引用、代码、表情和内嵌图', (WidgetTester tester) async {
    final Uri imageUri = Uri.parse(
      'https://bbs.yamibo.com/data/attachment/forum/page.png',
    );
    final Uri emoticonUri = Uri.parse(
      'https://bbs.yamibo.com/static/image/smiley/smile.gif',
    );
    final Uri linkUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=200&mobile=2',
    );
    final _MockReaderMediaRepository media = _MockReaderMediaRepository();
    when(() => media.peek(any())).thenReturn(Uri.file('/tmp/cached.png'));
    ForumPostLinkInline? opened;
    final ForumPost post = ForumPost(
      id: 10,
      threadId: 100,
      floor: 1,
      author: '作者',
      timeLabel: '',
      messageHtml: '<p>旧 HTML 不应显示</p>',
      uri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&mobile=2#pid10',
      ),
      contentBlocks: <ForumPostContentBlock>[
        ForumPostParagraphBlock(
          inlines: <ForumPostInline>[
            const ForumPostTextInline(text: '普通 '),
            const ForumPostTextInline(text: '粗体', bold: true),
            const ForumPostTextInline(text: ' 斜体', italic: true),
            const ForumPostLineBreakInline(),
            ForumPostImageInline(uri: emoticonUri, alt: '笑脸', isEmoticon: true),
            ForumPostLinkInline(
              label: '站内主题',
              uri: linkUri,
              kind: ForumPostLinkKind.internalThread,
              threadId: 200,
            ),
          ],
        ),
        const ForumPostQuoteBlock(
          inlines: <ForumPostInline>[ForumPostTextInline(text: '引用内容')],
        ),
        const ForumPostCodeBlock(
          inlines: <ForumPostInline>[
            ForumPostTextInline(text: 'print(value);', code: true),
          ],
        ),
        ForumPostParagraphBlock(
          inlines: <ForumPostInline>[
            ForumPostImageInline(uri: imageUri, alt: '内嵌图片'),
          ],
        ),
      ],
      attachments: <ForumAttachment>[
        ForumAttachment(name: '重复图片', uri: imageUri, isImage: true),
      ],
      comments: const <ForumPostComment>[
        ForumPostComment(
          id: 81,
          threadId: 100,
          postId: 10,
          authorId: 8,
          author: '点评用户',
          timeLabel: '刚刚',
          contentBlocks: <ForumPostContentBlock>[
            ForumPostParagraphBlock(
              inlines: <ForumPostInline>[ForumPostTextInline(text: '原生点评正文')],
            ),
          ],
        ),
      ],
      ratingSummary: const ForumPostRatingSummary(
        participantCount: 2,
        totals: <ForumPostRatingScore>[
          ForumPostRatingScore(credit: '积分', value: 6),
        ],
        entries: <ForumPostRatingEntry>[
          ForumPostRatingEntry(
            authorId: 9,
            author: '评分用户',
            scores: <ForumPostRatingScore>[
              ForumPostRatingScore(credit: '积分', value: 5),
            ],
            reason: '很喜欢',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [readerMediaRepositoryProvider.overrideWithValue(media)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ForumPostContent(
                post: post,
                onOpenLink: (ForumPostLinkInline value) => opened = value,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('旧 HTML 不应显示'), findsNothing);
    expect(find.textContaining('引用内容'), findsOneWidget);
    expect(find.textContaining('print(value);'), findsOneWidget);
    expect(find.byType(ForumImage), findsNWidgets(2));
    expect(
      find.byKey(ValueKey<String>('forum-inline-image-$imageUri')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('forum-inline-emoticon-$emoticonUri')),
      findsOneWidget,
    );
    expect(find.text('重复图片'), findsNothing);
    expect(find.text('点评 1'), findsOneWidget);
    expect(find.text('点评用户 · 刚刚'), findsOneWidget);
    expect(find.textContaining('原生点评正文'), findsOneWidget);
    expect(find.text('评分 · 2 人'), findsOneWidget);
    expect(find.text('积分 +6'), findsOneWidget);
    expect(find.text('评分用户'), findsOneWidget);
    expect(find.text('积分 +5'), findsOneWidget);
    expect(find.text('很喜欢'), findsOneWidget);
    expect(find.text('查看全部'), findsNothing);

    final List<TextSpan> spans = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .expand(
          (SelectableText value) => value.textSpan?.children ?? <InlineSpan>[],
        )
        .whereType<TextSpan>()
        .toList(growable: false);
    expect(
      spans
          .singleWhere((TextSpan value) => value.text == '粗体')
          .style
          ?.fontWeight,
      FontWeight.bold,
    );
    expect(
      spans
          .singleWhere((TextSpan value) => value.text == ' 斜体')
          .style
          ?.fontStyle,
      FontStyle.italic,
    );

    await tester.tap(find.text('站内主题'));
    expect(opened?.threadId, 200);
  });

  testWidgets('评分组件仅在调用方提供可靠入口时允许查看全部', (WidgetTester tester) async {
    bool opened = false;
    const ForumPostRatingSummary summary = ForumPostRatingSummary(
      participantCount: 3,
      totals: <ForumPostRatingScore>[
        ForumPostRatingScore(credit: '积分', value: 11),
      ],
      entries: <ForumPostRatingEntry>[
        ForumPostRatingEntry(
          authorId: 9,
          author: '评分用户',
          scores: <ForumPostRatingScore>[
            ForumPostRatingScore(credit: '积分', value: 5),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumPostRatings(
            summary: summary,
            onViewAll: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('查看全部'), findsOneWidget);
    await tester.tap(find.text('查看全部'));
    expect(opened, isTrue);
  });

  testWidgets('模型附件显示原生进度、取消和失败重试，不影响图片正文路径', (WidgetTester tester) async {
    final Uri fileUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=attachment&aid=7',
    );
    final Uri imageUri = Uri.parse(
      'https://bbs.yamibo.com/data/attachment/forum/image.png',
    );
    final ForumAttachment file = ForumAttachment(
      name: '资料.zip',
      uri: fileUri,
      sizeLabel: '128 KB',
    );
    final ForumPost post = ForumPost(
      id: 9,
      threadId: 8,
      floor: 1,
      author: '作者',
      timeLabel: '',
      messageHtml: '',
      uri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=8&mobile=2#pid9',
      ),
      attachments: <ForumAttachment>[
        file,
        ForumAttachment(name: '正文图片', uri: imageUri, isImage: true),
      ],
    );
    ForumAttachment? opened;
    ForumAttachment? cancelled;
    ForumAttachmentDownloadState state = const ForumAttachmentDownloadState(
      phase: ForumAttachmentDownloadPhase.downloading,
      received: 65536,
      total: 131072,
    );
    late StateSetter update;
    final _MockReaderMediaRepository media = _MockReaderMediaRepository();
    when(() => media.peek(any())).thenReturn(Uri.file('/tmp/image.png'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [readerMediaRepositoryProvider.overrideWithValue(media)],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                update = setState;
                return ForumPostContent(
                  post: post,
                  onOpenAttachment: (ForumAttachment value) => opened = value,
                  onCancelAttachment: (ForumAttachment value) =>
                      cancelled = value,
                  attachmentState: (ForumAttachment value) =>
                      value.uri == fileUri ? state : null,
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ForumImage), findsOneWidget);
    expect(
      find.byKey(ValueKey<String>('forum-attachment-progress-$fileUri')),
      findsOneWidget,
    );
    final CircularProgressIndicator progress = tester.widget(
      find.byKey(ValueKey<String>('forum-attachment-progress-$fileUri')),
    );
    expect(progress.value, 0.5);
    await tester.tap(
      find.byKey(ValueKey<String>('forum-attachment-cancel-$fileUri')),
    );
    expect(cancelled, same(file));
    expect(opened, isNull);

    update(() {
      state = const ForumAttachmentDownloadState(
        phase: ForumAttachmentDownloadPhase.failed,
        message: '附件下载失败，请稍后重试',
      );
    });
    await tester.pump();
    expect(find.text('附件下载失败，请稍后重试'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey<String>('forum-attachment-$fileUri')));
    expect(opened, same(file));
  });
}
