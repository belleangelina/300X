import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/update/data/update_repository.dart';

class _MockDio extends Mock implements Dio
{
}

void main()
{
    setUpAll(()
    {
        registerFallbackValue(Uri());
    });

    test('GitCode 失败时使用 GitHub 官方清单', () async
    {
        final _MockDio dio = _MockDio();
        when(() => dio.getUri<Object?>(any())).thenAnswer((Invocation call)
        {
            final Uri uri = call.positionalArguments.first! as Uri;
            if (uri.host == 'api.gitcode.com')
            {
                throw DioException(
                    requestOptions: RequestOptions(path: uri.toString()),
                );
            }
            return Future<Response<Object?>>.value(
                _response(uri, _manifestJson()),
            );
        });

        final manifest = await UpdateRepository(dio).fetchLatest();

        expect(manifest.buildNumber, 11);
        final List<Uri> requests = verify(
            () => dio.getUri<Object?>(captureAny()),
        ).captured.cast<Uri>();
        expect(requests, hasLength(2));
        expect(
            requests.map((Uri value) => value.host),
            containsAll(<String>['api.gitcode.com', 'github.com']),
        );
    });

    test('两个官方源都有效时选择较高构建号', () async
    {
        final _MockDio dio = _MockDio();
        when(() => dio.getUri<Object?>(any())).thenAnswer((Invocation call)
        {
            final Uri uri = call.positionalArguments.first! as Uri;
            if (uri.host == 'github.com')
            {
                return Future<Response<Object?>>.value(
                    _response(
                        uri,
                        _manifestJson(
                            versionName: '1.0.9',
                            buildNumber: 12,
                        ),
                    ),
                );
            }
            final Object data = uri.path.endsWith('/latest')
                ? <String, Object?>{
                    'tag_name': 'v1.0.8',
                    'prerelease': false,
                }
                : _manifestJson();
            return Future<Response<Object?>>.value(_response(uri, data));
        });

        final manifest = await UpdateRepository(dio).fetchLatest();

        expect(manifest.versionName, '1.0.9');
        expect(manifest.buildNumber, 12);
        final List<Uri> requests = verify(
            () => dio.getUri<Object?>(captureAny()),
        ).captured.cast<Uri>();
        expect(requests, hasLength(3));
        expect(
            requests.map((Uri value) => value.host),
            containsAll(<String>['api.gitcode.com', 'github.com']),
        );
    });

    test('GitCode 较新时保留 GitCode 清单', () async
    {
        final _MockDio dio = _MockDio();
        when(() => dio.getUri<Object?>(any())).thenAnswer((Invocation call)
        {
            final Uri uri = call.positionalArguments.first! as Uri;
            if (uri.host == 'github.com')
            {
                return Future<Response<Object?>>.value(
                    _response(
                        uri,
                        _manifestJson(
                            versionName: '1.0.7',
                            buildNumber: 10,
                        ),
                    ),
                );
            }
            final Object data = uri.path.endsWith('/latest')
                ? <String, Object?>{
                    'tag_name': 'v1.0.8',
                    'prerelease': false,
                }
                : _manifestJson();
            return Future<Response<Object?>>.value(_response(uri, data));
        });

        final manifest = await UpdateRepository(dio).fetchLatest();

        expect(manifest.versionName, '1.0.8');
        expect(manifest.buildNumber, 11);
    });
}

Response<Object?> _response(Uri uri, Object data)
{
    return Response<Object?>(
        requestOptions: RequestOptions(path: uri.toString()),
        data: data,
        statusCode: 200,
    );
}

Map<String, Object?> _manifestJson({
    String versionName = '1.0.8',
    int buildNumber = 11,
})
{
    final String fileName =
        'X300-v$versionName-android-universal-release.apk';
    return <String, Object?>{
        'schemaVersion': 1,
        'versionName': versionName,
        'buildNumber': buildNumber,
        'releaseNotes': '测试更新',
        'publishedAt': '2026-08-12T12:00:00Z',
        'artifacts': <Object?>[
            <String, Object?>{
                'platform': 'android',
                'variant': 'universal',
                'fileName': fileName,
                'size': 100,
                'sha256': 'a' * 64,
                'githubUrl':
                    'https://github.com/belleangelina/300X/releases/'
                    'download/v$versionName/$fileName',
                'gitcodeUrl':
                    'https://api.gitcode.com/api/v5/repos/belleangelina/'
                    '300X/releases/v$versionName/attach_files/$fileName/download',
            },
        ],
    };
}
