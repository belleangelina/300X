import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/features/auth/presentation/web_login_page.dart';

void main()
{
    test('Android WebView 返回 URL domain 时仍能同步论坛 Cookie', () async
    {
        final cookies = forumCookiesFromWebView(
            <WebViewCookie>[
                WebViewCookie(
                    name: 'auth_session',
                    value: 'logged-in',
                    domain: ForumClient.baseUri.toString(),
                ),
            ],
        );
        final CookieJar cookieJar = CookieJar();

        await cookieJar.saveFromResponse(ForumClient.baseUri, cookies);
        final loaded = await cookieJar.loadForRequest(
            ForumClient.baseUri.resolve(
                'forum.php?mod=forumdisplay&fid=30&mobile=2',
            ),
        );

        expect(
            loaded.map((cookie) => cookie.name),
            contains('auth_session'),
        );
    });
}
