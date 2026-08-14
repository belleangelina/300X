import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_post_content_parser.dart';
import 'package:x300/features/forum/domain/forum_announcement_models.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';

class ForumAnnouncementParser {
  const ForumAnnouncementParser({
    this.originPolicy = const ForumOriginPolicy(),
    this.contentParser = const ForumPostContentParser(),
  });

  final ForumOriginPolicy originPolicy;
  final ForumPostContentParser contentParser;

  void requireAnnouncementUri(Uri uri, {required int expectedAnnouncementId}) {
    if (expectedAnnouncementId <= 0) {
      throw ArgumentError.value(
        expectedAnnouncementId,
        'expectedAnnouncementId',
      );
    }
    originPolicy.ensureAllowed(uri);
    final Set<String> keys = uri.queryParametersAll.keys.toSet();
    if (uri.path != '/forum.php' ||
        uri.fragment.isNotEmpty ||
        !_hasSingleParameter(uri, 'mod', 'announcement') ||
        !_hasSingleParameter(uri, 'id', expectedAnnouncementId.toString()) ||
        !_hasOptionalMobileMode(uri) ||
        keys.difference(const <String>{'mod', 'id', 'mobile'}).isNotEmpty) {
      throw const ForumParseException('论坛公告地址无效');
    }
  }

  ForumAnnouncement parse(
    String html,
    Uri pageUri, {
    required int expectedAnnouncementId,
  }) {
    requireAnnouncementUri(
      pageUri,
      expectedAnnouncementId: expectedAnnouncementId,
    );
    final dom.Document document = html_parser.parse(html);
    final dom.Element? body = document.body;
    if (document.querySelector('form#loginform') != null ||
        body?.classes.contains('pg_logging') == true ||
        body?.classes.contains('logging') == true) {
      throw const ForumSessionExpiredException();
    }
    if (body?.id != 'forum' ||
        body?.classes.contains('pg_announcement') != true) {
      throw const ForumParseException('论坛未返回公告移动页面');
    }
    final dom.Element? list = document.querySelector('.annlist');
    if (list == null) {
      throw const ForumParseException('公告移动模板结构已变更');
    }
    final List<dom.Element> boxes = document.querySelectorAll(
      '#ann_${expectedAnnouncementId}_box',
    );
    if (boxes.length != 1 || !_isDescendantOf(boxes.single, list)) {
      throw const ForumParseException('公告页未返回指定公告 id');
    }
    final dom.Element box = boxes.single;
    final dom.Element? row = _closest(box, 'li');
    final dom.Element? titleElement = row?.querySelector('h2');
    final dom.Element? metadataElement = row?.querySelector('h3');
    if (row == null || titleElement == null || metadataElement == null) {
      throw const ForumParseException('公告移动模板结构已变更');
    }
    final String title = normalizeForumText(titleElement.text);
    if (title.isEmpty) {
      throw const ForumParseException('公告页缺少标题');
    }
    final ForumPostContentParseResult content = contentParser.parse(
      box,
      pageUri,
    );
    return ForumAnnouncement(
      id: expectedAnnouncementId,
      title: title,
      metadataLabel: normalizeForumText(metadataElement.text),
      contentBlocks: content.blocks,
      messageHtml: content.blocks.isEmpty ? '' : content.sanitizedHtml,
      sourceUri: pageUri,
    );
  }

  bool _hasSingleParameter(Uri uri, String name, String expected) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 && values.single == expected;
  }

  bool _hasOptionalMobileMode(Uri uri) {
    final List<String> values =
        uri.queryParametersAll['mobile'] ?? const <String>[];
    return values.isEmpty || (values.length == 1 && values.single == '2');
  }

  bool _isDescendantOf(dom.Element element, dom.Element ancestor) {
    dom.Element? cursor = element.parent;
    while (cursor != null) {
      if (identical(cursor, ancestor)) {
        return true;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  dom.Element? _closest(dom.Element element, String tag) {
    dom.Element? cursor = element.parent;
    while (cursor != null) {
      if (cursor.localName == tag) {
        return cursor;
      }
      cursor = cursor.parent;
    }
    return null;
  }
}
