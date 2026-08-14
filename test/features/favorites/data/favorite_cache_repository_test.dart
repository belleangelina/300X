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
        repository = FavoriteCacheRepository(database, 101);
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

    test('云收藏缓存按账号隔离', () async
    {
        final FavoriteWork comic = _favorite(
            id: 'comic:101',
            tid: 101,
            kind: LibraryKind.comic,
            board: ForumBoard.comic,
        );
        await repository.save(<FavoriteWork>[comic]);

        final FavoriteCacheRepository other = FavoriteCacheRepository(
            database,
            202,
        );

        expect(await other.load(), isNull);
        expect((await repository.load())!.works, hasLength(1));
    });

    test('云收藏缓存不落盘 formhash', () async
    {
        final FavoriteWork favorite = _favorite(
            id: 'comic:303',
            tid: 303,
            kind: LibraryKind.comic,
            board: ForumBoard.comic,
        );
        final CloudFavoriteRecord record = favorite.records.single;
        await repository.save(<FavoriteWork>[
            FavoriteWork(
                work: favorite.work,
                records: <CloudFavoriteRecord>[
                    CloudFavoriteRecord(
                        favoriteId: record.favoriteId,
                        threadId: record.threadId,
                        title: record.title,
                        threadUri: record.threadUri,
                        deleteDialogUri: record.deleteDialogUri.replace(
                            queryParameters: <String, String>{
                                ...record.deleteDialogUri.queryParameters,
                                'formhash': 'sensitive-token',
                            },
                        ),
                    ),
                ],
            ),
        ]);

        final FavoriteCache row = await database
            .select(database.favoriteCaches)
            .getSingle();
        expect(row.recordsJson, isNot(contains('sensitive-token')));
        expect(row.recordsJson, isNot(contains('formhash')));
        final CloudFavoriteRecord restored =
            (await repository.load())!.works.single.records.single;
        expect(restored.deleteDialogUri.queryParameters['favid'], '1303');
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
