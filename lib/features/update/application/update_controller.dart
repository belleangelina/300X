import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:x300/features/settings/application/app_settings_controller.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/features/update/application/update_platform.dart';
import 'package:x300/features/update/data/update_repository.dart';
import 'package:x300/features/update/domain/update_models.dart';

final NotifierProvider<UpdateController, UpdateState>
    updateControllerProvider = NotifierProvider<UpdateController, UpdateState>(
        UpdateController.new,
    );

class UpdateState
{
    const UpdateState({
        this.pending,
        this.checkingManually = false,
        this.manualMessage = '',
    });

    final UpdateManifest? pending;
    final bool checkingManually;
    final String manualMessage;

    UpdateState copyWith({
        UpdateManifest? pending,
        bool clearPending = false,
        bool? checkingManually,
        String? manualMessage,
    })
    {
        return UpdateState(
            pending: clearPending ? null : pending ?? this.pending,
            checkingManually: checkingManually ?? this.checkingManually,
            manualMessage: manualMessage ?? this.manualMessage,
        );
    }
}

class UpdateController extends Notifier<UpdateState>
{
    bool _automaticCheckStarted = false;
    int? _currentBuildNumber;

    AppSettingsRepository get _settingsRepository => ref.read(
        appSettingsRepositoryProvider,
    );

    @override
    UpdateState build()
    {
        return const UpdateState();
    }

    Future<void> checkAutomatically() async
    {
        if (!UpdatePlatform.supportsUpdates)
        {
            return;
        }
        if (_automaticCheckStarted)
        {
            return;
        }
        if (!ref.read(appSettingsControllerProvider).automaticUpdateChecks)
        {
            return;
        }
        final DateTime? previous = _settingsRepository.lastSuccessfulUpdateCheck;
        if (previous != null &&
            DateTime.now().toUtc().difference(previous) <
                const Duration(hours: 24))
        {
            return;
        }
        _automaticCheckStarted = true;
        try
        {
            final UpdateManifest manifest = await ref
                .read(updateRepositoryProvider)
                .fetchLatest();
            await _settingsRepository.saveSuccessfulUpdateCheck(DateTime.now());
            if (manifest.buildNumber <= await _installedBuildNumber() ||
                manifest.buildNumber <=
                    _settingsRepository.ignoredUpdateBuildNumber)
            {
                return;
            }
            state = state.copyWith(pending: manifest);
        }
        on Object
        {
            // 自动检查失败不打扰用户，并且不记录成功检查时间。
        }
    }

    Future<UpdateManifest?> checkManually() async
    {
        if (!UpdatePlatform.supportsUpdates)
        {
            state = state.copyWith(manualMessage: '当前平台暂不支持应用内更新');
            return null;
        }
        if (state.checkingManually)
        {
            return null;
        }
        state = state.copyWith(
            checkingManually: true,
            manualMessage: '',
        );
        try
        {
            final UpdateManifest manifest = await ref
                .read(updateRepositoryProvider)
                .fetchLatest();
            await _settingsRepository.saveSuccessfulUpdateCheck(DateTime.now());
            if (manifest.buildNumber <= await _installedBuildNumber())
            {
                state = state.copyWith(
                    checkingManually: false,
                    manualMessage: '当前已是最新版本',
                );
                return null;
            }
            state = state.copyWith(
                pending: manifest,
                checkingManually: false,
                manualMessage: '',
            );
            return manifest;
        }
        on Object
        {
            state = state.copyWith(
                checkingManually: false,
                manualMessage: '检查更新失败，请稍后重试',
            );
            return null;
        }
    }

    Future<void> ignorePending() async
    {
        final UpdateManifest? manifest = state.pending;
        if (manifest != null)
        {
            await _settingsRepository.ignoreUpdateBuild(manifest.buildNumber);
        }
        state = state.copyWith(clearPending: true);
    }

    void dismissPending()
    {
        state = state.copyWith(clearPending: true);
    }

    Future<int> _installedBuildNumber() async
    {
        final int? cached = _currentBuildNumber;
        if (cached != null)
        {
            return cached;
        }
        final PackageInfo package = await PackageInfo.fromPlatform();
        final int value = int.tryParse(package.buildNumber) ?? 0;
        _currentBuildNumber = value;
        return value;
    }
}
