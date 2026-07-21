import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/library/data/chapter_resolver.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

void main()
{
    const ChapterResolver resolver = ChapterResolver();

    test('明确目录有多个 pid 时以目录为准', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ForumThreadPage page = _page(<ThreadLink>[
            _link('第1章', 101),
            _link('第2章', 102),
        ]);

        final List<Chapter> chapters = resolver.resolve(work, page);

        expect(chapters, hasLength(2));
        expect(chapters.map((Chapter value) => value.sourcePid), <int?>[101, 102]);
        expect(chapters.first.sourceEndPid, 102);
        expect(chapters.last.sourceEndPid, isNull);
    });

    test('漫画目录不会把小说地址收成章节', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _page(<ThreadLink>[
                _chapterThreadLink('第1话', 10),
                _chapterThreadLink('第2话', 11),
                _relatedLink('小说地址', 521519),
            ]),
        );

        expect(result.evidence, ChapterResolutionEvidence.inlineDirectory);
        expect(result.chapters.map((Chapter chapter) => chapter.sourceTid), <int>[
            10,
            11,
        ]);
    });

    test('只有上一章链接时按上一章、当前章排序', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ForumThreadPage page = _page(<ThreadLink>[
            ThreadLink(
                label: '上一章',
                uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9'),
                kind: ThreadLinkKind.previous,
                tid: 9,
            ),
        ]);

        final List<Chapter> chapters = resolver.resolve(work, page);

        expect(chapters, hasLength(2));
        expect(chapters.first.sourceTid, 9);
        expect(chapters.last.sourceTid, 10);
    });

    test('上一章和下一章链接围绕当前主题排序', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ForumThreadPage page = _page(<ThreadLink>[
            ThreadLink(
                label: '上一章',
                uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9'),
                kind: ThreadLinkKind.previous,
                tid: 9,
            ),
            ThreadLink(
                label: '下一章',
                uri: Uri.parse(
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=11',
                ),
                kind: ThreadLinkKind.next,
                tid: 11,
            ),
        ]);

        final List<Chapter> chapters = resolver.resolve(work, page);

        expect(chapters.map((Chapter value) => value.sourceTid), <int>[9, 10, 11]);
    });

    test('明确目录章节覆盖到下一个跳转楼层之前', ()
    {
        final Work work = _work();
        final ForumThreadPage page = _pageWithPosts(<SourcePost>[
            _post(
                pid: 100,
                floor: 1,
                text: '目录',
                links: <ThreadLink>[_link('#2 第一篇', 101), _link('#4 第二篇', 103)],
            ),
            _post(pid: 101, floor: 2, text: '第一篇正文'),
            _post(pid: 102, floor: 3, text: '第一篇幕间'),
            _post(pid: 103, floor: 4, text: '第二篇正文'),
        ]);

        final List<Chapter> chapters = resolver.resolve(work, page);

        expect(chapters.map((Chapter value) => value.title), <String>[
            '第一篇',
            '第二篇',
        ]);
        expect(chapters.first.sourcePid, 101);
        expect(chapters.first.sourceEndPid, 103);
    });

    test('无链接目录的长篇小说按楼主正文楼层形成章节', ()
    {
        final Work work = _work();
        final ForumThreadPage page = _pageWithPosts(<SourcePost>[
            _post(pid: 100, floor: 1, text: '目录：2# 第一章 3# 第二章'),
            _post(pid: 101, floor: 2, text: '《第一章》\n正文内容'.padRight(100, '文')),
            _post(pid: 102, floor: 3, text: '《第二章》\n正文内容'.padRight(100, '文')),
            _post(
                pid: 103,
                floor: 4,
                text: '读者回复'.padRight(100, '回'),
                originalPoster: false,
            ),
        ]);

        final List<Chapter> chapters = resolver.resolve(work, page);

        expect(chapters, hasLength(2));
        expect(chapters.map((Chapter value) => value.title), <String>[
            '第一章',
            '第二章',
        ]);
        expect(chapters.first.sourceEndPid, 102);
        expect(chapters.last.sourceEndPid, isNull);
    });

    test('单楼超长小说跳过目录重复标题并按正文块分章', ()
    {
        final Work work = _work(typeName: '#轻小说');
        final ForumThreadPage page = _pageWithPosts(<SourcePost>[
            SourcePost(
                pid: 100,
                tid: 10,
                page: 1,
                floor: 1,
                author: '楼主',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: <PostContentBlock>[
                    const PostTextBlock(text: '作品说明'),
                    const PostTextBlock(text: 'CONTENTS'),
                    const PostTextBlock(text: '001 开端'),
                    const PostTextBlock(text: '002 重逢'),
                    const PostTextBlock(text: '001 开端'),
                    PostTextBlock(text: '第一章正文'.padRight(700, '文')),
                    const PostTextBlock(text: '002 重逢'),
                    PostTextBlock(text: '第二章正文'.padRight(700, '文')),
                    const PostTextBlock(text: '后记'),
                    PostTextBlock(text: '后记正文'.padRight(300, '文')),
                ],
                links: const <ThreadLink>[],
            ),
        ]);

        final ChapterResolution result = resolver.resolveWithEvidence(work, page);

        expect(result.evidence, ChapterResolutionEvidence.novelBlockSequence);
        expect(result.chapters.map((Chapter chapter) => chapter.title), <String>[
            '001 开端',
            '002 重逢',
            '后记',
        ]);
        expect(
            result.chapters.map((Chapter chapter) => chapter.sourceStartBlock),
            <int?>[4, 6, 8],
        );
        expect(
            result.chapters.map((Chapter chapter) => chapter.sourceEndBlock),
            <int?>[6, 8, 10],
        );
        expect(
            result.chapters.map((Chapter chapter) => chapter.sourcePid).toSet(),
            <int?>{100},
        );
    });

    test('小说本帖 pid 目录与跨帖卷目录分开返回', ()
    {
        final Work work = _work(typeName: '#轻小说');
        final ForumThreadPage page = _pageWithPosts(<SourcePost>[
            _post(
                pid: 100,
                floor: 1,
                text: '目录',
                links: <ThreadLink>[
                    _chapterThreadLink('第一卷', 10),
                    _chapterThreadLink('第二卷', 20),
                    _link('序章', 101),
                    _link('第一章', 102),
                ],
            ),
            _post(pid: 101, floor: 2, text: '序章'.padRight(900, '文')),
            _post(pid: 102, floor: 3, text: '第一章'.padRight(900, '文')),
        ]);

        final ChapterResolution result = resolver.resolveWithEvidence(work, page);

        expect(result.chapters.map((Chapter chapter) => chapter.sourcePid), <int?>[
            101,
            102,
        ]);
        expect(result.relatedThreads, hasLength(2));
        expect(result.relatedThreads.map((ThreadLink link) => link.tid), <int?>[
            10,
            20,
        ]);
    });

    test('小说楼层序列排除短说明和插画楼并优先使用章标题', ()
    {
        final Work work = _work(typeName: '#原创');
        final ForumThreadPage page = _pageWithPosts(<SourcePost>[
            _post(pid: 100, floor: 1, text: '防止翻译撞车，先说明一下更新安排。'.padRight(120, '说')),
            _post(
                pid: 101,
                floor: 2,
                text: '拖更了几天抱歉\n第一章 真正的标题\n正文'.padRight(1200, '文'),
            ),
            SourcePost(
                pid: 102,
                tid: 10,
                page: 1,
                floor: 3,
                author: '楼主',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: <PostContentBlock>[
                    PostTextBlock(text: '更新一张插画'.padRight(150, '图')),
                    PostImageBlock(uri: Uri.parse('https://bbs.yamibo.com/cover.jpg')),
                ],
                links: const <ThreadLink>[],
            ),
            _post(pid: 103, floor: 4, text: '第二章 再会\n正文'.padRight(1000, '文')),
        ]);

        final ChapterResolution result = resolver.resolveWithEvidence(work, page);

        expect(result.evidence, ChapterResolutionEvidence.novelPostSequence);
        expect(result.chapters, hasLength(2));
        expect(result.chapters.map((Chapter chapter) => chapter.title), <String>[
            '第一章 真正的标题',
            '第二章 再会',
        ]);
        expect(result.chapters.first.sourceEndPid, 102);
        expect(result.chapters.last.sourceEndPid, isNull);
    });

    test('小说非作品分类不会按楼主长楼层强行分章', ()
    {
        final Work work = _work(typeName: '#其它');
        final ForumThreadPage page = _pageWithPosts(<SourcePost>[
            _post(pid: 100, floor: 1, text: '作者推荐一'.padRight(900, '荐')),
            _post(pid: 101, floor: 2, text: '作者推荐二'.padRight(900, '荐')),
        ]);

        final ChapterResolution result = resolver.resolveWithEvidence(work, page);

        expect(result.evidence, ChapterResolutionEvidence.none);
        expect(result.chapters, hasLength(1));
    });

    test('细化当前主题目录时保留聚合得到的其他主题章节', ()
    {
        final Work base = _work();
        final Chapter other = Chapter(
            id: 'forum-thread:20',
            title: '第三篇',
            sourceUri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=20',
            ),
            sourceTid: 20,
        );
        final Work work = Work(
            id: 'grouped',
            kind: base.kind,
            title: base.title,
            sourceThreads: base.sourceThreads,
            chapters: <Chapter>[...base.chapters, other],
        );
        final ForumThreadPage page = _page(<ThreadLink>[
            _link('第一篇', 101),
            _link('第二篇', 102),
        ]);

        final List<Chapter> chapters = resolver.resolve(work, page);

        expect(chapters.map((Chapter value) => value.sourceTid), <int>[10, 10, 20]);
    });

    test('楼主后续楼层的单个站内链接不被误判为目录', ()
    {
        final Work work = _work();
        final ForumThreadPage page = _pageWithPosts(<SourcePost>[
            _post(pid: 100, floor: 1, text: '正文'),
            _post(
                pid: 101,
                floor: 2,
                text: '补充说明',
                links: <ThreadLink>[_link('原帖链接', 101)],
            ),
        ]);

        final List<Chapter> chapters = resolver.resolve(work, page);

        expect(chapters, hasLength(1));
        expect(chapters.single.id, 'forum-thread:10');
    });

    test('同一楼层的裸章节号链接簇形成漫画目录', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ForumThreadPage page = _pageWithPosts(<SourcePost>[
            _post(
                pid: 100,
                floor: 1,
                text: '转载说明',
                links: <ThreadLink>[
                    _relatedLink('1', 10),
                    _relatedLink('5前', 105),
                    _relatedLink('27(1)', 127),
                    _relatedLink('04卷', 204),
                ],
            ),
        ]);

        final ChapterResolution result = resolver.resolveWithEvidence(work, page);

        expect(result.evidence, ChapterResolutionEvidence.inlineDirectory);
        expect(result.chapters.map((Chapter value) => value.title), <String>[
            '1',
            '5前',
            '27(1)',
            '04卷',
        ]);
    });

    test('无单位小数范围目录保留多话合一标题和起始顺序', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _page(<ThreadLink>[
                _relatedLink('6.1', 10),
                _relatedLink('6.2~6.4', 102),
                _relatedLink('07', 103),
            ]),
        );

        expect(result.evidence, ChapterResolutionEvidence.inlineDirectory);
        expect(result.chapters.map((Chapter chapter) => chapter.title), <String>[
            '6.1',
            '6.2~6.4',
            '07',
        ]);
        expect(result.chapters.map((Chapter chapter) => chapter.order), <double?>[
            6.1,
            6.2,
            7,
        ]);
    });

    test('全角括号目录章名去除外框且不残留右括号', ()
    {
        final Work work = _work();
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _page(<ThreadLink>[
                _link('【序章】', 101),
                _link('【第一章传送】', 102),
            ]),
        );

        expect(result.chapters.map((Chapter chapter) => chapter.title), <String>[
            '序章',
            '第一章',
        ]);
    });

    test('小说第一部传送等相关链接规范为分卷关系', ()
    {
        final Work work = _work();
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _page(
                <ThreadLink>[
                    _relatedLink('【第一部传送】', 201),
                    _relatedLink('【第二部传送】', 202),
                    _relatedLink('【第三部传送】', 203),
                    _link('【序章】', 101),
                    _link('【第一章】', 102),
                ],
                title:
                        '[轻小说] 【霜月汉化组】[作者]测试作品4 '
                        '【完】（请看一楼，严禁传播资源）',
            ),
        );

        expect(result.relatedThreads.map((ThreadLink link) => link.label), <String>[
            '第一卷',
            '第二卷',
            '第三卷',
            '第4卷',
        ]);
        expect(result.relatedThreads.last.tid, 10);
    });

    test('目录分散在多个楼主楼层时合并而不是只选一个楼层', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ForumThreadPage page = _pageWithPosts(<SourcePost>[
            _post(
                pid: 100,
                floor: 1,
                text: '目录上半段',
                links: <ThreadLink>[_chapterThreadLink('第1话', 10)],
            ),
            _post(
                pid: 200,
                floor: 2,
                text: '目录下半段',
                links: <ThreadLink>[_chapterThreadLink('第2话', 102)],
            ),
        ]);

        final ChapterResolution result = resolver.resolveWithEvidence(work, page);

        expect(result.evidence, ChapterResolutionEvidence.inlineDirectory);
        expect(result.chapters.map((Chapter value) => value.sourceTid), <int>[
            10,
            102,
        ]);
        expect(resolver.hasStrongComicDirectoryEvidence(work, result), isTrue);
    });

    test('短篇集中不同作品的数字标题不作为长篇纠错证据', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _page(<ThreadLink>[
                _chapterThreadLink('其他短篇甲 第1话', 201),
                _chapterThreadLink('其他短篇乙 第2话', 202),
            ]),
        );

        expect(result.evidence, ChapterResolutionEvidence.inlineDirectory);
        expect(resolver.hasStrongComicDirectoryEvidence(work, result), isFalse);
    });

    test('论坛 Tag 目录作为最强证据并提取完整标题中的章节名', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _pageWithPosts(<SourcePost>[]),
            tagDirectoryLinks: <ThreadLink>[
                _chapterThreadLink('[汉化][作者]测试作品 第1话', 10),
                _chapterThreadLink('[汉化][作者]测试作品 第2话', 102),
            ],
        );

        expect(result.evidence, ChapterResolutionEvidence.forumTagDirectory);
        expect(result.chapters.map((Chapter value) => value.title), <String>[
            '第1话',
            '第2话',
        ]);
    });

    test('Tag 目录解析旧式章节号且回退顺序不冲突', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _pageWithPosts(<SourcePost>[]),
            tagDirectoryLinks: <ThreadLink>[
                _chapterThreadLink('【汉化】[作者]大室家 第2话', 10),
                _chapterThreadLink('来投个票吧', 103),
                _chapterThreadLink(
                    '[なもり][大室家01卷 限定版附錄] '
                    '花子様の絵日記帳 p.1-10',
                    104,
                ),
                _chapterThreadLink(
                    '[なもり][大室家01卷 限定版附錄] '
                    '花子様の絵日記帳 p.11-20',
                    105,
                ),
                _chapterThreadLink('[个人改汉][なもり]摇曳百合外传 大室家之三', 106),
            ],
        );

        expect(result.evidence, ChapterResolutionEvidence.forumTagDirectory);
        expect(result.chapters.map((Chapter value) => value.title), <String>[
            '第2话',
            '来投个票吧',
            '花子様の絵日記帳 p.1-10',
            '花子様の絵日記帳 p.11-20',
            '第3话',
        ]);
        expect(
            result.chapters.map((Chapter chapter) => chapter.order).toSet(),
            hasLength(result.chapters.length),
        );
    });

    test('Tag 自身不足两章时不能借内联链接形成权威证据', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _page(<ThreadLink>[_chapterThreadLink('第2话', 102)]),
            tagDirectoryLinks: <ThreadLink>[_chapterThreadLink('第1话', 10)],
        );

        expect(result.evidence, ChapterResolutionEvidence.none);
    });

    test('裸章节号之后的无关作品链接不会混入目录', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _page(<ThreadLink>[
                _relatedLink('1', 10),
                _relatedLink('2', 102),
                _relatedLink('作者其他作品', 999),
            ]),
        );

        expect(result.evidence, ChapterResolutionEvidence.inlineDirectory);
        expect(result.chapters.map((Chapter value) => value.sourceTid), <int>[
            10,
            102,
        ]);
    });

    test('连续同前缀的特别篇跟随数字章节形成目录', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _page(<ThreadLink>[
                _relatedLink('放學後1', 201),
                _chapterThreadLink('放學後2', 10),
                _relatedLink('放學後-kiss的種類-', 202),
                _relatedLink('作者其他作品', 999),
            ]),
        );

        expect(result.evidence, ChapterResolutionEvidence.inlineDirectory);
        expect(result.chapters.map((Chapter chapter) => chapter.sourceTid), <int>[
            201,
            10,
            202,
        ]);
        expect(result.chapters.map((Chapter chapter) => chapter.title), <String>[
            '1',
            '2',
            '放學後-kiss的種類-',
        ]);
    });

    test('Tag 目录移除发布信息并保留子系列名称和目录顺序', ()
    {
        final Uri sourceUri = Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=525121',
        );
        final SourceThread sourceThread = SourceThread(
            tid: 525121,
            board: ForumBoard.comic,
            title: '放學後 2nd season',
            uri: sourceUri,
        );
        final Work work = Work(
            id: 'forum-thread:525121',
            kind: LibraryKind.comic,
            title: '放學後 2nd season',
            sourceThreads: <SourceThread>[sourceThread],
            chapters: <Chapter>[
                Chapter(
                    id: 'forum-thread:525121',
                    title: '正文',
                    sourceUri: sourceUri,
                    sourceTid: 525121,
                ),
            ],
        );
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _pageWithPosts(<SourcePost>[]),
            tagDirectoryLinks: <ThreadLink>[
                _chapterThreadLink('[個人漢化][大島智＆大島永遠]放學後2', 493719),
                _chapterThreadLink('[個人漢化][大島智＆大島永遠]放學後3', 494449),
                _chapterThreadLink('[夜合後援組合作漢化][大島永遠＆大島智]放學後11(42p)', 520459),
                _chapterThreadLink(
                    '[夜合後援組合作漢化][大島永遠＆大島智]'
                    '（放課後 ）放學後 2nd season',
                    525121,
                ),
                _chapterThreadLink(
                    '[夜合後援組X雨田螺丝合作漢化][大島永遠＆大島智]'
                    '（放課後）放學後 Another Story',
                    545969,
                ),
                _chapterThreadLink(
                    '[夜合後援組X雨田螺丝合作漢化][大島永遠＆大島智]'
                    '（放課後）放學後 Another Story 2',
                    546445,
                ),
            ],
        );

        expect(result.evidence, ChapterResolutionEvidence.forumTagDirectory);
        expect(result.chapters.map((Chapter chapter) => chapter.title), <String>[
            '2',
            '3',
            '11(42p)',
            '2nd season',
            'Another Story',
            'Another Story 2',
        ]);
        expect(result.chapters.map((Chapter chapter) => chapter.order), <double?>[
            2,
            3,
            11,
            11.001,
            11.002,
            11.003,
        ]);
    });

    test('Tag 目录精简同作品特典中的发布信息和重复作品名', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _pageWithPosts(<SourcePost>[]),
            tagDirectoryLinks: <ThreadLink>[
                _chapterThreadLink('[夜合後援組](COMIC1☆13)[COCOA BREAK(大島智)]放課後', 491983),
                _chapterThreadLink('[個人漢化][大島智＆大島永遠]放學後2', 10),
                _chapterThreadLink(
                    '除夕快樂 [夜合後援組合作漢化][大島永遠＆大島智]'
                    '放學後-親吻所墜下的場所-(29p)',
                    502113,
                ),
                _chapterThreadLink('[個人漢化][大島智＆大島永遠]放學後3', 494449),
            ],
        );

        expect(result.chapters.map((Chapter chapter) => chapter.title), <String>[
            '放課後',
            '2',
            '除夕快樂 · 親吻所墜下的場所-(29p)',
            '3',
        ]);
    });

    test('重复目录链接去重后不足两章时不形成强目录证据', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ThreadLink duplicate = _chapterThreadLink('第1话', 101);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _pageWithPosts(<SourcePost>[
                _post(
                    pid: 100,
                    floor: 1,
                    text: '目录',
                    links: <ThreadLink>[duplicate, duplicate],
                ),
            ]),
        );

        expect(result.evidence, ChapterResolutionEvidence.none);
    });

    test('漫画目录中不同标签指向同一楼时不伪造多话', ()
    {
        final Work work = _work(kind: LibraryKind.comic);
        final ChapterResolution result = resolver.resolveWithEvidence(
            work,
            _page(<ThreadLink>[
                _link('第2话', 101),
                _link('第3话', 101),
            ]),
        );

        expect(
            result.chapters.where((Chapter chapter) => chapter.sourcePid == 101),
            hasLength(1),
        );
        expect(
            result.chapters.map((Chapter chapter) => chapter.title),
            isNot(contains('第3话')),
        );
        expect(result.evidence, isNot(ChapterResolutionEvidence.inlineDirectory));
    });

    test('小说目录按正文标题拆分同楼多章并区分重复番外编号', ()
    {
        final Work work = _work(typeName: '#轻小说');
        final ForumThreadPage page = _pageWithPosts(<SourcePost>[
            _post(
                pid: 100,
                floor: 1,
                text: '目录',
                links: <ThreadLink>[
                    _link('Bonus track 1', 101),
                    _link('Bonus track 2', 101),
                    _link('Bonus track 5', 105),
                    _link('Bonus track 5', 106),
                    _link('Bonus track 5', 107),
                ],
            ),
            SourcePost(
                pid: 101,
                tid: 10,
                page: 1,
                floor: 2,
                author: '楼主',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: <PostContentBlock>[
                    const PostTextBlock(text: 'Bonus track 01'),
                    const PostTextBlock(text: 'Bonus track 2'),
                    const PostTextBlock(text: 'Bonus track 01 第一篇'),
                    PostTextBlock(text: '第一篇正文'.padRight(400, '文')),
                    const PostTextBlock(text: 'Bonus track 2 第二篇'),
                    PostTextBlock(text: '第二篇正文'.padRight(400, '文')),
                ],
                links: const <ThreadLink>[],
            ),
            _post(
                pid: 105,
                floor: 3,
                text: 'Bonus track 5 - ① 第一部分\n${'正文'.padRight(400, '文')}',
            ),
            _post(
                pid: 106,
                floor: 4,
                text: 'Bonus track 5 - ② 第二部分\n${'正文'.padRight(400, '文')}',
            ),
            _post(
                pid: 107,
                floor: 5,
                text: 'Bonus track 5 - ③ 第三部分\n${'正文'.padRight(400, '文')}',
            ),
        ]);

        final ChapterResolution result = resolver.resolveWithEvidence(work, page);

        expect(result.evidence, ChapterResolutionEvidence.inlineDirectory);
        expect(result.chapters, hasLength(5));
        expect(result.chapters.map((Chapter chapter) => chapter.title), <String>[
            'Bonus track 01 第一篇',
            'Bonus track 2 第二篇',
            'Bonus track 5 - ① 第一部分',
            'Bonus track 5 - ② 第二部分',
            'Bonus track 5 - ③ 第三部分',
        ]);
        expect(result.chapters.map((Chapter chapter) => chapter.order), <double?>[
            900001,
            900002,
            900005,
            900005,
            900005,
        ]);
        expect(
            result.chapters.take(2).map((Chapter chapter) => chapter.sourcePid),
            <int?>[101, 101],
        );
        expect(
            result.chapters.take(2).map(
                (Chapter chapter) => chapter.sourceStartBlock,
            ),
            <int?>[2, 4],
        );
        expect(
            result.chapters.take(2).map(
                (Chapter chapter) => chapter.sourceEndBlock,
            ),
            <int?>[4, 6],
        );
    });
}

