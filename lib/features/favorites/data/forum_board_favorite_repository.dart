import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/favorites/data/raw_favorite_parser.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

final Provider<ForumBoardFavoriteRepository>
forumBoardFavoriteRepositoryProvider = Provider<ForumBoardFavoriteRepository>(
  (Ref ref) => ForumBoardFavoriteRepository(
    ref.watch(forumClientProvider),
    ref.watch(authControllerProvider).value?.userId ?? 0,
    ForumSubmissionTombstoneRepository(ref.watch(appDatabaseProvider)),
  ),
);

class ForumBoardFavoriteBlockedException extends ForumException {
  ForumBoardFavoriteBlockedException({
    required this.record,
    required this.boardId,
    required this.shouldBeFavorite,
    this.favoriteId,
  }) : super('版块收藏请求已经发出但结果尚未确认；请先回读收藏列表，勿重复操作');

  final SubmissionTombstoneRecord record;
  final int boardId;
  final int? favoriteId;
  final bool shouldBeFavorite;
}

class ForumBoardFavoriteRepository {
  ForumBoardFavoriteRepository(
    this._client,
    this._userId,
    this._tombstones, [
    this._rawParser = const RawFavoriteParser(),
    this._authParser = const AuthPageParser(),
    this._originPolicy = const ForumOriginPolicy(),
  ]);

  static final Uri listUri = ForumClient.baseUri.resolve(
    'home.php?mod=space&do=favorite&view=me&type=forum&mobile=2',
  );

  final ForumClient _client;
  final int _userId;
  final ForumSubmissionTombstoneRepository _tombstones;
  final RawFavoriteParser _rawParser;
  final AuthPageParser _authParser;
  final ForumOriginPolicy _originPolicy;

  Future<bool> add({
    required int boardId,
    required Uri entryUri,
    required Uri refererUri,
  }) {
    return _withAccount(() async {
      _requireAddUri(entryUri, boardId);
      _requireBoardReferer(refererUri, boardId);
      final List<RawFavoriteItem> before = await _loadAll();
      if (_containsBoard(before, boardId)) {
        await _resolveExisting(_addKey(boardId));
        return false;
      }
      await _throwIfBlocked(
        key: _addKey(boardId),
        boardId: boardId,
        shouldBeFavorite: true,
      );
      final String attemptId = await _claim(
        key: _addKey(boardId),
        boardId: boardId,
        shouldBeFavorite: true,
      );
      try {
        final Response<String> response = await _client.getText(
          entryUri,
          referer: refererUri.toString(),
        );
        _requireAddResult(
          entryUri,
          response.realUri,
          response.data ?? '',
          boardId,
        );
        final bool confirmed = _containsBoard(await _loadAll(), boardId);
        if (!confirmed) {
          throw const ForumParseException('论坛收藏列表尚未确认版块收藏结果');
        }
        await _tombstones.resolveTrustedOutcomeKey(
          userId: _userId,
          key: _addKey(boardId),
          attemptId: attemptId,
          deleteDraft: false,
        );
        return true;
      } on ForumSessionExpiredException {
        rethrow;
      } on Object {
        throw await _blocked(
          key: _addKey(boardId),
          boardId: boardId,
          shouldBeFavorite: true,
        );
      }
    });
  }

