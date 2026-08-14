import 'dart:io';

import 'package:flutter/services.dart';

const String _forumCookieChannelName = 'com.yamibox300/forum_web_cookies';
const String _forumHost = 'bbs.yamibo.com';
const Set<String> _forumCookieDomains = <String>{
  'bbs.yamibo.com',
  'yamibo.com',
};
const String _wafCookieName = 'nox_jst_v1';

typedef ForumWebCookieMethodInvoker =
    Future<Object?> Function(String method, Object? arguments);

class ForumWebCookieBridge {
  ForumWebCookieBridge({ForumWebCookieMethodInvoker? invokeMethod})
    : _invokeMethod = invokeMethod ?? _invokePlatformMethod;

  static const MethodChannel _channel = MethodChannel(_forumCookieChannelName);

  final ForumWebCookieMethodInvoker _invokeMethod;

  Future<List<ForumWebCookieSnapshot>> readSnapshot(Uri uri) async {
    _requireForumUri(uri);
    final Object? result = await _invokeMethod('getCookies', <String, Object?>{
      'url': uri.toString(),
    });
    if (result is! List<Object?>) {
      throw const FormatException('WebView Cookie 桥返回了无效快照');
    }
    return result
        .map(ForumWebCookieSnapshot.fromPlatformMap)
        .toList(growable: false);
  }

  Future<List<Cookie>> getCookies(
    Uri uri, {
    List<Cookie> knownCookies = const <Cookie>[],
  }) async {
    return forumCookiesFromWebViewSnapshot(
      await readSnapshot(uri),
      forumUri: uri,
      knownCookies: knownCookies,
    );
  }

  Future<void> setCookie(Uri uri, Cookie cookie) async {
    _requireForumUri(uri);
    final Map<String, Object?> map = forumWebCookiePlatformMap(
      cookie,
      forumUri: uri,
    );
    await _invokeMethod('setCookie', <String, Object?>{
      'url': uri.toString(),
      'cookie': map,
    });
  }

  Future<void> clearCookies(Uri uri) async {
    _requireForumUri(uri);
    await _invokeMethod('clearCookies', <String, Object?>{
      'url': uri.toString(),
    });
  }

  static Future<Object?> _invokePlatformMethod(
    String method,
    Object? arguments,
  ) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }
}

class ForumWebCookieSnapshot {
  const ForumWebCookieSnapshot({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.secure,
    required this.httpOnly,
    required this.attributesComplete,
    this.expires,
    this.maxAge,
    this.sameSite,
  });

  factory ForumWebCookieSnapshot.fromPlatformMap(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('WebView Cookie 条目不是对象');
    }
    final String name = _requiredString(value, 'name');
    final String cookieValue = _requiredString(
      value,
      'value',
      allowEmpty: true,
    );
    final String domain = _requiredString(value, 'domain');
    final String path = _requiredString(value, 'path');
    final bool secure = _requiredBool(value, 'secure');
    final bool httpOnly = _requiredBool(value, 'httpOnly');
    final bool attributesComplete = _requiredBool(value, 'attributesComplete');
    final int? expiresMilliseconds = _optionalInt(
      value,
      'expiresEpochMilliseconds',
    );
    final int? maxAge = _optionalInt(value, 'maxAge');
    final SameSite? sameSite = _decodeSameSite(
      _optionalString(value, 'sameSite'),
    );
    Cookie(name, cookieValue);
    if (!_isValidCookieDomain(domain) || !_isValidCookiePath(path)) {
      throw const FormatException('WebView Cookie 作用域不安全');
    }
    return ForumWebCookieSnapshot(
      name: name,
      value: cookieValue,
      domain: domain,
      path: path,
      secure: secure,
      httpOnly: httpOnly,
      attributesComplete: attributesComplete,
      expires: expiresMilliseconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              expiresMilliseconds,
              isUtc: true,
            ),
      maxAge: maxAge,
      sameSite: sameSite,
    );
  }

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool httpOnly;
  final bool attributesComplete;
  final DateTime? expires;
  final int? maxAge;
  final SameSite? sameSite;
}

List<Cookie> forumCookiesFromWebViewSnapshot(
  List<ForumWebCookieSnapshot> webCookies, {
  required Uri forumUri,
  List<Cookie> knownCookies = const <Cookie>[],
}) {
  _requireForumUri(forumUri);
  final Map<String, int> incompleteCounts = <String, int>{};
  for (final ForumWebCookieSnapshot cookie in webCookies) {
    if (!cookie.attributesComplete) {
      final int count = (incompleteCounts[cookie.name] ?? 0) + 1;
      if (count > 1) {
        throw StateError('WebView Cookie 同名作用域无法安全判定');
      }
      incompleteCounts[cookie.name] = count;
    }
  }
  final Map<String, List<Cookie>> knownByName = <String, List<Cookie>>{};
  for (final Cookie cookie in knownCookies) {
    if (cookie.name == _wafCookieName) {
      continue;
    }
    knownByName.putIfAbsent(cookie.name, () => <Cookie>[]).add(cookie);
  }
  return webCookies
      .map((ForumWebCookieSnapshot value) {
        final Cookie? known = _matchKnownCookie(
          value,
          knownByName[value.name] ?? const <Cookie>[],
        );
        final bool isWafCookie = value.name == _wafCookieName;
        final bool complete = value.attributesComplete;
        final Cookie cookie = Cookie(value.name, value.value)
          ..domain = complete ? value.domain : known?.domain ?? forumUri.host
          ..path = complete ? value.path : known?.path ?? '/'
          ..secure = isWafCookie
              ? true
              : value.secure || known?.secure == true || known == null
          ..httpOnly = isWafCookie
              ? false
              : value.httpOnly || known?.httpOnly == true || known == null
          ..expires = complete ? value.expires : known?.expires
          ..maxAge = complete ? value.maxAge : known?.maxAge
          ..sameSite = complete
              ? value.sameSite ?? known?.sameSite
              : known?.sameSite ?? SameSite.strict;
        return cookie;
      })
      .toList(growable: false);
}

