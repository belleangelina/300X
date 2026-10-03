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
  testWidgets('长目录实际列表滑动、分页、网格和刷新', (tester) async {
    final repository = _Catalog();
    final covers = _Covers();
    registerFallbackValue(
      SourceThread(
        tid: 1,
        board: ForumBoard.comic,
        title: 'fixture',
        uri: Uri.parse('https://example.invalid/thread-1'),
      ),
    );
    // Cover lookups are stubbed so no real forum session or content is needed.
    final initial = await repository.loadCatalog(
      kind: LibraryKind.comic,
      section: CatalogSection.updated,
    );
    registerFallbackValue(initial.works.first);
    when(() => covers.resolve(any())).thenAnswer((_) async => null);
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
          appSettingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
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
    await tester.pumpAndSettle();
    expect(find.byType(WorkListTile), findsWidgets);
    // Collect engine timings directly. Timeline/GC collection connects to a
    // host VM-service port that is not reachable from an Android emulator.
    final List<FrameTiming> frames = <FrameTiming>[];
    final void Function(List<FrameTiming>) collectTimings = frames.addAll;
    binding.addTimingsCallback(collectTimings);
    addTearDown(() => binding.removeTimingsCallback(collectTimings));
    for (int page = 2; page <= 8; page++) {
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
      await tester.pumpAndSettle();
      expect(repository.lastPage, page);
      expect(tester.takeException(), isNull);
    }
    binding.removeTimingsCallback(collectTimings);
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
    await tester.pumpAndSettle();
    expect(find.byType(WorkGridCard), findsWidgets);
    await tester.fling(
      find.byType(CustomScrollView).last,
      const Offset(0, 500),
      1500,
    );
    await tester.pumpAndSettle();
    await controller.scrollToTopAndRefresh();
    await tester.pumpAndSettle();
    expect(repository.lastPage, 1);
    expect(tester.takeException(), isNull);
    // The report is included in the captured validation log, not committed data.
    debugPrint('CATALOG_SCROLL_PERFORMANCE: ${binding.reportData}');
  });
}
