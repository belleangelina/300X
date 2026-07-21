import 'package:flutter/material.dart';

enum AppThemePreference
{
    system('跟随系统', ThemeMode.system),
    light('浅色模式', ThemeMode.light),
    dark('深色模式', ThemeMode.dark);

    const AppThemePreference(this.label, this.themeMode);

    final String label;
    final ThemeMode themeMode;
}

enum ReaderDirection
{
    leftToRight('左到右'),
    vertical('上下滚动'),
    rightToLeft('右到左');

    const ReaderDirection(this.label);

    final String label;
}

enum NovelReaderPalette
{
    light('亮色'),
    sepia('护眼'),
    dark('深色');

    const NovelReaderPalette(this.label);

    final String label;
}

class AppSettings
{
    const AppSettings({
        this.theme = AppThemePreference.system,
        this.useSystemTextScale = true,
        this.comicDirection = ReaderDirection.leftToRight,
        this.comicReverseControls = false,
        this.comicFullScreen = false,
        this.comicShowStatus = true,
        this.comicPageAnimation = true,
        this.comicPreloadPages = 3,
        this.novelDirection = ReaderDirection.leftToRight,
        this.novelReverseControls = false,
        this.novelShowStatus = true,
        this.novelPageAnimation = true,
        this.novelFontSize = 18,
        this.novelLineHeight = 1.8,
        this.novelPalette = NovelReaderPalette.light,
        this.allowMobileDownloads = true,
        this.comicMaximumDownloads = 1,
        this.novelMaximumDownloads = 1,
    });

    final AppThemePreference theme;
    final bool useSystemTextScale;
    final ReaderDirection comicDirection;
    final bool comicReverseControls;
    final bool comicFullScreen;
    final bool comicShowStatus;
    final bool comicPageAnimation;
    final int comicPreloadPages;
    final ReaderDirection novelDirection;
    final bool novelReverseControls;
    final bool novelShowStatus;
    final bool novelPageAnimation;
    final double novelFontSize;
    final double novelLineHeight;
    final NovelReaderPalette novelPalette;
    final bool allowMobileDownloads;
    final int comicMaximumDownloads;
    final int novelMaximumDownloads;

    AppSettings copyWith({
        AppThemePreference? theme,
        bool? useSystemTextScale,
        ReaderDirection? comicDirection,
        bool? comicReverseControls,
        bool? comicFullScreen,
        bool? comicShowStatus,
        bool? comicPageAnimation,
        int? comicPreloadPages,
        ReaderDirection? novelDirection,
        bool? novelReverseControls,
        bool? novelShowStatus,
        bool? novelPageAnimation,
        double? novelFontSize,
        double? novelLineHeight,
        NovelReaderPalette? novelPalette,
        bool? allowMobileDownloads,
        int? comicMaximumDownloads,
        int? novelMaximumDownloads,
    })
    {
        return AppSettings(
            theme: theme ?? this.theme,
            useSystemTextScale:
                useSystemTextScale ?? this.useSystemTextScale,
            comicDirection: comicDirection ?? this.comicDirection,
            comicReverseControls:
                comicReverseControls ?? this.comicReverseControls,
            comicFullScreen: comicFullScreen ?? this.comicFullScreen,
            comicShowStatus: comicShowStatus ?? this.comicShowStatus,
            comicPageAnimation:
                comicPageAnimation ?? this.comicPageAnimation,
            comicPreloadPages:
                comicPreloadPages ?? this.comicPreloadPages,
            novelDirection: novelDirection ?? this.novelDirection,
            novelReverseControls:
                novelReverseControls ?? this.novelReverseControls,
            novelShowStatus: novelShowStatus ?? this.novelShowStatus,
            novelPageAnimation:
                novelPageAnimation ?? this.novelPageAnimation,
            novelFontSize: novelFontSize ?? this.novelFontSize,
            novelLineHeight: novelLineHeight ?? this.novelLineHeight,
            novelPalette: novelPalette ?? this.novelPalette,
            allowMobileDownloads:
                allowMobileDownloads ?? this.allowMobileDownloads,
            comicMaximumDownloads:
                comicMaximumDownloads ?? this.comicMaximumDownloads,
            novelMaximumDownloads:
                novelMaximumDownloads ?? this.novelMaximumDownloads,
        );
    }
}
