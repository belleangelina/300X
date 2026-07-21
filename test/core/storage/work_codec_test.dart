import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/storage/work_codec.dart';
import 'package:x300/features/library/domain/library_models.dart';

void main()
{
    const WorkCodec codec = WorkCodec();

    test('作品来源和章节可无损往返 JSON', ()
    {
        final Work source = _work(
            id: 'work:comic',
            kind: LibraryKind.comic,
            board: ForumBoard.comic,
        );

        final Work decoded = codec.decode(codec.encode(source));

        expect(decoded.id, source.id);
        expect(decoded.kind, source.kind);
        expect(decoded.title, source.title);
        expect(decoded.sourceThreads, hasLength(1));
        expect(decoded.sourceThreads.single.tid, 101);
        expect(decoded.sourceThreads.single.board, ForumBoard.comic);
        expect(decoded.sourceThreads.single.postedAt, DateTime(2026, 7, 10));
        expect(decoded.chapters, hasLength(2));
        expect(decoded.chapters.last.sourcePid, 202);
        expect(decoded.chapters.first.sourceEndPid, 202);
        expect(decoded.chapters.first.sourceStartBlock, 1);
        expect(decoded.chapters.first.sourceEndBlock, 4);
        expect(decoded.chapters.last.sourceStartBlock, isNull);
        expect(decoded.chapters.last.sourceEndBlock, isNull);
        expect(decoded.chapters.last.order, 2);
        expect(decoded.directories, hasLength(1));
        expect(decoded.directories.single.owner, '作者');
        expect(decoded.directories.single.sourceTids, <int>[101]);
        expect(decoded.directories.single.chapters, hasLength(2));
    });

    test('索引编码移除摘要但保留章节定位信息', ()
    {
        final Work source = _work(
            id: 'work:novel',
            kind: LibraryKind.novel,
            board: ForumBoard.lightNovel,
        );

        final String encoded = codec.encodeIndex(source);
        final Work decoded = codec.decode(encoded);

        expect(encoded, isNot(contains('作品正文摘要')));
        expect(encoded, isNot(contains('来源正文摘要')));
        expect(decoded.summary, isEmpty);
        expect(decoded.sourceThreads.single.summary, isEmpty);
        expect(decoded.chapters.first.sourcePid, 201);
        expect(decoded.chapters.first.sourceEndPid, 202);
        expect(decoded.chapters.first.sourceStartBlock, 1);
        expect(decoded.chapters.first.sourceEndBlock, 4);
        expect(decoded.chapters.first.novelEdition, NovelEdition.serial);
        expect(decoded.chapters.last.novelEdition, NovelEdition.book);
        expect(decoded.chapters.last.volumeTitle, '第一卷');
        expect(decoded.chapters.last.volumeOrder, 1);
    });
}

Work _work({
    required String id,
    required LibraryKind kind,
    required ForumBoard board,
})
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2',
    );
    return Work(
        id: id,
        kind: kind,
        title: '测试作品',
        summary: '作品正文摘要',
        author: '作者',
        typeName: '分类',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 101,
                board: board,
                typeId: 7,
                typeName: '分类',
                title: '测试作品 第一章',
                summary: '来源正文摘要',
                author: '作者',
                avatarUri: Uri.parse('https://bbs.yamibo.com/avatar.jpg'),
                timeLabel: '2026-7-10 00:00',
                postedAt: DateTime(2026, 7, 10),
                views: 12,
                replies: 3,
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'chapter:1',
                title: '第一章',
                sourceUri: uri,
                sourceTid: 101,
                sourcePid: 201,
                sourceEndPid: 202,
                sourceStartBlock: 1,
                sourceEndBlock: 4,
                order: 1,
                novelEdition: kind == LibraryKind.novel
                        ? NovelEdition.serial
                        : null,
            ),
            Chapter(
                id: 'chapter:2',
                title: '第二章',
                sourceUri: uri,
                sourceTid: 101,
                sourcePid: 202,
                order: 2,
                novelEdition: kind == LibraryKind.novel
                        ? NovelEdition.book
                        : null,
                volumeTitle: kind == LibraryKind.novel ? '第一卷' : '',
                volumeOrder: kind == LibraryKind.novel ? 1 : null,
            ),
        ],
        directories: <WorkDirectory>[
            WorkDirectory(
                id: 'owner:作者',
                owner: '作者',
                sourceTids: const <int>[101],
                chapters: <Chapter>[
                    Chapter(
                        id: 'chapter:1',
                        title: '第一章',
                        sourceUri: uri,
                        sourceTid: 101,
                        sourcePid: 201,
                        sourceEndPid: 202,
                        sourceStartBlock: 1,
                        sourceEndBlock: 4,
                        order: 1,
                    ),
                    Chapter(
                        id: 'chapter:2',
                        title: '第二章',
                        sourceUri: uri,
                        sourceTid: 101,
                        sourcePid: 202,
                        order: 2,
                    ),
                ],
            ),
        ],
    );
}
