import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/core/storage/work_codec.dart';
import 'package:x300/features/downloads/data/download_payload_codec.dart';
import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

final Provider<DownloadRepository> downloadRepositoryProvider =
    Provider<DownloadRepository>(
        (Ref ref) => DownloadRepository(
            ref.watch(appDatabaseProvider),
        ),
    );

class DownloadRepository
{
    DownloadRepository(
        this._database, [
        this._workCodec = const WorkCodec(),
        this._payloadCodec = const DownloadPayloadCodec(),
    ]);

    final AppDatabase _database;
    final WorkCodec _workCodec;
    final DownloadPayloadCodec _payloadCodec;

    String taskId(String workId, String chapterId)
    {
        return '$workId::$chapterId';
    }

    Future<void> enqueue({
        required Work work,
        required Chapter chapter,
        required String directoryPath,
    }) async
    {
        final String id = taskId(work.id, chapter.id);
        final DownloadTask? existing = await (
            _database.select(_database.downloadTasks)
                ..where((DownloadTasks table) => table.taskId.equals(id))
        ).getSingleOrNull();
        if (existing != null &&
            existing.status == DownloadStatus.completed.name)
        {
            return;
        }
        await _database.into(_database.downloadTasks).insertOnConflictUpdate(
            DownloadTasksCompanion.insert(
                taskId: id,
                workId: work.id,
                libraryKind: work.kind.name,
                workJson: _workCodec.encode(work),
                chapterJson: _workCodec.encodeChapter(chapter),
                status: DownloadStatus.queued.name,
                completedItems: existing?.completedItems ?? 0,
                totalItems: existing?.totalItems ?? 0,
                directoryPath: directoryPath,
                payloadJson: existing?.payloadJson ?? '',
                errorMessage: '',
                updatedAt: DateTime.now(),
            ),
        );
    }

    Stream<List<DownloadTaskEntry>> watch({LibraryKind? kind})
    {
        final query = _database.select(_database.downloadTasks);
        if (kind != null)
        {
            query.where(
                (DownloadTasks table) =>
                    table.libraryKind.equals(kind.name),
            );
        }
        query.orderBy(<OrderClauseGenerator<DownloadTasks>>[
            (DownloadTasks table) => OrderingTerm.desc(table.updatedAt),
        ]);
        return query.watch().map(_decodeAll);
    }

    Future<DownloadTaskEntry?> nextQueued() async
    {
        final query = _database.select(_database.downloadTasks)
            ..where(
                (DownloadTasks table) =>
                    table.status.equals(DownloadStatus.queued.name),
            )
            ..orderBy(<OrderClauseGenerator<DownloadTasks>>[
                (DownloadTasks table) => OrderingTerm.asc(table.updatedAt),
            ])
            ..limit(1);
        final DownloadTask? task = await query.getSingleOrNull();
        return task == null ? null : _decode(task);
    }

    Future<DownloadTaskEntry?> claimNextQueued(LibraryKind kind)
    {
        return _database.transaction(() async
        {
            final DownloadTask? task = await (
                _database.select(_database.downloadTasks)
                    ..where(
                        (DownloadTasks table) =>
                            table.status.equals(DownloadStatus.queued.name) &
                            table.libraryKind.equals(kind.name),
                    )
                    ..orderBy(<OrderClauseGenerator<DownloadTasks>>[
                        (DownloadTasks table) =>
                            OrderingTerm.asc(table.updatedAt),
                    ])
                    ..limit(1)
            ).getSingleOrNull();
            if (task == null)
            {
                return null;
            }
            await (
                _database.update(_database.downloadTasks)
                    ..where(
                        (DownloadTasks table) =>
                            table.taskId.equals(task.taskId) &
                            table.status.equals(DownloadStatus.queued.name),
                    )
            ).write(DownloadTasksCompanion(
                status: Value<String>(DownloadStatus.downloading.name),
                updatedAt: Value<DateTime>(DateTime.now()),
            ));
            return get(task.taskId);
        });
    }

    Future<DownloadTaskEntry?> get(String id) async
    {
        final DownloadTask? task = await (
            _database.select(_database.downloadTasks)
                ..where((DownloadTasks table) => table.taskId.equals(id))
        ).getSingleOrNull();
        return task == null ? null : _decode(task);
    }

    Future<List<DownloadTaskEntry>> listForWork(String workId) async
    {
        final List<DownloadTask> tasks = await (
            _database.select(_database.downloadTasks)
                ..where(
                    (DownloadTasks table) => table.workId.equals(workId),
                )
                ..orderBy(<OrderClauseGenerator<DownloadTasks>>[
                    (DownloadTasks table) =>
                        OrderingTerm.desc(table.updatedAt),
                ])
        ).get();
        return _decodeAll(tasks);
    }

