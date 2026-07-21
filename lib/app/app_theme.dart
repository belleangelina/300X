import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x300/app/app_colors.dart';

extension _LinuxFontFallbackTheme on ThemeData
{
    ThemeData withLinuxFontFallback()
    {
        if (platform != TargetPlatform.linux)
        {
            return this;
        }
        const List<String> fallback = <String>[
            'Noto Sans CJK SC',
            'Noto Sans CJK JP',
        ];
        return copyWith(
            textTheme: textTheme.apply(fontFamilyFallback: fallback),
            primaryTextTheme: primaryTextTheme.apply(
                fontFamilyFallback: fallback,
            ),
        );
    }
}

abstract final class AppTheme
{
    static final ThemeData light = ThemeData.light(
        useMaterial3: false,
    ).copyWith(
        brightness: Brightness.light,
        colorScheme: AppColors.lightScheme,
        scaffoldBackgroundColor: Colors.white,
        cardColor: Colors.white,
        appBarTheme: AppBarTheme(
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: AppColors.black333,
            centerTitle: false,
            shape: Border(
                bottom: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.2),
                    width: 1,
                ),
            ),
            iconTheme: const IconThemeData(
                color: AppColors.black333,
            ),
            titleTextStyle: const TextStyle(
                color: AppColors.black333,
                fontSize: 16,
            ),
            systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
                systemNavigationBarColor: Colors.transparent,
            ),
        ),
    ).withLinuxFontFallback();

    static final ThemeData dark = ThemeData.dark(
        useMaterial3: false,
    ).copyWith(
        brightness: Brightness.dark,
        primaryColor: Colors.blue,
        cardColor: AppColors.cardDark,
        colorScheme: AppColors.darkScheme,
        scaffoldBackgroundColor: Colors.black,
        tabBarTheme: const TabBarThemeData(
            indicatorColor: Colors.blue,
        ),
        appBarTheme: AppBarTheme(
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            centerTitle: false,
            shape: Border(
                bottom: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.2),
                    width: 1,
                ),
            ),
            iconTheme: const IconThemeData(
                color: Colors.white,
            ),
            titleTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 16,
            ),
            systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
                systemNavigationBarColor: Colors.transparent,
            ),
        ),
    ).withLinuxFontFallback();
}
