import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/reader/data/reader_media_repository.dart';
import 'package:x300/features/search/data/search_cache_repository.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';

class _MockCoverRepository extends Mock implements CoverRepository
{
}

class _MockReaderMediaRepository extends Mock
    implements ReaderMediaRepository
{
}

class _MockSearchCacheRepository extends Mock
    implements SearchCacheRepository
{
}

void main()
{
    test('每个进程只执行一次自动缓存维护', () async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final _MockCoverRepository covers = _MockCoverRepository();
        final _MockReaderMediaRepository media =
                _MockReaderMediaRepository();
        final _MockSearchCacheRepository searches =
                _MockSearchCacheRepository();
        when(covers.maintainCache).thenAnswer((_) async {});
        when(media.maintainCache).thenAnswer((_) async {});
        when(searches.prune).thenAnswer((_) async {});
        when(covers.cacheSizeBytes).thenAnswer((_) async => 200);
        when(media.cacheSizeBytes).thenAnswer((_) async => 100);
        final CacheMaintenanceRepository repository =
                CacheMaintenanceRepository(
            database,
            covers,
            media,
            searches,
        );

        await repository.maintainAutomatically();
        await repository.maintainAutomatically();
        final CacheUsageSnapshot usage = await repository.measureUsage();

        verify(covers.maintainCache).called(1);
        verify(media.maintainCache).called(1);
        verify(searches.prune).called(1);
        expect(usage.temporaryBytes, 100);
        expect(usage.coverBytes, 200);
        await database.close();
    });

    test('临时缓存与封面缓存独立清理且保留索引、历史和下载', () async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final Directory directory = await Directory.systemTemp.createTemp(
            'page300_cache_maintenance_test_',
        );
        final File coverFile = File('${directory.path}/cover.jpg');
        await coverFile.writeAsBytes(<int>[1, 2, 3]);
        final File finalCoverFile = File('${directory.path}/final-cover.jpg');
        await finalCoverFile.writeAsBytes(<int>[4, 5, 6]);
        final DateTime now = DateTime(2026, 7, 11);
        await database.into(database.searchCaches).insert(
            SearchCachesCompanion.insert(
                cacheKey: 'comic:test',
                libraryKind: 'comic',
                keyword: 'test',
                worksJson: '[]',
                updatedAt: now,
            ),
        );
        await database.into(database.favoriteCaches).insert(
            FavoriteCachesCompanion.insert(
                workId: 'comic:1',
                workJson: '{}',
                recordsJson: '[]',
                updatedAt: now,
            ),
        );
        await database.into(database.coverCaches).insert(
            CoverCachesCompanion.insert(
                workId: 'comic:1',
                sourceMarker: 'marker',
                imageUri: 'https://bbs.yamibo.com/cover.jpg',
                filePath: coverFile.path,
                updatedAt: now,
            ),
        );
        await database.into(database.coverEntries).insert(
            CoverEntriesCompanion.insert(
                coverKey: 'cover:comic:work:forum-work:test',
                libraryKind: 'comic',
                status: 'finalCover',
                imageUri: 'https://bbs.yamibo.com/final-cover.jpg',
                filePath: finalCoverFile.path,
                updatedAt: now,
            ),
        );
        await database.into(database.coverAliases).insert(
            CoverAliasesCompanion.insert(
                libraryKind: 'comic',
                tid: 101,
                coverKey: 'cover:comic:work:forum-work:test',
            ),
        );
        await database.into(database.readingStates).insert(
            ReadingStatesCompanion.insert(
                workId: 'comic:1',
                libraryKind: 'comic',
                workJson: '{}',
                chapterId: 'chapter:1',
                chapterTitle: '正文',
                chapterIndex: 0,
                position: 0,
                progress: 0,
                updatedAt: now,
            ),
        );
        await database.into(database.downloadTasks).insert(
            DownloadTasksCompanion.insert(
                taskId: 'comic:1::chapter:1',
                workId: 'comic:1',
                libraryKind: 'comic',
                workJson: '{}',
                chapterJson: '{}',
                status: 'completed',
                completedItems: 1,
                totalItems: 1,
                directoryPath: '/tmp/download',
                payloadJson: '{}',
                errorMessage: '',
                updatedAt: now,
            ),
        );
        await database.into(database.workIndexes).insert(
            WorkIndexesCompanion.insert(
                canonicalKey: 'comic|测试|type=none',
                workId: 'forum-work:test',
                libraryKind: 'comic',
                workJson: '{}',
                updatedAt: now,
            ),
        );
        await database.into(database.workIndexSources).insert(
            WorkIndexSourcesCompanion.insert(
                tid: const Value<int>(101),
                canonicalKey: 'comic|测试|type=none',
            ),
        );

        final CacheMaintenanceRepository repository =
                CacheMaintenanceRepository(database);
        await repository.clearTemporaryCaches();

        expect(await database.select(database.searchCaches).get(), isEmpty);
        expect(await database.select(database.favoriteCaches).get(), isEmpty);
        expect(await database.select(database.coverCaches).get(), hasLength(1));
        expect(await database.select(database.coverEntries).get(), hasLength(1));
        expect(await database.select(database.coverAliases).get(), hasLength(1));
        expect(await coverFile.exists(), isTrue);
        expect(await finalCoverFile.exists(), isTrue);

        await repository.clearCoverCaches();

        expect(await database.select(database.coverCaches).get(), isEmpty);
        expect(await database.select(database.coverEntries).get(), isEmpty);
        expect(await database.select(database.coverAliases).get(), isEmpty);
        expect(await coverFile.exists(), isFalse);
        expect(await finalCoverFile.exists(), isFalse);
        expect(await database.select(database.readingStates).get(), hasLength(1));
        expect(await database.select(database.downloadTasks).get(), hasLength(1));
        expect(await database.select(database.workIndexes).get(), hasLength(1));
        expect(
            await database.select(database.workIndexSources).get(),
            hasLength(1),
        );
        await database.close();
        await directory.delete(recursive: true);
    });
}
