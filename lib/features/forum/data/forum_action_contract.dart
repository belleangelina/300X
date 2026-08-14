import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

class ForumActionContract {
  const ForumActionContract({this.originPolicy = const ForumOriginPolicy()});

  static const Set<ForumActionKind> verifiedKinds = <ForumActionKind>{
    ForumActionKind.newThread,
    ForumActionKind.reply,
    ForumActionKind.quoteReply,
    ForumActionKind.editPost,
    ForumActionKind.favoriteThread,
    ForumActionKind.removeFavorite,
    ForumActionKind.shareThread,
  };

  final ForumOriginPolicy originPolicy;

  bool isVerified(ForumActionKind kind) => verifiedKinds.contains(kind);

  void validateAccountUri(Uri uri, int expectedUserId) {
    if (expectedUserId <= 0) {
      throw const ForumSessionExpiredException();
    }
    for (final String name in const <String>['uid', 'spaceuid']) {
      final List<String> values =
          uri.queryParametersAll[name] ?? const <String>[];
      if (values.isNotEmpty &&
          (values.length != 1 ||
              int.tryParse(values.single) != expectedUserId)) {
        throw const ForumSessionExpiredException();
      }
    }
  }

  void validateAccountFields(
    Map<String, List<String>> fields,
    int expectedUserId,
  ) {
    if (expectedUserId <= 0) {
      throw const ForumSessionExpiredException();
    }
    for (final String name in const <String>['uid', 'spaceuid']) {
      final List<String> values = fields[name] ?? const <String>[];
      if (values.isNotEmpty &&
          (values.length != 1 || int.tryParse(values.single) != expectedUserId)) {
        throw const ForumSessionExpiredException();
      }
    }
  }

  void validateHiddenFields(
    ForumActionRequest request,
    Map<String, List<String>> fields,
  ) {
    final Set<String> expectedSubmit = _expectedSubmitNames(request.kind);
    for (final MapEntry<String, List<String>> entry in fields.entries) {
      final String rawName = entry.key.toLowerCase();
      final int bracket = rawName.indexOf('[');
      final String name =
          bracket < 0 ? rawName : rawName.substring(0, bracket);
      if (_reservedTransportFields.contains(name) && rawName != name) {
        throw ForumActionSecurityException(
          '论坛隐藏传输字段使用了数组别名：${entry.key}',
        );
      }
      if (const <String>{
        'mod',
        'action',
        'ac',
        'op',
        'type',
        'mobile',
      }.contains(name)) {
        throw ForumActionSecurityException(
          '论坛把路由字段重复放入隐藏载荷：${entry.key}',
        );
      }
      if (_allSubmitNames.contains(name) && !expectedSubmit.contains(name)) {
        throw ForumActionSecurityException(
          '论坛表单包含其他操作的提交标记：${entry.key}',
        );
      }
      if (_allSubmitNames.contains(name) &&
          (entry.value.length != 1 || entry.value.single.trim().isEmpty)) {
        throw ForumActionSecurityException(
          '论坛隐藏提交标记不唯一或为空：${entry.key}',
        );
      }
    }

    final ForumActionTarget target = request.target;
    _validateHiddenTarget(fields, 'fid', target.boardId);
    _validateHiddenTarget(fields, 'tid', target.threadId);
    _validateHiddenTarget(fields, 'pid', target.postId);
    if (request.kind == ForumActionKind.reply ||
        request.kind == ForumActionKind.quoteReply) {
      final int? replyPostId = request.kind == ForumActionKind.reply
          ? _positiveSingleInt(request.entryUri, 'reppost')
          : target.postId;
      _validateRequiredHiddenTarget(fields, 'reppid', replyPostId);
      _validateRequiredHiddenTarget(fields, 'reppost', replyPostId);
    }
    if (request.kind == ForumActionKind.editPost) {
      _validateRequiredHiddenTarget(fields, 'fid', target.boardId);
      _validateRequiredHiddenTarget(fields, 'tid', target.threadId);
      _validateRequiredHiddenTarget(fields, 'pid', target.postId);
      _validateRequiredHiddenEntryTarget(
        fields,
        'page',
        request.entryUri,
        'page',
      );
    }
    _validateHiddenTarget(fields, 'favid', target.favoriteId);
    _validateHiddenTarget(fields, 'id', switch (request.kind) {
      ForumActionKind.favoriteThread || ForumActionKind.shareThread =>
        target.threadId,
      ForumActionKind.favoriteBoard => target.boardId,
      _ => null,
    });

    final Set<String> permittedTargets = switch (request.kind) {
      ForumActionKind.newThread => const <String>{'fid'},
      ForumActionKind.reply || ForumActionKind.quoteReply =>
        const <String>{'reppid', 'reppost'},
      ForumActionKind.editPost => const <String>{'fid', 'tid', 'pid', 'page'},
      ForumActionKind.favoriteThread || ForumActionKind.shareThread =>
        const <String>{'id'},
      ForumActionKind.favoriteBoard => const <String>{'id'},
      ForumActionKind.removeFavorite => const <String>{'favid'},
      _ => const <String>{},
    };
    for (final String name in const <String>[
      'fid',
      'tid',
      'pid',
      'favid',
      'id',
      'reppid',
      'reppost',
      'repquote',
      'page',
    ]) {
      if (fields.containsKey(name) && !permittedTargets.contains(name)) {
        throw ForumActionSecurityException(
          '论坛表单包含与当前操作无关的目标字段：$name',
        );
      }
    }
  }