    Future<void> setStatus(
        String id,
        DownloadStatus status, {
        String errorMessage = '',
    })
    {
        return (
            _database.update(_database.downloadTasks)
                ..where((DownloadTasks table) => table.taskId.equals(id))
        ).write(DownloadTasksCompanion(
            status: Value<String>(status.name),
            errorMessage: Value<String>(errorMessage),
            updatedAt: Value<DateTime>(DateTime.now()),
        ));
    }

    Future<void> updateProgress(
        String id, {
        required int completedItems,
        required int totalItems,
    })
    {
        return (
            _database.update(_database.downloadTasks)
                ..where((DownloadTasks table) => table.taskId.equals(id))
        ).write(DownloadTasksCompanion(
            completedItems: Value<int>(completedItems),
            totalItems: Value<int>(totalItems),
            updatedAt: Value<DateTime>(DateTime.now()),
        ));
    }

    Future<void> complete(
        String id, {
        required List<PostContentBlock> blocks,
        required Uri referer,
    })
    {
        return (
            _database.update(_database.downloadTasks)
                ..where((DownloadTasks table) => table.taskId.equals(id))
        ).write(DownloadTasksCompanion(
            status: Value<String>(DownloadStatus.completed.name),
            payloadJson: Value<String>(_payloadCodec.encode(
                blocks: blocks,
                referer: referer,
            )),
            errorMessage: const Value<String>(''),
            updatedAt: Value<DateTime>(DateTime.now()),
        ));
    }

    Future<void> restoreInterrupted()
    {
        return (
            _database.update(_database.downloadTasks)
                ..where(
                    (DownloadTasks table) => table.status.equals(
                        DownloadStatus.downloading.name,
                    ),
                )
        ).write(DownloadTasksCompanion(
            status: Value<String>(DownloadStatus.queued.name),
            errorMessage: const Value<String>(''),
            updatedAt: Value<DateTime>(DateTime.now()),
        ));
    }

    Future<OfflineChapterContent?> loadOfflineContent(
        String workId,
        String chapterId,
    ) async
    {
        final String id = taskId(workId, chapterId);
        final DownloadTask? task = await (
            _database.select(_database.downloadTasks)
                ..where(
                    (DownloadTasks table) =>
                        table.taskId.equals(id) &
                        table.status.equals(DownloadStatus.completed.name),
                )
        ).getSingleOrNull();
        if (task == null || task.payloadJson.isEmpty)
        {
            return null;
        }
        try
        {
            final OfflineChapterContent content = _payloadCodec.decode(
                task.payloadJson,
            );
            for (final PostImageBlock block
                in content.blocks.whereType<PostImageBlock>())
            {
                if (block.uri.scheme != 'file')
                {
                    continue;
                }
                final File file = File.fromUri(block.uri);
                if (!await file.exists() || await file.length() == 0)
                {
                    await setStatus(
                        id,
                        DownloadStatus.failed,
                        errorMessage: '本地文件缺失，请重新下载',
                    );
                    return null;
                }
            }
            return content;
        }
        on Object
        {
            await setStatus(
                id,
                DownloadStatus.failed,
                errorMessage: '离线章节索引损坏，请重新下载',
            );
            return null;
        }
    }

    Future<void> delete(String id)
    {
        return (
            _database.delete(_database.downloadTasks)
                ..where((DownloadTasks table) => table.taskId.equals(id))
        ).go();
    }

    List<DownloadTaskEntry> _decodeAll(List<DownloadTask> tasks)
    {
        final List<DownloadTaskEntry> result = <DownloadTaskEntry>[];
        for (final DownloadTask task in tasks)
        {
            try
            {
                result.add(_decode(task));
            }
            on Object
            {
                continue;
            }
        }
        return result;
    }

    DownloadTaskEntry _decode(DownloadTask task)
    {
        return DownloadTaskEntry(
            id: task.taskId,
            work: _workCodec.decode(task.workJson),
            chapter: _workCodec.decodeChapter(task.chapterJson),
            status: DownloadStatus.values.byName(task.status),
            completedItems: task.completedItems,
            totalItems: task.totalItems,
            directoryPath: task.directoryPath,
            payloadJson: task.payloadJson,
            errorMessage: task.errorMessage,
            updatedAt: task.updatedAt,
        );
    }
}
