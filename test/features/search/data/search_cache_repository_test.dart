import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/search/data/search_cache_repository.dart';

void main()
{
    late AppDatabase database;
    late SearchCacheRepository repository;

    setUp(()
    {
        database = AppDatabase(NativeDatabase.memory());
        repository = SearchCacheRepository(database);
    });

    tearDown(() async
    {
        await database.close();
    });

    test('搜索缓存按内容类型和规范化关键词隔离', () async
    {
        final DateTime updatedAt = DateTime(2026, 7, 10, 20);
        final Work comic = _work(
            id: 'comic:101',
            kind: LibraryKind.comic,
            board: ForumBoard.comic,
        );
        await repository.save(
            kind: LibraryKind.comic,
            keyword: '  测试作品  ',
            works: <Work>[comic],
            updatedAt: updatedAt,
        );

        final SearchCacheSnapshot? cached = await repository.load(
            kind: LibraryKind.comic,
            keyword: '测试作品',
        );
        expect(cached, isNotNull);
        expect(cached!.works.single.id, comic.id);
        expect(cached.updatedAt, updatedAt);
        expect(
            await repository.load(
                kind: LibraryKind.novel,
                keyword: '测试作品',
            ),
            isNull,
        );
    });

    test('启动维护后每种内容只保留最近五十个搜索关键词', () async
    {
        final DateTime base = DateTime(2026, 7, 1);
        for (int index = 0; index <= 50; index++)
        {
            await repository.save(
                kind: LibraryKind.comic,
                keyword: '关键词$index',
                works: const <Work>[],
                updatedAt: base.add(Duration(minutes: index)),
            );
        }
        await repository.prune(kind: LibraryKind.comic);

        expect(
            await database.select(database.searchCaches).get(),
            hasLength(SearchCacheRepository.maximumEntriesPerKind),
        );
        expect(
            await repository.load(
                kind: LibraryKind.comic,
                keyword: '关键词0',
            ),
            isNull,
        );
        expect(
            await repository.load(
                kind: LibraryKind.comic,
                keyword: '关键词50',
            ),
            isNotNull,
        );
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
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 101,
                board: board,
                title: '测试作品 第一章',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: '$id:1',
                title: '第一章',
                sourceUri: uri,
                sourceTid: 101,
            ),
        ],
    );
}
