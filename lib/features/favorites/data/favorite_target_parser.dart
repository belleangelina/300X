import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/favorites/data/favorite_target_contract.dart';
import 'package:x300/features/favorites/domain/favorite_target_models.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/data/forum_post_content_parser.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';

class FavoriteTargetParser {
  const FavoriteTargetParser({
    this.contract = const FavoriteTargetContract(),
    this.contentParser = const ForumPostContentParser(),
  });

  final FavoriteTargetContract contract;
  final ForumPostContentParser contentParser;

  FavoriteGroupBoardTarget parseGroupBoardResult(
    String html,
    Uri pageUri, {
    required int expectedBoardId,
    required String fallbackTitle,
  }) {
    contract.requireGroupBoardResult(pageUri, expectedBoardId: expectedBoardId);
    final dom.Document document = html_parser.parse(html);
    _throwIfSessionExpired(document);
    if (document.body?.id != 'forum' ||
        document.body?.classes.contains('pg_forumdisplay') != true ||
        document.querySelector('.threadlist') == null) {
      throw const ForumParseException('群组收藏跳转结果不是移动版块页');
    }
    final String pageTitle = normalizeForumText(
      document.querySelector('.forumname, .forum_name, .header .name')?.text ??
          '',
    );
    return FavoriteGroupBoardTarget(
      sourceUri: pageUri,
      board: ForumBoardNode(
        id: expectedBoardId,
        name: pageTitle.isEmpty ? fallbackTitle : pageTitle,
        uri: pageUri,
      ),
    );
  }

  FavoriteGroupPage parseGroupPage(
    String html,
    Uri pageUri, {
    required int expectedGroupId,
    required String fallbackTitle,
  }) {
    contract.requireGroupCategoryPage(
      pageUri,
      expectedGroupId: expectedGroupId,
    );
    final dom.Document document = html_parser.parse(html);
    _throwIfSessionExpired(document);
    if (document.body?.id != 'group' ||
        document.body?.classes.contains('pg_index') != true) {
      throw const ForumParseException('无法识别移动群组分类页面');
    }
    final dom.Element? list = document.querySelector('.forumlist .sub-forum');
    if (list == null) {
      throw const ForumParseException('群组分类页缺少版块列表');
    }
    final List<dom.Element> rows = list.querySelectorAll('a.murl[href]');
    final List<ForumBoardNode> boards = <ForumBoardNode>[];
    final Set<int> seen = <int>{};
    for (final dom.Element anchor in rows) {
      final Uri? uri = contract.resolveGroupBoardLink(
        pageUri,
        anchor.attributes['href'],
      );
      final int? boardId = uri == null
          ? null
          : int.tryParse(uri.queryParameters['fid'] ?? '');
      final String title = normalizeForumText(
        anchor.querySelector('.mtit')?.text ?? '',
      );
      if (uri == null || boardId == null || boardId <= 0 || title.isEmpty) {
        throw const ForumParseException('群组分类包含无法验证的版块入口');
      }
      if (!seen.add(boardId)) {
        continue;
      }
      boards.add(
        ForumBoardNode(
          id: boardId,
          name: title,
          description: normalizeForumText(
            anchor.querySelector('.mtxt')?.text ?? '',
          ),
          uri: uri,
        ),
      );
    }
    if (rows.isNotEmpty && boards.isEmpty) {
      throw const ForumParseException('群组分类版块列表无法识别');
    }
    final dom.Element? nextAnchor = document.querySelector('.pg a.nxt[href]');
    final Uri? nextPageUri = nextAnchor == null
        ? null
        : contract.resolveGroupPagination(
            pageUri,
            nextAnchor.attributes['href'],
            expectedGroupId: expectedGroupId,
          );
    if (nextAnchor != null && nextPageUri == null) {
      throw const ForumParseException('群组分类下一页地址无效');
    }
    final int currentPage =
        int.tryParse(pageUri.queryParameters['page'] ?? '') ??
        int.tryParse(
          normalizeForumText(document.querySelector('.pg strong')?.text ?? ''),
        ) ??
        1;
    if (currentPage <= 0 ||
        (nextPageUri != null &&
            (int.tryParse(nextPageUri.queryParameters['page'] ?? '') ?? 0) <=
                currentPage)) {
      throw const ForumParseException('群组分类页码不一致');
    }
    return FavoriteGroupPage(
      groupId: expectedGroupId,
      title: fallbackTitle,
      boards: List<ForumBoardNode>.unmodifiable(boards),
      currentPage: currentPage,
      sourceUri: pageUri,
      nextPageUri: nextPageUri,
    );
  }

