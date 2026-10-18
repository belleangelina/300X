import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/network/waf_challenge_solver.dart';

final Provider<ForumClient> forumClientProvider = Provider<ForumClient>((
  Ref ref,
) {
  throw UnimplementedError('ForumClient must be overridden at startup.');
});

class ForumClient {
  ForumClient._(this._dio, this.cookieJar, this._wafChallengeSolver);

  static final Uri baseUri = Uri.parse('https://bbs.yamibo.com/');

  final Dio _dio;
  final CookieJar cookieJar;
  final WafChallengeSolver? _wafChallengeSolver;
  Future<void>? _pendingWafChallenge;
  int _wafCookieGeneration = 0;

  static Future<ForumClient> create({
    WafChallengeSolver? wafChallengeSolver,
  }) async {
    final Directory supportDirectory = await getApplicationSupportDirectory();
    final String cookieDirectory = path.join(supportDirectory.path, 'sessions');
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
          HttpHeaders.userAgentHeader: forumUserAgent,
          HttpHeaders.acceptLanguageHeader: 'zh-CN,zh;q=0.9,zh-TW;q=0.8',
        },
      ),
    );
    if (Platform.environment['PAGE300_FORCE_OFFLINE'] == '1') {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) =>
                  handler.reject(
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

    return ForumClient._(dio, cookieJar, wafChallengeSolver);
  }

  @visibleForTesting
  factory ForumClient.forTesting(
    Dio dio,
    CookieJar cookieJar, {
    WafChallengeSolver? wafChallengeSolver,
  }) {
    dio.interceptors.add(CookieManager(cookieJar));
    return ForumClient._(dio, cookieJar, wafChallengeSolver);
  }

  Uri resolve(String location) {
    return baseUri.resolve(location);
  }

  Future<Response<String>> getText(
    Object location, {
    Map<String, dynamic>? queryParameters,
    String? referer,
    int retryCount = 2,
  }) async {
    final Uri uri = _withQueryParameters(_toUri(location), queryParameters);
    DioException? lastError;
    bool wafRecoveryAttempted = false;
    final int wafCookieGeneration = _wafCookieGeneration;

    for (int attempt = 0; attempt <= retryCount;) {
      try {
        final Response<String> response = await _dio.getUri<String>(
          uri,
          options: Options(
            responseType: ResponseType.plain,
            headers: referer == null
                ? null
                : <String, String>{HttpHeaders.refererHeader: referer},
          ),
        );
        _resolveRedirects(response);
        return response;
      } on DioException catch (error) {
        lastError = error;
        if (!wafRecoveryAttempted && _isWafChallenge(error)) {
          wafRecoveryAttempted = true;
          if (wafCookieGeneration == _wafCookieGeneration) {
            await _refreshWafCookie();
          }
          continue;
        }
        if (!_canRetry(error) || attempt == retryCount) {
          break;
        }
        attempt++;
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }

    throw _failure(lastError, unreachable: '无法连接百合会论坛，请检查网络连接');
  }

  Future<Response<String>> postForm(
    Object location, {
    required Map<String, dynamic> fields,
    String? referer,
    ListFormat listFormat = ListFormat.multi,
  }) async {
    final Uri uri = _toUri(location);
    final int wafCookieGeneration = _wafCookieGeneration;
    try {
      final Response<String> response = await _dio.postUri<String>(
        uri,
        data: fields,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          listFormat: listFormat,
          followRedirects: false,
          validateStatus: (int? status) =>
              status != null && status >= 200 && status <= 303,
          headers: referer == null
              ? null
              : <String, String>{HttpHeaders.refererHeader: referer},
        ),
      );
      final int statusCode = response.statusCode ?? 0;
      if (statusCode < 300) {
        return response;
      }
      final String redirect =
          response.headers.value(HttpHeaders.locationHeader) ?? '';
      final Uri target = uri.resolve(redirect);
      if (redirect.isEmpty ||
          target.scheme != baseUri.scheme ||
          target.host != baseUri.host ||
          target.port != baseUri.port) {
        throw const ForumConnectionException('论坛提交返回了无效跳转');
      }
      return getText(target, referer: uri.toString());
    } on DioException catch (error) {
      if (_isWafChallenge(error)) {
        if (wafCookieGeneration == _wafCookieGeneration) {
          await _refreshWafCookie();
        }
        throw const ForumConnectionException('论坛安全验证已更新，请重新提交');
      }
      final int? statusCode = error.response?.statusCode;
      final String message = statusCode == null
          ? '提交论坛表单失败，请检查网络连接'
          : '论坛拒绝提交（HTTP $statusCode）';
      throw _isUnreachable(error)
          ? ForumUnreachableException(message)
          : ForumConnectionException(message);
    }
  }

  Future<Uint8List> getBytes(Object location, {String? referer}) async {
    bool wafRecoveryAttempted = false;
    final int wafCookieGeneration = _wafCookieGeneration;
    while (true) {
      try {
        final Response<List<int>> response = await _dio.getUri<List<int>>(
          _toUri(location),
          options: Options(
            responseType: ResponseType.bytes,
            headers: referer == null
                ? null
                : <String, String>{HttpHeaders.refererHeader: referer},
          ),
        );
        return Uint8List.fromList(response.data ?? const <int>[]);
      } on DioException catch (error) {
        if (!wafRecoveryAttempted && _isWafChallenge(error)) {
          wafRecoveryAttempted = true;
          if (wafCookieGeneration == _wafCookieGeneration) {
            await _refreshWafCookie();
          }
          continue;
        }
        throw _failure(error, unreachable: '加载论坛图片失败，请检查网络连接');
      }
    }
  }

  Future<void> clearSession() async {
    await cookieJar.deleteAll();
  }

  Future<bool> hasPotentialLoginSession() async {
    final List<Cookie> cookies = await cookieJar.loadForRequest(baseUri);
    return cookies.any((Cookie cookie) => cookie.name != 'nox_jst_v1');
  }

  Future<List<Cookie>> exportCookies() {
    return cookieJar.loadForRequest(baseUri);
  }

  Future<void> importCookies(List<Cookie> cookies) async {
    final List<Cookie> regularCookies = <Cookie>[];
    Cookie? wafCookie;
    for (final Cookie cookie in cookies) {
      if (cookie.name == 'nox_jst_v1') {
        wafCookie = cookie;
      } else {
        regularCookies.add(cookie);
      }
    }
    await cookieJar.saveFromResponse(baseUri, regularCookies);
    if (wafCookie != null) {
      await _replaceWafCookie(
        value: wafCookie.value,
        path: wafCookie.path ?? '/',
        expires:
            wafCookie.expires ??
            DateTime.now().toUtc().add(const Duration(minutes: 30)),
      );
    }
  }

  Future<void> _refreshWafCookie() {
    final Future<void>? pending = _pendingWafChallenge;
    if (pending != null) {
      return pending;
    }
    final Future<void> challenge = _solveAndImportWafCookie();
    _pendingWafChallenge = challenge;
    return challenge.whenComplete(() {
      if (identical(_pendingWafChallenge, challenge)) {
        _pendingWafChallenge = null;
      }
    });
  }

  Future<void> _solveAndImportWafCookie() async {
    final WafChallengeSolver? solver = _wafChallengeSolver;
    if (solver == null) {
      throw const ForumConnectionException('当前平台不支持论坛安全验证');
    }
    try {
      final WafChallengeCookie result = await solver.solve(baseUri);
      await _replaceWafCookie(
        value: result.value,
        path: result.path,
        expires: result.expires,
      );
      _wafCookieGeneration++;
    } on WafChallengeException catch (error) {
      throw ForumConnectionException(error.message);
    }
  }

  Future<void> _replaceWafCookie({
    required String value,
    required String path,
    required DateTime expires,
  }) async {
    final String cookiePath = path.isEmpty ? '/' : path;
    final DateTime expired = DateTime.fromMillisecondsSinceEpoch(
      0,
      isUtc: true,
    );
    final Cookie expiredHostCookie = Cookie('nox_jst_v1', '')
      ..path = cookiePath
      ..expires = expired
      ..secure = true;
    await cookieJar.saveFromResponse(baseUri, <Cookie>[expiredHostCookie]);
    final Cookie expiredDomainCookie = Cookie('nox_jst_v1', '')
      ..domain = baseUri.host
      ..path = cookiePath
      ..expires = expired
      ..secure = true;
    await cookieJar.saveFromResponse(baseUri, <Cookie>[expiredDomainCookie]);
    final Cookie cookie = Cookie('nox_jst_v1', value)
      ..path = cookiePath
      ..expires = expires
      ..secure = true;
    await cookieJar.saveFromResponse(baseUri, <Cookie>[cookie]);
  }

  Uri _toUri(Object location) {
    if (location is Uri) {
      return location;
    }
    return resolve(location.toString());
  }

  // dart:io 记录跳转时不补全相对 Location（论坛的 findpost 跳转就是相对地址），
  // realUri 会变成没有协议和域名的地址，页面里的相对图片和链接都会解析失败。
  // 按每一跳的上一个地址逐级补全，调用方拿到的 realUri 始终是绝对地址。
  void _resolveRedirects(Response<Object?> response) {
    if (response.redirects.isEmpty) {
      return;
    }
    Uri current = response.requestOptions.uri;
    final List<RedirectRecord> resolved = <RedirectRecord>[];
    for (final RedirectRecord record in response.redirects) {
      current = current.resolveUri(record.location);
      resolved.add(RedirectRecord(record.statusCode, record.method, current));
    }
    response.redirects = resolved;
  }

  Uri _withQueryParameters(Uri uri, Map<String, dynamic>? queryParameters) {
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: <String, dynamic>{
        ...uri.queryParameters,
        ...queryParameters,
      },
    );
  }

  ForumConnectionException _failure(
    DioException? error, {
    required String unreachable,
  }) {
    final String message = _failureMessage(error, unreachable: unreachable);
    return _isUnreachable(error)
        ? ForumUnreachableException(message)
        : ForumConnectionException(message);
  }

  // 论坛给出了 HTTP 响应或请求被主动取消时网络是通的，调用方不能当作离线处理。
  bool _isUnreachable(DioException? error) {
    return switch (error?.type) {
      DioExceptionType.badResponse || DioExceptionType.cancel => false,
      _ => true,
    };
  }

  // Dio 的 message 是面向开发者的英文长文本，界面只展示可理解的中文原因。
  String _failureMessage(DioException? error, {required String unreachable}) {
    if (error == null) {
      return unreachable;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => '连接百合会论坛超时，请稍后重试',
      DioExceptionType.badResponse =>
        '论坛返回异常（HTTP ${error.response?.statusCode ?? '未知'}），请稍后重试',
      DioExceptionType.badCertificate => '论坛证书校验失败，请检查网络环境',
      DioExceptionType.cancel => '论坛请求已取消',
      _ => unreachable,
    };
  }

  bool _canRetry(DioException error) {
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.unknown;
  }

  bool _isWafChallenge(DioException error) {
    if (error.response?.statusCode != HttpStatus.methodNotAllowed) {
      return false;
    }
    final String server = error.response?.headers.value('server') ?? '';
    if (server.toUpperCase().contains('BAIDU_WAF')) {
      return true;
    }
    final Object? data = error.response?.data;
    return data is String &&
        data.contains('__noxExpire') &&
        data.contains('nox_');
  }
}
