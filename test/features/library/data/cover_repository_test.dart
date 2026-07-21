import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

class _MockForumLibraryRepository extends Mock
    implements ForumLibraryRepository
{
}

class _MockForumClient extends Mock implements ForumClient
{
}

void main()
{
    registerFallbackValue(_work(1).sourceThreads.single);

    late AppDatabase database;
    late _MockForumLibraryRepository libraryRepository;
    late _MockForumClient client;
    late Directory directory;

    setUp(() async
    {
        database = AppDatabase(NativeDatabase.memory());
        libraryRepository = _MockForumLibraryRepository();
        client = _MockForumClient();
        directory = await Directory.systemTemp.createTemp(
            'page300_cover_repository_test_',
        );
    });

    tearDown(() async
    {
        await database.close();
        if (await directory.exists())
        {
            await directory.delete(recursive: true);
        }
    });

    test('首次解析帖内首图并持久缓存，之后不再请求论坛', () async
    {
        final Work work = _work(1);
        final Uri imageUri = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/cover.jpg',
        );
        final ForumThreadPage page = _page(work, imageUri: imageUri);
        when(
            () => libraryRepository.loadThread(any()),
        ).thenAnswer((_) async => page);
        when(
            () => client.getBytes(imageUri, referer: page.uri.toString()),
        ).thenAnswer((_) async => Uint8List.fromList(<int>[1, 2, 3, 4]));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
        );

        final Uri? first = await repository.resolve(work);
        final Uri? second = await repository.resolve(work);

        expect(first, isNotNull);
        expect(second, first);
        final File file = File.fromUri(first!);
        expect(await file.readAsBytes(), <int>[1, 2, 3, 4]);
        expect(await File('${file.path}.part').exists(), isFalse);
        final CoverEntry cached = await database
            .select(database.coverEntries)
            .getSingle();
        expect(cached.imageUri, imageUri.toString());
        expect(cached.filePath, file.path);
        verify(() => libraryRepository.loadThread(any())).called(1);
        verify(
            () => client.getBytes(imageUri, referer: page.uri.toString()),
        ).called(1);
    });

    test('启动维护只删除超过一天的孤儿封面文件', () async
    {
        final DateTime now = DateTime(2026, 7, 20);
        final Directory root = Directory(path.join(directory.path, 'covers'));
        await root.create();
        final File referenced = File(path.join(root.path, 'referenced.jpg'));
        final File staleOrphan = File(path.join(root.path, 'stale.jpg'));
        final File freshOrphan = File(path.join(root.path, 'fresh.jpg'));
        await referenced.writeAsBytes(<int>[1]);
        await staleOrphan.writeAsBytes(<int>[2]);
        await freshOrphan.writeAsBytes(<int>[3]);
        await referenced.setLastModified(now.subtract(const Duration(days: 2)));
        await staleOrphan.setLastModified(now.subtract(const Duration(days: 2)));
        await freshOrphan.setLastModified(now);
        await database.into(database.coverEntries).insert(
            CoverEntriesCompanion.insert(
                coverKey: 'cover:comic:work:test',
                libraryKind: 'comic',
                status: CoverEntryStatus.finalCover.name,
                imageUri: 'https://bbs.yamibo.com/referenced.jpg',
                filePath: referenced.path,
                updatedAt: now,
            ),
        );
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            now: () => now,
        );

        await repository.maintainCache();

        expect(await referenced.exists(), isTrue);
        expect(await staleOrphan.exists(), isFalse);
        expect(await freshOrphan.exists(), isTrue);
    });

    test('封面超过上限时按最旧文件清理到目标容量', () async
    {
        final DateTime now = DateTime(2026, 7, 20, 12);
        final Directory root = Directory(path.join(directory.path, 'covers'));
        await root.create();
        final List<File> files = <File>[];
        for (int index = 0; index < 4; index++)
        {
            final File file = File(path.join(root.path, 'cover-$index.jpg'));
            await file.writeAsBytes(<int>[1, 2, 3, 4]);
            await file.setLastModified(
                now.subtract(Duration(hours: 4 - index)),
            );
            files.add(file);
        }
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            maximumCacheBytes: 10,
            targetCacheBytes: 5,
            now: () => now,
        );

        await repository.maintainCache();

        expect(await files[0].exists(), isFalse);
        expect(await files[1].exists(), isFalse);
        expect(await files[2].exists(), isFalse);
        expect(await files[3].exists(), isTrue);
        expect(await repository.cacheSizeBytes(), 4);
    });

    test('固定封面自动清理水位为二百五十六 MB 到一百二十八 MB', ()
    {
        expect(
            CoverRepository.defaultMaximumCacheBytes,
            256 * 1024 * 1024,
        );
        expect(
            CoverRepository.defaultTargetCacheBytes,
            128 * 1024 * 1024,
        );
    });

    test('默认验证器接受尺寸合格且可解码的封面', () async
    {
        final Work work = _work(70);
        final Uri imageUri = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/valid-cover.png',
        );
        final ForumThreadPage page = _page(work, imageUri: imageUri);
        when(
            () => libraryRepository.loadThread(any()),
        ).thenAnswer((_) async => page);
        when(
            () => client.getBytes(imageUri, referer: page.uri.toString()),
        ).thenAnswer((_) async => base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAIAAAACAAQMAAAD58POIAAAABGdBTUEAALGPC/'
            'xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8'
            'AAAABlBMVEVvf4////+Sw/MhAAAAAWJLR0QB/wIt3gAAAAd0SU1FB+oHEgkiMySI'
            'zfkAAAAZSURBVEjHY2AYBaNgFIyCUTAKRsEooC8AAAiAAAFuKx1UAAAAJXRFWHRk'
            'YXRlOmNyZWF0ZQAyMDI2LTA3LTE4VDA5OjM0OjUxKzAwOjAwOe0qdgAAACV0RVh0'
            'ZGF0ZTptb2RpZnkAMjAyNi0wNy0xOFQwOTozNDo1MSswMDowMEiwksoAAAAASUVO'
            'RK5CYII=',
        ));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
        );

        final Uri? cover = await repository.resolve(work);

        expect(cover, isNotNull);
        expect(await File.fromUri(cover!).exists(), isTrue);
    });

    test('确认帖子没有图片后保存哨兵，重复显示不再解析', () async
    {
        final Work work = _work(2);
        when(
            () => libraryRepository.loadThread(any()),
        ).thenAnswer((_) async => _page(work));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
        );

        expect(await repository.resolve(work), isNull);
        expect(await repository.resolve(work), isNull);

        final CoverEntry cached = await database
            .select(database.coverEntries)
            .getSingle();
        expect(cached.imageUri, isEmpty);
        expect(cached.filePath, isEmpty);
        verify(() => libraryRepository.loadThread(any())).called(1);
        verifyNever(
            () => client.getBytes(any(), referer: any(named: 'referer')),
        );
    });

    test('首屏无图时通过只看楼主补探测封面', () async
    {
        final Work work = _work(4);
        final Uri imageUri = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/later-cover.jpg',
        );
        final Uri originalPosterUri = Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=4&authorid=8',
        );
        when(
            () => libraryRepository.loadThread(any()),
        ).thenAnswer((_) async => _page(
            work,
            originalPosterUri: originalPosterUri,
        ));
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                maximumOriginalPosterPages: 1,
            ),
        ).thenAnswer((_) async => _page(work, imageUri: imageUri));
        when(
            () => client.getBytes(imageUri, referer: work.primaryUri.toString()),
        ).thenAnswer((_) async => Uint8List.fromList(<int>[4, 3, 2, 1]));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
        );

        final Uri? cover = await repository.resolve(work);

        expect(cover, isNotNull);
        verify(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                maximumOriginalPosterPages: 1,
            ),
        ).called(1);
    });

    test('小说首楼无图时跳过表情包并选择明确彩插', () async
    {
        final Work work = _novelWork(40);
        final Uri memeUri = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/meme.jpg',
        );
        final Uri coverUri = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/illustration.jpg',
        );
        final Uri originalPosterUri = Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=40&authorid=8',
        );
        when(
            () => libraryRepository.loadThread(any()),
        ).thenAnswer((_) async => _novelPage(
            work,
            originalPosterUri: originalPosterUri,
        ));
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                maximumOriginalPosterPages: 1,
            ),
        ).thenAnswer((_) async => _novelPage(
            work,
            posts: <SourcePost>[
                _post(work, floor: 1),
                _post(
                    work,
                    floor: 2,
                    blocks: <PostContentBlock>[
                        const PostTextBlock(text: '本卷插图，其实只是梗图'),
                        PostImageBlock(uri: memeUri),
                    ],
                ),
                _post(
                    work,
                    floor: 3,
                    blocks: <PostContentBlock>[
                        const PostTextBlock(text: '本卷彩插'),
                        PostImageBlock(uri: coverUri),
                    ],
                ),
            ],
        ));
        when(
            () => client.getBytes(coverUri, referer: work.primaryUri.toString()),
        ).thenAnswer((_) async => Uint8List.fromList(<int>[4, 0, 4, 0]));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
        );

        expect(await repository.resolve(work), isNotNull);
        verifyNever(
            () => client.getBytes(memeUri, referer: any(named: 'referer')),
        );
        verify(
            () => client.getBytes(
                coverUri,
                referer: work.primaryUri.toString(),
            ),
        ).called(1);
    });

    test('小说后续楼层无高置信图片时固定使用文字封面', () async
    {
        final Work work = _novelWork(41);
        final Uri memeUri = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/meme-only.jpg',
        );
        final Uri originalPosterUri = Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=41&authorid=8',
        );
        when(
            () => libraryRepository.loadThread(any()),
        ).thenAnswer((_) async => _novelPage(
            work,
            originalPosterUri: originalPosterUri,
        ));
        when(
            () => libraryRepository.loadThread(
                any(),
                includeAllOriginalPosterPosts: true,
                maximumOriginalPosterPages: 1,
            ),
        ).thenAnswer((_) async => _novelPage(
            work,
            posts: <SourcePost>[
                _post(work, floor: 1),
                _post(
                    work,
                    floor: 2,
                    blocks: <PostContentBlock>[
                        const PostTextBlock(text: '图文无关，随手截图'),
                        PostImageBlock(uri: memeUri, alt: '插图'),
                    ],
                ),
            ],
        ));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
        );

        expect(await repository.resolve(work), isNull);
        expect(
            (await database.select(database.coverEntries).getSingle()).status,
            CoverEntryStatus.confirmedEmpty.name,
        );
        verifyNever(
            () => client.getBytes(any(), referer: any(named: 'referer')),
        );
    });

    test('同时出现多个作品时最多并发解析两个帖子', () async
    {
        int activeLoads = 0;
        int maximumActiveLoads = 0;
        final Completer<void> twoLoadsStarted = Completer<void>();
        final Completer<void> releaseLoads = Completer<void>();
        when(
            () => libraryRepository.loadThread(any()),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread thread =
                invocation.positionalArguments.single as SourceThread;
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
            return _page(_work(thread.tid));
        });
        when(
            () => client.getBytes(any(), referer: any(named: 'referer')),
        ).thenAnswer((_) async => Uint8List.fromList(<int>[1]));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            maximumConcurrentLoads: 2,
            imageValidator: (_) async => true,
        );
        final List<Future<Uri?>> loads = <Future<Uri?>>[
            repository.resolve(_work(1)),
            repository.resolve(_work(2)),
            repository.resolve(_work(3)),
        ];

        await twoLoadsStarted.future.timeout(const Duration(seconds: 2));
        expect(maximumActiveLoads, 2);
        releaseLoads.complete();
        await Future.wait(loads);

        expect(maximumActiveLoads, 2);
        verify(() => libraryRepository.loadThread(any())).called(3);
    });

    test('触屏和惯性滚动结束前不启动新的封面解析', () async
    {
        final CoverLoadCoordinator coordinator = CoverLoadCoordinator();
        final Object scrollable = Object();
        final Work work = _work(71);
        final CoverRequest request = CoverRequest(work: work);
        when(
            () => libraryRepository.loadThread(any()),
        ).thenAnswer((_) async => _page(work));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
            loadCoordinator: coordinator,
        );
        coordinator.pointerDown(1);
        coordinator.scrollActive(scrollable);
        coordinator.retain(request);

        final Future<Uri?> load = repository.resolve(work);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        verifyNever(() => libraryRepository.loadThread(any()));

        coordinator.pointerUp(1);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        verifyNever(() => libraryRepository.loadThread(any()));

        coordinator.scrollIdle(scrollable);
        expect(await load, isNull);
        verify(() => libraryRepository.loadThread(any())).called(1);
        coordinator.release(request);
        repository.dispose();
        coordinator.dispose();
    });

    test('离屏作品退出等待队列且不写入失败缓存', () async
    {
        final CoverLoadCoordinator coordinator = CoverLoadCoordinator();
        final Completer<void> firstStarted = Completer<void>();
        final Completer<void> releaseFirst = Completer<void>();
        when(
            () => libraryRepository.loadThread(any()),
        ).thenAnswer((Invocation invocation) async
        {
            final SourceThread source =
                    invocation.positionalArguments.single as SourceThread;
            if (source.tid == 72)
            {
                firstStarted.complete();
                await releaseFirst.future;
            }
            return _page(_work(source.tid));
        });
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            maximumConcurrentLoads: 1,
            imageValidator: (_) async => true,
            loadCoordinator: coordinator,
        );
        final Work firstWork = _work(72);
        final Work offscreenWork = _work(73);
        final CoverRequest firstRequest = CoverRequest(work: firstWork);
        final CoverRequest offscreenRequest = CoverRequest(work: offscreenWork);
        coordinator.retain(firstRequest);
        final Future<Uri?> firstLoad = repository.resolve(firstWork);
        await firstStarted.future.timeout(const Duration(seconds: 2));

        coordinator.retain(offscreenRequest);
        final Future<Uri?> offscreenLoad = repository.resolve(offscreenWork);
        coordinator.release(offscreenRequest);

        expect(
            await offscreenLoad.timeout(const Duration(seconds: 2)),
            isNull,
        );
        verify(() => libraryRepository.loadThread(any())).called(1);
        expect(await database.select(database.coverEntries).get(), isEmpty);

        releaseFirst.complete();
        expect(await firstLoad, isNull);
        coordinator.release(firstRequest);
        repository.dispose();
        coordinator.dispose();
    });

    test('已成功封面不随作品来源集合扩张失效', () async
    {
        final Work initial = _work(5);
        final Work expanded = Work(
            id: initial.id,
            kind: initial.kind,
            title: initial.title,
            sourceThreads: <SourceThread>[
                ...initial.sourceThreads,
                _work(6).sourceThreads.single,
            ],
            chapters: <Chapter>[
                ...initial.chapters,
                ..._work(6).chapters,
            ],
        );
        final Uri imageUri = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/stable-cover.jpg',
        );
        final ForumThreadPage page = _page(initial, imageUri: imageUri);
        when(
            () => libraryRepository.loadThread(any()),
        ).thenAnswer((_) async => page);
        when(
            () => client.getBytes(imageUri, referer: page.uri.toString()),
        ).thenAnswer((_) async => Uint8List.fromList(<int>[1, 2, 3, 4]));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
        );

        final Uri? first = await repository.resolve(initial);
        final Uri? second = await repository.resolve(expanded);

        expect(second, first);
        verify(() => libraryRepository.loadThread(any())).called(1);
        verify(
            () => client.getBytes(imageUri, referer: page.uri.toString()),
        ).called(1);
    });

    test('临时封面升级为正式封面并将全部来源映射到同一记录', () async
    {
        final Work provisional = _seriesWork(
            id: 'forum-thread:12',
            sourceTids: const <int>[12],
        );
        final Work indexed = _seriesWork(
            id: 'forum-work:series',
            sourceTids: const <int>[10, 11, 12],
        );
        when(() => libraryRepository.loadThread(any())).thenAnswer((
            Invocation invocation,
        ) async
        {
            final SourceThread source =
                    invocation.positionalArguments.single as SourceThread;
            return _pageForSource(
                source,
                imageUri: Uri.parse(
                    'https://bbs.yamibo.com/data/attachment/forum/${source.tid}.jpg',
                ),
            );
        });
        when(
            () => client.getBytes(any(), referer: any(named: 'referer')),
        ).thenAnswer((Invocation invocation) async
        {
            final Uri uri = invocation.positionalArguments.single as Uri;
            final int value = int.parse(path.basenameWithoutExtension(uri.path));
            return Uint8List.fromList(<int>[value]);
        });
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
        );

        final Uri? provisionalUri = await repository.resolve(provisional);
        final Uri? finalUri = await repository.resolve(
            indexed,
            finalize: true,
            entryTid: 12,
        );

        expect(finalUri, isNotNull);
        expect(finalUri, isNot(provisionalUri));
        final CoverEntry finalEntry = await (database.select(
            database.coverEntries,
        )..where(
            (CoverEntries row) => row.status.equals(
                CoverEntryStatus.finalCover.name,
            ),
        )).getSingle();
        expect(finalEntry.sourceTid, 10);
        final List<CoverAliase> aliases = await database
            .select(database.coverAliases)
            .get();
        expect(aliases.map((CoverAliase value) => value.tid).toSet(), <int>{10, 11, 12});
        expect(
            aliases.map((CoverAliase value) => value.coverKey).toSet(),
            <String>{finalEntry.coverKey},
        );

        final Uri? aliased = await repository.resolve(
            _seriesWork(id: 'forum-thread:11', sourceTids: const <int>[11]),
        );
        expect(aliased, finalUri);
        verify(() => libraryRepository.loadThread(any())).called(2);
    });

    test('正式封面根帖候选不使用目录误收的跨类型章节', () async
    {
        final Uri firstUri = Uri.parse(
            'https://bbs.yamibo.com/thread-546724-1-1.html',
        );
        final Uri secondUri = Uri.parse(
            'https://bbs.yamibo.com/thread-546725-1-1.html',
        );
        final Uri novelUri = Uri.parse(
            'https://bbs.yamibo.com/thread-521519-1-1.html',
        );
        final Work work = Work(
            id: 'forum-work:weekly-classmate',
            kind: LibraryKind.comic,
            title: '一周一次买下同班同学的那些事',
            sourceThreads: <SourceThread>[
                SourceThread(
                    tid: 546724,
                    board: ForumBoard.comic,
                    title: '一周一次买下同班同学的那些事 第1话',
                    uri: firstUri,
                ),
                SourceThread(
                    tid: 546725,
                    board: ForumBoard.comic,
                    title: '一周一次买下同班同学的那些事 第2话',
                    uri: secondUri,
                ),
            ],
            chapters: <Chapter>[
                Chapter(
                    id: 'forum-thread:546724',
                    title: '第1话',
                    sourceUri: firstUri,
                    sourceTid: 546724,
                    order: 1,
                ),
                Chapter(
                    id: 'forum-thread:546725',
                    title: '第2话',
                    sourceUri: secondUri,
                    sourceTid: 546725,
                    order: 2,
                ),
                Chapter(
                    id: 'forum-thread:521519',
                    title: '小说地址',
                    sourceUri: novelUri,
                    sourceTid: 521519,
                ),
            ],
        );
        final List<int> loadedTids = <int>[];
        when(() => libraryRepository.loadThread(any())).thenAnswer((
            Invocation invocation,
        ) async
        {
            final SourceThread source =
                    invocation.positionalArguments.single as SourceThread;
            loadedTids.add(source.tid);
            return _pageForSource(
                source,
                imageUri: Uri.parse(
                    'https://bbs.yamibo.com/data/attachment/forum/${source.tid}.jpg',
                ),
            );
        });
        when(
            () => client.getBytes(any(), referer: any(named: 'referer')),
        ).thenAnswer((_) async => Uint8List.fromList(<int>[1, 2, 3]));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
        );

        await repository.resolve(
            work,
            finalize: true,
            entryTid: 546724,
        );

        expect(loadedTids, <int>[546724]);
        final CoverEntry finalEntry = await (database.select(
            database.coverEntries,
        )..where(
            (CoverEntries row) => row.status.equals(
                CoverEntryStatus.finalCover.name,
            ),
        )).getSingle();
        expect(finalEntry.sourceTid, 546724);
    });

    test('网络失败使用五分钟和一小时退避且不误记无封面', () async
    {
        DateTime now = DateTime(2026, 7, 17, 10);
        when(
            () => libraryRepository.loadThread(any()),
        ).thenThrow(Exception('network'));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
            now: () => now,
        );
        final Work work = _work(7);

        expect(await repository.resolve(work), isNull);
        CoverEntry entry = await database.select(database.coverEntries).getSingle();
        expect(entry.status, CoverEntryStatus.retryableFailure.name);
        expect(entry.retryCount, 1);
        expect(entry.nextRetryAt, now.add(const Duration(minutes: 5)));

        expect(await repository.resolve(work), isNull);
        verify(() => libraryRepository.loadThread(any())).called(1);

        now = now.add(const Duration(minutes: 6));
        expect(await repository.resolve(work), isNull);
        entry = await database.select(database.coverEntries).getSingle();
        expect(entry.retryCount, 2);
        expect(entry.nextRetryAt, now.add(const Duration(hours: 1)));
        verify(() => libraryRepository.loadThread(any())).called(1);
    });

    test('主动重新解析失败时保留已有正式封面和文件', () async
    {
        final Work work = _seriesWork(
            id: 'forum-work:refresh',
            sourceTids: const <int>[10, 11, 12],
        );
        bool fail = false;
        when(() => libraryRepository.loadThread(any())).thenAnswer((
            Invocation invocation,
        ) async
        {
            if (fail)
            {
                throw Exception('network');
            }
            final SourceThread source =
                    invocation.positionalArguments.single as SourceThread;
            return _pageForSource(
                source,
                imageUri: Uri.parse(
                    'https://bbs.yamibo.com/data/attachment/forum/refresh.jpg',
                ),
            );
        });
        when(
            () => client.getBytes(any(), referer: any(named: 'referer')),
        ).thenAnswer((_) async => Uint8List.fromList(<int>[8, 8, 8]));
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
        );

        final Uri? initial = await repository.resolve(
            work,
            finalize: true,
            entryTid: 12,
        );
        fail = true;
        final Uri? refreshed = await repository.resolve(
            work,
            finalize: true,
            entryTid: 12,
            force: true,
        );

        expect(refreshed, initial);
        expect(await File.fromUri(initial!).exists(), isTrue);
        final CoverEntry finalEntry = await (database.select(
            database.coverEntries,
        )..where(
            (CoverEntries row) => row.coverKey.equals(
                'cover:${work.kind.name}:work:${work.id}',
            ),
        ))
            .getSingle();
        expect(finalEntry.status, CoverEntryStatus.retryableFailure.name);
        expect(finalEntry.filePath, initial.toFilePath());
    });

    test('旧成功缓存按当前作品身份惰性迁移且不重新联网', () async
    {
        final Work work = _work(8);
        final File legacyFile = File('${directory.path}/legacy.jpg');
        await legacyFile.writeAsBytes(<int>[9, 9, 9]);
        await database.into(database.coverCaches).insert(
            CoverCachesCompanion.insert(
                workId: work.id,
                sourceMarker: 'legacy',
                imageUri: 'https://bbs.yamibo.com/legacy.jpg',
                filePath: legacyFile.path,
                updatedAt: DateTime(2026, 7, 16),
            ),
        );
        final CoverRepository repository = CoverRepository(
            database,
            libraryRepository,
            client,
            cacheDirectory: () async => directory,
            imageValidator: (_) async => true,
        );

        final Uri? result = await repository.resolve(work);

        expect(result, legacyFile.uri);
        expect(await database.select(database.coverCaches).get(), isEmpty);
        expect(
            (await database.select(database.coverEntries).getSingle()).status,
            CoverEntryStatus.provisional.name,
        );
        verifyNever(() => libraryRepository.loadThread(any()));
    });
}

