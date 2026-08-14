import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/debug/debug_ui_automation.dart';

void main()
{
    tearDown(() async
    {
        await DebugUiAutomation.uninstall();
    });

    testWidgets('按 Key 点击可见按钮', (WidgetTester tester) async
    {
        bool tapped = false;
        await tester.pumpWidget(
            MaterialApp(
                home: ElevatedButton(
                    key: const Key('demo-btn'),
                    onPressed: ()
                    {
                        tapped = true;
                    },
                    child: const Text('Demo'),
                ),
            ),
        );

        final Map<String, Object?> result = await DebugUiAutomation.tap(
            'demo-btn',
        );
        await tester.pump();

        expect(result['ok'], isTrue);
        expect(result['hittable'], isTrue);
        expect(tapped, isTrue);
    });

    testWidgets('TickerMode 关闭的 Key 视为 offstage', (WidgetTester tester) async
    {
        await tester.pumpWidget(
            MaterialApp(
                home: TickerMode(
                    enabled: false,
                    child: ElevatedButton(
                        key: const Key('hidden-btn'),
                        onPressed: () {},
                        child: const Text('Hidden'),
                    ),
                ),
            ),
        );

        final Map<String, Object?> found = DebugUiAutomation.find('hidden-btn');
        expect(found['ok'], isTrue);
        expect(found['onstage'], isFalse);

        final Map<String, Object?> tapped = await DebugUiAutomation.tap(
            'hidden-btn',
        );
        expect(tapped['ok'], isFalse);
        expect(tapped['error'], 'offstage');
    });

    testWidgets('被挡住的 Key 拒绝点击', (WidgetTester tester) async
    {
        bool tapped = false;
        await tester.pumpWidget(
            MaterialApp(
                home: Stack(
                    children: <Widget>[
                        Center(
                            child: ElevatedButton(
                                key: const Key('behind-btn'),
                                onPressed: ()
                                {
                                    tapped = true;
                                },
                                child: const Text('Behind'),
                            ),
                        ),
                        const Positioned.fill(
                            child: ColoredBox(color: Color(0x88FF0000)),
                        ),
                    ],
                ),
            ),
        );

        final Map<String, Object?> result = await DebugUiAutomation.tap(
            'behind-btn',
        );
        expect(result['ok'], isFalse);
        expect(result['error'], 'not_hittable');
        expect(tapped, isFalse);
    });

    testWidgets('禁用按钮拒绝点击', (WidgetTester tester) async
    {
        await tester.pumpWidget(
            const MaterialApp(
                home: ElevatedButton(
                    key: Key('disabled-btn'),
                    onPressed: null,
                    child: Text('Disabled'),
                ),
            ),
        );

        final Map<String, Object?> result = await DebugUiAutomation.tap(
            'disabled-btn',
        );
        expect(result['ok'], isFalse);
        expect(result['error'], 'disabled');
    });

    testWidgets('按 Key 写入输入框', (WidgetTester tester) async
    {
        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
            MaterialApp(
                home: Scaffold(
                    body: TextField(
                        key: const Key('demo-field'),
                        controller: controller,
                    ),
                ),
            ),
        );

        final Map<String, Object?> result = await DebugUiAutomation.enterText(
            'demo-field',
            'hello-debug',
        );
        await tester.pump();

        expect(result['ok'], isTrue);
        expect(controller.text, 'hello-debug');
    });

    testWidgets('wait 对已有 Key 立即成功', (WidgetTester tester) async
    {
        await tester.pumpWidget(
            MaterialApp(
                home: ElevatedButton(
                    key: const Key('ready-btn'),
                    onPressed: () {},
                    child: const Text('Ready'),
                ),
            ),
        );
        final Map<String, Object?> ready = await DebugUiAutomation.waitFor(
            'ready-btn',
            timeout: const Duration(milliseconds: 200),
        );
        expect(ready['ok'], isTrue);
        expect(ready['key'], 'ready-btn');
    });

    testWidgets('dispatch 可列出 Key 并点击', (WidgetTester tester) async
    {
        bool tapped = false;
        await tester.pumpWidget(
            MaterialApp(
                home: ElevatedButton(
                    key: const Key('dispatch-btn'),
                    onPressed: ()
                    {
                        tapped = true;
                    },
                    child: const Text('Dispatch'),
                ),
            ),
        );

        final Map<String, Object?> keys = await DebugUiAutomation.dispatch(
            'keys',
            const <String, String>{},
        );
        final List<Object?> listed = keys['keys']! as List<Object?>;
        expect(
            listed.cast<Map<String, Object?>>().any(
                (Map<String, Object?> item) => item['key'] == 'dispatch-btn',
            ),
            isTrue,
        );

        final Map<String, Object?> tappedResult =
            await DebugUiAutomation.dispatch(
                'tap',
                const <String, String>{'key': 'dispatch-btn'},
            );
        await tester.pump();
        expect(tappedResult['ok'], isTrue);
        expect(tapped, isTrue);
    });
}
