import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/library/data/title_normalizer.dart';
import 'package:x300/features/library/domain/library_models.dart';

void main()
{
    const TitleNormalizer normalizer = TitleNormalizer();
    const String novelTitle =
            '「你这种家伙别想打赢魔王」被攻略厨踢出了勇者队伍，'
            '想在王都过上平静的生活';
    const String normalizedNovelTitle =
            '「你这种家伙别想打赢魔王」被攻略厨踢出了勇者队伍,'
            '想在王都过上平静的生活';

    test('ASCII 连字号章节范围保留完整语义', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '测试作品 第1-5話',
        );
        final NumericChapterRange? range =
                normalizer.detectNumericChapterRange('第1-5話');

        expect(title.displayTitle, '测试作品');
        expect(title.chapterLabel, '第1-5話');
        expect(title.chapterOrder, 1);
        expect(title.hasChapterMarker, isTrue);
        expect(range?.start, 1);
        expect(range?.end, 5);
        expect(range?.label, '第1-5話');
    });

    test('目录式小数范围即使省略话字也保留起止值', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '测试作品 6.2~6.4',
        );

        expect(title.displayTitle, '测试作品');
        expect(title.chapterLabel, '6.2~6.4');
        expect(title.chapterOrder, 6.2);
        expect(title.hasChapterMarker, isTrue);
        expect(normalizer.detectNumericChapterRange(title.original), isNull);

        final StructuredTitle chapterOnly = normalizer.analyze('6.2~6.4');
        expect(chapterOnly.chapterLabel, '6.2~6.4');
        expect(chapterOnly.chapterOrder, 6.2);
    });

    test('无单位整数范围作为单帖多话标题而不是章节加副标题', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '魔法少女与前邪恶女干部 02-03',
        );

        expect(title.displayTitle, '魔法少女与前邪恶女干部');
        expect(title.chapterLabel, '02-03');
        expect(title.chapterOrder, 2);
        expect(title.hasChapterMarker, isTrue);
        expect(normalizer.detectNumericChapterRange(title.original), isNull);
    });

    test('单数字连字符分段兼容紧贴、空格和带单位标题', ()
    {
        final StructuredTitle attached = normalizer.analyze(
            '【萝卜子汉化组】[矢坂しゅう]向笨蛋告白5-2',
        );
        final StructuredTitle separated = normalizer.analyze('向笨蛋告白 2-1');
        final StructuredTitle explicit = normalizer.analyze(
            '向笨蛋告白 第10-2话',
        );
        final StructuredTitle directory = normalizer.analyze('2-1');

        expect(attached.displayTitle, '向笨蛋告白');
        expect(attached.chapterLabel, '5-2');
        expect(attached.chapterOrder, 5.2);
        expect(separated.displayTitle, '向笨蛋告白');
        expect(separated.chapterLabel, '2-1');
        expect(separated.chapterOrder, 2.1);
        expect(explicit.displayTitle, '向笨蛋告白');
        expect(explicit.chapterLabel, '第10-2话');
        expect(explicit.chapterOrder, 10.2);
        expect(directory.chapterLabel, '2-1');
        expect(directory.chapterOrder, 2.1);
        expect(directory.hasChapterMarker, isTrue);
        expect(
            attached.chapterOrder,
            normalizer.analyze('向笨蛋告白 5.2').chapterOrder,
        );
        expect(
            normalizer.detectNumericChapterRange('第10-2话'),
            isNull,
        );
    });

    test('年份连字符不作为章节分段', ()
    {
        expect(normalizer.analyze('2026-7').hasChapterMarker, isFalse);
        expect(normalizer.analyze('作品 2026-7').hasChapterMarker, isFalse);
    });

    test('四格番外前缀保留在章节名但不进入作品名', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '【萝卜子汉化组】[矢坂しゅう]向笨蛋告白 四格番外篇1',
        );
        final StructuredTitle directory = normalizer.analyze('四格番外1');

        expect(title.displayTitle, '向笨蛋告白');
        expect(title.chapterLabel, '四格番外篇1');
        expect(title.chapterOrder, 900001);
        expect(directory.chapterLabel, '四格番外1');
        expect(directory.chapterOrder, 900001);
        expect(directory.hasChapterMarker, isTrue);
    });

    test('页码型无单位整数范围仍不视为章节', ()
    {
        final StructuredTitle title = normalizer.analyze('画集 p.1-10');

        expect(title.hasChapterMarker, isFalse);
    });

    test('tid 505406 和 505794 的尾部翻译标签不阻断裸卷号候选', ()
    {
        final StructuredTitle first = normalizer.analyze(
            '[轻小说] [转载][kiki]$novelTitle 01 [日翻/简]',
        );
        final StructuredTitle second = normalizer.analyze(
            '[轻小说] [转载][kiki]$novelTitle 02 [日翻/简]',
        );
        final NovelBareVolumeCandidate? firstCandidate =
                normalizer.detectNovelBareVolumeCandidate(first.original);
        final NovelBareVolumeCandidate? secondCandidate =
                normalizer.detectNovelBareVolumeCandidate(second.original);

        expect(first.displayTitle, normalizedNovelTitle);
        expect(first.creatorKey, 'kiki');
        expect(first.novelEdition, isNull);
        expect(firstCandidate?.displayTitle, normalizedNovelTitle);
        expect(firstCandidate?.volumeNumber, 1);
        expect(second.displayTitle, normalizedNovelTitle);
        expect(second.creatorKey, 'kiki');
        expect(second.novelEdition, isNull);
        expect(secondCandidate?.displayTitle, normalizedNovelTitle);
        expect(secondCandidate?.volumeNumber, 2);
    });

    test('tid 523062 的方括号作品名不会被当成 creator', ()
    {
        final String original =
                '[轻小说] [自翻][kiki][$novelTitle] 3 【完结】';
        final StructuredTitle title = normalizer.analyze(original);
        final NovelBareVolumeCandidate? candidate =
                normalizer.detectNovelBareVolumeCandidate(original);

        expect(title.displayTitle, normalizedNovelTitle);
        expect(title.creatorKey, 'kiki');
        expect(title.novelEdition, isNull);
        expect(candidate?.displayTitle, normalizedNovelTitle);
        expect(candidate?.volumeNumber, 3);
    });

    test('单个作者括号后已有作品名和章节号时不把作者并入作品名', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '【タチ】認真少女與青春內衣 第12话 Kakukuroi汉化组',
        );

        expect(title.displayTitle, '認真少女與青春內衣');
        expect(title.creatorKey, 'タチ');
        expect(title.chapterLabel, '第12话 Kakukuroi汉化组');
    });

    test('作品名前的最终话标记不覆盖作者', ()
    {
        final StructuredTitle title = normalizer.analyze(
            '[祐希堂百合组][一青二白汉化组][江島絵理]'
            '[最终话]少女決戰Orgia 第19話',
        );

        expect(title.displayTitle, '少女決戰Orgia');
        expect(title.creatorKey, '江島絵理');
        expect(title.chapterOrder, 19);

        final StructuredTitle wrappedTitle = normalizer.analyze('[最终话]第1话');
        expect(wrappedTitle.displayTitle, '最终话');
        expect(wrappedTitle.creatorKey, isEmpty);
        expect(wrappedTitle.chapterOrder, 1);
    });

    test('明确的第N幕作为章节且裸幕编号不扩展识别', ()
    {
        final StructuredTitle numeric = normalizer.analyze(
            '[中村汚濁]圣少女默示录 DEATHPAIR 第16幕 与救世者一起',
        );
        final StructuredTitle chinese = normalizer.analyze('测试作品 第十六幕 标题');
        final StructuredTitle bare = normalizer.analyze('测试作品 16幕 标题');

        expect(numeric.displayTitle, '圣少女默示录 DEATHPAIR');
        expect(numeric.chapterLabel, '第16幕 与救世者一起');
        expect(numeric.chapterOrder, 16);
        expect(chinese.displayTitle, '测试作品');
        expect(chinese.chapterOrder, 16);
        expect(bare.hasChapterMarker, isFalse);
    });

    test('括号后只有章节号时仍把括号内容视为作品名', ()
    {
        final StructuredTitle title = normalizer.analyze('【作品名】第12话');

        expect(title.displayTitle, '作品名');
        expect(title.creatorKey, isEmpty);
        expect(title.chapterOrder, 12);
    });

    test('tid 558094 的更新标签不阻断明确卷号', ()
    {
        final String original =
                '[轻小说] [自翻][kiki][$novelTitle] '
                '第五卷 [更新 010 扭曲]';
        final StructuredTitle title = normalizer.analyze(original);

        expect(title.displayTitle, normalizedNovelTitle);
        expect(title.creatorKey, 'kiki');
        expect(title.novelEdition, NovelEdition.book);
        expect(title.volumeTitle, '第五卷');
        expect(title.volumeOrder, 5);
        expect(normalizer.detectNovelBareVolumeCandidate(original), isNull);
    });

    test('页码范围不被识别为章节范围或裸卷号', ()
    {
        const String original = '花子様の絵日記帳 p.1-10';
        final StructuredTitle title = normalizer.analyze(original);

        expect(title.hasChapterMarker, isFalse);
        expect(normalizer.detectNumericChapterRange(original), isNull);
        expect(normalizer.detectNovelBareVolumeCandidate(original), isNull);
    });

    test('紧贴作品名的卷号只作为显式卷目录下的候选', ()
    {
        const String original =
                '[轻小说] 【霜月汉化组】[みかみてれん]'
                '百日百合4 【完】（请看一楼，严禁传播资源）';

        final NovelBareVolumeCandidate? candidate =
                normalizer.detectNovelAdjacentVolumeCandidate(original);

        expect(normalizer.detectNovelBareVolumeCandidate(original), isNull);
        expect(candidate?.displayTitle, '百日百合');
        expect(candidate?.volumeNumber, 4);
    });
}
