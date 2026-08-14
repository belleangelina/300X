import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_cache_codec.dart';
import 'package:x300/features/forum/domain/forum_announcement_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

void main() {
  const ForumCacheCodec codec = ForumCacheCodec();
  final Uri sourceUri = Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=announcement&id=7',
  );

  test('公告缓存保留只读结构并移除敏感正文数据', () {
    final ForumAnnouncement source = ForumAnnouncement(
      id: 7,
      title: '公告',
      metadataLabel: '时间',
      contentBlocks: <ForumPostContentBlock>[
        ForumPostParagraphBlock(
          inlines: <ForumPostInline>[
            ForumPostLinkInline(
              label: '敏感外链',
              uri: Uri.parse('https://example.org/?token=secret'),
              kind: ForumPostLinkKind.external,
            ),
          ],
        ),
      ],
      messageHtml: '<form>secret</form><p onclick="run()">正文</p>',
      sourceUri: sourceUri,
    );

    final Map<String, dynamic> encoded = codec.encodeAnnouncement(source);
    final ForumAnnouncement decoded = codec.decodeAnnouncement(encoded);

    expect(encoded.toString(), isNot(contains('secret')));
    expect(encoded.toString(), isNot(contains('onclick')));
    expect(decoded.id, 7);
    expect(
      decoded.contentBlocks.single.inlines.single,
      isA<ForumPostTextInline>(),
    );
  });

  test('公告缓存拒绝外域正文资源和错误类型', () {
    final Map<String, dynamic> encoded = codec.encodeAnnouncement(
      ForumAnnouncement(
        id: 7,
        title: '公告',
        metadataLabel: '',
        contentBlocks: const <ForumPostContentBlock>[],
        messageHtml: '',
        sourceUri: sourceUri,
      ),
    );
    encoded['contentBlocks'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'kind': 'paragraph',
        'inlines': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 'image',
            'uri': 'https://evil.example/image.png',
          },
        ],
      },
    ];
    expect(
      () => codec.decodeAnnouncement(encoded),
      throwsA(isA<ForumParseException>()),
    );
    encoded['kind'] = 'thread';
    expect(
      () => codec.decodeAnnouncement(encoded),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('公告缓存拒绝伪装成站内主题的同源正文链接', () {
    final Map<String, dynamic> encoded = codec.encodeAnnouncement(
      ForumAnnouncement(
        id: 7,
        title: '公告',
        metadataLabel: '',
        contentBlocks: const <ForumPostContentBlock>[],
        messageHtml: '',
        sourceUri: sourceUri,
      ),
    );
    encoded['contentBlocks'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'kind': 'paragraph',
        'inlines': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 'link',
            'label': '伪主题',
            'uri': 'https://bbs.yamibo.com/home.php?tid=99',
            'linkKind': 'internalThread',
            'threadId': 99,
          },
        ],
      },
    ];

    expect(
      () => codec.decodeAnnouncement(encoded),
      throwsA(isA<ForumParseException>()),
    );
  });
}
