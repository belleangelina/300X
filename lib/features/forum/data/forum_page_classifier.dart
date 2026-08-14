import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';

enum ForumMobilePageKind { forumIndex, board, topic }

class ForumPageClassification {
  const ForumPageClassification({required this.kind, required this.document});

  final ForumMobilePageKind kind;
  final dom.Document document;
}

class ForumPageClassifier {
  const ForumPageClassifier({this.originPolicy = const ForumOriginPolicy()});

  final ForumOriginPolicy originPolicy;

  ForumPageClassification classify(String html, Uri pageUri) {
    originPolicy.requireMobilePage(pageUri);
    final dom.Document document = html_parser.parse(html);
    _throwIfSessionExpired(document);

    final dom.Element? body = document.body;
    if (body == null) {
      throw const ForumParseException('论坛页面缺少 body');
    }
    if (body.id != 'forum') {
      if (body.id == 'nv_forum' ||
          document.querySelector('#hd, #nv, #wp') != null) {
        throw const ForumParseException('论坛返回了电脑版页面');
      }
      throw ForumParseException(_messageOrFallback(document, '无法识别论坛移动页面'));
    }

    if (body.classes.contains('pg_index')) {
      return ForumPageClassification(
        kind: ForumMobilePageKind.forumIndex,
        document: document,
      );
    }
    if (body.classes.contains('pg_forumdisplay')) {
      return ForumPageClassification(
        kind: ForumMobilePageKind.board,
        document: document,
      );
    }
    if (body.classes.contains('pg_viewthread')) {
      return ForumPageClassification(
        kind: ForumMobilePageKind.topic,
        document: document,
      );
    }
    throw ForumParseException(_messageOrFallback(document, '论坛移动模板已变更'));
  }

  dom.Document requireKind(
    String html,
    Uri pageUri,
    ForumMobilePageKind expected,
  ) {
    final ForumPageClassification classification = classify(html, pageUri);
    if (classification.kind != expected) {
      throw ForumParseException(
        '论坛返回了${_kindName(classification.kind)}，'
        '而不是${_kindName(expected)}',
      );
    }
    return classification.document;
  }

  void _throwIfSessionExpired(dom.Document document) {
    final dom.Element? body = document.body;
    if (document.querySelector('form#loginform') != null ||
        body?.classes.contains('pg_logging') == true ||
        body?.classes.contains('logging') == true) {
      throw const ForumSessionExpiredException();
    }
  }

  String _messageOrFallback(dom.Document document, String fallback) {
    final String message = normalizeForumText(
      document
              .querySelector('.jump_c p, #messagetext, .tip, .alert_info')
              ?.text ??
          '',
    );
    return message.isEmpty ? fallback : message;
  }

  String _kindName(ForumMobilePageKind kind) {
    return switch (kind) {
      ForumMobilePageKind.forumIndex => '论坛首页',
      ForumMobilePageKind.board => '版块页',
      ForumMobilePageKind.topic => '主题页',
    };
  }
}
