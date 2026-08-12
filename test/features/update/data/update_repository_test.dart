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

    test('GitCode 失败后回退 GitHub 官方清单', () async
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
        expect(requests.first.host, 'api.gitcode.com');
        expect(requests.last.host, 'github.com');
    });

    test('GitCode 正式版本有效时不访问 GitHub', () async
    {
        final _MockDio dio = _MockDio();
        when(() => dio.getUri<Object?>(any())).thenAnswer((Invocation call)
        {
            final Uri uri = call.positionalArguments.first! as Uri;
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
        final List<Uri> requests = verify(
            () => dio.getUri<Object?>(captureAny()),
        ).captured.cast<Uri>();
        expect(requests, hasLength(2));
        expect(requests.every((Uri value) => value.host == 'api.gitcode.com'), isTrue);
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

Map<String, Object?> _manifestJson()
{
    const String fileName = 'X300-v1.0.8-android-universal-release.apk';
    return <String, Object?>{
        'schemaVersion': 1,
        'versionName': '1.0.8',
        'buildNumber': 11,
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
                    'download/v1.0.8/$fileName',
                'gitcodeUrl':
                    'https://api.gitcode.com/api/v5/repos/belleangelina/'
                    '300X/releases/v1.0.8/attach_files/$fileName/download',
            },
        ],
    };
}
