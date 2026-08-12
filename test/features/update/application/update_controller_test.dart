import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/features/settings/application/app_settings_controller.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/features/settings/domain/app_settings.dart';
import 'package:x300/features/update/application/update_controller.dart';
import 'package:x300/features/update/data/update_repository.dart';
import 'package:x300/features/update/domain/update_models.dart';

class _MockUpdateRepository extends Mock implements UpdateRepository
{
}

void main()
{
    late AppSettingsRepository settingsRepository;
    late _MockUpdateRepository updateRepository;

    setUp(() async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        settingsRepository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        updateRepository = _MockUpdateRepository();
        PackageInfo.setMockInitialValues(
            appName: '300X',
            packageName: 'com.yamibox300',
            version: '1.0.4',
            buildNumber: '7',
            buildSignature: '',
        );
    });

    test('自动检查遵守关闭开关和 24 小时间隔', () async
    {
        await settingsRepository.save(
            const AppSettings(automaticUpdateChecks: false),
        );
        final ProviderContainer disabled = _container(
            settingsRepository,
            updateRepository,
        );
        addTearDown(disabled.dispose);

        await disabled
            .read(updateControllerProvider.notifier)
            .checkAutomatically();
        verifyNever(updateRepository.fetchLatest);

        await settingsRepository.save(const AppSettings());
        disabled.read(appSettingsControllerProvider.notifier).update(
            const AppSettings(),
        );
        when(updateRepository.fetchLatest).thenAnswer(
            (_) async => _manifest(buildNumber: 11),
        );
        await disabled
            .read(updateControllerProvider.notifier)
            .checkAutomatically();
        verify(updateRepository.fetchLatest).called(1);

        await settingsRepository.saveSuccessfulUpdateCheck(DateTime.now());
        final ProviderContainer recent = _container(
            settingsRepository,
            updateRepository,
        );
        addTearDown(recent.dispose);

        await recent
            .read(updateControllerProvider.notifier)
            .checkAutomatically();
        verifyNever(updateRepository.fetchLatest);
    });

    test('自动检查不提示已忽略构建，手动检查仍返回该更新', () async
    {
        final UpdateManifest manifest = _manifest(buildNumber: 11);
        await settingsRepository.ignoreUpdateBuild(11);
        when(updateRepository.fetchLatest).thenAnswer((_) async => manifest);
        final ProviderContainer container = _container(
            settingsRepository,
            updateRepository,
        );
        addTearDown(container.dispose);

        await container
            .read(updateControllerProvider.notifier)
            .checkAutomatically();
        expect(container.read(updateControllerProvider).pending, isNull);

        final UpdateManifest? manual = await container
            .read(updateControllerProvider.notifier)
            .checkManually();
        expect(manual, same(manifest));
        expect(container.read(updateControllerProvider).pending, same(manifest));
    });

    test('自动检查失败保持静默且不记录成功时间', () async
    {
        when(updateRepository.fetchLatest).thenThrow(Exception('offline'));
        final ProviderContainer container = _container(
            settingsRepository,
            updateRepository,
        );
        addTearDown(container.dispose);

        await container
            .read(updateControllerProvider.notifier)
            .checkAutomatically();

        expect(container.read(updateControllerProvider).pending, isNull);
        expect(settingsRepository.lastSuccessfulUpdateCheck, isNull);
    });
}

ProviderContainer _container(
    AppSettingsRepository settingsRepository,
    UpdateRepository updateRepository,
)
{
    return ProviderContainer(
        overrides: [
            appSettingsRepositoryProvider.overrideWithValue(
                settingsRepository,
            ),
            updateRepositoryProvider.overrideWithValue(updateRepository),
        ],
    );
}

UpdateManifest _manifest({required int buildNumber})
{
    return UpdateManifest(
        versionName: '1.0.8',
        buildNumber: buildNumber,
        releaseNotes: '测试更新',
        publishedAt: DateTime.utc(2026, 8, 12),
        artifacts: const <UpdateArtifact>[],
    );
}
