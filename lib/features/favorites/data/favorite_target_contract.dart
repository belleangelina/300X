import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';

class FavoriteTargetDescriptor {
  const FavoriteTargetDescriptor({
    required this.kind,
    required this.targetId,
    required this.uri,
    this.ownerUserId,
  });

  final RawFavoriteTargetKind kind;
  final int targetId;
  final int? ownerUserId;
  final Uri uri;
}

class FavoriteTargetContract {
  const FavoriteTargetContract([
    this._originPolicy = const ForumOriginPolicy(),
  ]);

  final ForumOriginPolicy _originPolicy;

  FavoriteTargetDescriptor? describe(Uri uri) {
    if (!_isSafeMobileUri(uri)) {
      return null;
    }
    if (uri.path == '/forum.php') {
      final String mod = _single(uri, 'mod');
      if (mod == 'viewthread' &&
          _hasOnly(uri, const <String>{'mod', 'tid', 'mobile'})) {
        return _positiveDescriptor(uri, RawFavoriteTargetKind.thread, 'tid');
      }
      if (mod == 'forumdisplay' &&
          _hasOnly(
            uri,
            uri.queryParameters.containsKey('action')
                ? const <String>{'mod', 'action', 'fid', 'mobile'}
                : const <String>{'mod', 'fid', 'mobile'},
          ) &&
          (!uri.queryParameters.containsKey('action') ||
              _single(uri, 'action') == 'list')) {
        return _positiveDescriptor(uri, RawFavoriteTargetKind.board, 'fid');
      }
      if (mod == 'group' &&
          _hasOnly(uri, const <String>{'mod', 'fid', 'mobile'})) {
        return _positiveDescriptor(
          uri,
          RawFavoriteTargetKind.groupBoard,
          'fid',
        );
      }
      return null;
    }
    if (uri.path == '/group.php' &&
        _hasOnly(uri, const <String>{'gid', 'mobile'})) {
      return _positiveDescriptor(
        uri,
        RawFavoriteTargetKind.groupCategory,
        'gid',
      );
    }
    if (uri.path != '/home.php' ||
        _single(uri, 'mod') != 'space' ||
        !_hasOnly(
          uri,
          uri.queryParameters.containsKey('do')
              ? const <String>{'mod', 'do', 'uid', 'id', 'mobile'}
              : const <String>{'mod', 'uid', 'mobile'},
        )) {
      return null;
    }
    final int? ownerUserId = _singlePositiveInteger(uri, 'uid');
    if (ownerUserId == null) {
      return null;
    }
    final String action = _single(uri, 'do');
    if (action.isEmpty) {
      return FavoriteTargetDescriptor(
        kind: RawFavoriteTargetKind.userSpace,
        targetId: ownerUserId,
        ownerUserId: ownerUserId,
        uri: uri,
      );
    }
    final int? contentId = _singlePositiveInteger(uri, 'id');
    if (contentId == null) {
      return null;
    }
    final RawFavoriteTargetKind? kind = switch (action) {
      'blog' => RawFavoriteTargetKind.blog,
      'album' => RawFavoriteTargetKind.album,
      _ => null,
    };
    if (kind == null) {
      return null;
    }
    return FavoriteTargetDescriptor(
      kind: kind,
      targetId: contentId,
      ownerUserId: ownerUserId,
      uri: uri,
    );
  }

  FavoriteTargetDescriptor requireItem(
    RawFavoriteItem item, {
    Set<RawFavoriteTargetKind>? allowedKinds,
  }) {
    final Uri? uri = item.targetUri;
    final FavoriteTargetDescriptor? descriptor = uri == null
        ? null
        : describe(uri);
    if (descriptor == null ||
        descriptor.kind != item.targetKind ||
        descriptor.targetId != item.targetId ||
        (descriptor.ownerUserId != null &&
            descriptor.ownerUserId != item.userId) ||
        (allowedKinds != null && !allowedKinds.contains(descriptor.kind))) {
      throw const ForumParseException('收藏目标地址与条目标识不一致');
    }
    return descriptor;
  }

  void requireGroupBoardResult(Uri uri, {required int expectedBoardId}) {
    _originPolicy.requireMobilePage(uri);
    if (uri.fragment.isNotEmpty ||
        uri.path != '/forum.php' ||
        _single(uri, 'mod') != 'forumdisplay' ||
        _single(uri, 'action') != 'list' ||
        _singlePositiveInteger(uri, 'fid') != expectedBoardId ||
        !_hasOnly(uri, const <String>{'mod', 'action', 'fid', 'mobile'})) {
      throw const ForumParseException('群组收藏没有跳转到对应移动版块');
    }
  }