  FavoriteBlog parseBlog(
    String html,
    Uri pageUri, {
    required int expectedBlogId,
    required int expectedOwnerUserId,
  }) {
    contract.requireContentPage(
      pageUri,
      kind: RawFavoriteTargetKind.blog,
      expectedContentId: expectedBlogId,
      expectedOwnerUserId: expectedOwnerUserId,
    );
    final dom.Document document = html_parser.parse(html);
    _throwIfSessionExpired(document);
    final dom.Element? view = document.querySelector('.viewthread');
    final dom.Element? message = view?.querySelector('.plc .message');
    final List<dom.Element> targetForms =
        view?.querySelectorAll('form#quickcommentform_$expectedBlogId') ??
        const <dom.Element>[];
    if (document.body?.id != 'home' ||
        document.body?.classes.contains('pg_space') != true ||
        view == null ||
        message == null ||
        targetForms.length != 1) {
      throw const ForumParseException('无法识别移动日志页面或日志编号');
    }
    final String title = normalizeForumText(
      view.querySelector('.view_tit em, .view_tit')?.text ?? '',
    );
    if (title.isEmpty) {
      throw const ForumParseException('日志页面缺少标题');
    }
    final bool ownerMatched = view
        .querySelectorAll('.plc .avatar a[href], .plc .authi a[href]')
        .map(
          (dom.Element value) =>
              contract.resolveSupported(pageUri, value.attributes['href']),
        )
        .whereType<Uri>()
        .map(contract.describe)
        .whereType<FavoriteTargetDescriptor>()
        .any(
          (FavoriteTargetDescriptor value) =>
              value.kind == RawFavoriteTargetKind.userSpace &&
              value.targetId == expectedOwnerUserId,
        );
    if (!ownerMatched) {
      throw const ForumParseException('日志页面作者 uid 与目标不一致');
    }
    final ForumPostContentParseResult content = contentParser.parse(
      message,
      pageUri,
    );
    if (content.blocks.isEmpty && normalizeForumText(message.text).isNotEmpty) {
      throw const ForumParseException('日志正文结构无法识别');
    }

    final dom.Element? commentBox = view.querySelector('.doing_list_box');
    final dom.Element? commentList = commentBox?.children
        .where((dom.Element value) => value.localName == 'ul')
        .firstOrNull;
    if (commentBox == null || commentList == null) {
      throw const ForumParseException('日志页面缺少评论列表');
    }
    final List<dom.Element> commentRows = commentList.children;
    final List<FavoriteBlogComment> comments = <FavoriteBlogComment>[];
    for (final dom.Element row in commentRows) {
      final dom.Element? body = row.querySelector('.do_comment');
      if (row.localName != 'li' ||
          !row.classes.contains('doing_list_li') ||
          !row.classes.contains('list') ||
          row.querySelector('.threadlist_top .muser') == null ||
          body == null) {
        throw const ForumParseException('日志评论结构无法识别');
      }
      final ForumPostContentParseResult parsed = contentParser.parse(
        body,
        pageUri,
      );
      comments.add(
        FavoriteBlogComment(
          blocks: List<ForumPostContentBlock>.unmodifiable(parsed.blocks),
          author: normalizeForumText(
            row.querySelector('.threadlist_top .muser h3')?.text ?? '',
          ),
          timeLabel: normalizeForumText(
            row.querySelector('.threadlist_top .muser .mtime span')?.text ??
                row.querySelector('.threadlist_top .muser .mtime')?.text ??
                '',
          ),
        ),
      );
    }

    final List<FavoriteNativeLink> nativeLinks = <FavoriteNativeLink>[];
    final Set<String> seenLinks = <String>{};
    for (final dom.Element anchor in <dom.Element>[
      ...message.querySelectorAll('a[href]'),
      ...commentRows.expand(
        (dom.Element value) => value.querySelectorAll('a[href]'),
      ),
    ]) {
      final Uri? uri = contract.resolveSupported(
        pageUri,
        anchor.attributes['href'],
      );
      final FavoriteTargetDescriptor? descriptor = uri == null
          ? null
          : contract.describe(uri);
      final String label = normalizeForumText(anchor.text);
      if (descriptor == null ||
          !const <RawFavoriteTargetKind>{
            RawFavoriteTargetKind.thread,
            RawFavoriteTargetKind.board,
            RawFavoriteTargetKind.groupBoard,
            RawFavoriteTargetKind.groupCategory,
            RawFavoriteTargetKind.blog,
            RawFavoriteTargetKind.album,
          }.contains(descriptor.kind) ||
          label.isEmpty ||
          (descriptor.kind == RawFavoriteTargetKind.blog &&
              descriptor.targetId == expectedBlogId &&
              descriptor.ownerUserId == expectedOwnerUserId) ||
          !seenLinks.add(uri.toString())) {
        continue;
      }
      nativeLinks.add(
        FavoriteNativeLink(label: label, item: _linkItem(label, descriptor)),
      );
    }

    final List<Uri> externalImages = <Uri>[];
    final Set<Uri> seenImages = <Uri>{};
    for (final dom.Element image in message.querySelectorAll('img')) {
      final Uri? uri = contract.resolveAlbumImage(
        pageUri,
        image.attributes['data-original'] ??
            image.attributes['file'] ??
            image.attributes['zoomfile'] ??
            image.attributes['src'],
      );
      if (uri != null && uri.host != pageUri.host && seenImages.add(uri)) {
        externalImages.add(uri);
      }
    }

    return FavoriteBlog(
      blogId: expectedBlogId,
      ownerUserId: expectedOwnerUserId,
      title: title,
      metadata: normalizeForumText(
        view.querySelector('.plc .authi')?.text ?? '',
      ),
      contentBlocks: List<ForumPostContentBlock>.unmodifiable(content.blocks),
      comments: List<FavoriteBlogComment>.unmodifiable(comments),
      nativeLinks: List<FavoriteNativeLink>.unmodifiable(nativeLinks),
      externalImageUris: List<Uri>.unmodifiable(externalImages),
      sourceUri: pageUri,
    );
  }

