import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/community/presentation/community_pages.dart';
import 'package:x300/features/forum/data/forum_search_repository.dart';
import 'package:x300/features/forum/domain/forum_search_models.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class ForumSearchPage extends ConsumerStatefulWidget {
  const ForumSearchPage({
    required this.onOpenResult,
    this.formUri,
    this.initialKeyword = '',
    this.onOpenAuthor,
    super.key,
  });

  final Uri? formUri;
  final String initialKeyword;
  final ValueChanged<ForumThreadSearchHit> onOpenResult;
  final ValueChanged<ForumThreadSearchHit>? onOpenAuthor;

  @override
  ConsumerState<ForumSearchPage> createState() {
    return _ForumSearchPageState();
  }
}

class _ForumSearchPageState extends ConsumerState<ForumSearchPage> {
  late final TextEditingController _keywordController;
  final ScrollController _scrollController = ScrollController();
  final List<ForumThreadSearchHit> _hits = <ForumThreadSearchHit>[];

  ForumThreadSearchPage? _cursor;
  String? _preparedScope;
  String _activeKeyword = '';
  Object? _error;
  bool _preparing = false;
  bool _searching = false;
  bool _loadingMore = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController(text: widget.initialKeyword);
    if (widget.initialKeyword.trim().isEmpty) {
      unawaited(_prepareScope());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_search()));
    }
  }

  @override
  void didUpdateWidget(covariant ForumSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.formUri != widget.formUri) {
      _generation++;
      _hits.clear();
      _cursor = null;
      _preparedScope = null;
      _error = null;
      unawaited(_prepareScope());
    }
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('论坛搜索')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('forum-search-keyword'),
                    controller: _keywordController,
                    enabled: !_searching,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: '搜索论坛主题',
                      prefixIcon: Icon(Icons.search_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => unawaited(_search()),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('forum-search-submit'),
                  tooltip: '搜索',
                  onPressed: _searching ? null : () => unawaited(_search()),
                  icon: _searching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ),
          if (_scopeText case final String scope)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  scope,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          if (_cursor?.isFromCache == true)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: const Text(
                '当前显示离线缓存，结果可能不完整',
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_searching && _hits.isEmpty) {
      return const AppLoadingView(message: '正在搜索论坛');
    }
    if (_error != null && _hits.isEmpty) {
      return AppErrorView(
        message: _error.toString(),
        onRetry: _activeKeyword.isEmpty
            ? () => unawaited(_prepareScope())
            : () => unawaited(_search(keyword: _activeKeyword)),
      );
    }
    if (_cursor == null) {
      return AppEmptyView(message: _preparing ? '正在读取搜索范围' : '输入关键字搜索论坛主题');
    }
    if (_hits.isEmpty) {
      return AppEmptyView(
        message: '没有找到“$_activeKeyword”相关主题',
        onRefresh: () => _search(keyword: _activeKeyword),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _search(keyword: _activeKeyword),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _hits.length + 1,
        separatorBuilder: (BuildContext context, int index) => Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        itemBuilder: (BuildContext context, int index) {
          if (index == _hits.length) {
            return _buildFooter();
          }
          return _buildHit(_hits[index]);
        },
      ),
    );
  }

  Widget _buildHit(ForumThreadSearchHit hit) {
    final List<String> metadata = <String>[
      if (hit.boardName.isNotEmpty) '#${hit.boardName}',
      if (hit.author.isNotEmpty) hit.author,
      if (hit.timeLabel.isNotEmpty) hit.timeLabel,
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: hit.authorUri == null || (hit.authorId ?? 0) <= 0
          ? const Icon(Icons.forum_outlined)
          : IconButton(
              key: ValueKey<String>('forum-search-author-${hit.authorId}'),
              tooltip: hit.author.isEmpty ? '查看作者资料' : '查看 ${hit.author}',
              onPressed: () => _openAuthor(hit),
              icon: const Icon(Icons.account_circle_outlined),
            ),
      title: Text(hit.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (metadata.isNotEmpty)
            Text(
              metadata.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (hit.summary.isNotEmpty)
            Text(hit.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: Text(
        '${hit.views} / ${hit.replies}',
        style: Theme.of(context).textTheme.labelSmall,
      ),
      onTap: () => widget.onOpenResult(hit),
    );
  }

  void _openAuthor(ForumThreadSearchHit hit) {
    final Uri? uri = hit.authorUri;
    final int userId = hit.authorId ?? 0;
    if (uri == null || userId <= 0) {
      return;
    }
    final ValueChanged<ForumThreadSearchHit>? callback = widget.onOpenAuthor;
    if (callback != null) {
      callback(hit);
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

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return TextButton(
        onPressed: () => unawaited(_loadMore()),
        child: Text('加载失败，点击重试：$_error'),
      );
    }
    if (_cursor?.hasMore == true) {
      return TextButton(
        key: const Key('forum-search-load-more'),
        onPressed: () => unawaited(_loadMore()),
        child: const Text('加载下一页'),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: Text('已显示全部结果')),
    );
  }

  String? get _scopeText {
    final ForumThreadSearchPage? page = _cursor;
    if (page != null) {
      if (page.scopeLabels.isNotEmpty) {
        return page.scopeLabels.join(' · ');
      }
      if (page.boardId != null) {
        return '当前版块 · fid ${page.boardId}';
      }
      return '全部论坛';
    }
    return _preparedScope;
  }

  Future<void> _prepareScope() async {
    final int generation = ++_generation;
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final ForumThreadSearchForm form = await ref
          .read(forumThreadSearchRepositoryProvider)
          .loadForm(widget.formUri);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _preparedScope = form.selectedScopeLabels.isNotEmpty
            ? form.selectedScopeLabels.join(' · ')
            : form.boardId == null
            ? '全部论坛'
            : '当前版块 · fid ${form.boardId}';
      });
    } on ForumSearchRequestSupersededException {
      // 新请求已经接管页面状态。
    } on ForumSessionExpiredException {
      if (mounted && generation == _generation) {
        ref.read(authControllerProvider.notifier).markSessionExpired();
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _preparing = false);
      }
    }
  }

  Future<void> _search({String? keyword}) async {
    final String normalized = (keyword ?? _keywordController.text).trim();
    if (normalized.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入搜索关键字')));
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final int generation = ++_generation;
    setState(() {
      _activeKeyword = normalized;
      _searching = true;
      _loadingMore = false;
      _error = null;
      _cursor = null;
      _hits.clear();
    });
    try {
      final ForumThreadSearchPage page = await ref
          .read(forumThreadSearchRepositoryProvider)
          .search(keyword: normalized, formUri: widget.formUri);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _cursor = page;
        _hits.addAll(page.hits);
      });
    } on ForumSearchRequestSupersededException {
      // 新请求已经接管页面状态。
    } on ForumSessionExpiredException {
      if (mounted && generation == _generation) {
        ref.read(authControllerProvider.notifier).markSessionExpired();
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _loadMore() async {
    final ForumThreadSearchPage? cursor = _cursor;
    if (cursor == null || !cursor.hasMore || _loadingMore) {
      return;
    }
    final int generation = _generation;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final ForumThreadSearchPage page = await ref
          .read(forumThreadSearchRepositoryProvider)
          .loadNext(cursor);
      if (!mounted || generation != _generation) {
        return;
      }
      final Set<String> existing = _hits
          .map(
            (ForumThreadSearchHit hit) => '${hit.threadId}:${hit.postId ?? 0}',
          )
          .toSet();
      setState(() {
        _cursor = page;
        _hits.addAll(
          page.hits.where(
            (ForumThreadSearchHit hit) =>
                existing.add('${hit.threadId}:${hit.postId ?? 0}'),
          ),
        );
      });
    } on ForumSearchRequestSupersededException {
      // 新请求已经接管页面状态。
    } on ForumSessionExpiredException {
      if (mounted && generation == _generation) {
        ref.read(authControllerProvider.notifier).markSessionExpired();
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }
}
