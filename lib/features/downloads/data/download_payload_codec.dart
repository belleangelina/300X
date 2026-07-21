import 'dart:convert';

import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

class DownloadPayloadCodec
{
    const DownloadPayloadCodec();

    String encode({
        required List<PostContentBlock> blocks,
        required Uri referer,
    })
    {
        return jsonEncode(<String, Object?>{
            'referer': referer.toString(),
            'blocks': blocks.map((PostContentBlock block)
            {
                return switch (block)
                {
                    PostTextBlock() => <String, Object?>{
                        'type': 'text',
                        'text': block.text,
                        'heading': block.heading,
                    },
                    PostImageBlock() => <String, Object?>{
                        'type': 'image',
                        'uri': block.uri.toString(),
                        'alt': block.alt,
                    },
                };
            }).toList(growable: false),
        });
    }

    OfflineChapterContent decode(String value)
    {
        final Object? decoded = jsonDecode(value);
        if (decoded is! Map<String, dynamic>)
        {
            throw const FormatException('离线章节格式无效');
        }
        final Object? blocksValue = decoded['blocks'];
        if (blocksValue is! List<dynamic>)
        {
            throw const FormatException('离线章节缺少正文');
        }
        final List<PostContentBlock> blocks = <PostContentBlock>[];
        for (final Object? value in blocksValue)
        {
            if (value is! Map<String, dynamic>)
            {
                continue;
            }
            switch (value['type'])
            {
                case 'text':
                    blocks.add(PostTextBlock(
                        text: value['text']?.toString() ?? '',
                        heading: value['heading'] == true,
                    ));
                case 'image':
                    final String uri = value['uri']?.toString() ?? '';
                    if (uri.isNotEmpty)
                    {
                        blocks.add(PostImageBlock(
                            uri: Uri.parse(uri),
                            alt: value['alt']?.toString() ?? '',
                        ));
                    }
            }
        }
        return OfflineChapterContent(
            blocks: blocks,
            referer: Uri.parse(decoded['referer']?.toString() ?? ''),
        );
    }
}