  Future<bool> remove(RawFavoriteItem item) {
    return _withAccount(() async {
      final int boardId = item.boardId ?? 0;
      final int favoriteId = item.favoriteId ?? 0;
      final Uri? entryUri = item.deleteDialogUri;
      if (item.targetKind != RawFavoriteTargetKind.board ||
          boardId <= 0 ||
          favoriteId <= 0 ||
          entryUri == null) {
        throw const ForumActionSecurityException('该收藏不是可取消的版块收藏');
      }
      _requireDeleteEntry(entryUri, favoriteId);
      final List<RawFavoriteItem> before = await _loadAll();
      final RawFavoriteItem? current = _itemByFavoriteId(before, favoriteId);
      if (current == null) {
        await _resolveExisting(_removeKey(boardId, favoriteId));
        return false;
      }
      if (current.targetKind != RawFavoriteTargetKind.board ||
          current.boardId != boardId ||
          current.deleteDialogUri != entryUri) {
        throw const ForumActionSecurityException('版块收藏记录已变化，请刷新后重试');
      }
      await _throwIfBlocked(
        key: _removeKey(boardId, favoriteId),
        boardId: boardId,
        favoriteId: favoriteId,
        shouldBeFavorite: false,
      );
      final Response<String> dialog = await _client.getText(
        entryUri,
        referer: listUri.toString(),
      );
      final _BoardFavoriteDeleteForm form = _parseDeleteForm(
        dialog.data ?? '',
        dialog.realUri,
        expectedEntryUri: entryUri,
        expectedFavoriteId: favoriteId,
      );
      final String attemptId = await _claim(
        key: _removeKey(boardId, favoriteId),
        boardId: boardId,
        favoriteId: favoriteId,
        shouldBeFavorite: false,
      );
      try {
        final Response<String> response = await _client.postForm(
          form.actionUri,
          fields: form.fields,
          referer: dialog.realUri.toString(),
        );
        _originPolicy.ensureAllowed(response.realUri);
        if ((response.data ?? '').isNotEmpty) {
          _requireIdentity(response.data ?? '');
        }
        final bool confirmed = _itemByFavoriteId(
              await _loadAll(),
              favoriteId,
            ) ==
            null;
        if (!confirmed) {
          throw const ForumParseException('论坛收藏列表尚未确认取消结果');
        }
        await _tombstones.resolveTrustedOutcomeKey(
          userId: _userId,
          key: _removeKey(boardId, favoriteId),
          attemptId: attemptId,
          deleteDraft: false,
        );
        return true;
      } on ForumSessionExpiredException {
        rethrow;
      } on Object {
        throw await _blocked(
          key: _removeKey(boardId, favoriteId),
          boardId: boardId,
          favoriteId: favoriteId,
          shouldBeFavorite: false,
        );
      }
    });
  }

  Future<bool> readback(ForumBoardFavoriteBlockedException blocked) {
    return _withAccount(() async {
      _requireBlockedOwner(blocked);
      final List<RawFavoriteItem> items = await _loadAll();
      final bool favorite = blocked.favoriteId == null
          ? _containsBoard(items, blocked.boardId)
          : _itemByFavoriteId(items, blocked.favoriteId!) != null;
      final bool confirmed = favorite == blocked.shouldBeFavorite;
      if (confirmed) {
        final SubmissionTombstoneRecord? current = await _tombstones.findKey(
          userId: _userId,
          key: blocked.record.key,
        );
        if (current != null && current.attemptId == blocked.record.attemptId) {
          await _tombstones.acknowledgeKey(current);
        }
      }
      return confirmed;
    });
  }

  Future<void> acknowledge(ForumBoardFavoriteBlockedException blocked) {
    return _withAccount(() async {
      _requireBlockedOwner(blocked);
      final SubmissionTombstoneRecord? current = await _tombstones.findKey(
        userId: _userId,
        key: blocked.record.key,
      );
      if (current == null) {
        return;
      }
      if (current.attemptId != blocked.record.attemptId ||
          !await _tombstones.acknowledgeKey(current)) {
        throw const ForumActionSecurityException('版块收藏封存记录已变化');
      }
    });
  }

  Future<void> reconcileVisibleAdditions(Iterable<RawFavoriteItem> items) {
    return _withAccount(() async {
      for (final RawFavoriteItem item in items) {
        final int boardId = item.targetKind == RawFavoriteTargetKind.board
            ? item.boardId ?? 0
            : 0;
        if (boardId > 0) {
          await _resolveExisting(_addKey(boardId));
        }
      }
    });
  }

