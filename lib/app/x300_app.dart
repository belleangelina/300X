import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/app/app_theme.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/auth/presentation/login_page.dart';
import 'package:x300/features/home/presentation/home_shell.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/presentation/cover_load_interaction_boundary.dart';
import 'package:x300/features/settings/application/app_settings_controller.dart';
import 'package:x300/features/settings/domain/app_settings.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class X300App extends ConsumerWidget
{
    const X300App({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        final AppSettings settings = ref.watch(
            appSettingsControllerProvider,
        );
        final CoverLoadCoordinator coverLoadCoordinator = ref.watch(
            coverLoadCoordinatorProvider,
        );
        return MaterialApp(
            title: '300X',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.theme.themeMode,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const <Locale>[
                Locale('zh', 'CN'),
            ],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
            ],
            scrollBehavior: const X300ScrollBehavior(),
            builder: (BuildContext context, Widget? child)
            {
                final Widget content = CoverLoadInteractionBoundary(
                    coordinator: coverLoadCoordinator,
                    child: child ?? const SizedBox.shrink(),
                );
                if (settings.useSystemTextScale)
                {
                    return content;
                }
                return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.noScaling,
                    ),
                    child: content,
                );
            },
            home: const AuthGate(),
        );
    }
}

class X300ScrollBehavior extends MaterialScrollBehavior
{
    const X300ScrollBehavior();

    @override
    Set<PointerDeviceKind> get dragDevices =>
        PointerDeviceKind.values.toSet();
}

class AuthGate extends ConsumerWidget
{
    const AuthGate({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        final AsyncValue<AuthState> auth = ref.watch(authControllerProvider);
        return auth.when(
            data: (AuthState value)
            {
                if (value.status == AuthStatus.authenticated)
                {
                    return HomeShell(username: value.username);
                }
                return LoginPage(authState: value);
            },
            loading: () => const Scaffold(
                body: AppLoadingView(message: '正在恢复登录状态'),
            ),
            error: (Object error, StackTrace stackTrace) => Scaffold(
                body: AppErrorView(
                    message: '初始化登录状态失败：$error',
                    onRetry: () => ref.invalidate(authControllerProvider),
                ),
            ),
        );
    }
}
