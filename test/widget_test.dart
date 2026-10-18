import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/auth/presentation/login_page.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  testWidgets('未登录时显示论坛登录表单', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LoginPage(authState: AuthState.unauthenticated()),
        ),
      ),
    );

    expect(find.text('300X'), findsOneWidget);
    expect(find.text('登录百合会论坛'), findsOneWidget);
    expect(find.text('用户名 / Email / UID'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('Android登录页始终提供低强调网页登录入口', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginPage(authState: AuthState.unauthenticated()),
          ),
        ),
      );

      expect(find.widgetWithText(TextButton, '网页登录'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('连续提交登录时只发起一次请求并仅返回登录页', (WidgetTester tester) async {
    final _MockAuthRepository repository = _MockAuthRepository();
    final Completer<AuthState> login = Completer<AuthState>();
    when(
      repository.restoreSession,
    ).thenAnswer((_) async => const AuthState.unauthenticated());
    when(
      () => repository.login(
        username: any(named: 'username'),
        password: any(named: 'password'),
        captcha: any(named: 'captcha'),
      ),
    ).thenAnswer((_) => login.future);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: _LoginTestHome()),
      ),
    );
    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '用户名 / Email / UID'),
      'test-user',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '密码'),
      'test-password',
    );

    final Finder submit = find.widgetWithText(ElevatedButton, '登录');
    await tester.tap(submit);
    await tester.tap(submit, warnIfMissed: false);
    await tester.pump();

    verify(
      () => repository.login(
        username: 'test-user',
        password: 'test-password',
        captcha: '',
      ),
    ).called(1);
    expect(find.text('登录中…'), findsOneWidget);

    login.complete(const AuthState.authenticated('测试账号'));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('登录请求失败时提示原因并停留在登录页', (WidgetTester tester) async {
    final _MockAuthRepository repository = _MockAuthRepository();
    when(
      repository.restoreSession,
    ).thenAnswer((_) async => const AuthState.unauthenticated());
    when(
      () => repository.login(
        username: any(named: 'username'),
        password: any(named: 'password'),
        captcha: any(named: 'captcha'),
      ),
    ).thenAnswer(
      (_) async => throw const ForumConnectionException('无法连接百合会论坛，请检查网络连接'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: _LoginTestHome()),
      ),
    );
    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '用户名 / Email / UID'),
      'test-user',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '密码'),
      'test-password',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('登录失败：无法连接百合会论坛，请检查网络连接'), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '登录'), findsOneWidget);
  });

  testWidgets('非论坛错误只提示通用原因而不显示英文异常', (WidgetTester tester) async {
    final _MockAuthRepository repository = _MockAuthRepository();
    when(
      repository.restoreSession,
    ).thenAnswer((_) async => const AuthState.unauthenticated());
    // 例如 Linux 钥匙串未解锁时，保存凭据会抛出系统 PlatformException。
    when(
      () => repository.login(
        username: any(named: 'username'),
        password: any(named: 'password'),
        captcha: any(named: 'captcha'),
      ),
    ).thenAnswer(
      (_) async => throw PlatformException(
        code: 'Libsecret error',
        message: 'Failed to unlock the keyring',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: _LoginTestHome()),
      ),
    );
    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '用户名 / Email / UID'),
      'test-user',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '密码'),
      'test-password',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('登录失败：发生未知错误，请稍后重试'), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('刷新验证码失败时提示原因', (WidgetTester tester) async {
    final _MockAuthRepository repository = _MockAuthRepository();
    when(repository.restoreSession).thenAnswer(
      (_) async => AuthState.captchaRequired(
        captcha: CaptchaChallenge(imageBytes: base64Decode(_pixelPng)),
      ),
    );
    when(repository.refreshCaptcha).thenAnswer(
      (_) async => throw const ForumConnectionException('连接百合会论坛超时，请稍后重试'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: LoginPage(authState: AuthState.unauthenticated()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(of: find.byType(Image), matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    verify(repository.refreshCaptcha).called(1);
    expect(find.text('刷新验证码失败：连接百合会论坛超时，请稍后重试'), findsOneWidget);
  });
}

const String _pixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCWQAAAAASUVORK5CYII=';

class _LoginTestHome extends StatelessWidget {
  const _LoginTestHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  const LoginPage(authState: AuthState.unauthenticated()),
            ),
          ),
          child: const Text('打开登录'),
        ),
      ),
      appBar: AppBar(title: const Text('首页')),
    );
  }
}
