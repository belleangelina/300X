import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/shared/presentation/app_snack_bar.dart';

class WebLoginPage extends ConsumerStatefulWidget
{
    const WebLoginPage({super.key});

    @override
    ConsumerState<WebLoginPage> createState()
    {
        return _WebLoginPageState();
    }
}

class _WebLoginPageState extends ConsumerState<WebLoginPage>
{
    late final WebViewController _controller;
    late final WebViewCookieManager _cookieManager;
    late final Future<void> _initialization;
    bool _pageLoading = true;
    bool _finishing = false;

    @override
    void initState()
    {
        super.initState();
        if (!Platform.isAndroid && !Platform.isIOS)
        {
            throw UnsupportedError('当前平台不支持网页登录');
        }
        _cookieManager = WebViewCookieManager();
        _controller = WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setNavigationDelegate(NavigationDelegate(
                onPageStarted: (String url)
                {
                    if (mounted)
                    {
                        setState(()
                        {
                            _pageLoading = true;
                        });
                    }
                },
                onPageFinished: (String url)
                {
                    if (mounted)
                    {
                        setState(()
                        {
                            _pageLoading = false;
                        });
                    }
                },
            ));
        _initialization = _prepare();
    }

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            appBar: AppBar(
                title: const Text('网页登录'),
                actions: <Widget>[
                    TextButton(
                        onPressed: _finishing ? null : _finish,
                        child: _finishing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                ),
                            )
                            : const Text('完成'),
                    ),
                ],
            ),
            body: FutureBuilder<void>(
                future: _initialization,
                builder: (
                    BuildContext context,
                    AsyncSnapshot<void> snapshot,
                )
                {
                    if (snapshot.hasError)
                    {
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
                    if (snapshot.connectionState != ConnectionState.done)
                    {
                        return const Center(
                            child: CircularProgressIndicator(),
                        );
                    }
                    return Stack(
                        children: <Widget>[
                            WebViewWidget(controller: _controller),
                            if (_pageLoading)
                                const LinearProgressIndicator(),
                        ],
                    );
                },
            ),
        );
    }

    Future<void> _prepare() async
    {
        final ForumClient client = ref.read(forumClientProvider);
        await _cookieManager.clearCookies();
        final List<Cookie> cookies = await client.exportCookies();
        for (final Cookie cookie in cookies)
        {
            await _cookieManager.setCookie(WebViewCookie(
                name: cookie.name,
                value: cookie.value,
                domain: (cookie.domain ?? ForumClient.baseUri.host)
                    .replaceFirst(RegExp(r'^\.'), ''),
                path: cookie.path ?? '/',
            ));
        }
        await _controller.loadRequest(AuthRepository.loginUri);
    }

    Future<void> _finish() async
    {
        setState(()
        {
            _finishing = true;
        });
        try
        {
            final List<WebViewCookie> webCookies =
                await _cookieManager.getCookies(
                    domain: ForumClient.baseUri,
                );
            final List<Cookie> cookies = forumCookiesFromWebView(webCookies);
            await ref.read(forumClientProvider).importCookies(cookies);
            await ref
                .read(authControllerProvider.notifier)
                .completeWebLogin();
            if (!mounted)
            {
                return;
            }
            Navigator.of(context).pop();
        }
        on Object catch (error)
        {
            if (!mounted)
            {
                return;
            }
            setState(()
            {
                _finishing = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
                AppSnackBar(content: Text('同步网页登录状态失败：$error')),
            );
        }
    }
}

List<Cookie> forumCookiesFromWebView(List<WebViewCookie> webCookies)
{
    return webCookies.map(
        (WebViewCookie value)
        {
            return Cookie(value.name, value.value)
                ..path = value.path
                ..secure = true;
        },
    ).toList(growable: false);
}
