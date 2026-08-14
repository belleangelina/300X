import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/favorites/data/favorite_target_contract.dart';
import 'package:x300/features/favorites/data/favorite_target_parser.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

void main() {
  const FavoriteTargetContract contract = FavoriteTargetContract();
  const FavoriteTargetParser parser = FavoriteTargetParser();

  group('异构收藏目标契约', () {
    test('只接受同源 HTTPS、mobile=2、唯一精确参数', () {
      expect(
        contract.describe(_blogUri),
        isA<FavoriteTargetDescriptor>()
            .having(
              (FavoriteTargetDescriptor value) => value.kind,
              'kind',
              RawFavoriteTargetKind.blog,
            )
            .having(
              (FavoriteTargetDescriptor value) => value.targetId,
              'id',
              91,
            )
            .having(
              (FavoriteTargetDescriptor value) => value.ownerUserId,
              'uid',
              7,
            ),
      );
      for (final String value in <String>[
        'http://bbs.yamibo.com/home.php?mod=space&do=blog&uid=7&id=91&mobile=2',
        'https://evil.example/home.php?mod=space&do=blog&uid=7&id=91&mobile=2',
        'https://bbs.yamibo.com/home.php?mod=space&do=blog&uid=7&id=91',
        'https://bbs.yamibo.com/home.php?mod=space&do=blog&uid=7&id=91&mobile=2&op=delete',
        'https://bbs.yamibo.com/home.php?mod=space&do=blog&uid=7&id=91&mobile=2&uid[]=7',
        'https://bbs.yamibo.com/home.php?mod=space&do=blog&uid=7&uid=8&id=91&mobile=2',
      ]) {
        expect(contract.describe(Uri.parse(value)), isNull, reason: value);
      }
    });

    test('条目字段必须与 URI 目标一致', () {
      expect(
        () => contract.requireItem(
          RawFavoriteItem(
            categoryKey: 'blog',
            title: '日志',
            targetKind: RawFavoriteTargetKind.blog,
            targetUri: _blogUri,
            userId: 7,
            contentId: 92,
          ),
        ),
        throwsA(isA<ForumParseException>()),
      );
    });

    test('用户空间只接受精确移动 uid 目标', () {
      final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=space&uid=77&mobile=2',
      );
      final FavoriteTargetDescriptor? descriptor = contract.describe(uri);
      expect(descriptor?.kind, RawFavoriteTargetKind.userSpace);
      expect(descriptor?.targetId, 77);
      expect(descriptor?.ownerUserId, 77);
      expect(
        contract.describe(uri.replace(queryParameters: <String, String>{
          ...uri.queryParameters,
          'op': 'delete',
        })),
        isNull,
      );
    });
  });

  test('群组收藏跳转必须落到同 fid 的移动版块', () {
    final String html = _fixture('group_board_mobile.html');
    final result = parser.parseGroupBoardResult(
      html,
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&action=list&fid=80&mobile=2',
      ),
      expectedBoardId: 80,
      fallbackTitle: '群组收藏',
    );
    expect(result.board.id, 80);
    expect(result.board.uri.queryParameters['action'], 'list');

    expect(
      () => parser.parseGroupBoardResult(
        html,
        Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=forumdisplay&action=list&fid=81&mobile=2',
        ),
        expectedBoardId: 80,
        fallbackTitle: '群组收藏',
      ),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('群组分类按真实 murl 结构解析版块及服务端下一页', () {
    final page = parser.parseGroupPage(
      _fixture('group_category_mobile.html'),
      _groupUri,
      expectedGroupId: 8,
      fallbackTitle: '群组分类',
    );
    expect(page.boards.map((value) => value.id), <int>[80, 81]);
    expect(page.boards.first.name, '群组版块甲');
    expect(
      page.nextPageUri?.queryParameters,
      containsPair('orderby', 'displayorder'),
    );
    expect(page.nextPageUri?.queryParameters, containsPair('page', '2'));
  });

  test('群组分类拒绝跨 gid、附加动作和漂移 body', () {
    final String fixture = _fixture('group_category_mobile.html');
    for (final String html in <String>[
      fixture.replaceFirst('gid=8', 'gid=9'),
      fixture.replaceFirst('orderby=displayorder', 'orderby=unknown'),
      fixture.replaceFirst(
        'fid=80&amp;mobile=2',
        'fid=80&amp;mobile=2&amp;op=delete',
      ),
      fixture.replaceFirst('id="group"', 'id="forum"'),
    ]) {
      expect(
        () => parser.parseGroupPage(
          html,
          _groupUri,
          expectedGroupId: 8,
          fallbackTitle: '群组分类',
        ),
        throwsA(isA<ForumParseException>()),
      );
    }
  });

  test('日志原生解析正文、评论、站内目标和外站图片', () {
    final blog = parser.parseBlog(
      _fixture('blog_mobile.html'),
      _blogUri,
      expectedBlogId: 91,
      expectedOwnerUserId: 7,
    );
    expect(blog.title, '脱敏日志标题');
    expect(blog.contentBlocks, isNotEmpty);
    expect(blog.comments, hasLength(2));
    expect(blog.comments.first.author, '评论者甲');
    expect(blog.comments.first.timeLabel, '时间甲');
    expect(
      blog.nativeLinks.map((value) => value.item.targetKind),
      <RawFavoriteTargetKind>[
        RawFavoriteTargetKind.thread,
        RawFavoriteTargetKind.album,
      ],
    );
    expect(blog.externalImageUris.single.host, 'media.example.test');
    expect(
      blog.contentBlocks
          .expand((ForumPostContentBlock value) => value.inlines)
          .whereType<ForumPostLinkInline>()
          .single
          .threadId,
      501,
    );
  });

  test('日志拒绝错误 uid/id、缺失目标表单和桌面 body', () {
    final String fixture = _fixture('blog_mobile.html');
    for (final String html in <String>[
      fixture.replaceFirst('quickcommentform_91', 'quickcommentform_92'),
      fixture.replaceFirst('id="home"', 'id="nv_home"'),
    ]) {
      expect(
        () => parser.parseBlog(
          html,
          _blogUri,
          expectedBlogId: 91,
          expectedOwnerUserId: 7,
        ),
        throwsA(isA<ForumParseException>()),
      );
    }
    expect(
      () => parser.parseBlog(
        fixture,
        _blogUri.replace(
          queryParameters: <String, String>{
            ..._blogUri.queryParameters,
            'uid': '8',
          },
        ),
        expectedBlogId: 91,
        expectedOwnerUserId: 7,
      ),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('相册解析元数据、站内及外站 HTTPS 图片', () {
    final album = parser.parseAlbum(
      _fixture('album_mobile.html'),
      _albumUri,
      expectedAlbumId: 92,
      expectedOwnerUserId: 7,
    );
    expect(album.title, '脱敏相册');
    expect(album.description, '相册简介');
    expect(album.images, hasLength(2));
    expect(album.images.first.imageUri.host, 'bbs.yamibo.com');
    expect(album.images.last.imageUri.host, 'media.example.test');
    expect(album.images.last.photoUri.queryParameters['picid'], '302');
  });

  test('相册拒绝图片详情跨 uid、附加动作及非 HTTPS 媒体', () {
    final String fixture = _fixture('album_mobile.html');
    for (final String html in <String>[
      fixture.replaceFirst('uid=7&amp;picid=301', 'uid=8&amp;picid=301'),
      fixture.replaceFirst(
        'picid=301&amp;mobile=2',
        'picid=301&amp;mobile=2&amp;op=delete',
      ),
      fixture.replaceFirst(
        'https://media.example.test/b.jpg',
        'http://media.example.test/b.jpg',
      ),
    ]) {
      expect(
        () => parser.parseAlbum(
          html,
          _albumUri,
          expectedAlbumId: 92,
          expectedOwnerUserId: 7,
        ),
        throwsA(isA<ForumParseException>()),
      );
    }
  });
}

String _fixture(String name) {
  return File('test/fixtures/favorites/$name').readAsStringSync();
}

final Uri _groupUri = Uri.parse(
  'https://bbs.yamibo.com/group.php?gid=8&mobile=2',
);
final Uri _blogUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=space&do=blog&uid=7&id=91&mobile=2',
);
final Uri _albumUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=space&do=album&uid=7&id=92&mobile=2',
);
