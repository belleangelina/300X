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

class _RawVersionTwoDatabase extends AppDatabase
{
    _RawVersionTwoDatabase(super.executor);

    @override
    int get schemaVersion => 2;

    @override
    MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) async
        {
            await customStatement('''
                CREATE TABLE reading_states (
                    work_id TEXT NOT NULL PRIMARY KEY,
                    library_kind TEXT NOT NULL,
                    work_json TEXT NOT NULL,
                    chapter_id TEXT NOT NULL,
                    chapter_title TEXT NOT NULL,
                    chapter_index INTEGER NOT NULL,
                    position INTEGER NOT NULL,
                    progress REAL NOT NULL,
                    updated_at INTEGER NOT NULL
                )
            ''');
            await customStatement('''
                CREATE TABLE search_caches (
                    cache_key TEXT NOT NULL PRIMARY KEY,
                    library_kind TEXT NOT NULL,
                    keyword TEXT NOT NULL,
                    works_json TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                )
            ''');
            await customStatement('''
                CREATE TABLE favorite_caches (
                    work_id TEXT NOT NULL PRIMARY KEY,
                    work_json TEXT NOT NULL,
                    records_json TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                )
            ''');
            await customStatement('''
                CREATE TABLE download_tasks (
                    task_id TEXT NOT NULL PRIMARY KEY,
                    work_id TEXT NOT NULL,
                    library_kind TEXT NOT NULL,
                    work_json TEXT NOT NULL,
                    chapter_json TEXT NOT NULL,
                    status TEXT NOT NULL,
                    completed_items INTEGER NOT NULL,
                    total_items INTEGER NOT NULL,
                    directory_path TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    error_message TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                )
            ''');
        },
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

class _VersionSevenDatabase extends AppDatabase
{
    _VersionSevenDatabase(super.executor);

    @override
    int get schemaVersion => 7;

    @override
    MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) async
        {
            await customStatement('''
                CREATE TABLE favorite_caches (
                    work_id TEXT NOT NULL PRIMARY KEY,
                    work_json TEXT NOT NULL,
                    records_json TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                )
            ''');
            await customStatement('''
                CREATE TABLE forum_caches (
                    account_key TEXT NOT NULL,
                    cache_key TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY (account_key, cache_key)
                )
            ''');
            await customStatement('''
                CREATE TABLE forum_drafts (
                    draft_id TEXT NOT NULL,
                    account_key TEXT NOT NULL,
                    action TEXT NOT NULL,
                    fid INTEGER NULL,
                    tid INTEGER NULL,
                    pid INTEGER NULL,
                    subject TEXT NOT NULL,
                    message TEXT NOT NULL,
                    attachments_json TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY (account_key, draft_id)
                )
            ''');
            await customStatement('''
                CREATE TABLE forum_read_anchors (
                    account_key TEXT NOT NULL,
                    tid INTEGER NOT NULL,
                    pid INTEGER NULL,
                    page INTEGER NOT NULL,
                    floor INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY (account_key, tid)
                )
            ''');
        },
    );
}

