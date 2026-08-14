import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_topic_parser.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

void main() {
  const ForumTopicParser parser = ForumTopicParser();
  final Uri pageUri = Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&page=2&'
    'mobile=2#pid101',
  );

  test('保留所有可见楼层、pid、HTML、附件与页面操作入口', () {
    const String html = '''
            <html><head>
                <meta name="viewport" content="width=device-width">
                <link rel="canonical" href="https://bbs.yamibo.com/thread-123-2-1.html">
            </head><body id="forum" class="pg_viewthread">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;page=2&amp;mobile=2">漫画区</a></h2></div>
                <div id="nav-more-menu">
                    <a class="nav-more-item" href="forum.php?mod=viewthread&amp;tid=123&amp;page=1&amp;authorid=88&amp;mobile=2"><span>只看楼主</span></a>
                    <a class="nav-more-item" href="forum.php?mod=viewthread&amp;tid=123&amp;ordertype=1&amp;mobile=2"><span>倒序浏览</span></a>
                </div>
                <div class="viewthread">
                    <div class="view_tit"><em>[漫画]</em>[漫画] 测试主题</div>
                    <div class="plc cl" id="pid100">
                        <div class="avatar"><img src="https://bbs.yamibo.com/avatar/88.jpg?formhash=avatar-secret"></div>
                        <ul class="authi">
                            <li class="mtit"><span class="y">1<sup>#</sup></span><span class="z"><a href="home.php?mod=space&amp;uid=88&amp;mobile=2">楼主</a></span></li>
                            <li class="mtime"><span class="y">浏览 10</span>2026-8-12 20:00</li>
                        </ul>
                        <div class="message"><strong>原样式</strong><img id="aimg_501" src="data/attachment/forum/page.jpg" alt="page.jpg"><img src="static/image/smiley/smile.gif"></div>
                        <div id="comment_100"><p>可见点评</p></div>
                        <div id="ratelog_100"><ul class="post_box"><li>
                          <div><a class="dialog" title="查看全部评分" href="forum.php?mod=misc&amp;action=viewratings&amp;tid=123&amp;pid=100&amp;mobile=2">参与人数 1</a></div>
                          <div>积分 +1</div><div>理由</div>
                        </li></ul></div>
                        <em class="mgl"><a href="forum.php?mod=post&amp;action=edit&amp;fid=30&amp;tid=123&amp;pid=100&amp;page=2&amp;mobile=2">编辑</a></em>
                        <div class="threadlist_foot"><ul>
                            <li><a href="forum.php?mod=misc&amp;action=rate&amp;tid=123&amp;pid=100&amp;mobile=2">评分</a></li>
                            <li><a href="forum.php?mod=misc&amp;action=comment&amp;tid=123&amp;pid=100&amp;mobile=2">点评</a></li>
                        </ul></div>
                    </div>
                    <div class="plc cl" id="pid101">
                        <div class="avatar"><img src="https://bbs.yamibo.com/avatar/99.jpg"></div>
                        <ul class="authi">
                            <li class="mtit"><span class="y">12<sup>#</sup></span><span class="z"><a href="home.php?mod=space&amp;uid=99&amp;mobile=2">读者</a></span></li>
                            <li class="mtime">2026-8-12 20:05</li>
                        </ul>
                        <div class="message"><div class="quote"><blockquote>引用原文</blockquote></div><span style="color: red">回复正文</span></div>
                        <ul class="attachlist"><li><a href="forum.php?mod=attachment&amp;aid=777">资料.zip</a><span class="attach_info">2.5 MB 附件说明</span></li></ul>
                        <div class="replybtn" id="replybtn_101"><a href="forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=123&amp;repquote=101&amp;page=2&amp;extra=page%3D2&amp;mobile=2">回复</a></div>
                    </div>
                </div>
                <div class="pg">
                    <a class="prev" href="forum.php?mod=viewthread&amp;tid=123&amp;page=1&amp;mobile=2">上一页</a>
                    <label><input name="custompage" value="2"><span title="共 4 页">2 / 4</span></label>
                    <a class="last" href="forum.php?mod=viewthread&amp;tid=123&amp;page=4&amp;mobile=2">4</a>
                    <a class="nxt" href="forum.php?mod=viewthread&amp;tid=123&amp;page=3&amp;mobile=2">下一页</a>
                </div>
                <div class="foot foot_reply">
                    <a href="forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=123&amp;reppost=100&amp;page=2&amp;mobile=2">发表回复</a>
                    <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=123&amp;mobile=2">收藏</a>
                    <a href="home.php?mod=spacecp&amp;ac=share&amp;type=thread&amp;id=123&amp;mobile=2">分享</a>
                </div>
            </body></html>
        ''';

    final ForumThreadPage page = parser.parse(
      html,
      pageUri,
      expectedThreadId: 123,
      expectedBoardId: 30,
    );

    expect(page.thread.id, 123);
    expect(page.thread.boardId, 30);
    expect(page.thread.title, '[漫画] 测试主题');
    expect(page.thread.typeName, '漫画');
    expect(page.thread.authorId, 88);
    expect(page.posts.first.authorUri?.queryParameters['uid'], '88');
    expect(page.posts.last.authorUri?.queryParameters['uid'], '99');
    expect(page.posts.first.avatarUri.toString(), isNot(contains('formhash')));
    expect(page.posts.map((ForumPost value) => value.id), <int>[100, 101]);
    expect(page.posts.map((ForumPost value) => value.floor), <int>[1, 12]);
    expect(page.posts.first.messageHtml, contains('<strong>'));
    expect(page.posts.first.messageHtml, contains('aimg_501'));
    expect(page.posts.first.contentBlocks, hasLength(1));
    expect(
      page.posts.first.contentBlocks.single,
      isA<ForumPostParagraphBlock>(),
    );
    final List<ForumPostImageInline> firstPostImages = _inlines(
      page.posts.first,
    ).whereType<ForumPostImageInline>().toList(growable: false);
    expect(firstPostImages, hasLength(2));
    expect(firstPostImages.last.isEmoticon, isTrue);
    expect(page.posts.last.contentBlocks.first, isA<ForumPostQuoteBlock>());
    expect(page.posts.last.contentBlocks.last, isA<ForumPostParagraphBlock>());
    expect(page.posts.first.comments, isEmpty);
    expect(page.posts.first.ratingSummary?.participantCount, 1);
    expect(page.posts.first.rateUri?.queryParameters['pid'], '100');
    expect(page.posts.first.commentUri?.queryParameters['pid'], '100');
    expect(page.posts.first.ratingsUri?.queryParameters['pid'], '100');
    expect(page.posts.first.editUri?.queryParameters['pid'], '100');
    expect(page.posts.first.attachments.single.id, 501);
    expect(page.posts.first.attachments.single.isImage, isTrue);
    expect(page.posts.last.quoteUri?.queryParameters['repquote'], '101');
    expect(page.posts.last.attachments.single.id, 777);
    expect(page.posts.last.attachments.single.sizeLabel, '2.5 MB');
    expect(page.posts.last.attachments.single.isImage, isFalse);
    expect(page.cursor.currentPage, 2);
    expect(page.cursor.totalPages, 4);
    expect(page.cursor.previousPageUri?.queryParameters['page'], '1');
    expect(page.cursor.nextPageUri?.queryParameters['page'], '3');
    expect(page.readingOptions, hasLength(2));
    expect(page.replyUri?.queryParameters['reppost'], '100');
    expect(page.favoriteUri?.queryParameters['type'], 'thread');
    expect(page.shareUri?.queryParameters['type'], 'thread');
    expect(page.focusedPostId, 101);
    expect(page.postById(101)?.author, '读者');
  });

  test('只从移动页登记的楼层管理区提取精确编辑入口', () {
    const String html = '''
      <html><body id="forum" class="pg_viewthread">
        <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
        <div class="viewthread"><div class="view_tit">可编辑主题</div>
          <div class="plc cl" id="pid100">
            <ul class="authi"><li class="mtit"><span class="y">1#</span><span class="z"><a>楼主</a></span></li></ul>
            <em class="mgl"><a href="forum.php?mod=post&amp;action=edit&amp;fid=30&amp;tid=123&amp;pid=100&amp;page=1&amp;mobile=2">编辑</a></em>
            <div class="message">首帖正文</div>
          </div>
          <div class="plc cl" id="pid101">
            <ul class="authi"><li class="mtit"><span class="y">2#</span><span class="z"><a>回复者</a></span></li></ul>
            <div class="message">回复正文</div>
            <div class="manage_popup"><a class="button" href="forum.php?mod=post&amp;action=edit&amp;fid=30&amp;tid=123&amp;pid=101&amp;page=1&amp;mobile=2">编辑</a></div>
          </div>
        </div>
      </body></html>
    ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    final ForumThreadPage page = parser.parse(
      html,
      uri,
      expectedThreadId: 123,
      expectedBoardId: 30,
    );

    expect(page.posts.first.editUri?.queryParameters['pid'], '100');
    expect(page.posts.last.editUri?.queryParameters['pid'], '101');
    expect(page.posts.every((ForumPost post) => post.editUri != null), isTrue);
  });

  test('不会根据登录态猜测未出现的楼层操作', () {
    const String html = '''
            <html><body id="forum" class="pg_viewthread">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <div class="viewthread"><div class="view_tit">普通主题</div>
                    <div class="plc cl" id="pid100">
                        <ul class="authi"><li class="mtit"><span class="y">1#</span><span class="z"><a>楼主</a></span></li></ul>
                        <div class="message">正文</div>
                    </div>
                </div>
            </body></html>
        ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    final ForumThreadPage page = parser.parse(
      html,
      uri,
      expectedThreadId: 123,
      expectedBoardId: 30,
    );

    expect(page.replyUri, isNull);
    expect(page.favoriteUri, isNull);
    expect(page.posts.single.quoteUri, isNull);
    expect(page.posts.single.rateUri, isNull);
  });

  test('缺少 mobile=2 的真实形状操作栏也不会产生空入口', () {
    const String html = '''
      <html><body id="forum" class="pg_viewthread">
        <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
        <div class="viewthread"><div class="view_tit">普通主题</div>
          <div class="plc cl" id="pid100">
            <ul class="authi"><li class="mtit"><span class="y">1#</span></li></ul>
            <div class="message">正文</div>
            <div class="threadlist_foot"><a href="forum.php?mod=misc&amp;action=rate&amp;tid=123&amp;pid=100">评分</a></div>
          </div>
        </div>
        <div class="foot foot_reply"><a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=123">收藏</a></div>
      </body></html>
    ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    final ForumThreadPage page = parser.parse(
      html,
      uri,
      expectedThreadId: 123,
      expectedBoardId: 30,
    );

    expect(page.favoriteUri, isNull);
    expect(page.posts.single.rateUri, isNull);
  });

  test('重复目标参数的真实操作栏不会产生空入口', () {
    const String html = '''
      <html><body id="forum" class="pg_viewthread">
        <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
        <div class="viewthread"><div class="view_tit">普通主题</div>
          <div class="plc cl" id="pid100">
            <ul class="authi"><li class="mtit"><span class="y">1#</span></li></ul>
            <div class="message">正文</div>
            <div class="threadlist_foot">
              <a href="forum.php?mod=misc&amp;action=rate&amp;tid=123&amp;pid=100&amp;pid=999&amp;mobile=2">评分</a>
            </div>
          </div>
        </div>
        <div class="foot foot_reply">
          <a href="forum.php?mod=post&amp;action=reply&amp;tid=123&amp;tid=999&amp;mobile=2">回复</a>
          <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=123&amp;id=999&amp;mobile=2">收藏</a>
          <a href="home.php?mod=spacecp&amp;ac=share&amp;type=thread&amp;id=123&amp;id=999&amp;mobile=2">分享</a>
          <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=123&amp;id[]=999&amp;mobile=2">伪数组收藏</a>
        </div>
      </body></html>
    ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    final ForumThreadPage page = parser.parse(
      html,
      uri,
      expectedThreadId: 123,
      expectedBoardId: 30,
    );

    expect(page.replyUri, isNull);
    expect(page.favoriteUri, isNull);
    expect(page.shareUri, isNull);
    expect(page.posts.single.rateUri, isNull);
  });

  test('选择器形状相似但路由语义错误的操作栏不会产生入口', () {
    const String html = '''
      <html><body id="forum" class="pg_viewthread">
        <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
        <div class="viewthread"><div class="view_tit">普通主题</div>
          <div class="plc cl" id="pid100">
            <ul class="authi"><li class="mtit"><span class="y">1#</span></li></ul>
            <div class="message">正文</div>
            <div class="threadlist_foot">
              <a href="home.php?mod=misc&amp;action=rate&amp;tid=123&amp;pid=100&amp;mobile=2">评分</a>
              <a href="forum.php?mod=post&amp;action=comment&amp;tid=123&amp;pid=100&amp;mobile=2">点评</a>
              <a href="misc.php?mod=post&amp;action=edit&amp;tid=123&amp;pid=100&amp;mobile=2">编辑</a>
            </div>
          </div>
        </div>
        <div class="foot foot_reply">
          <a href="home.php?mod=post&amp;action=reply&amp;tid=123&amp;mobile=2">回复</a>
          <a href="misc.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=123&amp;mobile=2">收藏</a>
          <a href="home.php?mod=space&amp;ac=share&amp;type=thread&amp;id=123&amp;mobile=2">伪分享</a>
        </div>
      </body></html>
    ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    final ForumThreadPage page = parser.parse(
      html,
      uri,
      expectedThreadId: 123,
      expectedBoardId: 30,
    );

    expect(page.replyUri, isNull);
    expect(page.favoriteUri, isNull);
    expect(page.shareUri, isNull);
    expect(page.posts.single.rateUri, isNull);
    expect(page.posts.single.commentUri, isNull);
    expect(page.posts.single.editUri, isNull);
  });

  test('操作栏夹带未登记路由目标或提交参数时不产生入口', () {
    const String html = '''
      <html><body id="forum" class="pg_viewthread">
        <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
        <div class="viewthread"><div class="view_tit">普通主题</div>
          <div class="plc cl" id="pid100">
            <ul class="authi"><li class="mtit"><span class="y">1#</span></li></ul>
            <div class="message">正文</div>
            <div class="threadlist_foot">
              <a href="forum.php?mod=misc&amp;action=rate&amp;tid=123&amp;pid=100&amp;op=delete&amp;mobile=2">评分</a>
              <a href="forum.php?mod=post&amp;action=edit&amp;tid=123&amp;pid=100&amp;deletesubmit=1&amp;mobile=2">编辑</a>
            </div>
          </div>
        </div>
        <div class="foot foot_reply">
          <a href="forum.php?mod=post&amp;action=reply&amp;tid=123&amp;pid=999&amp;mobile=2">回复</a>
          <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=123&amp;op=delete&amp;mobile=2">收藏</a>
          <a href="home.php?mod=spacecp&amp;ac=share&amp;type=thread&amp;id=123&amp;favid=9&amp;mobile=2">分享</a>
        </div>
      </body></html>
    ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
    final ForumThreadPage page = parser.parse(
      html,
      uri,
      expectedThreadId: 123,
      expectedBoardId: 30,
    );
    expect(page.replyUri, isNull);
    expect(page.favoriteUri, isNull);
    expect(page.shareUri, isNull);
    expect(page.posts.single.rateUri, isNull);
    expect(page.posts.single.editUri, isNull);
  });

  test('用户正文中的动作样式链接不能冒充当前账号权限入口', () {
    const String html = '''
      <html><body id="forum" class="pg_viewthread">
        <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
        <div class="viewthread"><div class="view_tit">普通主题</div>
          <div class="plc cl" id="pid100">
            <ul class="authi"><li class="mtit"><span class="y">1#</span><span class="z"><a>楼主</a></span></li></ul>
            <div class="message">
              <a href="forum.php?mod=post&amp;action=reply&amp;tid=123&amp;repquote=100&amp;mobile=2">伪引用</a>
              <a href="forum.php?mod=misc&amp;action=rate&amp;tid=123&amp;pid=100&amp;mobile=2">伪评分</a>
              <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=123&amp;mobile=2">伪收藏</a>
              <a href="home.php?mod=spacecp&amp;ac=share&amp;type=thread&amp;id=123&amp;mobile=2">伪分享</a>
            </div>
          </div>
        </div>
      </body></html>
    ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    final ForumThreadPage page = parser.parse(
      html,
      uri,
      expectedThreadId: 123,
      expectedBoardId: 30,
    );

    expect(page.replyUri, isNull);
    expect(page.favoriteUri, isNull);
    expect(page.shareUri, isNull);
    expect(page.posts.single.quoteUri, isNull);
    expect(page.posts.single.rateUri, isNull);
  });

  test('点评评分附件区域中的动作链接不能冒充操作栏', () {
    const String html = '''
      <html><body id="forum" class="pg_viewthread">
        <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
        <div class="viewthread"><div class="view_tit">普通主题</div>
          <div class="plc cl" id="pid100">
            <ul class="authi"><li class="mtit"><span class="y">1#</span><span class="z"><a>楼主</a></span></li></ul>
            <div class="message">正文</div>
            <div id="comment_100"><div class="mtxt">
              <a href="forum.php?mod=misc&amp;action=commentmore&amp;tid=123&amp;pid=100&amp;mobile=2">点评翻页</a>
              <a href="forum.php?mod=misc&amp;action=rate&amp;tid=123&amp;pid=100&amp;mobile=2">伪评分</a>
              <div class="manage_popup"><a class="button" href="forum.php?mod=post&amp;action=edit&amp;fid=30&amp;tid=123&amp;pid=100&amp;page=1&amp;mobile=2">伪编辑</a></div>
            </div></div>
            <div id="ratelog_100"><p>
              <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=123&amp;mobile=2">伪收藏</a>
            </p></div>
            <ul class="attachlist"><li>
              <a href="forum.php?mod=post&amp;action=edit&amp;tid=123&amp;pid=100&amp;mobile=2">伪编辑</a>
            </li></ul>
          </div>
        </div>
      </body></html>
    ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    final ForumThreadPage page = parser.parse(
      html,
      uri,
      expectedThreadId: 123,
      expectedBoardId: 30,
    );

    expect(page.favoriteUri, isNull);
    expect(page.posts.single.commentUri, isNull);
    expect(page.posts.single.rateUri, isNull);
    expect(page.posts.single.editUri, isNull);
  });

  test('脱敏移动模板漂移仍保留正文块、样式、媒体和链接语义', () {
    final String html = File(
      'test/features/forum/data/fixtures/topic_mobile_redacted.html',
    ).readAsStringSync();
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=321&mobile=2',
    );

    final ForumPost post = parser
        .parse(html, uri, expectedThreadId: 321, expectedBoardId: 40)
        .posts
        .single;

    expect(
      post.contentBlocks.map(
        (ForumPostContentBlock value) => value.runtimeType,
      ),
      <Type>[
        ForumPostParagraphBlock,
        ForumPostQuoteBlock,
        ForumPostCodeBlock,
        ForumPostParagraphBlock,
        ForumPostParagraphBlock,
      ],
    );
    final List<ForumPostInline> inlines = _inlines(
      post,
    ).toList(growable: false);
    expect(inlines.whereType<ForumPostLineBreakInline>(), hasLength(2));
    expect(
      inlines.whereType<ForumPostTextInline>().any(
        (ForumPostTextInline value) => value.text == '粗体' && value.bold,
      ),
      isTrue,
    );
    expect(
      inlines.whereType<ForumPostTextInline>().any(
        (ForumPostTextInline value) => value.text == '斜体' && value.italic,
      ),
      isTrue,
    );
    expect(
      inlines.whereType<ForumPostTextInline>().any(
        (ForumPostTextInline value) => value.text == 'inline()' && value.code,
      ),
      isTrue,
    );
    final List<ForumPostImageInline> images = inlines
        .whereType<ForumPostImageInline>()
        .toList(growable: false);
    expect(images, hasLength(2));
    expect(images.first.isEmoticon, isTrue);
    expect(images.last.alt, '内嵌图片');
    expect(
      images.every(
        (ForumPostImageInline value) => value.uri.host == 'bbs.yamibo.com',
      ),
      isTrue,
    );

    final List<ForumPostLinkInline> links = inlines
        .whereType<ForumPostLinkInline>()
        .toList(growable: false);
    expect(
      links.map((ForumPostLinkInline value) => value.kind),
      <ForumPostLinkKind>[
        ForumPostLinkKind.internalThread,
        ForumPostLinkKind.internalPost,
        ForumPostLinkKind.download,
        ForumPostLinkKind.external,
      ],
    );
    expect(links[0].threadId, 654);
    expect(links[1].threadId, 654);
    expect(links[1].postId, 902);
    expect(links.last.uri, Uri.parse('https://example.org/reference'));

    expect(post.comments, hasLength(1));
    final ForumPostComment comment = post.comments.single;
    expect(comment.id, 8001);
    expect(comment.threadId, 321);
    expect(comment.postId, 500);
    expect(comment.authorId, 71);
    expect(comment.authorUri?.queryParameters['uid'], '71');
    expect(comment.author, '点评用户');
    expect(comment.avatarUri.toString(), isNot(contains('formhash')));
    expect(comment.timeLabel, '发表于 2026-08-12 10:05');
    expect(comment.contentBlocks, hasLength(1));
    expect(
      comment.contentBlocks.single.inlines.whereType<ForumPostTextInline>().any(
        (ForumPostTextInline value) =>
            value.text == '加粗' && value.bold,
      ),
      isTrue,
    );
    expect(
      comment.contentBlocks.single.inlines
          .whereType<ForumPostTextInline>()
          .map((ForumPostTextInline value) => value.text)
          .join(),
      isNot(contains('redacted')),
    );

    final ForumPostRatingSummary summary = post.ratingSummary!;
    expect(summary.participantCount, 3);
    expect(summary.totals.single.credit, '积分');
    expect(summary.totals.single.value, 11);
    expect(summary.entries, hasLength(2));
    expect(summary.entries.first.authorId, 72);
    expect(summary.entries.first.authorUri?.queryParameters['uid'], '72');
    expect(summary.entries.first.author, '评分用户甲');
    expect(summary.entries.first.scores.single.value, 5);
    expect(summary.entries.first.reason, '很喜欢');
    expect(summary.hasMore, isTrue);
    expect(post.ratingsUri?.queryParameters['mobile'], '2');
  });

  test('评分详情入口不满足当前响应移动契约时关闭且不暴露原始 HTML', () {
    const String html = '''
            <html><body id="forum" class="pg_viewthread">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <div class="viewthread"><div class="view_tit">普通主题</div>
                    <div class="plc" id="pid700">
                        <ul class="authi"><li class="mtit"><span class="y">1#</span></li></ul>
                        <div class="message">正文</div>
                        <div id="ratelog_700"><ul class="post_box">
                            <li><div>参与人数 2</div><div>积分 +3</div><div>理由</div></li>
                            <li><div><a href="home.php?mod=space&amp;uid=71&amp;mobile=2">用户</a></div><div>+3</div><div><script>评分密文</script>理由</div></li>
                            <li><div><a href="forum.php?mod=misc&amp;action=viewratings&amp;tid=123&amp;pid=700&amp;mobile=2&amp;token=评分密文">查看全部</a></div></li>
                        </ul></div>
                    </div>
                </div>
            </body></html>
        ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    final ForumPost post = parser
        .parse(html, uri, expectedThreadId: 123, expectedBoardId: 30)
        .posts
        .single;

    expect(post.ratingsUri, isNull);
    expect(post.ratingSummary?.entries.single.reason, '理由');
    expect(
      <String>[
        for (final ForumPostRatingScore score in post.ratingSummary!.totals)
          score.credit,
        for (final ForumPostRatingEntry entry in post.ratingSummary!.entries)
          ...<String>[entry.author, entry.reason, entry.timeLabel],
      ].join(),
      isNot(contains('评分密文')),
    );
  });

  test('恶意 HTML 只留下不可执行文本和通过策略的 URI', () {
    const String html = '''
            <html><body id="forum" class="pg_viewthread">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <div class="viewthread"><div class="view_tit">普通主题</div>
                    <div class="plc" id="pid700">
                        <ul class="authi"><li class="mtit"><span class="y">1#</span></li></ul>
                        <div class="message">
                            <p>安全正文<script>script-secret</script></p>
                            <form action="https://evil.example/"><input name="formhash" value="form-secret">form-secret</form>
                            <iframe src="https://evil.example/">frame-secret</iframe>
                            <p>
                                <a href="javascript:alert(1)">脚本链接</a>
                                <a href="https://user:pass@example.org/private">认证外链</a>
                                <a href="https://example.org/private?token=token-secret">令牌外链</a>
                                <a href="http://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=456">降级站内链接</a>
                                <a href="home.php?tid=456">伪主题参数</a>
                                <a href="plugin.php?ptid=456&amp;pid=789">伪楼层参数</a>
                                <a href="http://example.org/public">安全外链</a>
                                <a href="forum.php?mod=viewthread&amp;tid=456&amp;pid=789&amp;formhash=post-secret">站内楼层</a>
                                <a href="forum.php?mod=attachment&amp;aid=99&amp;formhash=file-secret">安全附件</a>
                            </p>
                            <img src="data:image/png;base64,secret" alt="data 图片">
                            <img src="https://evil.example/image.png" alt="外域图片">
                            <img src="data/attachment/forum/safe.png?formhash=image-secret" alt="安全图片">
                        </div>
                    </div>
                </div>
            </body></html>
        ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    final ForumPost post = parser
        .parse(html, uri, expectedThreadId: 123, expectedBoardId: 30)
        .posts
        .single;
    final List<ForumPostInline> inlines = _inlines(
      post,
    ).toList(growable: false);
    final String plainText = _plainText(post);

    expect(plainText, contains('安全正文'));
    expect(plainText, isNot(contains('script-secret')));
    expect(plainText, isNot(contains('form-secret')));
    expect(plainText, isNot(contains('frame-secret')));
    expect(post.messageHtml, isNot(contains('<script')));
    expect(post.messageHtml, isNot(contains('<form')));
    expect(post.messageHtml, isNot(contains('<iframe')));
    expect(post.messageHtml, isNot(contains('formhash')));
    expect(post.messageHtml, isNot(contains('token-secret')));
    expect(post.messageHtml, isNot(contains('home.php?tid')));
    expect(post.messageHtml, isNot(contains('plugin.php?ptid')));

    final List<ForumPostLinkInline> links = inlines
        .whereType<ForumPostLinkInline>()
        .toList(growable: false);
    expect(
      links.map((ForumPostLinkInline value) => value.kind),
      <ForumPostLinkKind>[
        ForumPostLinkKind.external,
        ForumPostLinkKind.internalPost,
        ForumPostLinkKind.download,
      ],
    );
    expect(links.first.uri.scheme, 'http');
    expect(links[1].threadId, 456);
    expect(links[1].postId, 789);
    expect(
      links.every(
        (ForumPostLinkInline value) =>
            value.uri.userInfo.isEmpty &&
            !value.uri.toString().contains('formhash') &&
            !value.uri.toString().contains('token-secret'),
      ),
      isTrue,
    );
    final List<ForumPostImageInline> images = inlines
        .whereType<ForumPostImageInline>()
        .toList(growable: false);
    expect(images, hasLength(1));
    expect(images.single.uri.host, 'bbs.yamibo.com');
    expect(images.single.uri.toString(), isNot(contains('formhash')));
    expect(post.attachments, hasLength(2));
    expect(
      post.attachments.every(
        (ForumAttachment value) =>
            !value.uri.toString().contains('formhash') &&
            !value.uri.toString().contains('token-secret'),
      ),
      isTrue,
    );
  });

  test('同一 tid 的全站置顶允许从其他版块打开并采用页面真实 fid', () {
    const String html = '''
            <html><body id="forum" class="pg_viewthread">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=2&amp;mobile=2">管理版</a></h2></div>
                <div class="viewthread"><div class="view_tit">关于请不要发布政治及其相关敏感内容的公告</div>
                    <div class="plc cl" id="pid100">
                        <ul class="authi"><li class="mtit"><span class="y">1#</span></li></ul>
                        <div class="message">置顶正文</div>
                    </div>
                </div>
            </body></html>
        ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=55&mobile=2',
    );

    final ForumThreadPage page = parser.parse(
      html,
      uri,
      expectedThreadId: 55,
      expectedBoardId: 41,
    );

    expect(page.thread.id, 55);
    expect(page.thread.boardId, 2);
    expect(page.posts.single.messageHtml, contains('置顶正文'));
  });

  test('可见楼层缺少正文或权限提示时拒绝残缺结果', () {
    const String html = '''
            <html><body id="forum" class="pg_viewthread">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <div class="viewthread"><div class="view_tit">普通主题</div>
                    <div class="plc cl" id="pid100">
                        <ul class="authi"><li class="mtit"><span class="y">1#</span></li></ul>
                    </div>
                </div>
            </body></html>
        ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    expect(
      () => parser.parse(html, uri, expectedThreadId: 123, expectedBoardId: 30),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('页面声明的外域操作入口不会被暴露', () {
    const String html = '''
            <html><body id="forum" class="pg_viewthread">
                <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></h2></div>
                <div class="viewthread"><div class="view_tit">普通主题</div>
                    <div class="plc cl" id="pid100">
                        <ul class="authi"><li class="mtit"><span class="y">1#</span></li></ul>
                        <div class="message">正文</div>
                        <a href="https://evil.example/forum.php?mod=misc&amp;action=rate&amp;tid=123&amp;pid=100">评分</a>
                    </div>
                </div>
            </body></html>
        ''';
    final Uri uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );

    final ForumThreadPage page = parser.parse(
      html,
      uri,
      expectedThreadId: 123,
      expectedBoardId: 30,
    );

    expect(page.posts.single.rateUri, isNull);
  });
}

Iterable<ForumPostInline> _inlines(ForumPost post) sync* {
  for (final ForumPostContentBlock block in post.contentBlocks) {
    yield* block.inlines;
  }
}

String _plainText(ForumPost post) {
  return _inlines(post).map((ForumPostInline value) {
    return switch (value) {
      ForumPostTextInline(:final String text) => text,
      ForumPostLinkInline(:final String label) => label,
      ForumPostImageInline(:final String alt) => alt,
      ForumPostLineBreakInline() => '\n',
    };
  }).join();
}
