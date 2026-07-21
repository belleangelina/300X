import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/auth/presentation/login_page.dart';

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
}
