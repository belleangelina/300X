import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';
import 'package:x300/features/settings/domain/app_settings.dart';
import 'package:x300/features/settings/presentation/settings_page.dart';

class _MockCacheMaintenanceRepository extends Mock
    implements CacheMaintenanceRepository
{
}

void main()
{
    late AppSettingsRepository settingsRepository;
    late _MockCacheMaintenanceRepository maintenance;

    setUp(() async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        settingsRepository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        maintenance = _MockCacheMaintenanceRepository();
        when(maintenance.measureUsage).thenAnswer(
            (_) async => const CacheUsageSnapshot(
                temporaryBytes: 2048,
                coverBytes: 1024 * 1024,
            ),
        );
    });

    testWidgets('漫画设置与阅读器使用无对勾的内联分段选项', (
        WidgetTester tester,
    ) async
    {
        await tester.pumpWidget(_app(
            settingsRepository,
            initialIndex: 1,
            maintenance: maintenance,
        ));
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
        expect(find.text('预加载'), findsOneWidget);
        expect(find.text('分页预加载'), findsNothing);
        expect(find.text('1页'), findsOneWidget);
        expect(find.text('3页'), findsOneWidget);
        expect(find.text('5页'), findsOneWidget);
        final Finder bottomTabs = find.byKey(
            const Key('settings-bottom-tabs'),
        );
        expect(
            tester.getBottomRight(bottomTabs).dy,
            tester.getBottomRight(find.byType(Scaffold)).dy,
        );
        expect(
            find.descendant(of: bottomTabs, matching: find.byType(Icon)),
            findsNothing,
        );
        expect(find.text('更多设置'), findsOneWidget);
    });

    testWidgets('小说阅读方向与阅读主题不显示选中对勾', (
        WidgetTester tester,
    ) async
    {
        await tester.pumpWidget(_app(
            settingsRepository,
            initialIndex: 2,
            maintenance: maintenance,
        ));
        await tester.pumpAndSettle();

        final SegmentedButton<ReaderDirection> direction =
                tester.widget<SegmentedButton<ReaderDirection>>(
            find.byType(SegmentedButton<ReaderDirection>),
        );
        final SegmentedButton<NovelReaderPalette> palette =
                tester.widget<SegmentedButton<NovelReaderPalette>>(
            find.byType(SegmentedButton<NovelReaderPalette>),
        );

        expect(direction.showSelectedIcon, isFalse);
        expect(palette.showSelectedIcon, isFalse);
    });

    testWidgets('临时缓存和封面缓存分别确认后清理', (
        WidgetTester tester,
    ) async
    {
        when(maintenance.clearTemporaryCaches).thenAnswer((_) async {});
        when(maintenance.clearCoverCaches).thenAnswer((_) async {});
        await tester.pumpWidget(
            _app(
                settingsRepository,
                initialIndex: 0,
                maintenance: maintenance,
            ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('当前大小：约 2.0 KB'), findsOneWidget);
        expect(find.textContaining('当前大小：约 1.0 MB'), findsOneWidget);

        await tester.tap(
            find.descendant(
                of: find.widgetWithText(ListTile, '清除临时缓存'),
                matching: find.byType(OutlinedButton),
            ),
        );
        await tester.pumpAndSettle();
        expect(find.text('清除临时缓存？'), findsOneWidget);
        verifyNever(maintenance.clearTemporaryCaches);
        await tester.tap(find.text('确认清除'));
        await tester.pumpAndSettle();
        verify(maintenance.clearTemporaryCaches).called(1);
        verifyNever(maintenance.clearCoverCaches);

        await tester.tap(
            find.descendant(
                of: find.widgetWithText(ListTile, '清除封面缓存'),
                matching: find.byType(OutlinedButton),
            ),
        );
        await tester.pumpAndSettle();
        expect(find.text('清除封面缓存？'), findsOneWidget);
        await tester.tap(find.text('确认清除'));
        await tester.pumpAndSettle();
        verify(maintenance.clearCoverCaches).called(1);
    });
}

Widget _app(
    AppSettingsRepository settingsRepository, {
    required int initialIndex,
    CacheMaintenanceRepository? maintenance,
})
{
    return ProviderScope(
        overrides: [
            appSettingsRepositoryProvider.overrideWithValue(
                settingsRepository,
            ),
            if (maintenance != null)
                cacheMaintenanceRepositoryProvider.overrideWithValue(
                    maintenance,
                ),
        ],
        child: MaterialApp(
            home: SettingsPage(initialIndex: initialIndex),
        ),
    );
}
