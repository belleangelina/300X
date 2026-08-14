import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:x300/core/network/forum_webview_cookie_session.dart';

void main() {
  test('进程级 WebView Cookie 租约串行执行', () async {
    final ForumWebViewCookieSession session = ForumWebViewCookieSession();
    final ForumWebViewCookieSessionLease first = await session.acquire();
    bool secondEntered = false;
    final Future<void> second = session.runExclusive(() async {
      secondEntered = true;
    });

    await Future<void>.delayed(Duration.zero);
    expect(secondEntered, isFalse);

    first.release();
    await second;
    expect(secondEntered, isTrue);
  });

  test('WebView Cookie 租约在异常后仍释放', () async {
    final ForumWebViewCookieSession session = ForumWebViewCookieSession();

    await expectLater(
      session.runExclusive<void>(() async {
        throw StateError('failed');
      }),
      throwsStateError,
    );

    final ForumWebViewCookieSessionLease lease = await session
        .acquire()
        .timeout(const Duration(seconds: 1));
    lease.release();
  });

  test('取消受控 WebView 时完整恢复进入前 Cookie 快照', () async {
    final _MemoryWebViewCookies cookies = _MemoryWebViewCookies(<WebViewCookie>[
      const WebViewCookie(
        name: 'auth',
        value: 'entry-auth',
        domain: 'bbs.yamibo.com',
      ),
      const WebViewCookie(
        name: forumWafCookieName,
        value: 'entry-waf',
        domain: 'bbs.yamibo.com',
      ),
    ]);
    final List<WebViewCookie> entryWebCookies = await cookies.read(
      Uri.parse('https://bbs.yamibo.com/'),
    );
    final List<Cookie> entry = entryWebCookies
        .map((WebViewCookie value) {
          return Cookie(value.name, value.value)
            ..domain = value.domain
            ..path = value.path;
        })
        .toList(growable: false);
    await cookies.clear();
    await cookies.write(
      const WebViewCookie(
        name: 'auth',
        value: 'cancelled-page-auth',
        domain: 'bbs.yamibo.com',
      ),
    );

    await replaceForumWebViewCookieSnapshot(
      cookies: entry,
      clearCookies: cookies.clear,
      writeCookie: (Cookie cookie) => cookies.write(
        WebViewCookie(
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain!,
          path: cookie.path ?? '/',
        ),
      ),
    );

    expect(cookies.value('auth'), 'entry-auth');
    expect(cookies.value(forumWafCookieName), 'entry-waf');
  });

  test('Cookie 恢复 clear 失败时异常可见且外层租约仍可释放', () async {
    final ForumWebViewCookieSession session = ForumWebViewCookieSession();
    final ForumWebViewCookieSessionLease lease = await session.acquire();

    await expectLater(() async {
      try {
        await replaceForumWebViewCookieSnapshot(
          cookies: const <Cookie>[],
          clearCookies: () async => throw StateError('clear failed'),
          writeCookie: (Cookie _) async {},
        );
      } finally {
        lease.release();
      }
    }(), throwsStateError);
    final ForumWebViewCookieSessionLease next = await session.acquire().timeout(
      const Duration(seconds: 1),
    );
    next.release();
  });

  test('Cookie 恢复 set 失败时异常可见且外层租约仍可释放', () async {
    final ForumWebViewCookieSession session = ForumWebViewCookieSession();
    final ForumWebViewCookieSessionLease lease = await session.acquire();

    await expectLater(() async {
      try {
        await replaceForumWebViewCookieSnapshot(
          cookies: <Cookie>[Cookie('auth', 'entry')..domain = 'bbs.yamibo.com'],
          clearCookies: () async {},
          writeCookie: (Cookie _) async => throw StateError('set failed'),
        );
      } finally {
        lease.release();
      }
    }(), throwsStateError);
    final ForumWebViewCookieSessionLease next = await session.acquire().timeout(
      const Duration(seconds: 1),
    );
    next.release();
  });

  test('WAF 失败恢复原 nox 且不改写认证 Cookie', () async {
    final _MemoryWebViewCookies cookies = _MemoryWebViewCookies(<WebViewCookie>[
      const WebViewCookie(
        name: 'auth',
        value: 'private-session',
        domain: 'bbs.yamibo.com',
      ),
      const WebViewCookie(
        name: forumWafCookieName,
        value: 'old-waf',
        domain: 'https://bbs.yamibo.com/',
      ),
    ]);

    await expectLater(
      runWithForumWafCookieRecovery<void>(
        forumUri: Uri.parse('https://bbs.yamibo.com/'),
        readCookies: cookies.read,
        writeCookie: cookies.write,
        operation: () async {
          await cookies.write(
            const WebViewCookie(
              name: forumWafCookieName,
              value: 'new-waf',
              domain: 'bbs.yamibo.com',
            ),
          );
          throw StateError('challenge failed');
        },
      ),
      throwsStateError,
    );

    expect(cookies.value('auth'), 'private-session');
    expect(cookies.value(forumWafCookieName), 'old-waf');
    expect(
      cookies.writes.where((WebViewCookie cookie) => cookie.name == 'auth'),
      isEmpty,
    );
  });

  test('WAF 成功保留新 nox 且不改写认证 Cookie', () async {
    final _MemoryWebViewCookies cookies = _MemoryWebViewCookies(<WebViewCookie>[
      const WebViewCookie(
        name: 'auth',
        value: 'private-session',
        domain: 'bbs.yamibo.com',
      ),
    ]);

    final String result = await runWithForumWafCookieRecovery<String>(
      forumUri: Uri.parse('https://bbs.yamibo.com/'),
      readCookies: cookies.read,
      writeCookie: cookies.write,
      operation: () async {
        await cookies.write(
          const WebViewCookie(
            name: forumWafCookieName,
            value: 'solved-waf',
            domain: 'bbs.yamibo.com',
          ),
        );
        return cookies.value(forumWafCookieName)!;
      },
    );

    expect(result, 'solved-waf');
    expect(cookies.value('auth'), 'private-session');
    expect(cookies.value(forumWafCookieName), 'solved-waf');
    expect(
      cookies.writes.where((WebViewCookie cookie) => cookie.name == 'auth'),
      isEmpty,
    );
  });
}

class _MemoryWebViewCookies {
  _MemoryWebViewCookies(List<WebViewCookie> cookies) {
    for (final WebViewCookie cookie in cookies) {
      _values[_key(cookie)] = cookie;
    }
  }

  final Map<String, WebViewCookie> _values = <String, WebViewCookie>{};
  final List<WebViewCookie> writes = <WebViewCookie>[];

  Future<List<WebViewCookie>> read(Uri uri) async {
    return _values.values.toList(growable: false);
  }

  Future<void> write(WebViewCookie cookie) async {
    writes.add(cookie);
    _values[_key(cookie)] = cookie;
  }

  Future<void> clear() async {
    _values.clear();
  }

  String? value(String name) {
    for (final WebViewCookie cookie in _values.values.toList().reversed) {
      if (cookie.name == name) {
        return cookie.value;
      }
    }
    return null;
  }

  String _key(WebViewCookie cookie) {
    final String domain = Uri.tryParse(cookie.domain)?.host.isNotEmpty == true
        ? Uri.parse(cookie.domain).host
        : cookie.domain.replaceFirst(RegExp(r'^\.'), '');
    return '$domain\n${cookie.path}\n${cookie.name}';
  }
}
