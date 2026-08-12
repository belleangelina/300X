import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:x300/features/settings/application/app_settings_controller.dart';
import 'package:x300/features/settings/domain/app_settings.dart';
import 'package:x300/features/update/domain/update_models.dart';

final NotifierProvider<UpdateDownloadController, UpdateDownloadState>
    updateDownloadControllerProvider =
    NotifierProvider<UpdateDownloadController, UpdateDownloadState>(
        UpdateDownloadController.new,
    );

class UpdateDownloadState
{
    const UpdateDownloadState({
        this.artifact,
        this.received = 0,
        this.total = 0,
        this.filePath,
        this.error = '',
        this.downloading = false,
        this.verifying = false,
        this.domestic = false,
    });

    final UpdateArtifact? artifact;
    final int received;
    final int total;
    final String? filePath;
    final String error;
    final bool downloading;
    final bool verifying;
    final bool domestic;

    bool get readyToInstall => filePath != null && error.isEmpty;

    double? get progress => total > 0 ? received / total : null;
}

class UpdateDownloadController extends Notifier<UpdateDownloadState>
{
    static const MethodChannel _channel = MethodChannel(
        'com.yamibox300/app_update',
    );

    CancelToken? _cancelToken;

    @override
    UpdateDownloadState build()
    {
        ref.onDispose(() => _cancelToken?.cancel());
        return const UpdateDownloadState();
    }

    Future<void> download(
        UpdateArtifact artifact, {
        required bool domestic,
    }) async
    {
        if (state.downloading || state.verifying)
        {
            return;
        }
        final Directory cache = await getTemporaryDirectory();
        final Directory updates = Directory(path.join(cache.path, 'updates'));
        await updates.create(recursive: true);
        await _cleanOtherFiles(updates, artifact.fileName);
        final File completed = File(path.join(updates.path, artifact.fileName));
        if (await _matches(completed, artifact))
        {
            await _writeSourceBuild(updates);
            state = UpdateDownloadState(
                artifact: artifact,
                received: artifact.size,
                total: artifact.size,
                filePath: completed.path,
            );
            return;
        }
        final File partial = File('${completed.path}.part');
        if (await partial.exists())
        {
            await partial.delete();
        }
        final Uri uri = downloadUri(
            artifact,
            domestic: domestic,
            settings: ref.read(appSettingsControllerProvider),
        );
        _cancelToken = CancelToken();
        state = UpdateDownloadState(
            artifact: artifact,
            total: artifact.size,
            downloading: true,
            domestic: domestic,
        );
        try
        {
            await Dio(
                BaseOptions(
                    connectTimeout: const Duration(seconds: 10),
                    receiveTimeout: const Duration(minutes: 5),
                    followRedirects: true,
                    maxRedirects: 8,
                ),
            ).downloadUri(
                uri,
                partial.path,
                cancelToken: _cancelToken,
                deleteOnError: true,
                onReceiveProgress: (int received, int total)
                {
                    state = UpdateDownloadState(
                        artifact: artifact,
                        received: received,
                        total: total > 0 ? total : artifact.size,
                        downloading: true,
                        domestic: domestic,
                    );
                },
            );
            state = UpdateDownloadState(
                artifact: artifact,
                received: artifact.size,
                total: artifact.size,
                verifying: true,
                domestic: domestic,
            );
            if (!await _matches(partial, artifact))
            {
                throw const FormatException('安装包校验失败，请重新下载');
            }
            if (await completed.exists())
            {
                await completed.delete();
            }
            await partial.rename(completed.path);
            await _writeSourceBuild(updates);
            state = UpdateDownloadState(
                artifact: artifact,
                received: artifact.size,
                total: artifact.size,
                filePath: completed.path,
            );
        }
        on DioException catch (error)
        {
            if (await partial.exists())
            {
                await partial.delete();
            }
            state = UpdateDownloadState(
                artifact: artifact,
                error: CancelToken.isCancel(error)
                    ? '下载已取消'
                    : '下载失败，请稍后重试',
                domestic: domestic,
            );
        }
        on Object catch (error)
        {
            if (await partial.exists())
            {
                await partial.delete();
            }
            state = UpdateDownloadState(
                artifact: artifact,
                error: error is FormatException
                    ? error.message
                    : '安装包处理失败，请重新下载',
                domestic: domestic,
            );
        }
        finally
        {
            _cancelToken = null;
        }
    }

    void cancel()
    {
        _cancelToken?.cancel('用户取消下载');
    }

    Future<void> retry()
    {
        final UpdateArtifact? artifact = state.artifact;
        if (artifact == null)
        {
            return Future<void>.value();
        }
        return download(artifact, domestic: state.domestic);
    }

    Future<void> cleanInstalledUpdate() async
    {
        try
        {
            final Directory cache = await getTemporaryDirectory();
            final Directory updates = Directory(
                path.join(cache.path, 'updates'),
            );
            if (!await updates.exists())
            {
                return;
            }
            final File marker = File(
                path.join(updates.path, 'source-build.txt'),
            );
            if (!await marker.exists())
            {
                return;
            }
            final int sourceBuild =
                int.tryParse(await marker.readAsString()) ?? 0;
            final int currentBuild = int.tryParse(
                    (await PackageInfo.fromPlatform()).buildNumber,
                ) ??
                0;
            if (currentBuild <= sourceBuild)
            {
                return;
            }
            await for (final FileSystemEntity entity in updates.list())
            {
                if (entity is File)
                {
                    await entity.delete();
                }
            }
        }
        on Object
        {
            // 缓存清理失败不应影响应用启动。
        }
    }

    Future<bool> canInstallPackages() async
    {
        return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    }

    Future<void> openInstallPermission()
    {
        return _channel.invokeMethod<void>('openInstallPermission');
    }

    Future<void> install()
    {
        final String? filePath = state.filePath;
        if (filePath == null)
        {
            throw StateError('没有可安装的 APK');
        }
        return _channel.invokeMethod<void>('installApk', filePath);
    }

    static Uri downloadUri(
        UpdateArtifact artifact, {
        required bool domestic,
        required AppSettings settings,
    })
    {
        if (!domestic)
        {
            return artifact.githubUrl;
        }
        if (settings.domesticUpdateSource == DomesticUpdateSource.gitCode)
        {
            return artifact.gitcodeUrl;
        }
        return Uri.parse('${settings.updateProxyUrl}${artifact.githubUrl}');
    }

    static Future<bool> _matches(
        File file,
        UpdateArtifact artifact,
    ) async
    {
        if (!await file.exists() || await file.length() != artifact.size)
        {
            return false;
        }
        final Digest digest = await sha256.bind(file.openRead()).first;
        return digest.toString() == artifact.sha256;
    }

    static Future<void> _cleanOtherFiles(
        Directory directory,
        String keepName,
    ) async
    {
        await for (final FileSystemEntity entity in directory.list())
        {
            if (entity is File &&
                path.basename(entity.path) != keepName &&
                path.basename(entity.path) != 'source-build.txt')
            {
                await entity.delete();
            }
        }
    }

    static Future<void> _writeSourceBuild(Directory directory) async
    {
        final PackageInfo package = await PackageInfo.fromPlatform();
        await File(path.join(directory.path, 'source-build.txt')).writeAsString(
            package.buildNumber,
            flush: true,
        );
    }
}
