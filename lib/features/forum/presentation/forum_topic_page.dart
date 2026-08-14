import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/forum/application/forum_attachment_download_controller.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/data/forum_webview_policy.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart' as domain;
import 'package:x300/features/community/presentation/community_pages.dart';
import 'package:x300/features/forum/presentation/forum_action_page.dart';
import 'package:x300/features/forum/presentation/forum_original_page.dart';
import 'package:x300/features/forum/presentation/forum_read_widgets.dart';
import 'package:x300/features/library/data/work_index_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/reader/presentation/chapter_reader_page.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class ForumTopicPage extends ConsumerStatefulWidget {
  const ForumTopicPage({
    required this.thread,
    this.focusedPostId,
    this.onOpenAuthor,
    super.key,
  });

  final domain.ForumThreadSummary thread;
  final int? focusedPostId;
  final void Function(Uri uri, int userId)? onOpenAuthor;

  @override
  ConsumerState<ForumTopicPage> createState() {
    return _ForumTopicPageState();
  }
}

class _ForumTopicPageState extends ConsumerState<ForumTopicPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _postKeys = <int, GlobalKey>{};
  domain.ForumThreadPage? _page;
  Object? _error;
  bool _loading = true;
  int _generation = 0;
  int _anchorGeneration = 0;
  Work? _readingWork;
  Timer? _anchorTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_loadInitial(setBusy: false));
  }

  @override
  void didUpdateWidget(covariant ForumTopicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thread.id == widget.thread.id &&
        oldWidget.thread.uri == widget.thread.uri &&
        oldWidget.focusedPostId == widget.focusedPostId) {
      return;
    }
    _generation++;
    _anchorGeneration++;
    _anchorTimer?.cancel();
    unawaited(_saveReadPosition());
    _page = null;
    _readingWork = null;
    _postKeys.clear();
    _error = null;
    _loading = true;
    unawaited(_loadInitial(setBusy: false));
  }

  @override
  void dispose() {
    _anchorGeneration++;
    _anchorTimer?.cancel();
    unawaited(_saveReadPosition());
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final domain.ForumThreadPage? page = _page;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          page?.thread.title ?? widget.thread.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          if (page?.favoriteUri != null && !page!.isFromCache)
            IconButton(
              key: const Key('forum-favorite-thread'),
              tooltip: '收藏主题',
              onPressed: () => _openTopicAction(
                ForumActionKind.favoriteThread,
                page.favoriteUri!,
                '收藏主题',
              ),
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
          if (page?.shareUri != null && !page!.isFromCache)
            IconButton(
              key: const Key('forum-share-thread'),
              tooltip: '分享主题',
              onPressed: () => _openTopicAction(
                ForumActionKind.shareThread,
                page.shareUri!,
                '站内分享',
              ),
              icon: const Icon(Icons.share_outlined),
            ),
          if (page != null && _replyEntryPostId(page) != null)
            IconButton(
              key: const Key('forum-reply-thread'),
              tooltip: '回复主题',
              onPressed: _openReply,
              icon: const Icon(Icons.reply_outlined),
            ),
          if (_readingWork != null)
            IconButton(
              key: const Key('forum-reading-mode'),
              tooltip: '阅读模式',
              onPressed: _openReadingMode,
              icon: const Icon(Icons.chrome_reader_mode_outlined),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _page == null) {
      return const AppLoadingView(message: '正在加载主题');
    }
    if (_error != null && _page == null) {
      return AppErrorView(
        message: _error.toString(),
        onRetry: () => _loadInitial(setBusy: true),
      );
    }
    final domain.ForumThreadPage? page = _page;
    if (page == null) {
      return AppEmptyView(
        message: '暂无可见楼层',
        onRefresh: () => _loadInitial(setBusy: true),
      );
    }
    final Map<String, ForumAttachmentDownloadState> attachmentStates = ref
        .watch(forumAttachmentDownloadControllerProvider);
    final Widget content = RefreshIndicator(
      onRefresh: () => _loadUri(
        page.cursor.sourceUri,
        focusedPostId: page.focusedPostId,
        setBusy: false,
      ),
      child: SingleChildScrollView(
        key: PageStorageKey<String>('forum-topic-${widget.thread.id}'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (page.readingOptions.isNotEmpty)
              _ReadingOptions(
                options: page.readingOptions,
                onSelected: (domain.ForumRouteOption option) =>
                    unawaited(_loadUri(option.uri, setBusy: true)),
              ),
            if (_error != null)
              _InlineTopicWarning(message: '刷新失败，已保留当前内容：$_error'),
            _TopicHeader(page: page),
            for (final domain.ForumPost post in page.posts)
              KeyedSubtree(
                key: ValueKey<String>('forum-post-${post.id}'),
                child: _PostView(
                  key: _postKeys.putIfAbsent(post.id, GlobalKey.new),
                  post: post,
                  focused: post.id == page.focusedPostId,
                  onOpenLink: _openPostLink,
                  attachmentState: (domain.ForumAttachment attachment) =>
                      attachmentStates[ForumAttachmentDownloadController.keyFor(
                        attachment.uri,
                      )],
                  onOpenAttachment: (domain.ForumAttachment attachment) =>
                      unawaited(
                        ref
                            .read(
                              forumAttachmentDownloadControllerProvider
                                  .notifier,
                            )
                            .downloadAndOpen(
                              attachment,
                              topicSourceUri: page.cursor.sourceUri,
                            ),
                      ),
                  onCancelAttachment: (domain.ForumAttachment attachment) => ref
                      .read(forumAttachmentDownloadControllerProvider.notifier)
                      .cancel(attachment.uri),
                  allowOriginalActions:
                      forumOriginalPageSupported && !page.isFromCache,
                  onOpenQuoteAction: _quoteTargetPostId(page, post) == null
                      ? null
                      : () => _openQuoteReply(post),
                  onOpenEditAction: _editTargetPostId(page, post) == null
                      ? null
                      : () => _openEditPost(post),
                  onOpenOriginalAction: _openOriginalAction,
                  onOpenAuthor: _openAuthor,
                ),
              ),
            _TopicPager(
              cursor: page.cursor,
              onPrevious: page.cursor.previousPageUri == null
                  ? null
                  : () => _loadUri(page.cursor.previousPageUri!, setBusy: true),
              onNext: page.cursor.nextPageUri == null
                  ? null
                  : () => _loadUri(page.cursor.nextPageUri!, setBusy: true),
            ),
          ],
        ),
      ),
    );
    if (!page.isFromCache) {
      return content;
    }
    return Column(
      children: <Widget>[
        ForumCacheBanner(updatedAt: page.cacheUpdatedAt),
        Expanded(child: content),
      ],
    );
  }

  Future<void> _loadInitial({required bool setBusy}) async {
    final int? focusedPostId = widget.focusedPostId;
    if (focusedPostId != null) {
      return _performLoad(
        request: (ForumReadRepository repository) =>
            repository.loadThreadAtPost(
              threadId: widget.thread.id,
              postId: focusedPostId,
            ),
        focusedPostId: focusedPostId,
        setBusy: setBusy,
      );
    }
    final int anchorGeneration = ++_anchorGeneration;
    final ForumReadPosition? position = await _loadReadPosition();
    if (!mounted || anchorGeneration != _anchorGeneration) {
      return;
    }
    final int? postId = position?.postId;
    if (postId != null) {
      return _performLoad(
        request: (ForumReadRepository repository) async {
          try {
            return await repository.loadThreadAtPost(
              threadId: widget.thread.id,
              postId: postId,
            );
          } on ForumConnectionException {
            return repository.loadThread(
              widget.thread.uri,
              expectedThreadId: widget.thread.id,
              expectedBoardId: widget.thread.boardId > 0
                  ? widget.thread.boardId
                  : null,
            );
          }
        },
        focusedPostId: postId,
        setBusy: setBusy,
      );
    }
    return _loadUri(widget.thread.uri, setBusy: setBusy);
  }

  Future<void> _loadUri(Uri uri, {int? focusedPostId, required bool setBusy}) {
    return _performLoad(
      request: (ForumReadRepository repository) => repository.loadThread(
        uri,
        expectedThreadId: widget.thread.id,
        expectedBoardId: widget.thread.boardId > 0
            ? widget.thread.boardId
            : null,
        focusedPostId: focusedPostId,
      ),
      focusedPostId: focusedPostId,
      setBusy: setBusy,
    );
  }

  Future<void> _performLoad({
    required Future<domain.ForumThreadPage> Function(
      ForumReadRepository repository,
    )
    request,
    required int? focusedPostId,
    required bool setBusy,
  }) async {
    final int generation = ++_generation;
    if (setBusy && mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _page = null;
      });
    }
    try {
      final domain.ForumThreadPage result = await request(
        ref.read(forumReadRepositoryProvider),
      );
      if (!mounted || generation != _generation) {
        return;
      }
      _postKeys.removeWhere(
        (int postId, GlobalKey _) => result.postById(postId) == null,
      );
      for (final domain.ForumPost post in result.posts) {
        _postKeys.putIfAbsent(post.id, GlobalKey.new);
      }
      setState(() {
        _page = result;
        _error = null;
        _loading = false;
      });
      unawaited(_resolveReadingWork(result.thread.id, generation));
      final int? target = result.focusedPostId ?? focusedPostId;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted || generation != _generation) {
          return;
        }
        if (target == null) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
          return;
        }
        final BuildContext? targetContext = _postKeys[target]?.currentContext;
        if (targetContext != null) {
          unawaited(
            Scrollable.ensureVisible(
              targetContext,
              alignment: 0.08,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
            ),
          );
        }
      });
    } on ForumRequestSupersededException {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
        });
      }
    } on ForumSessionExpiredException {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
        });
        ref.read(authControllerProvider.notifier).markSessionExpired();
      }
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

  Future<void> _resolveReadingWork(int threadId, int generation) async {
    try {
      final WorkIndexRecord? record = await ref
          .read(workIndexRepositoryProvider)
          .loadAnyBySourceTid(threadId);
      if (!mounted || generation != _generation) {
        return;
      }
      final Work? work = record?.work;
      setState(() {
        _readingWork = work != null && _chaptersOf(work).isNotEmpty
            ? work
            : null;
      });
    } on Object {
      // 作品索引不可用时不推测阅读模式入口。
    }
  }

  void _openReadingMode() {
    final Work? work = _readingWork;
    final domain.ForumThreadPage? page = _page;
    if (work == null || page == null) {
      return;
    }
    final List<Chapter> chapters = _chaptersOf(work);
    if (chapters.isEmpty) {
      return;
    }
    final int? focusedPostId = page.focusedPostId;
    Chapter? selected;
    for (final Chapter chapter in chapters) {
      if (chapter.sourceTid == page.thread.id &&
          focusedPostId != null &&
          chapter.sourcePid == focusedPostId) {
        selected = chapter;
        break;
      }
    }
    selected ??= chapters.cast<Chapter?>().firstWhere(
      (Chapter? chapter) => chapter!.sourceTid == page.thread.id,
      orElse: () => null,
    );
    selected ??= chapters.first;
    final Chapter chapter = selected;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext readerContext) => ChapterReaderPage(
          work: work,
          chapter: chapter,
          chapters: chapters,
          onOpenDiscussion: () => Navigator.of(readerContext).pop(),
        ),
      ),
    );
  }

  List<Chapter> _chaptersOf(Work work) {
    final Map<String, Chapter> chapters = <String, Chapter>{
      for (final Chapter chapter in work.chapters) chapter.id: chapter,
      for (final WorkDirectory directory in work.directories)
        for (final Chapter chapter in directory.chapters) chapter.id: chapter,
    };
    return chapters.values.toList(growable: false);
  }

  Future<ForumReadPosition?> _loadReadPosition() async {
    try {
      final int userId = ref.read(authControllerProvider).value?.userId ?? 0;
      if (userId <= 0) {
        return null;
      }
      return ref
          .read(forumClientProvider)
          .withActiveAccount(
            userId,
            () => ref
                .read(forumLocalRepositoryProvider)
                .loadReadPosition(userId: userId, threadId: widget.thread.id),
          );
    } on Object {
      return null;
    }
  }

  void _handleScroll() {
    _anchorTimer?.cancel();
    _anchorTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_saveReadPosition()),
    );
  }

  Future<void> _saveReadPosition() async {
    final domain.ForumThreadPage? page = _page;
    if (page == null || page.posts.isEmpty) {
      return;
    }
    domain.ForumPost visible = page.posts.first;
    for (final domain.ForumPost post in page.posts) {
      final BuildContext? postContext = _postKeys[post.id]?.currentContext;
      final RenderObject? renderObject = postContext?.findRenderObject();
      if (renderObject is RenderBox &&
          renderObject.localToGlobal(Offset.zero).dy +
                  renderObject.size.height >
              kToolbarHeight) {
        visible = post;
        break;
      }
    }
    try {
      final int userId = ref.read(authControllerProvider).value?.userId ?? 0;
      if (userId <= 0) {
        return;
      }
      await ref
          .read(forumClientProvider)
          .withActiveAccount(
            userId,
            () => ref
                .read(forumLocalRepositoryProvider)
                .saveReadPosition(
                  ForumReadPosition(
                    userId: userId,
                    threadId: page.thread.id,
                    postId: visible.id,
                    page: page.cursor.currentPage,
                    floor: visible.floor,
                    updatedAt: DateTime.now(),
                  ),
                ),
          );
    } on Object {
      // 阅读位置落盘失败不影响当前主题。
    }
  }

  void _openAuthor(Uri uri, int userId) {
    if (userId <= 0) {
      return;
    }
    final void Function(Uri uri, int userId)? callback = widget.onOpenAuthor;
    if (callback != null) {
      callback(uri, userId);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CommunityProfileScreen(
          uri: uri,
          profileUserId: userId,
        ),
      ),
    );
  }

  void _openPostLink(domain.ForumPostLinkInline link) {
    switch (link.kind) {
      case domain.ForumPostLinkKind.internalThread:
      case domain.ForumPostLinkKind.internalPost:
        _openInternalPostLink(link);
        return;
      case domain.ForumPostLinkKind.download:
        _openInlineAttachment(link);
        return;
      case domain.ForumPostLinkKind.external:
        unawaited(_openExternalLink(link.uri));
        return;
    }
  }

  void _openInternalPostLink(domain.ForumPostLinkInline link) {
    final int? threadId = link.threadId;
    if (threadId == null || threadId <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该站内链接缺少主题编号')));
      return;
    }
    final int? postId = link.postId;
    if (threadId == widget.thread.id) {
      final BuildContext? targetContext = postId == null
          ? null
          : _postKeys[postId]?.currentContext;
      if (targetContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            targetContext,
            alignment: 0.08,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
          ),
        );
        return;
      }
      if (postId != null) {
        unawaited(
          _performLoad(
            request: (ForumReadRepository repository) =>
                repository.loadThreadAtPost(threadId: threadId, postId: postId),
            focusedPostId: postId,
            setBusy: true,
          ),
        );
        return;
      }
      unawaited(_loadUri(_withMobileMode(link.uri), setBusy: true));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ForumTopicPage(
          thread: domain.ForumThreadSummary(
            id: threadId,
            boardId: 0,
            title: link.label,
            uri: _withMobileMode(link.uri),
          ),
          focusedPostId: postId,
        ),
      ),
    );
  }

  Uri _withMobileMode(Uri uri) {
    if (uri.queryParameters['mobile'] == '2') {
      return uri;
    }
    return uri.replace(
      queryParameters: <String, String>{...uri.queryParameters, 'mobile': '2'},
    );
  }

  void _openInlineAttachment(domain.ForumPostLinkInline link) {
    final domain.ForumThreadPage? page = _page;
    if (page == null) {
      return;
    }
    unawaited(
      ref
          .read(forumAttachmentDownloadControllerProvider.notifier)
          .downloadAndOpen(
            domain.ForumAttachment(
              name: link.label.isEmpty ? '附件' : link.label,
              uri: link.uri,
            ),
            topicSourceUri: page.cursor.sourceUri,
          ),
    );
  }

  Future<void> _openExternalLink(Uri uri) async {
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }

  Future<void> _openTopicAction(
    ForumActionKind kind,
    Uri entryUri,
    String title,
  ) async {
    final domain.ForumThreadPage? page = _page;
    if (page == null || page.isFromCache) {
      return;
    }
    final Uri readbackUri = kind == ForumActionKind.favoriteThread
        ? ForumClient.baseUri.resolve(
            'home.php?mod=space&do=favorite&type=thread&mobile=2',
          )
        : ForumClient.baseUri.resolve(
            'forum.php?mod=viewthread&tid=${page.thread.id}&mobile=2',
          );
    final ForumActionPageResult? result = await Navigator.of(context).push(
      MaterialPageRoute<ForumActionPageResult>(
        builder: (BuildContext context) => ForumActionPage(
          request: ForumActionRequest(
            kind: kind,
            target: ForumActionTarget(
              boardId: page.thread.boardId,
              threadId: page.thread.id,
            ),
            entryUri: entryUri,
            readbackUri: readbackUri,
          ),
          title: title,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    await _loadUri(
      page.cursor.sourceUri,
      focusedPostId: page.focusedPostId,
      setBusy: true,
    );
  }

  Future<void> _openReply() async {
    final domain.ForumThreadPage? page = _page;
    if (page == null) {
      return;
    }
    final int? entryPostId = _replyEntryPostId(page);
    final Uri? entryUri = page.replyUri;
    if (entryPostId == null || entryUri == null) {
      return;
    }
    await _openReplyAction(
      page: page,
      kind: ForumActionKind.reply,
      entryUri: entryUri,
      postId: null,
      title: '回复主题',
      draftId: 'reply:${page.thread.id}',
    );
  }

  Future<void> _openQuoteReply(domain.ForumPost post) async {
    final domain.ForumThreadPage? page = _page;
    if (page == null || page.postById(post.id) == null) {
      return;
    }
    final int? postId = _quoteTargetPostId(page, post);
    final Uri? entryUri = post.quoteUri;
    if (postId == null || entryUri == null) {
      return;
    }
    await _openReplyAction(
      page: page,
      kind: ForumActionKind.quoteReply,
      entryUri: entryUri,
      postId: postId,
      title: '引用回复',
      draftId: 'quote-reply:$postId',
    );
  }

  Future<void> _openReplyAction({
    required domain.ForumThreadPage page,
    required ForumActionKind kind,
    required Uri entryUri,
    required int? postId,
    required String title,
    required String draftId,
  }) async {
    if (_page != page || page.isFromCache) {
      return;
    }
    final ForumActionPageResult? result = await Navigator.of(context).push(
      MaterialPageRoute<ForumActionPageResult>(
        builder: (BuildContext context) => ForumActionPage(
          request: ForumActionRequest(
            kind: kind,
            target: ForumActionTarget(
              boardId: page.thread.boardId,
              threadId: page.thread.id,
              postId: postId,
            ),
            entryUri: entryUri,
            readbackUri: ForumClient.baseUri.resolve(
              'forum.php?mod=viewthread&tid=${page.thread.id}&mobile=2',
            ),
          ),
          title: title,
          draftId: draftId,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    await _loadUri(
      page.cursor.sourceUri,
      focusedPostId: page.focusedPostId,
      setBusy: true,
    );
  }

  Future<void> _openEditPost(domain.ForumPost post) async {
    final domain.ForumThreadPage? page = _page;
    final int? postId = page == null ? null : _editTargetPostId(page, post);
    final Uri? entryUri = post.editUri;
    if (page == null || postId == null || entryUri == null) {
      return;
    }
    final Uri readbackUri = ForumClient.baseUri.resolve(
      'forum.php?mod=redirect&goto=findpost&ptid=${page.thread.id}'
      '&pid=$postId&mobile=2',
    );
    final ForumActionPageResult? result = await Navigator.of(context).push(
      MaterialPageRoute<ForumActionPageResult>(
        builder: (BuildContext context) => ForumActionPage(
          request: ForumActionRequest(
            kind: ForumActionKind.editPost,
            target: ForumActionTarget(
              boardId: page.thread.boardId,
              threadId: page.thread.id,
              postId: postId,
            ),
            entryUri: entryUri,
            readbackUri: readbackUri,
          ),
          title: '编辑楼层',
          draftId: 'edit-post:$postId',
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    await _loadUri(page.cursor.sourceUri, focusedPostId: postId, setBusy: true);
  }

  int? _replyEntryPostId(domain.ForumThreadPage page) {
    return _replyEntryTargetPostId(page, page.replyUri, 'reppost');
  }

  int? _quoteTargetPostId(domain.ForumThreadPage page, domain.ForumPost post) {
    final int? postId = _replyEntryTargetPostId(
      page,
      post.quoteUri,
      'repquote',
    );
    return postId == post.id ? postId : null;
  }

  int? _editTargetPostId(domain.ForumThreadPage page, domain.ForumPost post) {
    final Uri? uri = post.editUri;
    if (page.isFromCache || page.postById(post.id) == null || uri == null) {
      return null;
    }
    final Uri baseUri = ForumClient.baseUri;
    const Set<String> allowedParameters = <String>{
      'mod',
      'action',
      'fid',
      'tid',
      'pid',
      'page',
      'mobile',
    };
    if (uri.scheme != baseUri.scheme ||
        uri.host != baseUri.host ||
        uri.port != baseUri.port ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/forum.php' ||
        uri.fragment.isNotEmpty ||
        !uri.queryParametersAll.keys.every(allowedParameters.contains) ||
        _singleQueryValue(uri, 'mod') != 'post' ||
        _singleQueryValue(uri, 'action') != 'edit' ||
        _singleQueryValue(uri, 'mobile') != '2' ||
        _positiveQueryInt(uri, 'fid') != page.thread.boardId ||
        _positiveQueryInt(uri, 'tid') != page.thread.id ||
        _positiveQueryInt(uri, 'pid') != post.id ||
        _positiveQueryInt(uri, 'page') == null) {
      return null;
    }
    return post.id;
  }

  int? _replyEntryTargetPostId(
    domain.ForumThreadPage page,
    Uri? uri,
    String targetParameter,
  ) {
    if (page.isFromCache || uri == null) {
      return null;
    }
    final Uri baseUri = ForumClient.baseUri;
    if (uri.scheme != baseUri.scheme ||
        uri.host != baseUri.host ||
        uri.port != baseUri.port ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/forum.php' ||
        uri.fragment.isNotEmpty ||
        _singleQueryValue(uri, 'mod') != 'post' ||
        _singleQueryValue(uri, 'action') != 'reply' ||
        _positiveQueryInt(uri, 'tid') != page.thread.id ||
        _singleQueryValue(uri, 'mobile') != '2') {
      return null;
    }
    final bool quoteReply = targetParameter == 'repquote';
    final Set<String> allowedParameters = quoteReply
        ? const <String>{
            'mod',
            'action',
            'fid',
            'tid',
            'page',
            'repquote',
            'extra',
            'mobile',
          }
        : const <String>{
            'mod',
            'action',
            'fid',
            'tid',
            'page',
            'reppost',
            'mobile',
          };
    if (!uri.queryParametersAll.keys.every(allowedParameters.contains)) {
      return null;
    }
    if (page.thread.boardId <= 0 ||
        _positiveQueryInt(uri, 'fid') != page.thread.boardId) {
      return null;
    }
    final int? sourcePage = _positiveQueryInt(uri, 'page');
    if (sourcePage == null ||
        (quoteReply && _singleQueryValue(uri, 'extra') != 'page=$sourcePage')) {
      return null;
    }
    return _positiveQueryInt(uri, targetParameter);
  }

  String? _singleQueryValue(Uri uri, String name) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single : null;
  }

  int? _positiveQueryInt(Uri uri, String name) {
    final int? value = int.tryParse(_singleQueryValue(uri, name) ?? '');
    return value != null && value > 0 ? value : null;
  }

  Future<void> _openOriginalAction(Uri uri, String label) async {
    if (!forumOriginalPageSupported ||
        _page?.isFromCache != false ||
        !_isRegisteredOriginalUri(uri)) {
      return;
    }
    final bool? changed = await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            ForumOriginalPage(initialUri: uri, label: label),
      ),
    );
    final domain.ForumThreadPage? page = _page;
    if (!mounted || changed != true || page == null) {
      return;
    }
    await _loadUri(
      page.cursor.sourceUri,
      focusedPostId: page.focusedPostId,
      setBusy: true,
    );
  }

  bool _isRegisteredOriginalUri(Uri uri) {
    return const ForumWebViewPolicy().isRegisteredInitialUri(uri);
  }
}

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.page});

  final domain.ForumThreadPage page;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            page.thread.typeName.isEmpty
                ? page.thread.title
                : '【${page.thread.typeName}】${page.thread.title}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          if (page.thread.author.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '楼主：${page.thread.author}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _PostView extends StatelessWidget {
  const _PostView({
    required this.post,
    required this.focused,
    required this.onOpenLink,
    required this.onOpenAttachment,
    required this.onCancelAttachment,
    required this.attachmentState,
    required this.allowOriginalActions,
    required this.onOpenQuoteAction,
    required this.onOpenEditAction,
    required this.onOpenOriginalAction,
    required this.onOpenAuthor,
    super.key,
  });

  final domain.ForumPost post;
  final bool focused;
  final ValueChanged<domain.ForumPostLinkInline> onOpenLink;
  final ValueChanged<domain.ForumAttachment> onOpenAttachment;
  final ValueChanged<domain.ForumAttachment> onCancelAttachment;
  final ForumAttachmentDownloadState? Function(
    domain.ForumAttachment attachment,
  )
  attachmentState;
  final bool allowOriginalActions;
  final Future<void> Function()? onOpenQuoteAction;
  final Future<void> Function()? onOpenEditAction;
  final Future<void> Function(Uri uri, String label) onOpenOriginalAction;
  final void Function(Uri uri, int userId) onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: focused
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (post.authorUri != null && (post.authorId ?? 0) > 0)
                IconButton(
                  key: ValueKey<String>('forum-topic-author-${post.id}'),
                  tooltip: post.author.isEmpty
                      ? '查看作者资料'
                      : '查看 ${post.author}',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  onPressed: () =>
                      onOpenAuthor(post.authorUri!, post.authorId!),
                  icon: const Icon(Icons.account_circle_outlined),
                ),
              Expanded(
                child: Text(
                  post.author.isEmpty ? '匿名用户' : post.author,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (post.isOriginalPoster)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: _PostBadge('楼主'),
                ),
              Text(
                '${post.floor} 楼',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          if (post.timeLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              post.timeLabel,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          ForumPostContent(
            post: post,
            onOpenLink: onOpenLink,
            onOpenAttachment: onOpenAttachment,
            onCancelAttachment: onCancelAttachment,
            attachmentState: attachmentState,
            onOpenAuthor: onOpenAuthor,
          ),
          if (onOpenQuoteAction != null ||
              onOpenEditAction != null ||
              (allowOriginalActions && _hasOriginalAction)) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: <Widget>[
                if (onOpenQuoteAction != null)
                  TextButton(
                    onPressed: onOpenQuoteAction,
                    child: const Text('引用'),
                  ),
                if (onOpenEditAction != null)
                  TextButton(
                    key: ValueKey<String>('forum-edit-post-${post.id}'),
                    onPressed: onOpenEditAction,
                    child: const Text('编辑'),
                  ),
                if (allowOriginalActions &&
                    post.commentUri != null &&
                    _registered(post.commentUri!))
                  TextButton(
                    onPressed: () =>
                        onOpenOriginalAction(post.commentUri!, '点评'),
                    child: const Text('点评'),
                  ),
                if (allowOriginalActions &&
                    post.rateUri != null &&
                    _registered(post.rateUri!))
                  TextButton(
                    onPressed: () => onOpenOriginalAction(post.rateUri!, '评分'),
                    child: const Text('评分'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1),
        ],
      ),
    );
  }

  bool get _hasOriginalAction =>
      (post.commentUri != null && _registered(post.commentUri!)) ||
      (post.rateUri != null && _registered(post.rateUri!));

  bool _registered(Uri uri) {
    return const ForumWebViewPolicy().isRegisteredInitialUri(uri);
  }
}

class _PostBadge extends StatelessWidget {
  const _PostBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

class _ReadingOptions extends StatelessWidget {
  const _ReadingOptions({required this.options, required this.onSelected});

  final List<domain.ForumRouteOption> options;
  final ValueChanged<domain.ForumRouteOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: options
            .map(
              (domain.ForumRouteOption option) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(option.label),
                  selected: option.selected,
                  onSelected: option.selected
                      ? null
                      : (bool _) => onSelected(option),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _TopicPager extends StatelessWidget {
  const _TopicPager({
    required this.cursor,
    required this.onPrevious,
    required this.onNext,
  });

  final domain.ForumPageCursor cursor;
  final Future<void> Function()? onPrevious;
  final Future<void> Function()? onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const Key('forum-topic-prev'),
                onPressed: onPrevious,
                child: const Text('上一页'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '${cursor.currentPage} / ${cursor.totalPages}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            Expanded(
              child: OutlinedButton(
                key: const Key('forum-topic-next'),
                onPressed: onNext,
                child: const Text('下一页'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineTopicWarning extends StatelessWidget {
  const _InlineTopicWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(message, style: const TextStyle(fontSize: 12)),
    );
  }
}
