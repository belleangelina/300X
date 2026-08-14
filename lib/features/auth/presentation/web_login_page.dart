import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_web_cookie_bridge.dart';
import 'package:x300/core/network/forum_webview_cookie_session.dart';
import 'package:x300/core/network/waf_challenge_solver.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/forum/data/forum_webview_policy.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';
import 'package:x300/shared/presentation/app_snack_bar.dart';

class WebLoginPage extends ConsumerStatefulWidget {
  const WebLoginPage({super.key});

  @override
  ConsumerState<WebLoginPage> createState() {
    return _WebLoginPageState();
  }
}

class _WebLoginPageState extends ConsumerState<WebLoginPage> {
  static const ForumWebViewPolicy _webViewPolicy = ForumWebViewPolicy();

  late final WebViewController _controller;
  final ForumWebCookieBridge _cookieBridge = ForumWebCookieBridge();
  late final Future<void> _initialization;
  ForumWebViewCookieSessionLease? _cookieSessionLease;
  bool _initialized = false;
  bool _pageLoading = true;
  bool _finishing = false;
  bool _webViewDetached = false;
  bool _allowPop = false;
  bool _initializationFailed = false;
  bool _initializationRunning = false;
  bool _disposed = false;
  bool _cookieStoreModified = false;
  List<Cookie> _entryWebCookies = const <Cookie>[];
  List<Cookie> _seedNativeCookies = const <Cookie>[];
  Future<void>? _cookieCleanup;
  String _terminalSyncError = '';
  int _entryUserId = 0;
  int _entryIdentityGeneration = 0;

