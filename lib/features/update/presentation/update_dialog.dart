import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x300/features/settings/application/app_settings_controller.dart';
import 'package:x300/features/update/application/update_download_controller.dart';
import 'package:x300/features/update/application/update_platform.dart';
import 'package:x300/features/update/domain/update_models.dart';
import 'package:x300/shared/presentation/app_snack_bar.dart';

enum _UpdateAction
{
    github,
    domestic,
    ignore,
}

const ButtonStyle _downloadButtonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll<Size>(Size(0, 44)),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
    ),
);

@visibleForTesting
TargetPlatform? updateTargetPlatformOverride;

bool get _isAndroid =>
    updateTargetPlatformOverride == TargetPlatform.android ||
    updateTargetPlatformOverride == null && Platform.isAndroid;

bool get _isIOS =>
    updateTargetPlatformOverride == TargetPlatform.iOS ||
    updateTargetPlatformOverride == null && Platform.isIOS;

Future<bool> showUpdateDialog(
    BuildContext context,
    WidgetRef ref,
    UpdateManifest manifest,
) async
{
    final UpdateArtifact? artifact = await UpdatePlatform.selectArtifact(
        manifest,
    );
    if (!context.mounted)
    {
        return false;
    }
    if (artifact == null)
    {
        ScaffoldMessenger.of(context).showSnackBar(
            const AppSnackBar(content: Text('这个平台没有可用的更新安装包')),
        );
        return false;
    }
    final _UpdateAction? action = await showDialog<_UpdateAction>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
            title: Text('发现新版本 v${manifest.versionName}'),
            content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                            Text('安装包：${_formatBytes(artifact.size)}'),
                            const SizedBox(height: 12),
                            Text(
                                manifest.releaseNotes.isEmpty
                                    ? '本次更新未提供说明。'
                                    : manifest.releaseNotes,
                                style: const TextStyle(height: 1.5),
                            ),
                            if (!_isAndroid) ...<Widget>[
                                const SizedBox(height: 16),
                                SelectableText(
                                    'SHA-256\n${artifact.sha256}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                ),
                                TextButton.icon(
                                    onPressed: () async
                                    {
                                        await Clipboard.setData(
                                            ClipboardData(
                                                text: artifact.sha256,
                                            ),
                                        );
                                        if (context.mounted)
                                        {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                                    const AppSnackBar(
                                                        content: Text(
                                                            'SHA-256 已复制',
                                                        ),
                                                    ),
                                                );
                                        }
                                    },
                                    icon: const Icon(Icons.copy, size: 18),
                                    label: const Text('复制校验值'),
                                ),
                            ],
                            if (_isIOS) ...<Widget>[
                                const SizedBox(height: 8),
                                const Text(
                                    'iOS 安装包下载后无法直接安装，需要自行签名，'
                                    '或在受支持的设备上通过 TrollStore 安装。',
                                    style: TextStyle(height: 1.5),
                                ),
                            ],
                        ],
                    ),
                ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            actions: <Widget>[
                SizedBox(
                    width: double.maxFinite,
                    child: Column(
                        children: <Widget>[
                            Row(
                                children: <Widget>[
                                    Expanded(
                                        child: OutlinedButton(
                                            style: _downloadButtonStyle,
                                            onPressed: () => Navigator.of(
                                                context,
                                            ).pop(_UpdateAction.domestic),
                                            child: const Text('国内下载'),
                                        ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: FilledButton(
                                            style: _downloadButtonStyle,
                                            onPressed: () => Navigator.of(
                                                context,
                                            ).pop(_UpdateAction.github),
                                            child: const Text('GitHub 直连'),
                                        ),
                                    ),
                                ],
                            ),
                            TextButton(
                                onPressed: () => Navigator.of(context).pop(
                                    _UpdateAction.ignore,
                                ),
                                child: const Text('忽略此版本'),
                            ),
                        ],
                    ),
                ),
            ],
        ),
    );
    if (!context.mounted)
    {
        return false;
    }
    if (action == null || action == _UpdateAction.ignore)
    {
        return true;
    }
    final bool domestic = action == _UpdateAction.domestic;
    if (!_isAndroid)
    {
        final Uri uri = UpdateDownloadController.downloadUri(
            artifact,
            domestic: domestic,
            settings: ref.read(appSettingsControllerProvider),
        );
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
            context.mounted)
        {
            ScaffoldMessenger.of(context).showSnackBar(
                const AppSnackBar(content: Text('无法打开系统浏览器')),
            );
        }
        return false;
    }
    unawaited(
        ref
            .read(updateDownloadControllerProvider.notifier)
            .download(artifact, domestic: domestic),
    );
    if (context.mounted)
    {
        unawaited(showUpdateDownloadDialog(context, ref));
    }
    return false;
}

