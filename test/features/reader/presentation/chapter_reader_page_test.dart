import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/downloads/data/download_repository.dart';
import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/history/data/reading_history_repository.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';
import 'package:x300/features/reader/data/reader_media_repository.dart';
import 'package:x300/features/reader/presentation/chapter_reader_page.dart';
import 'package:x300/features/reader/presentation/novel_paginator.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/features/settings/domain/app_settings.dart';

class _MockForumLibraryRepository extends Mock
    implements ForumLibraryRepository
{
}

class _MockDownloadRepository extends Mock implements DownloadRepository
{
}

class _RecordingReaderMediaRepository extends Fake
    implements ReaderMediaRepository
{
    final List<Uri> requests = <Uri>[];

    @override
    Uri? peek(Uri source) => null;

    @override
    Future<Uri> resolve(Uri source, {required String referer}) async
    {
        requests.add(source);
        return Uri.file('/missing/reader-media.png');
    }

    @override
    Future<void> evict(Uri source) async {}
}

class _BlockingCurrentReaderMediaRepository extends Fake
    implements ReaderMediaRepository
{
    _BlockingCurrentReaderMediaRepository(this.blocked);

    final Uri blocked;
    final Completer<Uri> blocker = Completer<Uri>();
    final List<Uri> requests = <Uri>[];

    @override
    Uri? peek(Uri source) => null;

    @override
    Future<Uri> resolve(Uri source, {required String referer})
    {
        requests.add(source);
        if (source == blocked)
        {
            return blocker.future;
        }
        return Future<Uri>.value(Uri.file('/missing/reader-media.png'));
    }

    @override
    Future<void> evict(Uri source) async {}
}

