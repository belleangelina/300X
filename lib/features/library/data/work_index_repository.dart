import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/core/storage/work_codec.dart';
import 'package:x300/features/library/domain/library_models.dart';

final Provider<WorkIndexRepository> workIndexRepositoryProvider =
        Provider<WorkIndexRepository>(
            (Ref ref) => WorkIndexRepository(ref.watch(appDatabaseProvider)),
        );

class WorkIndexRecord
{
    const WorkIndexRecord({
        required this.canonicalKey,
        required this.work,
        required this.updatedAt,
    });

    final String canonicalKey;
    final Work work;
    final DateTime updatedAt;
}

class WorkIndexRepository
{
    static const int currentResolverVersion = 18;

    WorkIndexRepository(this._database, [this._workCodec = const WorkCodec()]);

    final AppDatabase _database;
    final WorkCodec _workCodec;

    Future<WorkIndexRecord?> loadByCanonicalKey(
        String canonicalKey,
        LibraryKind kind,
    ) async
    {
        final WorkIndex? row =
                await (_database.select(_database.workIndexes)..where(
                            (WorkIndexes table) =>
                                    table.canonicalKey.equals(canonicalKey) &
                                    table.libraryKind.equals(kind.name) &
                                    table.resolverVersion.equals(currentResolverVersion),
                        ))
                        .getSingleOrNull();
        return _decode(row);
    }

    Future<WorkIndexRecord?> loadBySourceTid(int tid, LibraryKind kind) async
    {
        final WorkIndexSource? source =
                await (_database.select(_database.workIndexSources)
                            ..where((WorkIndexSources table) => table.tid.equals(tid)))
                        .getSingleOrNull();
        if (source == null)
        {
            return null;
        }
        return loadByCanonicalKey(source.canonicalKey, kind);
    }

    Future<WorkIndexRecord?> loadByWorkId(String workId, LibraryKind kind) async
    {
        final WorkIndex? row =
                await (_database.select(_database.workIndexes)..where(
                            (WorkIndexes table) =>
                                    table.workId.equals(workId) &
                                    table.libraryKind.equals(kind.name) &
                                    table.resolverVersion.equals(currentResolverVersion),
                        ))
                        .getSingleOrNull();
        return _decode(row);
    }

    Future<void> save({
        required String canonicalKey,
        required Work work,
        DateTime? updatedAt,
    }) async
    {
        if (canonicalKey.isEmpty)
        {
            throw ArgumentError.value(canonicalKey, 'canonicalKey', '作品索引键不能为空');
        }
        final Set<int> tids = <int>{
            ...work.sourceThreads.map((SourceThread value) => value.tid),
            ...work.chapters.map((Chapter value) => value.sourceTid),
            ...work.directories.expand((WorkDirectory value) => value.sourceTids),
            ...work.directories.expand(
                (WorkDirectory value) =>
                        value.chapters.map((Chapter chapter) => chapter.sourceTid),
            ),
        };
        final DateTime timestamp = updatedAt ?? DateTime.now();
        await _database.transaction(() async
        {
            final WorkIndex? sameWork =
                    await (_database.select(_database.workIndexes)..where(
                                (WorkIndexes table) =>
                                        table.workId.equals(work.id) &
                                        table.libraryKind.equals(work.kind.name),
                            ))
                            .getSingleOrNull();
            final List<WorkIndexSource> mappedSources = tids.isEmpty
                    ? const <WorkIndexSource>[]
                    : await (_database.select(
                            _database.workIndexSources,
                        )..where((WorkIndexSources table) => table.tid.isIn(tids))).get();
            final Set<String> mappedKeys = mappedSources
                    .map((WorkIndexSource value) => value.canonicalKey)
                    .toSet();
            final List<WorkIndex> mappedWorks = mappedKeys.isEmpty
                    ? const <WorkIndex>[]
                    : await (_database.select(_database.workIndexes)..where(
                                    (WorkIndexes table) =>
                                            table.canonicalKey.isIn(mappedKeys) &
                                            table.libraryKind.equals(work.kind.name),
                                ))
                                .get();
            final Set<String> obsoleteKeys = <String>{
                if (sameWork != null && sameWork.canonicalKey != canonicalKey)
                    sameWork.canonicalKey,
                ...mappedWorks
                        .map((WorkIndex value) => value.canonicalKey)
                        .where((String value) => value != canonicalKey),
            };
            for (final String obsoleteKey in obsoleteKeys)
            {
                await (_database.delete(_database.workIndexSources)..where(
                            (WorkIndexSources table) =>
                                    table.canonicalKey.equals(obsoleteKey),
                        ))
                        .go();
                await (_database.delete(_database.workIndexes)..where(
                            (WorkIndexes table) => table.canonicalKey.equals(obsoleteKey),
                        ))
                        .go();
            }

            await _database
                    .into(_database.workIndexes)
                    .insertOnConflictUpdate(
                        WorkIndexesCompanion.insert(
                            canonicalKey: canonicalKey,
                            workId: work.id,
                            libraryKind: work.kind.name,
                            workJson: _workCodec.encodeIndex(work),
                            resolverVersion: const Value<int>(currentResolverVersion),
                            updatedAt: timestamp,
                        ),
                    );
            await (_database.delete(_database.workIndexSources)..where(
                        (WorkIndexSources table) => table.canonicalKey.equals(canonicalKey),
                    ))
                    .go();
            for (final int tid in tids)
            {
                await _database
                        .into(_database.workIndexSources)
                        .insert(
                            WorkIndexSourcesCompanion.insert(
                                tid: Value<int>(tid),
                                canonicalKey: canonicalKey,
                            ),
                            mode: InsertMode.insertOrReplace,
                        );
            }
        });
    }

    Future<void> clearAll()
    {
        return _database.transaction(() async
        {
            await _database.delete(_database.workIndexSources).go();
            await _database.delete(_database.workIndexes).go();
        });
    }

    WorkIndexRecord? _decode(WorkIndex? row)
    {
        if (row == null)
        {
            return null;
        }
        try
        {
            return WorkIndexRecord(
                canonicalKey: row.canonicalKey,
                work: _workCodec.decode(row.workJson),
                updatedAt: row.updatedAt,
            );
        } on Object
        {
            return null;
        }
    }
}
