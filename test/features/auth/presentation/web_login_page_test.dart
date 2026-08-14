import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_web_cookie_bridge.dart';

void main() {
  test('Android WebView 返回 URL domain 时仍能同步论坛 Cookie', () async {
    final cookies = forumCookiesFromWebViewSnapshot(<ForumWebCookieSnapshot>[
      ForumWebCookieSnapshot(
        name: 'auth_session',
        value: 'logged-in',
        domain: ForumClient.baseUri.host,
        path: '/',
        secure: false,
        httpOnly: false,
        attributesComplete: false,
      ),
    ], forumUri: ForumClient.baseUri);

    expect(cookies.single.name, 'auth_session');
    expect(cookies.single.domain, ForumClient.baseUri.host);
    expect(cookies.single.secure, isTrue);
    expect(cookies.single.httpOnly, isTrue);
    expect(cookies.single.sameSite, SameSite.strict);
  });
}
