import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/favorites/data/favorite_target_repository.dart';
import 'package:x300/features/favorites/domain/favorite_target_models.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/forum/presentation/forum_board_page.dart'
    as forum_board_presentation;
import 'package:x300/features/forum/presentation/forum_topic_page.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

typedef FavoriteOpenThread =
    void Function(ForumThreadSummary thread, {int? focusedPostId});

class FavoriteTargetPage extends ConsumerStatefulWidget {
  const FavoriteTargetPage({
    required this.item,
    this.onOpenBoard,
    this.onOpenThread,
    this.onOpenTarget,
    super.key,
  });

  final RawFavoriteItem item;
  final ValueChanged<ForumBoardNode>? onOpenBoard;
  final FavoriteOpenThread? onOpenThread;
  final ValueChanged<RawFavoriteItem>? onOpenTarget;

  @override
  ConsumerState<FavoriteTargetPage> createState() => _FavoriteTargetPageState();
}

class _FavoriteTargetPageState extends ConsumerState<FavoriteTargetPage> {
  final ScrollController _scrollController = ScrollController();
  FavoriteTargetContent? _content;
  List<ForumBoardNode> _groupBoards = <ForumBoardNode>[];
  FavoriteGroupPage? _groupCursor;
  Object? _error;
  Object? _loadMoreError;
  bool _loading = true;
  bool _loadingMore = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant FavoriteTargetPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.targetKind == widget.item.targetKind &&
        oldWidget.item.targetUri == widget.item.targetUri) {
      return;
    }
    _content = null;
    _groupBoards = <ForumBoardNode>[];
    _groupCursor = null;
    _error = null;
    _loadMoreError = null;
    _loading = true;
    _loadingMore = false;
    _generation += 1;
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FavoriteTargetContent? content = _content;
    if (content is FavoriteGroupBoardTarget) {
      return forum_board_presentation.ForumBoardPage(
        key: ValueKey<String>('favorite-group-board-${content.board.id}'),
        board: content.board,
        onOpenThread: (ForumThreadSummary thread) => _openThread(thread),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_title(content))),
      body: _buildBody(content),
    );
  }

  Widget _buildBody(FavoriteTargetContent? content) {
    if (_loading && content == null) {
      return const AppLoadingView(message: '正在读取收藏内容');
    }
    if (_error != null && content == null) {
      return AppErrorView(message: '$_error', onRetry: _load);
    }
    return switch (content) {
      FavoriteGroupPage() => _buildGroup(content),
      FavoriteBlog() => _buildBlog(content),
      FavoriteAlbum() => _buildAlbum(content),
      FavoriteGroupBoardTarget() => const SizedBox.shrink(),
      null => AppEmptyView(message: '收藏内容不可用', onRefresh: _load),
    };
  }

  Widget _buildGroup(FavoriteGroupPage page) {
    final Widget list = RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: ValueKey<String>('favorite-group-list-${page.groupId}'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount:
            _groupBoards.length +
            (_loadingMore || _loadMoreError != null ? 1 : 0),
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (BuildContext context, int index) {
          if (index >= _groupBoards.length) {
            if (_loadMoreError != null) {
              return TextButton(
                key: const Key('favorite-group-load-more-retry'),
                onPressed: _loadMore,
                child: Text('加载下一页失败，点击重试：$_loadMoreError'),
              );
            }
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final ForumBoardNode board = _groupBoards[index];
          return ListTile(
            key: ValueKey<String>('favorite-group-board-${board.id}'),
            leading: const Icon(Icons.forum_outlined),
            title: Text(board.name),
            subtitle: board.description.isEmpty
                ? null
                : Text(
                    board.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openBoard(board),
          );
        },
      ),
    );
    if (!page.isFromCache) {
      return list;
    }
    return Column(
      children: <Widget>[
        const Material(
          color: Color(0xfffff3cd),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.cloud_off_outlined, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '论坛不可用，当前显示该账号的群组只读缓存',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  Widget _buildBlog(FavoriteBlog blog) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: ValueKey<String>('favorite-blog-${blog.blogId}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: <Widget>[
          Text(
            blog.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (blog.metadata.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              blog.metadata,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _FavoriteContentBlocks(
            blocks: blog.contentBlocks,
            referer: blog.sourceUri.toString(),
            onOpenLink: _openPostLink,
          ),
          for (final Uri uri in blog.externalImageUris) ...<Widget>[
            const SizedBox(height: 10),
            _EphemeralForumImage(
              key: ValueKey<String>('favorite-blog-external-image-$uri'),
              uri: uri,
              referer: blog.sourceUri.toString(),
            ),
          ],
          if (blog.nativeLinks.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            const Text(
              '站内链接',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final FavoriteNativeLink link in blog.nativeLinks)
              ListTile(
                key: ValueKey<String>(
                  'favorite-blog-native-link-${link.item.targetUri}',
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.link, size: 20),
                title: Text(link.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openRawTarget(link.item),
              ),
          ],
          const SizedBox(height: 18),
          Text(
            '评论 ${blog.comments.length}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (blog.comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('暂无评论', style: TextStyle(color: Colors.grey)),
            )
          else
            for (
              int index = 0;
              index < blog.comments.length;
              index++
            ) ...<Widget>[
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (blog.comments[index].author.isNotEmpty ||
                          blog
                              .comments[index]
                              .timeLabel
                              .isNotEmpty) ...<Widget>[
                        Text(
                          <String>[
                                blog.comments[index].author,
                                blog.comments[index].timeLabel,
                              ]
                              .where((String value) => value.isNotEmpty)
                              .join(' · '),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 5),
                      ],
                      if (blog.comments[index].blocks.isEmpty)
                        const Text('（无文字内容）')
                      else
                        _FavoriteContentBlocks(
                          blocks: blog.comments[index].blocks,
                          referer: blog.sourceUri.toString(),
                          onOpenLink: _openPostLink,
                        ),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildAlbum(FavoriteAlbum album) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: ValueKey<String>('favorite-album-${album.albumId}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
        children: <Widget>[
          Text(
            album.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (album.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(album.description),
          ],
          const SizedBox(height: 14),
          if (album.images.isEmpty)
            const SizedBox(height: 260, child: AppEmptyView(message: '相册暂无图片'))
          else
            for (final FavoriteAlbumImage image in album.images) ...<Widget>[
              Semantics(
                image: true,
                label: image.alt.isEmpty ? '相册图片' : image.alt,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _EphemeralForumImage(
                    key: ValueKey<String>(
                      'favorite-album-image-${image.photoUri}',
                    ),
                    uri: image.imageUri,
                    referer: album.sourceUri.toString(),
                  ),
                ),
              ),
              if (image.alt.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    image.alt,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }

  String _title(FavoriteTargetContent? content) {
    return switch (content) {
      FavoriteGroupPage() => content.title,
      FavoriteBlog() => '日志',
      FavoriteAlbum() => '相册',
      _ => widget.item.title,
    };
  }

  Future<void> _load() async {
    final int generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _loadMoreError = null;
      });
    }
    try {
      final FavoriteTargetContent content = await ref
          .read(favoriteTargetRepositoryProvider)
          .load(widget.item);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _content = content;
        _loading = false;
        if (content is FavoriteGroupPage) {
          _groupBoards = List<ForumBoardNode>.of(content.boards);
          _groupCursor = content;
        }
      });
    } on ForumSessionExpiredException {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _loading = false);
      ref.read(authControllerProvider.notifier).markSessionExpired();
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadMore() async {
    final FavoriteGroupPage? cursor = _groupCursor;
    if (_loadingMore || cursor?.hasNext != true) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    final int generation = _generation;
    try {
      final FavoriteGroupPage next = await ref
          .read(favoriteTargetRepositoryProvider)
          .loadNextGroup(cursor!);
      if (!mounted || generation != _generation) {
        return;
      }
      final Map<int, ForumBoardNode> merged = <int, ForumBoardNode>{
        for (final ForumBoardNode board in _groupBoards) board.id: board,
        for (final ForumBoardNode board in next.boards) board.id: board,
      };
      setState(() {
        _groupBoards = List<ForumBoardNode>.unmodifiable(merged.values);
        _groupCursor = next;
        _content = FavoriteGroupPage(
          groupId: next.groupId,
          title: next.title,
          boards: _groupBoards,
          currentPage: next.currentPage,
          sourceUri: next.sourceUri,
          nextPageUri: next.nextPageUri,
          isFromCache: next.isFromCache,
          cacheUpdatedAt: next.cacheUpdatedAt,
        );
        _loadingMore = false;
      });
    } on ForumSessionExpiredException {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _loadingMore = false);
      ref.read(authControllerProvider.notifier).markSessionExpired();
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loadingMore = false;
        _loadMoreError = error;
      });
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 320 ||
        _loadingMore ||
        _groupCursor?.hasNext != true) {
      return;
    }
    unawaited(_loadMore());
  }

  void _openBoard(ForumBoardNode board) {
    final ValueChanged<ForumBoardNode>? callback = widget.onOpenBoard;
    if (callback != null) {
      callback(board);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            forum_board_presentation.ForumBoardPage(board: board),
      ),
    );
  }

  void _openThread(ForumThreadSummary thread, {int? focusedPostId}) {
    final FavoriteOpenThread? callback = widget.onOpenThread;
    if (callback != null) {
      callback(thread, focusedPostId: focusedPostId);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ForumTopicPage(thread: thread, focusedPostId: focusedPostId),
      ),
    );
  }

  void _openRawTarget(RawFavoriteItem item) {
    switch (item.targetKind) {
      case RawFavoriteTargetKind.thread:
        final int? threadId = item.threadId;
        final Uri? uri = item.targetUri;
        if (threadId != null && uri != null) {
          _openThread(
            ForumThreadSummary(
              id: threadId,
              boardId: item.boardId ?? 0,
              title: item.title,
              uri: _withMobile(uri),
            ),
          );
          return;
        }
        _showMessage('该站内链接缺少主题编号');
        return;
      case RawFavoriteTargetKind.board:
        final int? boardId = item.boardId;
        final Uri? uri = item.targetUri;
        if (boardId != null && uri != null) {
          _openBoard(ForumBoardNode(id: boardId, name: item.title, uri: uri));
          return;
        }
        _showMessage('该站内链接缺少版块编号');
        return;
      case RawFavoriteTargetKind.groupBoard:
      case RawFavoriteTargetKind.groupCategory:
      case RawFavoriteTargetKind.blog:
      case RawFavoriteTargetKind.album:
        final ValueChanged<RawFavoriteItem>? callback = widget.onOpenTarget;
        if (callback != null) {
          callback(item);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => FavoriteTargetPage(item: item),
            ),
          );
        }
        return;
      case RawFavoriteTargetKind.userSpace:
      case RawFavoriteTargetKind.community:
      case RawFavoriteTargetKind.unknown:
        _showMessage('该站内链接缺少可验证的原生目标');
        return;
    }
  }

  void _openPostLink(ForumPostLinkInline link) {
    switch (link.kind) {
      case ForumPostLinkKind.internalThread:
      case ForumPostLinkKind.internalPost:
        final int? threadId = link.threadId;
        if (threadId == null || threadId <= 0) {
          _showMessage('该站内链接缺少主题编号');
          return;
        }
        _openThread(
          ForumThreadSummary(
            id: threadId,
            boardId: 0,
            title: link.label,
            uri: _withMobile(link.uri),
          ),
          focusedPostId: link.postId,
        );
        return;
      case ForumPostLinkKind.download:
      case ForumPostLinkKind.external:
        unawaited(_openExternal(link.uri));
        return;
    }
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showMessage('无法打开链接');
      }
    } on Object {
      _showMessage('无法打开链接');
    }
  }

  Uri _withMobile(Uri uri) {
    if (uri.queryParameters['mobile'] == '2') {
      return uri;
    }
    return uri.replace(
      queryParameters: <String, String>{...uri.queryParameters, 'mobile': '2'},
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FavoriteContentBlocks extends StatelessWidget {
  const _FavoriteContentBlocks({
    required this.blocks,
    required this.referer,
    required this.onOpenLink,
  });

  final List<ForumPostContentBlock> blocks;
  final String referer;
  final ValueChanged<ForumPostLinkInline> onOpenLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int index = 0; index < blocks.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: 9),
          _FavoriteContentBlock(
            block: blocks[index],
            referer: referer,
            onOpenLink: onOpenLink,
          ),
        ],
      ],
    );
  }
}

