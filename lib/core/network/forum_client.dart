import 'dart:async';
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
import 'package:x300/core/network/forum_webview_cookie_session.dart';
import 'package:x300/core/network/waf_challenge_solver.dart';

final Provider<ForumClient> forumClientProvider = Provider<ForumClient>((
  Ref ref,
) {
  throw UnimplementedError('ForumClient must be overridden at startup.');
});

class ForumWebSessionVerification<T> {
  const ForumWebSessionVerification({
    required this.userId,
    required this.value,
  });

  final int userId;
  final T value;
}

class ForumByteStreamResponse {
  const ForumByteStreamResponse({
    required this.stream,
    required this.headers,
    required this.finalUri,
    required this.contentLength,
  });

  final Stream<Uint8List> stream;
  final Headers headers;
  final Uri finalUri;
  final int? contentLength;
}

class ForumControlledWebSession {
  const ForumControlledWebSession({
    required this.cookies,
    required this.identityGeneration,
    required this.lease,
  });

  final List<Cookie> cookies;
  final int identityGeneration;
  final ForumWebViewCookieSessionLease lease;
}

class ForumWebSessionTransitionReservation {
  ForumWebSessionTransitionReservation._(this._client, this.identityGeneration);

  ForumClient? _client;
  final int identityGeneration;

  void cancel() {
    final ForumClient? client = _client;
    if (client != null) {
      client._cancelWebSessionTransitionReservation(this);
    }
  }
}

class _RetryControlledWebSession implements Exception {
  const _RetryControlledWebSession();
}

class ForumClient {
  ForumClient._(
    this._dio,
    this._publicDio,
    this._cookieJar,
    this._cookieManager,
    this._wafChallengeSolver,
    this._sessionRoot,
    this._activeUserId,
    this._hasPendingWebIdentity,
    this._pendingPreviousUserId,
  );

  static final Uri baseUri = Uri.parse('https://bbs.yamibo.com/');

  final Dio _dio;
  final Dio _publicDio;
  CookieJar _cookieJar;
  CookieManager _cookieManager;
  final WafChallengeSolver? _wafChallengeSolver;
  final String? _sessionRoot;
  int _activeUserId;
  bool _hasPendingWebIdentity;
  int _pendingPreviousUserId;
  bool _identityTransitionInFlight = false;
  Completer<void>? _identityTransitionCompleter;
  ForumWebSessionTransitionReservation? _reservedWebTransition;
  int _identityGeneration = 0;
  Future<void>? _pendingWafChallenge;
  int _wafCookieGeneration = 0;
  Future<void> _sessionBarrier = Future<void>.value();
  int _activeRequests = 0;
  final Object _activeSessionZoneKey = Object();
  Completer<void>? _idleCompleter;

  CookieJar get cookieJar => _cookieJar;

  int get activeUserId => _activeUserId;

  bool get hasPendingWebIdentity => _hasPendingWebIdentity;

