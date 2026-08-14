import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/community/data/community_repository.dart';
import 'package:x300/features/community/domain/community_pm_action_models.dart';
import 'package:x300/features/community/domain/community_models.dart';
import 'package:x300/features/community/presentation/community_pm_send_page.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/features/forum/presentation/forum_read_widgets.dart';
import 'package:x300/features/forum/presentation/forum_topic_page.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';
import 'package:x300/shared/presentation/forum_image.dart';

class CommunityNoticesScreen extends ConsumerWidget {
  const CommunityNoticesScreen({required this.uri, super.key});

  final Uri uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知')),
      body: _CommunityPagedList<CommunityNoticePage, CommunityNotice>(
        initialUri: uri,
        loadPage: ref.read(communityRepositoryProvider).loadNotices,
        itemsOf: (CommunityNoticePage value) => value.items,
        cursorOf: (CommunityNoticePage value) => value.cursor,
        cachedOf: (CommunityNoticePage value) => value.isFromCache,
        cacheUpdatedAtOf: (CommunityNoticePage value) => value.cacheUpdatedAt,
        emptyMessage: '暂无通知',
        effectMessage: '打开通知列表可能会在服务端标记已读',
        headerBuilder: (BuildContext context, CommunityNoticePage? page) =>
            _sectionTabs(context, page?.navigation),
        itemBuilder: (BuildContext context, CommunityNotice item) {
          final String subtitle = <String>[
            item.message,
            item.timeLabel,
          ].where((String value) => value.isNotEmpty).join('\n');
          return ListTile(
            key: ValueKey<String>('community-notice-${item.id}'),
            leading: _CommunityAvatar(
              uri: item.avatarUri,
              referer: uri.toString(),
              unread: item.unread,
            ),
            title: Text(
              item.title.isEmpty ? item.category.label : item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: item.unread ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: subtitle.isEmpty
                ? Text(item.category.label)
                : Text(
                    '${item.category.label} · $subtitle',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: item.canOpen ? const Icon(Icons.chevron_right) : null,
            onTap: item.canOpen ? () => _openNoticeTarget(context, item) : null,
          );
        },
      ),
    );
  }
}

class CommunityMessagesScreen extends ConsumerStatefulWidget {
  const CommunityMessagesScreen({required this.uri, super.key});

  final Uri uri;

  @override
  ConsumerState<CommunityMessagesScreen> createState() =>
      _CommunityMessagesScreenState();
}

