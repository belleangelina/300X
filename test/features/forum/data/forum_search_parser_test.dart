import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_search_parser.dart';
import 'package:x300/features/forum/domain/forum_search_models.dart';

void main() {
  const ForumThreadSearchParser parser = ForumThreadSearchParser();
  final Uri currentBoardUri = Uri.parse(
    'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=30&mobile=2',
  );

  test('从移动页动态读取 action、隐藏字段、关键字字段和可见范围', () {
    const String html = '''
            <html><head><meta name="viewport" content="width=device-width"></head>
            <body id="search" class="pg_forum">
                <form class="searchform" method="post" action="search.php?mod=forum">
                    <input type="hidden" name="formhash" value="secret-hash">
                    <input type="hidden" name="srhfid" value="30">
                    <input type="hidden" name="searchsubmit" value="yes">
                    <input type="search" name="keyword_from_page" value="旧词">
                    <select name="search_scope">
                        <option value="title">标题</option>
                        <option value="post" selected>正文</option>
                    </select>
                    <label><input type="checkbox" name="digest" value="1" checked>精华</label>
                </form>
            </body></html>
        ''';

    final ForumThreadSearchForm form = parser.parseForm(html, currentBoardUri);

    expect(
      form.actionUri,
      Uri.parse('https://bbs.yamibo.com/search.php?mod=forum'),
    );
    expect(form.keywordFieldName, 'keyword_from_page');
    expect(form.initialKeyword, '旧词');
    expect(form.hiddenFields['formhash'], <String>['secret-hash']);
    expect(form.hiddenFields['srhfid'], <String>['30']);
    expect(form.hiddenFields['searchsubmit'], <String>['yes']);
    expect(form.boardId, 30);
    expect(
      form.scopeOptions.map(
        (ForumThreadSearchScopeOption value) =>
            '${value.fieldName}:${value.value}:${value.selected}',
      ),
      <String>[
        'search_scope:title:false',
        'search_scope:post:true',
        'digest:1:true',
      ],
    );
    expect(form.selectedScopeLabels, <String>['正文', '精华']);
  });

  test('当前版块搜索必须保留页面返回的 srhfid', () {
    const String missingScope = '''
            <html><body id="search" class="pg_forum">
                <form method="post" action="search.php?mod=forum">
                    <input type="hidden" name="formhash" value="hash">
                    <input type="text" name="q">
                </form>
            </body></html>
        ''';

    expect(
      () => parser.parseForm(missingScope, currentBoardUri),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('全站搜索表单不能暗中收窄到某个版块', () {
    final Uri globalUri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
    );
    const String narrowed = '''
            <html><body id="search" class="pg_forum">
                <form method="post" action="search.php?mod=forum">
                    <input type="hidden" name="srhfid" value="30">
                    <input type="text" name="q">
                </form>
            </body></html>
        ''';

    expect(
      () => parser.parseForm(narrowed, globalUri),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('当前版块移动页使用 pg_curforum 和 curforum action', () {
    const String html = '''
            <html><head><meta name="viewport" content="width=device-width"></head>
            <body id="search" class="pg_curforum">
                <form class="searchform" method="post" action="search.php?mod=curforum&amp;srhfid=30">
                    <input type="hidden" name="formhash" value="secret-hash">
                    <input type="hidden" name="srhfid" value="30">
                    <input type="hidden" name="searchsubmit" value="yes">
                    <input type="search" name="srchtxt">
                </form>
            </body></html>
        ''';

    final ForumThreadSearchForm form = parser.parseForm(html, currentBoardUri);

    expect(
      form.actionUri,
      Uri.parse(
        'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=30',
      ),
    );
    expect(form.keywordFieldName, 'srchtxt');
    expect(form.boardId, 30);
    expect(form.hiddenFields['srhfid'], <String>['30']);
  });

  test('当前版块搜索拒绝错 fid 或缺少 srhfid 的 action', () {
    const String wrongFid = '''
            <html><body id="search" class="pg_curforum">
                <form method="post" action="search.php?mod=curforum&amp;srhfid=99">
                    <input type="hidden" name="srhfid" value="30">
                    <input type="search" name="srchtxt">
                </form>
            </body></html>
        ''';
    const String missingFid = '''
            <html><body id="search" class="pg_curforum">
                <form method="post" action="search.php?mod=curforum">
                    <input type="hidden" name="srhfid" value="30">
                    <input type="search" name="srchtxt">
                </form>
            </body></html>
        ''';

    expect(
      () => parser.parseForm(wrongFid, currentBoardUri),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parseForm(missingFid, currentBoardUri),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('拒绝外站 action 和电脑版搜索模板', () {
    const String externalAction = '''
            <html><body id="search" class="pg_forum">
                <form method="post" action="https://example.com/search.php?mod=forum">
                    <input type="text" name="q">
                </form>
            </body></html>
        ''';
    const String desktop = '''
            <html><body id="nv_search" class="pg_search">
                <form method="post" action="search.php?mod=forum">
                    <input type="text" name="q">
                </form>
            </body></html>
        ''';

    expect(
      () => parser.parseForm(externalAction, currentBoardUri),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parseForm(desktop, currentBoardUri),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('移动结果保留 fid、tid、pid 并精确复用服务端分页地址', () {
    final Uri resultUri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=forum&searchid=88&page=2&mobile=2',
    );
    final ForumThreadSearchPage page = parser.parseResults(
      _resultHtml(),
      resultUri,
      expectedKeyword: '百合',
      expectedBoardId: 30,
    );

    expect(page.keyword, '百合');
    expect(page.searchId, '88');
    expect(page.boardId, 30);
    expect(page.totalResults, 1);
    expect(page.hits, hasLength(1));
    expect(page.hits.single.threadId, 501);
    expect(page.hits.single.boardId, 30);
    expect(page.hits.single.postId, 9001);
    expect(page.hits.single.authorId, 7);
    expect(page.hits.single.authorUri?.queryParameters['uid'], '7');
    expect(page.hits.single.title, '测试 百合 主题');
    expect(page.hits.single.boardName, '漫画区');
    expect(page.hits.single.views, 12000);
    expect(page.hits.single.replies, 34);
    expect(page.cursor.currentPage, 2);
    expect(page.cursor.totalPages, 5);
    expect(page.cursor.previousPageUri?.queryParameters['page'], '1');
    expect(
      page.cursor.nextPageUri,
      Uri.parse(
        'https://bbs.yamibo.com/search.php?mod=forum&searchid=88&orderby=lastpost&page=3&mobile=2',
      ),
    );
  });

  test('结果范围冲突或分页不是移动同源地址时明确失败', () {
    final Uri resultUri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=forum&searchid=88&page=2&mobile=2',
    );
    expect(
      () => parser.parseResults(
        _resultHtml(),
        resultUri,
        expectedKeyword: '百合',
        expectedBoardId: 31,
      ),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parseResults(
        _resultHtml().replaceFirst('&amp;page=3&amp;mobile=2', '&amp;page=3'),
        resultUri,
        expectedKeyword: '百合',
        expectedBoardId: 30,
      ),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('只有明确的移动结果容器才能返回空结果', () {
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=forum&searchid=9&mobile=2',
    );
    const String empty = '''
            <html><body id="search" class="pg_forum">
                <form method="post" action="search.php?mod=forum">
                    <input type="hidden" name="srhfid" value="0">
                    <input type="text" name="q" value="没有">
                </form>
                <div class="threadlist_box">
                    <h2>结果：找到 “没有” 相关内容 0 个</h2>
                    <div class="threadlist"><ul></ul></div>
                </div>
            </body></html>
        ''';
    const String drifted = '''
            <html><body id="search" class="pg_forum">
                <div class="tip">模板发生变化</div>
            </body></html>
        ''';

    final ForumThreadSearchPage page = parser.parseResults(
      empty,
      uri,
      expectedKeyword: '没有',
    );
    expect(page.hits, isEmpty);
    expect(page.totalResults, 0);
    expect(
      () => parser.parseResults(drifted, uri, expectedKeyword: '没有'),
      throwsA(isA<ForumParseException>()),
    );
  });
}

String _resultHtml() {
  return '''
        <html><head><meta name="viewport" content="width=device-width"></head>
        <body id="search" class="pg_forum">
            <form class="searchform" method="post" action="search.php?mod=forum">
                <input type="hidden" name="formhash" value="result-hash">
                <input type="hidden" name="srhfid" value="30">
                <input type="text" name="srchtxt" value="百合">
            </form>
            <div class="threadlist_box">
                <h2>结果: 找到 “<span class="emfont">百合</span>” 相关内容 1 个</h2>
                <div class="threadlist"><ul>
                    <li class="list">
                        <div class="threadlist_top">
                            <a class="mimg"><img src="avatar/7.jpg"></a>
                            <div class="muser">
                                <a class="mmc" href="home.php?mod=space&amp;uid=7&amp;mobile=2">作者甲</a>
                                <span class="mtime">2026-8-12 10:00</span>
                            </div>
                        </div>
                        <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=501&amp;pid=9001&amp;mobile=2#pid9001">
                            <div class="threadlist_tit"><em>测试 <strong>百合</strong> 主题</em></div>
                        </a>
                        <a href="forum.php?mod=viewthread&amp;tid=501&amp;mobile=2">
                            <div class="threadlist_mes">结果摘要</div>
                        </a>
                        <div class="threadlist_foot"><ul>
                            <li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">#漫画区</a></li>
                            <li>1.2万</li><li>34</li>
                        </ul></div>
                    </li>
                </ul></div>
                <div class="pg">
                    <a class="prev" href="search.php?mod=forum&amp;searchid=88&amp;orderby=lastpost&amp;page=1&amp;mobile=2">上一页</a>
                    <strong>2</strong>
                    <label><input name="custompage" value="2"><span title="共 5 页">2 / 5</span></label>
                    <a class="last" href="search.php?mod=forum&amp;searchid=88&amp;orderby=lastpost&amp;page=5&amp;mobile=2">5</a>
                    <a class="nxt" href="search.php?mod=forum&amp;searchid=88&amp;orderby=lastpost&amp;page=3&amp;mobile=2">下一页</a>
                </div>
            </div>
        </body></html>
    ''';
}
