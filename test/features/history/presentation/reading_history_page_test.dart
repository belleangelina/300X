import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/history/data/reading_history_repository.dart';
import 'package:x300/features/history/presentation/reading_history_page.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';

class _EmptyCoverRepository extends Fake implements CoverRepository
{
    final Completer<Uri?> _pending = Completer<Uri?>();

    @override
    Uri? peek(CoverRequest request) => null;

    @override
    Future<Uri?> resolve(
        Work work, {
        bool finalize = false,
        int? entryTid,
        bool force = false,
    }) => _pending.future;
}

void main()
{
    testWidgets('本机记录显示阅读进度', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final ReadingHistoryRepository repository = ReadingHistoryRepository(
            database,
        );
        final Work work = _work();
        await repository.save(
            work: work,
            chapter: work.chapters.single,
            position: 4,
            progress: 0.4,
            updatedAt: DateTime(2026, 7, 10, 12, 30),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    coverRepositoryProvider.overrideWithValue(
                        _EmptyCoverRepository(),
                    ),
                ],
                child: const MaterialApp(home: ReadingHistoryPage()),
            ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('本机记录'), findsOneWidget);
        expect(find.text('测试漫画'), findsWidgets);
        expect(find.textContaining('上次看到：正文 · 40%'), findsOneWidget);

        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await database.close();
    });

    testWidgets('漫画记录和小说记录只显示对应类型', (
        WidgetTester tester,
    ) async
    {
        final AppDatabase database = AppDatabase(NativeDatabase.memory());
        final ReadingHistoryRepository repository = ReadingHistoryRepository(
            database,
        );
        final Work comic = _work();
        final Work novel = _novelWork();
        await repository.save(
            work: comic,
            chapter: comic.chapters.single,
            position: 1,
            progress: 0.1,
        );
        await repository.save(
            work: novel,
            chapter: novel.chapters.single,
            position: 2,
            progress: 0.2,
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    coverRepositoryProvider.overrideWithValue(
                        _EmptyCoverRepository(),
                    ),
                ],
                child: const MaterialApp(
                    home: ReadingHistoryPage(kind: LibraryKind.novel),
                ),
            ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('小说记录'), findsOneWidget);
        expect(find.text('测试小说'), findsWidgets);
        expect(find.text('测试漫画'), findsNothing);
        expect(find.byType(ChoiceChip), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await database.close();
    });
}

Work _work()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2',
    );
    return Work(
        id: 'work:comic',
        kind: LibraryKind.comic,
        title: '测试漫画',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 101,
                board: ForumBoard.comic,
                title: '测试漫画',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'chapter:1',
                title: '正文',
                sourceUri: uri,
                sourceTid: 101,
            ),
        ],
    );
}

Work _novelWork()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=102&mobile=2',
    );
    return Work(
        id: 'work:novel',
        kind: LibraryKind.novel,
        title: '测试小说',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 102,
                board: ForumBoard.lightNovel,
                title: '测试小说',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'novel:chapter:1',
                title: '第一章',
                sourceUri: uri,
                sourceTid: 102,
            ),
        ],
    );
}