  Future<List<RawFavoriteItem>> _loadAll() async {
    final List<RawFavoriteItem> items = <RawFavoriteItem>[];
    final Set<Uri> visited = <Uri>{};
    final Set<int> favoriteIds = <int>{};
    Uri? uri = listUri;
    int expectedPage = 1;
    int? totalPages;
    while (uri != null) {
      if (!visited.add(uri) || visited.length > 100) {
        throw const ForumParseException('版块收藏分页不完整，不能作为写入结果依据');
      }
      _requireListUri(uri, expectedPage: expectedPage);
      final Response<String> response = await _client.getText(uri);
      _requireListUri(response.realUri, expectedPage: expectedPage);
      _requireIdentity(response.data ?? '');
      final RawFavoritePage page = _rawParser.parse(
        response.data ?? '',
        response.realUri,
        expectedCategoryKey: 'forum',
      );
      totalPages ??= page.totalPages;
      if (page.currentPage != expectedPage ||
          page.totalPages != totalPages ||
          page.totalPages < page.currentPage ||
          (page.currentPage < page.totalPages) != (page.nextPageUri != null)) {
        throw const ForumParseException('版块收藏分页不完整，不能作为写入结果依据');
      }
      for (final RawFavoriteItem item in page.items) {
        final int? favoriteId = item.favoriteId;
        if (favoriteId == null || favoriteId <= 0 || !favoriteIds.add(favoriteId)) {
          throw const ForumParseException('版块收藏记录缺少唯一服务端编号');
        }
        if (item.targetKind != RawFavoriteTargetKind.board ||
            (item.boardId ?? 0) <= 0 ||
            item.deleteDialogUri == null) {
          throw const ForumParseException('版块收藏记录目标结构无法确认');
        }
        _requireDeleteEntry(item.deleteDialogUri!, favoriteId);
        items.add(item);
      }
      uri = page.nextPageUri;
      expectedPage++;
    }
    return List<RawFavoriteItem>.unmodifiable(items);
  }

  _BoardFavoriteDeleteForm _parseDeleteForm(
    String source,
    Uri pageUri, {
    required Uri expectedEntryUri,
    required int expectedFavoriteId,
  }) {
    _requireDeleteEntry(pageUri, expectedFavoriteId);
    if (pageUri != expectedEntryUri) {
      throw const ForumActionSecurityException('取消版块收藏确认页发生了目标重定向');
    }
    _requireIdentity(source);
    final Document document = html_parser.parse(source);
    if (document.body?.id != 'home' ||
        document.body?.classes.contains('pg_spacecp') != true) {
      throw const ForumParseException('无法识别取消版块收藏移动确认页');
    }
    final List<Element> forms = document.querySelectorAll(
      'form[id^="favoriteform_"]',
    );
    if (forms.length != 1 || forms.single.id != 'favoriteform_$expectedFavoriteId') {
      throw const ForumParseException('取消版块收藏页面缺少唯一目标表单');
    }
    final Element form = forms.single;
    if ((form.attributes['method'] ?? 'get').toLowerCase() != 'post') {
      throw const ForumParseException('取消版块收藏表单不是 POST');
    }
    final Uri actionUri;
    try {
      actionUri = pageUri.resolve(form.attributes['action']?.trim() ?? '');
    } on FormatException {
      throw const ForumActionSecurityException('取消版块收藏提交地址无效');
    }
    _requireDeleteAction(actionUri, expectedFavoriteId);

    const Set<String> expectedNames = <String>{
      'referer',
      'deletesubmit',
      'formhash',
      'deletesubmitbtn',
    };
    final Map<String, List<Element>> controls = <String, List<Element>>{};
    for (final Element control in form.querySelectorAll(
      'input[name], button[name], textarea[name], select[name]',
    )) {
      final String name = control.attributes['name']?.trim() ?? '';
      final String base = name.toLowerCase().split('[').first;
      if (name.isEmpty || base != name.toLowerCase() || !expectedNames.contains(name)) {
        throw const ForumActionSecurityException('取消版块收藏表单包含未登记字段');
      }
      controls.putIfAbsent(name, () => <Element>[]).add(control);
    }
    if (controls.keys.toSet().length != expectedNames.length ||
        !controls.keys.toSet().containsAll(expectedNames)) {
      throw const ForumParseException('取消版块收藏表单字段不完整');
    }
    final Map<String, Object> fields = <String, Object>{};
    for (final String name in expectedNames) {
      final List<Element> values = controls[name] ?? const <Element>[];
      if (values.length != 1) {
        throw const ForumActionSecurityException('取消版块收藏表单字段不唯一');
      }
      final Element control = values.single;
      final String type = control.attributes['type']?.toLowerCase() ?? '';
      final bool expectedShape = name == 'deletesubmitbtn'
          ? control.localName == 'input' && type == 'submit'
          : control.localName == 'input' && type == 'hidden';
      final String value = control.attributes['value'] ?? '';
      if (!expectedShape || value.trim().isEmpty) {
        throw const ForumParseException('取消版块收藏表单字段形状不一致');
      }
      fields[name] = value;
    }
    final Uri referer;
    try {
      referer = pageUri.resolve((fields['referer']! as String).trim());
    } on FormatException {
      throw const ForumActionSecurityException('取消版块收藏 referer 无效');
    }
    _requireFavoriteListReferer(referer);
    return _BoardFavoriteDeleteForm(actionUri, fields);
  }

