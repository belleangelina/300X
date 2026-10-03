import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/cover_load_interaction_boundary.dart';
import 'package:x300/features/library/presentation/library_home_page.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';

class _Catalog extends Mock implements ForumLibraryRepository {}

class _Covers extends Mock implements CoverRepository {}

void main() {
  testWidgets('小说双分区已缓存封面列表与网格往返滑动', (tester) async {
    final catalog = _Catalog();
    final covers = _Covers();
    final coordinator = CoverLoadCoordinator();
    final directory = Directory.systemTemp.createTempSync('novel-scroll-');
    final file = File('${directory.path}/cover.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCWQAAAAASUVORK5CYII=',
        ),
      );
    addTearDown(() {
      coordinator.dispose();
      PaintingBinding.instance.imageCache.clear();
      directory.deleteSync(recursive: true);
    });
    final datasets = <NovelSourceFilter, List<Work>>{};
    for (final source in [
      NovelSourceFilter.lightNovel,
      NovelSourceFilter.literature,
    ]) {
      final board = source == NovelSourceFilter.lightNovel
          ? ForumBoard.lightNovel
          : ForumBoard.literature;
      datasets[source] = List.generate(200, (index) {
        final tid =
            (source == NovelSourceFilter.lightNovel ? 1000 : 2000) + index;
        final uri = Uri.parse('https://example.invalid/thread-$tid');
        final thread = SourceThread(
          tid: tid,
          board: board,
          title: '测试小说$tid',
          uri: uri,
        );
        return Work(
          id: 'novel:$tid',
          kind: LibraryKind.novel,
          title: thread.title,
          sourceThreads: [thread],
          chapters: [
            Chapter(id: '$tid', title: '第一章', sourceUri: uri, sourceTid: tid),
          ],
          typeName: '小说',
        );
      });
    }
    registerFallbackValue(NovelSourceFilter.all);
    registerFallbackValue(datasets.values.first.first);
    registerFallbackValue(CoverRequest(work: datasets.values.first.first));
    var loads = 0;
    when(
      () => catalog.loadCatalog(
        kind: LibraryKind.novel,
        section: CatalogSection.updated,
        novelSource: any(named: 'novelSource'),
        page: 1,
        typeId: null,
      ),
    ).thenAnswer((invocation) async {
      loads++;
      final works = datasets[invocation.namedArguments[#novelSource]]!;
      return WorkCatalogPage(
        works: works,
        sourceThreads: works.map((w) => w.primarySourceThread).toList(),
        categories: const [],
        pages: const {},
      );
    });
    when(() => covers.peek(any())).thenReturn(file.uri);
    when(() => covers.resolve(any())).thenAnswer((_) async => file.uri);
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsRepository(
      await SharedPreferences.getInstance(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumLibraryRepositoryProvider.overrideWithValue(catalog),
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
            kind: LibraryKind.novel,
            authState: const AuthState.authenticated('synthetic'),
            onLogin: () {},
            onOpenWork: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final title in ['轻小说', '文学区']) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      final list = find.byType(ListView).hitTestable();
      expect(list, findsOneWidget);
      expect(tester.widget<ListView>(list).itemExtentBuilder, isNotNull);
      await tester.fling(list, const Offset(0, -1200), 9000);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-view-toggle')).hitTestable(),
      );
      await tester.pumpAndSettle();
      final grid = find.byType(CustomScrollView).hitTestable();
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: grid, matching: find.byType(Scrollable)).first,
          )
          .position;
      for (var sweep = 0; sweep < 4; sweep++) {
        position.jumpTo(position.maxScrollExtent * 0.5);
        await tester.pump();
        await tester.fling(grid, const Offset(0, -1200), 9000);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.fling(grid, const Offset(0, 1200), 9000);
        await tester.pumpAndSettle();
      }
      expect(find.byType(WorkGridCard).hitTestable(), findsWidgets);
      final expectedBoard = title == '轻小说'
          ? ForumBoard.lightNovel
          : ForumBoard.literature;
      for (final card in tester.widgetList<WorkGridCard>(
        find.byType(WorkGridCard).hitTestable(),
      )) {
        expect(card.work.primarySourceThread.board, expectedBoard);
      }
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('轻小说'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkGridCard).hitTestable(), findsWidgets);
    expect(loads, 2);
    verifyNever(() => covers.resolve(any()));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
