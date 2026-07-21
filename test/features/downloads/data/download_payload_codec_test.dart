import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/downloads/data/download_payload_codec.dart';
import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

void main()
{
    test('离线正文可以完整编码和解码', ()
    {
        const DownloadPayloadCodec codec = DownloadPayloadCodec();
        final String value = codec.encode(
            blocks: <PostContentBlock>[
                const PostTextBlock(text: '第一段', heading: true),
                PostImageBlock(
                    uri: Uri.file('/tmp/page300/chapter/image_0001.jpg'),
                    alt: '插图',
                ),
            ],
            referer: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101',
            ),
        );

        final OfflineChapterContent content = codec.decode(value);

        expect(content.blocks, hasLength(2));
        final PostTextBlock text = content.blocks.first as PostTextBlock;
        expect(text.text, '第一段');
        expect(text.heading, isTrue);
        final PostImageBlock image = content.blocks.last as PostImageBlock;
        expect(image.uri.scheme, 'file');
        expect(image.uri.toFilePath(), '/tmp/page300/chapter/image_0001.jpg');
        expect(image.alt, '插图');
        expect(content.referer.host, 'bbs.yamibo.com');
    });

    test('正文结构无效时拒绝解码', ()
    {
        const DownloadPayloadCodec codec = DownloadPayloadCodec();

        expect(
            () => codec.decode('{"referer":"https://bbs.yamibo.com"}'),
            throwsFormatException,
        );
    });
}