class _FavoriteContentBlock extends StatelessWidget {
  const _FavoriteContentBlock({
    required this.block,
    required this.referer,
    required this.onOpenLink,
  });

  final ForumPostContentBlock block;
  final String referer;
  final ValueChanged<ForumPostLinkInline> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final bool quote = block is ForumPostQuoteBlock;
    final bool code = block is ForumPostCodeBlock;
    final Widget content = _FavoriteInlineContent(
      inlines: block.inlines,
      referer: referer,
      onOpenLink: onOpenLink,
      baseStyle: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontFamily: code ? 'monospace' : null,
        fontSize: code ? 13 : 15,
        height: code ? 1.55 : 1.65,
      ),
    );
    if (!quote && !code) {
      return content;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: quote
            ? Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 3,
                ),
              )
            : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(padding: const EdgeInsets.all(10), child: content),
    );
  }
}

class _FavoriteInlineContent extends StatelessWidget {
  const _FavoriteInlineContent({
    required this.inlines,
    required this.referer,
    required this.onOpenLink,
    required this.baseStyle,
  });

  final List<ForumPostInline> inlines;
  final String referer;
  final ValueChanged<ForumPostLinkInline> onOpenLink;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    final List<ForumPostInline> textRun = <ForumPostInline>[];

    void flush() {
      if (textRun.isEmpty) {
        return;
      }
      children.add(
        SelectableText.rich(
          TextSpan(
            style: baseStyle,
            children: textRun
                .map((ForumPostInline value) => _span(context, value))
                .toList(growable: false),
          ),
        ),
      );
      textRun.clear();
    }

