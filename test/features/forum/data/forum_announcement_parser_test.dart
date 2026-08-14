import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_announcement_parser.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

void main() {
  const ForumAnnouncementParser parser = ForumAnnouncementParser();
  final Uri pageUri = Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=announcement&id=7',
  );

  test('按真实移动模板精确选择公告并解析连续正文', () {
    final announcement = parser.parse(
      _announcementHtml(),
      pageUri,
      expectedAnnouncementId: 7,
    );

    expect(announcement.id, 7);
    expect(announcement.title, '维护公告');
    expect(announcement.metadataLabel, '管理员 · 2026-08-13');
    expect(announcement.contentBlocks, isNotEmpty);
    expect(
      announcement.contentBlocks
          .expand((ForumPostContentBlock value) => value.inlines)
          .whereType<ForumPostLinkInline>()
          .single
          .threadId,
      99,
    );
  });

  test('公告正文为空时保留标题和元数据', () {
    final announcement = parser.parse(
      _announcementHtml(body: ''),
      pageUri,
      expectedAnnouncementId: 7,
    );

    expect(announcement.title, '维护公告');
    expect(announcement.hasContent, isFalse);
  });

  test('模板漂移、重复内容盒和错 id 均失败', () {
    expect(
      () => parser.parse(
        _announcementHtml().replaceFirst('class="annlist"', 'class="other"'),
        pageUri,
        expectedAnnouncementId: 7,
      ),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parse(
        _announcementHtml().replaceFirst(
          '</ul>',
          '<li><h2>重复</h2><h3>时间</h3>'
              '<div id="ann_7_box"></div></li></ul>',
        ),
        pageUri,
        expectedAnnouncementId: 7,
      ),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parse(
        _announcementHtml(id: 8),
        pageUri,
        expectedAnnouncementId: 7,
      ),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parse(
        _announcementHtml(),
        pageUri.replace(
          queryParameters: <String, String>{'mod': 'announcement', 'id': '8'},
        ),
        expectedAnnouncementId: 7,
      ),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('公告地址可缺少 mobile=2，但拒绝外域、错模式和额外参数', () {
    expect(
      () => parser.requireAnnouncementUri(pageUri, expectedAnnouncementId: 7),
      returnsNormally,
    );
    expect(
      () => parser.requireAnnouncementUri(
        pageUri.replace(
          queryParameters: <String, String>{
            'mod': 'announcement',
            'id': '7',
            'mobile': '2',
          },
        ),
        expectedAnnouncementId: 7,
      ),
      returnsNormally,
    );
    for (final Uri invalid in <Uri>[
      Uri.parse('https://evil.example/forum.php?mod=announcement&id=7'),
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=announcement&id=7&mobile=1',
      ),
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=announcement&id=7&page=1',
      ),
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=announcement&mod=forumdisplay&id=7',
      ),
    ]) {
      expect(
        () => parser.requireAnnouncementUri(invalid, expectedAnnouncementId: 7),
        throwsA(isA<ForumException>()),
        reason: invalid.toString(),
      );
    }
  });

  test('登录页按会话失效处理', () {
    expect(
      () => parser.parse(
        '<body class="pg_logging"><form id="loginform"></form></body>',
        pageUri,
        expectedAnnouncementId: 7,
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
  });
}

String _announcementHtml({int id = 7, String? body}) {
  return '''
  <html>
    <body id="forum" class="pg_announcement">
      <div class="annlist"><ul>
        <li class="cl">
          <h2><a id="ann_$id" class="ann_more">维护公告</a></h2>
          <h3>管理员 · 2026-08-13</h3>
          <div id="ann_${id}_box" class="annlist_box">
            ${body ?? '''
              <p>第一段 <strong>重点</strong></p>
              <p><a href="forum.php?mod=viewthread&amp;tid=99&amp;mobile=2">相关主题</a></p>
            '''}
          </div>
        </li>
      </ul></div>
    </body>
  </html>
  ''';
}
