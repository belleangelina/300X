import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/favorites/data/favorite_cache_repository.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/library/domain/library_models.dart';

void main()
{
    late AppDatabase database;
    late FavoriteCacheRepository repository;

    setUp(()
    {
        database = AppDatabase(NativeDatabase.memory());
        repository = FavoriteCacheRepository(database);
    });

    tearDown(() async
    {
        await database.close();
    });

    test('云收藏缓存保留作品和删除所需记录并支持整体替换', () async
    {
        final DateTime updatedAt = DateTime(2026, 7, 10, 20);
        final FavoriteWork comic = _favorite(
            id: 'comic:101',
            tid: 101,
            kind: LibraryKind.comic,
            board: ForumBoard.comic,
        );
        final FavoriteWork novel = _favorite(
            id: 'novel:202',
            tid: 202,
            kind: LibraryKind.novel,
            board: ForumBoard.literature,
        );
        await repository.save(
            <FavoriteWork>[comic, novel],
            updatedAt: updatedAt,
        );

        FavoriteCacheSnapshot? cached = await repository.load();
        expect(cached, isNotNull);
        expect(
            cached!.works.map((FavoriteWork value) => value.work.id),
            <String>[comic.work.id, novel.work.id],
        );
        expect(cached.works.first.records.single.favoriteId, 1101);
        expect(cached.updatedAt, updatedAt);

        await repository.save(<FavoriteWork>[novel]);
        cached = await repository.load();
        expect(cached!.works.single.work.id, novel.work.id);
    });
}

FavoriteWork _favorite({
    required String id,
    required int tid,
    required LibraryKind kind,
    required ForumBoard board,
})
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
    return FavoriteWork(
        work: Work(
            id: id,
            kind: kind,
            title: '测试作品 $tid',
            sourceThreads: <SourceThread>[
                SourceThread(
                    tid: tid,
                    board: board,
                    title: '测试作品 $tid',
                    uri: uri,
                ),
            ],
            chapters: <Chapter>[
                Chapter(
                    id: '$id:1',
                    title: '正文',
                    sourceUri: uri,
                    sourceTid: tid,
                ),
            ],
        ),
        records: <CloudFavoriteRecord>[
            CloudFavoriteRecord(
                favoriteId: tid + 1000,
                threadId: tid,
                title: '测试作品 $tid',
                threadUri: uri,
                deleteDialogUri: Uri.parse(
                    'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&favid=${tid + 1000}',
                ),
            ),
        ],
    );
}