  void _requireAddUri(Uri uri, int boardId) {
    _requireExactUri(
      uri,
      const <String>{'mod', 'ac', 'type', 'id', 'handlekey', 'mobile'},
    );
    final String handleKey = _single(uri, 'handlekey') ?? '';
    if (uri.path != '/home.php' ||
        _single(uri, 'mod') != 'spacecp' ||
        _single(uri, 'ac') != 'favorite' ||
        _single(uri, 'type') != 'forum' ||
        _positive(uri, 'id') != boardId ||
        handleKey.isEmpty ||
        _single(uri, 'mobile') != '2') {
      throw const ForumActionSecurityException('版块收藏入口与移动合同不一致');
    }
  }

  void _requireAddResult(
    Uri entry,
    Uri result,
    String source,
    int boardId,
  ) {
    _requireAddUri(result, boardId);
    if (_single(result, 'handlekey') != _single(entry, 'handlekey')) {
      throw const ForumActionSecurityException('版块收藏响应目标发生变化');
    }
    _requireIdentity(source);
    final Document document = html_parser.parse(source);
    if (document.body?.id != 'home' ||
        document.body?.classes.contains('pg_spacecp') != true) {
      throw const ForumParseException('无法识别版块收藏移动响应页');
    }
  }

  void _requireDeleteEntry(Uri uri, int favoriteId) {
    _requireExactUri(
      uri,
      const <String>{'mod', 'ac', 'op', 'favid', 'mobile'},
    );
    if (uri.path != '/home.php' ||
        _single(uri, 'mod') != 'spacecp' ||
        _single(uri, 'ac') != 'favorite' ||
        _single(uri, 'op') != 'delete' ||
        _positive(uri, 'favid') != favoriteId ||
        _single(uri, 'mobile') != '2') {
      throw const ForumActionSecurityException('取消版块收藏入口与移动合同不一致');
    }
  }

  void _requireDeleteAction(Uri uri, int favoriteId) {
    _requireExactUri(
      uri,
      const <String>{'mod', 'ac', 'op', 'favid', 'type', 'mobile'},
    );
    if (uri.path != '/home.php' ||
        _single(uri, 'mod') != 'spacecp' ||
        _single(uri, 'ac') != 'favorite' ||
        _single(uri, 'op') != 'delete' ||
        _positive(uri, 'favid') != favoriteId ||
        _single(uri, 'type') != 'forum' ||
        _single(uri, 'mobile') != '2') {
      throw const ForumActionSecurityException('取消版块收藏提交地址与合同不一致');
    }
  }

