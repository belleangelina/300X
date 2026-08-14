import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:x300/core/network/forum_webview_cookie_session.dart';

const String forumUserAgent =
    'Mozilla/5.0 (Linux; Android 13) '
    'AppleWebKit/537.36 Chrome/126 Mobile Safari/537.36 300X/1.0';

class WafChallengeCookie
{
    const WafChallengeCookie({
        required this.name,
        required this.value,
        required this.domain,
        required this.path,
        required this.expires,
    });

    final String name;
    final String value;
    final String domain;
    final String path;
    final DateTime expires;
}

abstract class WafChallengeSolver
{
    Future<WafChallengeCookie> solve(Uri forumUri);
}

class WafChallengeHost extends StatelessWidget
{
    const WafChallengeHost({
        required this.child,
        super.key,
    });

    final Widget child;

    @override
    Widget build(BuildContext context)
    {
        if (!Platform.isAndroid && !Platform.isIOS)
        {
            return child;
        }
        return ValueListenableBuilder<_MobileWafChallengeRequest?>(
            valueListenable: _mobileWafChallengeRequest,
            child: child,
            builder: (
                BuildContext context,
                _MobileWafChallengeRequest? request,
                Widget? child,
            )
            {
                return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                        if (request != null)
                            Positioned(
                                left: 0,
                                top: 0,
                                width: 1,
                                height: 1,
                                child: ExcludeSemantics(
                                    child: IgnorePointer(
                                        child: Builder(
                                            builder: (
                                                BuildContext context,
                                            )
                                            {
                                                WidgetsBinding.instance
                                                    .addPostFrameCallback(
                                                        (_) => request
                                                            .completeMount(),
                                                    );
                                                return WebViewWidget(
                                                    controller:
                                                        request.controller,
                                                );
                                            },
                                        ),
                                    ),
                                ),
                            ),
                        child!,
                    ],
                );
            },
        );
    }
}

final ValueNotifier<_MobileWafChallengeRequest?>
    _mobileWafChallengeRequest =
        ValueNotifier<_MobileWafChallengeRequest?>(null);

class _MobileWafChallengeRequest
{
    _MobileWafChallengeRequest(this.controller);

    final WebViewController controller;
    final Completer<void> mounted = Completer<void>();

    void completeMount()
    {
        if (!mounted.isCompleted)
        {
            mounted.complete();
        }
    }
}

class WafChallengeException implements Exception
{
    const WafChallengeException(this.message);

    final String message;

    @override
    String toString()
    {
        return message;
    }
}

WafChallengeSolver createPlatformWafChallengeSolver()
{
    if (Platform.isLinux)
    {
        return const _LinuxWafChallengeSolver();
    }
    if (Platform.isAndroid || Platform.isIOS)
    {
        return const _MobileWafChallengeSolver();
    }
    return const _UnsupportedWafChallengeSolver();
}

class _LinuxWafChallengeSolver implements WafChallengeSolver
{
    const _LinuxWafChallengeSolver();

    @override
    Future<WafChallengeCookie> solve(Uri forumUri) async
    {
        final Uri helperUri = File(Platform.resolvedExecutable)
            .parent
            .uri
            .resolve('x300_waf_challenge');
        final Process process;
        try
        {
            process = await Process.start(
                File.fromUri(helperUri).path,
                const <String>[],
            );
        }
        on ProcessException
        {
            throw const WafChallengeException(
                'Linux 缺少论坛安全验证组件',
            );
        }

        final Future<String> output = process.stdout
            .transform(utf8.decoder)
            .join();
        final Future<String> errorOutput = process.stderr
            .transform(utf8.decoder)
            .join();
        int exitCode;
        try
        {
            exitCode = await process.exitCode.timeout(
                const Duration(seconds: 25),
            );
        }
        on TimeoutException
        {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode;
            throw const WafChallengeException('论坛安全验证超时');
        }
        final String result = await output;
        await errorOutput;
        if (exitCode != 0)
        {
            throw const WafChallengeException('无法完成论坛安全验证');
        }

        final List<String> fields = const LineSplitter()
            .convert(result);
        if (fields.length != 5)
        {
            throw const WafChallengeException('论坛安全验证返回无效结果');
        }
        final String value;
        try
        {
            value = utf8.decode(base64.decode(fields[1]));
        }
        on FormatException
        {
            throw const WafChallengeException('论坛安全验证返回无效结果');
        }
        final String domain = fields[2];
        final int expiresAt = int.tryParse(fields[4]) ?? 0;
        if (fields[0] != forumWafCookieName ||
            value.isEmpty ||
            domain.replaceFirst(RegExp(r'^\.'), '') != forumUri.host ||
            expiresAt <= 0)
        {
            throw const WafChallengeException(
                '论坛安全验证未返回有效 Cookie',
            );
        }
        return WafChallengeCookie(
            name: fields[0],
            value: value,
            domain: domain,
            path: fields[3],
            expires: DateTime.fromMillisecondsSinceEpoch(
                expiresAt,
                isUtc: true,
            ),
        );
    }
}

