import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';
import 'package:x300/features/forum/data/forum_search_repository.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/forum/domain/forum_search_models.dart';
import 'package:x300/features/forum/presentation/forum_search_page.dart';

class _MockForumClient extends Mock implements ForumClient {}

class _MockForumLocalRepository extends Mock implements ForumLocalRepository {}

class _FakeForumThreadSearchRepository extends ForumThreadSearchRepository {
  _FakeForumThreadSearchRepository(this.form, this.page)
    : super(_MockForumClient(), _MockForumLocalRepository(), 42);

  final ForumThreadSearchForm form;
  final ForumThreadSearchPage page;
  String? submittedKeyword;
  Uri? submittedFormUri;

  @override
  Future<ForumThreadSearchForm> loadForm([Uri? sourceUri]) async => form;

  @override
  Future<ForumThreadSearchPage> search({
    required String keyword,
    Uri? formUri,
  }) async {
    submittedKeyword = keyword;
    submittedFormUri = formUri;
    return page;
  }
}

void main() {
  testWidgets('展示当前版块范围并通过稳定标识回调搜索结果', (WidgetTester tester) async {
    final Uri formUri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=30&mobile=2',
    );
    final Uri resultUri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=forum&searchid=88&mobile=2',
    );
    final ForumThreadSearchForm form = ForumThreadSearchForm(
      sourceUri: formUri,
      actionUri: Uri.parse('https://bbs.yamibo.com/search.php?mod=forum'),
      keywordFieldName: 'q',
      hiddenFields: const <String, List<String>>{
        'srhfid': <String>['30'],
      },
      scopeOptions: const <ForumThreadSearchScopeOption>[],
      boardId: 30,
    );
    final ForumThreadSearchHit hit = ForumThreadSearchHit(
      threadId: 501,
      boardId: 30,
      postId: 9001,
      title: '论坛搜索结果',
      uri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=501&pid=9001&mobile=2',
      ),
      authorId: 7,
      authorUri: Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=space&uid=7&mobile=2',
      ),
      author: '作者甲',
      boardName: '漫画区',
    );
    final ForumThreadSearchPage page = ForumThreadSearchPage(
      keyword: '百合',
      boardId: 30,
      hits: <ForumThreadSearchHit>[hit],
      cursor: ForumPageCursor(
        currentPage: 1,
        totalPages: 1,
        sourceUri: resultUri,
      ),
      sourceUri: resultUri,
    );
    final _FakeForumThreadSearchRepository repository =
        _FakeForumThreadSearchRepository(form, page);
    ForumThreadSearchHit? opened;
    ForumThreadSearchHit? openedAuthor;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumThreadSearchRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: ForumSearchPage(
            formUri: formUri,
            onOpenResult: (ForumThreadSearchHit value) => opened = value,
            onOpenAuthor: (ForumThreadSearchHit value) => openedAuthor = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前版块 · fid 30'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('forum-search-keyword')), '百合');
    await tester.tap(find.byKey(const Key('forum-search-submit')));
    await tester.pumpAndSettle();

    expect(find.text('论坛搜索结果'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('forum-search-author-7')));
    expect(openedAuthor?.authorId, 7);
    expect(repository.submittedKeyword, '百合');
    expect(repository.submittedFormUri, formUri);
    await tester.tap(find.text('论坛搜索结果'));
    expect(opened?.threadId, 501);
    expect(opened?.boardId, 30);
    expect(opened?.postId, 9001);
  });
}
