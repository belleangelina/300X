import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'app_database.g.dart';

class ReadingStates extends Table
{
    TextColumn get workId => text()();

    TextColumn get libraryKind => text()();

    TextColumn get workJson => text()();

    TextColumn get chapterId => text()();

    TextColumn get chapterTitle => text()();

    IntColumn get chapterIndex => integer()();

    IntColumn get position => integer()();

    RealColumn get progress => real()();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{workId};
}

class SearchCaches extends Table
{
    TextColumn get cacheKey => text()();

    TextColumn get libraryKind => text()();

    TextColumn get keyword => text()();

    TextColumn get worksJson => text()();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{cacheKey};
}

class FavoriteCaches extends Table
{
    IntColumn get userId => integer()();

    TextColumn get workId => text()();

    TextColumn get workJson => text()();

    TextColumn get recordsJson => text()();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{userId, workId};
}

class DownloadTasks extends Table
{
    TextColumn get taskId => text()();

    TextColumn get workId => text()();

    TextColumn get libraryKind => text()();

    TextColumn get workJson => text()();

    TextColumn get chapterJson => text()();

    TextColumn get status => text()();

    IntColumn get completedItems => integer()();

    IntColumn get totalItems => integer()();

    TextColumn get directoryPath => text()();

    TextColumn get payloadJson => text()();

    TextColumn get errorMessage => text()();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{taskId};
}

class CoverCaches extends Table
{
    TextColumn get workId => text()();

    TextColumn get sourceMarker => text()();

    TextColumn get imageUri => text()();

    TextColumn get filePath => text()();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{workId};
}

class CoverEntries extends Table
{
    TextColumn get coverKey => text()();

    TextColumn get libraryKind => text()();

    TextColumn get status => text()();

    TextColumn get imageUri => text()();

    TextColumn get filePath => text()();

    IntColumn get sourceTid => integer().nullable()();

    IntColumn get retryCount => integer().withDefault(const Constant<int>(0))();

    DateTimeColumn get nextRetryAt => dateTime().nullable()();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{coverKey};
}

class CoverAliases extends Table
{
    TextColumn get libraryKind => text()();

    IntColumn get tid => integer()();

    TextColumn get coverKey => text().references(
        CoverEntries,
        #coverKey,
        onDelete: KeyAction.cascade,
    )();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{libraryKind, tid};
}

@DataClassName('WorkIndex')
class WorkIndexes extends Table
{
    TextColumn get canonicalKey => text()();

    TextColumn get workId => text().unique()();

    TextColumn get libraryKind => text()();

    TextColumn get workJson => text()();

    IntColumn get resolverVersion => integer().withDefault(
        const Constant<int>(1),
    )();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{canonicalKey};
}

class WorkIndexSources extends Table
{
    IntColumn get tid => integer()();

    TextColumn get canonicalKey => text().references(
        WorkIndexes,
        #canonicalKey,
        onDelete: KeyAction.cascade,
    )();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{tid};
}

class ForumCaches extends Table
{
    TextColumn get accountKey => text()();

    TextColumn get cacheKey => text()();

    TextColumn get payloadJson => text()();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{
        accountKey,
        cacheKey,
    };
}

class ForumDrafts extends Table
{
    TextColumn get draftId => text()();

    TextColumn get accountKey => text()();

    TextColumn get action => text()();

    IntColumn get fid => integer().nullable()();

    IntColumn get tid => integer().nullable()();

    IntColumn get pid => integer().nullable()();

    TextColumn get subject => text()();

    TextColumn get message => text()();

    TextColumn get attachmentsJson => text()();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{
        accountKey,
        draftId,
    };
}

class ForumReadAnchors extends Table
{
    TextColumn get accountKey => text()();

    IntColumn get tid => integer()();

    IntColumn get pid => integer().nullable()();

    IntColumn get page => integer()();

    IntColumn get floor => integer()();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{
        accountKey,
        tid,
    };
}

class ForumActionTombstones extends Table
{
    TextColumn get accountKey => text()();

    TextColumn get contextKey => text()();

    TextColumn get attemptId => text()();

    TextColumn get action => text()();

    IntColumn get fid => integer().nullable()();

    IntColumn get tid => integer().nullable()();

    IntColumn get pid => integer().nullable()();

    IntColumn get favoriteId => integer().nullable()();

    TextColumn get draftContext => text()();

    TextColumn get status => text()();

    DateTimeColumn get createdAt => dateTime()();

    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column<Object>> get primaryKey => <Column<Object>>{
        accountKey,
        contextKey,
    };
}

@DriftDatabase(
    tables: <Type>[
        ReadingStates,
        SearchCaches,
        FavoriteCaches,
        DownloadTasks,
        CoverCaches,
        CoverEntries,
        CoverAliases,
        WorkIndexes,
        WorkIndexSources,
        ForumCaches,
        ForumDrafts,
        ForumReadAnchors,
        ForumActionTombstones,
    ],
)
class AppDatabase extends _$AppDatabase
{
    AppDatabase([QueryExecutor? executor])
        : super(executor ?? driftDatabase(name: 'x300'));

    @override
    int get schemaVersion => 9;

    @override
    MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) => migrator.createAll(),
        onUpgrade: (Migrator migrator, int from, int to) async
        {
            if (from < 2)
            {
                await migrator.createTable(searchCaches);
                await migrator.createTable(favoriteCaches);
                await migrator.createTable(downloadTasks);
            }
            if (from < 3)
            {
                await migrator.createTable(coverCaches);
            }
            if (from < 4)
            {
                await migrator.createTable(workIndexes);
                await migrator.createTable(workIndexSources);
            }
            if (from >= 4 && from < 5)
            {
                await migrator.addColumn(
                    workIndexes,
                    workIndexes.resolverVersion,
                );
            }
            if (from < 6)
            {
                await migrator.createTable(coverEntries);
                await migrator.createTable(coverAliases);
            }
            if (from < 7)
            {
                await migrator.createTable(forumCaches);
                await migrator.createTable(forumDrafts);
                await migrator.createTable(forumReadAnchors);
            }
            if (from >= 2 && from < 8)
            {
                await customStatement(
                    'ALTER TABLE favorite_caches '
                    'RENAME TO favorite_caches_v1',
                );
                await migrator.createTable(favoriteCaches);
                await customStatement('''
                    INSERT INTO favorite_caches (
                        user_id,
                        work_id,
                        work_json,
                        records_json,
                        updated_at
                    )
                    SELECT
                        0,
                        work_id,
                        work_json,
                        records_json,
                        updated_at
                    FROM favorite_caches_v1
                ''');
                await migrator.deleteTable('favorite_caches_v1');
            }
            if (from < 9)
            {
                await migrator.createTable(forumActionTombstones);
            }
        },
    );
}

final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
    (Ref ref)
    {
        final AppDatabase database = AppDatabase();
        ref.onDispose(database.close);
        return database;
    },
);
