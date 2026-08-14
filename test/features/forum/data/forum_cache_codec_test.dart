import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_cache_codec.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

void main() {
  const ForumCacheCodec codec = ForumCacheCodec();

  test('主题缓存只保留只读内容并移除 formhash 和动作入口', () {
    final ForumThreadPage source = ForumThreadPage(
      thread: ForumThread(
        id: 501,
        boardId: 30,
        title: '主题',
        uri: _uri('forum.php?mod=viewthread&tid=501&mobile=2'),
      ),
      posts: <ForumPost>[
        ForumPost(
          id: 9001,
          threadId: 501,
          floor: 1,
          authorId: 76,
          authorUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=space&uid=76&mobile=2',
          ),
          author: '作者',
          timeLabel: '刚刚',
          messageHtml: '<a href="forum.php?formhash=secret&pid=9001">正文</a>',
          contentBlocks: <ForumPostContentBlock>[
            ForumPostQuoteBlock(
              inlines: <ForumPostInline>[
                const ForumPostTextInline(text: '引用', bold: true),
                ForumPostLinkInline(
                  label: '楼层',
                  uri: _uri(
                    'forum.php?mod=redirect&goto=findpost&'
                    'ptid=501&pid=9001&mobile=2',
                  ),
                  kind: ForumPostLinkKind.internalPost,
                  threadId: 501,
                  postId: 9001,
                ),
                ForumPostImageInline(
                  uri: _uri(
                    'data/attachment/forum/image.png?token=image-secret',
                  ),
                ),
                ForumPostLinkInline(
                  label: '外链',
                  uri: Uri.parse('https://example.org/public'),
                  kind: ForumPostLinkKind.external,
                ),
              ],
            ),
          ],
          comments: <ForumPostComment>[
            ForumPostComment(
              id: 7001,
              threadId: 501,
              postId: 9001,
              authorId: 77,
              authorUri: Uri.parse(
                'https://bbs.yamibo.com/home.php?mod=space&uid=77&mobile=2',
              ),
              author: '点评用户',
              avatarUri: _uri(
                'uc_server/avatar.php?uid=77&formhash=comment-secret',
              ),
              timeLabel: '刚刚',
              contentBlocks: const <ForumPostContentBlock>[
                ForumPostParagraphBlock(
                  inlines: <ForumPostInline>[
                    ForumPostTextInline(text: '原生点评'),
                  ],
                ),
              ],
            ),
          ],
          ratingSummary: ForumPostRatingSummary(
            participantCount: 2,
            totals: const <ForumPostRatingScore>[
              ForumPostRatingScore(credit: '积分', value: 6),
            ],
            entries: <ForumPostRatingEntry>[
              ForumPostRatingEntry(
                authorId: 78,
                authorUri: Uri.parse(
                  'https://bbs.yamibo.com/home.php?mod=space&uid=78&mobile=2',
                ),
                author: '评分用户',
                avatarUri: _uri(
                  'uc_server/avatar.php?uid=78&token=rating-secret',
                ),
                scores: const <ForumPostRatingScore>[
                  ForumPostRatingScore(credit: '积分', value: 5),
                ],
                reason: '理由',
              ),
            ],
          ),
          uri: _uri('forum.php?mod=viewthread&tid=501&mobile=2#pid9001'),
          quoteUri: _uri('forum.php?mod=post&action=reply&formhash=secret'),
          ratingsUri: _uri(
            'forum.php?mod=misc&action=viewratings&tid=501&pid=9001&mobile=2',
          ),
        ),
      ],
      readingOptions: const <ForumRouteOption>[],
      cursor: ForumPageCursor(
        currentPage: 1,
        totalPages: 1,
        sourceUri: _uri('forum.php?mod=viewthread&tid=501&mobile=2'),
      ),
    );

    final Map<String, dynamic> encoded = codec.encodeThreadPage(source);
    final ForumThreadPage decoded = codec.decodeThreadPage(encoded);

    expect(encoded.toString(), isNot(contains('secret')));
    expect(decoded.posts.single.quoteUri, isNull);
    expect(decoded.posts.single.authorUri?.queryParameters['uid'], '76');
    expect(decoded.posts.single.messageHtml, contains('正文'));
    expect(
      decoded.posts.single.contentBlocks.single,
      isA<ForumPostQuoteBlock>(),
    );
    final List<ForumPostInline> inlines =
        decoded.posts.single.contentBlocks.single.inlines;
    expect(inlines.first, isA<ForumPostTextInline>());
    expect((inlines.first as ForumPostTextInline).bold, isTrue);
    expect(inlines[1], isA<ForumPostLinkInline>());
    expect((inlines[1] as ForumPostLinkInline).postId, 9001);
    expect(inlines[2], isA<ForumPostImageInline>());
    expect(
      (inlines[2] as ForumPostImageInline).uri.toString(),
      isNot(contains('token')),
    );
    expect(
      (inlines.last as ForumPostLinkInline).kind,
      ForumPostLinkKind.external,
    );
    expect(decoded.posts.single.comments.single.authorId, 77);
    expect(
      decoded.posts.single.comments.single.authorUri?.queryParameters['uid'],
      '77',
    );
    expect(
      decoded.posts.single.comments.single.avatarUri.toString(),
      isNot(contains('formhash')),
    );
    expect(
      decoded
          .posts
          .single
          .comments
          .single
          .contentBlocks
          .single
          .inlines
          .single,
      isA<ForumPostTextInline>(),
    );
    expect(decoded.posts.single.ratingSummary?.participantCount, 2);
    expect(
      decoded
          .posts
          .single
          .ratingSummary
          ?.entries
          .single
          .authorUri
          ?.queryParameters['uid'],
      '78',
    );
    expect(
      decoded.posts.single.ratingSummary?.entries.single.scores.single.value,
      5,
    );
    expect(
      decoded.posts.single.ratingSummary?.entries.single.avatarUri.toString(),
      isNot(contains('token')),
    );
    expect(decoded.posts.single.ratingsUri, isNull);
    expect(decoded.thread.id, 501);

    final Map<String, dynamic> encodedPost =
        (encoded['posts'] as List<dynamic>).single as Map<String, dynamic>;
    encodedPost['authorUri'] =
        'https://bbs.yamibo.com/home.php?mod=space&uid=999&mobile=2';
    expect(
      () => codec.decodeThreadPage(encoded),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('主题缓存拒绝跨楼层点评和无效评分摘要', () {
    final Map<String, dynamic> encoded = codec.encodeThreadPage(
      ForumThreadPage(
        thread: ForumThread(
          id: 501,
          boardId: 30,
          title: '主题',
          uri: _uri('forum.php?mod=viewthread&tid=501&mobile=2'),
        ),
        posts: <ForumPost>[
          ForumPost(
            id: 9001,
            threadId: 501,
            floor: 1,
            author: '作者',
            timeLabel: '',
            messageHtml: '正文',
            uri: _uri('forum.php?mod=viewthread&tid=501&mobile=2#pid9001'),
          ),
        ],
        readingOptions: const <ForumRouteOption>[],
        cursor: ForumPageCursor(
          currentPage: 1,
          totalPages: 1,
          sourceUri: _uri('forum.php?mod=viewthread&tid=501&mobile=2'),
        ),
      ),
    );
    final Map<String, dynamic> post =
        (encoded['posts'] as List<dynamic>).single as Map<String, dynamic>;
    post['comments'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 1,
        'threadId': 501,
        'postId': 9002,
        'author': '伪造点评',
        'contentBlocks': <dynamic>[],
      },
    ];

    expect(
      () => codec.decodeThreadPage(encoded),
      throwsA(isA<ForumParseException>()),
    );

    post['comments'] = <dynamic>[];
    post['ratingSummary'] = <String, dynamic>{
      'participantCount': 0,
      'totals': <dynamic>[],
      'entries': <dynamic>[],
    };
    expect(
      () => codec.decodeThreadPage(encoded),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('缓存拒绝伪造正文 URI 并将不安全链接降级为文本', () {
    final Map<String, dynamic> encoded = codec.encodeThreadPage(
      ForumThreadPage(
        thread: ForumThread(
          id: 501,
          boardId: 30,
          title: '主题',
          uri: _uri('forum.php?mod=viewthread&tid=501&mobile=2'),
        ),
        posts: <ForumPost>[
          ForumPost(
            id: 1,
            threadId: 501,
            floor: 1,
            author: '作者',
            timeLabel: '',
            messageHtml: '<form>secret</form><p onclick="run()">正文</p>',
            contentBlocks: <ForumPostContentBlock>[
              ForumPostParagraphBlock(
                inlines: <ForumPostInline>[
                  ForumPostLinkInline(
                    label: '认证外链',
                    uri: Uri.parse('https://example.org/?access_token=secret'),
                    kind: ForumPostLinkKind.external,
                  ),
                ],
              ),
            ],
            uri: _uri('forum.php?mod=viewthread&tid=501&mobile=2#pid1'),
          ),
        ],
        readingOptions: const <ForumRouteOption>[],
        cursor: ForumPageCursor(
          currentPage: 1,
          totalPages: 1,
          sourceUri: _uri('forum.php?mod=viewthread&tid=501&mobile=2'),
        ),
      ),
    );

    expect(encoded.toString(), isNot(contains('secret')));
    expect(encoded.toString(), isNot(contains('onclick')));
    expect(
      codec
          .decodeThreadPage(encoded)
          .posts
          .single
          .contentBlocks
          .single
          .inlines
          .single,
      isA<ForumPostTextInline>(),
    );

    final Map<String, dynamic> post =
        (encoded['posts'] as List<dynamic>).single as Map<String, dynamic>;
    final Map<String, dynamic> block =
        (post['contentBlocks'] as List<dynamic>).single as Map<String, dynamic>;
    (block['inlines'] as List<dynamic>)[0] = <String, dynamic>{
      'kind': 'image',
      'uri': 'https://evil.example/image.png',
    };
    expect(
      () => codec.decodeThreadPage(encoded),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('缓存保留公告目标类型并拒绝不安全 URI 或旧版本', () {
    final ForumBoardPage page = ForumBoardPage(
      board: ForumBoardNode(
        id: 30,
        name: '漫画区',
        uri: _uri('forum.php?mod=forumdisplay&fid=30&mobile=2'),
      ),
      threads: <ForumThreadSummary>[
        ForumThreadSummary(
          id: 7,
          boardId: 30,
          title: '公告',
          uri: _uri('forum.php?mod=announcement&id=7'),
          targetKind: ForumThreadTargetKind.announcement,
        ),
      ],
      filters: const <ForumRouteOption>[],
      cursor: ForumPageCursor(
        currentPage: 1,
        totalPages: 1,
        sourceUri: _uri('forum.php?mod=forumdisplay&fid=30&mobile=2'),
      ),
      favoriteUri: _uri(
        'home.php?mod=spacecp&ac=favorite&type=forum&id=30&'
        'handlekey=opaque-fresh-only&mobile=2',
      ),
    );

    final Map<String, dynamic> encoded = codec.encodeBoardPage(page);
    final ForumBoardPage decoded = codec.decodeBoardPage(encoded);
    expect(
      decoded.threads.single.targetKind,
      ForumThreadTargetKind.announcement,
    );
    expect(encoded.toString(), isNot(contains('opaque-fresh-only')));
    expect(decoded.favoriteUri, isNull);

    encoded['board'] = <String, dynamic>{
      ...(encoded['board'] as Map<String, dynamic>),
      'uri': 'https://evil.example/forum.php',
    };
    expect(
      () => codec.decodeBoardPage(encoded),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => codec.decodeIndex(<String, dynamic>{'version': 1, 'kind': 'index'}),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('版块缓存保留作者资料并拒绝作者 uid 不一致', () {
    final ForumBoardPage page = ForumBoardPage(
      board: ForumBoardNode(
        id: 30,
        name: '漫画区',
        uri: _uri('forum.php?mod=forumdisplay&fid=30&mobile=2'),
      ),
      threads: <ForumThreadSummary>[
        ForumThreadSummary(
          id: 8,
          boardId: 30,
          title: '主题',
          uri: _uri('forum.php?mod=viewthread&tid=8&mobile=2'),
          author: '作者',
          authorId: 77,
          authorUri: _uri('home.php?mod=space&uid=77&mobile=2'),
        ),
      ],
      filters: const <ForumRouteOption>[],
      cursor: ForumPageCursor(
        currentPage: 1,
        totalPages: 1,
        sourceUri: _uri('forum.php?mod=forumdisplay&fid=30&mobile=2'),
      ),
    );

    final Map<String, dynamic> encoded = codec.encodeBoardPage(page);
    final ForumBoardPage decoded = codec.decodeBoardPage(encoded);
    expect(decoded.threads.single.authorId, 77);
    expect(decoded.threads.single.authorUri?.queryParameters['uid'], '77');

    final Map<String, dynamic> thread =
        (encoded['threads'] as List<dynamic>).single as Map<String, dynamic>;
    thread['authorUri'] =
        'https://bbs.yamibo.com/home.php?mod=space&uid=88&mobile=2';
    expect(
      () => codec.decodeBoardPage(encoded),
      throwsA(isA<ForumParseException>()),
    );
  });
}

Uri _uri(String path) => Uri.parse('https://bbs.yamibo.com/').resolve(path);