    for (final ForumPostInline inline in inlines) {
      if (inline is ForumPostImageInline && !inline.isEmoticon) {
        flush();
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: 8));
        }
        children.add(
          _EphemeralForumImage(
            key: ValueKey<String>('favorite-inline-image-${inline.uri}'),
            uri: inline.uri,
            referer: referer,
          ),
        );
      } else {
        textRun.add(inline);
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  InlineSpan _span(BuildContext context, ForumPostInline inline) {
    return switch (inline) {
      ForumPostTextInline() => TextSpan(
        text: inline.text,
        style: _style(
          bold: inline.bold,
          italic: inline.italic,
          code: inline.code,
        ),
      ),
      ForumPostLineBreakInline() => const TextSpan(text: '\n'),
      ForumPostImageInline() => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox(
          width: 24,
          height: 24,
          child: _EphemeralForumImage(uri: inline.uri, referer: referer),
        ),
      ),
      ForumPostLinkInline() => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: InkWell(
          onTap: () => onOpenLink(inline),
          child: Text(
            inline.label,
            style:
                _style(
                  bold: inline.bold,
                  italic: inline.italic,
                  code: inline.code,
                ).copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
          ),
        ),
      ),
    };
  }

  TextStyle _style({
    required bool bold,
    required bool italic,
    required bool code,
  }) {
    return baseStyle.copyWith(
      fontFamily: code ? 'monospace' : baseStyle.fontFamily,
      fontWeight: bold ? FontWeight.bold : baseStyle.fontWeight,
      fontStyle: italic ? FontStyle.italic : baseStyle.fontStyle,
    );
  }
}

