import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/library/data/title_normalizer.dart';
import 'package:x300/features/library/data/work_aggregator.dart';
import 'package:x300/features/library/domain/library_models.dart';

void main()
{
    const TitleNormalizer normalizer = TitleNormalizer();
    const WorkAggregator aggregator = WorkAggregator();

    test('只对同作品键和结构化章节号执行聚合', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(1, '[个人汉化](犬兎ねこ)邻座那个朴素的女孩 第70话'),
            _thread(2, '[个人汉化](犬兎ねこ)邻座那个朴素的女孩 第71话'),
            _thread(3, '邻座那个朴素的女孩 外传'),
        ]);

        expect(works, hasLength(2));
        expect(works.first.chapters, hasLength(2));
        expect(works.first.chapters[0].title, '第70话');
        expect(works.first.chapters[1].title, '第71话');
        expect(works.last.id, 'forum-thread:3');
    });

    test('版本标记和分类冲突不会合并', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(10, '同名作品 WEB版 第1章', typeId: 1),
            _thread(11, '同名作品 单行本 第2章', typeId: 1),
            _thread(12, '同名作品 WEB版 第3章', typeId: 2),
        ]);

        expect(works, hasLength(3));
        expect(works.every((Work value) => value.chapters.length == 1), isTrue);
    });

    test('目录帖标题中的更新至不被误判为单章', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '[無銘]测试作品 第二部（6.27更新至第48话）',
        );

        expect(title.hasChapterMarker, isFalse);
        expect(title.displayTitle, '测试作品 第二部');
        expect(title.versionMarker, '第二部');
    });

    test('搜索结果中的裸章节号和不同发布组标签可聚合', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(20, '[个人汉化] [入間人間×柚原もけ] 安达与岛村 24', typeId: null),
            _thread(21, '【才不×提灯喵×绿茶】[入間人間×柚原もけ]安达与岛村 12.5', typeId: null),
            _thread(22, '[个人汉化] [入間人間×柚原もけ] 安达与岛村 16', typeId: null),
            _thread(23, '[个人汉化] [入間人間×柚原もけ] 安达与岛村 13（附单行本1卷蜜瓜特典）', typeId: null),
            _thread(24, '[个人汉化] [入間人間×柚原もけ] 安达与岛村 05 后篇', typeId: null),
            _thread(
                25,
                '[个人汉化] [入間人間×柚原もけ] '
                '安达与岛村 30.5 ＆ 单行本5卷附录',
                typeId: null,
            ),
        ]);

        expect(works, hasLength(1));
        expect(works.single.title, '安达与岛村');
        expect(works.single.chapters.map((Chapter value) => value.title), <String>[
                '05 后篇',
                '12.5',
                '13(附单行本1卷蜜瓜特典)',
                '16',
                '24',
                '30.5 单行本5卷附录',
        ]);
    });

    test('章节号后的副标题保留在章节名但不进入作品键', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(30, '【星愿汉化组】【紫のあ】无法向星星许愿的恋情 22话 我的青梅竹马'),
            _thread(31, '【星愿汉化组】【紫のあ】无法向星星许愿的恋情 23话 夏日'),
        ]);

        expect(works, hasLength(1));
        expect(works.single.title, '无法向星星许愿的恋情');
        expect(works.single.chapters.first.title, '22话 我的青梅竹马');
        expect(works.single.chapters.last.title, '23话 夏日');
    });

    test('作者括号前后发布标签变化时跨楼主仍聚合为同一作品', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(
                562803,
                '【タチ】認真少女與青春內衣1-2话 Kakukuroi汉化组',
                author: '上传者甲',
            ),
            _thread(
                567557,
                '【Kakukuroi汉化组】【タチ】認真少女與青春內衣 第6话',
                author: '上传者乙',
            ),
            _thread(
                571663,
                '【タチ】認真少女與青春內衣 第12话 Kakukuroi汉化组',
                author: '上传者甲',
            ),
        ]);

        expect(works, hasLength(1));
        expect(works.single.title, '認真少女與青春內衣');
        expect(
            works.single.chapters.map((Chapter chapter) => chapter.order),
            <double?>[1, 6, 12],
        );
        expect(works.single.directories, hasLength(2));
    });

    test('英文作品的裸章节号和副标题可以聚合', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(40, '[百合會][百合姫][サブロウタ]Citrus 01- Love Affair', typeId: null),
            _thread(
                41,
                '[百合會][百合姫][サブロウタ]Citrus 02- One\'s first love',
                typeId: null,
            ),
        ]);

        expect(works, hasLength(1));
        expect(works.single.title, 'Citrus');
        expect(works.single.chapters.map((Chapter value) => value.title), <String>[
            '01 Love Affair',
            '02 One\'s first love',
        ]);
    });

    test('方括号和圆括号混排的发布信息不会进入作品键', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '[片羽汉化组][百合姬 Vol.47]（授权汉化）[サブロウタ]'
            'Citrus 14-the course of love',
        );

        expect(title.displayTitle, 'Citrus');
        expect(title.chapterLabel, '14 the course of love');
        expect(title.workKey, contains('author=サブロウタ'));
    });

    test('标题中的加号区分正篇和续篇', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(50, '[汉化][作者]Citrus 06-Under Lover', typeId: null),
            _thread(51, '[汉化][作者]citrus+ 第6话', typeId: null),
        ]);

        expect(works, hasLength(2));
        expect(works.map((Work value) => value.title).toSet(), <String>{
            'Citrus',
            'citrus+',
        });
    });

    test('同一数字章节的重制帖只保留较新来源', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(60, '[旧版][作者]测试作品 10-旧版', postedAt: DateTime(2020)),
            _thread(61, '[重制版][作者]测试作品 10-重制版', postedAt: DateTime(2021)),
            _thread(62, '[汉化][作者]测试作品 11-后续'),
        ]);

        expect(works, hasLength(1));
        expect(works.single.sourceThreads, hasLength(3));
        expect(works.single.chapters.map((Chapter value) => value.title), <String>[
            '10 重制版',
            '11 后续',
        ]);
        expect(works.single.chapters.first.sourceTid, 61);
    });

    test('同一话的其之一和其之二作为分段而不是重制帖保留', ()
    {
        final Work work = aggregator.aggregate(<SourceThread>[
            _thread(
                562706,
                '[汉化][作者]关于女儿带了女朋友回来这档事 '
                '第1话「我会狠狠推你们的」其之1',
                author: '白咲星空',
            ),
            _thread(
                562722,
                '[汉化][作者]关于女儿带了女朋友回来这档事 '
                '第1话「我会狠狠推你们的」其之2',
                author: '白咲星空',
            ),
        ]).single;

        expect(work.directories.single.chapters, hasLength(2));
        expect(
            work.chapters.map((Chapter chapter) => chapter.title),
            <String>[
                '第1话 「我会狠狠推你们的」其之1',
                '第1话 「我会狠狠推你们的」其之2',
            ],
        );
    });

    test('多个独立番外保留并显示可区分的章节名', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(70, '[汉化][作者]测试作品 第1话'),
            _thread(71, '[汉化][作者]测试作品 番外篇'),
            _thread(72, '[汉化][作者]测试作品 番外篇'),
        ]);

        expect(works, hasLength(1));
        expect(works.single.chapters.map((Chapter value) => value.title), <String>[
            '第1话',
            '番外篇 1',
            '番外篇 2',
        ]);
    });

    test('相同搜索全集从不同帖子入口得到同一作品和目录', ()
    {
        final List<SourceThread> threads = <SourceThread>[
            _thread(80, '[汉化][作者]长篇作品 01-开始'),
            _thread(81, '[汉化][作者]长篇作品 02-继续'),
            _thread(82, '[汉化][作者]长篇作品 03-结尾'),
        ];

        final Work forward = aggregator.aggregate(threads).single;
        final Work reversed = aggregator
                .aggregate(threads.reversed.toList())
                .single;

        expect(reversed.id, forward.id);
        expect(
            reversed.chapters.map((Chapter value) => value.sourceTid),
            forward.chapters.map((Chapter value) => value.sourceTid),
        );
    });

    test('创作者标记缺失时并入唯一同名作品', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(83, '【提灯喵汉化组】[あおのなち]与你相恋到生命尽头 第1话', author: '提灯喵', typeId: null),
            _thread(84, '[个人汉化]与你相恋到生命尽头 第2话', author: '个人译者', typeId: null),
        ]);

        expect(works, hasLength(1));
        expect(works.single.directories, hasLength(2));
        expect(
            works.single.directories.map((WorkDirectory value) => value.owner),
            <String>['个人译者', '提灯喵'],
        );
        expect(
            works.single.directories
                    .expand((WorkDirectory value) => value.chapters)
                    .map((Chapter value) => value.sourceTid)
                    .toSet(),
            <int>{83, 84},
        );
        expect(works.single.primarySourceThread.author, works.single.author);
    });

    test('智能目录优先完整来源并只从其它来源补缺章', ()
    {
        final Work work = aggregator.aggregate(<SourceThread>[
            _thread(101, '[汉化][作者]智能作品 第1话', author: '楼主甲'),
            _thread(102, '[汉化][作者]智能作品 第2话', author: '楼主甲'),
            _thread(104, '[汉化][作者]智能作品 第4话', author: '楼主甲'),
            _thread(202, '[汉化][作者]智能作品 第2话', author: '楼主乙'),
            _thread(203, '[汉化][作者]智能作品 第3话', author: '楼主乙'),
        ]).single;

        expect(work.directories, hasLength(2));
        expect(
            work.chapters.map((Chapter chapter) => chapter.sourceTid),
            <int>[101, 102, 203, 104],
        );
    });

    test('不同非空创作者标记的同名作品不合并', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(85, '[汉化][作者甲]同名作品 第1话', typeId: null),
            _thread(86, '[汉化][作者乙]同名作品 第2话', typeId: null),
        ]);

        expect(works, hasLength(2));
    });

    test('带编号番外归属正篇且活动届次不占用正文章节号', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(87, '[汉化][作者]怎样才能成为发小的女友呢 第1话'),
            _thread(88, '[汉化][作者]怎样才能成为发小的女友呢 番外1'),
            _thread(89, '[汉化][作者]怎样才能成为发小的女友呢 第17话'),
            _thread(
                90,
                '[汉化][作者]怎样才能成为发小的女友呢 '
                '第17回メロンブックス漫画祭り小册子',
            ),
        ]);

        expect(works, hasLength(1));
        expect(works.single.chapters.map((Chapter value) => value.title), <String>[
            '第1话',
            '第17话',
            '第17回 メロンブックス漫画祭り小册子',
            '番外1',
        ]);
        expect(works.single.chapters.map((Chapter value) => value.order), <double?>[
            1,
            17,
            800000,
            900001,
        ]);
    });

    test('中文章节号和末尾完结标记可解析', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '[百合會][百合姬VOL.5]Simoun-第三話(End)',
        );

        expect(title.displayTitle, 'Simoun');
        expect(title.chapterLabel, '第三話');
        expect(title.chapterOrder, 3);
        expect(title.hasChapterMarker, isTrue);
    });

    test('旧帖之字章节号可解析为统一章节名', ()
    {
        final StructuredTitle single = normalizer.analyze(
            '[个人改汉][なもり]ゆるゆり摇曳百合外传 大室家之一',
        );
        final StructuredTitle range = normalizer.analyze(
            '[个人改汉][なもり]ゆるゆり摇曳百合外传 '
            '大室家之十四、十五、十六',
        );

        expect(single.displayTitle, 'ゆるゆり摇曳百合外传 大室家');
        expect(single.chapterLabel, '第1话');
        expect(single.chapterOrder, 1);
        expect(range.chapterLabel, '第14、15、16话');
        expect(range.chapterOrder, 14);
    });

    test('附录页码范围不被误认为章节号', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '[なもり][大室家01卷 限定版附錄] '
            '花子様の絵日記帳 (大室花子的繪圖日記) p.1-10',
        );

        expect(title.hasChapterMarker, isFalse);
        expect(title.chapterLabel, isEmpty);
    });

    test('紧贴作品名的章节号及页数备注可解析', ()
    {
        final StructuredTitle zeroPadded = normalizer.analyze(
            '[百合會][作者]どれが恋かがわからない'
            '(我也不知道誰才是真愛)01',
        );
        final StructuredTitle pageCount = normalizer.analyze('[漢化][作者]放學後11(42p)');

        expect(zeroPadded.displayTitle, 'どれが恋かがわからない(我也不知道誰才是真愛)');
        expect(zeroPadded.chapterLabel, '01');
        expect(zeroPadded.chapterOrder, 1);
        expect(pageCount.displayTitle, '放學後');
        expect(pageCount.chapterLabel, '11(42p)');
        expect(pageCount.chapterOrder, 11);
    });

    test('紧贴结束标点或带空格副标题的章节号可解析', ()
    {
        final StructuredTitle attached = normalizer.analyze(
            '【提灯喵汉化组】[玉崎たま]'
            '无用圣女与无能王女～被召唤至异世界的零魔力圣女救国纪～'
            '02 严重的缺陷',
        );
        final StructuredTitle subtitle = normalizer.analyze(
            '【提灯喵汉化组】[原作：みかみてれん×漫画：千種みのり]'
            '女孩们×吸血鬼 14 露露娜大人、瓮中捉鳖',
        );
        final StructuredTitle split = normalizer.analyze(
            '【提灯喵汉化组】[原作：みかみてれん×漫画：千種みのり]'
            '女孩们×吸血鬼 18下 才不想被人类看扁呢',
        );

        expect(attached.displayTitle, '无用圣女与无能王女~被召唤至异世界的零魔力圣女救国纪~');
        expect(attached.chapterLabel, '02 严重的缺陷');
        expect(attached.chapterOrder, 2);
        expect(subtitle.displayTitle, '女孩们×吸血鬼');
        expect(subtitle.chapterLabel, '14 露露娜大人、瓮中捉鳖');
        expect(subtitle.chapterOrder, 14);
        expect(split.displayTitle, '女孩们×吸血鬼');
        expect(split.chapterLabel, '18下 才不想被人类看扁呢');
        expect(split.chapterOrder, 18.003);
    });

    test('长标题末尾紧贴章节号且发布标签变化时仍聚合', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(
                561912,
                '【提灯喵汉化组】'
                '[原作：みかみてれん×漫画：千種みのり]'
                '女孩们×吸血鬼 14 露露娜大人、瓮中捉鳖',
            ),
            _thread(
                563955,
                '【喵】【提灯喵汉化组】'
                '[原作：みかみてれん×漫画：千種みのり]'
                '女孩们×吸血鬼 21 露露娜大人、想让人类臣服',
            ),
            _thread(
                573378,
                '【提灯喵汉化组】'
                '[原作：みかみてれん×作画：千種みのり]'
                '女孩们×吸血鬼 35：露露娜大人、被和奏牵着走',
            ),
        ]);

        expect(works, hasLength(1));
        expect(works.single.title, '女孩们×吸血鬼');
        expect(
            works.single.chapters.map((Chapter chapter) => chapter.title),
            <String>['14 露露娜大人、瓮中捉鳖', '21 露露娜大人、想让人类臣服', '35 露露娜大人、被和奏牵着走'],
        );
    });

    test('长作品名后紧贴的非零章节号可连续聚合', ()
    {
        const String prefix =
                '【提灯喵汉化组】'
                '[漫画：むっしゅ×原作：みかみてれん]'
                '我怎么可能成为你的恋人，不行不行！（※也不是不可能!?）';
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(505928, '${prefix}01'),
            _thread(538749, '${prefix}49'),
            _thread(559215, '【动画】${prefix}64 (7/9修正P12漏頁)'),
            _thread(571742, '${prefix}73'),
        ]);

        expect(works, hasLength(1));
        expect(
            works.single.chapters.map((Chapter chapter) => chapter.order),
            <double?>[1, 49, 64, 73],
        );
    });

    test('英文序数作品名不会被误判为章节', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '[夜合後援組合作漢化][大島永遠＆大島智]'
            '（放課後 ）放學後 2nd season',
        );

        expect(title.displayTitle, '放學後 2nd season');
        expect(title.hasChapterMarker, isFalse);
    });

    test('明确分隔的上中下篇可用于作品聚合', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(92, '[汉化][作者]inversion(逆转)-上'),
            _thread(93, '[汉化][作者]inversion(逆转)-下'),
        ]);

        expect(works, hasLength(1));
        expect(works.single.title, 'inversion(逆转)');
        expect(
            works.single.chapters.map((Chapter chapter) => chapter.title),
            <String>['上篇', '下篇'],
        );
    });

    test('明确短篇分类即使标题带连续章节号也保持单帖', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(94, '【汉化组】【作者】魔法少女与前邪恶女干部 11', typeId: 68),
            _thread(95, '【汉化组】【作者】魔法少女与前邪恶女干部 12', typeId: 68),
        ]);

        expect(works, hasLength(2));
        expect(works.every((Work work) => work.chapters.length == 1), isTrue);
        expect(
            aggregator.canonicalKeyForWork(works.first),
            isNot(aggregator.canonicalKeyForWork(works.last)),
        );
        expect(
            works
                    .expand((Work work) => work.sourceThreads)
                    .map((SourceThread thread) => thread.tid),
            <int>[94, 95],
        );
    });

    test('裸章节号的前后篇标记无需篇字也可解析', ()
    {
        final StructuredTitle title = normalizer.analyze('[汉化][作者]测试作品 5前');

        expect(title.displayTitle, '测试作品');
        expect(title.chapterLabel, '5前');
        expect(title.chapterOrder, 5.001);
    });

    test('小说卷号及卷章组合使用同一作品键', ()
    {
        final StructuredTitle combined = normalizer.analyze('长篇小说 第2卷 第3章 新篇');
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(83, '长篇小说 第一卷'),
            _thread(84, '长篇小说 第二卷'),
        ]);

        expect(combined.displayTitle, '长篇小说');
        expect(combined.chapterLabel, '第2卷 第3章 新篇');
        expect(combined.chapterOrder, 20003);
        expect(works, hasLength(1));
        expect(
            works.single.chapters.map((Chapter chapter) => chapter.title),
            <String>['第一卷', '第二卷'],
        );
    });

    test('小说版本和分卷标题归一为同一作品但保留版本元数据', ()
    {
        final StructuredTitle serial = normalizer.analyze(
            '[轻小说] 【WEB版】测试作品',
        );
        final StructuredTitle firstVolume = normalizer.analyze(
            '[轻小说] 测试作品[第一卷]【完】（第二卷已开坑，见新贴）',
        );
        final StructuredTitle secondVolume = normalizer.analyze(
            '[轻小说] 【文庫版】测试作品 第二卷',
        );

        expect(serial.novelDisplayTitle, '测试作品');
        expect(serial.novelEdition, NovelEdition.serial);
        expect(firstVolume.novelDisplayTitle, '测试作品');
        expect(firstVolume.novelEdition, NovelEdition.book);
        expect(firstVolume.volumeTitle, '第一卷');
        expect(firstVolume.volumeOrder, 1);
        expect(secondVolume.novelDisplayTitle, '测试作品');
        expect(secondVolume.novelEdition, NovelEdition.book);
        expect(secondVolume.volumeTitle, '第二卷');

        final List<Work> works = aggregator.aggregate(<SourceThread>[
            _thread(
                831,
                '[轻小说] 【WEB版】测试作品',
                board: ForumBoard.lightNovel,
            ),
            _thread(
                832,
                '[轻小说] 测试作品 第一卷',
                board: ForumBoard.lightNovel,
            ),
            _thread(
                833,
                '[轻小说] 测试作品 第二卷',
                board: ForumBoard.lightNovel,
            ),
        ]);

        expect(works, hasLength(1));
        expect(works.single.title, '测试作品');
        expect(works.single.sourceThreads, hasLength(3));
    });

    test('小说分卷聚合按卷从其它译者补缺', ()
    {
        final Work work = aggregator.aggregate(<SourceThread>[
            _thread(
                841,
                '[轻小说] 多译者小说 第一卷',
                board: ForumBoard.lightNovel,
                author: '译者甲',
            ),
            _thread(
                842,
                '[轻小说] 多译者小说 第二卷',
                board: ForumBoard.lightNovel,
                author: '译者甲',
            ),
            _thread(
                843,
                '[轻小说] 多译者小说 第三卷',
                board: ForumBoard.lightNovel,
                author: '译者乙',
            ),
        ]).single;

        expect(work.directories, hasLength(2));
        expect(work.directories.first.owner, '译者甲');
        expect(
            work.chapters.map((Chapter chapter) => chapter.sourceTid),
            <int>[841, 842, 843],
        );
    });

    test('小说连载智能目录以可靠完整来源为基准仅补明确缺章', ()
    {
        final List<Chapter> chapters = aggregator.smartNovelChaptersForDirectories(
            <WorkDirectory>[
                _directory('译者甲', <Chapter>[
                    _chapter(101, '序章', order: 0),
                    _chapter(102, '第1章', order: 1),
                    _chapter(103, '第2章', order: 2),
                    _chapter(104, '旅途的开始', order: 3),
                    _chapter(105, '第4章', order: 4),
                    _chapter(107, '第7章', order: 7),
                ]),
                _directory('译者乙', <Chapter>[
                    _chapter(202, '第2章 新译', order: 2),
                    _chapter(203, '第3章', order: 3),
                    _chapter(205, '另一个标题', order: 5),
                    _chapter(206, '第5-6章', order: 5),
                    _chapter(299, '尾声', order: 900000),
                ]),
            ],
        );

        expect(
            chapters.map((Chapter chapter) => chapter.sourceTid),
            <int>[101, 102, 103, 104, 203, 105, 206, 107, 299],
        );
        expect(chapters.where((Chapter chapter) => chapter.sourceTid == 202), isEmpty);
        expect(chapters.where((Chapter chapter) => chapter.sourceTid == 205), isEmpty);
    });

    test('小说跨译者补章认可明确中文章节号', ()
    {
        final List<Chapter> chapters = aggregator.smartNovelChaptersForDirectories(
            <WorkDirectory>[
                _directory('译者甲', <Chapter>[
                    _chapter(301, '第一章', order: 1),
                    _chapter(303, '第三章', order: 3),
                    _chapter(304, '第四章', order: 4),
                ]),
                _directory('译者乙', <Chapter>[
                    _chapter(302, '第二章', order: 2),
                    _chapter(399, '无编号标题', order: 9),
                ]),
            ],
        );

        expect(
            chapters.map((Chapter chapter) => chapter.sourceTid),
            <int>[301, 302, 303, 304],
        );
    });

    test('小说智能目录分离连载版和单行本章节键', ()
    {
        final List<Chapter> chapters = aggregator.smartNovelChaptersForDirectories(
            <WorkDirectory>[
                _directory('译者甲', <Chapter>[
                    _chapter(101, '第1章', order: 1),
                    _chapter(
                        111,
                        '第一章',
                        order: 10001,
                        novelEdition: NovelEdition.book,
                        volumeTitle: '第一卷',
                        volumeOrder: 1,
                        sourcePid: 1111,
                    ),
                ]),
                _directory('译者乙', <Chapter>[
                    _chapter(202, '第2章', order: 2),
                ]),
            ],
        );

        expect(
            chapters.map((Chapter chapter) => chapter.sourceTid),
            <int>[101, 202, 111],
        );
    });

    test('单行本按卷选择单一译者且分章优先于整卷', ()
    {
        final List<Chapter> chapters = aggregator.smartNovelChaptersForDirectories(
            <WorkDirectory>[
                _directory('译者甲', <Chapter>[
                    _chapter(
                        110,
                        '整卷阅读',
                        order: 10000,
                        novelEdition: NovelEdition.book,
                        volumeTitle: '第一卷',
                        volumeOrder: 1,
                    ),
                    _chapter(
                        120,
                        '序章',
                        order: 20000,
                        novelEdition: NovelEdition.book,
                        volumeTitle: '第二卷',
                        volumeOrder: 2,
                        sourcePid: 1201,
                    ),
                    _chapter(
                        120,
                        '第一章',
                        order: 20001,
                        novelEdition: NovelEdition.book,
                        volumeTitle: '第二卷',
                        volumeOrder: 2,
                        sourcePid: 1202,
                    ),
                ]),
                _directory('译者乙', <Chapter>[
                    _chapter(
                        210,
                        '序章',
                        order: 10000,
                        novelEdition: NovelEdition.book,
                        volumeTitle: '第一卷',
                        volumeOrder: 1,
                        sourcePid: 2101,
                    ),
                    _chapter(
                        210,
                        '第一章',
                        order: 10001,
                        novelEdition: NovelEdition.book,
                        volumeTitle: '第一卷',
                        volumeOrder: 1,
                        sourcePid: 2102,
                    ),
                    _chapter(
                        220,
                        '整卷阅读',
                        order: 20000,
                        novelEdition: NovelEdition.book,
                        volumeTitle: '第二卷',
                        volumeOrder: 2,
                    ),
                    _chapter(
                        230,
                        '整卷阅读',
                        order: 30000,
                        novelEdition: NovelEdition.book,
                        volumeTitle: '第三卷',
                        volumeOrder: 3,
                    ),
                ]),
            ],
        );

        expect(
            chapters.map((Chapter chapter) => chapter.sourceTid),
            <int>[210, 210, 120, 120, 230],
        );
        expect(chapters.where((Chapter chapter) => chapter.sourceTid == 110), isEmpty);
        expect(chapters.where((Chapter chapter) => chapter.sourceTid == 220), isEmpty);
    });

    test('公告和版规主题不进入作品列表', ()
    {
        final List<Work> works = aggregator.aggregate(<SourceThread>[
            SourceThread(
                tid: 90,
                board: ForumBoard.comic,
                title: '版规公告',
                administrative: true,
                uri: Uri.parse(
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=90',
                ),
            ),
            _thread(91, '正常作品 第1话'),
        ]);

        expect(works, hasLength(1));
        expect(works.single.sourceThreads.single.tid, 91);
    });
}

SourceThread _thread(
    int tid,
    String title, {
    ForumBoard board = ForumBoard.comic,
    int? typeId = 65,
    String author = '',
    DateTime? postedAt,
})
{
    return SourceThread(
        tid: tid,
        board: board,
        typeId: typeId,
        title: title,
        author: author,
        postedAt: postedAt,
        uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
        ),
    );
}

WorkDirectory _directory(String owner, List<Chapter> chapters)
{
    return WorkDirectory(
        id: 'owner:$owner',
        owner: owner,
        sourceTids: chapters
                .map((Chapter chapter) => chapter.sourceTid)
                .toSet()
                .toList(growable: false),
        chapters: chapters,
    );
}

Chapter _chapter(
    int tid,
    String title, {
    required double order,
    int? sourcePid,
    NovelEdition? novelEdition,
    String volumeTitle = '',
    double? volumeOrder,
})
{
    return Chapter(
        id: 'chapter:$tid:${sourcePid ?? 0}:$title',
        title: title,
        sourceUri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
        ),
        sourceTid: tid,
        sourcePid: sourcePid,
        order: order,
        novelEdition: novelEdition,
        volumeTitle: volumeTitle,
        volumeOrder: volumeOrder,
    );
}