class _CommunityMessagesScreenState
    extends ConsumerState<CommunityMessagesScreen> {
  int _refreshGeneration = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('私信')),
      body: _CommunityPagedList<CommunityPmListPage, CommunityPmConversation>(
        key: ValueKey<int>(_refreshGeneration),
        initialUri: widget.uri,
        loadPage: ref.read(communityRepositoryProvider).loadPmList,
        itemsOf: (CommunityPmListPage value) => value.items,
        cursorOf: (CommunityPmListPage value) => value.cursor,
        cachedOf: (CommunityPmListPage value) => value.isFromCache,
        cacheUpdatedAtOf: (CommunityPmListPage value) => value.cacheUpdatedAt,
        emptyMessage: '暂无私信会话',
        headerBuilder: (BuildContext context, CommunityPmListPage? page) =>
            _pmListHeader(context, page),
        itemBuilder: (BuildContext context, CommunityPmConversation item) {
          final String subtitle = <String>[
            item.preview,
            item.timeLabel,
          ].where((String value) => value.isNotEmpty).join('\n');
          return ListTile(
            key: ValueKey<String>('community-pm-${item.peerUserId}'),
            leading: _CommunityAvatar(
              uri: item.avatarUri,
              referer: widget.uri.toString(),
              unread: item.unread,
            ),
            title: Text(
              item.peerUsername,
              style: TextStyle(
                fontWeight: item.unread ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: subtitle.isEmpty
                ? null
                : Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => CommunityConversationScreen(
                  uri: item.uri,
                  peerUserId: item.peerUserId,
                  peerUsername: item.peerUsername,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget? _pmListHeader(BuildContext context, CommunityPmListPage? page) {
    final Widget? tabs = _sectionTabs(context, page?.navigation);
    final Uri? composeUri = page?.composeUri;
    if (tabs == null && composeUri == null) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ?tabs,
        if (composeUri != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: OutlinedButton.icon(
              key: const ValueKey<String>('community-pm-compose'),
              onPressed: () => _openSend(
                CommunityPmSendRequest(
                  context: CommunityPmSendContext.compose,
                  entryUri: composeUri,
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('发送新私信'),
            ),
          ),
      ],
    );
  }

  Future<void> _openSend(CommunityPmSendRequest request) async {
    final bool? shouldRefresh = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => CommunityPmSendPage(request: request),
      ),
    );
    if (mounted && shouldRefresh == true) {
      setState(() {
        _refreshGeneration++;
      });
    }
  }
}

class CommunityConversationScreen extends ConsumerStatefulWidget {
  const CommunityConversationScreen({
    required this.uri,
    required this.peerUserId,
    required this.peerUsername,
    super.key,
  });

  final Uri uri;
  final int peerUserId;
  final String peerUsername;

  @override
  ConsumerState<CommunityConversationScreen> createState() =>
      _CommunityConversationScreenState();
}

class _CommunityConversationScreenState
    extends ConsumerState<CommunityConversationScreen> {
  int _refreshGeneration = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.peerUsername.isEmpty ? '私信会话' : widget.peerUsername,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _CommunityPagedList<CommunityPmThreadPage, CommunityPmMessage>(
        key: ValueKey<int>(_refreshGeneration),
        initialUri: widget.uri,
        loadPage: (Uri value) => ref
            .read(communityRepositoryProvider)
            .loadPmThread(value, expectedPeerUserId: widget.peerUserId),
        itemsOf: (CommunityPmThreadPage value) => value.messages,
        cursorOf: (CommunityPmThreadPage value) => value.cursor,
        cachedOf: (CommunityPmThreadPage value) => value.isFromCache,
        cacheUpdatedAtOf: (CommunityPmThreadPage value) => value.cacheUpdatedAt,
        emptyMessage: '当前会话暂无消息',
        effectMessage: '打开会话可能会在服务端标记已读',
        headerBuilder: (BuildContext context, CommunityPmThreadPage? page) =>
            _conversationHeader(page),
        separator: false,
        itemBuilder: (BuildContext context, CommunityPmMessage item) {
          return Align(
            alignment: item.sentByViewer
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              key: ValueKey<String>(
                'community-pm-message-${item.sentByViewer}-${item.timeLabel}',
              ),
              constraints: const BoxConstraints(maxWidth: 280),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: item.sentByViewer
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(item.message),
                  if (item.timeLabel.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      item.timeLabel,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget? _conversationHeader(CommunityPmThreadPage? page) {
    if (page?.hasSendCapability != true || page?.isFromCache == true) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: OutlinedButton.icon(
        key: const ValueKey<String>('community-pm-reply'),
        onPressed: () => _openReply(page!.cursor.sourceUri),
        icon: const Icon(Icons.reply_outlined),
        label: const Text('回复私信'),
      ),
    );
  }

  Future<void> _openReply(Uri entryUri) async {
    final bool? shouldRefresh = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => CommunityPmSendPage(
          request: CommunityPmSendRequest(
            context: CommunityPmSendContext.conversation,
            entryUri: entryUri,
            expectedPeerUserId: widget.peerUserId,
            expectedPeerUsername: widget.peerUsername,
          ),
        ),
      ),
    );
    if (mounted && shouldRefresh == true) {
      setState(() {
        _refreshGeneration++;
      });
    }
  }
}

class CommunityProfileScreen extends ConsumerStatefulWidget {
  const CommunityProfileScreen({
    required this.uri,
    required this.profileUserId,
    super.key,
  });

  final Uri uri;
  final int profileUserId;

  @override
  ConsumerState<CommunityProfileScreen> createState() =>
      _CommunityProfileScreenState();
}

class _CommunityProfileScreenState
    extends ConsumerState<CommunityProfileScreen> {
  CommunityProfile? _profile;
  Object? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CommunityProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri == widget.uri &&
        oldWidget.profileUserId == widget.profileUserId) {
      return;
    }
    _generation++;
    _profile = null;
    _error = null;
    _loading = true;
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _profile?.username ?? '个人资料',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _profile == null) {
      return const AppLoadingView(message: '正在读取个人资料');
    }
    if (_error != null && _profile == null) {
      return AppErrorView(message: '$_error', onRetry: _load);
    }
    final CommunityProfile? profile = _profile;
    if (profile == null) {
      return AppEmptyView(message: '暂无可见资料', onRefresh: _load);
    }
    final Widget list = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: <Widget>[
                _CommunityAvatar(
                  uri: profile.avatarUri,
                  referer: profile.sourceUri.toString(),
                  size: 72,
                ),
                const SizedBox(height: 12),
                Text(
                  profile.username,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          for (final CommunityProfileEntry entry in profile.entries)
            ListTile(
              key: ValueKey<String>(
                'community-profile-entry-${entry.kind.name}',
              ),
              title: Text(entry.label),
              subtitle: entry.supported ? null : const Text('当前原生页不承载该入口'),
              trailing: entry.supported
                  ? const Icon(Icons.chevron_right)
                  : null,
              enabled: entry.supported,
              onTap: entry.supported
                  ? () => _openProfileEntry(context, profile, entry)
                  : null,
            ),
          if (profile.details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('资料', style: Theme.of(context).textTheme.titleSmall),
            ),
          for (final String detail in profile.details)
            ListTile(dense: true, title: Text(detail)),
        ],
      ),
    );
    if (!profile.isFromCache) {
      return list;
    }
    return Column(
      children: <Widget>[
        ForumCacheBanner(updatedAt: profile.cacheUpdatedAt),
        Expanded(child: list),
      ],
    );
  }

  Future<void> _load() async {
    final int generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final CommunityProfile result = await ref
          .read(communityRepositoryProvider)
          .loadProfile(widget.uri, expectedProfileUserId: widget.profileUserId);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _profile = result;
        _loading = false;
      });
    } on CommunityRequestSupersededException {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
        });
      }
    } on ForumSessionExpiredException {
      if (mounted && generation == _generation) {
        ref.read(authControllerProvider.notifier).markSessionExpired();
        setState(() {
          _loading = false;
          _error = const ForumSessionExpiredException();
        });
      }
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }
}