Work _work(int tid)
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
    return Work(
        id: 'comic:$tid',
        kind: LibraryKind.comic,
        title: '测试漫画 $tid',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: tid,
                board: ForumBoard.comic,
                title: '测试漫画 $tid',
                uri: uri,
                timeLabel: '2026-07-$tid',
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'comic:$tid:1',
                title: '正文',
                sourceUri: uri,
                sourceTid: tid,
            ),
        ],
    );
}

Work _novelWork(int tid)
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
    return Work(
        id: 'novel:$tid',
        kind: LibraryKind.novel,
        title: '测试小说 $tid',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: tid,
                board: ForumBoard.literature,
                title: '测试小说 $tid',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'novel:$tid:1',
                title: '第一章',
                sourceUri: uri,
                sourceTid: tid,
            ),
        ],
    );
}

ForumThreadPage _novelPage(
    Work work, {
    Uri? originalPosterUri,
    List<SourcePost>? posts,
})
{
    return ForumThreadPage(
        tid: work.primarySourceTid,
        board: ForumBoard.literature,
        title: work.title,
        uri: work.primaryUri,
        posts: posts ?? <SourcePost>[_post(work, floor: 1)],
        currentPage: 1,
        totalPages: 1,
        originalPosterUri: originalPosterUri,
    );
}

