import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/history/data/reading_history_repository.dart';
import 'package:x300/features/history/domain/reading_history_models.dart';
import 'package:x300/features/library/domain/library_models.dart';

void main()
{
    late AppDatabase database;
    late ReadingHistoryRepository repository;

    setUp(()
    {
        database = AppDatabase(NativeDatabase.memory());
        repository = ReadingHistoryRepository(database);
    });

    tearDown(() async
    {
        await database.close();
    });

    test('保存、更新、筛选和删除本机进度', () async
    {
        final Work comic = _work(
            id: 'work:comic',
            kind: LibraryKind.comic,
            board: ForumBoard.comic,
        );
        final Work novel = _work(
            id: 'work:novel',
            kind: LibraryKind.novel,
            board: ForumBoard.literature,
        );
        await repository.save(
            work: comic,
            chapter: comic.chapters.last,
            position: 5,
            progress: 0.75,
            updatedAt: DateTime(2026, 7, 10, 10),
        );
        await repository.save(
            work: novel,
            chapter: novel.chapters.first,
            position: 1200,
            progress: 0.25,
            updatedAt: DateTime(2026, 7, 10, 11),
        );

        final ReadingHistoryEntry? comicState = await repository.get(
            comic.id,
        );
        expect(comicState, isNotNull);
        expect(comicState!.chapterId, 'chapter:2');
        expect(comicState.chapterIndex, 1);
        expect(comicState.position, 5);
        expect(comicState.progress, 0.75);

        final List<ReadingHistoryEntry> all = await repository.watch().first;
        expect(
            all.map((ReadingHistoryEntry value) => value.work.id),
            <String>['work:novel', 'work:comic'],
        );
        final List<ReadingHistoryEntry> comics = await repository.watch(
            kind: LibraryKind.comic,
        ).first;
        expect(comics, hasLength(1));
        expect(comics.single.work.kind, LibraryKind.comic);

        await repository.save(
            work: comic,
            chapter: comic.chapters.first,
            position: -3,
            progress: 2,
            updatedAt: DateTime(2026, 7, 10, 12),
        );
        final ReadingHistoryEntry updated = (await repository.get(comic.id))!;
        expect(updated.chapterId, 'chapter:1');
        expect(updated.position, 0);
        expect(updated.progress, 1);

        await repository.delete(comic.id);
        expect(await repository.get(comic.id), isNull);
        expect(await repository.watch().first, hasLength(1));
    });
}

Work _work({
    required String id,
    required LibraryKind kind,
    required ForumBoard board,
})
{
    final int tid = kind == LibraryKind.comic ? 101 : 102;
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
    return Work(
        id: id,
        kind: kind,
        title: kind == LibraryKind.comic ? '测试漫画' : '测试小说',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: tid,
                board: board,
                title: '测试作品 第一章',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'chapter:1',
                title: '第一章',
                sourceUri: uri,
                sourceTid: tid,
            ),
            Chapter(
                id: 'chapter:2',
                title: '第二章',
                sourceUri: uri,
                sourceTid: tid,
            ),
        ],
    );
}
