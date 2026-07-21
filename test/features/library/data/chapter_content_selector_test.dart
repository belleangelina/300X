import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/library/data/chapter_content_selector.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

void main()
{
    const ChapterContentSelector selector = ChapterContentSelector();

    test('章节范围包含目标楼层到下一个目录楼层之前', ()
    {
        final ForumThreadPage page = _page();
        final Chapter chapter = _chapter(sourcePid: 101, sourceEndPid: 103);

        final List<PostContentBlock> blocks = selector.select(page, chapter);

        expect(
            blocks.whereType<PostTextBlock>().map(
                (PostTextBlock value) => value.text,
            ),
            <String>['正文一', '幕间'],
        );
    });

    test('按 pid 打开的章节使用目标作者而不依赖当前分页的楼主标记', ()
    {
        final ForumThreadPage page = ForumThreadPage(
            tid: 10,
            board: ForumBoard.lightNovel,
            title: '测试作品',
            uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10'),
            posts: <SourcePost>[
                _post(100, '当前分页首楼', author: '读者甲'),
                _post(
                    101,
                    '第100章正文上',
                    originalPoster: false,
                    author: '译者',
                ),
                _post(102, '读者回复', originalPoster: false, author: '读者乙'),
                _post(
                    103,
                    '第100章正文下',
                    originalPoster: false,
                    author: '译者',
                ),
                _post(
                    104,
                    '第101章正文',
                    originalPoster: false,
                    author: '译者',
                ),
            ],
            currentPage: 34,
            totalPages: 37,
        );

        final List<PostContentBlock> blocks = selector.select(
            page,
            _chapter(sourcePid: 101, sourceEndPid: 104),
        );

        expect(
            blocks.whereType<PostTextBlock>().map(
                (PostTextBlock value) => value.text,
            ),
            <String>['第100章正文上', '第100章正文下'],
        );
    });

    test('仅剩积分标题的受限楼层仍按无正文处理', ()
    {
        final ForumThreadPage page = ForumThreadPage(
            tid: 10,
            board: ForumBoard.lightNovel,
            title: '测试作品',
            uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10'),
            posts: <SourcePost>[
                _postWithBlocks(
                    101,
                    const <PostContentBlock>[
                        PostTextBlock(text: '第83话 我的'),
                        PostTextBlock(text: '（积分100）'),
                    ],
                    originalPoster: false,
                    author: '译者',
                ),
            ],
            currentPage: 23,
            totalPages: 37,
        );

        expect(
            selector.select(page, _chapter(sourcePid: 101)),
            isEmpty,
        );
    });

    test('单帖章节合并全部楼主楼层并排除读者回复', ()
    {
        final List<PostContentBlock> blocks = selector.select(_page(), _chapter());

        expect(
            blocks.whereType<PostTextBlock>().map(
                (PostTextBlock value) => value.text,
            ),
            <String>['目录', '正文一', '幕间', '正文二'],
        );
    });

    test('单楼层 block 范围使用前闭后开且忽略跨楼层终点', ()
    {
        final ForumThreadPage page = ForumThreadPage(
            tid: 10,
            board: ForumBoard.literature,
            title: '测试作品',
            uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10'),
            posts: <SourcePost>[
                _postWithBlocks(101, <PostContentBlock>[
                    const PostTextBlock(text: '第一章', heading: true),
                    const PostTextBlock(text: '第一章正文'),
                    PostImageBlock(
                        uri: Uri.parse('https://bbs.yamibo.com/illustration.jpg'),
                    ),
                    const PostTextBlock(text: '第二章', heading: true),
                    const PostTextBlock(text: '第二章正文'),
                ]),
                _post(102, '下一楼正文'),
                _post(103, '目录中的下一章'),
            ],
            currentPage: 1,
            totalPages: 1,
        );
        final Chapter chapter = _chapter(
            sourcePid: 101,
            sourceEndPid: 103,
            sourceStartBlock: 1,
            sourceEndBlock: 3,
        );

        final List<PostContentBlock> blocks = selector.select(page, chapter);

        expect(blocks, hasLength(2));
        expect((blocks.first as PostTextBlock).text, '第一章正文');
        expect(blocks.last, isA<PostImageBlock>());
    });

    test('block 范围缺少可命中的 sourcePid 或越界时返回空', ()
    {
        expect(
            selector.select(
                _page(),
                _chapter(sourceStartBlock: 0, sourceEndBlock: 1),
            ),
            isEmpty,
        );
        expect(
            selector.select(
                _page(),
                _chapter(sourcePid: 101, sourceStartBlock: 0, sourceEndBlock: 2),
            ),
            isEmpty,
        );
    });

    test('章节含小说正文 quote 时只返回正文块', ()
    {
        final ForumThreadPage page = ForumThreadPage(
            tid: 10,
            board: ForumBoard.lightNovel,
            title: '测试作品',
            uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10'),
            posts: <SourcePost>[
                _postWithBlocks(100, <PostContentBlock>[
                    const PostTextBlock(text: '更新公告'),
                    const PostTextBlock(text: '小说正文', substantiveQuote: true),
                    PostImageBlock(
                        uri: Uri.parse('https://bbs.yamibo.com/illustration.jpg'),
                        substantiveQuote: true,
                    ),
                ]),
            ],
            currentPage: 1,
            totalPages: 1,
        );

        final List<PostContentBlock> blocks = selector.select(page, _chapter());

        expect(blocks, hasLength(2));
        expect((blocks.first as PostTextBlock).text, '小说正文');
        expect(blocks.last, isA<PostImageBlock>());
    });
}

ForumThreadPage _page()
{
    return ForumThreadPage(
        tid: 10,
        board: ForumBoard.literature,
        title: '测试作品',
        uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10'),
        posts: <SourcePost>[
            _post(100, '目录'),
            _post(101, '正文一'),
            _post(102, '幕间'),
            _post(103, '正文二'),
            _post(104, '读者回复', originalPoster: false),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}

SourcePost _post(
    int pid,
    String text,
    {
    bool originalPoster = true,
    String? author,
})
{
    return _postWithBlocks(pid, <PostContentBlock>[
        PostTextBlock(text: text),
    ], originalPoster: originalPoster, author: author);
}

SourcePost _postWithBlocks(
    int pid,
    List<PostContentBlock> blocks,
    {
    bool originalPoster = true,
    String? author,
})
{
    return SourcePost(
        pid: pid,
        tid: 10,
        page: 1,
        floor: pid - 99,
        author: author ?? (originalPoster ? '楼主' : '读者'),
        timeLabel: '',
        isOriginalPoster: originalPoster,
        blocks: blocks,
        links: const <ThreadLink>[],
    );
}

Chapter _chapter({
    int? sourcePid,
    int? sourceEndPid,
    int? sourceStartBlock,
    int? sourceEndBlock,
})
{
    return Chapter(
        id: 'chapter:${sourcePid ?? 0}',
        title: '测试章节',
        sourceUri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10',
        ),
        sourceTid: 10,
        sourcePid: sourcePid,
        sourceEndPid: sourceEndPid,
        sourceStartBlock: sourceStartBlock,
        sourceEndBlock: sourceEndBlock,
    );
}
