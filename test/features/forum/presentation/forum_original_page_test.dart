import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/forum/presentation/forum_original_page.dart';

void main()
{
    testWidgets('Linux 不构造 WebView 并明确提示不适用', (
        WidgetTester tester,
    ) async
    {
        if (forumOriginalPageSupported)
        {
            return;
        }
        await tester.pumpWidget(MaterialApp(
            home: ForumOriginalPage(
                initialUri: Uri.parse(
                    'https://bbs.yamibo.com/forum.php?mobile=2',
                ),
            ),
        ));

        expect(find.text('当前平台不支持论坛原页'), findsOneWidget);
        expect(find.text('论坛原页'), findsOneWidget);
    });
}