  void validateSubmitFields(
    ForumActionRequest request,
    Map<String, List<String>> fields,
  ) {
    final Set<String> expected = _expectedSubmitNames(request.kind);
    if (fields.isEmpty) {
      throw const ForumActionSecurityException('论坛表单缺少唯一提交控件');
    }
    for (final MapEntry<String, List<String>> entry in fields.entries) {
      if (!expected.contains(entry.key) ||
          entry.value.length != 1 ||
          entry.value.single.trim().isEmpty) {
        throw ForumActionSecurityException(
          '论坛提交控件与当前操作不一致：${entry.key}',
        );
      }
    }
    if ((request.kind == ForumActionKind.reply ||
            request.kind == ForumActionKind.quoteReply) &&
        !_isUniqueValue(fields, 'replysubmit', 'yes')) {
      throw const ForumActionSecurityException('论坛回复提交标记与移动契约不一致');
    }
    if (request.kind == ForumActionKind.editPost &&
        !_isUniqueValue(fields, 'editsubmit', 'yes')) {
      throw const ForumActionSecurityException('论坛编辑提交标记与移动契约不一致');
    }
  }

  void validateUserFieldNames(Iterable<String> names) {
    for (final String name in names) {
      final String lower = name.toLowerCase();
      final int bracket = lower.indexOf('[');
      final String normalized = bracket < 0
          ? lower
          : lower.substring(0, bracket);
      if (_reservedTransportFields.contains(normalized)) {
        throw ForumActionSecurityException('论坛把保留传输字段暴露为可编辑项：$name');
      }
    }
  }

  static const Set<String> _allSubmitNames = <String>{
    'topicsubmit',
    'replysubmit',
    'editsubmit',
    'pollsubmit',
    'commentsubmit',
    'ratesubmit',
    'reportsubmit',
    'favoritesubmit',
    'favoritesubmit_btn',
    'deletesubmit',
    'deletesubmitbtn',
    'sharesubmit',
    'sharesubmit_btn',
  };

  static const Set<String> _reservedTransportFields = <String>{
    'uid',
    'spaceuid',
    'fid',
    'tid',
    'pid',
    'id',
    'favid',
    'pmid',
    'touid',
    'repquote',
    'reppid',
    'reppost',
    'authorid',
    'fromuid',
    'formhash',
    'referer',
    'mod',
    'action',
    'ac',
    'op',
    'type',
    'mobile',
    'handlekey',
    'page',
  };

