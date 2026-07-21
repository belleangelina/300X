import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/library/data/forum_thread_parser.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

void main()
{
    const ForumThreadParser parser = ForumThreadParser();
    final Uri pageUri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&page=1&mobile=2',
    );

    test('按正文顺序解析文本、图片和目录链接', ()
    {
        const String html = '''
                        <html>
                        <body id="forum" class="pg_viewthread">
                                <div class="view_tit"><em>[文学]</em>测试作品</div>
                                <a href="forum.php?mod=viewthread&amp;tid=123&amp;page=1&amp;authorid=88&amp;mobile=2">只看楼主</a>
                                <div class="plc cl" id="pid100">
                                        <ul class="authi">
                                                <li class="mtit"><span class="y">1楼</span><span class="z"><a>楼主</a></span></li>
                                                <li class="mtime"><span class="y">浏览 10</span>2026-7-10 09:00</li>
                                        </ul>
                                        <div class="message">
                                                <i class="pstatus">编辑记录</i>
                                                <h3>第一章</h3>
                                                <p>第一段 <strong>正文</strong></p>
                                                <blockquote class="quote">引用内容</blockquote>
                                                <img src="data/attachment/forum/chapter.png" alt="插图" />
                                                <img src="static/image/smiley/smile.gif" smilieid="1" />
                                                <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=123&amp;pid=101">第2章</a>
                                                <a href="forum.php?mod=viewthread&amp;tid=456&amp;mobile=2">下一章</a>
                                        </div>
                                        <ul class="img_one">
                                                <li><img src="data/attachment/forum/sibling-page.jpg" alt="正文附件" /></li>
                                        </ul>
                                </div>
                                <div class="plc cl" id="pid101">
                                        <ul class="authi">
                                                <li class="mtit"><span class="y">2楼</span><span class="z"><a>读者</a></span></li>
                                                <li class="mtime">2026-7-10 09:05</li>
                                        </ul>
                                        <div class="message">普通回复</div>
                                </div>
                                <div class="pg">
                                        <input name="custompage" value="1" />
                                        <a class="last" href="forum.php?mod=viewthread&amp;tid=123&amp;page=3&amp;mobile=2">3</a>
                                        <a class="nxt" href="forum.php?mod=viewthread&amp;tid=123&amp;page=2&amp;mobile=2">下一页</a>
                                </div>
                        </body>
                        </html>
                ''';

        final ForumThreadPage page = parser.parse(
            html,
            pageUri,
            ForumBoard.literature,
        );
        final SourcePost original = page.originalPost!;

        expect(page.tid, 123);
        expect(page.typeName, '#文学');
        expect(page.posts, hasLength(2));
        expect(page.totalPages, 3);
        expect(
            page.originalPosterUri,
            Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&page=1&authorid=88&mobile=2',
            ),
        );
        expect(original.isOriginalPoster, isTrue);
        expect(original.timeLabel, '2026-7-10 09:00');
        expect(original.imageUris, <Uri>[
            Uri.parse('https://bbs.yamibo.com/data/attachment/forum/chapter.png'),
            Uri.parse(
                'https://bbs.yamibo.com/data/attachment/forum/sibling-page.jpg',
            ),
        ]);
        expect(original.plainText, contains('第一章'));
        expect(original.plainText, contains('第一段 正文'));
        expect(original.plainText, isNot(contains('编辑记录')));
        expect(original.plainText, isNot(contains('引用内容')));
        expect(original.links, hasLength(2));
        expect(original.links[0].kind, ThreadLinkKind.chapter);
        expect(original.links[0].pid, 101);
        expect(original.links[1].kind, ThreadLinkKind.next);
        expect(original.links[1].tid, 456);
    });

    test('保留论坛 Tag 目录并排除引用块内跳转链接', ()
    {
        const String html = '''
                        <html>
                        <body id="forum" class="pg_viewthread">
                                <div class="view_tit">测试作品</div>
                                <div class="plc cl" id="pid100">
                                        <ul class="authi">
                                                <li class="mtit"><span class="y">1楼</span><span class="z"><a>楼主</a></span></li>
                                        </ul>
                                        <div class="message">
                                                <a href="misc.php?mod=tag&amp;id=15629">本作目录</a>
                                                <a href="http://bbs.yamibo.com/misc.php?mod=tag&amp;id=1">不安全目录</a>
                                                <blockquote class="quote">
                                                        <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=123&amp;pid=99">第99话</a>
                                                </blockquote>
                                                <a href="thread-456-1-1.html">第一话</a>
                                        </div>
                                </div>
                        </body>
                        </html>
                ''';

        final ForumThreadPage page = parser.parse(html, pageUri, ForumBoard.comic);

        expect(page.originalPost!.links, hasLength(2));
        expect(page.originalPost!.links.first.kind, ThreadLinkKind.directory);
        expect(page.originalPost!.links.last.tid, 456);
        expect(
            page.originalPost!.links.any((ThreadLink link) => link.pid == 99),
            isFalse,
        );
    });

    test('小说楼主的无引用来源长 quote 作为正文保留', ()
    {
        final String body = '小说正文'.padRight(900, '文');
        final String html = '''
                        <html>
                        <body id="forum" class="pg_viewthread">
                                <div class="view_tit"><em>[轻小说]</em>测试小说</div>
                                <div class="plc cl" id="pid100">
                                        <ul class="authi">
                                                <li class="mtit"><span class="y">1楼</span><span class="z"><a>楼主</a></span></li>
                                        </ul>
                                        <div class="message">
                                                <div>更新公告</div>
                                                <div class="quote"><blockquote>$body</blockquote></div>
                                        </div>
                                </div>
                        </body>
                        </html>
                ''';

        final ForumThreadPage page = parser.parse(
            html,
            pageUri,
            ForumBoard.lightNovel,
        );

        expect(page.originalPost!.plainText, contains(body));
        expect(page.originalPost!.plainText, contains('更新公告'));
    });

    test('旧帖链接含非 UTF-8 附加参数时仍可提取 tid', ()
    {
        const String html = '''
                        <html>
                        <body id="forum" class="pg_viewthread">
                                <div class="view_tit">测试作品</div>
                                <div class="plc cl" id="pid100">
                                        <ul class="authi">
                                                <li class="mtit"><span class="y">1楼</span><span class="z"><a>楼主</a></span></li>
                                        </ul>
                                        <div class="message">
                                                <a href="forum.php?mod=viewthread&amp;tid=456&amp;extra=%B7">第2话</a>
                                        </div>
                                </div>
                        </body>
                        </html>
                ''';

        final ForumThreadPage page = parser.parse(
            html,
            pageUri,
            ForumBoard.comic,
            expectedTid: 123,
        );

        expect(page.originalPost!.links.single.tid, 456);
        expect(page.originalPost!.links.single.kind, ThreadLinkKind.chapter);
    });

    test('忽略论坛错误包裹的数据图片占位符', ()
    {
        const String html = '''
                        <html>
                        <body id="forum" class="pg_viewthread">
                                <div class="view_tit">测试作品</div>
                                <div class="plc cl" id="pid100">
                                        <ul class="authi">
                                                <li class="mtit"><span class="y">1楼</span><span class="z"><a>楼主</a></span></li>
                                        </ul>
                                        <div class="message">
                                                <img src="//data:image/png;base64,iVBORw0KGgo=" />
                                                <img src="data:image/png;base64,iVBORw0KGgo=" />
                                                <img src="http://data:image/png;base64,iVBORw0KGgo=" />
                                                <img src="data/attachment/forum/real.jpg" />
                                        </div>
                                </div>
                        </body>
                        </html>
                ''';

        final ForumThreadPage page = parser.parse(
            html,
            pageUri,
            ForumBoard.comic,
            expectedTid: 123,
        );

        expect(page.originalPost!.imageUris, <Uri>[
            Uri.parse('https://bbs.yamibo.com/data/attachment/forum/real.jpg'),
        ]);
    });
}