class CommunityActivityScreen extends ConsumerWidget {
  const CommunityActivityScreen({
    required this.uri,
    required this.profileUserId,
    required this.kind,
    super.key,
  });

  final Uri uri;
  final int profileUserId;
  final CommunityActivityKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(kind == CommunityActivityKind.topics ? '主题' : '回复'),
      ),
      body: _CommunityPagedList<CommunityActivityPage, CommunityActivityItem>(
        initialUri: uri,
        loadPage: (Uri value) => ref
            .read(communityRepositoryProvider)
            .loadActivity(
              value,
              expectedProfileUserId: profileUserId,
              expectedKind: kind,
            ),
        itemsOf: (CommunityActivityPage value) => value.items,
        cursorOf: (CommunityActivityPage value) => value.cursor,
        cachedOf: (CommunityActivityPage value) => value.isFromCache,
        cacheUpdatedAtOf: (CommunityActivityPage value) => value.cacheUpdatedAt,
        emptyMessage: kind == CommunityActivityKind.topics
            ? '暂无可见主题'
            : '暂无可见回复',
        headerBuilder: (BuildContext context, CommunityActivityPage? page) =>
            page == null
            ? null
            : _CommunityTabs(
                tabs: <_CommunityTab>[
                  for (final CommunityProfileEntry entry in page.tabs)
                    _CommunityTab(
                      label: entry.label,
                      selected:
                          entry.kind == CommunityProfileEntryKind.topics &&
                              kind == CommunityActivityKind.topics ||
                          entry.kind == CommunityProfileEntryKind.replies &&
                              kind == CommunityActivityKind.replies,
                      onTap: () => _replaceActivity(context, entry),
                    ),
                ],
              ),
        itemBuilder: (BuildContext context, CommunityActivityItem item) {
          final String counters = <String>[
            if (item.views > 0) '阅读 ${item.views}',
            if (item.replies > 0) '回复 ${item.replies}',
          ].join(' · ');
          final String subtitle = <String>[
            item.summary,
            item.author,
            item.timeLabel,
            counters,
          ].where((String value) => value.isNotEmpty).join('\n');
          return ListTile(
            key: ValueKey<String>(
              'community-activity-${item.target.threadId}-${item.target.postId}',
            ),
            title: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: subtitle.isEmpty
                ? null
                : Text(subtitle, maxLines: 4, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openTopicTarget(context, item.target),
          );
        },
      ),
    );
  }

  void _replaceActivity(BuildContext context, CommunityProfileEntry entry) {
    final CommunityActivityKind nextKind =
        entry.kind == CommunityProfileEntryKind.replies
        ? CommunityActivityKind.replies
        : CommunityActivityKind.topics;
    if (nextKind == kind) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CommunityActivityScreen(
          uri: entry.uri,
          profileUserId: profileUserId,
          kind: nextKind,
        ),
      ),
    );
  }
}

