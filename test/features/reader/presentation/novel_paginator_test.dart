import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/library/domain/thread_models.dart';
import 'package:x300/features/reader/presentation/novel_paginator.dart';

void main()
{
    const NovelPaginator paginator = NovelPaginator();

    test('分页不丢失正文、插图和代理对字符', ()
    {
        final String first = '标题😀${List<String>.filled(900, '甲').join()}';
        final String second = List<String>.filled(700, '乙').join();
        final Uri image = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/novel.png',
        );
        final List<NovelPageLayout> pages = paginator.paginate(
            blocks: <PostContentBlock>[
                PostTextBlock(text: first, heading: true),
                PostImageBlock(uri: image),
                PostTextBlock(text: second),
            ],
            width: 420,
            height: 640,
            fontSize: 18,
            lineHeight: 1.8,
            textDirection: TextDirection.ltr,
        );

        final List<PostContentBlock> output = pages
            .expand((NovelPageLayout page) => page.blocks)
            .toList(growable: false);
        final String text = output
            .whereType<PostTextBlock>()
            .map((PostTextBlock block) => block.text)
            .join();
        expect(text, '$first$second');
        expect(
            output.whereType<PostImageBlock>().single.uri,
            image,
        );
        expect(pages.first.startCharacter, 0);
        expect(pages.last.endCharacter, first.length + second.length);
        for (final PostTextBlock block in output.whereType<PostTextBlock>())
        {
            expect(_startsWithLowSurrogate(block.text), isFalse);
            expect(_endsWithHighSurrogate(block.text), isFalse);
        }
    });

    test('窗口变窄或字号变大时会重新排成更多页', ()
    {
        final List<PostContentBlock> blocks = <PostContentBlock>[
            PostTextBlock(
                text: List<String>.filled(3200, '百').join(),
            ),
        ];
        final List<NovelPageLayout> wide = paginator.paginate(
            blocks: blocks,
            width: 900,
            height: 700,
            fontSize: 16,
            lineHeight: 1.6,
            textDirection: TextDirection.ltr,
        );
        final List<NovelPageLayout> narrow = paginator.paginate(
            blocks: blocks,
            width: 400,
            height: 700,
            fontSize: 16,
            lineHeight: 1.6,
            textDirection: TextDirection.ltr,
        );
        final List<NovelPageLayout> largeText = paginator.paginate(
            blocks: blocks,
            width: 900,
            height: 700,
            fontSize: 28,
            lineHeight: 2,
            textDirection: TextDirection.ltr,
        );

        expect(narrow.length, greaterThan(wide.length));
        expect(largeText.length, greaterThan(wide.length));
        expect(
            narrow.map((NovelPageLayout page) => page.startCharacter),
            orderedEquals(
                narrow
                    .map((NovelPageLayout page) => page.startCharacter)
                    .toList()
                    ..sort(),
            ),
        );
    });

    test('极窄页面也不会拆开 emoji 代理对', ()
    {
        final String source = List<String>.filled(20, '😀').join();
        final List<NovelPageLayout> pages = paginator.paginate(
            blocks: <PostContentBlock>[PostTextBlock(text: source)],
            width: 80,
            height: 150,
            fontSize: 40,
            lineHeight: 1.8,
            textDirection: TextDirection.ltr,
        );
        final List<PostTextBlock> blocks = pages
            .expand((NovelPageLayout page) => page.blocks)
            .whereType<PostTextBlock>()
            .toList(growable: false);

        expect(blocks.map((PostTextBlock block) => block.text).join(), source);
        for (final PostTextBlock block in blocks)
        {
            expect(_startsWithLowSurrogate(block.text), isFalse);
            expect(_endsWithHighSurrogate(block.text), isFalse);
        }
    });

    test('分时分页与同步分页生成相同版式', () async
    {
        final Uri image = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/novel.png',
        );
        final List<PostContentBlock> blocks = <PostContentBlock>[
            PostTextBlock(
                text: '标题😀${List<String>.filled(1200, '甲').join()}',
                heading: true,
            ),
            PostImageBlock(uri: image),
            PostTextBlock(text: List<String>.filled(1800, '乙').join()),
        ];
        final List<NovelPageLayout> synchronous = paginator.paginate(
            blocks: blocks,
            width: 420,
            height: 640,
            fontSize: 18,
            lineHeight: 1.8,
            textDirection: TextDirection.ltr,
        );
        final List<NovelPageLayout> incremental =
            await paginator.paginateIncrementally(
                blocks: blocks,
                width: 420,
                height: 640,
                fontSize: 18,
                lineHeight: 1.8,
                textDirection: TextDirection.ltr,
                timeSlice: Duration.zero,
            );

        expect(_layoutSignature(incremental), _layoutSignature(synchronous));
    });

    test('分时分页可以在章节离开后取消', () async
    {
        int cancellationChecks = 0;
        final List<NovelPageLayout> pages =
            await paginator.paginateIncrementally(
                blocks: List<PostContentBlock>.generate(
                    200,
                    (int index) => PostTextBlock(
                        text: List<String>.filled(100, '文').join(),
                    ),
                ),
                width: 420,
                height: 640,
                fontSize: 18,
                lineHeight: 1.8,
                textDirection: TextDirection.ltr,
                timeSlice: Duration.zero,
                isCancelled: () => ++cancellationChecks >= 4,
            );

        expect(pages, isEmpty);
    });
}

List<String> _layoutSignature(List<NovelPageLayout> pages)
{
    return pages.map((NovelPageLayout page)
    {
        final String blocks = page.blocks.map((PostContentBlock block)
        {
            return switch (block)
            {
                PostTextBlock() =>
                    'text:${block.heading}:${block.text}',
                PostImageBlock() => 'image:${block.uri}',
            };
        }).join('|');
        return '${page.startCharacter}:${page.endCharacter}:$blocks';
    }).toList(growable: false);
}

bool _startsWithLowSurrogate(String value)
{
    if (value.isEmpty)
    {
        return false;
    }
    final int codeUnit = value.codeUnitAt(0);
    return codeUnit >= 0xdc00 && codeUnit <= 0xdfff;
}

bool _endsWithHighSurrogate(String value)
{
    if (value.isEmpty)
    {
        return false;
    }
    final int codeUnit = value.codeUnitAt(value.length - 1);
    return codeUnit >= 0xd800 && codeUnit <= 0xdbff;
}
