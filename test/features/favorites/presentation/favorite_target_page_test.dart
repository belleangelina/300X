import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/favorites/data/favorite_target_repository.dart';
import 'package:x300/features/favorites/domain/favorite_target_models.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/favorites/presentation/favorite_target_page.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

class _MockFavoriteTargetRepository extends Mock
    implements FavoriteTargetRepository {}

class _MockForumClient extends Mock implements ForumClient {}

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      FavoriteGroupPage(
        groupId: 1,
        title: '占位',
        boards: <ForumBoardNode>[],
        currentPage: 1,
        sourceUri: Uri.parse('https://bbs.yamibo.com/group.php?gid=1&mobile=2'),
      ),
    );
  });

  testWidgets('群组分类连续列表可原生打开版块并按服务端 URI 翻页', (WidgetTester tester) async {
    final _MockFavoriteTargetRepository repository =
        _MockFavoriteTargetRepository();
    final List<ForumBoardNode> opened = <ForumBoardNode>[];
    final Uri nextUri = _groupItem.targetUri!.replace(
      queryParameters: <String, String>{
        ..._groupItem.targetUri!.queryParameters,
        'orderby': 'displayorder',
        'page': '2',
      },
    );
    final FavoriteGroupPage first = FavoriteGroupPage(
      groupId: 8,
      title: '群组分类',
      boards: List<ForumBoardNode>.generate(
        20,
        (int index) => _board(80 + index, index == 0 ? '版块甲' : '版块 $index'),
      ),
      currentPage: 1,
      sourceUri: _groupItem.targetUri!,
      nextPageUri: nextUri,
    );
    final FavoriteGroupPage second = FavoriteGroupPage(
      groupId: 8,
      title: '群组分类',
      boards: <ForumBoardNode>[_board(180, '版块乙')],
      currentPage: 2,
      sourceUri: nextUri,
    );
    when(() => repository.load(_groupItem)).thenAnswer((_) async => first);
    when(() => repository.loadNextGroup(first)).thenAnswer((_) async => second);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteTargetRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: FavoriteTargetPage(item: _groupItem, onOpenBoard: opened.add),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('版块甲'), findsOneWidget);
    await tester.tap(find.text('版块甲'));
    expect(opened.single.id, 80);

    await tester.drag(
      find.byKey(const ValueKey<String>('favorite-group-list-8')),
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    expect(find.text('版块乙'), findsOneWidget);
    verify(() => repository.loadNextGroup(first)).called(1);
  });

  testWidgets('日志展示结构化正文评论且站内异构链接继续原生路由', (WidgetTester tester) async {
    final _MockFavoriteTargetRepository repository =
        _MockFavoriteTargetRepository();
    final List<RawFavoriteItem> opened = <RawFavoriteItem>[];
    final RawFavoriteItem albumLink = RawFavoriteItem(
      categoryKey: 'internal-link',
      title: '相册链接',
      targetKind: RawFavoriteTargetKind.album,
      targetUri: Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=space&do=album&uid=7&id=92&mobile=2',
      ),
      userId: 7,
      contentId: 92,
    );
    when(() => repository.load(_blogItem)).thenAnswer(
      (_) async => FavoriteBlog(
        blogId: 91,
        ownerUserId: 7,
        title: '日志标题',
        metadata: '时间',
        contentBlocks: const <ForumPostContentBlock>[
          ForumPostParagraphBlock(
            inlines: <ForumPostInline>[ForumPostTextInline(text: '日志正文')],
          ),
        ],
        comments: const <FavoriteBlogComment>[
          FavoriteBlogComment(
            blocks: <ForumPostContentBlock>[
              ForumPostParagraphBlock(
                inlines: <ForumPostInline>[ForumPostTextInline(text: '评论正文')],
              ),
            ],
          ),
        ],
        nativeLinks: <FavoriteNativeLink>[
          FavoriteNativeLink(label: '相册链接', item: albumLink),
        ],
        externalImageUris: const <Uri>[],
        sourceUri: _blogItem.targetUri!,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteTargetRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: FavoriteTargetPage(item: _blogItem, onOpenTarget: opened.add),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('日志标题'), findsOneWidget);
    expect(find.text('日志正文'), findsOneWidget);
    expect(find.text('评论正文'), findsOneWidget);
    await tester.tap(find.text('相册链接'));
    expect(opened.single.targetKind, RawFavoriteTargetKind.album);
    expect(opened.single.contentId, 92);
  });

  testWidgets('相册空图片仍展示元数据且不伪造媒体', (WidgetTester tester) async {
    final _MockFavoriteTargetRepository repository =
        _MockFavoriteTargetRepository();
    when(() => repository.load(_albumItem)).thenAnswer(
      (_) async => FavoriteAlbum(
        albumId: 92,
        ownerUserId: 7,
        title: '相册标题',
        description: '相册说明',
        images: const <FavoriteAlbumImage>[],
        sourceUri: _albumItem.targetUri!,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteTargetRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(home: FavoriteTargetPage(item: _albumItem)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('相册标题'), findsOneWidget);
    expect(find.text('相册说明'), findsOneWidget);
    expect(find.text('相册暂无图片'), findsOneWidget);
  });

  testWidgets('外域相册媒体通过公开通道读取且不携论坛 Referer', (WidgetTester tester) async {
    final _MockFavoriteTargetRepository repository =
        _MockFavoriteTargetRepository();
    final _MockForumClient client = _MockForumClient();
    final _MockAuthRepository auth = _MockAuthRepository();
    final Uri externalImage = Uri.parse('https://media.example.test/image.png');
    when(auth.restoreSession).thenAnswer(
      (_) async => const AuthState.authenticated('测试账号', userId: 42),
    );
    when(() => client.withActiveAccount<Uint8List>(42, any())).thenAnswer((
      Invocation invocation,
    ) {
      final action =
          invocation.positionalArguments[1] as Future<Uint8List> Function();
      return action();
    });
    when(
      () => client.getBytes(externalImage, referer: null),
    ).thenAnswer((_) async => base64Decode(_onePixelPng));
    when(() => repository.load(_albumItem)).thenAnswer(
      (_) async => FavoriteAlbum(
        albumId: 92,
        ownerUserId: 7,
        title: '外站图片相册',
        description: '',
        images: <FavoriteAlbumImage>[
          FavoriteAlbumImage(
            imageUri: externalImage,
            photoUri: Uri.parse(
              'https://bbs.yamibo.com/home.php?mod=space&do=album&uid=7&picid=1&mobile=2',
            ),
          ),
        ],
        sourceUri: _albumItem.targetUri!,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteTargetRepositoryProvider.overrideWithValue(repository),
          forumClientProvider.overrideWithValue(client),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: MaterialApp(home: FavoriteTargetPage(item: _albumItem)),
      ),
    );
    await tester.pumpAndSettle();

    verify(() => client.getBytes(externalImage, referer: null)).called(1);
  });
}

ForumBoardNode _board(int id, String name) {
  return ForumBoardNode(
    id: id,
    name: name,
    uri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&action=list&fid=$id&mobile=2',
    ),
  );
}

final RawFavoriteItem _groupItem = RawFavoriteItem(
  categoryKey: 'group',
  title: '群组分类',
  targetKind: RawFavoriteTargetKind.groupCategory,
  targetUri: Uri.parse('https://bbs.yamibo.com/group.php?gid=8&mobile=2'),
  groupId: 8,
);

final RawFavoriteItem _blogItem = RawFavoriteItem(
  categoryKey: 'blog',
  title: '日志',
  targetKind: RawFavoriteTargetKind.blog,
  targetUri: Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=space&do=blog&uid=7&id=91&mobile=2',
  ),
  userId: 7,
  contentId: 91,
);

final RawFavoriteItem _albumItem = RawFavoriteItem(
  categoryKey: 'album',
  title: '相册',
  targetKind: RawFavoriteTargetKind.album,
  targetUri: Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=space&do=album&uid=7&id=92&mobile=2',
  ),
  userId: 7,
  contentId: 92,
);

const String _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