class _MobileWafChallengeSolver implements WafChallengeSolver
{
    const _MobileWafChallengeSolver();

    @override
    Future<WafChallengeCookie> solve(Uri forumUri)
    {
        return forumWebViewCookieSession.runExclusive(() async
        {
            final WebViewCookieManager cookieManager =
                WebViewCookieManager();
            return runWithForumWafCookieRecovery<WafChallengeCookie>(
                forumUri: forumUri,
                readCookies: (Uri uri) =>
                    cookieManager.getCookies(domain: uri),
                writeCookie: cookieManager.setCookie,
                operation: () => _solveWithWebView(
                    forumUri,
                    cookieManager,
                ),
            );
        });
    }

    Future<WafChallengeCookie> _solveWithWebView(
        Uri forumUri,
        WebViewCookieManager cookieManager,
    ) async
    {
        final Completer<void> completed = Completer<void>();
        bool verificationPending = false;
        final WebViewController controller = WebViewController();
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.setNavigationDelegate(NavigationDelegate(
                onPageFinished: (String url) async
                {
                    if (completed.isCompleted)
                    {
                        return;
                    }
                    try
                    {
                        final Object result =
                            await controller.runJavaScriptReturningResult(
                                '''
                                (() => {
                                    if (document.documentElement.innerHTML
                                        .includes('__noxExpire')) {
                                        return 1;
                                    }
                                    const hasCookie = document.cookie
                                        .split(';')
                                        .some((item) => {
                                            const value = item.trim();
                                            return value.startsWith(
                                                'nox_jst_v1='
                                            ) && value.length >
                                                'nox_jst_v1='.length;
                                        });
                                    return hasCookie ? 2 : 0;
                                })()
                                ''',
                            );
                        final String state = result.toString()
                            .replaceAll('"', '');
                        if (state == '1')
                        {
                            verificationPending = false;
                            return;
                        }
                        if (state != '2')
                        {
                            return;
                        }
                        if (!verificationPending)
                        {
                            verificationPending = true;
                            await controller.reload();
                            return;
                        }
                        if (!completed.isCompleted)
                        {
                            completed.complete();
                        }
                    }
                    on Object
                    {
                        // 页面跳转过程中执行 JavaScript 可能失败，下一次完成事件重试。
                    }
                },
            ));
        await controller.setUserAgent(forumUserAgent);
        final _MobileWafChallengeRequest request =
            _MobileWafChallengeRequest(controller);
        _mobileWafChallengeRequest.value = request;
        try
        {
            await request.mounted.future.timeout(
                const Duration(seconds: 5),
            );
            await controller.loadRequest(forumUri);
            await completed.future.timeout(const Duration(seconds: 20));

            final List<WebViewCookie> cookies =
                await cookieManager.getCookies(
                    domain: forumUri,
                );
            final WebViewCookie? cookie = cookies
                .cast<WebViewCookie?>()
                .firstWhere(
                    (WebViewCookie? value) =>
                        value?.name == forumWafCookieName &&
                        value!.value.isNotEmpty,
                    orElse: () => null,
                );
            if (cookie == null || cookie.value.isEmpty)
            {
                throw const WafChallengeException(
                    '论坛安全验证未返回有效 Cookie',
                );
            }
            return WafChallengeCookie(
                name: cookie.name,
                value: cookie.value,
                domain: forumUri.host,
                path: cookie.path,
                expires: DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 30)),
            );
        }
        on TimeoutException
        {
            throw const WafChallengeException('论坛安全验证超时');
        }
        finally
        {
            if (identical(_mobileWafChallengeRequest.value, request))
            {
                _mobileWafChallengeRequest.value = null;
            }
        }
    }
}

class _UnsupportedWafChallengeSolver implements WafChallengeSolver
{
    const _UnsupportedWafChallengeSolver();

    @override
    Future<WafChallengeCookie> solve(Uri forumUri)
    {
        throw const WafChallengeException('当前平台不支持论坛安全验证');
    }
}
