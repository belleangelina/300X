import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/downloads/application/download_manager.dart';
import 'package:x300/features/downloads/data/download_repository.dart';
import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/features/settings/domain/app_settings.dart';

class _MockForumLibraryRepository extends Mock
    implements ForumLibraryRepository
{
}

class _MockForumClient extends Mock implements ForumClient
{
}

void main()
{
    registerFallbackValue(_work().chapters.single);

    late AppDatabase database;
    late DownloadRepository repository;
    late _MockForumLibraryRepository libraryRepository;
    late _MockForumClient client;
    late AppSettingsRepository settingsRepository;
    late DownloadManager manager;
    late Directory temporaryDirectory;

    setUp(() async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        database = AppDatabase(NativeDatabase.memory());
        repository = DownloadRepository(database);
        libraryRepository = _MockForumLibraryRepository();
        client = _MockForumClient();
        settingsRepository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        manager = DownloadManager(
            repository,
            libraryRepository,
            client,
            settingsRepository,
        );
        temporaryDirectory = await Directory.systemTemp.createTemp(
            'page300_manager_test_',
        );
    });

    tearDown(() async
    {
        manager.dispose();
        await database.close();
        if (await temporaryDirectory.exists())
        {
            await temporaryDirectory.delete(recursive: true);
        }
    });

    test('失败图片会重试并最终形成可读取的离线章节', () async
    {
        final Work work = _work();
        final Chapter chapter = work.chapters.single;
        final Uri imageUri = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/test.jpg',
        );
        final ForumThreadPage page = _page(chapter: chapter, imageUri: imageUri);
        int pageLoads = 0;
        when(
            () => libraryRepository.loadChapterPage(any(), ForumBoard.comic),
        ).thenAnswer((_) async
        {
            pageLoads++;
            return page;
        });
        int attempts = 0;
        when(
            () => client.getBytes(imageUri, referer: page.uri.toString()),
        ).thenAnswer((_) async
        {
            attempts++;
            if (attempts < 3)
            {
                throw const ForumConnectionException();
            }
            return Uint8List.fromList(<int>[1, 2, 3, 4]);
        });
        await repository.enqueue(
            work: work,
            chapter: chapter,
            directoryPath: temporaryDirectory.path,
        );

        await manager.start();
        final List<DownloadTaskEntry> tasks = await repository
                .watch(kind: LibraryKind.comic)
                .firstWhere(
                    (List<DownloadTaskEntry> value) =>
                            value.single.status == DownloadStatus.completed ||
                            value.single.status == DownloadStatus.failed,
                )
                .timeout(const Duration(seconds: 5));

        expect(pageLoads, 1);
        expect(attempts, 3);
        expect(
            tasks.single.status,
            DownloadStatus.completed,
            reason: tasks.single.errorMessage,
        );
        expect(tasks.single.completedItems, 1);
        expect(tasks.single.totalItems, 1);
        final OfflineChapterContent? offline = await repository.loadOfflineContent(
            work.id,
            chapter.id,
        );
        expect(offline, isNotNull);
        final File image = File.fromUri(
            (offline!.blocks.single as PostImageBlock).uri,
        );
        expect(await image.readAsBytes(), <int>[1, 2, 3, 4]);
        expect(await File('${image.path}.part').exists(), isFalse);
    });

    test('小说最大任务数为二时只并发处理两个章节', () async
    {
        await settingsRepository.save(
            const AppSettings(novelMaximumDownloads: 2),
        );
        final Work work = _novelWork();
        int activeLoads = 0;
        int maximumActiveLoads = 0;
        final Completer<void> twoLoadsStarted = Completer<void>();
        final Completer<void> releaseLoads = Completer<void>();
        when(
            () => libraryRepository.loadChapterPage(
                any(),
                ForumBoard.literature,
            ),
        ).thenAnswer((Invocation invocation) async
        {
            final Chapter chapter =
                invocation.positionalArguments.first as Chapter;
            activeLoads++;
            if (activeLoads > maximumActiveLoads)
            {
                maximumActiveLoads = activeLoads;
            }
            if (activeLoads == 2 && !twoLoadsStarted.isCompleted)
            {
                twoLoadsStarted.complete();
            }
            await releaseLoads.future;
            activeLoads--;
            return _textPage(chapter);
        });
        for (final Chapter chapter in work.chapters)
        {
            final Directory directory = Directory(
                '${temporaryDirectory.path}/${chapter.id}',
            );
            await directory.create(recursive: true);
            await repository.enqueue(
                work: work,
                chapter: chapter,
                directoryPath: directory.path,
            );
        }

        await manager.start();
        await twoLoadsStarted.future.timeout(const Duration(seconds: 2));
        expect(activeLoads, 2);
        expect(maximumActiveLoads, 2);
        verify(
            () => libraryRepository.loadChapterPage(
                any(),
                ForumBoard.literature,
            ),
        ).called(2);

        releaseLoads.complete();
        final List<DownloadTaskEntry> completed = await repository
            .watch(kind: LibraryKind.novel)
            .firstWhere(
                (List<DownloadTaskEntry> tasks) =>
                    tasks.length == 3 &&
                    tasks.every(
                        (DownloadTaskEntry task) =>
                            task.status == DownloadStatus.completed,
                    ),
            )
            .timeout(const Duration(seconds: 5));

        expect(completed, hasLength(3));
        expect(maximumActiveLoads, 2);
        verify(
            () => libraryRepository.loadChapterPage(
                any(),
                ForumBoard.literature,
            ),
        ).called(1);
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

ForumThreadPage _page({required Chapter chapter, required Uri imageUri})
{
    return ForumThreadPage(
        tid: chapter.sourceTid,
        board: ForumBoard.comic,
        title: '测试漫画 第一话',
        uri: chapter.sourceUri,
        posts: <SourcePost>[
            SourcePost(
                pid: chapter.sourcePid!,
                tid: chapter.sourceTid,
                page: 1,
                floor: 1,
                author: 'tester',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: <PostContentBlock>[PostImageBlock(uri: imageUri)],
                links: const <ThreadLink>[],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}

Work _novelWork()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=202&mobile=2',
    );
    final List<Chapter> chapters = List<Chapter>.generate(3, (int index)
    {
        final int value = index + 1;
        return Chapter(
            id: 'novel:202:$value',
            title: '第$value章',
            sourceUri: uri,
            sourceTid: 202,
            sourcePid: 2000 + value,
            order: value.toDouble(),
        );
    });
    return Work(
        id: 'novel:202',
        kind: LibraryKind.novel,
        title: '测试小说',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 202,
                board: ForumBoard.literature,
                title: '测试小说',
                uri: uri,
            ),
        ],
        chapters: chapters,
    );
}

ForumThreadPage _textPage(Chapter chapter)
{
    return ForumThreadPage(
        tid: chapter.sourceTid,
        board: ForumBoard.literature,
        title: chapter.title,
        uri: chapter.sourceUri,
        posts: <SourcePost>[
            SourcePost(
                pid: chapter.sourcePid!,
                tid: chapter.sourceTid,
                page: 1,
                floor: 1,
                author: 'tester',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: <PostContentBlock>[
                    PostTextBlock(text: '${chapter.title}正文'),
                ],
                links: const <ThreadLink>[],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}