  @override
  void dispose() {
    _disposed = true;
    if (!_initializationRunning) {
      unawaited(_restoreWebCookiesAndRelease().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('当前平台不支持网页登录');
    }
    _webViewPolicy.requireRegisteredInitialUri(AuthRepository.loginUri);
    _entryUserId = ref.read(forumClientProvider).activeUserId;
    _controller = WebViewController();
    final NavigationDelegate navigationDelegate = NavigationDelegate(
      onNavigationRequest: (NavigationRequest request) {
        final Uri? uri = Uri.tryParse(request.url);
        if (uri != null && _webViewPolicy.isAllowedNavigation(uri)) {
          return NavigationDecision.navigate;
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const AppSnackBar(content: Text('已阻止离开百合会登录页面')));
        }
        return NavigationDecision.prevent;
      },
      onPageStarted: (String url) {
        if (mounted) {
          setState(() {
            _pageLoading = true;
          });
        }
      },
      onPageFinished: (String url) {
        if (mounted) {
          setState(() {
            _pageLoading = false;
          });
        }
      },
    );
    _initializationRunning = true;
    _initialization = _initialize(navigationDelegate);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _allowPop || _initializationFailed,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) {
          return;
        }
        if (_finishing) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const AppSnackBar(content: Text('登录状态同步完成前不能离开此页')));
        } else {
          unawaited(_cancel());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('网页登录'),
          actions: <Widget>[
            TextButton(
              onPressed:
                  _finishing || !_initialized || _terminalSyncError.isNotEmpty
                  ? null
                  : _finish,
              child: _finishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('完成'),
            ),
          ],
        ),
        body: FutureBuilder<void>(
          future: _initialization,
          builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
            if (_terminalSyncError.isNotEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '网页登录状态同步失败：$_terminalSyncError\n请关闭后重新进入。',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (_webViewDetached) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在复核登录状态'),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '无法打开论坛登录页：${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return Stack(
              children: <Widget>[
                WebViewWidget(controller: _controller),
                if (_pageLoading) const LinearProgressIndicator(),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _initialize(NavigationDelegate navigationDelegate) async {
    try {
      final ForumControlledWebSession session = await ref
          .read(forumClientProvider)
          .beginControlledWebSession();
      _cookieSessionLease = session.lease;
      _entryIdentityGeneration = session.identityGeneration;
      if (_disposed) {
        return;
      }
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (_disposed) {
        return;
      }
      await _controller.setNavigationDelegate(navigationDelegate);
      if (_disposed) {
        return;
      }
      await _prepare(session.cookies);
      if (!_disposed && mounted) {
        setState(() => _initialized = true);
      }
    } on Object catch (error, stackTrace) {
      Object terminalError = error;
      StackTrace terminalStackTrace = stackTrace;
      try {
        await _restoreWebCookiesAndRelease();
      } on Object catch (cleanupError, cleanupStackTrace) {
        terminalError = cleanupError;
        terminalStackTrace = cleanupStackTrace;
      }
      if (mounted) {
        setState(() {
          _initializationFailed = true;
          _terminalSyncError = terminalError.toString();
        });
      }
      Error.throwWithStackTrace(terminalError, terminalStackTrace);
    } finally {
      _initializationRunning = false;
      if (_disposed) {
        await _restoreWebCookiesAndRelease();
      }
    }
  }

  Future<void> _prepare(List<Cookie> nativeCookies) async {
    await _controller.setUserAgent(forumUserAgent);
    if (_disposed) {
      return;
    }
    _entryWebCookies = await _cookieBridge.getCookies(ForumClient.baseUri);
    _seedNativeCookies = nativeCookies.toList(growable: false);
    if (_disposed) {
      return;
    }
    _cookieStoreModified = true;
    await _cookieBridge.clearCookies(ForumClient.baseUri);
    if (_disposed) {
      return;
    }
    for (final Cookie cookie in nativeCookies) {
      if (cookie.name == forumWafCookieName) {
        continue;
      }
      await _cookieBridge.setCookie(ForumClient.baseUri, cookie);
      if (_disposed) {
        return;
      }
    }
    if (_disposed) {
      return;
    }
    await _controller.loadRequest(AuthRepository.loginUri);
  }

  Future<void> _finish() async {
    if (_finishing) {
      return;
    }
    setState(() {
      _finishing = true;
    });
    ForumWebSessionTransitionReservation? reservation;
    try {
      await _initialization;
      await _controller.setJavaScriptMode(JavaScriptMode.disabled);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest _) =>
              NavigationDecision.prevent,
        ),
      );
      final List<Cookie> cookies = await _cookieBridge.getCookies(
        ForumClient.baseUri,
        knownCookies: _seedNativeCookies,
      );
      if (!mounted) {
        return;
      }
      setState(() => _webViewDetached = true);
      await WidgetsBinding.instance.endOfFrame;
      final ForumClient client = ref.read(forumClientProvider);
      reservation = client.reserveWebSessionTransition(
        _entryIdentityGeneration,
      );
      await _restoreWebCookiesAndRelease();
      final AuthState authState = await ref
          .read(authControllerProvider.notifier)
          .completeWebLogin(
            cookies: cookies,
            expectedIdentityGeneration: _entryIdentityGeneration,
            reservation: reservation,
          );
      reservation = null;
      if (_entryUserId > 0 && authState.userId != _entryUserId) {
        await ref
            .read(cacheMaintenanceRepositoryProvider)
            .clearAccountCaches(_entryUserId);
      }
      if (authState.status != AuthStatus.authenticated) {
        throw StateError(
          authState.message.isEmpty ? '未检测到登录状态，请完成登录后重试' : authState.message,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object catch (error) {
      Object terminalError = error;
      reservation?.cancel();
      try {
        await _restoreWebCookiesAndRelease();
      } on Object catch (cleanupError) {
        terminalError = cleanupError;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _finishing = false;
        _initialized = false;
        _allowPop = true;
        _webViewDetached = true;
        _terminalSyncError = terminalError.toString();
      });
    }
  }

  Future<void> _cancel() async {
    if (_finishing) {
      return;
    }
    setState(() => _finishing = true);
    try {
      try {
        await _initialization;
      } on Object {
        // 初始化失败路径已经负责恢复 Cookie 并释放租约。
      }
      if (_initialized) {
        await _controller.setJavaScriptMode(JavaScriptMode.disabled);
        await _controller.setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest _) =>
                NavigationDecision.prevent,
          ),
        );
        if (mounted) {
          setState(() => _webViewDetached = true);
          await WidgetsBinding.instance.endOfFrame;
        }
      }
      await _restoreWebCookiesAndRelease();
      if (!mounted) {
        return;
      }
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _finishing = false;
        _allowPop = true;
        _webViewDetached = true;
        _terminalSyncError = error.toString();
      });
    }
  }

  Future<void> _restoreWebCookiesAndRelease() {
    final Future<void>? cleanup = _cookieCleanup;
    if (cleanup != null) {
      return cleanup;
    }
    final Future<void> next = () async {
      try {
        if (_cookieStoreModified) {
          await replaceForumWebViewCookieSnapshot(
            cookies: _entryWebCookies,
            clearCookies: () async {
              await _cookieBridge.clearCookies(ForumClient.baseUri);
            },
            writeCookie: (Cookie cookie) =>
                _cookieBridge.setCookie(ForumClient.baseUri, cookie),
          );
        }
      } finally {
        _releaseCookieSession();
      }
    }();
    _cookieCleanup = next;
    return next;
  }

  void _releaseCookieSession() {
    _cookieSessionLease?.release();
    _cookieSessionLease = null;
  }
}
