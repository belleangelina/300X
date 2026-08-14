import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/community/data/community_repository.dart';
import 'package:x300/features/community/domain/community_models.dart';
import 'package:x300/features/community/presentation/community_pages.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/domain/forum_announcement_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart' as domain;
import 'package:x300/features/forum/presentation/forum_announcement_page.dart';
import 'package:x300/features/forum/presentation/forum_board_page.dart';
import 'package:x300/features/forum/presentation/forum_home_page.dart';
import 'package:x300/features/forum/presentation/forum_topic_page.dart';

class _MockForumReadRepository extends Mock implements ForumReadRepository {}

class _MockCommunityRepository extends Mock implements CommunityRepository {}

void main() {
  late _MockForumReadRepository repository;
  late _MockCommunityRepository communityRepository;
  late Uri boardUri;
  late Uri filterUri;
  late Uri threadUri;
  late Uri nextThreadUri;
  late domain.ForumBoardNode board;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://bbs.yamibo.com/?mobile=2'));
    registerFallbackValue(
      _boardPage(
        board: _board(
          Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=41&mobile=2',
          ),
        ),
      ),
    );
  });

  setUp(() {
    repository = _MockForumReadRepository();
    communityRepository = _MockCommunityRepository();
    boardUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=41&mobile=2',
    );
    filterUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=41&filter=digest&mobile=2',
    );
    threadUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&mobile=2',
    );
    nextThreadUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=2&mobile=2',
    );
    board = _board(boardUri);
  });

  testWidgets('论坛首页连续展示分区和子版块并标记只读缓存', (WidgetTester tester) async {
    final Uri noticesUri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&do=notice&mobile=2',
    );
    final domain.ForumBoardNode child = domain.ForumBoardNode(
      id: 42,
      parentId: 41,
      name: '子版块',
      uri: boardUri.replace(
        queryParameters: <String, String>{
          'mod': 'forumdisplay',
          'fid': '42',
          'mobile': '2',
        },
      ),
    );
    final domain.ForumBoardNode parent = domain.ForumBoardNode(
      id: board.id,
      name: board.name,
      uri: board.uri,
      description: '版块说明',
      todayPostCount: 3,
      children: <domain.ForumBoardNode>[child],
    );
    when(repository.loadIndex).thenAnswer(
      (_) async => domain.ForumBoardIndex(
        sections: <domain.ForumSection>[
          domain.ForumSection(
            id: 1,
            name: '测试分区',
            boards: <domain.ForumBoardNode>[parent],
          ),
        ],
        unsectionedBoards: const <domain.ForumBoardNode>[],
        viewer: const domain.ForumViewer(
          userId: 7,
          username: '测试账号',
          noticeCount: 2,
          privateMessageCount: 1,
        ),
        navigation: domain.ForumNavigationLinks(
          searchUri: Uri.parse(
            'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
          ),
          noticesUri: noticesUri,
          messagesUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=space&do=pm&mobile=2',
          ),
          profileUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=space&do=profile&uid=7&mobile=2',
          ),
        ),
        sourceUri: Uri.parse('https://bbs.yamibo.com/forum.php?mobile=2'),
        isFromCache: true,
        cacheUpdatedAt: DateTime(2026, 8, 12, 9, 30),
      ),
    );
    when(() => communityRepository.loadNotices(noticesUri)).thenAnswer(
      (_) async => CommunityNoticePage(
        items: const <CommunityNotice>[],
        categories: const <CommunityNoticeCategory>[],
        cursor: CommunityPageCursor(
          sourceUri: noticesUri,
          currentPage: 1,
          totalPages: 1,
        ),
      ),
    );

    await tester.pumpWidget(
      _app(
        repository,
        ForumHomePage(
          authState: const AuthState.authenticated('测试账号', userId: 7),
          onLogin: () {},
        ),
        communityRepository: communityRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试分区'), findsOneWidget);
    expect(find.text('测试版块'), findsOneWidget);
    expect(find.text('子版块'), findsOneWidget);
    expect(find.textContaining('今日 3'), findsOneWidget);
    expect(find.byTooltip('搜索论坛'), findsOneWidget);
    expect(find.byTooltip('社区与账号'), findsOneWidget);
    await tester.tap(find.byTooltip('社区与账号'));
    await tester.pumpAndSettle();
    expect(find.text('通知 (2)'), findsOneWidget);
    expect(find.text('私信 (1)'), findsOneWidget);
    expect(find.text('个人资料'), findsOneWidget);
    expect(find.textContaining('论坛不可用，当前显示只读缓存'), findsOneWidget);
    await tester.tap(find.text('通知 (2)'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityNoticesScreen), findsOneWidget);
    verify(() => communityRepository.loadNotices(noticesUri)).called(1);
  });

  testWidgets('未登录论坛首页只提供登录入口', (WidgetTester tester) async {
    var loginRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ForumHomePage(
          authState: const AuthState.unauthenticated(),
          onLogin: () => loginRequests++,
        ),
      ),
    );

    expect(find.text('登录后查看论坛'), findsOneWidget);
    await tester.tap(find.text('登录'));
    expect(loginRequests, 1);
    verifyNever(repository.loadIndex);
  });

  testWidgets('版块页展示动态筛选和主题状态，公告不冒充普通主题', (WidgetTester tester) async {
    final Uri nextBoardUri = boardUri.replace(
      queryParameters: <String, String>{
        'mod': 'forumdisplay',
        'fid': '41',
        'page': '2',
        'mobile': '2',
      },
    );
    final domain.ForumBoardPage first = _boardPage(
      board: board,
      filters: <domain.ForumRouteOption>[
        domain.ForumRouteOption(
          key: 'all',
          label: '全部',
          uri: boardUri,
          selected: true,
        ),
        domain.ForumRouteOption(key: 'digest', label: '精华筛选', uri: filterUri),
      ],
      threads: <domain.ForumThreadSummary>[
        domain.ForumThreadSummary(
          id: 9,
          boardId: 41,
          title: '站务公告',
          uri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=announcement&id=9&mobile=2',
          ),
          pinned: true,
          targetKind: domain.ForumThreadTargetKind.announcement,
        ),
        domain.ForumThreadSummary(
          id: 100,
          boardId: 41,
          title: '普通主题',
          uri: threadUri,
          author: '作者甲',
          authorId: 77,
          authorUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=space&uid=77&mobile=2',
          ),
          digest: true,
          closed: true,
        ),
      ],
      cursor: domain.ForumPageCursor(
        currentPage: 1,
        totalPages: 2,
        sourceUri: boardUri,
        nextPageUri: nextBoardUri,
      ),
      searchUri: boardUri.resolve('search.php'),
      newThreadUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=41&mobile=2',
      ),
    );
    final domain.ForumBoardPage second = _boardPage(
      board: board,
      threads: <domain.ForumThreadSummary>[
        domain.ForumThreadSummary(
          id: 101,
          boardId: 41,
          title: '第二页主题',
          uri: nextThreadUri.replace(
            queryParameters: <String, String>{
              'mod': 'viewthread',
              'tid': '101',
              'mobile': '2',
            },
          ),
        ),
      ],
      cursor: domain.ForumPageCursor(
        currentPage: 2,
        totalPages: 2,
        sourceUri: nextBoardUri,
        previousPageUri: boardUri,
      ),
    );
    when(
      () => repository.loadBoard(
        any(),
        expectedBoardId: any(named: 'expectedBoardId'),
      ),
    ).thenAnswer((_) async => first);
    when(() => repository.loadNextBoard(any())).thenAnswer((_) async => second);
    when(
      () => repository.loadAnnouncement(
        any(),
        expectedAnnouncementId: any(named: 'expectedAnnouncementId'),
      ),
    ).thenAnswer(
      (_) async => ForumAnnouncement(
        id: 9,
        title: '站务公告',
        metadataLabel: '2026-08-13',
        contentBlocks: const <domain.ForumPostContentBlock>[
          domain.ForumPostParagraphBlock(
            inlines: <domain.ForumPostInline>[
              domain.ForumPostTextInline(text: '公告正文'),
            ],
          ),
        ],
        messageHtml: '<p>公告正文</p>',
        sourceUri: Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=announcement&id=9&mobile=2',
        ),
      ),
    );

    domain.ForumThreadSummary? openedAuthor;
    await tester.pumpWidget(
      _app(
        repository,
        ForumBoardPage(
          board: board,
          onOpenAuthor: (domain.ForumThreadSummary value) =>
              openedAuthor = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('精华筛选'), findsOneWidget);
    expect(find.text('公告'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('精华'), findsOneWidget);
    expect(find.text('已关闭'), findsOneWidget);
    expect(find.byTooltip('搜索本版'), findsOneWidget);
    expect(find.byKey(const Key('forum-new-thread')), findsOneWidget);
    expect(find.byTooltip('收藏版块'), findsNothing);
    expect(find.byTooltip('发布主题'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('forum-board-author-77')),
    );
    expect(openedAuthor?.authorId, 77);

    await tester.tap(
      find.byKey(const ValueKey<String>('forum-announcement-9')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ForumAnnouncementPage), findsOneWidget);
    expect(find.text('公告正文'), findsOneWidget);
    expect(find.byType(ForumTopicPage), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('精华筛选'));
    await tester.pumpAndSettle();
    verify(
      () => repository.loadBoard(filterUri, expectedBoardId: 41),
    ).called(1);

    await tester.tap(find.text('加载下一页'));
    await tester.pumpAndSettle();
    expect(find.text('第二页主题'), findsOneWidget);
    verify(() => repository.loadNextBoard(any())).called(1);
  });

  testWidgets('主题页安全展示全部楼层并精确定位 pid', (WidgetTester tester) async {
    final domain.ForumThreadPage page = _topicPage(
      threadUri: threadUri,
      posts: <domain.ForumPost>[
        _post(
          id: 201,
          floor: 1,
          threadUri: threadUri,
          messageHtml: List<String>.filled(55, '<p>首屏占位正文</p>').join(),
          originalPoster: true,
        ),
        _post(
          id: 202,
          floor: 2,
          threadUri: threadUri,
          messageHtml:
              '<p>安全正文<script>恶意脚本</script>'
              '<a href="https://example.com/">外链文字</a></p>'
              '<form>不应显示</form>',
          contentBlocks: <domain.ForumPostContentBlock>[
            const domain.ForumPostParagraphBlock(
              inlines: <domain.ForumPostInline>[
                domain.ForumPostTextInline(text: '安全正文'),
              ],
            ),
            domain.ForumPostQuoteBlock(
              inlines: <domain.ForumPostInline>[
                const domain.ForumPostTextInline(text: '引用正文', italic: true),
                const domain.ForumPostLineBreakInline(),
                domain.ForumPostLinkInline(
                  label: '同帖楼层',
                  uri: threadUri.replace(fragment: 'pid201'),
                  kind: domain.ForumPostLinkKind.internalPost,
                  threadId: 100,
                  postId: 201,
                ),
              ],
            ),
            const domain.ForumPostCodeBlock(
              inlines: <domain.ForumPostInline>[
                domain.ForumPostTextInline(text: 'print(value);', code: true),
              ],
            ),
          ],
          attachments: <domain.ForumAttachment>[
            domain.ForumAttachment(
              name: '资料.txt',
              uri: threadUri.resolve('forum.php?mod=attachment&aid=8'),
              sizeLabel: '2 KB',
            ),
          ],
          quoteUri: threadUri.resolve(
            'forum.php?mod=post&action=reply&repquote=202',
          ),
        ),
      ],
      focusedPostId: 202,
      isFromCache: true,
      replyUri: threadUri.resolve('forum.php?mod=post&action=reply&tid=100'),
    );
    when(
      () => repository.loadThreadAtPost(threadId: 100, postId: 202),
    ).thenAnswer((_) async => page);

    await tester.pumpWidget(
      _app(
        repository,
        ForumTopicPage(thread: _thread(threadUri), focusedPostId: 202),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('forum-post-201')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('forum-post-202')),
      findsOneWidget,
    );
    expect(find.textContaining('安全正文'), findsOneWidget);
    expect(find.textContaining('外链文字'), findsNothing);
    expect(find.textContaining('引用正文'), findsOneWidget);
    expect(find.textContaining('print(value);'), findsOneWidget);
    expect(find.text('同帖楼层'), findsOneWidget);
    expect(find.textContaining('恶意脚本'), findsNothing);
    expect(find.textContaining('不应显示'), findsNothing);
    expect(find.text('资料.txt'), findsOneWidget);
    expect(find.byTooltip('回复主题'), findsNothing);
    expect(find.byTooltip('收藏主题'), findsNothing);
    expect(find.byTooltip('分享主题'), findsNothing);
    expect(find.text('引用'), findsNothing);
    expect(find.text('评分'), findsNothing);
    expect(find.textContaining('论坛不可用，当前显示只读缓存'), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey<String>('forum-post-202')))
          .dy,
      lessThan(360),
    );

    await tester.tap(find.text('同帖楼层'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey<String>('forum-post-201')))
          .dy,
      lessThan(360),
    );
  });

  testWidgets('主题页只显示当前响应提供且本平台可完成的操作', (
    WidgetTester tester,
  ) async {
    final domain.ForumThreadPage page = _topicPage(
      threadUri: threadUri,
      posts: <domain.ForumPost>[
        _post(
          id: 201,
          floor: 1,
          threadUri: threadUri,
          messageHtml: '<p>正文</p>',
        ),
      ],
      replyUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=41&tid=100&mobile=2',
      ),
      favoriteUri: Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&type=thread&id=100&mobile=2',
      ),
      shareUri: Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=spacecp&ac=share&type=thread&id=100&mobile=2',
      ),
    );
    when(
      () => repository.loadThread(
        any(),
        expectedThreadId: any(named: 'expectedThreadId'),
        expectedBoardId: any(named: 'expectedBoardId'),
        focusedPostId: any(named: 'focusedPostId'),
      ),
    ).thenAnswer((_) async => page);

    await tester.pumpWidget(
      _app(repository, ForumTopicPage(thread: _thread(threadUri))),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-favorite-thread')), findsOneWidget);
    expect(find.byKey(const Key('forum-share-thread')), findsOneWidget);
    expect(find.byKey(const Key('forum-original-reply')), findsNothing);
  });

  testWidgets('公告正文内链进入原生主题，外链仅交给系统应用', (WidgetTester tester) async {
    final Uri announcementUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=announcement&id=9',
    );
    final Uri targetUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=200&mobile=2',
    );
    final Uri externalUri = Uri.parse('https://example.org/public');
    when(
      () => repository.loadAnnouncement(
        announcementUri,
        expectedAnnouncementId: 9,
      ),
    ).thenAnswer(
      (_) async => ForumAnnouncement(
        id: 9,
        title: '站务公告',
        metadataLabel: '2026-08-13',
        contentBlocks: <domain.ForumPostContentBlock>[
          domain.ForumPostParagraphBlock(
            inlines: <domain.ForumPostInline>[
              domain.ForumPostLinkInline(
                label: '相关主题',
                uri: targetUri,
                kind: domain.ForumPostLinkKind.internalThread,
                threadId: 200,
              ),
              const domain.ForumPostTextInline(text: ' '),
              domain.ForumPostLinkInline(
                label: '公开外链',
                uri: externalUri,
                kind: domain.ForumPostLinkKind.external,
              ),
            ],
          ),
        ],
        messageHtml: '',
        sourceUri: announcementUri,
      ),
    );
    when(
      () => repository.loadThread(
        any(),
        expectedThreadId: any(named: 'expectedThreadId'),
        expectedBoardId: any(named: 'expectedBoardId'),
        focusedPostId: any(named: 'focusedPostId'),
      ),
    ).thenAnswer((_) => Completer<domain.ForumThreadPage>().future);
    final List<String> launched = <String>[];
    const MethodChannel channel = MethodChannel(
      'plugins.flutter.io/url_launcher',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      launched.add((call.arguments as Map<Object?, Object?>)['url'] as String);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      _app(
        repository,
        ForumAnnouncementPage(
          announcement: domain.ForumThreadSummary(
            id: 9,
            boardId: 41,
            title: '站务公告',
            uri: announcementUri,
            targetKind: domain.ForumThreadTargetKind.announcement,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('公开外链'));
    await tester.pump();
    expect(launched, <String>[externalUri.toString()]);
    verifyNever(
      () => repository.loadThread(
        externalUri,
        expectedThreadId: any(named: 'expectedThreadId'),
        expectedBoardId: any(named: 'expectedBoardId'),
        focusedPostId: any(named: 'focusedPostId'),
      ),
    );

    final InkWell internalLink = tester.widget<InkWell>(
      find.byKey(
        ValueKey<String>('forum-post-link-internalThread-$targetUri'),
      ),
    );
    internalLink.onTap!();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isTrue,
    );
    final ForumTopicPage page = tester.widget<ForumTopicPage>(
      find.byType(ForumTopicPage, skipOffstage: false),
    );
    expect(page.thread.id, 200);
    expect(page.thread.uri, targetUri);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('主题翻页严格使用服务端返回的 next 地址', (WidgetTester tester) async {
    final domain.ForumThreadPage first = _topicPage(
      threadUri: threadUri,
      posts: <domain.ForumPost>[
        _post(
          id: 201,
          floor: 1,
          threadUri: threadUri,
          messageHtml: '<p>第一页正文</p>',
        ),
      ],
      nextPageUri: nextThreadUri,
      totalPages: 2,
    );
    final domain.ForumThreadPage second = _topicPage(
      threadUri: nextThreadUri,
      posts: <domain.ForumPost>[
        _post(
          id: 211,
          floor: 11,
          threadUri: nextThreadUri,
          messageHtml: '<p>第二页正文</p>',
        ),
      ],
      currentPage: 2,
      totalPages: 2,
      previousPageUri: threadUri,
    );
    when(
      () => repository.loadThread(
        any(),
        expectedThreadId: any(named: 'expectedThreadId'),
        expectedBoardId: any(named: 'expectedBoardId'),
        focusedPostId: any(named: 'focusedPostId'),
      ),
    ).thenAnswer((Invocation invocation) async {
      final Uri uri = invocation.positionalArguments.first as Uri;
      return uri == nextThreadUri ? second : first;
    });

    await tester.pumpWidget(
      _app(repository, ForumTopicPage(thread: _thread(threadUri))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('第一页正文'), findsOneWidget);

    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();

    expect(find.textContaining('第二页正文'), findsOneWidget);
    verify(
      () => repository.loadThread(
        nextThreadUri,
        expectedThreadId: 100,
        expectedBoardId: 41,
        focusedPostId: null,
      ),
    ).called(1);
  });

  testWidgets('外链与下载交给系统应用且不经过论坛读取仓库', (WidgetTester tester) async {
    final Uri externalUri = Uri.parse('https://example.org/public');
    final Uri downloadUri = threadUri.resolve('forum.php?mod=attachment&aid=9');
    final domain.ForumThreadPage page = _topicPage(
      threadUri: threadUri,
      posts: <domain.ForumPost>[
        _post(
          id: 201,
          floor: 1,
          threadUri: threadUri,
          messageHtml: '<p>旧正文</p>',
          contentBlocks: <domain.ForumPostContentBlock>[
            domain.ForumPostParagraphBlock(
              inlines: <domain.ForumPostInline>[
                domain.ForumPostLinkInline(
                  label: '外部资料',
                  uri: externalUri,
                  kind: domain.ForumPostLinkKind.external,
                ),
                const domain.ForumPostTextInline(text: ' '),
                domain.ForumPostLinkInline(
                  label: '下载资料',
                  uri: downloadUri,
                  kind: domain.ForumPostLinkKind.download,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    when(
      () => repository.loadThread(
        any(),
        expectedThreadId: any(named: 'expectedThreadId'),
        expectedBoardId: any(named: 'expectedBoardId'),
        focusedPostId: any(named: 'focusedPostId'),
      ),
    ).thenAnswer((_) async => page);
    final List<String> launched = <String>[];
    const MethodChannel channel = MethodChannel(
      'plugins.flutter.io/url_launcher',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      launched.add((call.arguments as Map<Object?, Object?>)['url'] as String);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      _app(repository, ForumTopicPage(thread: _thread(threadUri))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('外部资料'));
    await tester.pump();
    await tester.tap(find.text('下载资料'));
    await tester.pump();

    expect(launched, <String>[externalUri.toString(), downloadUri.toString()]);
    verify(
      () => repository.loadThread(
        threadUri,
        expectedThreadId: 100,
        expectedBoardId: 41,
        focusedPostId: null,
      ),
    ).called(1);
    verifyNever(
      () => repository.loadThreadAtPost(
        threadId: any(named: 'threadId'),
        postId: any(named: 'postId'),
      ),
    );
  });

  testWidgets('跨主题正文链接进入原生 ForumTopicPage', (WidgetTester tester) async {
    final Uri targetUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=200&mobile=2',
    );
    final domain.ForumThreadPage page = _topicPage(
      threadUri: threadUri,
      posts: <domain.ForumPost>[
        _post(
          id: 201,
          floor: 1,
          threadUri: threadUri,
          messageHtml: '',
          contentBlocks: <domain.ForumPostContentBlock>[
            domain.ForumPostParagraphBlock(
              inlines: <domain.ForumPostInline>[
                domain.ForumPostLinkInline(
                  label: '另一个主题',
                  uri: targetUri,
                  kind: domain.ForumPostLinkKind.internalThread,
                  threadId: 200,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    when(
      () => repository.loadThread(
        any(),
        expectedThreadId: any(named: 'expectedThreadId'),
        expectedBoardId: any(named: 'expectedBoardId'),
        focusedPostId: any(named: 'focusedPostId'),
      ),
    ).thenAnswer((_) async => page);

    await tester.pumpWidget(
      _app(repository, ForumTopicPage(thread: _thread(threadUri))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('另一个主题'));
    await tester.pumpAndSettle();

    final List<ForumTopicPage> pages = tester
        .widgetList<ForumTopicPage>(find.byType(ForumTopicPage))
        .toList(growable: false);
    final ForumTopicPage targetPage = pages.singleWhere(
      (ForumTopicPage page) => page.thread.id == 200,
    );
    expect(targetPage.thread.uri, targetUri);
  });
}

Widget _app(
  ForumReadRepository repository,
  Widget home, {
  CommunityRepository? communityRepository,
}) {
  return ProviderScope(
    overrides: [
      forumReadRepositoryProvider.overrideWithValue(repository),
      if (communityRepository != null)
        communityRepositoryProvider.overrideWithValue(communityRepository),
    ],
    child: MaterialApp(home: home),
  );
}

domain.ForumBoardNode _board(Uri uri) {
  return domain.ForumBoardNode(id: 41, name: '测试版块', uri: uri);
}

domain.ForumBoardPage _boardPage({
  required domain.ForumBoardNode board,
  List<domain.ForumRouteOption> filters = const <domain.ForumRouteOption>[],
  List<domain.ForumThreadSummary> threads = const <domain.ForumThreadSummary>[],
  domain.ForumPageCursor? cursor,
  Uri? searchUri,
  Uri? newThreadUri,
}) {
  return domain.ForumBoardPage(
    board: board,
    threads: threads,
    filters: filters,
    cursor:
        cursor ??
        domain.ForumPageCursor(
          currentPage: 1,
          totalPages: 1,
          sourceUri: board.uri,
        ),
    searchUri: searchUri,
    newThreadUri: newThreadUri,
  );
}

domain.ForumThreadSummary _thread(Uri uri) {
  return domain.ForumThreadSummary(
    id: 100,
    boardId: 41,
    title: '测试主题',
    uri: uri,
  );
}

domain.ForumPost _post({
  required int id,
  required int floor,
  required Uri threadUri,
  required String messageHtml,
  bool originalPoster = false,
  List<domain.ForumAttachment> attachments = const <domain.ForumAttachment>[],
  List<domain.ForumPostContentBlock> contentBlocks =
      const <domain.ForumPostContentBlock>[],
  Uri? quoteUri,
}) {
  return domain.ForumPost(
    id: id,
    threadId: 100,
    floor: floor,
    author: floor == 1 ? '楼主' : '回复者',
    timeLabel: '2026-08-12',
    messageHtml: messageHtml,
    uri: threadUri.replace(fragment: 'pid$id'),
    attachments: attachments,
    contentBlocks: contentBlocks,
    quoteUri: quoteUri,
    isOriginalPoster: originalPoster,
  );
}

domain.ForumThreadPage _topicPage({
  required Uri threadUri,
  required List<domain.ForumPost> posts,
  int currentPage = 1,
  int totalPages = 1,
  Uri? previousPageUri,
  Uri? nextPageUri,
  int? focusedPostId,
  bool isFromCache = false,
  Uri? replyUri,
  Uri? favoriteUri,
  Uri? shareUri,
}) {
  return domain.ForumThreadPage(
    thread: domain.ForumThread(
      id: 100,
      boardId: 41,
      title: '测试主题',
      uri: threadUri,
      author: '楼主',
    ),
    posts: posts,
    readingOptions: const <domain.ForumRouteOption>[],
    cursor: domain.ForumPageCursor(
      currentPage: currentPage,
      totalPages: totalPages,
      sourceUri: threadUri,
      previousPageUri: previousPageUri,
      nextPageUri: nextPageUri,
    ),
    replyUri: replyUri,
    favoriteUri: favoriteUri,
    shareUri: shareUri,
    focusedPostId: focusedPostId,
    isFromCache: isFromCache,
    cacheUpdatedAt: isFromCache ? DateTime(2026, 8, 12, 9, 30) : null,
  );
}