  Set<String> _expectedSubmitNames(ForumActionKind kind) {
    return switch (kind) {
      ForumActionKind.newThread => const <String>{'topicsubmit'},
      ForumActionKind.reply || ForumActionKind.quoteReply =>
        const <String>{'replysubmit'},
      ForumActionKind.editPost || ForumActionKind.deletePost =>
        const <String>{'editsubmit'},
      ForumActionKind.vote => const <String>{'pollsubmit'},
      ForumActionKind.comment => const <String>{'commentsubmit'},
      ForumActionKind.rate => const <String>{'ratesubmit'},
      ForumActionKind.report => const <String>{'reportsubmit'},
      ForumActionKind.favoriteThread || ForumActionKind.favoriteBoard =>
        const <String>{'favoritesubmit', 'favoritesubmit_btn'},
      ForumActionKind.removeFavorite =>
        const <String>{'deletesubmit', 'deletesubmitbtn'},
      ForumActionKind.shareThread =>
        const <String>{'sharesubmit', 'sharesubmit_btn'},
    };
  }

  void _validateHiddenTarget(
    Map<String, List<String>> fields,
    String name,
    int? expected,
  ) {
    final List<String> values = fields[name] ?? const <String>[];
    if (values.isEmpty) {
      return;
    }
    if (expected == null ||
        expected <= 0 ||
        values.length != 1 ||
        int.tryParse(values.single) != expected) {
      throw ForumActionSecurityException(
        '论坛隐藏目标字段与当前操作不一致：$name',
      );
    }
  }

  void _validateRequiredHiddenTarget(
    Map<String, List<String>> fields,
    String name,
    int? expected,
  ) {
    final List<String> values = fields[name] ?? const <String>[];
    if (expected == null ||
        expected <= 0 ||
        values.length != 1 ||
        int.tryParse(values.single) != expected) {
      throw ForumActionSecurityException(
        '论坛隐藏目标字段缺失或与当前操作不一致：$name',
      );
    }
  }

  void _validateRequiredHiddenEntryTarget(
    Map<String, List<String>> fields,
    String hiddenName,
    Uri entryUri,
    String entryName,
  ) {
    _validateRequiredHiddenTarget(
      fields,
      hiddenName,
      _positiveSingleInt(entryUri, entryName),
    );
  }

  void validateEntry(ForumActionRequest request, Uri uri) {
    if (!isVerified(request.kind)) {
      throw const ForumParseException('该操作尚未取得真实移动标准表单契约');
    }
    _requireMobileUri(uri);
    _requireExactQuery(uri, _entryQueryKeys(request.kind));
    if (!_matchesEntry(request, uri)) {
      throw const ForumActionSecurityException('论坛操作入口与目标不一致');
    }
  }

  void validateFormAction(
    ForumActionRequest request,
    Uri uri,
    Map<String, List<String>> hiddenFields,
  ) {
    _requireMobileUri(uri);
    _requireExactQuery(uri, _formActionQueryKeys(request.kind));
    if (!_matchesFormAction(request, uri, hiddenFields)) {
      throw const ForumActionSecurityException('论坛表单提交地址与目标不一致');
    }
  }

  void validateSubmissionFinal(ForumPreparedAction prepared, Uri uri) {
    validateAccountUri(uri, prepared.userId);
    try {
      validateFormAction(prepared.request, uri, prepared.form.hiddenFields);
      return;
    } on ForumActionSecurityException {
      try {
        validateReadbackUri(prepared.readback, uri);
        return;
      } on ForumActionSecurityException {
        try {
          _requireMobileUri(uri, allowFragment: true);
          _requireExactQuery(uri, _redirectQueryKeys(prepared.request.kind));
          if (_matchesActionRedirect(prepared.request, uri)) {
            return;
          }
        } on ForumException {
          // Preserve the more useful readback contract error below.
        }
        rethrow;
      }
    }
  }

  bool isVerifiedSuccessRedirect(ForumPreparedAction prepared, Uri uri) {
    try {
      _requireMobileUri(uri, allowFragment: true);
      _requireExactQuery(uri, _redirectQueryKeys(prepared.request.kind));
      validateAccountUri(uri, prepared.userId);
      return _matchesActionRedirect(prepared.request, uri);
    } on ForumException {
      return false;
    }
  }

  void validateReadbackUri(ForumReadbackDescriptor descriptor, Uri uri) {
    _requireMobileUri(uri, allowFragment: true);
    _requireExactQuery(uri, _readbackQueryKeys(descriptor.kind));
    if (!_matchesReadback(descriptor, uri)) {
      throw const ForumActionSecurityException('论坛回读地址与操作目标不一致');
    }
  }

