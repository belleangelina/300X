import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/features/settings/domain/app_settings.dart';

final Provider<AppSettingsRepository> appSettingsRepositoryProvider =
    Provider<AppSettingsRepository>(
        (Ref ref)
        {
            throw UnimplementedError(
                'AppSettingsRepository must be overridden at startup.',
            );
        },
    );

class AppSettingsRepository
{
    AppSettingsRepository(this._preferences);

    static const String allowMobilePreference =
        'allow_mobile_network_downloads';

    final SharedPreferences _preferences;

    bool catalogUsesGrid(String scope)
    {
        return _preferences.getBool('catalog_view_grid_$scope') ?? false;
    }

    Future<void> saveCatalogUsesGrid(String scope, bool value)
    {
        return _preferences.setBool('catalog_view_grid_$scope', value);
    }

    bool workDirectoryUsesGrid(
        String scope, {
        required bool defaultValue,
    })
    {
        return _preferences.getBool('work_directory_grid_$scope') ??
            defaultValue;
    }

    Future<void> saveWorkDirectoryUsesGrid(String scope, bool value)
    {
        return _preferences.setBool('work_directory_grid_$scope', value);
    }

    bool workDirectoryAscending(String scope)
    {
        return _preferences.getBool('work_directory_ascending_$scope') ?? true;
    }

    Future<void> saveWorkDirectoryAscending(String scope, bool value)
    {
        return _preferences.setBool(
            'work_directory_ascending_$scope',
            value,
        );
    }

    AppSettings load()
    {
        const AppSettings defaults = AppSettings();
        return AppSettings(
            theme: _enum(
                AppThemePreference.values,
                _preferences.getString('theme_mode'),
                defaults.theme,
            ),
            useSystemTextScale: _preferences.getBool(
                    'use_system_text_scale',
                ) ??
                defaults.useSystemTextScale,
            comicDirection: _enum(
                ReaderDirection.values,
                _preferences.getString('comic_reader_direction'),
                defaults.comicDirection,
            ),
            comicReverseControls: _preferences.getBool(
                    'comic_reverse_controls',
                ) ??
                defaults.comicReverseControls,
            comicFullScreen: _preferences.getBool('comic_full_screen') ??
                defaults.comicFullScreen,
            comicShowStatus: _preferences.getBool('comic_show_status') ??
                defaults.comicShowStatus,
            comicPageAnimation: _preferences.getBool(
                    'comic_page_animation',
                ) ??
                defaults.comicPageAnimation,
            comicPreloadPages: _preloadPages(
                _preferences.getInt('comic_preload_pages'),
                defaults.comicPreloadPages,
            ),
            novelDirection: _enum(
                ReaderDirection.values,
                _preferences.getString('novel_reader_direction'),
                defaults.novelDirection,
            ),
            novelReverseControls: _preferences.getBool(
                    'novel_reverse_controls',
                ) ??
                defaults.novelReverseControls,
            novelShowStatus: _preferences.getBool('novel_show_status') ??
                defaults.novelShowStatus,
            novelPageAnimation: _preferences.getBool(
                    'novel_page_animation',
                ) ??
                defaults.novelPageAnimation,
            novelFontSize: _preferences.getDouble('novel_font_size') ??
                defaults.novelFontSize,
            novelLineHeight: _preferences.getDouble('novel_line_height') ??
                defaults.novelLineHeight,
            novelPalette: _enum(
                NovelReaderPalette.values,
                _preferences.getString('novel_reader_palette'),
                defaults.novelPalette,
            ),
            allowMobileDownloads: _preferences.getBool(
                    allowMobilePreference,
                ) ??
                defaults.allowMobileDownloads,
            comicMaximumDownloads: _taskLimit(
                _preferences.getInt('comic_maximum_downloads'),
                defaults.comicMaximumDownloads,
            ),
            novelMaximumDownloads: _taskLimit(
                _preferences.getInt('novel_maximum_downloads'),
                defaults.novelMaximumDownloads,
            ),
        );
    }

    Future<void> save(AppSettings value) async
    {
        await Future.wait(<Future<bool>>[
            _preferences.setString('theme_mode', value.theme.name),
            _preferences.setBool(
                'use_system_text_scale',
                value.useSystemTextScale,
            ),
            _preferences.setString(
                'comic_reader_direction',
                value.comicDirection.name,
            ),
            _preferences.setBool(
                'comic_reverse_controls',
                value.comicReverseControls,
            ),
            _preferences.setBool(
                'comic_full_screen',
                value.comicFullScreen,
            ),
            _preferences.setBool(
                'comic_show_status',
                value.comicShowStatus,
            ),
            _preferences.setBool(
                'comic_page_animation',
                value.comicPageAnimation,
            ),
            _preferences.setInt(
                'comic_preload_pages',
                value.comicPreloadPages,
            ),
            _preferences.setString(
                'novel_reader_direction',
                value.novelDirection.name,
            ),
            _preferences.setBool(
                'novel_reverse_controls',
                value.novelReverseControls,
            ),
            _preferences.setBool(
                'novel_show_status',
                value.novelShowStatus,
            ),
            _preferences.setBool(
                'novel_page_animation',
                value.novelPageAnimation,
            ),
            _preferences.setDouble(
                'novel_font_size',
                value.novelFontSize,
            ),
            _preferences.setDouble(
                'novel_line_height',
                value.novelLineHeight,
            ),
            _preferences.setString(
                'novel_reader_palette',
                value.novelPalette.name,
            ),
            _preferences.setBool(
                allowMobilePreference,
                value.allowMobileDownloads,
            ),
            _preferences.setInt(
                'comic_maximum_downloads',
                value.comicMaximumDownloads,
            ),
            _preferences.setInt(
                'novel_maximum_downloads',
                value.novelMaximumDownloads,
            ),
        ]);
    }

    int _taskLimit(int? value, int fallback)
    {
        if (value == null || value < 1 || value > 5)
        {
            return fallback;
        }
        return value;
    }

    int _preloadPages(int? value, int fallback)
    {
        if (value == 0)
        {
            return 1;
        }
        return const <int>{1, 3, 5}.contains(value) ? value! : fallback;
    }

    T _enum<T extends Enum>(
        List<T> values,
        String? name,
        T fallback,
    )
    {
        for (final T value in values)
        {
            if (value.name == name)
            {
                return value;
            }
        }
        return fallback;
    }
}
