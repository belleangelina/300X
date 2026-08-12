import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:x300/features/update/domain/update_models.dart';

class UpdatePlatform
{
    static const MethodChannel _channel = MethodChannel(
        'com.yamibox300/app_update',
    );

    @visibleForTesting
    static String? platformOverride;

    static bool get supportsUpdates
    {
        final String platform = platformOverride ?? Platform.operatingSystem;
        return platform == 'android' || platform == 'ios';
    }

    static Future<UpdateArtifact?> selectArtifact(
        UpdateManifest manifest,
    ) async
    {
        final String platform = platformOverride ?? Platform.operatingSystem;
        if (platform == 'android')
        {
            final String abi =
                await _channel.invokeMethod<String>('primaryAbi') ?? '';
            return abi == 'arm64-v8a'
                ? manifest.artifactFor('android', 'arm64-v8a') ??
                      manifest.artifactFor('android', 'universal')
                : manifest.artifactFor('android', 'universal');
        }
        if (platform == 'ios')
        {
            return manifest.artifactFor('ios', 'unsigned');
        }
        return null;
    }
}