  bool _matchesEntry(ForumActionRequest request, Uri uri) {
    final ForumActionTarget target = request.target;
    return switch (request.kind) {
      ForumActionKind.newThread =>
        _isForumAction(uri, 'post', 'newthread') &&
            _targetId(uri, const <String>['fid'], target.boardId),
      ForumActionKind.reply =>
        target.postId == null &&
            target.favoriteId == null &&
            _isForumAction(uri, 'post', 'reply') &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _targetId(uri, const <String>['fid'], target.boardId) &&
            _positiveSingleInt(uri, 'reppost') != null &&
            _positiveSingleInt(uri, 'reppost') ==
                _positiveSingleInt(request.entryUri, 'reppost') &&
            _samePositiveParameter(uri, request.entryUri, 'page') &&
            _hasNoParameters(uri, const <String>['repquote', 'extra']),
      ForumActionKind.quoteReply =>
        target.favoriteId == null &&
            _isForumAction(uri, 'post', 'reply') &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _targetId(uri, const <String>['fid'], target.boardId) &&
            _targetId(uri, const <String>['repquote'], target.postId) &&
            _hasNoParameters(uri, const <String>['reppost']) &&
            _samePositiveParameter(uri, request.entryUri, 'page') &&
            _pageExtraMatches(uri, uri),
      ForumActionKind.editPost =>
        _isForumAction(uri, 'post', 'edit') &&
            target.favoriteId == null &&
            _targetId(uri, const <String>['fid'], target.boardId) &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _targetId(uri, const <String>['pid'], target.postId) &&
            _samePositiveParameter(uri, request.entryUri, 'page'),
      ForumActionKind.deletePost =>
        _isForumAction(uri, 'post', 'edit') &&
            _targetId(uri, const <String>['fid'], target.boardId) &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _targetId(uri, const <String>['pid'], target.postId),
      ForumActionKind.vote =>
        _isForumAction(uri, 'viewthread', null) &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _optionalTargetId(uri, const <String>['fid'], target.boardId),
      ForumActionKind.comment =>
        _isForumAction(uri, 'misc', 'comment') &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _targetId(uri, const <String>['pid'], target.postId),
      ForumActionKind.rate =>
        _isForumAction(uri, 'misc', 'rate') &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _targetId(uri, const <String>['pid'], target.postId),
      ForumActionKind.report =>
        uri.path == '/misc.php' &&
            _single(uri, 'mod') == 'report' &&
            _single(uri, 'rtype') == 'post' &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _targetId(uri, const <String>['rid'], target.postId),
      ForumActionKind.favoriteThread =>
        _isSpaceControl(uri, 'favorite', type: 'thread') &&
            _targetId(uri, const <String>['id'], target.threadId),
      ForumActionKind.favoriteBoard =>
        _isSpaceControl(uri, 'favorite', type: 'forum') &&
            _targetId(uri, const <String>['id'], target.boardId),
      ForumActionKind.removeFavorite =>
        _isSpaceControl(uri, 'favorite') &&
            _single(uri, 'op') == 'delete' &&
            _optionalValue(uri, 'type', 'thread') &&
            _targetId(uri, const <String>['favid'], target.favoriteId),
      ForumActionKind.shareThread =>
        _isSpaceControl(uri, 'share', type: 'thread') &&
            _targetId(uri, const <String>['id'], target.threadId),
    };
  }

