import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/core/storage/work_codec.dart';
import 'package:x300/features/library/data/work_index_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';

void main()
{
    late AppDatabase database;
    late WorkIndexRepository repository;

    setUp(()
    {
        database = AppDatabase(NativeDatabase.memory());
        repository = WorkIndexRepository(database);
    });

    tearDown(() async
    {
        await database.close();
    });

    test('作品索引可按键、作品 ID 和全部章节 tid 读取', () async
    {
        final DateTime updatedAt = DateTime(2026, 7, 12, 11);
        final Work work = _work(
            id: 'forum-work:novel',
            chapterTids: const <int>[101, 101, 102],
        );

        await repository.save(
            canonicalKey: 'novel|测试作品|type=7',
            work: work,
            updatedAt: updatedAt,
        );

        final WorkIndexRecord? byKey = await repository.loadByCanonicalKey(
            'novel|测试作品|type=7',
            LibraryKind.novel,
        );
        final WorkIndexRecord? byWorkId = await repository.loadByWorkId(
            work.id,
            LibraryKind.novel,
        );
        final WorkIndexRecord? bySource = await repository.loadBySourceTid(
            101,
            LibraryKind.novel,
        );
        final WorkIndexRecord? byLinkedChapter = await repository.loadBySourceTid(
            102,
            LibraryKind.novel,
        );
        expect(byKey, isNotNull);
        expect(byKey!.work.id, work.id);
        expect(byKey.updatedAt, updatedAt);
        expect(byWorkId?.canonicalKey, byKey.canonicalKey);
        expect(bySource?.canonicalKey, byKey.canonicalKey);
        expect(byLinkedChapter?.canonicalKey, byKey.canonicalKey);
        expect(byKey.work.summary, isEmpty);
        expect(byKey.work.sourceThreads.single.summary, isEmpty);
        expect(byKey.work.chapters.first.sourcePid, 201);
        expect(byKey.work.chapters.first.sourceEndPid, 202);

        final WorkIndex row = await database
            .select(database.workIndexes)
            .getSingle();
        expect(
            row.resolverVersion,
            WorkIndexRepository.currentResolverVersion,
        );
        expect(row.workJson, isNot(contains('作品正文摘要')));
        expect(row.workJson, isNot(contains('来源正文摘要')));
    });

    test('重键和刷新会原子替换旧作品及失效 tid 映射', () async
    {
        await repository.save(
            canonicalKey: 'novel|旧键|type=7',
            work: _work(
                id: 'forum-thread:101',
                chapterTids: const <int>[101],
            ),
        );
        await repository.save(
            canonicalKey: 'novel|新键|type=7',
            work: _work(
                id: 'forum-work:novel',
                chapterTids: const <int>[101, 102],
            ),
        );

        expect(
            await repository.loadByCanonicalKey(
                'novel|旧键|type=7',
                LibraryKind.novel,
            ),
            isNull,
        );
        expect(
            (await repository.loadBySourceTid(102, LibraryKind.novel))
                    ?.canonicalKey,
            'novel|新键|type=7',
        );

        await repository.save(
            canonicalKey: 'novel|新键|type=7',
            work: _work(
                id: 'forum-work:novel',
                chapterTids: const <int>[101],
            ),
        );

        expect(
            await repository.loadBySourceTid(101, LibraryKind.novel),
            isNotNull,
        );
        expect(
            await repository.loadBySourceTid(102, LibraryKind.novel),
            isNull,
        );
        expect(await database.select(database.workIndexes).get(), hasLength(1));
    });

    test('交叉来源 tid 不会让漫画和小说索引互相覆盖', () async
    {
        final Work comic = _work(
            id: 'forum-work:comic',
            chapterTids: const <int>[201, 202],
            kind: LibraryKind.comic,
            sourceTid: 201,
        );
        final Work novel = _work(
            id: 'forum-work:novel',
            chapterTids: const <int>[202],
            sourceTid: 202,
        );

        await repository.save(
            canonicalKey: 'comic|测试作品|type=7',
            work: comic,
        );
        await repository.save(
            canonicalKey: 'novel|测试作品|type=7',
            work: novel,
        );

        expect(
            await repository.loadByCanonicalKey(
                'comic|测试作品|type=7',
                LibraryKind.comic,
            ),
            isNotNull,
        );
        expect(
            await repository.loadByCanonicalKey(
                'novel|测试作品|type=7',
                LibraryKind.novel,
            ),
            isNotNull,
        );
        expect(
            await repository.loadByCanonicalKey(
                'comic|测试作品|type=7',
                LibraryKind.novel,
            ),
            isNull,
        );
        expect(
            (await repository.loadBySourceTid(202, LibraryKind.novel))
                    ?.canonicalKey,
            'novel|测试作品|type=7',
        );
        expect(await database.select(database.workIndexes).get(), hasLength(2));
    });

    test('独立清除作品索引会同时删除作品和来源映射', () async
    {
        await repository.save(
            canonicalKey: 'novel|测试作品|type=7',
            work: _work(
                id: 'forum-work:novel',
                chapterTids: const <int>[101, 102],
            ),
        );

        await repository.clearAll();

        expect(await database.select(database.workIndexes).get(), isEmpty);
        expect(await database.select(database.workIndexSources).get(), isEmpty);
    });

    test('旧解析版本索引保留在库中但不会作为有效目录返回', () async
    {
        final Work work = _work(
            id: 'forum-work:legacy',
            chapterTids: const <int>[101],
        );
        await database.into(database.workIndexes).insert(
            WorkIndexesCompanion.insert(
                canonicalKey: 'novel|旧解析|type=7',
                workId: work.id,
                libraryKind: work.kind.name,
                workJson: const WorkCodec().encodeIndex(work),
                resolverVersion: const Value<int>(
                    WorkIndexRepository.currentResolverVersion - 1,
                ),
                updatedAt: DateTime(2026, 7, 12),
            ),
        );
        await database.into(database.workIndexSources).insert(
            WorkIndexSourcesCompanion.insert(
                tid: const Value<int>(101),
                canonicalKey: 'novel|旧解析|type=7',
            ),
        );

        expect(
            await repository.loadByCanonicalKey(
                'novel|旧解析|type=7',
                LibraryKind.novel,
            ),
            isNull,
        );
        expect(
            await repository.loadBySourceTid(101, LibraryKind.novel),
            isNull,
        );
        expect(
            await repository.loadByWorkId(work.id, LibraryKind.novel),
            isNull,
        );
        expect(await database.select(database.workIndexes).get(), hasLength(1));
    });
}

