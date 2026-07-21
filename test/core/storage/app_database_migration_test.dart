import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/storage/app_database.dart';

class _VersionOneDatabase extends AppDatabase
{
    _VersionOneDatabase(super.executor);

    @override
    int get schemaVersion => 1;

    @override
    MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) =>
            migrator.createTable(readingStates),
    );
}

class _VersionThreeDatabase extends AppDatabase
{
    _VersionThreeDatabase(super.executor);

    @override
    int get schemaVersion => 3;

    @override
    MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) async
        {
            await migrator.createTable(readingStates);
            await migrator.createTable(searchCaches);
            await migrator.createTable(favoriteCaches);
            await migrator.createTable(downloadTasks);
            await migrator.createTable(coverCaches);
        },
    );
}

class _VersionFourDatabase extends AppDatabase
{
    _VersionFourDatabase(super.executor);

    @override
    int get schemaVersion => 4;

    @override
    MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) async
        {
            await migrator.createTable(readingStates);
            await migrator.createTable(searchCaches);
            await migrator.createTable(favoriteCaches);
            await migrator.createTable(downloadTasks);
            await migrator.createTable(coverCaches);
            await migrator.createTable(workIndexes);
            await migrator.createTable(workIndexSources);
            await customStatement(
                'ALTER TABLE work_indexes DROP COLUMN resolver_version',
            );
        },
    );
}

void main()
{
    test('v1 阅读历史数据库升级到当前版本后保留原数据', () async
    {
        final Directory directory = await Directory.systemTemp.createTemp(
            'page300_migration_test_',
        );
        final File file = File('${directory.path}/page300.sqlite');
        final _VersionOneDatabase legacy = _VersionOneDatabase(
            NativeDatabase(file),
        );
        await legacy.into(legacy.readingStates).insert(
            ReadingStatesCompanion.insert(
                workId: 'comic:101',
                libraryKind: 'comic',
                workJson: '{}',
                chapterId: 'chapter:1',
                chapterTitle: '正文',
                chapterIndex: 0,
                position: 3,
                progress: 0.3,
                updatedAt: DateTime(2026, 7, 10, 20),
            ),
        );
        await legacy.close();

        final AppDatabase current = AppDatabase(NativeDatabase(file));
        final List<ReadingState> states = await current
            .select(current.readingStates)
            .get();
        expect(states.single.workId, 'comic:101');
        expect(await current.select(current.searchCaches).get(), isEmpty);
        expect(await current.select(current.favoriteCaches).get(), isEmpty);
        expect(await current.select(current.downloadTasks).get(), isEmpty);
        expect(await current.select(current.coverCaches).get(), isEmpty);
        expect(await current.select(current.coverEntries).get(), isEmpty);
        expect(await current.select(current.coverAliases).get(), isEmpty);
        expect(await current.select(current.workIndexes).get(), isEmpty);
        expect(await current.select(current.workIndexSources).get(), isEmpty);
        expect(await current.select(current.coverEntries).get(), isEmpty);
        expect(await current.select(current.coverAliases).get(), isEmpty);

        await current.close();
        await directory.delete(recursive: true);
    });

    test('v3 数据库升级后保留缓存并创建作品索引表', () async
    {
        final Directory directory = await Directory.systemTemp.createTemp(
            'page300_migration_v3_test_',
        );
        final File file = File('${directory.path}/page300.sqlite');
        final _VersionThreeDatabase legacy = _VersionThreeDatabase(
            NativeDatabase(file),
        );
        final DateTime updatedAt = DateTime(2026, 7, 12, 10);
        await legacy.into(legacy.searchCaches).insert(
            SearchCachesCompanion.insert(
                cacheKey: 'comic:test',
                libraryKind: 'comic',
                keyword: 'test',
                worksJson: '[]',
                updatedAt: updatedAt,
            ),
        );
        await legacy.into(legacy.coverCaches).insert(
            CoverCachesCompanion.insert(
                workId: 'forum-thread:101',
                sourceMarker: 'marker',
                imageUri: '',
                filePath: '',
                updatedAt: updatedAt,
            ),
        );
        await legacy.close();

        final AppDatabase current = AppDatabase(NativeDatabase(file));
        expect(
            (await current.select(current.searchCaches).get()).single.cacheKey,
            'comic:test',
        );
        expect(
            (await current.select(current.coverCaches).get()).single.workId,
            'forum-thread:101',
        );
        expect(await current.select(current.workIndexes).get(), isEmpty);
        expect(await current.select(current.workIndexSources).get(), isEmpty);

        await current.close();
        await directory.delete(recursive: true);
    });

    test('v4 作品索引升级后标记为旧解析版本等待重建', () async
    {
        final Directory directory = await Directory.systemTemp.createTemp(
            'page300_migration_v4_test_',
        );
        final File file = File('${directory.path}/page300.sqlite');
        final _VersionFourDatabase legacy = _VersionFourDatabase(
            NativeDatabase(file),
        );
        await legacy.customStatement('''
            INSERT INTO work_indexes (
                canonical_key,
                work_id,
                library_kind,
                work_json,
                updated_at
            ) VALUES (
                'comic|legacy',
                'forum-thread:101',
                'comic',
                '{}',
                1783900800
            )
        ''');
        await legacy.close();

        final AppDatabase current = AppDatabase(NativeDatabase(file));
        final WorkIndex row = await current
            .select(current.workIndexes)
            .getSingle();

        expect(row.canonicalKey, 'comic|legacy');
        expect(row.resolverVersion, 1);
        expect(await current.select(current.coverEntries).get(), isEmpty);
        expect(await current.select(current.coverAliases).get(), isEmpty);

        await current.close();
        await directory.delete(recursive: true);
    });
}
