import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/favorites/data/raw_favorite_parser.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';

void main() {
  const RawFavoriteParser parser = RawFavoriteParser();
  final Uri pageUri = Uri.parse(
    'https://bbs.yamibo.com/home.php?'
    'mod=space&do=favorite&type=all&mobile=2',
  );

  test('动态读取服务端分类并保留异构收藏和未知项', () {
    final RawFavoritePage page = parser.parse(
      _favoriteFixture,
      pageUri,
      expectedCategoryKey: 'all',
    );

    expect(
      page.categories.map((RawFavoriteCategory value) => value.label),
      <String>['主题', '版块', '群组', '日志', '相册', '全部'],
    );
    expect(page.selectedCategoryKey, 'all');
    expect(page.items, hasLength(6));
    expect(page.items[0].targetKind, RawFavoriteTargetKind.thread);
    expect(page.items[0].threadId, 501);
    expect(page.items[0].favoriteId, 71);
    expect(page.items[1].targetKind, RawFavoriteTargetKind.board);
    expect(page.items[1].boardId, 30);
    expect(page.items[1].deleteDialogUri, isNull);
    expect(page.items[2].targetKind, RawFavoriteTargetKind.groupBoard);
    expect(page.items[2].boardId, 80);
    expect(page.items[3].userId, 7);
    expect(page.items[3].targetKind, RawFavoriteTargetKind.blog);
    expect(page.items[3].contentId, 91);
    expect(page.items[4].targetKind, RawFavoriteTargetKind.album);
    expect(page.items[4].contentId, 92);
    expect(page.items[5].targetKind, RawFavoriteTargetKind.unknown);
    expect(page.items[5].targetUri, isNull);
    expect(page.currentPage, 1);
    expect(page.totalPages, 3);
    expect(page.nextPageUri?.queryParameters['page'], '2');
  });

  test('分类不把携 type 的分页页码当成新类型', () {
    final RawFavoritePage page = parser.parse(
      _favoriteFixture.replaceFirst(
        '<strong>1</strong>',
        '<strong>1</strong>'
            '<a href="home.php?mod=space&amp;do=favorite&amp;type=all&amp;'
            'page=2&amp;mobile=2">2</a>',
      ),
      pageUri,
      expectedCategoryKey: 'all',
    );

    expect(
      page.categories.map((RawFavoriteCategory value) => value.label),
      isNot(contains('2')),
    );
    expect(page.nextPageUri?.queryParameters['page'], '2');
  });

  test('群组分类收藏识别 group.php 的 gid 移动目标', () {
    final RawFavoritePage page = parser.parse(
      _favoriteFixture.replaceFirst(
        'forum.php?mod=group&amp;fid=80&amp;mobile=2',
        'group.php?gid=8&amp;mobile=2',
      ),
      pageUri,
      expectedCategoryKey: 'all',
    );

    expect(page.items[2].targetKind, RawFavoriteTargetKind.groupCategory);
    expect(page.items[2].groupId, 8);
    expect(page.items[2].boardId, isNull);
  });

  test('用户空间收藏保留精确 uid 和移动资料地址', () {
    final RawFavoritePage page = parser.parse(
      _favoriteFixture.replaceFirst(
        '<h4>未来类型收藏</h4>\n      '
            '<a href="https://evil.example/item/1">外部目标</a>',
        '<h4><a href="home.php?mod=space&amp;uid=77&amp;mobile=2">'
            '用户收藏</a></h4>',
      ),
      pageUri,
      expectedCategoryKey: 'all',
    );

    expect(page.items.last.targetKind, RawFavoriteTargetKind.userSpace);
    expect(page.items.last.userId, 77);
    expect(page.items.last.targetUri?.queryParameters['uid'], '77');
  });

  test('登录失效、桌面回退与列表模板漂移显式失败', () {
    expect(
      () => parser.parse(
        '<body class="pg_logging"><form id="loginform"></form></body>',
        pageUri,
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    expect(
      () => parser.parse(
        _favoriteFixture,
        pageUri.replace(
          queryParameters: <String, String>{
            'mod': 'space',
            'do': 'favorite',
            'type': 'all',
          },
        ),
      ),
      throwsA(isA<ForumException>()),
    );
    expect(
      () => parser.parse(
        '''
                <body class="pg_space">
                  ${_categoriesHtml()}
                  <div class="findbox"><li class="sclist"><span></span></li></div>
                </body>
                ''',
        pageUri,
        expectedCategoryKey: 'all',
      ),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('分类、分页和目标 URI 拒绝跨域或缺少移动标识', () {
    final String html = _favoriteFixture
        .replaceFirst(
          'home.php?mod=space&amp;do=favorite&amp;type=forum&amp;mobile=2',
          'https://evil.example/home.php?mod=space&amp;do=favorite&amp;type=forum&amp;mobile=2',
        )
        .replaceFirst(
          'home.php?mod=space&amp;do=favorite&amp;type=all&amp;page=2&amp;mobile=2',
          'https://evil.example/home.php?mod=space&amp;do=favorite&amp;type=all&amp;page=2&amp;mobile=2',
        );

    final RawFavoritePage page = parser.parse(
      html,
      pageUri,
      expectedCategoryKey: 'all',
    );

    expect(
      page.categories.map((RawFavoriteCategory value) => value.key),
      isNot(contains('forum')),
    );
    expect(page.nextPageUri, isNull);
    expect(page.items.last.targetUri, isNull);
  });

  test('明确空态返回空列表而不是伪造入口', () {
    final RawFavoritePage page = parser.parse(
      '''
            <body id="home" class="pg_space">
              ${_categoriesHtml()}
              <div class="threadlist_box"><h4>暂无收藏</h4></div>
            </body>
            ''',
      pageUri,
      expectedCategoryKey: 'all',
    );

    expect(page.items, isEmpty);
    expect(page.categories, isNotEmpty);
  });
}

String _categoriesHtml() {
  return '''
      <nav>
        <a href="home.php?mod=space&amp;do=favorite&amp;type=thread&amp;mobile=2">主题</a>
        <a href="home.php?mod=space&amp;do=favorite&amp;type=forum&amp;mobile=2">版块</a>
        <a href="home.php?mod=space&amp;do=favorite&amp;type=group&amp;mobile=2">群组</a>
        <a href="home.php?mod=space&amp;do=favorite&amp;type=blog&amp;mobile=2">日志</a>
        <a href="home.php?mod=space&amp;do=favorite&amp;type=album&amp;mobile=2">相册</a>
        <a class="a" href="home.php?mod=space&amp;do=favorite&amp;type=all&amp;mobile=2">全部</a>
      </nav>
    ''';
}

final String _favoriteFixture =
    '''
<html>
<body id="home" class="pg_space">
  ${_categoriesHtml()}
  <div class="findbox"><ul>
    <li class="sclist">
      <a href="home.php?mod=spacecp&amp;ac=favorite&amp;op=delete&amp;favid=71&amp;mobile=2">删除</a>
      <h4><a href="forum.php?mod=viewthread&amp;tid=501&amp;mobile=2">主题收藏</a></h4>
      <p>主题摘要</p>
    </li>
    <li class="sclist">
      <h4><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">版块收藏</a></h4>
    </li>
    <li class="sclist">
      <h4><a href="forum.php?mod=group&amp;fid=80&amp;mobile=2">群组收藏</a></h4>
    </li>
    <li class="sclist">
      <h4><a href="home.php?mod=space&amp;uid=7&amp;do=blog&amp;id=91&amp;mobile=2">日志收藏</a></h4>
    </li>
    <li class="sclist">
      <h4><a href="home.php?mod=space&amp;uid=7&amp;do=album&amp;id=92&amp;mobile=2">相册收藏</a></h4>
    </li>
    <li class="sclist">
      <h4>未来类型收藏</h4>
      <a href="https://evil.example/item/1">外部目标</a>
    </li>
  </ul></div>
  <div class="pg">
    <strong>1</strong>
    <label><input name="custompage" value="1" /><span title="共 3 页"></span></label>
    <a class="nxt" href="home.php?mod=space&amp;do=favorite&amp;type=all&amp;page=2&amp;mobile=2">下一页</a>
  </div>
</body>
</html>
''';
