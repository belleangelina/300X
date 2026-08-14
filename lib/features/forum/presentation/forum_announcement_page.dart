import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/forum/data/forum_read_repository.dart';
import 'package:x300/features/forum/domain/forum_announcement_models.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/forum/presentation/forum_read_widgets.dart';
import 'package:x300/features/forum/presentation/forum_topic_page.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class ForumAnnouncementPage extends ConsumerStatefulWidget {
  const ForumAnnouncementPage({required this.announcement, super.key});

  final ForumThreadSummary announcement;

  @override
  ConsumerState<ForumAnnouncementPage> createState() {
    return _ForumAnnouncementPageState();
  }
}

class _ForumAnnouncementPageState extends ConsumerState<ForumAnnouncementPage> {
  ForumAnnouncement? _announcement;
  Object? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(setBusy: false));
  }

  @override
  void didUpdateWidget(covariant ForumAnnouncementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.announcement.id == widget.announcement.id &&
        oldWidget.announcement.uri == widget.announcement.uri) {
      return;
    }
    _generation++;
    _announcement = null;
    _error = null;
    _loading = true;
    unawaited(_load(setBusy: false));
  }

  @override
  Widget build(BuildContext context) {
    final ForumAnnouncement? announcement = _announcement;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          announcement?.title ?? widget.announcement.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _announcement == null) {
      return const AppLoadingView(message: '正在加载公告');
    }
    if (_error != null && _announcement == null) {
      return AppErrorView(
        message: _error.toString(),
        onRetry: () => _load(setBusy: true),
      );
    }
    final ForumAnnouncement? announcement = _announcement;
    if (announcement == null) {
      return AppEmptyView(
        message: '暂无公告内容',
        onRefresh: () => _load(setBusy: true),
      );
    }
    final Widget content = RefreshIndicator(
      onRefresh: () => _load(setBusy: false),
      child: ListView(
        key: PageStorageKey<String>('forum-announcement-${announcement.id}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: <Widget>[
          Text(
            announcement.title,
            key: ValueKey<String>(
              'forum-announcement-title-${announcement.id}',
            ),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (announcement.metadataLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              announcement.metadataLabel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 18),
          if (!announcement.hasContent)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('公告正文为空')),
            )
          else
            ForumPostContent(
              post: ForumPost(
                id: announcement.id,
                threadId: 0,
                floor: 0,
                author: '',
                timeLabel: announcement.metadataLabel,
                messageHtml: announcement.messageHtml,
                contentBlocks: announcement.contentBlocks,
                uri: announcement.sourceUri,
              ),
              onOpenLink: _openLink,
            ),
        ],
      ),
    );
    if (!announcement.isFromCache) {
      return content;
    }
    return Column(
      children: <Widget>[
        ForumCacheBanner(updatedAt: announcement.cacheUpdatedAt),
        Expanded(child: content),
      ],
    );
  }

  Future<void> _load({required bool setBusy}) async {
    final int generation = ++_generation;
    if (setBusy && mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _announcement = null;
      });
    }
    try {
      final ForumAnnouncement result = await ref
          .read(forumReadRepositoryProvider)
          .loadAnnouncement(
            widget.announcement.uri,
            expectedAnnouncementId: widget.announcement.id,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _announcement = result;
        _error = null;
        _loading = false;
      });
    } on ForumRequestSupersededException {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    } on ForumSessionExpiredException {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        ref.read(authControllerProvider.notifier).markSessionExpired();
      }
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _openLink(ForumPostLinkInline link) {
    switch (link.kind) {
      case ForumPostLinkKind.internalThread:
      case ForumPostLinkKind.internalPost:
        final int? threadId = link.threadId;
        if (threadId == null || threadId <= 0) {
          _showMessage('该站内链接缺少主题编号');
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => ForumTopicPage(
              thread: ForumThreadSummary(
                id: threadId,
                boardId: 0,
                title: link.label,
                uri: _withMobileMode(link.uri),
              ),
              focusedPostId: link.postId,
            ),
          ),
        );
        return;
      case ForumPostLinkKind.download:
      case ForumPostLinkKind.external:
        unawaited(_openExternalLink(link.uri));
        return;
    }
  }

  Future<void> _openExternalLink(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showMessage('无法打开链接');
      }
    } on Object {
      _showMessage('无法打开链接');
    }
  }

  Uri _withMobileMode(Uri uri) {
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
