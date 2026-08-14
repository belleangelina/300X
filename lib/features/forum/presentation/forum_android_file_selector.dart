import 'package:flutter/services.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

typedef ForumFileSelectorInvoker = Future<Object?> Function(
    Map<String, Object?> arguments,
);

class ForumAndroidFileSelectionRequest
{
    const ForumAndroidFileSelectionRequest({
        required this.mode,
        required this.mimeTypes,
    });

    final String mode;
    final List<String> mimeTypes;

    static const Map<String, String> _extensionMimeTypes = <String, String>{
        '.7z': 'application/x-7z-compressed',
        '.apk': 'application/vnd.android.package-archive',
        '.avi': 'video/x-msvideo',
        '.bmp': 'image/bmp',
        '.doc': 'application/msword',
        '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        '.gif': 'image/gif',
        '.heic': 'image/heic',
        '.heif': 'image/heif',
        '.jpeg': 'image/jpeg',
        '.jpg': 'image/jpeg',
        '.m4a': 'audio/mp4',
        '.mkv': 'video/x-matroska',
        '.mov': 'video/quicktime',
        '.mp3': 'audio/mpeg',
        '.mp4': 'video/mp4',
        '.pdf': 'application/pdf',
        '.png': 'image/png',
        '.rar': 'application/vnd.rar',
        '.tar': 'application/x-tar',
        '.txt': 'text/plain',
        '.webm': 'video/webm',
        '.webp': 'image/webp',
        '.xls': 'application/vnd.ms-excel',
        '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        '.zip': 'application/zip',
    };
    static final RegExp _mimeTypePattern = RegExp(
        r'^(\*/\*|[a-z0-9][a-z0-9!#&^_.+\-]*/(?:\*|[a-z0-9][a-z0-9!#&^_.+\-]*))$',
    );

    static ForumAndroidFileSelectionRequest? fromParams(
        FileSelectorParams params,
    )
    {
        final String mode;
        switch (params.mode)
        {
            case FileSelectorMode.open:
                mode = 'open';
            case FileSelectorMode.openMultiple:
                mode = 'openMultiple';
            case FileSelectorMode.save:
                return null;
        }
        return ForumAndroidFileSelectionRequest(
            mode: mode,
            mimeTypes: normalizeMimeTypes(params.acceptTypes),
        );
    }

    static List<String> normalizeMimeTypes(List<String> acceptTypes)
    {
        final Set<String> normalized = <String>{};
        for (final String declaration in acceptTypes)
        {
            for (final String rawValue in declaration.split(','))
            {
                final String value = rawValue
                    .split(';')
                    .first
                    .trim()
                    .toLowerCase();
                if (value.isEmpty)
                {
                    continue;
                }
                final String? mimeType = value.startsWith('.')
                    ? _extensionMimeTypes[value]
                    : _mimeTypePattern.hasMatch(value)
                        ? value
                        : null;
                if (mimeType == null)
                {
                    continue;
                }
                if (mimeType == '*/*')
                {
                    return const <String>['*/*'];
                }
                normalized.add(mimeType);
            }
        }
        if (normalized.isEmpty)
        {
            return const <String>['*/*'];
        }
        return List<String>.unmodifiable(normalized);
    }

    Map<String, Object?> toChannelArguments()
    {
        return <String, Object?>{
            'mode': mode,
            'mimeTypes': mimeTypes,
        };
    }
}

class ForumAndroidFileSelectorAdapter
{
    ForumAndroidFileSelectorAdapter({ForumFileSelectorInvoker? invoke})
        : _invoke = invoke ?? _invokePlatform;

    static const MethodChannel _channel = MethodChannel(
        'com.yamibox300/forum_file_selector',
    );

    final ForumFileSelectorInvoker _invoke;
    bool _pending = false;

    Future<List<String>> select(
        FileSelectorParams params, {
        required bool Function() isEnabled,
    }) async
    {
        if (_pending || !isEnabled())
        {
            return const <String>[];
        }
        final ForumAndroidFileSelectionRequest? request =
            ForumAndroidFileSelectionRequest.fromParams(params);
        if (request == null)
        {
            return const <String>[];
        }
        _pending = true;
        try
        {
            final Object? response = await _invoke(
                request.toChannelArguments(),
            );
            if (!isEnabled() || response is! List<Object?>)
            {
                return const <String>[];
            }
            final Set<String> selected = <String>{};
            for (final Object? value in response)
            {
                if (value is! String)
                {
                    continue;
                }
                final String rawUri = value.trim();
                final Uri? uri = Uri.tryParse(rawUri);
                if (uri == null ||
                    uri.scheme != 'content' ||
                    !uri.hasAuthority)
                {
                    continue;
                }
                selected.add(rawUri);
                if (request.mode == 'open')
                {
                    break;
                }
            }
            return List<String>.unmodifiable(selected);
        }
        on Object
        {
            return const <String>[];
        }
        finally
        {
            _pending = false;
        }
    }

    static Future<Object?> _invokePlatform(
        Map<String, Object?> arguments,
    )
    {
        return _channel.invokeMethod<Object?>('chooseFiles', arguments);
    }
}