  bool _matchesFormAction(
    ForumActionRequest request,
    Uri uri,
    Map<String, List<String>> hidden,
  ) {
    final ForumActionTarget target = request.target;
    return switch (request.kind) {
      ForumActionKind.newThread =>
        _isForumAction(uri, 'post', 'newthread') &&
            _targetIdIn(uri, hidden, const <String>['fid'], target.boardId),
      ForumActionKind.reply =>
        _isForumAction(uri, 'post', 'reply') &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _targetId(uri, const <String>['fid'], target.boardId) &&
            _single(uri, 'replysubmit') == 'yes' &&
            _single(uri, 'extra') == '' &&
            _hiddenTargetMatchesEntry(hidden, 'reppid', request.entryUri, 'reppost') &&
            _hiddenTargetMatchesEntry(hidden, 'reppost', request.entryUri, 'reppost') &&
            _hasNoTargetIn(uri, hidden, const <String>['repquote']),
      ForumActionKind.quoteReply =>
        _isForumAction(uri, 'post', 'reply') &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _targetId(uri, const <String>['fid'], target.boardId) &&
            _single(uri, 'replysubmit') == 'yes' &&
            _pageExtraMatches(request.entryUri, uri) &&
            _hiddenTargetId(hidden, 'reppid', target.postId) &&
            _hiddenTargetId(hidden, 'reppost', target.postId) &&
            _hasNoTargetIn(uri, hidden, const <String>['repquote']),
      ForumActionKind.editPost =>
        _isForumAction(uri, 'post', 'edit') &&
            _single(uri, 'editsubmit') == 'yes' &&
            _single(uri, 'extra') == '' &&
            _hasExactQueryKeys(uri, const <String>{
              'mod',
              'action',
              'editsubmit',
              'extra',
              'mobile',
            }) &&
            _hiddenTargetId(hidden, 'fid', target.boardId) &&
            _hiddenTargetId(hidden, 'tid', target.threadId) &&
            _hiddenTargetId(hidden, 'pid', target.postId) &&
            _hiddenTargetMatchesEntry(hidden, 'page', request.entryUri, 'page'),
      ForumActionKind.deletePost =>
        _isForumAction(uri, 'post', 'edit') &&
            _targetIdIn(uri, hidden, const <String>['fid'], target.boardId) &&
            _targetIdIn(uri, hidden, const <String>['tid'], target.threadId) &&
            _targetIdIn(uri, hidden, const <String>['pid'], target.postId),
      ForumActionKind.vote =>
        (_isForumAction(uri, 'viewthread', null) ||
                _isForumAction(uri, 'misc', 'pollvote')) &&
            _targetIdIn(uri, hidden, const <String>['tid'], target.threadId),
      ForumActionKind.comment =>
        _isForumAction(uri, 'misc', 'comment') &&
            _targetIdIn(uri, hidden, const <String>['tid'], target.threadId) &&
            _targetIdIn(uri, hidden, const <String>['pid'], target.postId),
      ForumActionKind.rate =>
        _isForumAction(uri, 'misc', 'rate') &&
            _targetIdIn(uri, hidden, const <String>['tid'], target.threadId) &&
            _targetIdIn(uri, hidden, const <String>['pid'], target.postId),
      ForumActionKind.report =>
        uri.path == '/misc.php' &&
            _single(uri, 'mod') == 'report' &&
            _targetIdIn(uri, hidden, const <String>['tid'], target.threadId) &&
            _targetIdIn(uri, hidden, const <String>[
              'rid',
              'pid',
            ], target.postId),
      ForumActionKind.favoriteThread =>
        _isSpaceControl(uri, 'favorite', type: 'thread') &&
            _targetIdIn(uri, hidden, const <String>['id'], target.threadId),
      ForumActionKind.favoriteBoard =>
        _isSpaceControl(uri, 'favorite', type: 'forum') &&
            _targetIdIn(uri, hidden, const <String>['id'], target.boardId),
      ForumActionKind.removeFavorite =>
        _isSpaceControl(uri, 'favorite') &&
            _single(uri, 'op') == 'delete' &&
            _optionalValue(uri, 'type', 'thread') &&
            _targetIdIn(uri, hidden, const <String>[
              'favid',
            ], target.favoriteId),
      ForumActionKind.shareThread =>
        _isSpaceControl(uri, 'share', type: 'thread') &&
            _targetIdIn(uri, hidden, const <String>['id'], target.threadId),
    };
  }

  bool _matchesReadback(ForumReadbackDescriptor descriptor, Uri uri) {
    final ForumActionTarget target = descriptor.target;
    return switch (descriptor.kind) {
      ForumReadbackKind.boardThreads =>
        _isForumAction(uri, 'forumdisplay', null) &&
            _targetId(uri, const <String>['fid'], target.boardId),
      ForumReadbackKind.thread ||
      ForumReadbackKind.poll => _isThreadReadback(uri, target.threadId),
      ForumReadbackKind.post ||
      ForumReadbackKind.comments ||
      ForumReadbackKind.report => _isPostReadback(
        uri,
        target.threadId,
        target.postId,
      ),
      ForumReadbackKind.ratings =>
        _isForumAction(uri, 'misc', 'viewratings') &&
            _targetId(uri, const <String>['tid'], target.threadId) &&
            _targetId(uri, const <String>['pid'], target.postId),
      ForumReadbackKind.threadFavorites => _isFavoriteList(uri, 'thread'),
      ForumReadbackKind.boardFavorites => _isFavoriteList(uri, 'forum'),
      ForumReadbackKind.shares =>
        _isThreadReadback(uri, target.threadId) ||
            (uri.path == '/home.php' &&
                _single(uri, 'mod') == 'space' &&
                _single(uri, 'do') == 'share'),
    };
  }

