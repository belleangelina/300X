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
        final Directory attachmentRoot = Directory(
            '${directory.path}/temporary',
        );
        final File attachmentFile = File(
            '${attachmentRoot.path}/forum-attachments/uid-101/result/a.pdf',
        );
        await attachmentFile.parent.create(recursive: true);
        await attachmentFile.writeAsBytes(<int>[7]);
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
                userId: 101,
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
                CacheMaintenanceRepository(
            database,
            null,
            null,
            null,
            () async => attachmentRoot,
        );
        await repository.clearTemporaryCaches();

        expect(await database.select(database.searchCaches).get(), isEmpty);
        expect(await database.select(database.favoriteCaches).get(), isEmpty);
        expect(await attachmentFile.exists(), isFalse);
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

    test('退出清当前账号缓存但保留防重封存', () async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final _MockReaderMediaRepository media =
            _MockReaderMediaRepository();
        when(media.clear).thenAnswer((_) async {});
        final Directory attachmentRoot = await Directory.systemTemp.createTemp(
            'page300_account_attachment_cache_test_',
        );
        final Directory user101Attachments = Directory(
            '${attachmentRoot.path}/forum-attachments/uid-101/result-a',
        );
        final Directory user202Attachments = Directory(
            '${attachmentRoot.path}/forum-attachments/uid-202/result-b',
        );
        await user101Attachments.create(recursive: true);
        await user202Attachments.create(recursive: true);
        await File('${user101Attachments.path}/a.pdf').writeAsBytes(<int>[1]);
        await File('${user202Attachments.path}/b.pdf').writeAsBytes(<int>[2]);
        final DateTime now = DateTime(2026, 8, 12);
        for (final int userId in <int>[101, 202])
        {
            await database.into(database.favoriteCaches).insert(
                FavoriteCachesCompanion.insert(
                    userId: userId,
                    workId: 'comic:$userId',
                    workJson: '{}',
                    recordsJson: '[]',
                    updatedAt: now,
                ),
            );
            await database.into(database.forumCaches).insert(
                ForumCachesCompanion.insert(
                    accountKey: 'uid:$userId',
                    cacheKey: 'forum:v2:index',
                    payloadJson: '{}',
                    updatedAt: now,
                ),
            );
            await database.into(database.forumReadAnchors).insert(
                ForumReadAnchorsCompanion.insert(
                    accountKey: 'uid:$userId',
                    tid: userId,
                    page: 1,
                    floor: 1,
                    updatedAt: now,
                ),
            );
            await database.into(database.forumDrafts).insert(
                ForumDraftsCompanion.insert(
                    draftId: 'community-pm:conversation:$userId',
                    accountKey: 'uid:$userId',
                    action: 'communityPm:conversation',
                    tid: Value<int?>(userId),
                    subject: '用户$userId',
                    message: '未发送草稿',
                    attachmentsJson: '{}',
                    updatedAt: now,
                ),
            );
            await database.into(database.forumDrafts).insert(
                ForumDraftsCompanion.insert(
                    draftId: 'new-thread:$userId',
                    accountKey: 'uid:$userId',
                    action: 'newThread',
                    subject: '未发送主题',
                    message: '未发送正文 $userId',
                    attachmentsJson: '[]',
                    updatedAt: now,
                ),
            );
            await database.into(database.forumActionTombstones).insert(
                ForumActionTombstonesCompanion.insert(
                    accountKey: 'uid:$userId',
                    contextKey: 'new-thread:$userId',
                    attemptId: 'attempt:$userId',
                    action: 'newThread',
                    draftContext: 'new-thread:$userId',
                    status: 'attempted',
                    createdAt: now,
                    updatedAt: now,
                ),
            );
        }
        final CacheMaintenanceRepository repository =
            CacheMaintenanceRepository(
                database,
                null,
                media,
                null,
                () async => attachmentRoot,
            );

        await repository.clearAccountCaches(101);

        expect(
            (await database.select(database.favoriteCaches).get())
                .single.userId,
            202,
        );
        expect(
            (await database.select(database.forumCaches).get())
                .single.accountKey,
            'uid:202',
        );
        expect(
            (await database.select(database.forumReadAnchors).get())
                .single.accountKey,
            'uid:202',
        );
        final List<ForumDraft> remainingDrafts =
            await database.select(database.forumDrafts).get();
        expect(remainingDrafts, hasLength(2));
        expect(
            remainingDrafts.every(
                (ForumDraft value) => value.accountKey == 'uid:202',
            ),
            isTrue,
        );
        expect(
            remainingDrafts.map((ForumDraft value) => value.draftId),
            containsAll(<String>[
                'community-pm:conversation:202',
                'new-thread:202',
            ]),
        );
        expect(
            (await database.select(database.forumActionTombstones).get())
                .map((ForumActionTombstone value) => value.accountKey),
            containsAll(<String>['uid:101', 'uid:202']),
        );
        final ForumActionTombstone retained =
            (await database.select(database.forumActionTombstones).get())
                .firstWhere(
                    (ForumActionTombstone value) =>
                        value.accountKey == 'uid:101',
                );
        expect(retained.draftContext, 'new-thread:101');
        expect(retained.attemptId, 'attempt:101');
        expect(await user101Attachments.exists(), isFalse);
        expect(await user202Attachments.exists(), isTrue);
        expect(
            await File('${user202Attachments.path}/b.pdf').readAsBytes(),
            <int>[2],
        );
        verify(media.clear).called(1);
        await database.close();
        await attachmentRoot.delete(recursive: true);
    });
}
