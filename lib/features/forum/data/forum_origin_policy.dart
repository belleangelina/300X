import 'package:x300/core/network/forum_exceptions.dart';

class ForumActionSecurityException extends ForumException {
  const ForumActionSecurityException([super.message = '论坛操作地址不安全']);
}

class ForumOriginPolicy {
  const ForumOriginPolicy();

  static final Uri _origin = Uri.parse('https://bbs.yamibo.com/');

  bool isAllowed(Uri uri) {
    return uri.scheme == _origin.scheme &&
        uri.host == _origin.host &&
        uri.port == _origin.port &&
        uri.userInfo.isEmpty;
  }

  void ensureAllowed(Uri uri) {
    if (!isAllowed(uri)) {
      throw const ForumActionSecurityException();
    }
  }

  void requireMobilePage(Uri uri) {
    ensureAllowed(uri);
    if (!_hasMobileMode(uri)) {
      throw const ForumParseException('论坛未返回 mobile=2 移动页面');
    }
  }

  bool hasNoAliasedQueryParameters(Uri uri, Set<String> names) {
    for (final String key in uri.queryParametersAll.keys) {
      final String lower = key.toLowerCase();
      final int bracket = lower.indexOf('[');
      final String base = bracket < 0 ? lower : lower.substring(0, bracket);
      if (names.contains(base) && lower != base) {
        return false;
      }
    }
    return true;
  }

  Uri? resolveAllowed(Uri pageUri, String? value) {
    if (!isAllowed(pageUri) || value == null || value.trim().isEmpty) {
      return null;
    }
    final Uri uri;
    try {
      uri = pageUri.resolve(value.trim());
    } on FormatException {
      return null;
    }
    return isAllowed(uri) ? uri : null;
  }

  Uri? resolveMobile(Uri pageUri, String? value) {
    final Uri? uri = resolveAllowed(pageUri, value);
    return uri != null && _hasMobileMode(uri) ? uri : null;
  }

  bool _hasMobileMode(Uri uri) {
    final List<String> values =
        uri.queryParametersAll['mobile'] ?? const <String>[];
    return hasNoAliasedQueryParameters(uri, const <String>{'mobile'}) &&
        values.length == 1 &&
        values.single == '2';
  }
}
