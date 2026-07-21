import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/favorites/data/favorite_work_policy.dart';
import 'package:x300/features/library/domain/library_models.dart';

void main()
{
    const FavoriteWorkPolicy policy = FavoriteWorkPolicy();

    test('作品收藏使用默认目录当前解析基准帖', ()
    {
        final Work work = _work();

        expect(policy.anchor(work).tid, 102);
    });

    test('收藏状态覆盖作品线程章节和全部目录来源', ()
    {
        expect(
            policy.sourceTids(_work()),
            <int>{101, 102, 201, 202, 301},
        );
    });
}

Work _work()
{
    final List<SourceThread> sources = <SourceThread>[
        _source(101, '测试作品 第1话'),
        _source(102, '测试作品 第12话'),
        _source(201, '测试作品 第20话'),
        _source(202, '测试作品 第21话'),
    ];
    final List<Chapter> primaryChapters = <Chapter>[
        _chapter(sources[0], 1),
        _chapter(sources[1], 12),
        Chapter(
            id: 'forum-thread:301',
            title: '第8话',
            sourceUri: Uri.parse('https://bbs.yamibo.com/thread-301-1-1.html'),
            sourceTid: 301,
            order: 8,
        ),
    ];
    final List<Chapter> secondaryChapters = <Chapter>[
        _chapter(sources[2], 20),
        _chapter(sources[3], 21),
    ];
    return Work(
        id: 'forum-work:test',
        kind: LibraryKind.comic,
        title: '测试作品',
        sourceThreads: sources,
        chapters: <Chapter>[...primaryChapters, ...secondaryChapters],
        directories: <WorkDirectory>[
            WorkDirectory(
                id: 'owner:primary',
                owner: '译者甲',
                sourceTids: const <int>[101, 102],
                chapters: primaryChapters,
            ),
            WorkDirectory(
                id: 'owner:secondary',
                owner: '译者乙',
                sourceTids: const <int>[201, 202],
                chapters: secondaryChapters,
            ),
        ],
    );
}

SourceThread _source(int tid, String title)
{
    return SourceThread(
        tid: tid,
        board: ForumBoard.comic,
        title: title,
        uri: Uri.parse('https://bbs.yamibo.com/thread-$tid-1-1.html'),
        postedAt: DateTime(2026, 7, tid % 28 + 1),
    );
}

Chapter _chapter(SourceThread source, double order)
{
    return Chapter(
        id: 'forum-thread:${source.tid}',
        title: '第${order.toInt()}话',
        sourceUri: source.uri,
        sourceTid: source.tid,
        order: order,
    );
}