class _EphemeralForumImage extends ConsumerStatefulWidget {
  const _EphemeralForumImage({
    required this.uri,
    required this.referer,
    super.key,
  });

  final Uri uri;
  final String referer;

  @override
  ConsumerState<_EphemeralForumImage> createState() =>
      _EphemeralForumImageState();
}

class _EphemeralForumImageState extends ConsumerState<_EphemeralForumImage> {
  ForumClient? _client;
  int? _userId;
  Future<Uint8List>? _future;

  @override
  void didUpdateWidget(covariant _EphemeralForumImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri || oldWidget.referer != widget.referer) {
      _client = null;
      _userId = null;
      _future = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ForumClient client = ref.watch(forumClientProvider);
    final int userId = ref.watch(authControllerProvider).value?.userId ?? 0;
    if (!identical(_client, client) || _userId != userId || _future == null) {
      _client = client;
      _userId = userId;
      _future = userId <= 0
          ? Future<Uint8List>.error(const ForumSessionExpiredException())
          : client.withActiveAccount<Uint8List>(
              userId,
              () => client.getBytes(
                widget.uri,
                referer: widget.uri.host == ForumClient.baseUri.host
                    ? widget.referer
                    : null,
              ),
            );
    }
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: _imageError,
          );
        }
        if (snapshot.hasError) {
          return InkWell(
            onTap: _retry,
            child: _imageError(context, null, null),
          );
        }
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }

  Widget _imageError(
    BuildContext context,
    Object? error,
    StackTrace? stackTrace,
  ) {
    return const SizedBox(
      height: 120,
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.grey),
      ),
    );
  }

  void _retry() {
    setState(() => _future = null);
  }
}
