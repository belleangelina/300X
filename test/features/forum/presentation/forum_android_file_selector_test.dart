import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:x300/features/forum/presentation/forum_android_file_selector.dart';

void main()
{
    test('acceptTypes 规范为去重 MIME 并识别常用扩展名', ()
    {
        expect(
            ForumAndroidFileSelectionRequest.normalizeMimeTypes(<String>[
                ' IMAGE/PNG ; q=1, .jpg ',
                'image/png',
                '.pdf',
                'invalid',
                '.unknown',
            ]),
            <String>[
                'image/png',
                'image/jpeg',
                'application/pdf',
            ],
        );
    });

    test('空或全类型声明回退到单一通配 MIME', ()
    {
        expect(
            ForumAndroidFileSelectionRequest.normalizeMimeTypes(
                const <String>[],
            ),
            const <String>['*/*'],
        );
        expect(
            ForumAndroidFileSelectionRequest.normalizeMimeTypes(
                const <String>['image/png', '*/*', 'video/mp4'],
            ),
            const <String>['*/*'],
        );
    });

    test('openMultiple 调用受控通道且不传 capture 或保存参数', () async
    {
        Map<String, Object?>? arguments;
        final ForumAndroidFileSelectorAdapter adapter =
            ForumAndroidFileSelectorAdapter(
                invoke: (Map<String, Object?> value) async
                {
                    arguments = value;
                    return <Object?>[
                        'content://documents/one',
                        'file:///tmp/two',
                        'content://documents/one',
                        'content://documents/two',
                        3,
                    ];
                },
            );

        final List<String> selected = await adapter.select(
            const FileSelectorParams(
                isCaptureEnabled: true,
                acceptTypes: <String>['image/*', '.png'],
                mode: FileSelectorMode.openMultiple,
            ),
            isEnabled: () => true,
        );

        expect(arguments, <String, Object?>{
            'mode': 'openMultiple',
            'mimeTypes': <String>['image/*', 'image/png'],
        });
        expect(arguments, isNot(contains('capture')));
        expect(
            selected,
            <String>[
                'content://documents/one',
                'content://documents/two',
            ],
        );
    });

    test('open 最多返回一个 content URI', () async
    {
        final ForumAndroidFileSelectorAdapter adapter =
            ForumAndroidFileSelectorAdapter(
                invoke: (Map<String, Object?> _) async => <Object?>[
                    'content://documents/one',
                    'content://documents/two',
                ],
            );

        expect(
            await adapter.select(
                const FileSelectorParams(
                    isCaptureEnabled: false,
                    acceptTypes: <String>['application/pdf'],
                    mode: FileSelectorMode.open,
                ),
                isEnabled: () => true,
            ),
            const <String>['content://documents/one'],
        );
    });

    test('save、页面不可用和通道失败均安全拒绝', () async
    {
        int calls = 0;
        final ForumAndroidFileSelectorAdapter adapter =
            ForumAndroidFileSelectorAdapter(
                invoke: (Map<String, Object?> _) async
                {
                    calls += 1;
                    throw StateError('channel failed');
                },
            );

        expect(
            await adapter.select(
                const FileSelectorParams(
                    isCaptureEnabled: false,
                    acceptTypes: <String>[],
                    mode: FileSelectorMode.save,
                ),
                isEnabled: () => true,
            ),
            isEmpty,
        );
        expect(
            await adapter.select(
                const FileSelectorParams(
                    isCaptureEnabled: false,
                    acceptTypes: <String>[],
                    mode: FileSelectorMode.open,
                ),
                isEnabled: () => false,
            ),
            isEmpty,
        );
        expect(calls, 0);
        expect(
            await adapter.select(
                const FileSelectorParams(
                    isCaptureEnabled: false,
                    acceptTypes: <String>[],
                    mode: FileSelectorMode.open,
                ),
                isEnabled: () => true,
            ),
            isEmpty,
        );
        expect(calls, 1);
    });

    test('并发请求拒绝后到者且页面关闭后丢弃已选 URI', () async
    {
        final Completer<Object?> response = Completer<Object?>();
        int calls = 0;
        bool enabled = true;
        final ForumAndroidFileSelectorAdapter adapter =
            ForumAndroidFileSelectorAdapter(
                invoke: (Map<String, Object?> _) async
                {
                    calls += 1;
                    return response.future;
                },
            );
        const FileSelectorParams params = FileSelectorParams(
            isCaptureEnabled: false,
            acceptTypes: <String>['image/png'],
            mode: FileSelectorMode.open,
        );

        final Future<List<String>> first = adapter.select(
            params,
            isEnabled: () => enabled,
        );
        expect(
            await adapter.select(params, isEnabled: () => enabled),
            isEmpty,
        );
        expect(calls, 1);

        enabled = false;
        response.complete(<Object?>['content://documents/one']);
        expect(await first, isEmpty);
    });
}
