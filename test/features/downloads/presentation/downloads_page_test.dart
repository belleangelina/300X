import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/downloads/data/download_repository.dart';
import 'package:x300/features/downloads/presentation/downloads_page.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/reader/presentation/chapter_reader_page.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';

class _MockCoverRepository extends Mock implements CoverRepository
{
}

class _MockForumLibraryRepository extends Mock
    implements ForumLibraryRepository
{
}

void main()
{
    late AppDatabase database;
    late DownloadRepository downloadRepository;
    late _MockCoverRepository coverRepository;
    late _MockForumLibraryRepository forumRepository;
    late AppSettingsRepository settingsRepository;

    setUp(() async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        database = AppDatabase(NativeDatabase.memory());
        downloadRepository = DownloadRepository(database);
        coverRepository = _MockCoverRepository();
        forumRepository = _MockForumLibraryRepository();
        settingsRepository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        registerFallbackValue(_work(_chapters().first));
        registerFallbackValue(_chapters().first);
        registerFallbackValue(ForumBoard.literature);
        when(
            () => coverRepository.resolve(any()),
        ).thenAnswer((_) async => null);
    });

    tearDown(() async
    {
        await database.close();
    });

    testWidgets('同一作品的已完成章节在离线阅读器中合并为目录', (
        WidgetTester tester,
    ) async
    {
        final List<Chapter> chapters = _chapters();
        for (final Chapter chapter in chapters)
        {
            final Work snapshot = _work(chapter);
            await downloadRepository.enqueue(
                work: snapshot,
                chapter: chapter,
                directoryPath: '',
            );
            await downloadRepository.complete(
                downloadRepository.taskId(snapshot.id, chapter.id),
                blocks: <PostContentBlock>[
                    PostTextBlock(text: '${chapter.title}离线正文'),
                ],
                referer: chapter.sourceUri,
            );
        }
        when(
            () => forumRepository.loadChapterPage(any(), any()),
        ).thenThrow(StateError('不应请求论坛'));

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    coverRepositoryProvider.overrideWithValue(
                        coverRepository,
                    ),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: const MaterialApp(
                    home: DownloadsPage(kind: LibraryKind.novel),
                ),
            ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WorkListTile), findsOneWidget);
        expect(find.text('测试小说'), findsWidgets);
        expect(find.byTooltip('离线阅读'), findsNothing);

        await tester.tap(find.byType(WorkListTile));
        await tester.pumpAndSettle();
        expect(find.byTooltip('离线阅读'), findsNWidgets(2));

        await tester.tap(find.byTooltip('离线阅读').first);
        await tester.pumpAndSettle();

        final bool openedSecond = find
            .text('第二章离线正文')
            .evaluate()
            .isNotEmpty;
        final ChapterReaderPage reader = tester.widget<ChapterReaderPage>(
            find.byType(ChapterReaderPage),
        );
        expect(reader.chapters, hasLength(2));
        await tester.tapAt(tester.getCenter(find.byType(Scaffold)));
        await tester.pumpAndSettle();
        await tester.tap(
            find.byKey(
                Key(
                    openedSecond
                            ? 'reader-previous-chapter'
                            : 'reader-next-chapter',
                ),
            ),
        );
        await tester.pumpAndSettle();
        expect(
            find.text(openedSecond ? '第一章离线正文' : '第二章离线正文'),
            findsOneWidget,
        );
        verifyNever(
            () => forumRepository.loadChapterPage(any(), any()),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });
}

List<Chapter> _chapters()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=303&mobile=2',
    );
    return <Chapter>[
        Chapter(
            id: 'novel:303:1',
            title: '第一章',
            sourceUri: uri,
            sourceTid: 303,
            sourcePid: 3001,
            order: 1,
        ),
        Chapter(
            id: 'novel:303:2',
            title: '第二章',
            sourceUri: uri,
            sourceTid: 303,
            sourcePid: 3002,
            order: 2,
        ),
    ];
}

Work _work(Chapter chapter)
{
    return Work(
        id: 'novel:303',
        kind: LibraryKind.novel,
        title: '测试小说',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 303,
                board: ForumBoard.literature,
                title: '测试小说',
                uri: chapter.sourceUri,
            ),
        ],
        chapters: <Chapter>[chapter],
    );
}