Work _work({LibraryKind kind = LibraryKind.novel, String typeName = ''})
{
    final SourceThread thread = SourceThread(
        tid: 10,
        board: kind == LibraryKind.comic ? ForumBoard.comic : ForumBoard.literature,
        title: '测试作品',
        typeName: typeName,
        uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10'),
    );
    return Work(
        id: 'forum-thread:10',
        kind: kind,
        title: '测试作品',
        typeName: typeName,
        sourceThreads: <SourceThread>[thread],
        chapters: <Chapter>[
            Chapter(
                id: 'forum-thread:10',
                title: '正文',
                sourceUri: thread.uri,
                sourceTid: 10,
            ),
        ],
    );
}

ForumThreadPage _page(
    List<ThreadLink> links, {
    String title = '测试作品',
})
{
    return ForumThreadPage(
        tid: 10,
        board: ForumBoard.literature,
        title: title,
        uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10'),
        posts: <SourcePost>[
            SourcePost(
                pid: 100,
                tid: 10,
                page: 1,
                floor: 1,
                author: '楼主',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: const <PostContentBlock>[PostTextBlock(text: '目录')],
                links: links,
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}

ThreadLink _link(String label, int pid)
{
    return ThreadLink(
        label: label,
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=10&pid=$pid',
        ),
        kind: ThreadLinkKind.chapter,
        tid: 10,
        pid: pid,
    );
}

ThreadLink _relatedLink(String label, int tid)
{
    return ThreadLink(
        label: label,
        uri: Uri.parse('https://bbs.yamibo.com/thread-$tid-1-1.html'),
        kind: ThreadLinkKind.related,
        tid: tid,
    );
}

ThreadLink _chapterThreadLink(String label, int tid)
{
    return ThreadLink(
        label: label,
        uri: Uri.parse('https://bbs.yamibo.com/thread-$tid-1-1.html'),
        kind: ThreadLinkKind.chapter,
        tid: tid,
    );
}

ForumThreadPage _pageWithPosts(List<SourcePost> posts)
{
    return ForumThreadPage(
        tid: 10,
        board: ForumBoard.literature,
        title: '测试作品',
        uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10'),
        posts: posts,
        currentPage: 1,
        totalPages: 1,
    );
}

SourcePost _post({
    required int pid,
    required int floor,
    required String text,
    List<ThreadLink> links = const <ThreadLink>[],
    bool originalPoster = true,
})
{
    return SourcePost(
        pid: pid,
        tid: 10,
        page: 1,
        floor: floor,
        author: originalPoster ? '楼主' : '读者',
        timeLabel: '',
        isOriginalPoster: originalPoster,
        blocks: <PostContentBlock>[PostTextBlock(text: text)],
        links: links,
    );
}
