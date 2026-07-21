import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';

class _MockCoverRepository extends Mock implements CoverRepository
{
}

void main()
{
    registerFallbackValue(_work());

    testWidgets('等价作品对象重建不会重新请求封面', (WidgetTester tester) async
    {
        final _MockCoverRepository repository = _MockCoverRepository();
        when(() => repository.resolve(any())).thenAnswer((_) async => null);
        final Work first = _work();
        final Work equivalent = _work();

        await tester.pumpWidget(_app(repository, first));
        await tester.pumpAndSettle();
        await tester.pumpWidget(_app(repository, equivalent));
        await tester.pumpAndSettle();

        verify(() => repository.resolve(any())).called(1);
    });

    testWidgets('封面后台加载时稳定显示文字封面且不显示转圈', (
        WidgetTester tester,
    ) async
    {
        final Completer<Uri?> pending = Completer<Uri?>();
        final _MockCoverRepository repository = _MockCoverRepository();
        when(() => repository.resolve(any())).thenAnswer((_) => pending.future);

        await tester.pumpWidget(_app(repository, _work()));
        await tester.pump();

        expect(find.text('测试漫画'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        pending.complete(null);
        await tester.pumpAndSettle();
    });

    testWidgets('隐藏分区不加载封面且重新显示后恢复', (
        WidgetTester tester,
    ) async
    {
        final _MockCoverRepository repository = _MockCoverRepository();
        when(() => repository.resolve(any())).thenAnswer((_) async => null);
        final Work work = _work();

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    coverRepositoryProvider.overrideWithValue(repository),
                ],
                child: MaterialApp(
                    home: TickerMode(
                        enabled: false,
                        child: WorkCover(work: work, width: 120, height: 160),
                    ),
                ),
            ),
        );
        await tester.pump();
        verifyNever(() => repository.resolve(any()));

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    coverRepositoryProvider.overrideWithValue(repository),
                ],
                child: MaterialApp(
                    home: TickerMode(
                        enabled: true,
                        child: WorkCover(work: work, width: 120, height: 160),
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();
        verify(() => repository.resolve(any())).called(1);
    });

    testWidgets('文字封面使用克制样式并移除装饰字样', (WidgetTester tester) async
    {
        await tester.pumpWidget(
            const MaterialApp(
                home: Scaffold(
                    body: SizedBox(
                        width: 120,
                        height: 160,
                        child: WorkTextCover(
                            title: '测试漫画',
                            kind: LibraryKind.comic,
                        ),
                    ),
                ),
            ),
        );

        expect(find.text('测试漫画'), findsOneWidget);
        expect(find.text('YAMIBO · 漫画'), findsNothing);
        final Iterable<Container> containers = tester.widgetList<Container>(
            find.descendant(
                of: find.byType(WorkTextCover),
                matching: find.byType(Container),
            ),
        );
        expect(
            containers.where((Container value)
            {
                final Decoration? decoration = value.decoration;
                return decoration is BoxDecoration && decoration.gradient != null;
            }),
            isEmpty,
        );
    });

    testWidgets('图片封面按实际物理显示高度解码', (WidgetTester tester) async
    {
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.resetDevicePixelRatio);
        final Work work = _work();
        final Uri uri = Uri.file('/tmp/page300-cover-test.jpg');
        final _MockCoverRepository repository = _MockCoverRepository();
        when(
            () => repository.peek(CoverRequest(work: work)),
        ).thenReturn(uri);
        when(() => repository.resolve(any())).thenAnswer((_) async => uri);

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    coverRepositoryProvider.overrideWithValue(repository),
                ],
                child: MaterialApp(
                    home: Scaffold(
                        body: SizedBox(
                            width: 90,
                            height: 140,
                            child: WorkCover(work: work),
                        ),
                    ),
                ),
            ),
        );

        final Image image = tester.widget<Image>(find.byType(Image));
        expect(image.image, isA<ResizeImage>());
        final ResizeImage provider = image.image as ResizeImage;
        expect(provider.width, isNull);
        expect(provider.height, 350);
    });

    testWidgets('滚动期间延迟未进入图片缓存的磁盘封面', (
        WidgetTester tester,
    ) async
    {
        final CoverLoadCoordinator coordinator = CoverLoadCoordinator();
        addTearDown(coordinator.dispose);
        final Object scrollable = Object();
        coordinator.scrollActive(scrollable);
        final Work work = _work();
        final Uri uri = Uri.file('/tmp/page300-cover-scroll-test.jpg');
        final _MockCoverRepository repository = _MockCoverRepository();
        when(
            () => repository.peek(CoverRequest(work: work)),
        ).thenReturn(uri);
        when(() => repository.resolve(any())).thenAnswer((_) async => uri);

        await tester.pumpWidget(
            _app(repository, work, coordinator: coordinator),
        );
        await tester.pump();

        expect(find.byType(Image), findsNothing);
        expect(find.text('测试漫画'), findsOneWidget);

        coordinator.scrollIdle(scrollable);
        await tester.pump();

        expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('滚动开始后继续显示已进入图片缓存的封面', (
        WidgetTester tester,
    ) async
    {
        final Uri uri = Uri.file('/tmp/page300-cover-cached-test.png');
        final ImageProvider<Object> provider = ResizeImage.resizeIfNeeded(
            null,
            (160 * tester.view.devicePixelRatio).round(),
            FileImage(File.fromUri(uri)),
        );
        Object? cacheKey;
        provider.obtainKey(ImageConfiguration.empty).then<void>((Object value)
        {
            cacheKey = value;
        });
        expect(cacheKey, isNotNull);
        PaintingBinding.instance.imageCache.putIfAbsent(
            cacheKey!,
            () => OneFrameImageStreamCompleter(
                Completer<ImageInfo>().future,
            ),
        );
        addTearDown(()
        {
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
        });

        final CoverLoadCoordinator coordinator = CoverLoadCoordinator();
        addTearDown(coordinator.dispose);
        coordinator.scrollActive(Object());
        final Work work = _work();
        final _MockCoverRepository repository = _MockCoverRepository();
        when(
            () => repository.peek(CoverRequest(work: work)),
        ).thenReturn(uri);
        when(() => repository.resolve(any())).thenAnswer((_) async => uri);

        await tester.pumpWidget(
            _app(repository, work, coordinator: coordinator),
        );
        await tester.pump();

        expect(find.byType(Image), findsOneWidget);
        expect(find.text('测试漫画'), findsNothing);
        coordinator.dispose();
    });
}

Widget _app(
    CoverRepository repository,
    Work work, {
    CoverLoadCoordinator? coordinator,
})
{
    return ProviderScope(
        overrides: [
            coverRepositoryProvider.overrideWithValue(repository),
            if (coordinator != null)
                coverLoadCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: WorkCover(work: work, width: 120, height: 160),
            ),
        ),
    );
}

Work _work()
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&mobile=2',
    );
    return Work(
        id: 'forum-thread:10',
        kind: LibraryKind.comic,
        title: '测试漫画',
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 10,
                board: ForumBoard.comic,
                title: '测试漫画',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'forum-thread:10',
                title: '正文',
                sourceUri: uri,
                sourceTid: 10,
            ),
        ],
    );
}
