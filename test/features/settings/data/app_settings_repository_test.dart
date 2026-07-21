import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/features/settings/domain/app_settings.dart';

void main()
{
    test('设置可以完整持久化并在重启后恢复', () async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final AppSettingsRepository repository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        final AppSettings changed = repository.load().copyWith(
            theme: AppThemePreference.dark,
            useSystemTextScale: false,
            comicDirection: ReaderDirection.rightToLeft,
            comicFullScreen: true,
            comicPreloadPages: 5,
            novelDirection: ReaderDirection.leftToRight,
            novelFontSize: 24,
            novelLineHeight: 2.1,
            novelPalette: NovelReaderPalette.sepia,
            allowMobileDownloads: true,
            comicMaximumDownloads: 4,
            novelMaximumDownloads: 3,
        );

        await repository.save(changed);
        final AppSettings restored = repository.load();

        expect(restored.theme, AppThemePreference.dark);
        expect(restored.useSystemTextScale, isFalse);
        expect(restored.comicDirection, ReaderDirection.rightToLeft);
        expect(restored.comicFullScreen, isTrue);
        expect(restored.comicPreloadPages, 5);
        expect(restored.novelDirection, ReaderDirection.leftToRight);
        expect(restored.novelFontSize, 24);
        expect(restored.novelLineHeight, 2.1);
        expect(restored.novelPalette, NovelReaderPalette.sepia);
        expect(restored.allowMobileDownloads, isTrue);
        expect(restored.comicMaximumDownloads, 4);
        expect(restored.novelMaximumDownloads, 3);
    });

    test('损坏的枚举设置回退为安全默认值', () async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{
            'theme_mode': 'unknown',
            'comic_reader_direction': 'broken',
            'comic_preload_pages': 2,
            'comic_maximum_downloads': 0,
            'novel_maximum_downloads': 9,
        });
        final AppSettingsRepository repository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );

        final AppSettings settings = repository.load();

        expect(settings.theme, AppThemePreference.system);
        expect(settings.comicDirection, ReaderDirection.leftToRight);
        expect(settings.comicPreloadPages, 3);
        expect(settings.novelDirection, ReaderDirection.leftToRight);
        expect(settings.allowMobileDownloads, isTrue);
        expect(settings.comicMaximumDownloads, 1);
        expect(settings.novelMaximumDownloads, 1);
    });

    test('旧版关闭预加载设置迁移为最低一页', () async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{
            'comic_preload_pages': 0,
        });
        final AppSettingsRepository repository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );

        expect(repository.load().comicPreloadPages, 1);
    });

    test('主页视图模式按分区持久化', () async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final AppSettingsRepository repository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );

        expect(repository.catalogUsesGrid('comic_all'), isFalse);
        await repository.saveCatalogUsesGrid('comic_all', true);

        expect(repository.catalogUsesGrid('comic_all'), isTrue);
        expect(repository.catalogUsesGrid('novel_lightNovel'), isFalse);
    });

    test('详情页目录视图和章节顺序按媒体类型持久化', () async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final AppSettingsRepository repository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );

        expect(
            repository.workDirectoryUsesGrid(
                'comic',
                defaultValue: true,
            ),
            isTrue,
        );
        expect(repository.workDirectoryAscending('comic'), isTrue);

        await repository.saveWorkDirectoryUsesGrid('comic', false);
        await repository.saveWorkDirectoryAscending('comic', false);

        expect(
            repository.workDirectoryUsesGrid(
                'comic',
                defaultValue: true,
            ),
            isFalse,
        );
        expect(repository.workDirectoryAscending('comic'), isFalse);
        expect(
            repository.workDirectoryUsesGrid(
                'novel',
                defaultValue: false,
            ),
            isFalse,
        );
        expect(repository.workDirectoryAscending('novel'), isTrue);
    });
}
