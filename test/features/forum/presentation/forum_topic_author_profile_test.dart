import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/domain/forum_models.dart' as domain;
import 'package:x300/features/forum/presentation/forum_topic_page.dart';

class _MockReadRepository extends Mock implements ForumReadRepository {}

void main() {
  late _MockReadRepository readRepository;
  late Uri topicUri;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://bbs.yamibo.com/'));
  });

  setUp(() {
    readRepository = _MockReadRepository();
    topicUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&mobile=2',
    );
  });

  testWidgets('楼层、点评和评分的可信作者进入资料页，无合同作者只保留文字', (
    WidgetTester tester,
  ) async {
    final Uri postAuthorUri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&uid=7&mobile=2',
    );
    final Uri commentAuthorUri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&uid=8&mobile=2',
    );
    final Uri ratingAuthorUri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&uid=9&mobile=2',
    );
    final domain.ForumThreadPage page = domain.ForumThreadPage(
      thread: domain.ForumThread(
        id: 100,
        boardId: 41,
        title: '测试主题',
        uri: topicUri,
        author: '楼主',
        authorId: 7,
      ),
      posts: <domain.ForumPost>[
        domain.ForumPost(
          id: 201,
          threadId: 100,
          floor: 1,
          author: '楼主',
          authorId: 7,
          authorUri: postAuthorUri,
          timeLabel: '',
          messageHtml: '',
          uri: topicUri.replace(fragment: 'pid201'),
          contentBlocks: const <domain.ForumPostContentBlock>[
            domain.ForumPostParagraphBlock(
              inlines: <domain.ForumPostInline>[
                domain.ForumPostTextInline(text: '楼主正文'),
              ],
            ),
          ],
          comments: <domain.ForumPostComment>[
            domain.ForumPostComment(
              id: 81,
              threadId: 100,
              postId: 201,
              authorId: 8,
              authorUri: commentAuthorUri,
              author: '点评用户',
              timeLabel: '',
              contentBlocks: const <domain.ForumPostContentBlock>[
                domain.ForumPostParagraphBlock(
                  inlines: <domain.ForumPostInline>[
                    domain.ForumPostTextInline(text: '点评正文'),
                  ],
                ),
              ],
            ),
          ],
          ratingSummary: domain.ForumPostRatingSummary(
            participantCount: 1,
            totals: const <domain.ForumPostRatingScore>[
              domain.ForumPostRatingScore(credit: '积分', value: 5),
            ],
            entries: <domain.ForumPostRatingEntry>[
              domain.ForumPostRatingEntry(
                authorId: 9,
                authorUri: ratingAuthorUri,
                author: '评分用户',
                scores: const <domain.ForumPostRatingScore>[
                  domain.ForumPostRatingScore(credit: '积分', value: 5),
                ],
              ),
            ],
          ),
          isOriginalPoster: true,
        ),
        domain.ForumPost(
          id: 202,
          threadId: 100,
          floor: 2,
          author: '匿名用户',
          timeLabel: '',
          messageHtml: '',
          uri: topicUri.replace(fragment: 'pid202'),
          contentBlocks: const <domain.ForumPostContentBlock>[
            domain.ForumPostParagraphBlock(
              inlines: <domain.ForumPostInline>[
                domain.ForumPostTextInline(text: '无资料楼层'),
              ],
            ),
          ],
        ),
      ],
      readingOptions: const <domain.ForumRouteOption>[],
      cursor: domain.ForumPageCursor(
        currentPage: 1,
        totalPages: 1,
        sourceUri: topicUri,
      ),
    );
    when(
      () => readRepository.loadThreadAtPost(threadId: 100, postId: 201),
    ).thenAnswer((_) async => page);

    final List<(Uri, int)> opened = <(Uri, int)>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumReadRepositoryProvider.overrideWithValue(readRepository),
        ],
        child: MaterialApp(
          home: ForumTopicPage(
            thread: domain.ForumThreadSummary(
              id: 100,
              boardId: 41,
              title: '测试主题',
              uri: topicUri,
            ),
            focusedPostId: 201,
            onOpenAuthor: (Uri uri, int userId) => opened.add((uri, userId)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('forum-topic-author-201')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('forum-topic-author-202')), findsNothing);
    expect(find.byKey(const ValueKey<String>('forum-comment-author-81')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('forum-rating-author-9-0')), findsOneWidget);

    await tester.tap(find.text('楼主正文'));
    expect(opened, isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('forum-topic-author-201')));
    await tester.tap(find.byKey(const ValueKey<String>('forum-comment-author-81')));
    await tester.tap(find.byKey(const ValueKey<String>('forum-rating-author-9-0')));
    expect(opened, <(Uri, int)>[
      (postAuthorUri, 7),
      (commentAuthorUri, 8),
      (ratingAuthorUri, 9),
    ]);
  });
}
