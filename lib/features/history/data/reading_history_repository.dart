import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/core/storage/work_codec.dart';
import 'package:x300/features/history/domain/reading_history_models.dart';
import 'package:x300/features/library/domain/library_models.dart';

final Provider<ReadingHistoryRepository> readingHistoryRepositoryProvider =
    Provider<ReadingHistoryRepository>(
        (Ref ref) => ReadingHistoryRepository(
            ref.watch(appDatabaseProvider),
        ),
    );

class ReadingHistoryRepository
{
    ReadingHistoryRepository(
        this._database, [
        this._workCodec = const WorkCodec(),
    ]);

    final AppDatabase _database;
    final WorkCodec _workCodec;

    Future<void> save({
        required Work work,
        required Chapter chapter,
        required int position,
        required double progress,
        DateTime? updatedAt,
    }) async
    {
        int chapterIndex = work.chapters.indexWhere(
            (Chapter value) => value.id == chapter.id,
        );
        if (chapterIndex < 0)
        {
            chapterIndex = 0;
        }
        await _database.into(_database.readingStates).insertOnConflictUpdate(
            ReadingStatesCompanion.insert(
                workId: work.id,
                libraryKind: work.kind.name,
                workJson: _workCodec.encode(work),
                chapterId: chapter.id,
                chapterTitle: chapter.title,
                chapterIndex: chapterIndex,
                position: position < 0 ? 0 : position,
                progress: progress.clamp(0.0, 1.0).toDouble(),
                updatedAt: updatedAt ?? DateTime.now(),
            ),
        );
    }

    Future<ReadingHistoryEntry?> get(String workId) async
    {
        final ReadingState? state = await (
            _database.select(_database.readingStates)
                ..where(
                    (ReadingStates table) => table.workId.equals(workId),
                )
        ).getSingleOrNull();
        return state == null ? null : _decode(state);
    }

    Stream<List<ReadingHistoryEntry>> watch({LibraryKind? kind})
    {
        final query = _database.select(_database.readingStates);
        if (kind != null)
        {
            query.where(
                (ReadingStates table) =>
                    table.libraryKind.equals(kind.name),
            );
        }
        query.orderBy(<OrderClauseGenerator<ReadingStates>>[
            (ReadingStates table) => OrderingTerm.desc(table.updatedAt),
        ]);
        return query.watch().map(_decodeAll);
    }

    Future<void> delete(String workId)
    {
        return (
            _database.delete(_database.readingStates)
                ..where(
                    (ReadingStates table) => table.workId.equals(workId),
                )
        ).go();
    }

    List<ReadingHistoryEntry> _decodeAll(List<ReadingState> states)
    {
        final List<ReadingHistoryEntry> result = <ReadingHistoryEntry>[];
        for (final ReadingState state in states)
        {
            try
            {
                result.add(_decode(state));
            }
            on Object
            {
                continue;
            }
        }
        return result;
    }

    ReadingHistoryEntry _decode(ReadingState state)
    {
        return ReadingHistoryEntry(
            work: _workCodec.decode(state.workJson),
            chapterId: state.chapterId,
            chapterTitle: state.chapterTitle,
            chapterIndex: state.chapterIndex,
            position: state.position,
            progress: state.progress,
            updatedAt: state.updatedAt,
        );
    }
}
