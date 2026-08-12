import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/settings/domain/app_settings.dart';
import 'package:x300/features/update/application/update_download_controller.dart';
import 'package:x300/features/update/domain/update_models.dart';

void main()
{
    final UpdateArtifact artifact = UpdateArtifact(
        platform: 'android',
        variant: 'universal',
        fileName: 'X300.apk',
        size: 100,
        sha256: 'hash',
        githubUrl: Uri.parse(
            'https://github.com/owner/repo/file.apk',
        ),
        gitcodeUrl: Uri.parse(
            'https://gitcode.com/owner/repo/file.apk',
        ),
    );

    test('GitHub 直连始终使用原地址', ()
    {
        final Uri uri = UpdateDownloadController.downloadUri(
            artifact,
            domestic: false,
            settings: const AppSettings(),
        );

        expect(uri, artifact.githubUrl);
    });

    test('国内下载按设置选择 GitCode 或自定义代理', ()
    {
        expect(
            UpdateDownloadController.downloadUri(
                artifact,
                domestic: true,
                settings: const AppSettings(),
            ),
            artifact.gitcodeUrl,
        );
        expect(
            UpdateDownloadController.downloadUri(
                artifact,
                domestic: true,
                settings: const AppSettings(
                    domesticUpdateSource: DomesticUpdateSource.customProxy,
                    updateProxyUrl: 'https://proxy.example/',
                ),
            ).toString(),
            'https://proxy.example/https://github.com/owner/repo/file.apk',
        );
    });
}