class CommunityPeopleScreen extends ConsumerWidget {
  const CommunityPeopleScreen({
    required this.uri,
    required this.kind,
    super.key,
  });

  final Uri uri;
  final CommunityPeopleKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(_peopleLabel(kind))),
      body: _CommunityPagedList<CommunityPeoplePage, CommunityPerson>(
        initialUri: uri,
        loadPage: (Uri value) => ref
            .read(communityRepositoryProvider)
            .loadPeople(value, expectedKind: kind),
        itemsOf: (CommunityPeoplePage value) => value.people,
        cursorOf: (CommunityPeoplePage value) => value.cursor,
        cachedOf: (CommunityPeoplePage value) => value.isFromCache,
        cacheUpdatedAtOf: (CommunityPeoplePage value) => value.cacheUpdatedAt,
        emptyMessage: '当前分类暂无成员',
        headerBuilder: (BuildContext context, CommunityPeoplePage? page) =>
            page == null
            ? null
            : _CommunityTabs(
                tabs: <_CommunityTab>[
                  for (final CommunityPeopleTab tab in page.tabs)
                    _CommunityTab(
                      label: tab.label,
                      selected: tab.kind == kind,
                      onTap: () => _replacePeople(context, tab),
                    ),
                ],
              ),
        itemBuilder: (BuildContext context, CommunityPerson item) {
          final String subtitle = <String>[
            item.description,
            item.timeLabel,
          ].where((String value) => value.isNotEmpty).join('\n');
          return ListTile(
            key: ValueKey<String>('community-person-${item.profile.userId}'),
            leading: _CommunityAvatar(
              uri: item.profile.avatarUri,
              referer: uri.toString(),
            ),
            title: Text(
              item.profile.username.isEmpty
                  ? '用户 ${item.profile.userId}'
                  : item.profile.username,
            ),
            subtitle: subtitle.isEmpty
                ? null
                : Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (item.conversationUri != null)
                  IconButton(
                    tooltip: '查看私信会话',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            CommunityConversationScreen(
                              uri: item.conversationUri!,
                              peerUserId: item.profile.userId,
                              peerUsername: item.profile.username,
                            ),
                      ),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _openProfileTarget(context, item.profile),
          );
        },
      ),
    );
  }

  void _replacePeople(BuildContext context, CommunityPeopleTab tab) {
    if (tab.kind == kind) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            CommunityPeopleScreen(uri: tab.uri, kind: tab.kind),
      ),
    );
  }
}

typedef _CommunityPageLoader<Data> = Future<Data> Function(Uri uri);
typedef _CommunityItemsOf<Data, Item> = List<Item> Function(Data page);
typedef _CommunityCursorOf<Data> = CommunityPageCursor Function(Data page);

class _CommunityPagedList<Data extends Object, Item>
    extends ConsumerStatefulWidget {
  const _CommunityPagedList({
    required this.initialUri,
    required this.loadPage,
    required this.itemsOf,
    required this.cursorOf,
    required this.cachedOf,
    required this.cacheUpdatedAtOf,
    required this.emptyMessage,
    required this.itemBuilder,
    this.headerBuilder,
    this.effectMessage,
    this.separator = true,
    super.key,
  });

  final Uri initialUri;
  final _CommunityPageLoader<Data> loadPage;
  final _CommunityItemsOf<Data, Item> itemsOf;
  final _CommunityCursorOf<Data> cursorOf;
  final bool Function(Data page) cachedOf;
  final DateTime? Function(Data page) cacheUpdatedAtOf;
  final String emptyMessage;
  final Widget Function(BuildContext context, Item item) itemBuilder;
  final Widget? Function(BuildContext context, Data? page)? headerBuilder;
  final String? effectMessage;
  final bool separator;

  @override
  ConsumerState<_CommunityPagedList<Data, Item>> createState() =>
      _CommunityPagedListState<Data, Item>();
}

