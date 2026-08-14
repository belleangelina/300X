import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_index_parser.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

void main() {
  const ForumIndexParser parser = ForumIndexParser();
  final Uri mobileUri = Uri.parse('https://bbs.yamibo.com/forum.php?mobile=2');
  final Uri apiUri = Uri.parse(
    'https://bbs.yamibo.com/api/mobile/index.php?'
    'version=4&module=forumindex',
  );

  test('以移动首页可见性和顺序约束 API 版块层级', () {
    final ForumBoardIndex index = parser.parse(
      mobileHtml: _mobileIndexHtml,
      mobileUri: mobileUri,
      apiJson: _apiIndexJson,
      apiUri: apiUri,
      expectedUserId: 471581,
    );

    expect(index.viewer.userId, 471581);
    expect(index.viewer.noticeCount, 5);
    expect(index.viewer.privateMessageCount, 1);
    expect(index.sections, hasLength(1));
    expect(index.sections.single.name, '阅读区');
    expect(
      index.sections.single.boards.map((ForumBoardNode board) => board.id),
      <int>[55, 30],
    );
    expect(index.boardById(49)?.parentId, 55);
    expect(index.boardById(77), isNull);
    expect(index.navigation.searchUri?.queryParameters['mobile'], '2');
    expect(index.navigation.favoritesUri?.queryParameters['mobile'], '2');
    expect(index.navigation.noticesUri?.queryParameters['do'], 'notice');
    expect(index.navigation.messagesUri?.queryParameters['do'], 'pm');
    expect(index.navigation.profileUri?.queryParameters['uid'], '471581');
  });

  test('API 缺少移动页可见版块时仍保留 HTML 返回的入口', () {
    final ForumBoardIndex index = parser.parse(
      mobileHtml: _mobileIndexHtml,
      mobileUri: mobileUri,
      apiJson: _apiIndexJson.replaceFirst(
        '{"fid":"30","name":"漫画区","threads":"20"},',
        '',
      ),
      apiUri: apiUri,
      expectedUserId: 471581,
    );

    expect(index.boardById(30)?.name, '漫画移动入口');
    expect(index.boardById(30)?.uri.queryParameters['mobile'], '2');
  });

  test('API 损坏时降级为移动 HTML 可见版块而不猜层级', () {
    final ForumBoardIndex index = parser.parse(
      mobileHtml: _mobileIndexHtml,
      mobileUri: mobileUri,
      apiJson: '{broken',
      apiUri: apiUri,
      expectedUserId: 471581,
    );

    expect(index.sections, isEmpty);
    expect(
      index.unsectionedBoards.map((ForumBoardNode value) => value.id),
      <int>[55, 49, 30],
    );
    expect(index.viewer.userId, 471581);
  });

  test('登录页、桌面回退和错误账号均显式失败', () {
    expect(
      () => parser.parse(
        mobileHtml:
            '<body class="pg_logging"><form id="loginform"></form></body>',
        mobileUri: mobileUri,
        apiJson: _apiIndexJson,
        apiUri: apiUri,
        expectedUserId: 471581,
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    expect(
      () => parser.parse(
        mobileHtml: _mobileIndexHtml,
        mobileUri: Uri.parse('https://bbs.yamibo.com/forum.php'),
        apiJson: _apiIndexJson,
        apiUri: apiUri,
        expectedUserId: 471581,
      ),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parse(
        mobileHtml: _mobileIndexHtml,
        mobileUri: mobileUri,
        apiJson: _apiIndexJson,
        apiUri: apiUri,
        expectedUserId: 7,
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
  });

  test('拒绝伪造、跨域或非 forumindex 的 API 响应地址', () {
    for (final Uri invalid in <Uri>[
      Uri.parse(
        'https://evil.example/api/mobile/index.php?'
        'version=4&module=forumindex',
      ),
      Uri.parse(
        'https://user@bbs.yamibo.com/api/mobile/index.php?'
        'version=4&module=forumindex',
      ),
      Uri.parse(
        'https://bbs.yamibo.com:444/api/mobile/index.php?'
        'version=4&module=forumindex',
      ),
      Uri.parse(
        'https://bbs.yamibo.com/api/mobile/index.php?'
        'version=4&module=viewthread',
      ),
    ]) {
      expect(
        () => parser.parse(
          mobileHtml: _mobileIndexHtml,
          mobileUri: mobileUri,
          apiJson: _apiIndexJson,
          apiUri: invalid,
          expectedUserId: 471581,
        ),
        throwsA(isA<ForumParseException>()),
        reason: invalid.toString(),
      );
    }
  });
}

const String _mobileIndexHtml = '''
<html>
<head><script>var discuz_uid = '471581';</script></head>
<body id="forum" class="pg_index">
  <a href="forum.php?mod=forumdisplay&amp;fid=55&amp;mobile=2">文学移动入口</a>
  <a href="forum.php?mod=forumdisplay&amp;fid=49&amp;mobile=2">小说移动入口</a>
  <a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画移动入口</a>
  <a href="search.php?mod=forum&amp;mobile=2">搜索</a>
  <a href="home.php?mod=space&amp;do=favorite&amp;mobile=2">收藏</a>
  <a href="home.php?mod=space&amp;do=notice&amp;mobile=2">通知</a>
  <a href="home.php?mod=space&amp;do=pm&amp;mobile=2">私信</a>
  <a href="home.php?mod=space&amp;do=profile&amp;uid=471581&amp;mobile=2">个人资料</a>
  <a href="https://evil.example/forum.php?mod=forumdisplay&amp;fid=77&amp;mobile=2">外站</a>
</body>
</html>
''';

const String _apiIndexJson = '''
{
  "Variables": {
    "member_uid": "471581",
    "member_username": "脱敏用户",
    "notice": {"newprompt": "2", "newmypost": 3, "newpm": "1"},
    "catlist": [
      {"fid": "1", "name": "阅读区", "forums": ["30", {"fid": "55"}]},
      {"fid": "2", "name": "隐藏区", "forums": ["77"]}
    ],
    "forumlist": [
      {"fid":"30","name":"漫画区","threads":"20"},
      {
        "fid":"55",
        "name":"文学区",
        "threads":"10",
        "sublist":[{"fid":"49","fup":"55","name":"轻小说","posts":"9"}]
      },
      {"fid":"77","name":"不可见版块"}
    ]
  }
}
''';