  bool _matchesActionRedirect(ForumActionRequest request, Uri uri) {
    final ForumActionTarget target = request.target;
    return switch (request.kind) {
      ForumActionKind.newThread =>
        _isForumAction(uri, 'viewthread', null) &&
            _positiveTargetId(uri, const <String>['tid']) &&
            _optionalTargetId(uri, const <String>['fid'], target.boardId),
      ForumActionKind.favoriteThread ||
      ForumActionKind.shareThread => _isThreadReadback(uri, target.threadId),
      _ => false,
    };
  }

  bool _isThreadReadback(Uri uri, int? threadId) {
    return _isForumAction(uri, 'viewthread', null) &&
        _targetId(uri, const <String>['tid'], threadId);
  }

  bool _isPostReadback(Uri uri, int? threadId, int? postId) {
    if (_isThreadReadback(uri, threadId)) {
      return uri.fragment == 'pid$postId';
    }
    return _isForumAction(uri, 'redirect', null) &&
        _single(uri, 'goto') == 'findpost' &&
        _targetId(uri, const <String>['ptid', 'tid'], threadId) &&
        _targetId(uri, const <String>['pid'], postId);
  }

  bool _isFavoriteList(Uri uri, String type) {
    return uri.path == '/home.php' &&
        _single(uri, 'mod') == 'space' &&
        _single(uri, 'do') == 'favorite' &&
        _single(uri, 'type') == type;
  }

  bool _isForumAction(Uri uri, String mod, String? action) {
    return uri.path == '/forum.php' &&
        _single(uri, 'mod') == mod &&
        (action == null
            ? !uri.queryParametersAll.containsKey('action')
            : _single(uri, 'action') == action);
  }

  bool _isSpaceControl(Uri uri, String action, {String? type}) {
    return uri.path == '/home.php' &&
        _single(uri, 'mod') == 'spacecp' &&
        _single(uri, 'ac') == action &&
        (type == null || _single(uri, 'type') == type);
  }