SourcePost _post(
    Work work, {
    required int floor,
    List<PostContentBlock> blocks = const <PostContentBlock>[],
})
{
    return SourcePost(
        pid: work.primarySourceTid * 10 + floor,
        tid: work.primarySourceTid,
        page: 1,
        floor: floor,
        author: 'tester',
        timeLabel: '',
        isOriginalPoster: true,
        blocks: blocks,
        links: const <ThreadLink>[],
    );
}

ForumThreadPage _page(
    Work work, {
    Uri? imageUri,
    Uri? originalPosterUri,
})
{
    return ForumThreadPage(
        tid: work.sourceThreads.single.tid,
        board: ForumBoard.comic,
        title: work.title,
        uri: work.primaryUri,
        posts: <SourcePost>[
            SourcePost(
                pid: work.sourceThreads.single.tid * 10,
                tid: work.sourceThreads.single.tid,
                page: 1,
                floor: 1,
                author: 'tester',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: <PostContentBlock>[
                    if (imageUri != null) PostImageBlock(uri: imageUri),
                ],
                links: const <ThreadLink>[],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
        originalPosterUri: originalPosterUri,
    );
}

Work _seriesWork({required String id, required List<int> sourceTids})
{
    final List<SourceThread> sources = sourceTids.map((int tid)
    {
        final Uri uri = Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
        );
        return SourceThread(
            tid: tid,
            board: ForumBoard.comic,
            title: tid == 10 ? '统一作品' : '统一作品 第${tid - 10}话',
            uri: uri,
            postedAt: DateTime(2026, 7, tid),
        );
    }).toList(growable: false);
    final List<Chapter> chapters = sources.map((SourceThread source)
    {
        return Chapter(
            id: 'forum-thread:${source.tid}',
            title: source.tid == 10 ? '正文' : '第${source.tid - 10}话',
            sourceUri: source.uri,
            sourceTid: source.tid,
            order: source.tid == 10 ? null : (source.tid - 10).toDouble(),
        );
    }).toList(growable: false);
    return Work(
        id: id,
        kind: LibraryKind.comic,
        title: '统一作品',
        sourceThreads: sources,
        chapters: chapters,
    );
}

ForumThreadPage _pageForSource(
    SourceThread source, {
    Uri? imageUri,
})
{
    return ForumThreadPage(
        tid: source.tid,
        board: source.board,
        title: source.title,
        uri: source.uri,
        posts: <SourcePost>[
            SourcePost(
                pid: source.tid * 10,
                tid: source.tid,
                page: 1,
                floor: 1,
                author: 'tester',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: <PostContentBlock>[
                    if (imageUri != null) PostImageBlock(uri: imageUri),
                ],
                links: const <ThreadLink>[],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}