class _CommunityPagedListState<Data extends Object, Item>
    extends ConsumerState<_CommunityPagedList<Data, Item>> {
  final ScrollController _scrollController = ScrollController();
  final List<Item> _items = <Item>[];
  Data? _page;
  Object? _error;
  Object? _loadMoreError;
  bool _loading = true;
  bool _loadingMore = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_load(reset: true));
  }

  @override
  void didUpdateWidget(covariant _CommunityPagedList<Data, Item> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUri == widget.initialUri) {
      return;
    }
    _generation++;
    _items.clear();
    _page = null;
    _error = null;
    _loadMoreError = null;
    _loading = true;
    _loadingMore = false;
    unawaited(_load(reset: true));
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
    final Widget? header = widget.headerBuilder?.call(context, _page);
    final Data? page = _page;
    return Column(
      children: <Widget>[
        ?header,
        if (widget.effectMessage != null)
          Material(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.visibility_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.effectMessage!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (page != null && widget.cachedOf(page))
          ForumCacheBanner(updatedAt: widget.cacheUpdatedAtOf(page)),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading && _page == null) {
      return const AppLoadingView(message: '正在读取社区内容');
    }
    if (_error != null && _page == null) {
      return AppErrorView(
        message: '$_error',
        onRetry: () => _load(reset: true),
      );
    }
    if (_items.isEmpty) {
      return AppEmptyView(
        message: widget.emptyMessage,
        onRefresh: () => _load(reset: true),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount:
            _items.length + (_loadingMore || _loadMoreError != null ? 1 : 0),
        separatorBuilder: (BuildContext context, int index) => widget.separator
            ? const Divider(height: 1, indent: 12, endIndent: 12)
            : const SizedBox.shrink(),
        itemBuilder: (BuildContext context, int index) {
          if (index < _items.length) {
            return widget.itemBuilder(context, _items[index]);
          }
          if (_loadMoreError != null) {
            return TextButton(
              onPressed: () => unawaited(_load(reset: false)),
              child: Text('加载失败，点击重试：$_loadMoreError'),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      ),
    );
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 320 ||
        _loadingMore ||
        _loadMoreError != null ||
        _nextUri == null) {
      return;
    }
    unawaited(_load(reset: false));
  }

  Uri? get _nextUri =>
      _page == null ? null : widget.cursorOf(_page as Data).nextPageUri;

  Future<void> _load({required bool reset}) async {
    final Uri? target = reset ? widget.initialUri : _nextUri;
    if (target == null || (!reset && _loadingMore)) {
      return;
    }
    final int generation = reset ? ++_generation : _generation;
    if (mounted) {
      setState(() {
        if (reset) {
          _loading = true;
          _error = null;
          _loadMoreError = null;
        } else {
          _loadingMore = true;
          _loadMoreError = null;
        }
      });
    }
    try {
      final Data result = await widget.loadPage(target);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(widget.itemsOf(result));
        } else {
          _items.addAll(widget.itemsOf(result));
        }
        _page = result;
        _loading = false;
        _loadingMore = false;
        _error = null;
        _loadMoreError = null;
      });
    } on CommunityRequestSupersededException {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    } on ForumSessionExpiredException {
      if (mounted && generation == _generation) {
        ref.read(authControllerProvider.notifier).markSessionExpired();
        setState(() {
          _loading = false;
          _loadingMore = false;
          if (_page == null) {
            _error = const ForumSessionExpiredException();
          } else {
            _loadMoreError = const ForumSessionExpiredException();
          }
        });
      }
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          if (_page == null || reset) {
            _error = error;
          } else {
            _loadMoreError = error;
          }
        });
      }
    }
  }
}

class _CommunityAvatar extends StatelessWidget {
  const _CommunityAvatar({
    required this.uri,
    required this.referer,
    this.unread = false,
    this.size = 44,
  });

