import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_web_cookie_bridge.dart';
import 'package:x300/core/network/forum_webview_cookie_session.dart';
import 'package:x300/core/network/waf_challenge_solver.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/forum/data/forum_webview_policy.dart';
import 'package:x300/features/forum/presentation/forum_android_file_selector.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';

bool get forumOriginalPageSupported => Platform.isAndroid || Platform.isIOS;

class ForumOriginalPage extends ConsumerStatefulWidget {
  const ForumOriginalPage({
    required this.initialUri,
    this.label = '论坛原页',
    this.policy = const ForumWebViewPolicy(),
    super.key,
  });

  final Uri initialUri;
  final String label;
  final ForumWebViewPolicy policy;

  @override
  ConsumerState<ForumOriginalPage> createState() {
    return _ForumOriginalPageState();
  }
}

class _ForumOriginalPageState extends ConsumerState<ForumOriginalPage> {
  final ForumAndroidFileSelectorAdapter _androidFileSelector =
      ForumAndroidFileSelectorAdapter();
  WebViewController? _controller;
  final ForumWebCookieBridge _cookieBridge = ForumWebCookieBridge();
  Future<void>? _initialization;
  ForumWebViewCookieSessionLease? _cookieSessionLease;
  bool _initialized = false;
  bool _initializationFailed = false;
  bool _pageLoading = true;
  bool _finishing = false;
  bool _allowPop = false;
  bool _webViewDetached = false;
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
    unawaited(_disableAndroidFileSelector().catchError((Object _) {}));
    if (!_initializationRunning) {
      unawaited(_restoreWebCookiesAndRelease().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (!forumOriginalPageSupported) {
      return;
    }
    widget.policy.requireRegisteredInitialUri(widget.initialUri);
    _entryUserId = ref.read(forumClientProvider).activeUserId;
    final WebViewController controller = WebViewController();
    final NavigationDelegate navigationDelegate = NavigationDelegate(
      onNavigationRequest: (NavigationRequest request) {
        final Uri? uri = Uri.tryParse(request.url);
        if (uri != null && widget.policy.isAllowedNavigation(uri)) {
          return NavigationDecision.navigate;
        }
        _showMessage('已阻止离开百合会移动页面');
        return NavigationDecision.prevent;
      },
      onPageStarted: (String _) {
        if (mounted) {
          setState(() => _pageLoading = true);
        }
      },
      onPageFinished: (String _) {
        if (mounted) {
          setState(() => _pageLoading = false);
        }
      },
    );
    _controller = controller;
    _initializationRunning = true;
    _initialization = _initialize(controller, navigationDelegate);
  }

  @override
  Widget build(BuildContext context) {
    if (!forumOriginalPageSupported) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.label)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('当前平台不支持论坛原页'),
          ),
        ),
      );
    }
    return PopScope<Object?>(
      canPop: _allowPop || _initializationFailed,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          if (_initialized) {
            unawaited(_finish());
          } else {
            _showMessage('正在安全同步论坛会话，请稍候');
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '关闭',
            onPressed: _finishing
                ? null
                : _initialized
                ? _finish
                : _initializationFailed
                ? _closeWithoutSync
                : null,
            icon: const Icon(Icons.close),
          ),
          title: Text(widget.label),
          actions: <Widget>[
            IconButton(
              tooltip: '刷新',
              onPressed: _finishing || !_initialized
                  ? null
                  : () => _controller?.reload(),
              icon: const Icon(Icons.refresh),
            ),
            TextButton(
              onPressed: _finishing || !_initialized ? null : _finish,
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
        body: Column(
          children: <Widget>[
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.security, size: 17),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '论坛原页 · 仅允许百合会 HTTPS 移动页面',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _buildWebView()),
          ],
        ),
      ),
    );
  }

  Future<void> _initialize(
    WebViewController controller,
    NavigationDelegate navigationDelegate,
  ) async {
    try {
      final ForumControlledWebSession session = await ref
          .read(forumClientProvider)
          .beginControlledWebSession();
      _cookieSessionLease = session.lease;
      _entryIdentityGeneration = session.identityGeneration;
      if (_disposed) {
        return;
      }
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (_disposed) {
        return;
      }
      await controller.setNavigationDelegate(navigationDelegate);
      if (_disposed) {
        return;
      }
      await _configureAndroidFileSelector(controller);
      if (_disposed) {
        return;
      }
      await _prepare(controller, session.cookies);
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

  Widget _buildWebView() {
    if (_terminalSyncError.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '论坛原页状态同步失败：$_terminalSyncError\n请关闭后重新进入。',
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
            Text('正在复核论坛身份'),
          ],
        ),
      );
    }
    return FutureBuilder<void>(
      future: _initialization,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '无法打开论坛原页：${snapshot.error}',
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
            WebViewWidget(controller: _controller!),
            if (_pageLoading) const LinearProgressIndicator(),
          ],
        );
      },
    );
  }

  Future<void> _prepare(
    WebViewController controller,
    List<Cookie> nativeCookies,
  ) async {
    await controller.setUserAgent(forumUserAgent);
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
    await controller.loadRequest(widget.initialUri);
  }

  Future<void> _finish() async {
    if (_finishing) {
      return;
    }
    final Future<void>? initialization = _initialization;
    if (initialization == null) {
      return;
    }
    setState(() => _finishing = true);
    ForumWebSessionTransitionReservation? reservation;
    try {
      await initialization;
      await _disableAndroidFileSelector().catchError((Object _) {});
      await _controller!.setJavaScriptMode(JavaScriptMode.disabled);
      await _controller!.setNavigationDelegate(
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
      if (!mounted) {
        return;
      }
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
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
        _initializationFailed = true;
        _webViewDetached = true;
        _terminalSyncError = terminalError.toString();
      });
    }
  }

  Future<void> _closeWithoutSync() async {
    await _restoreWebCookiesAndRelease();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(false);
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
            clearCookies: () => _cookieBridge.clearCookies(ForumClient.baseUri),
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

  Future<void> _configureAndroidFileSelector(
    WebViewController controller,
  ) async {
    if (!Platform.isAndroid) {
      return;
    }
    final Object platformController = controller.platform;
    if (platformController is! AndroidWebViewController) {
      throw StateError('Android WebView controller is unavailable');
    }
    await platformController.setOnShowFileSelector((FileSelectorParams params) {
      return _androidFileSelector.select(
        params,
        isEnabled: _fileSelectionEnabled,
      );
    });
  }

  Future<void> _disableAndroidFileSelector() async {
    if (!Platform.isAndroid) {
      return;
    }
    final Object? platformController = _controller?.platform;
    if (platformController is AndroidWebViewController) {
      await platformController.setOnShowFileSelector(null);
    }
  }

  bool _fileSelectionEnabled() {
    return mounted &&
        !_disposed &&
        _initialized &&
        !_initializationFailed &&
        !_finishing &&
        !_webViewDetached;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
