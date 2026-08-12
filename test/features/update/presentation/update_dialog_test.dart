import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/update/domain/update_models.dart';
import 'package:x300/features/update/application/update_platform.dart';
import 'package:x300/features/update/presentation/update_dialog.dart';

void main()
{
    testWidgets('更新弹窗以 GitHub 直连为主操作并将关闭视为忽略', (
        WidgetTester tester,
    ) async
    {
        UpdatePlatform.platformOverride = 'ios';
        updateTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(()
        {
            UpdatePlatform.platformOverride = null;
            updateTargetPlatformOverride = null;
        });
        bool? ignored;
        await tester.pumpWidget(
            ProviderScope(
                child: MaterialApp(
                    home: Consumer(
                        builder: (
                            BuildContext context,
                            WidgetRef ref,
                            Widget? child,
                        ) => Scaffold(
                            body: TextButton(
                                onPressed: () async
                                {
                                    ignored = await showUpdateDialog(
                                        context,
                                        ref,
                                        _manifest(),
                                    );
                                },
                                child: const Text('显示更新'),
                            ),
                        ),
                    ),
                ),
            ),
        );

        await tester.tap(find.text('显示更新'));
        await tester.pumpAndSettle();

        expect(find.text('发现新版本 v1.0.8'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'GitHub 直连'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, '国内下载'), findsOneWidget);
        expect(find.text('忽略此版本'), findsOneWidget);
        expect(find.textContaining('SHA-256'), findsOneWidget);
        final Rect github = tester.getRect(find.text('GitHub 直连'));
        final Rect domestic = tester.getRect(find.text('国内下载'));
        final Rect ignore = tester.getRect(find.text('忽略此版本'));
        expect(github.center.dy, domestic.center.dy);
        expect(ignore.top, greaterThan(github.bottom));
        final Size githubButton = tester.getSize(
            find.widgetWithText(FilledButton, 'GitHub 直连'),
        );
        final Size domesticButton = tester.getSize(
            find.widgetWithText(OutlinedButton, '国内下载'),
        );
        expect(githubButton, domesticButton);
        expect(githubButton.height, greaterThanOrEqualTo(44));

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(ignored, isTrue);
    });
}

UpdateManifest _manifest()
{
    const String fileName = 'X300-v1.0.8-ios-unsigned.ipa';
    return UpdateManifest(
        versionName: '1.0.8',
        buildNumber: 11,
        releaseNotes: '测试更新说明',
        publishedAt: DateTime.utc(2026, 8, 12),
        artifacts: <UpdateArtifact>[
            UpdateArtifact(
                platform: 'ios',
                variant: 'unsigned',
                fileName: fileName,
                size: 1024,
                sha256: 'a' * 64,
                githubUrl: Uri.parse(
                    'https://github.com/belleangelina/300X/releases/'
                    'download/v1.0.8/$fileName',
                ),
                gitcodeUrl: Uri.parse(
                    'https://api.gitcode.com/api/v5/repos/belleangelina/'
                    '300X/releases/v1.0.8/attach_files/$fileName/download',
                ),
            ),
        ],
    );
}
