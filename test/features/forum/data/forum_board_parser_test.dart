import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_board_parser.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

void main()
{
    const ForumBoardParser parser = ForumBoardParser();
    final Uri pageUri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&'
        'filter=lastpost&orderby=lastpost&page=2&mobile=2',
    );

    test('按移动页解析动态筛选、主题、分页和操作入口', ()
    {
        const String html = '''
            <html><head><meta name="viewport" content="width=device-width"></head>
            <body id="forum" class="pg_forumdisplay">
                <div class="header">
                    <h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">中文百合漫画区</a></h2>
                    <a href="search.php?mod=curforum&amp;srhfid=30&amp;mobile=2">搜索</a>
                </div>
                <div id="dhnavs_li"><ul class="swiper-wrapper">
                    <li><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">全部</a></li>
                    <li class="a"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=lastpost&amp;orderby=lastpost&amp;mobile=2">最新</a></li>
                    <li><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=heat&amp;orderby=heats&amp;mobile=2">热门</a></li>
                    <li><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=digest&amp;digest=1&amp;mobile=2">精华</a></li>
                    <li><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=typeid&amp;typeid=65&amp;mobile=2">汉化</a></li>
                </ul></div>
                <a href="forum.php?mod=post&amp;action=newthread&amp;fid=30&amp;mobile=2">发帖</a>
                <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=forum&amp;id=30&amp;handlekey=opaque-board-control&amp;mobile=2">收藏</a>
                <div class="threadlist"><ul>
                    <li class="list_top">
                        <a href="forum.php?mod=announcement&amp;id=7&amp;fid=30&amp;page=1"><em>全站公告</em></a>
                    </li>
                    <li class="list_top">
                        <a href="forum.php?mod=viewthread&amp;tid=99&amp;mobile=2"><em>版规公告</em></a>
                    </li>
                    <li class="list">
                        <div class="threadlist_top cl">
                            <a class="mimg"><img src="https://bbs.yamibo.com/avatar/example.jpg"></a>
                            <div class="muser"><a class="mmc" href="home.php?mod=space&amp;do=profile&amp;uid=88&amp;mobile=2">译者甲</a><span class="mtime">2026-8-12 20:00</span></div>
                        </div>
                        <a href="forum.php?mod=viewthread&amp;tid=123&amp;mobile=2">
                            <div class="threadlist_tit"><span class="digest">精华</span><em>作品 第12话</em></div>
                        </a>
                        <div class="threadlist_mes">章节摘要</div>
                        <div class="threadlist_foot"><ul>
                            <li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=typeid&amp;typeid=65&amp;mobile=2">汉化</a></li>
                            <li>1.2万</li><li>34</li>
                        </ul></div>
                    </li>
                    <li class="list">
                        <a href="forum.php?mod=viewthread&amp;tid=124&amp;mobile=2">
                            <div class="threadlist_tit"><span class="locked" title="已关闭"></span><span class="poll" title="投票"></span><em>投票主题</em></div>
                        </a>
                        <div class="threadlist_foot"><ul><li>9</li><li>2</li></ul></div>
                    </li>
                </ul></div>
                <div class="pg">
                    <a class="prev" href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=lastpost&amp;orderby=lastpost&amp;page=1&amp;mobile=2">上一页</a>
                    <strong>2</strong>
                    <label><input name="custompage" value="2"><span title="共 5 页">2 / 5</span></label>
                    <a class="last" href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=lastpost&amp;orderby=lastpost&amp;page=5&amp;mobile=2">5</a>
                    <a class="nxt" href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=lastpost&amp;orderby=lastpost&amp;page=3&amp;mobile=2">下一页</a>
                </div>
            </body></html>
        ''';

        final ForumBoardPage page = parser.parse(
            html,
            pageUri,
            expectedBoardId: 30,
        );

        expect(page.board.id, 30);
        expect(page.board.name, '中文百合漫画区');
        expect(page.filters.map((ForumRouteOption value) => value.label),
            <String>['全部', '最新', '热门', '精华', '汉化']);
        expect(
            page.filters.singleWhere(
                (ForumRouteOption value) => value.label == '最新',
            ).selected,
            isTrue,
        );
        expect(page.threads, hasLength(4));
        expect(page.threads[0].pinned, isTrue);
        expect(page.threads[0].targetKind, ForumThreadTargetKind.announcement);
        expect(page.threads[0].id, 7);
        expect(page.threads[0].threadId, isNull);
        expect(page.threads[0].uri.queryParameters['mod'], 'announcement');
        expect(page.threads[0].uri.queryParameters['id'], '7');
        expect(page.threads[0].uri.queryParameters['mobile'], '2');
        expect(
            page.threads[0].uri.queryParameters.keys.toSet(),
            <String>{'mod', 'id', 'mobile'},
        );
        expect(page.threads[1].targetKind, ForumThreadTargetKind.thread);
        expect(page.threads[1].threadId, 99);
        expect(page.threads[2].id, 123);
        expect(page.threads[2].digest, isTrue);
        expect(page.threads[2].authorId, 88);
        expect(page.threads[2].authorUri?.queryParameters['uid'], '88');
        expect(page.threads[2].views, 12000);
        expect(page.threads[2].replies, 34);
        expect(page.threads[3].closed, isTrue);
        expect(page.threads[3].special, isTrue);
        expect(page.cursor.currentPage, 2);
        expect(page.cursor.totalPages, 5);
        expect(page.cursor.previousPageUri?.queryParameters['page'], '1');
        expect(page.cursor.nextPageUri?.queryParameters['page'], '3');
        expect(page.newThreadUri?.queryParameters['action'], 'newthread');
        expect(page.favoriteUri?.queryParameters['type'], 'forum');
        expect(
            page.favoriteUri?.queryParameters['handlekey'],
            'opaque-board-control',
        );
        expect(page.searchUri?.queryParameters['srhfid'], '30');
    });

    test('主题作者资料只接受精确移动资料页', ()
    {
        const String html = '''
            <html><body id="forum" class="pg_forumdisplay">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <div class="threadlist"><ul>
                    <li class="list">
                        <div class="threadlist_top"><div class="muser">
                            <a class="mmc" href="home.php?mod=space&amp;uid=7&amp;action=delete&amp;mobile=2">作者</a>
                        </div></div>
                        <a href="forum.php?mod=viewthread&amp;tid=123&amp;mobile=2"><div class="threadlist_tit"><em>主题</em></div></a>
                        <div class="threadlist_foot"><ul><li>1</li><li>0</li></ul></div>
                    </li>
                </ul></div>
            </body></html>
        ''';

        final ForumBoardPage page = parser.parse(
            html,
            pageUri,
            expectedBoardId: 30,
        );

        expect(page.threads.single.author, '作者');
        expect(page.threads.single.authorId, isNull);
        expect(page.threads.single.authorUri, isNull);
    });

    test('不自行补全缺少 mobile=2 的分页地址', ()
    {
        const String html = '''
            <html><body id="forum" class="pg_forumdisplay">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <div class="threadlist"><div class="empty"></div></div>
                <div class="pg"><a class="nxt" href="forum.php?mod=forumdisplay&amp;fid=30&amp;page=3">下一页</a></div>
            </body></html>
        ''';

        expect(
            () => parser.parse(html, pageUri, expectedBoardId: 30),
            throwsA(isA<ForumParseException>()),
        );
    });

    test('缺少或重复 mobile=2 的操作链接不会暴露为空入口', ()
    {
        const String html = '''
            <html><body id="forum" class="pg_forumdisplay">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <a href="forum.php?mod=post&amp;action=newthread&amp;fid=30">发帖</a>
                <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=forum&amp;id=30&amp;mobile=2&amp;mobile=2">收藏</a>
                <div class="threadlist"><div class="empty"></div></div>
            </body></html>
        ''';

        final ForumBoardPage page = parser.parse(
            html,
            pageUri,
            expectedBoardId: 30,
        );

        expect(page.newThreadUri, isNull);
        expect(page.favoriteUri, isNull);
    });

    test('版块收藏入口必须带唯一非空 opaque handlekey', ()
    {
        const String html = '''
            <html><body id="forum" class="pg_forumdisplay">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=forum&amp;id=30&amp;mobile=2">缺失</a>
                <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=forum&amp;id=30&amp;handlekey=first&amp;handlekey=second&amp;mobile=2">重复</a>
                <div class="threadlist"><div class="empty"></div></div>
            </body></html>
        ''';

        final ForumBoardPage page = parser.parse(
            html,
            pageUri,
            expectedBoardId: 30,
        );

        expect(page.favoriteUri, isNull);
    });

    test('重复目标参数的操作链接不会暴露为空入口', ()
    {
        const String html = '''
            <html><body id="forum" class="pg_forumdisplay">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <a href="forum.php?mod=post&amp;action=newthread&amp;fid=30&amp;fid=999&amp;mobile=2">发帖</a>
                <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=forum&amp;id=30&amp;id=999&amp;mobile=2">收藏</a>
                <a href="search.php?mod=curforum&amp;srhfid=30&amp;srhfid=999&amp;mobile=2">搜索</a>
                <a href="forum.php?mod=post&amp;action=newthread&amp;fid=30&amp;fid[]=999&amp;mobile=2">伪数组发帖</a>
                <div class="threadlist"><div class="empty"></div></div>
            </body></html>
        ''';

        final ForumBoardPage page = parser.parse(
            html,
            pageUri,
            expectedBoardId: 30,
        );

        expect(page.newThreadUri, isNull);
        expect(page.favoriteUri, isNull);
        expect(page.searchUri, isNull);
    });

    test('选择器形状相似但路由语义错误的操作链接不会暴露', ()
    {
        const String html = '''
            <html><body id="forum" class="pg_forumdisplay">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <a href="home.php?mod=post&amp;action=newthread&amp;fid=30&amp;mobile=2">发帖</a>
                <a href="misc.php?mod=spacecp&amp;ac=favorite&amp;type=forum&amp;id=30&amp;mobile=2">收藏</a>
                <a href="forum.php?mod=curforum&amp;srhfid=30&amp;mobile=2">搜索</a>
                <div class="threadlist"><div class="empty"></div></div>
            </body></html>
        ''';

        final ForumBoardPage page = parser.parse(
            html,
            pageUri,
            expectedBoardId: 30,
        );

        expect(page.newThreadUri, isNull);
        expect(page.favoriteUri, isNull);
        expect(page.searchUri, isNull);
    });

    test('操作链接夹带未登记路由或目标参数时不暴露', ()
    {
        const String html = '''
            <html><body id="forum" class="pg_forumdisplay">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <a href="forum.php?mod=post&amp;action=newthread&amp;fid=30&amp;op=delete&amp;mobile=2">发帖</a>
                <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=forum&amp;id=30&amp;tid=9&amp;mobile=2">收藏</a>
                <a href="search.php?mod=curforum&amp;srhfid=30&amp;action=delete&amp;mobile=2">搜索</a>
                <ul class="threadlist"><li class="nothread">暂无主题</li></ul>
            </body></html>
        ''';
        final ForumBoardPage page = parser.parse(
            html,
            pageUri,
            expectedBoardId: 30,
        );
        expect(page.newThreadUri, isNull);
        expect(page.favoriteUri, isNull);
        expect(page.searchUri, isNull);
    });

    test('模板标识存在但主题容器缺失时明确失败', ()
    {
        const String html = '''
            <html><body id="forum" class="pg_forumdisplay">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
            </body></html>
        ''';

        expect(
            () => parser.parse(html, pageUri, expectedBoardId: 30),
            throwsA(isA<ForumParseException>()),
        );
    });
}