Future<void> showUpdateDownloadDialog(
    BuildContext context,
    WidgetRef ref,
)
async {
    if (_downloadDialogVisible)
    {
        return;
    }
    _downloadDialogVisible = true;
    try
    {
        await showDialog<void>(
            context: context,
            builder: (BuildContext context) =>
                const _UpdateDownloadDialog(),
        );
    }
    finally
    {
        _downloadDialogVisible = false;
    }
}

bool _downloadDialogVisible = false;

class _UpdateDownloadDialog extends ConsumerWidget
{
    const _UpdateDownloadDialog();

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        final UpdateDownloadState state = ref.watch(
            updateDownloadControllerProvider,
        );
        final String title = state.verifying
            ? '正在校验安装包'
            : state.readyToInstall
            ? '安装包已就绪'
            : state.error.isNotEmpty
            ? '更新下载未完成'
            : '正在下载更新';
        return AlertDialog(
            title: Text(title),
            content: SizedBox(
                width: 360,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                        if (state.downloading || state.verifying)
                            LinearProgressIndicator(
                                value: state.verifying ? null : state.progress,
                            ),
                        const SizedBox(height: 12),
                        Text(
                            state.error.isNotEmpty
                                ? state.error
                                : state.readyToInstall
                                ? '文件大小和 SHA-256 校验通过。'
                                : state.verifying
                                ? '下载完成，正在确认文件完整性。'
                                : '${_formatBytes(state.received)} / '
                                      '${_formatBytes(state.total)}',
                        ),
                    ],
                ),
            ),
            actions: <Widget>[
                if (state.downloading)
                    TextButton(
                        onPressed: () => ref
                            .read(updateDownloadControllerProvider.notifier)
                            .cancel(),
                        child: const Text('取消下载'),
                    ),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(state.readyToInstall ? '稍后' : '关闭'),
                ),
                if (state.error.isNotEmpty)
                    OutlinedButton(
                        onPressed: () => ref
                            .read(updateDownloadControllerProvider.notifier)
                            .retry(),
                        child: const Text('重试'),
                    ),
                if (state.readyToInstall)
                    FilledButton(
                        onPressed: () => _install(context, ref),
                        child: const Text('立即安装'),
                    ),
            ],
        );
    }

    Future<void> _install(BuildContext context, WidgetRef ref) async
    {
        final UpdateDownloadController controller = ref.read(
            updateDownloadControllerProvider.notifier,
        );
        try
        {
            if (!await controller.canInstallPackages())
            {
                if (!context.mounted)
                {
                    return;
                }
                final bool? open = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                        title: const Text('允许安装应用更新'),
                        content: const Text(
                            'Android 需要允许 300X 安装未知应用。授权后返回此处，'
                            '无需重新下载安装包。',
                        ),
                        actions: <Widget>[
                            TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('取消'),
                            ),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('前往设置'),
                            ),
                        ],
                    ),
                );
                if (open == true)
                {
                    await controller.openInstallPermission();
                }
                return;
            }
            await controller.install();
        }
        on PlatformException catch (error)
        {
            if (context.mounted)
            {
                ScaffoldMessenger.of(context).showSnackBar(
                    AppSnackBar(
                        content: Text(error.message ?? '无法打开系统安装器'),
                    ),
                );
            }
        }
    }
}

String _formatBytes(int bytes)
{
    if (bytes <= 0)
    {
        return '未知大小';
    }
    if (bytes < 1024)
    {
        return '$bytes B';
    }
    final double kib = bytes / 1024;
    if (kib < 1024)
    {
        return '${kib.toStringAsFixed(1)} KB';
    }
    return '${(kib / 1024).toStringAsFixed(1)} MB';
}