  void _requireListUri(Uri uri, {required int expectedPage}) {
    _requireExactUri(
      uri,
      const <String>{'mod', 'do', 'view', 'type', 'page', 'uid', 'mobile'},
    );
    final String? page = _single(uri, 'page');
    final String? uid = _single(uri, 'uid');
    if (uri.path != '/home.php' ||
        _single(uri, 'mod') != 'space' ||
        _single(uri, 'do') != 'favorite' ||
        _single(uri, 'view') != 'me' ||
        _single(uri, 'type') != 'forum' ||
        (expectedPage == 1
            ? page != null && page != '1'
            : int.tryParse(page ?? '') != expectedPage) ||
        (uid != null && int.tryParse(uid) != _userId) ||
        _single(uri, 'mobile') != '2') {
      throw const ForumActionSecurityException('版块收藏回读地址与合同不一致');
    }
  }

  void _requireFavoriteListReferer(Uri uri) {
    _requireExactUri(
      uri,
      const <String>{'mod', 'do', 'view', 'type', 'page', 'uid', 'mobile'},
    );
    final String? view = _single(uri, 'view');
    final String? page = _single(uri, 'page');
    if (uri.path != '/home.php' ||
        _single(uri, 'mod') != 'space' ||
        _single(uri, 'do') != 'favorite' ||
        (view != null && view != 'me') ||
        _single(uri, 'type') != 'forum' ||
        (page != null && (int.tryParse(page) ?? 0) <= 0) ||
        _positive(uri, 'uid') != _userId ||
        _single(uri, 'mobile') != '2') {
      throw const ForumActionSecurityException('取消版块收藏来源页与合同不一致');
    }
  }

  void _requireBoardReferer(Uri uri, int boardId) {
    _originPolicy.requireMobilePage(uri);
    if (uri.path != '/forum.php' ||
        _single(uri, 'mod') != 'forumdisplay' ||
        _positive(uri, 'fid') != boardId) {
      throw const ForumActionSecurityException('版块收藏来源页与目标版块不一致');
    }
  }

  void _requireExactUri(Uri uri, Set<String> allowed) {
    _originPolicy.ensureAllowed(uri);
    if (uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) {
      throw const ForumActionSecurityException('版块收藏地址包含不安全组成');
    }
    for (final MapEntry<String, List<String>> entry
        in uri.queryParametersAll.entries) {
      final String base = entry.key.toLowerCase().split('[').first;
      if (base != entry.key.toLowerCase() ||
          !allowed.contains(entry.key) ||
          entry.value.length != 1) {
        throw const ForumActionSecurityException('版块收藏地址包含未登记或重复参数');
      }
    }
  }

  String? _single(Uri uri, String name) {
    final List<String> values = uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single : null;
  }

  int? _positive(Uri uri, String name) {
    final int? value = int.tryParse(_single(uri, name) ?? '');
    return value != null && value > 0 ? value : null;
  }

  void _requireIdentity(String source) {
    if (_authParser.currentUserId(source) != _userId) {
      throw const ForumSessionExpiredException();
    }
  }

  RawFavoriteItem? _itemByFavoriteId(
    Iterable<RawFavoriteItem> items,
    int favoriteId,
  ) {
    for (final RawFavoriteItem item in items) {
      if (item.favoriteId == favoriteId) {
        return item;
      }
    }
    return null;
  }

  bool _containsBoard(Iterable<RawFavoriteItem> items, int boardId) {
    return items.any(
      (RawFavoriteItem item) =>
          item.targetKind == RawFavoriteTargetKind.board &&
          item.boardId == boardId,
    );
  }