void main()
{
    late AppDatabase database;
    late DownloadRepository downloadRepository;
    late _MockForumLibraryRepository forumRepository;
    late AppSettingsRepository settingsRepository;

    setUp(() async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        database = AppDatabase(NativeDatabase.memory());
        downloadRepository = DownloadRepository(database);
        forumRepository = _MockForumLibraryRepository();
        settingsRepository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        registerFallbackValue(_work().chapters.first);
        registerFallbackValue(ForumBoard.literature);
    });

    tearDown(() async
    {
        await database.close();
    });

    testWidgets('存在离线正文时阅读器不请求论坛', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(novelDirection: ReaderDirection.vertical),
        );
        final Work work = _work();
        final Chapter chapter = work.chapters.first;
        await downloadRepository.enqueue(
            work: work,
            chapter: chapter,
            directoryPath: '',
        );
        await downloadRepository.complete(
            downloadRepository.taskId(work.id, chapter.id),
            blocks: const <PostContentBlock>[
                PostTextBlock(text: '只存在本机的离线正文'),
            ],
            referer: chapter.sourceUri,
        );
        when(
            () => forumRepository.loadChapterPage(any(), any()),
        ).thenThrow(StateError('不应请求论坛'));

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(
                        work: work,
                        chapter: chapter,
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('只存在本机的离线正文'), findsOneWidget);
        final ListView reader = tester.widget<ListView>(find.byType(ListView));
        expect(reader.childrenDelegate, isA<SliverChildBuilderDelegate>());
        verifyNever(
            () => forumRepository.loadChapterPage(any(), any()),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('离线阅读器可以切换章节并保持零论坛请求', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(novelDirection: ReaderDirection.vertical),
        );
        final Work work = _work();
        for (final Chapter chapter in work.chapters)
        {
            await downloadRepository.enqueue(
                work: work,
                chapter: chapter,
                directoryPath: '',
            );
            await downloadRepository.complete(
                downloadRepository.taskId(work.id, chapter.id),
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
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(
                        work: work,
                        chapter: work.chapters.first,
                        chapters: work.chapters,
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();
        expect(find.text('第一章离线正文'), findsOneWidget);
        final double readerWidth = tester.getSize(find.byType(Scaffold)).width;
        expect(
            tester.getSize(
                find.byKey(const Key('reader-left-page-area')),
            ).width,
            moreOrLessEquals(readerWidth * 0.3),
        );
        expect(
            tester.getSize(
                find.byKey(const Key('reader-right-page-area')),
            ).width,
            moreOrLessEquals(readerWidth * 0.3),
        );
        expect(
            tester.widget<IgnorePointer>(
                find.ancestor(
                    of: find.byKey(const Key('reader-bottom-controls')),
                    matching: find.byType(IgnorePointer),
                ).first,
            ).ignoring,
            isTrue,
        );

        await _showReaderControls(tester);

        expect(find.text('原帖'), findsOneWidget);
        expect(find.text('目录'), findsOneWidget);
        expect(find.text('设置'), findsOneWidget);
        expect(find.text('上一章'), findsNothing);
        expect(find.text('下一章'), findsNothing);

        await tester.tap(find.byKey(const Key('reader-directory-button')));
        await tester.pumpAndSettle();
        expect(find.byType(CircleAvatar), findsNothing);
        expect(find.text('第一章'), findsWidgets);
        expect(find.text('第二章'), findsOneWidget);
        Navigator.of(tester.element(find.text('第一章').last)).pop();
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('reader-next-chapter')));
        await tester.pumpAndSettle();

        expect(find.text('第二章离线正文'), findsOneWidget);
        expect(find.text('第二章'), findsOneWidget);
        await tester.tap(find.byKey(const Key('reader-original-button')));
        await tester.pumpAndSettle();
        expect(find.text('打开原帖'), findsOneWidget);
        expect(find.textContaining('当前章节原帖'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        verifyNever(
            () => forumRepository.loadChapterPage(any(), any()),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('阅读器控制层保持对比度并可强制刷新当前章节', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(novelDirection: ReaderDirection.leftToRight),
        );
        final Work work = _work();
        final Chapter chapter = work.chapters.first;
        when(
            () => forumRepository.loadChapterPage(any(), any()),
        ).thenAnswer((_) async => _novelThreadPage('刷新前正文'));
        when(
            () => forumRepository.loadChapterPage(
                any(),
                any(),
                forceReload: true,
            ),
        ).thenAnswer((_) async => _novelThreadPage('刷新后正文'));

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(work: work, chapter: chapter),
                ),
            ),
        );
        await tester.pumpAndSettle();

        expect(find.text('刷新前正文'), findsOneWidget);
        await _showReaderControls(tester);
        final Material top = tester.widget<Material>(
            find.byKey(const Key('reader-top-controls')),
        );
        final Material bottom = tester.widget<Material>(
            find.byKey(const Key('reader-bottom-controls')),
        );
        expect(top.color, isNot(const Color(0xfffafafa)));
        expect(bottom.color, top.color);
        final BuildContext originalButton = tester.element(
            find.byKey(const Key('reader-original-button')),
        );
        expect(
            TextButtonTheme.of(originalButton).style?.foregroundColor?.resolve(
                const <WidgetState>{},
            ),
            const Color(0xff333333),
        );
        final Rect pageCount = tester.getRect(
            find.byKey(const Key('reader-control-page-count')),
        );
        final Rect nextChapter = tester.getRect(
            find.byKey(const Key('reader-next-chapter')),
        );
        expect(pageCount.right, lessThanOrEqualTo(nextChapter.left));
        final IconButton previousButton = tester.widget<IconButton>(
            find.byKey(const Key('reader-previous-chapter')),
        );
        final IconButton nextButton = tester.widget<IconButton>(
            find.byKey(const Key('reader-next-chapter')),
        );
        expect(previousButton.color, const Color(0xff333333));
        expect(nextButton.color, previousButton.color);
        expect(
            previousButton.disabledColor,
            const Color(0xff333333).withValues(alpha: 0.35),
        );

        await tester.tap(find.byKey(const Key('reader-refresh-button')));
        await tester.pumpAndSettle();

        expect(find.text('刷新后正文'), findsOneWidget);
        verify(
            () => forumRepository.loadChapterPage(
                any(),
                any(),
                forceReload: true,
            ),
        ).called(1);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('正文受限提示从中间入口打开章节精确原帖', (
        WidgetTester tester,
    ) async
    {
        final Uri sourceUri = Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&'
            'ptid=550739&pid=41238910&mobile=2',
        );
        final Chapter chapter = Chapter(
            id: 'forum-post:550739:41238910',
            title: '第100话 正解',
            sourceUri: sourceUri,
            sourceTid: 550739,
            sourcePid: 41238910,
            order: 100,
        );
        final Work work = Work(
            id: 'novel:550739',
            kind: LibraryKind.novel,
            title: '测试小说',
            sourceThreads: <SourceThread>[
                SourceThread(
                    tid: 550739,
                    board: ForumBoard.lightNovel,
                    title: '测试小说',
                    uri: sourceUri,
                ),
            ],
            chapters: <Chapter>[chapter],
        );
        when(
            () => forumRepository.loadChapterPage(any(), any()),
        ).thenAnswer(
            (_) async => ForumThreadPage(
                tid: 550739,
                board: ForumBoard.lightNovel,
                title: '测试小说',
                uri: Uri.parse(
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&'
                    'tid=550739&page=34&mobile=2#pid41238910',
                ),
                posts: <SourcePost>[
                    SourcePost(
                        pid: 1,
                        tid: 550739,
                        page: 34,
                        floor: 1,
                        author: '读者',
                        timeLabel: '',
                        isOriginalPoster: true,
                        blocks: const <PostContentBlock>[],
                        links: const <ThreadLink>[],
                    ),
                ],
                currentPage: 34,
                totalPages: 37,
            ),
        );
        String? launchedUrl;
        const MethodChannel channel = MethodChannel(
            'plugins.flutter.io/url_launcher',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (MethodCall call) async
            {
                launchedUrl = (call.arguments as Map<Object?, Object?>)['url']
                        as String?;
                return true;
            },
        );
        addTearDown(
            () => tester.binding.defaultBinaryMessenger
                    .setMockMethodCallHandler(channel, null),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(work: work, chapter: chapter),
                ),
            ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('点击重试'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '打开'));
        await tester.pumpAndSettle();

        expect(launchedUrl, sourceUri.toString());

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('横向阅读关闭动画后点击右侧立即翻到下一页', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(
                novelDirection: ReaderDirection.leftToRight,
                novelPageAnimation: false,
            ),
        );
        final Work work = _work();
        final Chapter chapter = work.chapters.first;
        await downloadRepository.enqueue(
            work: work,
            chapter: chapter,
            directoryPath: '',
        );
        await downloadRepository.complete(
            downloadRepository.taskId(work.id, chapter.id),
            blocks: <PostContentBlock>[
                PostTextBlock(text: List<String>.filled(800, '甲').join()),
                PostTextBlock(text: List<String>.filled(800, '乙').join()),
            ],
            referer: chapter.sourceUri,
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(
                        work: work,
                        chapter: chapter,
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();
        final String initialStatus = _pageBadgeText(tester);
        expect(initialStatus, startsWith('1 / '));
        final String total = initialStatus.split(' / ').last;
        final Future<List<NovelPageLayout>> pagesFuture = tester
            .widget<FutureBuilder<List<NovelPageLayout>>>(
                find.byType(FutureBuilder<List<NovelPageLayout>>),
            )
            .future!;

        await tester.tap(find.byKey(const Key('reader-right-page-area')));
        await tester.pump();

        expect(_pageBadgeText(tester), '2 / $total');
        final Future<List<NovelPageLayout>> rebuiltFuture = tester
            .widget<FutureBuilder<List<NovelPageLayout>>>(
                find.byType(FutureBuilder<List<NovelPageLayout>>),
            )
            .future!;
        expect(identical(rebuiltFuture, pagesFuture), isTrue);
        verifyNever(
            () => forumRepository.loadChapterPage(any(), any()),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('小说正文不继承调试回退样式的黄色双下划线', (
        WidgetTester tester,
    ) async
    {
        final Work work = _work();
        final Chapter chapter = work.chapters.first;
        await downloadRepository.enqueue(
            work: work,
            chapter: chapter,
            directoryPath: '',
        );
        await downloadRepository.complete(
            downloadRepository.taskId(work.id, chapter.id),
            blocks: const <PostContentBlock>[
                PostTextBlock(text: '没有下划线的小说正文'),
            ],
            referer: chapter.sourceUri,
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(work: work, chapter: chapter),
                ),
            ),
        );
        await tester.pumpAndSettle();

        final Text body = tester.widget<Text>(
            find.text('没有下划线的小说正文'),
        );
        expect(body.style?.decoration, TextDecoration.none);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('横向小说版心上方留白足够且正文填满底部', (
        WidgetTester tester,
    ) async
    {
        await tester.binding.setSurfaceSize(const Size(420, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await settingsRepository.save(
            const AppSettings(
                novelDirection: ReaderDirection.leftToRight,
                novelPageAnimation: false,
            ),
        );
        final Work work = _work();
        final Chapter chapter = work.chapters.first;
        await downloadRepository.enqueue(
            work: work,
            chapter: chapter,
            directoryPath: '',
        );
        await downloadRepository.complete(
            downloadRepository.taskId(work.id, chapter.id),
            blocks: <PostContentBlock>[
                PostTextBlock(text: List<String>.filled(5000, '版').join()),
            ],
            referer: chapter.sourceUri,
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(work: work, chapter: chapter),
                ),
            ),
        );
        await tester.pumpAndSettle();
        final Finder body = find.byKey(const Key('reader-novel-page-block-0'));

        expect(tester.getTopLeft(body).dy, greaterThanOrEqualTo(40));
        expect(tester.getBottomLeft(body).dy, greaterThan(580));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('开启操作反转后点击左侧翻到下一页', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(
                novelDirection: ReaderDirection.leftToRight,
                novelReverseControls: true,
                novelPageAnimation: false,
            ),
        );
        final Work work = _work();
        final Chapter chapter = work.chapters.first;
        await downloadRepository.enqueue(
            work: work,
            chapter: chapter,
            directoryPath: '',
        );
        await downloadRepository.complete(
            downloadRepository.taskId(work.id, chapter.id),
            blocks: <PostContentBlock>[
                PostTextBlock(text: List<String>.filled(800, '甲').join()),
                PostTextBlock(text: List<String>.filled(800, '乙').join()),
            ],
            referer: chapter.sourceUri,
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(
                        work: work,
                        chapter: chapter,
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();
        final String initialStatus = _pageBadgeText(tester);
        final String total = initialStatus.split(' / ').last;

        await tester.tap(find.byKey(const Key('reader-left-page-area')));
        await tester.pump();

        expect(_pageBadgeText(tester), '2 / $total');
        verifyNever(
            () => forumRepository.loadChapterPage(any(), any()),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('小说右到左分页向右滑动进入下一页', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(
                novelDirection: ReaderDirection.rightToLeft,
                novelPageAnimation: false,
            ),
        );
        final Work work = _work();
        final Chapter chapter = work.chapters.first;
        await downloadRepository.enqueue(
            work: work,
            chapter: chapter,
            directoryPath: '',
        );
        await downloadRepository.complete(
            downloadRepository.taskId(work.id, chapter.id),
            blocks: <PostContentBlock>[
                PostTextBlock(text: List<String>.filled(1600, '右').join()),
            ],
            referer: chapter.sourceUri,
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(
                        work: work,
                        chapter: chapter,
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();
        final String total = _pageBadgeText(tester).split(' / ').last;

        await tester.fling(
            find.byType(PageView),
            const Offset(500, 0),
            1200,
        );
        await tester.pumpAndSettle();
        final String actual = _pageBadgeText(tester);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        expect(actual, '2 / $total');
        verifyNever(
            () => forumRepository.loadChapterPage(any(), any()),
        );
    });

    testWidgets('漫画左右方向从侧边点击区起手滑动仍可分页', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(
                comicDirection: ReaderDirection.rightToLeft,
                comicPageAnimation: false,
            ),
        );
        final Work work = _comicWork();
        final Chapter chapter = work.chapters.first;
        final _MockDownloadRepository comicDownloads =
            _MockDownloadRepository();
        when(
            () => comicDownloads.loadOfflineContent(work.id, chapter.id),
        ).thenAnswer(
            (_) async => OfflineChapterContent(
                blocks: <PostContentBlock>[
                    PostImageBlock(uri: Uri.file('/missing/page-1.png')),
                    PostImageBlock(uri: Uri.file('/missing/page-2.png')),
                    PostImageBlock(uri: Uri.file('/missing/page-3.png')),
                ],
                referer: chapter.sourceUri,
            ),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    downloadRepositoryProvider.overrideWithValue(
                        comicDownloads,
                    ),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(
                        work: work,
                        chapter: chapter,
                    ),
                ),
            ),
        );
        for (int frame = 0; frame < 20; frame++)
        {
            await tester.pump(const Duration(milliseconds: 100));
            if (find.byKey(const Key('reader-page-badge')).evaluate().isNotEmpty)
            {
                break;
            }
        }
        await tester.pump();
        await _showReaderControls(tester);
        expect(_pageBadgeText(tester), '1 / 3');
        expect(_controlPageText(tester), '1/3');
        final DecoratedBox pageBadge = tester.widget<DecoratedBox>(
            find.byKey(const Key('reader-page-badge')),
        );
        expect(
            (pageBadge.decoration as BoxDecoration).color,
            Colors.transparent,
        );

        final Rect reader = tester.getRect(find.byType(Scaffold));
        await tester.flingFrom(
            Offset(
                reader.left + reader.width * 0.15,
                reader.top + reader.height * 0.5,
            ),
            Offset(reader.width * 0.65, 0),
            1200,
        );
        for (int frame = 0; frame < 10; frame++)
        {
            await tester.pump(const Duration(milliseconds: 100));
        }
        final String actual = _pageBadgeText(tester);
        final String controlActual = _controlPageText(tester);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(actual, '2 / 3');
        expect(controlActual, '2/3');

        await settingsRepository.save(
            const AppSettings(
                comicDirection: ReaderDirection.leftToRight,
                comicPageAnimation: false,
            ),
        );
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    downloadRepositoryProvider.overrideWithValue(
                        comicDownloads,
                    ),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(
                        work: work,
                        chapter: chapter,
                        restoreProgress: false,
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();
        final Rect leftToRightReader = tester.getRect(find.byType(Scaffold));
        await tester.flingFrom(
            Offset(
                leftToRightReader.left + leftToRightReader.width * 0.85,
                leftToRightReader.top + leftToRightReader.height * 0.5,
            ),
            Offset(-leftToRightReader.width * 0.65, 0),
            10000,
        );
        await tester.pumpAndSettle();
        expect(_pageBadgeText(tester), '2 / 3');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        verifyNever(
            () => forumRepository.loadChapterPage(any(), any()),
        );
    });

    testWidgets('漫画判断窗口内出现第二指时优先缩放且不翻页', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(
                comicDirection: ReaderDirection.rightToLeft,
                comicPageAnimation: false,
            ),
        );
        final Work work = _comicWork();
        final Chapter chapter = work.chapters.first;
        final _MockDownloadRepository comicDownloads =
                _MockDownloadRepository();
        when(
            () => comicDownloads.loadOfflineContent(work.id, chapter.id),
        ).thenAnswer(
            (_) async => OfflineChapterContent(
                blocks: <PostContentBlock>[
                    PostImageBlock(uri: Uri.file('/missing/page-1.png')),
                    PostImageBlock(uri: Uri.file('/missing/page-2.png')),
                    PostImageBlock(uri: Uri.file('/missing/page-3.png')),
                ],
                referer: chapter.sourceUri,
            ),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    downloadRepositoryProvider.overrideWithValue(
                        comicDownloads,
                    ),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(work: work, chapter: chapter),
                ),
            ),
        );
        await tester.pumpAndSettle();
        final Finder page = find.byKey(const Key('reader-comic-page-0'));
        final Finder viewer = find.descendant(
            of: page,
            matching: find.byType(InteractiveViewer),
        );
        final Rect reader = tester.getRect(find.byType(Scaffold));
        final Offset firstPosition = Offset(
            reader.left + reader.width * 0.15,
            reader.top + reader.height * 0.5,
        );
        final TestGesture first = await tester.startGesture(
            firstPosition,
            pointer: 1,
        );
        for (int step = 1; step <= 15; step++)
        {
            await first.moveBy(
                const Offset(10, 0),
                timeStamp: Duration(milliseconds: step * 4),
            );
            await tester.pump(const Duration(milliseconds: 4));
        }
        final PageController pageController = tester
                .widget<PageView>(find.byType(PageView))
                .controller!;
        expect(pageController.page, closeTo(0, 0.01));
        final TestGesture second = await tester.startGesture(
            firstPosition,
            pointer: 2,
        );
        await second.moveBy(const Offset(-100, 0));
        await first.moveBy(const Offset(100, 0));
        await tester.pump(const Duration(milliseconds: 40));
        await second.up();
        await first.up();
        await tester.pumpAndSettle();

        final TransformationController controller = tester
                .widget<InteractiveViewer>(viewer)
                .transformationController!;
        expect(_pageBadgeText(tester), '1 / 3');
        expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.1));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('从具体章节进入漫画时忽略该作品的旧进度', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(
                comicDirection: ReaderDirection.leftToRight,
                comicPageAnimation: false,
            ),
        );
        final Work work = _comicWork();
        final Chapter chapter = work.chapters.first;
        await ReadingHistoryRepository(database).save(
            work: work,
            chapter: chapter,
            position: 2,
            progress: 1,
        );
        final _MockDownloadRepository comicDownloads =
                _MockDownloadRepository();
        when(
            () => comicDownloads.loadOfflineContent(work.id, chapter.id),
        ).thenAnswer(
            (_) async => OfflineChapterContent(
                blocks: <PostContentBlock>[
                    PostImageBlock(uri: Uri.file('/missing/page-1.png')),
                    PostImageBlock(uri: Uri.file('/missing/page-2.png')),
                    PostImageBlock(uri: Uri.file('/missing/page-3.png')),
                ],
                referer: chapter.sourceUri,
            ),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    downloadRepositoryProvider.overrideWithValue(comicDownloads),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(
                        work: work,
                        chapter: chapter,
                        restoreProgress: false,
                    ),
                ),
            ),
        );
        for (int frame = 0; frame < 20; frame++)
        {
            await tester.pump(const Duration(milliseconds: 100));
            if (find.byKey(const Key('reader-control-page-count')).evaluate().isNotEmpty &&
                    _controlPageText(tester) == '1/3')
            {
                break;
            }
        }

        await _showReaderControls(tester);
        expect(_controlPageText(tester), '1/3');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
    });

    testWidgets('纵向漫画进度条显示页数且状态背景透明', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(comicDirection: ReaderDirection.vertical),
        );
        final Work work = _comicWork();
        final Chapter chapter = work.chapters.first;
        final _MockDownloadRepository comicDownloads =
                _MockDownloadRepository();
        when(
            () => comicDownloads.loadOfflineContent(work.id, chapter.id),
        ).thenAnswer(
            (_) async => OfflineChapterContent(
                blocks: <PostContentBlock>[
                    PostImageBlock(uri: Uri.file('/missing/page-1.png')),
                    PostImageBlock(uri: Uri.file('/missing/page-2.png')),
                    PostImageBlock(uri: Uri.file('/missing/page-3.png')),
                ],
                referer: chapter.sourceUri,
            ),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    downloadRepositoryProvider.overrideWithValue(
                        comicDownloads,
                    ),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(work: work, chapter: chapter),
                ),
            ),
        );
        await tester.pumpAndSettle();
        await _showReaderControls(tester);

        expect(_controlPageText(tester), '1/3');
        final DecoratedBox progressBadge = tester.widget<DecoratedBox>(
            find.byKey(const Key('reader-progress-badge')),
        );
        expect(
            (progressBadge.decoration as BoxDecoration).color,
            Colors.transparent,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
    });

    testWidgets('漫画分页默认预取后三页并为回翻保留前一页', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(
                comicDirection: ReaderDirection.leftToRight,
                comicPageAnimation: false,
                comicPreloadPages: 3,
            ),
        );
        final Work work = _comicWork();
        final Chapter chapter = work.chapters.first;
        final List<Uri> images = List<Uri>.generate(
            7,
            (int index) => Uri.parse(
                'https://bbs.yamibo.com/data/attachment/forum/page-$index.jpg',
            ),
        );
        final _MockDownloadRepository comicDownloads =
                _MockDownloadRepository();
        final _RecordingReaderMediaRepository media =
                _RecordingReaderMediaRepository();
        when(
            () => comicDownloads.loadOfflineContent(work.id, chapter.id),
        ).thenAnswer(
            (_) async => OfflineChapterContent(
                blocks: images
                        .map((Uri uri) => PostImageBlock(uri: uri))
                        .toList(growable: false),
                referer: chapter.sourceUri,
            ),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    downloadRepositoryProvider.overrideWithValue(comicDownloads),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    readerMediaRepositoryProvider.overrideWithValue(media),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(work: work, chapter: chapter),
                ),
            ),
        );
        for (int frame = 0; frame < 20; frame++)
        {
            await tester.pump(const Duration(milliseconds: 100));
            if (media.requests.toSet().containsAll(images.take(4)))
            {
                break;
            }
        }
        expect(media.requests.toSet(), containsAll(images.take(4)));
        expect(media.requests.toSet(), isNot(contains(images[4])));

        media.requests.clear();
        await tester.tap(find.byKey(const Key('reader-right-page-area')));
        for (int frame = 0; frame < 20; frame++)
        {
            await tester.pump(const Duration(milliseconds: 100));
            if (media.requests.toSet().containsAll(
                <Uri>[images[0], images[2], images[3], images[4]],
            ))
            {
                break;
            }
        }

        expect(
            media.requests.toSet(),
            containsAll(<Uri>[images[0], images[2], images[3], images[4]]),
        );
        expect(media.requests.toSet(), isNot(contains(images[5])));

        await _showReaderControls(tester);
        await tester.tap(find.byKey(const Key('reader-settings-button')));
        await tester.pumpAndSettle();
        final SegmentedButton<ReaderDirection> direction =
                tester.widget<SegmentedButton<ReaderDirection>>(
            find.byType(SegmentedButton<ReaderDirection>),
        );
        final SegmentedButton<int> preload = tester.widget<SegmentedButton<int>>(
            find.byType(SegmentedButton<int>),
        );
        expect(direction.showSelectedIcon, isFalse);
        expect(preload.showSelectedIcon, isFalse);
        expect(
            preload.segments.map((ButtonSegment<int> value) => value.value),
            <int>[1, 3, 5],
        );
        expect(find.text('预加载'), findsOneWidget);
        expect(find.text('分页预加载'), findsNothing);
        expect(find.textContaining('预取后续页'), findsNothing);
        expect(find.text('关'), findsNothing);
        expect(find.text('1页'), findsOneWidget);
        expect(find.text('3页'), findsOneWidget);
        expect(find.text('5页'), findsOneWidget);
        expect(
            tester.getSize(find.byType(BottomSheet)).height,
            lessThan(MediaQuery.sizeOf(tester.element(find.byType(BottomSheet))).height * 0.8),
        );
        expect(
            find.byKey(const Key('reader-refresh-button')),
            findsOneWidget,
        );
        final Rect pageCount = tester.getRect(
            find.byKey(const Key('reader-control-page-count')),
        );
        final Rect nextChapter = tester.getRect(
            find.byKey(const Key('reader-next-chapter')),
        );
        expect(pageCount.right, lessThanOrEqualTo(nextChapter.left));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
    });

    testWidgets('漫画放大后侧边单击不翻页且侧边双击可恢复原始比例', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(
                comicDirection: ReaderDirection.leftToRight,
                comicPageAnimation: false,
            ),
        );
        final Work work = _comicWork();
        final Chapter chapter = work.chapters.first;
        final _MockDownloadRepository comicDownloads =
                _MockDownloadRepository();
        when(
            () => comicDownloads.loadOfflineContent(work.id, chapter.id),
        ).thenAnswer(
            (_) async => OfflineChapterContent(
                blocks: <PostContentBlock>[
                    PostImageBlock(uri: Uri.file('/missing/page-1.png')),
                    PostImageBlock(uri: Uri.file('/missing/page-2.png')),
                    PostImageBlock(uri: Uri.file('/missing/page-3.png')),
                ],
                referer: chapter.sourceUri,
            ),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    downloadRepositoryProvider.overrideWithValue(
                        comicDownloads,
                    ),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(work: work, chapter: chapter),
                ),
            ),
        );
        await tester.pumpAndSettle();
        final Finder page = find.byKey(const Key('reader-comic-page-0'));
        final Finder viewer = find.descendant(
            of: page,
            matching: find.byType(InteractiveViewer),
        );
        final Offset center = tester.getCenter(page);

        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(center);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        TransformationController controller = tester
                .widget<InteractiveViewer>(viewer)
                .transformationController!;
        expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
        expect(controller.value.getMaxScaleOnAxis(), lessThan(2));
        await tester.pumpAndSettle();
        controller = tester
                .widget<InteractiveViewer>(viewer)
                .transformationController!;
        expect(controller.value.getMaxScaleOnAxis(), closeTo(2, 0.01));

        final Rect reader = tester.getRect(find.byType(Scaffold));
        final Offset leftSide = Offset(
            reader.left + reader.width * 0.15,
            reader.top + reader.height * 0.5,
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tapAt(leftSide);
        await tester.pump(const Duration(milliseconds: 400));
        expect(_pageBadgeText(tester), '1 / 3');
        controller = tester
                .widget<InteractiveViewer>(viewer)
                .transformationController!;
        expect(controller.value.getMaxScaleOnAxis(), closeTo(2, 0.01));

        await tester.tapAt(leftSide);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(leftSide);
        await tester.pumpAndSettle();
        controller = tester
                .widget<InteractiveViewer>(viewer)
                .transformationController!;
        expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.01));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });

    testWidgets('漫画当前页未完成加载时仍优先准备下一页并立即开始翻页', (
        WidgetTester tester,
    ) async
    {
        await settingsRepository.save(
            const AppSettings(
                comicDirection: ReaderDirection.leftToRight,
                comicPageAnimation: true,
                comicPreloadPages: 3,
            ),
        );
        final Work work = _comicWork();
        final Chapter chapter = work.chapters.first;
        final List<Uri> images = List<Uri>.generate(
            3,
            (int index) => Uri.parse(
                'https://bbs.yamibo.com/data/attachment/forum/delay-$index.jpg',
            ),
        );
        final _MockDownloadRepository comicDownloads =
                _MockDownloadRepository();
        final _BlockingCurrentReaderMediaRepository media =
                _BlockingCurrentReaderMediaRepository(images.first);
        when(
            () => comicDownloads.loadOfflineContent(work.id, chapter.id),
        ).thenAnswer(
            (_) async => OfflineChapterContent(
                blocks: images
                    .map((Uri uri) => PostImageBlock(uri: uri))
                    .toList(growable: false),
                referer: chapter.sourceUri,
            ),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    downloadRepositoryProvider.overrideWithValue(comicDownloads),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                    readerMediaRepositoryProvider.overrideWithValue(media),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(work: work, chapter: chapter),
                ),
            ),
        );
        for (int frame = 0; frame < 5; frame++)
        {
            await tester.pump(const Duration(milliseconds: 16));
        }

        expect(media.requests, contains(images.first));
        expect(media.requests, contains(images[1]));
        final PageController controller = tester.widget<PageView>(
            find.byType(PageView),
        ).controller!;
        await tester.tap(find.byKey(const Key('reader-right-page-area')));
        expect(controller.position.isScrollingNotifier.value, isTrue);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.page, greaterThan(0));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
            tester.widget<IgnorePointer>(
                find.ancestor(
                    of: find.byKey(const Key('reader-bottom-controls')),
                    matching: find.byType(IgnorePointer),
                ).first,
            ).ignoring,
            isTrue,
        );

        media.blocker.complete(Uri.file('/missing/current-page.png'));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
    });

    testWidgets('窗口变窄后按字符锚点恢复到最接近页面', (
        WidgetTester tester,
    ) async
    {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await settingsRepository.save(
            const AppSettings(
                novelDirection: ReaderDirection.leftToRight,
                novelPageAnimation: false,
            ),
        );
        final Work work = _work();
        final Chapter chapter = work.chapters.first;
        await downloadRepository.enqueue(
            work: work,
            chapter: chapter,
            directoryPath: '',
        );
        await downloadRepository.complete(
            downloadRepository.taskId(work.id, chapter.id),
            blocks: <PostContentBlock>[
                PostTextBlock(text: List<String>.filled(5000, '百').join()),
            ],
            referer: chapter.sourceUri,
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    appDatabaseProvider.overrideWithValue(database),
                    forumLibraryRepositoryProvider.overrideWithValue(
                        forumRepository,
                    ),
                    appSettingsRepositoryProvider.overrideWithValue(
                        settingsRepository,
                    ),
                ],
                child: MaterialApp(
                    home: ChapterReaderPage(
                        work: work,
                        chapter: chapter,
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();
        final int wideTotal = int.parse(
            _pageBadgeText(tester).split(' / ').last,
        );
        await tester.tap(find.byKey(const Key('reader-right-page-area')));
        await tester.pump(const Duration(milliseconds: 700));
        final ReadingState before = await database
            .select(database.readingStates)
            .getSingle();
        expect(before.position, greaterThan(0));

        await tester.binding.setSurfaceSize(const Size(420, 600));
        await tester.pumpAndSettle();
        final List<int> narrowStatus = _pageBadgeText(tester)
            .split(' / ')
            .map(int.parse)
            .toList(growable: false);
        await tester.pump(const Duration(milliseconds: 700));
        final ReadingState after = await database
            .select(database.readingStates)
            .getSingle();

        expect(narrowStatus.first, greaterThan(2));
        expect(narrowStatus.last, greaterThan(wideTotal));
        expect(after.position, lessThanOrEqualTo(before.position));
        expect(before.position - after.position, lessThan(500));
        verifyNever(
            () => forumRepository.loadChapterPage(any(), any()),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
    });
}

Future<void> _showReaderControls(WidgetTester tester) async
{
    final GestureDetector detector = tester
        .widgetList<GestureDetector>(find.byType(GestureDetector))
        .firstWhere(
            (GestureDetector value) =>
                    value.onTapUp != null && value.child is FutureBuilder,
        );
    final Size size = tester.getSize(find.byType(Scaffold));
    detector.onTapUp!(
        TapUpDetails(
            localPosition: size.center(Offset.zero),
            kind: PointerDeviceKind.touch,
        ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
}

String _pageBadgeText(WidgetTester tester)
{
    final Finder text = find.descendant(
        of: find.byKey(const Key('reader-page-badge')),
        matching: find.byType(Text),
    );
    return tester.widget<Text>(text).data!;
}

String _controlPageText(WidgetTester tester)
{
    final Finder text = find.descendant(
        of: find.byKey(const Key('reader-control-page-count')),
        matching: find.byType(Text),
    );
    return tester.widget<Text>(text).data!;
}

Work _work()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=202&mobile=2',
    );
    return Work(
        id: 'novel:202',
        kind: LibraryKind.novel,
        title: '测试小说',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 202,
                board: ForumBoard.literature,
                title: '测试小说 第一章',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'novel:202:1',
                title: '第一章',
                sourceUri: uri,
                sourceTid: 202,
                sourcePid: 2001,
                order: 1,
            ),
            Chapter(
                id: 'novel:202:2',
                title: '第二章',
                sourceUri: uri,
                sourceTid: 202,
                sourcePid: 2002,
                order: 2,
            ),
        ],
    );
}

Work _comicWork()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=303&mobile=2',
    );
    return Work(
        id: 'comic:303',
        kind: LibraryKind.comic,
        title: '测试漫画',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 303,
                board: ForumBoard.comic,
                title: '测试漫画',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'comic:303:1',
                title: '正文',
                sourceUri: uri,
                sourceTid: 303,
                order: 1,
            ),
        ],
    );
}

ForumThreadPage _novelThreadPage(String text)
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=202&mobile=2',
    );
    return ForumThreadPage(
        tid: 202,
        board: ForumBoard.literature,
        title: '测试小说 第一章',
        uri: uri,
        posts: <SourcePost>[
            SourcePost(
                pid: 2001,
                tid: 202,
                page: 1,
                floor: 1,
                author: 'tester',
                timeLabel: '',
                isOriginalPoster: true,
                blocks: <PostContentBlock>[PostTextBlock(text: text)],
                links: const <ThreadLink>[],
            ),
        ],
        currentPage: 1,
        totalPages: 1,
    );
}
