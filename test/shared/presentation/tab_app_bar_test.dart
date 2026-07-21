import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/shared/presentation/tab_app_bar.dart';

void main()
{
    testWidgets('顶部安全区不压缩标签栏', (WidgetTester tester) async
    {
        await tester.pumpWidget(
            MaterialApp(
                home: MediaQuery(
                    data: const MediaQueryData(
                        padding: EdgeInsets.only(top: 40),
                    ),
                    child: DefaultTabController(
                        length: 2,
                        child: Scaffold(
                            appBar: const TabAppBar(
                                tabs: <Tab>[
                                    Tab(text: '推荐'),
                                    Tab(text: '更新'),
                                ],
                            ),
                            body: const SizedBox(
                                key: Key('body'),
                                width: double.infinity,
                                height: double.infinity,
                            ),
                        ),
                    ),
                ),
            ),
        );

        expect(
            tester.getSize(find.byType(TabBar)).height,
            greaterThanOrEqualTo(48),
        );
        expect(tester.getTopLeft(find.byKey(const Key('body'))).dy, 96);
    });
}