  static Future<ForumClient> create({
    WafChallengeSolver? wafChallengeSolver,
    Directory? supportDirectory,
    int userId = 0,
    @visibleForTesting HttpClientAdapter? httpClientAdapter,
  }) async {
    if (userId < 0) {
      throw ArgumentError.value(userId, 'userId');
    }
    final Directory resolvedSupportDirectory =
        supportDirectory ?? await getApplicationSupportDirectory();
    final String sessionRoot = path.join(
      resolvedSupportDirectory.path,
      'sessions',
    );
    final int? pendingPreviousUserId = await _readIdentityPendingPreviousUserId(
      sessionRoot,
    );
    final bool hasPendingWebIdentity = pendingPreviousUserId != null;
    final int rememberedUserId = await _readActiveUserId(sessionRoot);
    final int activeUserId = hasPendingWebIdentity
        ? 0
        : rememberedUserId > 0
        ? rememberedUserId
        : userId;
    final String cookieDirectory = _accountSessionDirectory(
      sessionRoot,
      activeUserId,
    );
    await Directory(cookieDirectory).create(recursive: true);

    final PersistCookieJar cookieJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(cookieDirectory),
    );
    await _migrateLegacySession(sessionRoot, cookieJar);
    if (activeUserId > 0) {
      await _writeActiveUserId(sessionRoot, activeUserId);
    }
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
    final Dio publicDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 20),
        followRedirects: true,
        maxRedirects: 8,
        headers: const <String, String>{
          HttpHeaders.userAgentHeader: forumUserAgent,
          HttpHeaders.acceptLanguageHeader: 'zh-CN,zh;q=0.9,zh-TW;q=0.8',
        },
      ),
    );
    if (httpClientAdapter != null) {
      dio.httpClientAdapter = httpClientAdapter;
    }
    if (Platform.environment['PAGE300_FORCE_OFFLINE'] == '1') {
      final InterceptorsWrapper offlineInterceptor = InterceptorsWrapper(
        onRequest:
            (RequestOptions options, RequestInterceptorHandler handler) =>
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionError,
                    message: '300X forced offline transport',
                  ),
                ),
      );
      dio.interceptors.add(offlineInterceptor);
      publicDio.interceptors.add(
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
    final CookieManager cookieManager = CookieManager(cookieJar);
    dio.interceptors.add(cookieManager);

    return ForumClient._(
      dio,
      publicDio,
      cookieJar,
      cookieManager,
      wafChallengeSolver,
      sessionRoot,
      activeUserId,
      hasPendingWebIdentity,
      pendingPreviousUserId ?? 0,
    );
  }

  @visibleForTesting
  factory ForumClient.forTesting(
    Dio dio,
    CookieJar cookieJar, {
    WafChallengeSolver? wafChallengeSolver,
    Dio? publicDio,
  }) {
    final CookieManager cookieManager = CookieManager(cookieJar);
    dio.interceptors.add(cookieManager);
    return ForumClient._(
      dio,
      publicDio ?? Dio(),
      cookieJar,
      cookieManager,
      wafChallengeSolver,
      null,
      0,
      false,
      0,
    );
  }

  Uri resolve(String location) {
    return baseUri.resolve(location);
  }

  Future<Response<String>> getText(
    Object location, {
    Map<String, dynamic>? queryParameters,
    String? referer,
    int retryCount = 2,
  }) {
    return _withActiveSession(
      () => _getText(
        location,
        queryParameters: queryParameters,
        referer: referer,
        retryCount: retryCount,
      ),
    );
  }

  Future<Response<String>> _getText(
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
        return _normalizeRedirects(response, uri);
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

    throw ForumConnectionException(lastError?.message ?? '无法连接百合会论坛');
  }

  Future<Response<String>> postForm(
    Object location, {
    required Map<String, dynamic> fields,
    String? referer,
    ListFormat listFormat = ListFormat.multi,
  }) {
    return _withActiveSession(
      () => _postForm(
        location,
        fields: fields,
        referer: referer,
        listFormat: listFormat,
      ),
    );
  }

  Future<Response<String>> _postForm(
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
      return _getText(target, referer: uri.toString());
    } on DioException catch (error) {
      if (_isWafChallenge(error)) {
        if (wafCookieGeneration == _wafCookieGeneration) {
          await _refreshWafCookie();
        }
        throw const ForumConnectionException('论坛安全验证已更新，请重新提交');
      }
      final int? statusCode = error.response?.statusCode;
      throw ForumConnectionException(
        statusCode == null ? '提交论坛表单失败，请检查网络连接' : '论坛拒绝提交（HTTP $statusCode）',
      );
    }
  }

  Future<Uint8List> getBytes(Object location, {String? referer}) {
    final Uri uri = _toUri(location);
    if (!_isForumOrigin(uri)) {
      return _getPublicBytes(uri, referer: referer);
    }
    return _withActiveSession(() => _getBytes(uri, referer: referer));
  }

  Future<T> consumeByteStream<T>(
    Object location, {
    required Future<T> Function(ForumByteStreamResponse response) consume,
    String? referer,
    CancelToken? cancelToken,
    bool Function(Uri uri)? allowRedirect,
  }) {
    final Uri uri = _toUri(location);
    if (!_isForumOrigin(uri)) {
      return _consumeByteStream(
        _publicDio,
        uri,
        consume: consume,
        referer: referer,
        cancelToken: cancelToken,
        allowRedirect: allowRedirect,
        isForumRequest: false,
      );
    }
    return _withActiveSession(
      () => _consumeByteStream(
        _dio,
        uri,
        consume: consume,
        referer: referer,
        cancelToken: cancelToken,
        allowRedirect: allowRedirect,
        isForumRequest: true,
      ),
    );
  }

  Future<T> _consumeByteStream<T>(
    Dio dio,
    Uri uri, {
    required Future<T> Function(ForumByteStreamResponse response) consume,
    required bool isForumRequest,
    String? referer,
    CancelToken? cancelToken,
    bool Function(Uri uri)? allowRedirect,
  }) async {
    bool wafRecoveryAttempted = false;
    final int wafCookieGeneration = _wafCookieGeneration;
    Uri currentUri = uri;
    int redirectCount = 0;
    while (true) {
      try {
        final Response<ResponseBody> response = await dio.getUri<ResponseBody>(
          currentUri,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            maxRedirects: 0,
            validateStatus: (int? status) =>
                status != null && status >= 200 && status < 400,
            headers: referer == null
                ? null
                : <String, String>{HttpHeaders.refererHeader: referer},
          ),
        );
        final ResponseBody? body = response.data;
        if (body == null) {
          throw const ForumConnectionException('论坛下载未返回文件内容');
        }
        final int statusCode = response.statusCode ?? 0;
        if (statusCode >= 300) {
          await body.stream.drain<void>();
          final String location =
              response.headers.value(HttpHeaders.locationHeader) ?? '';
          final Uri nextUri;
          try {
            nextUri = currentUri.resolve(location);
          } on FormatException {
            throw const ForumConnectionException('论坛下载返回了无效跳转');
          }
          if (location.isEmpty ||
              redirectCount >= 8 ||
              (isForumRequest && !_isForumOrigin(nextUri)) ||
              (allowRedirect != null && !allowRedirect(nextUri))) {
            throw const ForumConnectionException('论坛下载返回了无效跳转');
          }
          redirectCount++;
          currentUri = nextUri;
          continue;
        }
        final int contentLength = body.contentLength;
        return await consume(
          ForumByteStreamResponse(
            stream: body.stream,
            headers: response.headers,
            finalUri: currentUri,
            contentLength: contentLength >= 0 ? contentLength : null,
          ),
        );
      } on DioException catch (error) {
        if (isForumRequest && !wafRecoveryAttempted && _isWafChallenge(error)) {
          wafRecoveryAttempted = true;
          if (wafCookieGeneration == _wafCookieGeneration) {
            await _refreshWafCookie();
          }
          continue;
        }
        if (CancelToken.isCancel(error)) {
          rethrow;
        }
        throw ForumConnectionException(
          isForumRequest ? '下载论坛附件失败，请稍后重试' : '下载外站文件失败，请稍后重试',
        );
      }
    }
  }

  Future<Uint8List> _getPublicBytes(Uri uri, {String? referer}) async {
    try {
      final Response<List<int>> response = await _publicDio.getUri<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          headers: referer == null
              ? null
              : <String, String>{HttpHeaders.refererHeader: referer},
        ),
      );
      final Response<List<int>> normalized = _normalizeRedirects(response, uri);
      return Uint8List.fromList(normalized.data ?? const <int>[]);
    } on DioException catch (error) {
      throw ForumConnectionException(error.message ?? '加载外站图片失败');
    }
  }

  Future<Uint8List> _getBytes(Object location, {String? referer}) async {
    bool wafRecoveryAttempted = false;
    final int wafCookieGeneration = _wafCookieGeneration;
    while (true) {
      try {
        final Uri uri = _toUri(location);
        final Response<List<int>> response = await _dio.getUri<List<int>>(
          uri,
          options: Options(
            responseType: ResponseType.bytes,
            headers: referer == null
                ? null
                : <String, String>{HttpHeaders.refererHeader: referer},
          ),
        );
        final Response<List<int>> normalized = _normalizeRedirects(
          response,
          uri,
        );
        return Uint8List.fromList(normalized.data ?? const <int>[]);
      } on DioException catch (error) {
        if (!wafRecoveryAttempted && _isWafChallenge(error)) {
          wafRecoveryAttempted = true;
          if (wafCookieGeneration == _wafCookieGeneration) {
            await _refreshWafCookie();
          }
          continue;
        }
        throw ForumConnectionException(error.message ?? '加载论坛图片失败');
      }
    }
  }

  bool _isForumOrigin(Uri uri) {
    return uri.scheme == baseUri.scheme &&
        uri.host == baseUri.host &&
        uri.port == baseUri.port;
  }

  Response<T> _normalizeRedirects<T>(Response<T> response, Uri requestUri) {
    if (response.redirects.isEmpty) {
      return response;
    }
    Uri current = requestUri;
    response.redirects = response.redirects
        .map((RedirectRecord redirect) {
          current = current.resolveUri(redirect.location);
          return RedirectRecord(redirect.statusCode, redirect.method, current);
        })
        .toList(growable: false);
    return response;
  }

  Future<void> clearSession() async {
    await _mutateSession(() async {
      await _cookieJar.deleteAll();
      if (_activeUserId != 0) {
        await _activateAccountUnlocked(0);
        await _cookieJar.deleteAll();
      } else if (_sessionRoot case final String sessionRoot) {
        if (_hasPendingWebIdentity) {
          await _deletePreviousAccountSession(
            sessionRoot,
            _pendingPreviousUserId,
            confirmedUserId: 0,
          );
        }
        await _deleteActiveUserId(sessionRoot);
        await _deleteIdentityPendingMarker(sessionRoot);
      }
      _hasPendingWebIdentity = false;
      _pendingPreviousUserId = 0;
      _identityGeneration++;
    });
  }

  Future<bool> hasPotentialLoginSession() {
    return _withActiveSession(() async {
      final List<Cookie> cookies = await _cookieJar.loadForRequest(baseUri);
      return cookies.any((Cookie cookie) => cookie.name != 'nox_jst_v1');
    });
  }

  Future<void> activateAccount(
    int userId, {
    bool migrateCurrentCookies = false,
  }) {
    if (userId < 0) {
      throw ArgumentError.value(userId, 'userId');
    }
    if (_hasPendingWebIdentity || _identityTransitionInFlight) {
      return Future<void>.error(const ForumSessionExpiredException());
    }
    return _mutateSession(() async {
      if (userId == _activeUserId) {
        return;
      }
      await _activateAccountUnlocked(
        userId,
        migrateCurrentCookies: migrateCurrentCookies,
      );
    });
  }

  Future<void> _activateAccountUnlocked(
    int userId, {
    bool migrateCurrentCookies = false,
  }) async {
    final String? sessionRoot = _sessionRoot;
    if (sessionRoot == null) {
      throw StateError(
        'Account switching is unavailable for this ForumClient.',
      );
    }
    final CookieJar previousJar = _cookieJar;
    final bool committingPendingIdentity = _hasPendingWebIdentity;
    final List<Cookie> snapshot = migrateCurrentCookies
        ? await previousJar.loadForRequest(baseUri)
        : const <Cookie>[];
    final String directory = _accountSessionDirectory(sessionRoot, userId);
    await Directory(directory).create(recursive: true);
    final PersistCookieJar nextJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(directory),
    );
    if (migrateCurrentCookies) {
      await nextJar.deleteAll();
      if (snapshot.isNotEmpty) {
        await nextJar.saveFromResponse(baseUri, snapshot);
      }
    }

    if (userId > 0) {
      await _writeActiveUserId(sessionRoot, userId);
    } else {
      await _deleteActiveUserId(sessionRoot);
    }
    if (committingPendingIdentity) {
      await _deletePreviousAccountSession(
        sessionRoot,
        _pendingPreviousUserId,
        confirmedUserId: userId,
      );
    }
    await _deleteIdentityPendingMarker(sessionRoot);

    _dio.interceptors.remove(_cookieManager);
    final CookieManager nextManager = CookieManager(nextJar);
    _dio.interceptors.add(nextManager);
    _cookieJar = nextJar;
    _cookieManager = nextManager;
    _activeUserId = userId;
    _hasPendingWebIdentity = false;
    _pendingPreviousUserId = 0;
    _identityGeneration++;
    _wafCookieGeneration++;
    if (migrateCurrentCookies) {
      try {
        await previousJar.deleteAll();
      } on Object {
        // active_uid + identity_pending 已完成提交；旧桶仅做尽力清理。
        if (!committingPendingIdentity) {
          rethrow;
        }
      }
    }
  }

  Future<List<Cookie>> exportCookies() {
    return _withActiveSession(() => _cookieJar.loadForRequest(baseUri));
  }

  Future<ForumControlledWebSession> beginControlledWebSession() {
    if (_hasPendingWebIdentity) {
      return Future<ForumControlledWebSession>.error(
        const ForumSessionExpiredException(),
      );
    }
    return () async {
      while (true) {
        final Future<void>? pendingTransition =
            _identityTransitionCompleter?.future;
        if (pendingTransition != null) {
          await pendingTransition;
          if (_hasPendingWebIdentity) {
            throw const ForumSessionExpiredException();
          }
          continue;
        }
        try {
          return await _mutateSession(() async {
            if (_identityTransitionInFlight) {
              throw const _RetryControlledWebSession();
            }
            if (_hasPendingWebIdentity) {
              throw const ForumSessionExpiredException();
            }
            final ForumWebViewCookieSessionLease lease =
                await forumWebViewCookieSession.acquire();
            try {
              if (_identityTransitionInFlight) {
                throw const _RetryControlledWebSession();
              }
              final List<Cookie> cookies = await _cookieJar.loadForRequest(
                baseUri,
              );
              if (_identityTransitionInFlight) {
                throw const _RetryControlledWebSession();
              }
              return ForumControlledWebSession(
                cookies: cookies,
                identityGeneration: _identityGeneration,
                lease: lease,
              );
            } on Object {
              lease.release();
              rethrow;
            }
          });
        } on _RetryControlledWebSession {
          final Future<void>? transition = _identityTransitionCompleter?.future;
          if (transition != null) {
            await transition;
          }
          if (_hasPendingWebIdentity) {
            throw const ForumSessionExpiredException();
          }
          continue;
        }
      }
    }();
  }

  ForumWebSessionTransitionReservation reserveWebSessionTransition(
    int expectedIdentityGeneration,
  ) {
    if (_identityTransitionInFlight ||
        _hasPendingWebIdentity ||
        expectedIdentityGeneration != _identityGeneration) {
      throw const ForumSessionExpiredException();
    }
    final ForumWebSessionTransitionReservation reservation =
        ForumWebSessionTransitionReservation._(
          this,
          expectedIdentityGeneration,
        );
    _reservedWebTransition = reservation;
    _beginIdentityTransition();
    return reservation;
  }

  @visibleForTesting
  Future<void> importCookies(List<Cookie> cookies) {
    if (_hasPendingWebIdentity || _identityTransitionInFlight) {
      return Future<void>.error(const ForumSessionExpiredException());
    }
    return _mutateSession(() async {
      // WebView 快照只是身份会话的权威来源。WAF Cookie 由原生
      // 请求恢复链路管理，必须保留等待 active idle 后的最新值。
      final List<Cookie> regularCookies = <Cookie>[];
      for (final Cookie cookie in cookies) {
        if (cookie.name != 'nox_jst_v1') {
          regularCookies.add(cookie);
        }
      }
      final List<Cookie> nativeWafCookies =
          (await _cookieJar.loadForRequest(baseUri))
              .where((Cookie cookie) => cookie.name == 'nox_jst_v1')
              .toList(growable: false);
      await _cookieJar.deleteAll();
      await _cookieJar.saveFromResponse(baseUri, regularCookies);
      if (nativeWafCookies.isNotEmpty) {
        await _cookieJar.saveFromResponse(baseUri, nativeWafCookies);
      }
      _identityGeneration++;
    });
  }

  Future<T> transitionWebSession<T>({
    required List<Cookie> cookies,
    required Future<ForumWebSessionVerification<T>> Function() verify,
    int? expectedIdentityGeneration,
    ForumWebSessionTransitionReservation? reservation,
  }) {
    if (reservation != null) {
      if (!identical(_reservedWebTransition, reservation) ||
          !identical(reservation._client, this)) {
        return Future<T>.error(const ForumSessionExpiredException());
      }
      _reservedWebTransition = null;
      reservation._client = null;
      expectedIdentityGeneration = reservation.identityGeneration;
    } else {
      if (_identityTransitionInFlight || _hasPendingWebIdentity) {
        return Future<T>.error(const ForumSessionExpiredException());
      }
      _beginIdentityTransition();
    }
    return _mutateSession(() async {
      if (expectedIdentityGeneration != null &&
          expectedIdentityGeneration != _identityGeneration) {
        throw const ForumSessionExpiredException();
      }
      await _stageWebSessionUnlocked(cookies);
      return _verifyPendingWebSessionUnlocked(verify);
    }).whenComplete(_finishIdentityTransition);
  }

  Future<T> resumePendingWebSession<T>({
    required Future<ForumWebSessionVerification<T>> Function() verify,
  }) {
    if (_identityTransitionInFlight || !_hasPendingWebIdentity) {
      return Future<T>.error(const ForumSessionExpiredException());
    }
    _beginIdentityTransition();
    return _mutateSession(
      () => _verifyPendingWebSessionUnlocked(verify),
    ).whenComplete(_finishIdentityTransition);
  }

  void _beginIdentityTransition() {
    _identityTransitionInFlight = true;
    _identityTransitionCompleter = Completer<void>();
  }

  void _finishIdentityTransition() {
    _identityTransitionInFlight = false;
    _identityTransitionCompleter?.complete();
    _identityTransitionCompleter = null;
  }

  void _cancelWebSessionTransitionReservation(
    ForumWebSessionTransitionReservation reservation,
  ) {
    if (!identical(_reservedWebTransition, reservation) ||
        !identical(reservation._client, this)) {
      return;
    }
    _reservedWebTransition = null;
    reservation._client = null;
    _finishIdentityTransition();
  }

  Future<void> _stageWebSessionUnlocked(List<Cookie> cookies) async {
    final List<Cookie> regularCookies = cookies
        .where((Cookie cookie) => cookie.name != 'nox_jst_v1')
        .toList(growable: false);
    final List<Cookie> nativeWafCookies =
        (await _cookieJar.loadForRequest(baseUri))
            .where((Cookie cookie) => cookie.name == 'nox_jst_v1')
            .toList(growable: false);
    final String? sessionRoot = _sessionRoot;
    final int previousUserId = _activeUserId;
    final CookieJar pendingJar;
    if (sessionRoot == null) {
      pendingJar = CookieJar();
    } else {
      final String directory = _accountSessionDirectory(sessionRoot, 0);
      await Directory(directory).create(recursive: true);
      pendingJar = PersistCookieJar(
        ignoreExpires: false,
        storage: FileStorage(directory),
      );
    }
    await pendingJar.deleteAll();
    if (regularCookies.isNotEmpty) {
      await pendingJar.saveFromResponse(baseUri, regularCookies);
    }
    if (nativeWafCookies.isNotEmpty) {
      await pendingJar.saveFromResponse(baseUri, nativeWafCookies);
    }
    if (sessionRoot != null) {
      await _writeIdentityPendingMarker(sessionRoot, previousUserId);
    }

    _activeUserId = 0;
    _hasPendingWebIdentity = true;
    _pendingPreviousUserId = previousUserId;

    _dio.interceptors.remove(_cookieManager);
    final CookieManager pendingManager = CookieManager(pendingJar);
    _dio.interceptors.add(pendingManager);
    _cookieJar = pendingJar;
    _cookieManager = pendingManager;
    _identityGeneration++;
    _wafCookieGeneration++;
  }

  Future<T> _verifyPendingWebSessionUnlocked<T>(
    Future<ForumWebSessionVerification<T>> Function() verify,
  ) async {
    try {
      final ForumWebSessionVerification<T> result = await runZoned(
        verify,
        zoneValues: <Object, Object>{_activeSessionZoneKey: this},
      );
      if (result.userId < 0) {
        throw ArgumentError.value(result.userId, 'userId');
      }
      await _commitPendingWebSessionUnlocked(result.userId);
      return result.value;
    } on Object catch (error, stackTrace) {
      final String? sessionRoot = _sessionRoot;
      if (sessionRoot != null) {
        await _writeIdentityPendingMarker(sessionRoot, _pendingPreviousUserId);
      }
      _activeUserId = 0;
      _hasPendingWebIdentity = true;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _commitPendingWebSessionUnlocked(int userId) async {
    final String? sessionRoot = _sessionRoot;
    final int previousUserId = _pendingPreviousUserId;
    if (userId > 0) {
      if (sessionRoot == null) {
        _activeUserId = userId;
        _hasPendingWebIdentity = false;
        _pendingPreviousUserId = 0;
        _wafCookieGeneration++;
        return;
      }
      await _activateAccountUnlocked(userId, migrateCurrentCookies: true);
      return;
    }

    if (sessionRoot != null) {
      await _deletePreviousAccountSession(
        sessionRoot,
        previousUserId,
        confirmedUserId: 0,
      );
      await _deleteActiveUserId(sessionRoot);
      await _deleteIdentityPendingMarker(sessionRoot);
    }
    _activeUserId = 0;
    _hasPendingWebIdentity = false;
    _pendingPreviousUserId = 0;
    try {
      await _cookieJar.deleteAll();
    } on Object {
      // identity_pending 已删除，登出已提交；pending 桶只做尽力清理。
    }
    _wafCookieGeneration++;
  }

  Future<T> withActiveAccount<T>(int userId, Future<T> Function() operation) {
    if (userId <= 0) {
      throw ArgumentError.value(userId, 'userId');
    }
    return _withActiveSession(() {
      if (_activeUserId != userId) {
        throw const ForumSessionExpiredException();
      }
      return operation();
    });
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
    await _cookieJar.saveFromResponse(baseUri, <Cookie>[expiredHostCookie]);
    final Cookie expiredDomainCookie = Cookie('nox_jst_v1', '')
      ..domain = baseUri.host
      ..path = cookiePath
      ..expires = expired
      ..secure = true;
    await _cookieJar.saveFromResponse(baseUri, <Cookie>[expiredDomainCookie]);
    final Cookie cookie = Cookie('nox_jst_v1', value)
      ..path = cookiePath
      ..expires = expires
      ..secure = true;
    await _cookieJar.saveFromResponse(baseUri, <Cookie>[cookie]);
  }

  Future<T> _withActiveSession<T>(Future<T> Function() operation) async {
    if (identical(Zone.current[_activeSessionZoneKey], this)) {
      return operation();
    }
    if (_identityTransitionInFlight || _hasPendingWebIdentity) {
      throw const ForumSessionExpiredException();
    }
    while (true) {
      final Future<void> barrier = _sessionBarrier;
      await barrier;
      if (_identityTransitionInFlight || _hasPendingWebIdentity) {
        throw const ForumSessionExpiredException();
      }
      if (!identical(barrier, _sessionBarrier)) {
        continue;
      }
      _activeRequests++;
      if (!identical(barrier, _sessionBarrier)) {
        _finishActiveRequest();
        continue;
      }
      try {
        return await runZoned(
          operation,
          zoneValues: <Object, Object>{_activeSessionZoneKey: this},
        );
      } finally {
        _finishActiveRequest();
      }
    }
  }

  Future<T> _mutateSession<T>(Future<T> Function() operation) {
    final Future<void> previousBarrier = _sessionBarrier;
    final Completer<void> barrier = Completer<void>();
    _sessionBarrier = barrier.future;
    return () async {
      try {
        await previousBarrier;
        await _waitForIdle();
        return await operation();
      } finally {
        barrier.complete();
      }
    }();
  }

  Future<void> _waitForIdle() {
    if (_activeRequests == 0) {
      return Future<void>.value();
    }
    return (_idleCompleter ??= Completer<void>()).future;
  }

  void _finishActiveRequest() {
    _activeRequests--;
    if (_activeRequests == 0) {
      _idleCompleter?.complete();
      _idleCompleter = null;
    }
  }

  Uri _toUri(Object location) {
    if (location is Uri) {
      return location;
    }
    return resolve(location.toString());
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

  static String _accountSessionDirectory(String root, int userId) {
    return path.join(root, userId > 0 ? 'uid-$userId' : 'pending');
  }

  static Future<int?> _readIdentityPendingPreviousUserId(
    String sessionRoot,
  ) async {
    final File marker = File(path.join(sessionRoot, 'identity_pending'));
    if (!await marker.exists()) {
      return null;
    }
    try {
      final String value = (await marker.readAsString()).trim();
      if (value.isEmpty || value == '1') {
        return 0;
      }
      final RegExpMatch? match = RegExp(
        r'^previous_uid=([0-9]+)$',
      ).firstMatch(value);
      if (match != null) {
        return int.tryParse(match.group(1)!) ?? 0;
      }
    } on FileSystemException {
      // 标记不可读时仍按 pending 处理，禁止回绑 active_uid。
    }
    return 0;
  }

  static Future<void> _writeIdentityPendingMarker(
    String sessionRoot,
    int previousUserId,
  ) async {
    await Directory(sessionRoot).create(recursive: true);
    final File marker = File(path.join(sessionRoot, 'identity_pending'));
    final File temporary = File(
      path.join(
        sessionRoot,
        '.identity_pending.$pid.'
        '${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    await temporary.writeAsString(
      'previous_uid=$previousUserId\n',
      flush: true,
    );
    try {
      await temporary.rename(marker.path);
    } on FileSystemException {
      if (await marker.exists()) {
        await marker.delete();
      }
      await temporary.rename(marker.path);
    }
  }

  static Future<void> _deleteIdentityPendingMarker(String sessionRoot) async {
    final File marker = File(path.join(sessionRoot, 'identity_pending'));
    if (await marker.exists()) {
      await marker.delete();
    }
  }

  static Future<void> _deletePreviousAccountSession(
    String sessionRoot,
    int previousUserId, {
    required int confirmedUserId,
  }) async {
    if (previousUserId <= 0 || previousUserId == confirmedUserId) {
      return;
    }
    final String directory = _accountSessionDirectory(
      sessionRoot,
      previousUserId,
    );
    final PersistCookieJar jar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(directory),
    );
    await jar.deleteAll();
  }

  static Future<int> _readActiveUserId(String sessionRoot) async {
    final File marker = File(path.join(sessionRoot, 'active_uid'));
    if (!await marker.exists()) {
      return 0;
    }
    final String value;
    try {
      value = (await marker.readAsString()).trim();
    } on FileSystemException {
      return 0;
    }
    final int? userId = RegExp(r'^[1-9][0-9]*$').hasMatch(value)
        ? int.tryParse(value)
        : null;
    if (userId == null ||
        !await Directory(
          _accountSessionDirectory(sessionRoot, userId),
        ).exists()) {
      await _deleteActiveUserId(sessionRoot);
      return 0;
    }
    return userId;
  }

  static Future<void> _writeActiveUserId(String sessionRoot, int userId) async {
    final File marker = File(path.join(sessionRoot, 'active_uid'));
    final File temporary = File(
      path.join(
        sessionRoot,
        '.active_uid.$pid.'
        '${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    await temporary.writeAsString('$userId\n', flush: true);
    try {
      await temporary.rename(marker.path);
    } on FileSystemException {
      if (await marker.exists()) {
        await marker.delete();
      }
      await temporary.rename(marker.path);
    }
  }

  static Future<void> _deleteActiveUserId(String sessionRoot) async {
    final File marker = File(path.join(sessionRoot, 'active_uid'));
    if (await marker.exists()) {
      await marker.delete();
    }
  }

  static Future<void> _migrateLegacySession(
    String sessionRoot,
    PersistCookieJar targetJar,
  ) async {
    final Directory legacyStorage = Directory(
      path.join(sessionRoot, 'ie0_ps1'),
    );
    if (!await legacyStorage.exists()) {
      return;
    }
    final PersistCookieJar legacyJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(sessionRoot),
    );
    final List<Cookie> legacyCookies = await legacyJar.loadForRequest(baseUri);
    final List<Cookie> targetCookies = await targetJar.loadForRequest(baseUri);
    if (targetCookies.isEmpty && legacyCookies.isNotEmpty) {
      await targetJar.saveFromResponse(baseUri, legacyCookies);
    }
    await legacyJar.deleteAll();
  }
}
