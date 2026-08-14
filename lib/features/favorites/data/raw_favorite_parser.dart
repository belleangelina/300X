import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/favorites/data/favorite_target_contract.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';

class RawFavoriteParser {
  const RawFavoriteParser([
    this._originPolicy = const ForumOriginPolicy(),
    this._targetContract = const FavoriteTargetContract(),
  ]);

  final ForumOriginPolicy _originPolicy;
  final FavoriteTargetContract _targetContract;

  RawFavoritePage parse(
    String html,
    Uri pageUri, {
    String? expectedCategoryKey,
  }) {
    final dom.Document document = html_parser.parse(html);
    _throwIfSessionExpired(document);
    _originPolicy.requireMobilePage(pageUri);
    if (pageUri.path != '/home.php' ||
        pageUri.queryParameters['mod'] != 'space' ||
        pageUri.queryParameters['do'] != 'favorite' ||
        document.body?.classes.contains('pg_space') != true) {
      throw ForumParseException(_messageOrFallback(document, '无法识别移动收藏页面'));
    }

    final List<RawFavoriteCategory> categories = _parseCategories(
      document,
      pageUri,
      expectedCategoryKey,
    );
    if (categories.isEmpty) {
      throw const ForumParseException('移动收藏页面缺少分类入口');
    }
    final String selectedCategoryKey =
        expectedCategoryKey ??
        categories
            .where((RawFavoriteCategory value) => value.selected)
            .map((RawFavoriteCategory value) => value.key)
            .firstOrNull ??
        categories.first.key;
    final List<dom.Element> rows = document.querySelectorAll('li.sclist');
    final List<RawFavoriteItem> items = rows
        .map((dom.Element row) => _parseItem(row, pageUri, selectedCategoryKey))
        .whereType<RawFavoriteItem>()
        .toList(growable: false);
    if (rows.isNotEmpty && items.isEmpty) {
      throw const ForumParseException('收藏列表结构无法识别');
    }
    if (rows.isEmpty && !_hasListOrEmptyState(document)) {
      throw const ForumParseException('收藏页面中没有可识别的列表');
    }

    final _RawFavoritePagination pagination = _parsePagination(
      document,
      pageUri,
      selectedCategoryKey,
    );
    return RawFavoritePage(
      categories: List<RawFavoriteCategory>.unmodifiable(categories),
      items: List<RawFavoriteItem>.unmodifiable(items),
      selectedCategoryKey: selectedCategoryKey,
      currentPage: pagination.currentPage,
      totalPages: pagination.totalPages,
      sourceUri: pageUri,
      previousPageUri: pagination.previousPageUri,
      nextPageUri: pagination.nextPageUri,
    );
  }

  List<RawFavoriteCategory> _parseCategories(
    dom.Document document,
    Uri pageUri,
    String? expectedCategoryKey,
  ) {
    final List<RawFavoriteCategory> result = <RawFavoriteCategory>[];
    final Set<String> seen = <String>{};
    for (final dom.Element anchor in document.querySelectorAll(
      'a[href*="do=favorite"][href*="type="]',
    )) {
      final Uri? uri = _originPolicy.resolveMobile(
        pageUri,
        anchor.attributes['href'],
      );
      if (uri == null ||
          !_isFavoritePageUri(uri) ||
          uri.queryParameters.containsKey('page') ||
          _hasPageAncestor(anchor)) {
        continue;
      }
      final String key = uri.queryParameters['type']?.trim() ?? '';
      final String label = normalizeForumText(anchor.text);
      if (key.isEmpty || label.isEmpty || !seen.add(key)) {
        continue;
      }
      final bool selected =
          expectedCategoryKey == key ||
          (expectedCategoryKey == null &&
              (_hasSelectedStyle(anchor) ||
                  pageUri.queryParameters['type'] == key));
      result.add(
        RawFavoriteCategory(
          key: key,
          label: label,
          uri: uri,
          selected: selected,
        ),
      );
    }
    return result;
  }

