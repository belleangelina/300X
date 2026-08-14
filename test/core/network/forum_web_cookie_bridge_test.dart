import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_web_cookie_bridge.dart';

void main() {
  group('ForumWebCookieBridge codec', () {
    test('native 到 web 编码完整可表达属性', () {
      final DateTime expires = DateTime.utc(2030, 1, 2, 3, 4, 5);
      final Cookie cookie = Cookie('auth', 'secret')
        ..domain = '.yamibo.com'
        ..path = '/forum'
        ..secure = true
        ..httpOnly = true
        ..expires = expires
        ..maxAge = 3600
        ..sameSite = SameSite.strict;

      expect(
        forumWebCookiePlatformMap(cookie, forumUri: ForumClient.baseUri),
        <String, Object?>{
          'name': 'auth',
          'value': 'secret',
          'domain': '.yamibo.com',
          'path': '/forum',
          'secure': true,
          'httpOnly': true,
          'expiresEpochMilliseconds': expires.millisecondsSinceEpoch,
          'maxAge': 3600,
          'sameSite': 'Strict',
        },
      );
    });

    test('iOS 完整快照保留安全和生命周期属性', () {
      final DateTime expires = DateTime.utc(2030, 1, 2, 3, 4, 5);
      final List<Cookie> cookies =
          forumCookiesFromWebViewSnapshot(<ForumWebCookieSnapshot>[
            ForumWebCookieSnapshot(
              name: 'auth',
              value: 'changed',
              domain: '.yamibo.com',
              path: '/forum',
              secure: true,
              httpOnly: true,
              attributesComplete: true,
              expires: expires,
              maxAge: 60,
              sameSite: SameSite.none,
            ),
          ], forumUri: ForumClient.baseUri);

      expect(cookies.single.secure, isTrue);
      expect(cookies.single.httpOnly, isTrue);
      expect(cookies.single.expires, expires);
      expect(cookies.single.maxAge, 60);
      expect(cookies.single.sameSite, SameSite.none);
      expect(cookies.single.domain, '.yamibo.com');
      expect(cookies.single.path, '/forum');
    });

    test('iOS 完整快照不能降低已知认证 Cookie 安全属性', () {
      final Cookie known = Cookie('auth', 'old')
        ..secure = true
        ..httpOnly = true;
      final Cookie cookie = forumCookiesFromWebViewSnapshot(
        const <ForumWebCookieSnapshot>[
          ForumWebCookieSnapshot(
            name: 'auth',
            value: 'changed',
            domain: 'bbs.yamibo.com',
            path: '/',
            secure: false,
            httpOnly: false,
            attributesComplete: true,
          ),
        ],
        forumUri: ForumClient.baseUri,
        knownCookies: <Cookie>[known],
      ).single;

      expect(cookie.secure, isTrue);
      expect(cookie.httpOnly, isTrue);
    });

    test('Android 不完整快照继承已知 Cookie 且不降级属性', () {
      final DateTime expires = DateTime.utc(2030, 1, 2);
      final Cookie known = Cookie('auth', 'old')
        ..domain = '.yamibo.com'
        ..path = '/forum'
        ..secure = true
        ..httpOnly = true
        ..expires = expires
        ..maxAge = 3600
        ..sameSite = SameSite.strict;
      final Cookie result = forumCookiesFromWebViewSnapshot(
        const <ForumWebCookieSnapshot>[
          ForumWebCookieSnapshot(
            name: 'auth',
            value: 'changed',
            domain: 'bbs.yamibo.com',
            path: '/',
            secure: false,
            httpOnly: false,
            attributesComplete: false,
          ),
        ],
        forumUri: ForumClient.baseUri,
        knownCookies: <Cookie>[known],
      ).single;

      expect(result.value, 'changed');
      expect(result.domain, '.yamibo.com');
      expect(result.path, '/forum');
      expect(result.secure, isTrue);
      expect(result.httpOnly, isTrue);
      expect(result.expires, expires);
      expect(result.maxAge, 3600);
      expect(result.sameSite, SameSite.strict);
    });

    test('Android 新认证 Cookie 使用安全默认值', () {
      final Cookie cookie =
          forumCookiesFromWebViewSnapshot(const <ForumWebCookieSnapshot>[
            ForumWebCookieSnapshot(
              name: 'new_auth',
              value: 'created-in-web',
              domain: 'bbs.yamibo.com',
              path: '/',
              secure: false,
              httpOnly: false,
              attributesComplete: false,
            ),
          ], forumUri: ForumClient.baseUri).single;

      expect(cookie.secure, isTrue);
      expect(cookie.httpOnly, isTrue);
      expect(cookie.sameSite, SameSite.strict);
    });

    test('WAF Cookie 保持脚本可读但强制 Secure', () {
      final Cookie cookie =
          forumCookiesFromWebViewSnapshot(const <ForumWebCookieSnapshot>[
            ForumWebCookieSnapshot(
              name: 'nox_jst_v1',
              value: 'challenge',
              domain: 'bbs.yamibo.com',
              path: '/',
              secure: false,
              httpOnly: false,
              attributesComplete: false,
            ),
          ], forumUri: ForumClient.baseUri).single;

      expect(cookie.secure, isTrue);
      expect(cookie.httpOnly, isFalse);
    });

    test('Android 同名多作用域歧义 fail closed', () {
      final Cookie first = Cookie('auth', 'same')..path = '/';
      final Cookie second = Cookie('auth', 'same')..path = '/forum';

      expect(
        () => forumCookiesFromWebViewSnapshot(
          const <ForumWebCookieSnapshot>[
            ForumWebCookieSnapshot(
              name: 'auth',
              value: 'same',
              domain: 'bbs.yamibo.com',
              path: '/',
              secure: false,
              httpOnly: false,
              attributesComplete: false,
            ),
          ],
          forumUri: ForumClient.baseUri,
          knownCookies: <Cookie>[first, second],
        ),
        throwsStateError,
      );
    });

    test('Android 同名快照因缺失作用域属性而 fail closed', () {
      expect(
        () => forumCookiesFromWebViewSnapshot(const <ForumWebCookieSnapshot>[
          ForumWebCookieSnapshot(
            name: 'auth',
            value: 'first',
            domain: 'bbs.yamibo.com',
            path: '/',
            secure: false,
            httpOnly: false,
            attributesComplete: false,
          ),
          ForumWebCookieSnapshot(
            name: 'auth',
            value: 'second',
            domain: 'bbs.yamibo.com',
            path: '/',
            secure: false,
            httpOnly: false,
            attributesComplete: false,
          ),
        ], forumUri: ForumClient.baseUri),
        throwsStateError,
      );
    });

    test('拒绝跨站来源、跨站 Domain 和不安全 SameSite=None', () {
      final Cookie domain = Cookie('auth', 'value')..domain = 'com';
      final Cookie sameSite = Cookie('auth', 'value')
        ..secure = false
        ..sameSite = SameSite.none;

      expect(
        () => forumWebCookiePlatformMap(domain, forumUri: ForumClient.baseUri),
        throwsFormatException,
      );
      expect(
        () =>
            forumWebCookiePlatformMap(sameSite, forumUri: ForumClient.baseUri),
        throwsFormatException,
      );
      expect(
        () => forumCookiesFromWebViewSnapshot(
          const <ForumWebCookieSnapshot>[],
          forumUri: Uri.parse('https://example.com/'),
        ),
        throwsFormatException,
      );
    });

    test('channel adapter 严格解析完整平台快照', () async {
      String? invokedMethod;
      Object? invokedArguments;
      final ForumWebCookieBridge bridge = ForumWebCookieBridge(
        invokeMethod: (String method, Object? arguments) async {
          invokedMethod = method;
          invokedArguments = arguments;
          return <Object?>[
            <String, Object?>{
              'name': 'auth',
              'value': 'secret',
              'domain': '.yamibo.com',
              'path': '/',
              'secure': true,
              'httpOnly': true,
              'expiresEpochMilliseconds': 1893456000000,
              'maxAge': 60,
              'sameSite': 'Lax',
              'attributesComplete': true,
            },
          ];
        },
      );

      final List<ForumWebCookieSnapshot> result = await bridge.readSnapshot(
        ForumClient.baseUri,
      );

      expect(invokedMethod, 'getCookies');
      expect(invokedArguments, <String, Object?>{
        'url': ForumClient.baseUri.toString(),
      });
      expect(result.single.httpOnly, isTrue);
      expect(result.single.sameSite, SameSite.lax);
    });
  });
}