  bool _optionalValue(Uri uri, String name, String expected) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    return values.isEmpty || (values.length == 1 && values.single == expected);
  }

  Set<String> _entryQueryKeys(ForumActionKind kind) {
    return switch (kind) {
      ForumActionKind.newThread => const <String>{
        'mod', 'action', 'fid', 'mobile',
      },
      ForumActionKind.favoriteThread || ForumActionKind.favoriteBoard =>
        const <String>{'mod', 'ac', 'type', 'id', 'uid', 'spaceuid', 'mobile'},
      ForumActionKind.removeFavorite => const <String>{
        'mod', 'ac', 'op', 'type', 'favid', 'uid', 'spaceuid', 'mobile',
      },
      ForumActionKind.shareThread => const <String>{
        'mod', 'ac', 'type', 'id', 'uid', 'spaceuid', 'mobile',
      },
      ForumActionKind.reply => const <String>{
        'mod', 'action', 'fid', 'tid', 'page', 'reppost', 'mobile',
      },
      ForumActionKind.quoteReply => const <String>{
        'mod', 'action', 'fid', 'tid', 'page', 'repquote', 'extra', 'mobile',
      },
      ForumActionKind.editPost => const <String>{
        'mod', 'action', 'fid', 'tid', 'pid', 'page', 'mobile',
      },
      ForumActionKind.deletePost => const <String>{
        'mod', 'action', 'fid', 'tid', 'pid', 'mobile',
      },
      ForumActionKind.vote => const <String>{'mod', 'tid', 'fid', 'mobile'},
      ForumActionKind.comment || ForumActionKind.rate => const <String>{
        'mod', 'action', 'tid', 'pid', 'mobile',
      },
      ForumActionKind.report => const <String>{
        'mod', 'rtype', 'rid', 'tid', 'mobile',
      },
    };
  }

  Set<String> _formActionQueryKeys(ForumActionKind kind) {
    return switch (kind) {
      ForumActionKind.newThread => const <String>{
        'mod', 'action', 'fid', 'topicsubmit', 'extra', 'uid', 'spaceuid',
        'mobile',
      },
      ForumActionKind.favoriteThread || ForumActionKind.favoriteBoard =>
        const <String>{'mod', 'ac', 'type', 'id', 'uid', 'spaceuid', 'mobile'},
      ForumActionKind.removeFavorite => const <String>{
        'mod', 'ac', 'op', 'type', 'favid', 'uid', 'spaceuid', 'mobile',
      },
      ForumActionKind.shareThread => const <String>{
        'mod', 'ac', 'type', 'id', 'uid', 'spaceuid', 'mobile',
      },
      ForumActionKind.reply || ForumActionKind.quoteReply => const <String>{
        'mod', 'action', 'fid', 'tid', 'replysubmit', 'extra', 'mobile',
      },
      ForumActionKind.editPost => const <String>{
        'mod', 'action', 'editsubmit', 'extra', 'mobile',
      },
      ForumActionKind.deletePost => const <String>{
        'mod', 'action', 'fid', 'tid', 'pid', 'editsubmit', 'extra', 'mobile',
      },
      ForumActionKind.vote => const <String>{
        'mod', 'action', 'fid', 'tid', 'pollsubmit', 'mobile',
      },
      ForumActionKind.comment || ForumActionKind.rate => const <String>{
        'mod', 'action', 'tid', 'pid', 'mobile',
      },
      ForumActionKind.report => const <String>{
        'mod', 'rtype', 'rid', 'tid', 'mobile',
      },
    };
  }

  Set<String> _readbackQueryKeys(ForumReadbackKind kind) {
    return switch (kind) {
      ForumReadbackKind.boardThreads => const <String>{
        'mod', 'fid', 'filter', 'orderby', 'typeid', 'digest', 'specialtype',
        'page', 'mobile',
      },
      ForumReadbackKind.thread || ForumReadbackKind.poll => const <String>{
        'mod', 'tid', 'page', 'authorid', 'ordertype', 'mobile',
      },
      ForumReadbackKind.post ||
      ForumReadbackKind.comments ||
      ForumReadbackKind.report => const <String>{
        'mod', 'goto', 'tid', 'ptid', 'pid', 'page', 'mobile',
      },
      ForumReadbackKind.ratings => const <String>{
        'mod', 'action', 'tid', 'pid', 'mobile',
      },
      ForumReadbackKind.threadFavorites ||
      ForumReadbackKind.boardFavorites => const <String>{
        'mod', 'do', 'view', 'type', 'uid', 'page', 'mobile',
      },
      ForumReadbackKind.shares => const <String>{
        'mod', 'do', 'view', 'type', 'uid', 'tid', 'page', 'mobile',
      },
    };
  }

  Set<String> _redirectQueryKeys(ForumActionKind kind) {
    return switch (kind) {
      ForumActionKind.newThread => const <String>{
        'mod', 'fid', 'tid', 'pid', 'mobile',
      },
      ForumActionKind.favoriteThread || ForumActionKind.shareThread =>
        const <String>{'mod', 'tid', 'page', 'mobile'},
      _ => const <String>{'mobile'},
    };
  }

  void _requireExactQuery(Uri uri, Set<String> allowed) {
    for (final MapEntry<String, List<String>> entry
        in uri.queryParametersAll.entries) {
      if (!allowed.contains(entry.key) || entry.value.length != 1) {
        throw const ForumActionSecurityException('论坛操作地址包含未登记或重复参数');
      }
    }
  }

  void _requireMobileUri(Uri uri, {bool allowFragment = false}) {
    originPolicy.ensureAllowed(uri);
    if (!originPolicy.hasNoAliasedQueryParameters(
      uri,
      <String>{..._reservedTransportFields, ..._allSubmitNames},
    )) {
      throw const ForumActionSecurityException('论坛操作地址包含保留参数数组别名');
    }
    if (!allowFragment && uri.fragment.isNotEmpty) {
      throw const ForumActionSecurityException('论坛操作地址不能包含片段');
    }
    final List<String> mobile =
        uri.queryParametersAll['mobile'] ?? const <String>[];
    if (mobile.length != 1 || mobile.single != '2') {
      throw const ForumActionSecurityException('论坛操作不是 mobile=2 页面');
    }
  }

  String? _single(Uri uri, String name) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single : null;
  }

  bool _targetId(Uri uri, List<String> names, int? expected) {
    if (expected == null || expected <= 0) {
      return false;
    }
    final List<String> values = <String>[
      for (final String name in names)
        ...uri.queryParametersAll[name] ?? const <String>[],
    ];
    return values.length == 1 && int.tryParse(values.single) == expected;
  }

  bool _positiveTargetId(Uri uri, List<String> names) {
    final List<String> values = <String>[
      for (final String name in names)
        ...uri.queryParametersAll[name] ?? const <String>[],
    ];
    final int? parsed = values.length == 1 ? int.tryParse(values.single) : null;
    return parsed != null && parsed > 0;
  }

  bool _optionalTargetId(Uri uri, List<String> names, int? expected) {
    final List<String> values = <String>[
      for (final String name in names)
        ...uri.queryParametersAll[name] ?? const <String>[],
    ];
    if (values.isEmpty) {
      return true;
    }
    return expected != null &&
        expected > 0 &&
        values.length == 1 &&
        int.tryParse(values.single) == expected;
  }

  bool _targetIdIn(
    Uri uri,
    Map<String, List<String>> hidden,
    List<String> names,
    int? expected,
  ) {
    if (expected == null || expected <= 0) {
      return false;
    }
    final List<String> values = <String>[
      for (final String name in names) ...<String>[
        ...uri.queryParametersAll[name] ?? const <String>[],
        ...hidden[name] ?? const <String>[],
      ],
    ];
    return values.isNotEmpty &&
        values.every((String value) => int.tryParse(value) == expected);
  }

  bool _hasNoParameters(Uri uri, List<String> names) {
    return names.every(
      (String name) =>
          (uri.queryParametersAll[name] ?? const <String>[]).isEmpty,
    );
  }

  bool _hasExactQueryKeys(Uri uri, Set<String> expected) {
    return uri.queryParametersAll.length == expected.length &&
        uri.queryParametersAll.keys.every(expected.contains);
  }

  bool _isUniqueValue(
    Map<String, List<String>> fields,
    String name,
    String expected,
  ) {
    final List<String> values = fields[name] ?? const <String>[];
    return values.length == 1 && values.single == expected;
  }

  bool _hasNoTargetIn(
    Uri uri,
    Map<String, List<String>> hidden,
    List<String> names,
  ) {
    return names.every(
      (String name) =>
          (uri.queryParametersAll[name] ?? const <String>[]).isEmpty &&
          (hidden[name] ?? const <String>[]).isEmpty,
    );
  }

  int? _positiveSingleInt(Uri uri, String name) {
    final int? value = int.tryParse(_single(uri, name) ?? '');
    return value != null && value > 0 ? value : null;
  }

  bool _samePositiveParameter(Uri left, Uri right, String name) {
    final int? value = _positiveSingleInt(left, name);
    return value != null && value == _positiveSingleInt(right, name);
  }

  bool _pageExtraMatches(Uri pageSource, Uri uri) {
    final int? page = _positiveSingleInt(pageSource, 'page');
    return page != null && _single(uri, 'extra') == 'page=$page';
  }

  bool _hiddenTargetId(
    Map<String, List<String>> hidden,
    String name,
    int? expected,
  ) {
    final List<String> values = hidden[name] ?? const <String>[];
    return expected != null &&
        expected > 0 &&
        values.length == 1 &&
        int.tryParse(values.single) == expected;
  }

  bool _hiddenTargetMatchesEntry(
    Map<String, List<String>> hidden,
    String hiddenName,
    Uri entryUri,
    String entryName,
  ) {
    return _hiddenTargetId(
      hidden,
      hiddenName,
      _positiveSingleInt(entryUri, entryName),
    );
  }
}
