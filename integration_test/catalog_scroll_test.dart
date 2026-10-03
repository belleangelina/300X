import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/library_home_page.dart';
import 'package:x300/features/library/presentation/cover_load_interaction_boundary.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';

class _Client extends Mock implements ForumClient {}

class _Covers extends Mock implements CoverRepository {}

// Synthetic forum data; the production aggregator and page widgets are real.
class _Catalog extends ForumLibraryRepository {
  _Catalog() : super(_Client());
  int lastPage = 0;

  @override
  Future<WorkCatalogPage> loadCatalog({
    required LibraryKind kind,
    required CatalogSection section,
    NovelSourceFilter novelSource = NovelSourceFilter.all,
    int page = 1,
    int? typeId,
  }) => _page(page);

  @override
  Future<WorkCatalogPage> loadNextCatalog({
    required WorkCatalogPage cursor,
    required CatalogSection section,
  }) => _page(cursor.pages.values.single.currentPage + 1);

  Future<WorkCatalogPage> _page(int page) async {
    final List<SourceThread> threads = List<SourceThread>.generate(150, (
      int index,
    ) {
      final int id = (page - 1) * 150 + index + 1;
      return SourceThread(
        tid: id,
        board: ForumBoard.comic,
        title: '合成作品${id ~/ 3} 第${id % 3 + 1}话',
        uri: Uri.parse('https://example.invalid/thread-$id'),
        typeName: '#長篇連載',
      );
    });
    final List<Work> works = await aggregateThreadsInBackground(threads);
    lastPage = page;
    return WorkCatalogPage(
      works: works,
      sourceThreads: threads,
      categories: const <ForumCategory>[],
      pages: <ForumBoard, ForumCatalogPage>{
        ForumBoard.comic: ForumCatalogPage(
          board: ForumBoard.comic,
          threads: threads,
          pinnedThreads: const <SourceThread>[],
          categories: const <ForumCategory>[],
          currentPage: page,
          totalPages: 8,
          nextPageUri: page < 8
              ? Uri.parse('https://example.invalid/page-${page + 1}')
              : null,
        ),
      },
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultTestTimeout = const Timeout(Duration(minutes: 5));
  testWidgets('长目录实际列表滑动、分页、网格和刷新', (tester) async {
    final repository = _Catalog();
    final covers = _Covers();
    final coordinator = CoverLoadCoordinator();
    addTearDown(coordinator.dispose);
    final directory = await Directory.systemTemp.createTemp(
      'x300-grid-covers-',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await directory.delete(recursive: true);
    });
    debugPrint('GRID_STAGE: create fixture images');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 900, 1200),
      Paint()..color = Colors.blue,
    );
    canvas.drawCircle(
      const Offset(450, 600),
      300,
      Paint()..color = Colors.amber,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(900, 1200);
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    final Map<int, Uri> coverFiles = <int, Uri>{};
    for (int tid = 1; tid <= 1200; tid++) {
      final file = File('${directory.path}/$tid.png');
      await file.writeAsBytes(bytes);
      coverFiles[tid] = file.uri;
    }
    debugPrint('GRID_STAGE: fixtures ready');
    final Set<int> resolvedCovers = <int>{};
    int pausedCoverQueries = 0;
    int coverQueries = 0;
    registerFallbackValue(
      SourceThread(
        tid: 1,
        board: ForumBoard.comic,
        title: 'fixture',
        uri: Uri.parse('https://example.invalid/thread-1'),
      ),
    );
    // Synthetic local images exercise real file decoding without forum credentials.
    final initial = await repository.loadCatalog(
      kind: LibraryKind.comic,
      section: CatalogSection.updated,
    );
    registerFallbackValue(initial.works.first);
    registerFallbackValue(CoverRequest(work: initial.works.first));
    when(() => covers.peek(any())).thenAnswer((invocation) {
      final request = invocation.positionalArguments.single as CoverRequest;
      return resolvedCovers.contains(request.sourceTid)
          ? coverFiles[request.sourceTid]
          : null;
    });
    when(() => covers.resolve(any())).thenAnswer((invocation) async {
      coverQueries++;
      if (coordinator.paused) pausedCoverQueries++;
      final work = invocation.positionalArguments.single as Work;
      resolvedCovers.add(work.primarySourceTid);
      return coverFiles[work.primarySourceTid];
    });
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettingsRepository(
      await SharedPreferences.getInstance(),
    );
    final controller = LibraryHomeController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumLibraryRepositoryProvider.overrideWithValue(repository),
          coverRepositoryProvider.overrideWithValue(covers),
          coverLoadCoordinatorProvider.overrideWithValue(coordinator),
          appSettingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
          builder: (context, child) => CoverLoadInteractionBoundary(
            coordinator: coordinator,
            child: child!,
          ),
          home: LibraryHomePage(
            kind: LibraryKind.comic,
            authState: const AuthState.authenticated('synthetic-test'),
            controller: controller,
            onLogin: () {},
            onOpenWork: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
    expect(find.byType(WorkListTile), findsWidgets);
    // Collect engine timings directly. Timeline/GC collection connects to a
    // host VM-service port that is not reachable from an Android emulator.
    final List<FrameTiming> frames = <FrameTiming>[];
    final void Function(List<FrameTiming>) collectTimings = frames.addAll;
    binding.addTimingsCallback(collectTimings);
    addTearDown(() => binding.removeTimingsCallback(collectTimings));
    debugPrint('GRID_STAGE: paginate catalog');
    for (int attempt = 0; repository.lastPage < 8 && attempt < 8; attempt++) {
      final int previousPage = repository.lastPage;
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent - 600);
      await tester.pump();
      await tester.fling(find.byType(ListView), const Offset(0, -650), 1800);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 30),
      );
      expect(repository.lastPage, greaterThan(previousPage));
      expect(repository.lastPage, lessThanOrEqualTo(8));
      expect(tester.takeException(), isNull);
    }
    expect(repository.lastPage, 8);
    expect(frames, isNotEmpty);
    binding.reportData = <String, dynamic>{
      'catalog_scroll': <String, dynamic>{
        'frame_count': frames.length,
        'worst_frame_build_time_millis':
            frames
                .map((FrameTiming frame) => frame.buildDuration.inMicroseconds)
                .reduce((int a, int b) => a > b ? a : b) /
            1000,
      },
    };
    await tester.tap(find.byKey(const ValueKey<String>('catalog-view-toggle')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
    expect(find.byType(WorkGridCard), findsWidgets);
    // Preload the entire existing catalog; this scenario never waits for a
    // new page. Revisit the same covers after their widgets have been recycled.
    final grid = find.byType(CustomScrollView).last;
    final ScrollableState gridScrollable = tester.state<ScrollableState>(
      find.descendant(of: grid, matching: find.byType(Scrollable)).first,
    );
    final position = gridScrollable.position;
    debugPrint('GRID_STAGE: preload existing grid');
    for (
      double offset = 0;
      offset < position.maxScrollExtent;
      offset += position.viewportDimension * 0.8
    ) {
      position.jumpTo(offset);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 30),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 30),
      );
    }
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
    expect(repository.lastPage, 8);
    debugPrint('GRID_STAGE: preload complete; covers=${resolvedCovers.length}');
    final int queriesBeforeGrid = coverQueries;
    final int gridFrameStart = frames.length;
    for (int sweep = 0; sweep < 12; sweep++) {
      position.jumpTo(position.maxScrollExtent * (sweep.isEven ? 0.3 : 0.7));
      await tester.pump();
      await tester.fling(grid, Offset(0, sweep.isEven ? -1200 : 1200), 9000);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.fling(grid, Offset(0, sweep.isEven ? 1200 : -1200), 9000);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 30),
      );
      expect(repository.lastPage, 8);
      expect(tester.takeException(), isNull);
    }
    expect(pausedCoverQueries, 0);
    expect(coverQueries, queriesBeforeGrid);
    expect(find.byType(Image), findsWidgets);
    binding.reportData!['warm_grid_scroll'] = <String, dynamic>{
      'frame_count': frames.length - gridFrameStart,
      'cover_queries_while_scrolling': pausedCoverQueries,
      'additional_cover_queries': coverQueries - queriesBeforeGrid,
      'preloaded_covers': resolvedCovers.length,
    };
    debugPrint('GRID_STAGE: warm flings complete');
    // Drive animation frames before awaiting animateTo, as required by widget tests.
    final refresh = controller.scrollToTopAndRefresh();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
    await refresh;
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
    expect(repository.lastPage, 1);
    expect(tester.takeException(), isNull);
    // The report is included in the captured validation log, not committed data.
    debugPrint('CATALOG_SCROLL_PERFORMANCE: ${binding.reportData}');
  });
}
