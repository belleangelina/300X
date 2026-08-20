import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/features/update/domain/update_models.dart';

final Provider<UpdateRepository> updateRepositoryProvider =
    Provider<UpdateRepository>((Ref ref) => UpdateRepository());

class UpdateRepository
{
    UpdateRepository([Dio? dio]) : _dio = dio ?? _createDio();

    static final Uri _gitCodeLatestUri = Uri.parse(
        'https://api.gitcode.com/api/v5/repos/belleangelina/300X/releases/latest',
    );
    static final Uri _githubManifestUri = Uri.parse(
        'https://github.com/belleangelina/300X/releases/latest/download/'
        'update-manifest.json',
    );

    final Dio _dio;

    Future<UpdateManifest> fetchLatest() async
    {
        final List<UpdateManifest?> manifests = await Future.wait(
            <Future<UpdateManifest?>>[
                _tryFetch(_fetchGitCode),
                _tryFetch(_fetchGithub),
            ],
        );
        final UpdateManifest? gitCode = manifests[0];
        final UpdateManifest? github = manifests[1];
        if (gitCode == null && github == null)
        {
            throw StateError('两个官方更新源均不可用');
        }
        if (github != null &&
            (gitCode == null || github.buildNumber > gitCode.buildNumber))
        {
            return github;
        }
        return gitCode!;
    }

    Future<UpdateManifest?> _tryFetch(
        Future<UpdateManifest> Function() fetch,
    ) async
    {
        try
        {
            return await fetch().timeout(const Duration(seconds: 10));
        }
        on Object
        {
            return null;
        }
    }

    Future<UpdateManifest> _fetchGitCode() async
    {
        final Response<Object?> release = await _dio.getUri<Object?>(
            _gitCodeLatestUri,
        );
        final Object? data = release.data;
        if (data is! Map<String, Object?> || data['prerelease'] == true)
        {
            throw const FormatException('GitCode 最新版本信息无效');
        }
        final Object? tagValue = data['tag_name'];
        if (tagValue is! String || !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tagValue))
        {
            throw const FormatException('GitCode 最新版本标签无效');
        }
        final Uri manifestUri = Uri.parse(
            'https://api.gitcode.com/api/v5/repos/belleangelina/300X/'
            'releases/$tagValue/attach_files/update-manifest.json/download',
        );
        return _fetchManifest(manifestUri);
    }

    Future<UpdateManifest> _fetchGithub()
    {
        return _fetchManifest(_githubManifestUri);
    }

    Future<UpdateManifest> _fetchManifest(Uri uri) async
    {
        final Response<Object?> response = await _dio.getUri<Object?>(uri);
        Object? data = response.data;
        if (data is String)
        {
            data = jsonDecode(data);
        }
        if (data is! Map<String, Object?>)
        {
            throw const FormatException('更新清单不是 JSON 对象');
        }
        return UpdateManifest.fromJson(data);
    }

    static Dio _createDio()
    {
        return Dio(
            BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 10),
                responseType: ResponseType.json,
                followRedirects: true,
                maxRedirects: 5,
            ),
        );
    }
}