  SubmissionTombstoneKey _addKey(int boardId) {
    return SubmissionTombstoneKey(
      action: ForumActionKind.favoriteBoard.name,
      boardId: boardId,
      draftContext: '',
    );
  }

  SubmissionTombstoneKey _removeKey(int boardId, int favoriteId) {
    return SubmissionTombstoneKey(
      action: ForumActionKind.removeFavorite.name,
      boardId: boardId,
      favoriteId: favoriteId,
      draftContext: '',
    );
  }

  Future<String> _claim({
    required SubmissionTombstoneKey key,
    required int boardId,
    required bool shouldBeFavorite,
    int? favoriteId,
  }) async {
    final String? attemptId = await _tombstones.claimAttemptedKey(
      userId: _userId,
      key: key,
      deleteDraft: false,
    );
    if (attemptId == null) {
      throw await _blocked(
        key: key,
        boardId: boardId,
        favoriteId: favoriteId,
        shouldBeFavorite: shouldBeFavorite,
      );
    }
    return attemptId;
  }

  Future<void> _throwIfBlocked({
    required SubmissionTombstoneKey key,
    required int boardId,
    required bool shouldBeFavorite,
    int? favoriteId,
  }) async {
    final SubmissionTombstoneRecord? record = await _tombstones.findKey(
      userId: _userId,
      key: key,
    );
    if (record != null) {
      throw ForumBoardFavoriteBlockedException(
        record: record,
        boardId: boardId,
        favoriteId: favoriteId,
        shouldBeFavorite: shouldBeFavorite,
      );
    }
  }

  Future<ForumBoardFavoriteBlockedException> _blocked({
    required SubmissionTombstoneKey key,
    required int boardId,
    required bool shouldBeFavorite,
    int? favoriteId,
  }) async {
    final SubmissionTombstoneRecord? record = await _tombstones.findKey(
      userId: _userId,
      key: key,
    );
    if (record == null) {
      throw const ForumActionSecurityException('版块收藏提交封存意外丢失');
    }
    return ForumBoardFavoriteBlockedException(
      record: record,
      boardId: boardId,
      favoriteId: favoriteId,
      shouldBeFavorite: shouldBeFavorite,
    );
  }

  Future<void> _resolveExisting(SubmissionTombstoneKey key) async {
    final SubmissionTombstoneRecord? record = await _tombstones.findKey(
      userId: _userId,
      key: key,
    );
    if (record != null) {
      await _tombstones.acknowledgeKey(record);
    }
  }

  void _requireBlockedOwner(ForumBoardFavoriteBlockedException blocked) {
    final SubmissionTombstoneKey key = blocked.record.key;
    if (blocked.record.userId != _userId ||
        blocked.record.status != ForumSubmissionTombstoneStatus.attempted ||
        blocked.boardId <= 0 ||
        key.boardId != blocked.boardId ||
        key.action !=
            (blocked.shouldBeFavorite
                ? ForumActionKind.favoriteBoard.name
                : ForumActionKind.removeFavorite.name) ||
        key.favoriteId != blocked.favoriteId ||
        key.threadId != null ||
        key.postId != null ||
        key.draftContext.isNotEmpty ||
        (blocked.shouldBeFavorite
            ? blocked.favoriteId != null
            : (blocked.favoriteId ?? 0) <= 0)) {
      throw const ForumActionSecurityException('版块收藏封存不属于当前操作');
    }
  }

  Future<T> _withAccount<T>(Future<T> Function() operation) {
    if (_userId <= 0) {
      throw const ForumSessionExpiredException();
    }
    return _client.withActiveAccount(_userId, operation);
  }
}

class _BoardFavoriteDeleteForm {
  const _BoardFavoriteDeleteForm(this.actionUri, this.fields);

  final Uri actionUri;
  final Map<String, Object> fields;
}