  void requireGroupCategoryPage(Uri uri, {required int expectedGroupId}) {
    _originPolicy.requireMobilePage(uri);
    if (uri.fragment.isNotEmpty ||
        uri.path != '/group.php' ||
        _singlePositiveInteger(uri, 'gid') != expectedGroupId ||
        !_hasOnly(uri, const <String>{'gid', 'orderby', 'page', 'mobile'}) ||
        (uri.queryParameters.containsKey('page') &&
            _singlePositiveInteger(uri, 'page') == null) ||
        (uri.queryParameters.containsKey('orderby') &&
            _single(uri, 'orderby') != 'displayorder')) {
      throw const ForumParseException('群组分类分页地址无效');
    }
  }

  void requireContentPage(
    Uri uri, {
    required RawFavoriteTargetKind kind,
    required int expectedContentId,
    required int expectedOwnerUserId,
  }) {
    _originPolicy.requireMobilePage(uri);
    final FavoriteTargetDescriptor? descriptor = describe(uri);
    if (descriptor == null ||
        descriptor.kind != kind ||
        descriptor.targetId != expectedContentId ||
        descriptor.ownerUserId != expectedOwnerUserId) {
      throw const ForumParseException('收藏内容最终地址与目标不一致');
    }
  }

  Uri? resolveSupported(Uri pageUri, String? value) {
    final Uri? uri = _originPolicy.resolveMobile(pageUri, value);
    return uri != null && describe(uri) != null ? uri : null;
  }

  Uri? resolveGroupBoardLink(Uri pageUri, String? value) {
    final Uri? uri = _originPolicy.resolveMobile(pageUri, value);
    if (uri == null ||
        uri.path != '/forum.php' ||
        _single(uri, 'mod') != 'forumdisplay' ||
        _single(uri, 'action') != 'list' ||
        _singlePositiveInteger(uri, 'fid') == null ||
        !_hasOnly(uri, const <String>{'mod', 'action', 'fid', 'mobile'})) {
      return null;
    }
    return uri;
  }

  Uri? resolveGroupPagination(
    Uri pageUri,
    String? value, {
    required int expectedGroupId,
  }) {
    final Uri? uri = _originPolicy.resolveMobile(pageUri, value);
    if (uri == null) {
      return null;
    }
    try {
      requireGroupCategoryPage(uri, expectedGroupId: expectedGroupId);
    } on ForumException {
      return null;
    }
    return uri;
  }

  Uri? resolveAlbumImage(Uri pageUri, String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final Uri uri;
    try {
      uri = pageUri.resolve(value.trim());
    } on FormatException {
      return null;
    }
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    return uri;
  }

  Uri? resolveAlbumPhoto(
    Uri pageUri,
    String? value, {
    required int expectedOwnerUserId,
  }) {
    final Uri? uri = _originPolicy.resolveMobile(pageUri, value);
    if (uri == null ||
        uri.path != '/home.php' ||
        _single(uri, 'mod') != 'space' ||
        _single(uri, 'do') != 'album' ||
        _singlePositiveInteger(uri, 'uid') != expectedOwnerUserId ||
        _singlePositiveInteger(uri, 'picid') == null ||
        !_hasOnly(uri, const <String>{'mod', 'do', 'uid', 'picid', 'mobile'})) {
      return null;
    }
    return uri;
  }

  bool _isSafeMobileUri(Uri uri) {
    try {
      _originPolicy.requireMobilePage(uri);
    } on ForumException {
      return false;
    }
    return uri.fragment.isEmpty;
  }

  FavoriteTargetDescriptor? _positiveDescriptor(
    Uri uri,
    RawFavoriteTargetKind kind,
    String name,
  ) {
    final int? id = _singlePositiveInteger(uri, name);
    return id == null
        ? null
        : FavoriteTargetDescriptor(kind: kind, targetId: id, uri: uri);
  }

  bool _hasOnly(Uri uri, Set<String> allowed) {
    if (!_originPolicy.hasNoAliasedQueryParameters(uri, allowed)) {
      return false;
    }
    for (final MapEntry<String, List<String>> entry
        in uri.queryParametersAll.entries) {
      if (!allowed.contains(entry.key.toLowerCase()) ||
          entry.value.length != 1) {
        return false;
      }
    }
    return true;
  }

  String _single(Uri uri, String name) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single : '';
  }

  int? _singlePositiveInteger(Uri uri, String name) {
    final int? value = int.tryParse(_single(uri, name));
    return value != null && value > 0 ? value : null;
  }
}