  FavoriteAlbum parseAlbum(
    String html,
    Uri pageUri, {
    required int expectedAlbumId,
    required int expectedOwnerUserId,
  }) {
    contract.requireContentPage(
      pageUri,
      kind: RawFavoriteTargetKind.album,
      expectedContentId: expectedAlbumId,
      expectedOwnerUserId: expectedOwnerUserId,
    );
    final dom.Document document = html_parser.parse(html);
    _throwIfSessionExpired(document);
    final dom.Element? view = document.querySelector('.album_view');
    final dom.Element? top = view?.querySelector('.album_view_top');
    final dom.Element? list = view?.querySelector('.album_view_list');
    if (document.body?.id != 'home' ||
        document.body?.classes.contains('pg_space') != true ||
        view == null ||
        top == null ||
        list == null) {
      throw const ForumParseException('无法识别移动相册页面');
    }
    final String title = normalizeForumText(
      top.querySelector('.album_name .albumname')?.text ?? '',
    );
    if (title.isEmpty) {
      throw const ForumParseException('相册页面缺少名称');
    }
    final List<dom.Element> rows = list.querySelectorAll('.album_pic');
    final List<FavoriteAlbumImage> images = <FavoriteAlbumImage>[];
    final Set<Uri> seen = <Uri>{};
    for (final dom.Element row in rows) {
      final dom.Element? anchor = row.querySelector('a[href]');
      final dom.Element? image = anchor?.querySelector('img');
      final Uri? photoUri = contract.resolveAlbumPhoto(
        pageUri,
        anchor?.attributes['href'],
        expectedOwnerUserId: expectedOwnerUserId,
      );
      final Uri? imageUri = contract.resolveAlbumImage(
        pageUri,
        image?.attributes['data-original'] ??
            image?.attributes['file'] ??
            image?.attributes['zoomfile'] ??
            image?.attributes['src'],
      );
      if (photoUri == null || imageUri == null) {
        throw const ForumParseException('相册包含无法验证的图片入口');
      }
      if (!seen.add(photoUri)) {
        continue;
      }
      images.add(
        FavoriteAlbumImage(
          imageUri: imageUri,
          photoUri: photoUri,
          alt: normalizeForumText(
            image?.attributes['alt'] ?? image?.attributes['title'] ?? '',
          ),
        ),
      );
    }
    if (rows.isNotEmpty && images.isEmpty) {
      throw const ForumParseException('相册图片列表无法识别');
    }
    return FavoriteAlbum(
      albumId: expectedAlbumId,
      ownerUserId: expectedOwnerUserId,
      title: title,
      description: normalizeForumText(
        top.querySelector('.album_depict')?.text ?? '',
      ),
      images: List<FavoriteAlbumImage>.unmodifiable(images),
      sourceUri: pageUri,
    );
  }

  RawFavoriteItem _linkItem(String label, FavoriteTargetDescriptor descriptor) {
    return RawFavoriteItem(
      categoryKey: 'internal-link',
      title: label,
      targetKind: descriptor.kind,
      targetUri: descriptor.uri,
      threadId: descriptor.kind == RawFavoriteTargetKind.thread
          ? descriptor.targetId
          : null,
      boardId:
          descriptor.kind == RawFavoriteTargetKind.board ||
              descriptor.kind == RawFavoriteTargetKind.groupBoard
          ? descriptor.targetId
          : null,
      userId: descriptor.ownerUserId,
      groupId: descriptor.kind == RawFavoriteTargetKind.groupCategory
          ? descriptor.targetId
          : null,
      contentId:
          descriptor.kind == RawFavoriteTargetKind.blog ||
              descriptor.kind == RawFavoriteTargetKind.album
          ? descriptor.targetId
          : null,
    );
  }

  void _throwIfSessionExpired(dom.Document document) {
    if (document.querySelector('form#loginform') != null ||
        document.body?.classes.contains('pg_logging') == true) {
      throw const ForumSessionExpiredException();
    }
  }
}
