import 'dart:async';
import 'dart:io';

import 'package:webview_flutter/webview_flutter.dart';

const String forumWafCookieName = 'nox_jst_v1';

final ForumWebViewCookieSession forumWebViewCookieSession =
    ForumWebViewCookieSession();

class ForumWebViewCookieSession {
  Future<void> _tail = Future<void>.value();

  Future<ForumWebViewCookieSessionLease> acquire() {
    final Future<void> predecessor = _tail;
    final Completer<void> release = Completer<void>();
    _tail = release.future;
    return predecessor.then((_) => ForumWebViewCookieSessionLease._(release));
  }

  Future<T> runExclusive<T>(Future<T> Function() operation) async {
    final ForumWebViewCookieSessionLease lease = await acquire();
    try {
      return await operation();
    } finally {
      lease.release();
    }
  }
}

class ForumWebViewCookieSessionLease {
  ForumWebViewCookieSessionLease._(this._release);

  final Completer<void> _release;

  bool get isReleased => _release.isCompleted;

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }
}

typedef ForumWafWebViewCookieReader =
    Future<List<WebViewCookie>> Function(Uri uri);
typedef ForumWafWebViewCookieWriter =
    Future<void> Function(WebViewCookie cookie);
typedef ForumCookieWriter = Future<void> Function(Cookie cookie);
typedef ForumCookieClearer = Future<void> Function();

Future<void> replaceForumWebViewCookieSnapshot({
  required List<Cookie> cookies,
  required ForumCookieClearer clearCookies,
  required ForumCookieWriter writeCookie,
}) async {
  await clearCookies();
  for (final Cookie cookie in cookies) {
    await writeCookie(cookie);
  }
}

Future<T> runWithForumWafCookieRecovery<T>({
  required Uri forumUri,
  required ForumWafWebViewCookieReader readCookies,
  required ForumWafWebViewCookieWriter writeCookie,
  required Future<T> Function() operation,
}) async {
  final List<WebViewCookie> original = (await readCookies(forumUri))
      .where((WebViewCookie cookie) => cookie.name == forumWafCookieName)
      .map((WebViewCookie cookie) => _normalizeCookie(cookie, forumUri))
      .whereType<WebViewCookie>()
      .toList(growable: false);

  try {
    return await operation();
  } on Object catch (error, stackTrace) {
    for (final WebViewCookie cookie in original) {
      await writeCookie(cookie);
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

WebViewCookie? _normalizeCookie(WebViewCookie cookie, Uri forumUri) {
  final String rawDomain = cookie.domain.trim();
  final Uri? parsedDomain = Uri.tryParse(rawDomain);
  final String domain = (parsedDomain?.host.isNotEmpty ?? false)
      ? parsedDomain!.host
      : rawDomain.replaceFirst(RegExp(r'^\.'), '');
  if (domain.isEmpty ||
      (forumUri.host != domain && !forumUri.host.endsWith('.$domain'))) {
    return null;
  }
  return WebViewCookie(
    name: cookie.name,
    value: cookie.value,
    domain: domain,
    path: cookie.path.isEmpty ? '/' : cookie.path,
  );
}