Map<String, Object?> forumWebCookiePlatformMap(
  Cookie cookie, {
  required Uri forumUri,
}) {
  _requireForumUri(forumUri);
  final String? domain = cookie.domain;
  if (domain != null && !_isValidCookieDomain(domain)) {
    throw const FormatException('Cookie Domain 不属于论坛');
  }
  final String path = cookie.path ?? '/';
  if (!_isValidCookiePath(path)) {
    throw const FormatException('Cookie Path 必须从根路径开始');
  }
  if (cookie.sameSite == SameSite.none && !cookie.secure) {
    throw const FormatException('SameSite=None Cookie 必须启用 Secure');
  }
  return <String, Object?>{
    'name': cookie.name,
    'value': cookie.value,
    'domain': domain,
    'path': path,
    'secure': cookie.secure,
    'httpOnly': cookie.httpOnly,
    'expiresEpochMilliseconds': cookie.expires?.toUtc().millisecondsSinceEpoch,
    'maxAge': cookie.maxAge,
    'sameSite': cookie.sameSite?.name,
  };
}

Cookie? _matchKnownCookie(
  ForumWebCookieSnapshot snapshot,
  List<Cookie> candidates,
) {
  if (candidates.isEmpty) {
    return null;
  }
  if (candidates.length == 1) {
    return candidates.single;
  }
  if (snapshot.attributesComplete) {
    final List<Cookie> exactScopes = candidates
        .where((Cookie cookie) {
          final String domain = (cookie.domain ?? _forumHost)
              .toLowerCase()
              .replaceFirst(RegExp(r'^\.'), '');
          final String snapshotDomain = snapshot.domain
              .toLowerCase()
              .replaceFirst(RegExp(r'^\.'), '');
          return domain == snapshotDomain &&
              (cookie.path ?? '/') == snapshot.path;
        })
        .toList(growable: false);
    if (exactScopes.length == 1) {
      return exactScopes.single;
    }
  }
  final List<Cookie> exactValues = candidates
      .where((Cookie cookie) => cookie.value == snapshot.value)
      .toList(growable: false);
  if (exactValues.length == 1) {
    return exactValues.single;
  }
  throw StateError('WebView Cookie 同名作用域无法安全判定');
}

void _requireForumUri(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host != _forumHost ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('WebView Cookie 桥仅允许论坛 HTTPS 来源');
  }
}

bool _isValidCookieDomain(String value) {
  if (value != value.trim()) {
    return false;
  }
  final String domain = value.trim().toLowerCase().replaceFirst(
    RegExp(r'^\.'),
    '',
  );
  return _forumCookieDomains.contains(domain);
}

bool _isValidCookiePath(String value) {
  return value.startsWith('/') &&
      value.codeUnits.every((int character) {
        return character >= 0x20 && character != 0x7f && character != 0x3b;
      });
}

String _requiredString(
  Map<Object?, Object?> value,
  String key, {
  bool allowEmpty = false,
}) {
  final Object? field = value[key];
  if (field is! String || (!allowEmpty && field.isEmpty)) {
    throw FormatException('WebView Cookie 缺少 $key');
  }
  return field;
}

String? _optionalString(Map<Object?, Object?> value, String key) {
  final Object? field = value[key];
  if (field == null) {
    return null;
  }
  if (field is! String || field.isEmpty) {
    throw FormatException('WebView Cookie 的 $key 无效');
  }
  return field;
}

bool _requiredBool(Map<Object?, Object?> value, String key) {
  final Object? field = value[key];
  if (field is! bool) {
    throw FormatException('WebView Cookie 缺少 $key');
  }
  return field;
}

int? _optionalInt(Map<Object?, Object?> value, String key) {
  final Object? field = value[key];
  if (field == null) {
    return null;
  }
  if (field is! int) {
    throw FormatException('WebView Cookie 的 $key 无效');
  }
  return field;
}

SameSite? _decodeSameSite(String? value) {
  return switch (value?.toLowerCase()) {
    null => null,
    'lax' => SameSite.lax,
    'strict' => SameSite.strict,
    'none' => SameSite.none,
    _ => throw const FormatException('WebView Cookie SameSite 无效'),
  };
}