void main()
{
    test('raw v2 无 user_id 收藏升级到 v9 后保留为 uid0 且创建提交封存表', () async
    {
        final Directory directory = await Directory.systemTemp.createTemp(
            'page300_migration_raw_v2_test_',
        );
        final File file = File('${directory.path}/page300.sqlite');
        final _RawVersionTwoDatabase legacy = _RawVersionTwoDatabase(
            NativeDatabase(file),
        );
        await legacy.customStatement('''
            INSERT INTO favorite_caches (
                work_id,
                work_json,
                records_json,
                updated_at
            ) VALUES (
                'comic:raw-v2',
                '{"title":"旧收藏"}',
                '[]',
                1783900800
            )
        ''');
        await legacy.close();

        final AppDatabase current = AppDatabase(NativeDatabase(file));
        final FavoriteCache favorite = await current
            .select(current.favoriteCaches)
            .getSingle();
        expect(favorite.userId, 0);
        expect(favorite.workId, 'comic:raw-v2');
        expect(
            await (current.select(current.favoriteCaches)..where(
                (FavoriteCaches table) => table.userId.equals(101),
            )).get(),
            isEmpty,
        );
        expect(
            await current.select(current.forumActionTombstones).get(),
            isEmpty,
        );

        await current.close();
        await directory.delete(recursive: true);
    });

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
        expect(await current.select(current.forumCaches).get(), isEmpty);
        expect(await current.select(current.forumDrafts).get(), isEmpty);
        expect(await current.select(current.forumReadAnchors).get(), isEmpty);
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

    test('v7 收藏缓存升级后保留为未绑定数据且不暴露给账号', () async
    {
        final Directory directory = await Directory.systemTemp.createTemp(
            'page300_migration_v7_test_',
        );
        final File file = File('${directory.path}/page300.sqlite');
        final _VersionSevenDatabase legacy = _VersionSevenDatabase(
            NativeDatabase(file),
        );
        await legacy.customStatement('''
            INSERT INTO favorite_caches (
                work_id,
                work_json,
                records_json,
                updated_at
            ) VALUES (
                'comic:legacy',
                '{}',
                '[]',
                1783900800
            )
        ''');
        await legacy.customStatement('''
            INSERT INTO forum_caches (
                account_key,
                cache_key,
                payload_json,
                updated_at
            ) VALUES ('uid:101', 'forum:v2:index', '{}', 1783900800)
        ''');
        await legacy.customStatement('''
            INSERT INTO forum_drafts (
                draft_id,
                account_key,
                action,
                fid,
                subject,
                message,
                attachments_json,
                updated_at
            ) VALUES (
                'new-thread:30',
                'uid:101',
                'newThread',
                30,
                '标题',
                '正文',
                '{}',
                1783900800
            )
        ''');
        await legacy.close();

        final AppDatabase current = AppDatabase(NativeDatabase(file));
        final FavoriteCache legacyRow = await current
            .select(current.favoriteCaches)
            .getSingle();
        expect(legacyRow.userId, 0);
        expect(legacyRow.workId, 'comic:legacy');
        expect(legacyRow.workJson, '{}');
        expect(legacyRow.recordsJson, '[]');
        expect(
            await (current.select(current.favoriteCaches)..where(
                (FavoriteCaches table) => table.userId.equals(101),
            )).get(),
            isEmpty,
        );
        await current.into(current.favoriteCaches).insert(
            FavoriteCachesCompanion.insert(
                userId: 101,
                workId: 'comic:101',
                workJson: '{}',
                recordsJson: '[]',
                updatedAt: DateTime(2026, 7, 26),
            ),
        );
        final List<FavoriteCache> rows = await (current.select(
            current.favoriteCaches,
        )..orderBy(<OrderClauseGenerator<FavoriteCaches>>[
            (FavoriteCaches table) => OrderingTerm.asc(table.userId),
        ])).get();
        expect(rows.map((FavoriteCache row) => row.userId), <int>[0, 101]);
        expect(
            (await current.select(current.forumCaches).get()).single.cacheKey,
            'forum:v2:index',
        );
        expect(
            (await current.select(current.forumDrafts).get()).single.draftId,
            'new-thread:30',
        );
        final DateTime now = DateTime.utc(2026, 8, 13);
        Future<void> insertTombstone(String accountKey, String contextKey) =>
            current.into(current.forumActionTombstones).insert(
                ForumActionTombstonesCompanion.insert(
                    accountKey: accountKey,
                    contextKey: contextKey,
                    attemptId: '$accountKey:$contextKey',
                    action: 'newThread',
                    draftContext: 'new-thread:30',
                    status: 'attempted',
                    createdAt: now,
                    updatedAt: now,
                ),
            );
        await insertTombstone('uid:101', 'same-context');
        await insertTombstone('uid:202', 'same-context');
        await insertTombstone('uid:101', 'other-context');
        expect(
            await current.select(current.forumActionTombstones).get(),
            hasLength(3),
        );
        await expectLater(
            insertTombstone('uid:101', 'same-context'),
            throwsA(isA<Exception>()),
        );

        await current.close();
        await directory.delete(recursive: true);
    });
}
