import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/downloads/data/download_repository.dart';
import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

void main()
{
    late AppDatabase database;
    late DownloadRepository repository;
    late Directory temporaryDirectory;

    setUp(() async
    {
        database = AppDatabase(NativeDatabase.memory());
        repository = DownloadRepository(database);
        temporaryDirectory = await Directory.systemTemp.createTemp(
            'page300_download_test_',
        );
    });

    tearDown(() async
    {
        await database.close();
        if (await temporaryDirectory.exists())
        {
            await temporaryDirectory.delete(recursive: true);
        }
    });

    test('下载任务状态、进度和离线正文可以持久化', () async
    {
        final Work work = _work();
        final Chapter chapter = work.chapters.single;
        await repository.enqueue(
            work: work,
            chapter: chapter,
            directoryPath: temporaryDirectory.path,
        );

        DownloadTaskEntry task = (await repository.nextQueued())!;
        expect(task.work.title, '测试漫画');
        expect(task.chapter.title, '第一话');
        expect(task.status, DownloadStatus.queued);

        await repository.setStatus(task.id, DownloadStatus.downloading);
        await repository.updateProgress(task.id, completedItems: 1, totalItems: 2);
        await repository.restoreInterrupted();
        task = (await repository.get(task.id))!;
        expect(task.status, DownloadStatus.queued);
        expect(task.progress, 0.5);

        final File image = File('${temporaryDirectory.path}/image_0000.jpg');
        await image.writeAsBytes(<int>[1, 2, 3]);
        await repository.complete(
            task.id,
            blocks: <PostContentBlock>[PostImageBlock(uri: image.uri, alt: '第一页')],
            referer: chapter.sourceUri,
        );

        final OfflineChapterContent? content = await repository.loadOfflineContent(
            work.id,
            chapter.id,
        );
        expect(content, isNotNull);
        expect(content!.blocks, hasLength(1));
        expect(
            (content.blocks.single as PostImageBlock).uri.toFilePath(),
            image.path,
        );
        final List<DownloadTaskEntry> tasks = await repository
                .watch(kind: LibraryKind.comic)
                .first;
        expect(tasks.single.status, DownloadStatus.completed);
        final List<DownloadTaskEntry> workTasks = await repository.listForWork(
            work.id,
        );
        expect(workTasks.single.chapter.id, chapter.id);

        await repository.delete(task.id);
        expect(await repository.get(task.id), isNull);
    });

    test('离线图片缺失时将任务标记为失败', () async
    {
        final Work work = _work();
        final Chapter chapter = work.chapters.single;
        await repository.enqueue(
            work: work,
            chapter: chapter,
            directoryPath: temporaryDirectory.path,
        );
        final DownloadTaskEntry task = (await repository.nextQueued())!;
        final File missing = File('${temporaryDirectory.path}/missing.jpg');
        await repository.complete(
            task.id,
            blocks: <PostContentBlock>[PostImageBlock(uri: missing.uri)],
            referer: chapter.sourceUri,
        );

        expect(await repository.loadOfflineContent(work.id, chapter.id), isNull);
        final DownloadTaskEntry failed = (await repository.get(task.id))!;
        expect(failed.status, DownloadStatus.failed);
        expect(failed.errorMessage, '本地文件缺失，请重新下载');
    });
}

Work _work()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2',
    );
    return Work(
        id: 'comic:101',
        kind: LibraryKind.comic,
        title: '测试漫画',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 101,
                board: ForumBoard.comic,
                title: '测试漫画 第一话',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'comic:101:1',
                title: '第一话',
                sourceUri: uri,
                sourceTid: 101,
                sourcePid: 1001,
                order: 1,
            ),
        ],
    );
}