Work _work({
    required String id,
    required List<int> chapterTids,
    LibraryKind kind = LibraryKind.novel,
    int sourceTid = 101,
})
{
    final Uri sourceUri = _threadUri(sourceTid);
    final ForumBoard board = kind == LibraryKind.comic
            ? ForumBoard.comic
            : ForumBoard.lightNovel;
    return Work(
        id: id,
        kind: kind,
        title: '测试作品',
        summary: '作品正文摘要',
        author: '作者',
        typeName: '连载',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: sourceTid,
                board: board,
                typeId: 7,
                typeName: '连载',
                title: '测试作品',
                summary: '来源正文摘要',
                author: '作者',
                uri: sourceUri,
            ),
        ],
        chapters: <Chapter>[
            for (int index = 0; index < chapterTids.length; index++)
                Chapter(
                    id: 'forum-post:${chapterTids[index]}:${201 + index}',
                    title: '第${index + 1}章',
                    sourceUri: _threadUri(chapterTids[index]),
                    sourceTid: chapterTids[index],
                    sourcePid: 201 + index,
                    sourceEndPid: index + 1 < chapterTids.length &&
                            chapterTids[index + 1] == chapterTids[index]
                        ? 202 + index
                        : null,
                    order: (index + 1).toDouble(),
                ),
        ],
    );
}

Uri _threadUri(int tid)
{
    return Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
}