  final Uri? uri;
  final String referer;
  final bool unread;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget avatar = uri == null
        ? CircleAvatar(
            radius: size / 2,
            child: const Icon(Icons.person_outline),
          )
        : ClipOval(
            child: SizedBox(
              width: size,
              height: size,
              child: ForumImage(
                uri: uri!,
                referer: referer,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            ),
          );
    if (!unread) {
      return avatar;
    }
    return Badge(child: avatar);
  }
}

class _CommunityTabs extends StatelessWidget {
  const _CommunityTabs({required this.tabs});

  final List<_CommunityTab> tabs;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final _CommunityTab tab = tabs[index];
          return ChoiceChip(
            label: Text(tab.label),
            selected: tab.selected,
            onSelected: tab.selected ? null : (_) => tab.onTap(),
          );
        },
      ),
    );
  }
}

class _CommunityTab {
  const _CommunityTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
}

void _openNoticeTarget(BuildContext context, CommunityNotice item) {
  final CommunityTopicTarget? topic = item.topicTarget;
  if (topic != null) {
    _openTopicTarget(context, topic);
    return;
  }
  final CommunityProfileTarget? profile = item.profileTarget;
  if (profile != null) {
    _openProfileTarget(context, profile);
  }
}

void _openTopicTarget(BuildContext context, CommunityTopicTarget target) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => ForumTopicPage(
        thread: ForumThreadSummary(
          id: target.threadId,
          boardId: target.boardId,
          title: target.title.isEmpty ? '论坛主题' : target.title,
          uri: target.uri,
        ),
        focusedPostId: target.postId,
      ),
    ),
  );
}

void _openProfileTarget(BuildContext context, CommunityProfileTarget target) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) =>
          CommunityProfileScreen(uri: target.uri, profileUserId: target.userId),
    ),
  );
}

void _openProfileEntry(
  BuildContext context,
  CommunityProfile profile,
  CommunityProfileEntry entry,
) {
  final Widget? page = switch (entry.kind) {
    CommunityProfileEntryKind.topics => CommunityActivityScreen(
      uri: entry.uri,
      profileUserId: profile.userId,
      kind: CommunityActivityKind.topics,
    ),
    CommunityProfileEntryKind.replies => CommunityActivityScreen(
      uri: entry.uri,
      profileUserId: profile.userId,
      kind: CommunityActivityKind.replies,
    ),
    CommunityProfileEntryKind.messages => CommunityMessagesScreen(
      uri: entry.uri,
    ),
    CommunityProfileEntryKind.friends => CommunityPeopleScreen(
      uri: entry.uri,
      kind: CommunityPeopleKind.friends,
    ),
    CommunityProfileEntryKind.favorites ||
    CommunityProfileEntryKind.unknown => null,
  };
  if (page == null) {
    return;
  }
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (BuildContext context) => page));
}

String _peopleLabel(CommunityPeopleKind kind) {
  return switch (kind) {
    CommunityPeopleKind.friends => '好友',
    CommunityPeopleKind.online => '在线成员',
    CommunityPeopleKind.visitors => '访客',
    CommunityPeopleKind.visited => '访问记录',
  };
}

Widget? _sectionTabs(BuildContext context, List<CommunitySectionLink>? links) {
  if (links == null || links.isEmpty) {
    return null;
  }
  return _CommunityTabs(
    tabs: <_CommunityTab>[
      for (final CommunitySectionLink link in links)
        _CommunityTab(
          label: link.label,
          selected: link.selected,
          onTap: () => _replaceCommunitySection(context, link),
        ),
    ],
  );
}

void _replaceCommunitySection(BuildContext context, CommunitySectionLink link) {
  final int profileUserId =
      int.tryParse(link.uri.queryParameters['uid'] ?? '') ?? 0;
  final Widget? page = switch (link.kind) {
    CommunitySectionKind.notices => CommunityNoticesScreen(uri: link.uri),
    CommunitySectionKind.messages => CommunityMessagesScreen(uri: link.uri),
    CommunitySectionKind.profile when profileUserId > 0 =>
      CommunityProfileScreen(uri: link.uri, profileUserId: profileUserId),
    CommunitySectionKind.profile => null,
  };
  if (page == null) {
    return;
  }
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(builder: (BuildContext context) => page),
  );
}
