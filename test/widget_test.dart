import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/auth/presentation/login_page.dart';

class _MockAuthRepository extends Mock implements AuthRepository
{
}

void main()
{
    testWidgets('未登录时显示论坛登录表单', (WidgetTester tester) async
    {
        await tester.pumpWidget(
            const ProviderScope(
                child: MaterialApp(
                    home: LoginPage(
                        authState: AuthState.unauthenticated(),
                    ),
                ),
            ),
        );

        expect(find.text('300X'), findsOneWidget);
        expect(find.text('登录百合会论坛'), findsOneWidget);
        expect(find.text('用户名 / Email / UID'), findsOneWidget);
        expect(find.text('密码'), findsOneWidget);
        expect(find.text('登录'), findsOneWidget);
    });

    testWidgets('Android登录页始终提供低强调网页登录入口', (
        WidgetTester tester,
    ) async
    {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try
        {
            await tester.pumpWidget(
                const ProviderScope(
                    child: MaterialApp(
                        home: LoginPage(
                            authState: AuthState.unauthenticated(),
                        ),
                    ),
                ),
            );

            expect(
                find.widgetWithText(
                    TextButton,
                    '网页登录',
                ),
                findsOneWidget,
            );
        }
        finally
        {
            debugDefaultTargetPlatformOverride = null;
        }
    });

    testWidgets('连续提交登录时只发起一次请求并仅返回登录页', (
        WidgetTester tester,
    ) async
    {
        final _MockAuthRepository repository = _MockAuthRepository();
        final Completer<AuthState> login = Completer<AuthState>();
        when(repository.restoreSession).thenAnswer(
            (_) async => const AuthState.unauthenticated(),
        );
        when(
            () => repository.login(
                username: any(named: 'username'),
                password: any(named: 'password'),
                captcha: any(named: 'captcha'),
            ),
        ).thenAnswer((_) => login.future);

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    authRepositoryProvider.overrideWithValue(repository),
                ],
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
}

class _LoginTestHome extends StatelessWidget
{
    const _LoginTestHome();

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            body: Center(
                child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (BuildContext context) => const LoginPage(
                                authState: AuthState.unauthenticated(),
                            ),
                        ),
                    ),
                    child: const Text('打开登录'),
                ),
            ),
            appBar: AppBar(title: const Text('首页')),
        );
    }
}
