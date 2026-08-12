import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/update/domain/update_models.dart';

void main()
{
    test('解析完整更新清单并选择平台产物', ()
    {
        final UpdateManifest manifest = UpdateManifest.fromJson(
            _manifestJson(),
        );

        expect(manifest.versionName, '1.0.8');
        expect(manifest.buildNumber, 11);
        expect(
            manifest.artifactFor('android', 'arm64-v8a')?.fileName,
            'X300-v1.0.8-android-arm64-v8a-release.apk',
        );
    });

    test('拒绝非项目地址和非法哈希', ()
    {
        final Map<String, Object?> json = _manifestJson();
        final List<Object?> artifacts = json['artifacts']! as List<Object?>;
        final Map<String, Object?> artifact =
            artifacts.first! as Map<String, Object?>;
        artifact['githubUrl'] = 'https://example.com/fake.apk';
        artifact['sha256'] = '1234';

        expect(
            () => UpdateManifest.fromJson(json),
            throwsFormatException,
        );
    });

    test('拒绝同平台同变体重复产物', ()
    {
        final Map<String, Object?> json = _manifestJson();
        final List<Object?> artifacts = json['artifacts']! as List<Object?>;
        artifacts.add(Map<String, Object?>.from(
            artifacts.first! as Map<String, Object?>,
        ));

        expect(
            () => UpdateManifest.fromJson(json),
            throwsFormatException,
        );
    });
}

Map<String, Object?> _manifestJson()
{
    const String fileName =
        'X300-v1.0.8-android-arm64-v8a-release.apk';
    return <String, Object?>{
        'schemaVersion': 1,
        'versionName': '1.0.8',
        'buildNumber': 11,
        'releaseNotes': '测试更新',
        'publishedAt': '2026-08-12T12:00:00Z',
        'artifacts': <Object?>[
            <String, Object?>{
                'platform': 'android',
                'variant': 'arm64-v8a',
                'fileName': fileName,
                'size': 100,
                'sha256': 'a' * 64,
                'githubUrl':
                    'https://github.com/belleangelina/300X/releases/'
                    'download/v1.0.8/$fileName',
                'gitcodeUrl':
                    'https://api.gitcode.com/api/v5/repos/belleangelina/'
                    '300X/releases/v1.0.8/attach_files/$fileName/download',
            },
        ],
    };
}
