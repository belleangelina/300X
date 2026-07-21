import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:x300/core/network/forum_exceptions.dart';

final Provider<ForumClient> forumClientProvider = Provider<ForumClient>(
    (Ref ref)
    {
        throw UnimplementedError('ForumClient must be overridden at startup.');
    },
);

class ForumClient
{
    ForumClient._(this._dio, this.cookieJar);

    static final Uri baseUri = Uri.parse('https://bbs.yamibo.com/');

    final Dio _dio;
    final PersistCookieJar cookieJar;

    static Future<ForumClient> create() async
    {
        final Directory supportDirectory =
            await getApplicationSupportDirectory();
        final String cookieDirectory = path.join(
            supportDirectory.path,
            'sessions',
        );
        await Directory(cookieDirectory).create(recursive: true);

        final PersistCookieJar cookieJar = PersistCookieJar(
            ignoreExpires: false,
            storage: FileStorage(cookieDirectory),
        );
        final Dio dio = Dio(
            BaseOptions(
                baseUrl: baseUri.toString(),
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 20),
                followRedirects: true,
                maxRedirects: 8,
                responseType: ResponseType.plain,
                headers: const <String, String>{
                    HttpHeaders.userAgentHeader:
                        'Mozilla/5.0 (Linux; Android 13) '
                        'AppleWebKit/537.36 Chrome/126 Mobile Safari/537.36 '
                        '300X/1.0',
                    HttpHeaders.acceptLanguageHeader:
                        'zh-CN,zh;q=0.9,zh-TW;q=0.8',
                },
            ),
        );
        if (Platform.environment['PAGE300_FORCE_OFFLINE'] == '1')
        {
            dio.interceptors.add(
                InterceptorsWrapper(
                    onRequest: (
                        RequestOptions options,
                        RequestInterceptorHandler handler,
                    ) => handler.reject(
                        DioException(
                            requestOptions: options,
                            type: DioExceptionType.connectionError,
                            message: '300X forced offline transport',
                        ),
                    ),
                ),
            );
        }
        dio.interceptors.add(CookieManager(cookieJar));

        return ForumClient._(dio, cookieJar);
    }

    Uri resolve(String location)
    {
        return baseUri.resolve(location);
    }

    Future<Response<String>> getText(
        Object location, {
        Map<String, dynamic>? queryParameters,
        String? referer,
        int retryCount = 2,
    }) async
    {
        final Uri uri = _withQueryParameters(
            _toUri(location),
            queryParameters,
        );
        DioException? lastError;

        for (int attempt = 0; attempt <= retryCount; attempt++)
        {
            try
            {
                return await _dio.getUri<String>(
                    uri,
                    options: Options(
                        responseType: ResponseType.plain,
                        headers: referer == null
                            ? null
                            : <String, String>{
                                HttpHeaders.refererHeader: referer,
                            },
                    ),
                );
            }
            on DioException catch (error)
            {
                lastError = error;
                if (!_canRetry(error) || attempt == retryCount)
                {
                    break;
                }
                await Future<void>.delayed(
                    Duration(milliseconds: 350 * (attempt + 1)),
                );
            }
        }

        throw ForumConnectionException(
            lastError?.message ?? '无法连接百合会论坛',
        );
    }

    Future<Response<String>> postForm(
        Object location, {
        required Map<String, dynamic> fields,
        String? referer,
        ListFormat listFormat = ListFormat.multi,
    }) async
    {
        final Uri uri = _toUri(location);
        try
        {
            final Response<String> response = await _dio.postUri<String>(
                uri,
                data: fields,
                options: Options(
                    contentType: Headers.formUrlEncodedContentType,
                    responseType: ResponseType.plain,
                    listFormat: listFormat,
                    followRedirects: false,
                    validateStatus: (int? status) => status != null &&
                        status >= 200 &&
                        status <= 303,
                    headers: referer == null
                        ? null
                        : <String, String>{
                            HttpHeaders.refererHeader: referer,
                        },
                    ),
            );
            final int statusCode = response.statusCode ?? 0;
            if (statusCode < 300)
            {
                return response;
            }
            final String redirect = response.headers.value(
                    HttpHeaders.locationHeader,
                ) ??
                '';
            final Uri target = uri.resolve(redirect);
            if (redirect.isEmpty ||
                target.scheme != baseUri.scheme ||
                target.host != baseUri.host ||
                target.port != baseUri.port)
            {
                throw const ForumConnectionException(
                    '论坛提交返回了无效跳转',
                );
            }
            return getText(
                target,
                referer: uri.toString(),
            );
        }
        on DioException catch (error)
        {
            final int? statusCode = error.response?.statusCode;
            throw ForumConnectionException(
                statusCode == null
                    ? '提交论坛表单失败，请检查网络连接'
                    : '论坛拒绝提交（HTTP $statusCode）',
            );
        }
    }

    Future<Uint8List> getBytes(
        Object location, {
        String? referer,
    }) async
    {
        try
        {
            final Response<List<int>> response =
                await _dio.getUri<List<int>>(
                    _toUri(location),
                    options: Options(
                        responseType: ResponseType.bytes,
                        headers: referer == null
                            ? null
                            : <String, String>{
                                HttpHeaders.refererHeader: referer,
                            },
                    ),
                );
            return Uint8List.fromList(response.data ?? const <int>[]);
        }
        on DioException catch (error)
        {
            throw ForumConnectionException(
                error.message ?? '加载论坛图片失败',
            );
        }
    }

    Future<void> clearSession() async
    {
        await cookieJar.deleteAll();
    }

    Future<List<Cookie>> exportCookies()
    {
        return cookieJar.loadForRequest(baseUri);
    }

    Future<void> importCookies(List<Cookie> cookies)
    {
        return cookieJar.saveFromResponse(baseUri, cookies);
    }

    Uri _toUri(Object location)
    {
        if (location is Uri)
        {
            return location;
        }
        return resolve(location.toString());
    }

    Uri _withQueryParameters(
        Uri uri,
        Map<String, dynamic>? queryParameters,
    )
    {
        if (queryParameters == null || queryParameters.isEmpty)
        {
            return uri;
        }
        return uri.replace(
            queryParameters: <String, dynamic>{
                ...uri.queryParameters,
                ...queryParameters,
            },
        );
    }

    bool _canRetry(DioException error)
    {
        return error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.unknown;
    }
}