  RawFavoriteItem? _parseItem(
    dom.Element row,
    Uri pageUri,
    String categoryKey,
  ) {
    final dom.Element? deleteAnchor = row.querySelector(
      'a[href*="ac=favorite"][href*="op=delete"][href*="favid="]',
    );
    final Uri? deleteUri = _originPolicy.resolveAllowed(
      pageUri,
      deleteAnchor?.attributes['href'],
    );
    final int? favoriteId = deleteUri == null
        ? null
        : queryInt(deleteUri, 'favid');

    dom.Element? targetAnchor;
    for (final String selector in const <String>[
      'a[href*="mod=viewthread"][href*="tid="]',
      'a[href*="mod=forumdisplay"][href*="fid="]',
      'a[href*="do=blog"][href*="id="]',
      'a[href*="do=album"][href*="id="]',
      'a[href*="mod=group"]',
      'a[href*="group.php"][href*="gid="]',
      'h4 a[href]',
      'a[href]',
    ]) {
      for (final dom.Element candidate in row.querySelectorAll(selector)) {
        if (identical(candidate, deleteAnchor) ||
            normalizeForumText(candidate.text).isEmpty) {
          continue;
        }
        final Uri? candidateUri = _originPolicy.resolveMobile(
          pageUri,
          candidate.attributes['href'],
        );
        if (candidateUri == null ||
            candidateUri.queryParameters['op'] == 'delete' ||
            _targetContract.describe(candidateUri) == null) {
          continue;
        }
        targetAnchor = candidate;
        break;
      }
      if (targetAnchor != null) {
        break;
      }
    }

    final Uri? resolvedTargetUri = _originPolicy.resolveMobile(
      pageUri,
      targetAnchor?.attributes['href'],
    );
    final FavoriteTargetDescriptor? descriptor = resolvedTargetUri == null
        ? null
        : _targetContract.describe(resolvedTargetUri);
    final Uri? targetUri = descriptor?.uri;
    final String title = normalizeForumText(
      targetAnchor?.text ?? row.querySelector('h4, .title')?.text ?? '',
    );
    if (title.isEmpty) {
      return null;
    }
    final int? threadId = descriptor?.kind == RawFavoriteTargetKind.thread
        ? descriptor?.targetId
        : null;
    final int? boardId =
        descriptor?.kind == RawFavoriteTargetKind.board ||
            descriptor?.kind == RawFavoriteTargetKind.groupBoard
        ? descriptor?.targetId
        : null;
    final int? userId = descriptor?.ownerUserId;
    final int? groupId = descriptor?.kind == RawFavoriteTargetKind.groupCategory
        ? descriptor?.targetId
        : null;
    final int? contentId =
        descriptor?.kind == RawFavoriteTargetKind.blog ||
            descriptor?.kind == RawFavoriteTargetKind.album
        ? descriptor?.targetId
        : null;
    return RawFavoriteItem(
      favoriteId: favoriteId,
      categoryKey: categoryKey,
      title: title,
      description: normalizeForumText(row.querySelector('p, .xg1')?.text ?? ''),
      targetUri: targetUri,
      deleteDialogUri: deleteUri,
      targetKind: descriptor?.kind ?? RawFavoriteTargetKind.unknown,
      threadId: threadId,
      boardId: boardId,
      userId: userId,
      groupId: groupId,
      contentId: contentId,
    );
  }

  _RawFavoritePagination _parsePagination(
    dom.Document document,
    Uri pageUri,
    String categoryKey,
  ) {
    final dom.Element? pageElement = document.querySelector('.pg');
    if (pageElement == null) {
      return const _RawFavoritePagination(currentPage: 1, totalPages: 1);
    }
    final int currentPage =
        int.tryParse(
          pageElement
                  .querySelector('input[name="custompage"]')
                  ?.attributes['value'] ??
              '',
        ) ??
        int.tryParse(
          normalizeForumText(pageElement.querySelector('strong')?.text ?? ''),
        ) ??
        1;
    int totalPages = currentPage;
    final String title =
        pageElement.querySelector('label span')?.attributes['title'] ?? '';
    totalPages =
        int.tryParse(RegExp(r'(\d+)').firstMatch(title)?.group(1) ?? '') ??
        totalPages;
    return _RawFavoritePagination(
      currentPage: currentPage,
      totalPages: totalPages,
      previousPageUri: _paginationUri(
        pageElement.querySelector('a.prev[href]'),
        pageUri,
        categoryKey,
      ),
      nextPageUri: _paginationUri(
        pageElement.querySelector('a.nxt[href]'),
        pageUri,
        categoryKey,
      ),
    );
  }

  Uri? _paginationUri(dom.Element? anchor, Uri pageUri, String categoryKey) {
    final Uri? uri = _originPolicy.resolveMobile(
      pageUri,
      anchor?.attributes['href'],
    );
    if (uri == null ||
        !_isFavoritePageUri(uri) ||
        uri.queryParameters['type'] != categoryKey) {
      return null;
    }
    return uri;
  }

  bool _isFavoritePageUri(Uri uri) {
    return uri.path == '/home.php' &&
        uri.queryParameters['mod'] == 'space' &&
        uri.queryParameters['do'] == 'favorite';
  }

  bool _hasPageAncestor(dom.Element anchor) {
    dom.Element? current = anchor.parent;
    while (current != null) {
      if (current.classes.contains('pg')) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  bool _hasSelectedStyle(dom.Element anchor) {
    return anchor.classes.any(_selectedClass) ||
        (anchor.parent?.classes.any(_selectedClass) ?? false);
  }

  bool _selectedClass(String value) {
    return value == 'a' || value == 'current' || value == 'selected';
  }

  bool _hasListOrEmptyState(dom.Document document) {
    return document.querySelector('.findbox') != null ||
        document.querySelector('.threadlist_box h4, .emp, .empty') != null;
  }

  void _throwIfSessionExpired(dom.Document document) {
    if (document.querySelector('form#loginform') != null ||
        document.body?.classes.contains('pg_logging') == true) {
      throw const ForumSessionExpiredException();
    }
  }

  String _messageOrFallback(dom.Document document, String fallback) {
    final String message = normalizeForumText(
      document
              .querySelector('.jump_c p, #messagetext p, #messagetext, .tip')
              ?.text ??
          '',
    );
    return message.isEmpty ? fallback : message;
  }
}

class _RawFavoritePagination {
  const _RawFavoritePagination({
    required this.currentPage,
    required this.totalPages,
    this.previousPageUri,
    this.nextPageUri,
  });

  final int currentPage;
  final int totalPages;
  final Uri? previousPageUri;
  final Uri? nextPageUri;
}
