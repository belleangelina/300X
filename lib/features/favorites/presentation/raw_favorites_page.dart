import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/favorites/data/forum_board_favorite_repository.dart';
import 'package:x300/features/favorites/data/raw_favorite_repository.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class RawFavoritesPageController {
  Future<void> Function()? _refreshHandler;

  Future<void> scrollToTopAndRefresh() {
    return _refreshHandler?.call() ?? Future<void>.value();
  }

  void attach(Future<void> Function() handler) {
    _refreshHandler = handler;
  }

  void detach(Future<void> Function() handler) {
    if (identical(_refreshHandler, handler)) {
      _refreshHandler = null;
    }
  }
}

class RawFavoritesPage extends ConsumerStatefulWidget {
  const RawFavoritesPage({
    this.controller,
    this.onOpenThread,
    this.onOpenBoard,
    this.onOpenTarget,
    super.key,
  });

  final RawFavoritesPageController? controller;
  final ValueChanged<RawFavoriteItem>? onOpenThread;
  final ValueChanged<RawFavoriteItem>? onOpenBoard;
  final ValueChanged<RawFavoriteItem>? onOpenTarget;

  @override
  ConsumerState<RawFavoritesPage> createState() {
    return _RawFavoritesPageState();
  }
}

class _RawFavoritesPageState extends ConsumerState<RawFavoritesPage> {
  final ScrollController _scrollController = ScrollController();
  RawFavoritePage? _page;
  Object? _error;
  Object? _loadMoreError;
  bool _loading = true;
  bool _loadingMore = false;
  int _generation = 0;
  final Set<int> _busyFavoriteIds = <int>{};
  String _selectedCategoryKey = RawFavoriteRepository.allCategoryKey;
  late final Future<void> Function() _refreshHandler;

  @override
  void initState() {
    super.initState();
    _refreshHandler = _scrollToTopAndRefresh;
    widget.controller?.attach(_refreshHandler);
    _scrollController.addListener(_handleScroll);
    unawaited(_load(reset: true));
  }

  @override
  void didUpdateWidget(covariant RawFavoritesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach(_refreshHandler);
      widget.controller?.attach(_refreshHandler);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach(_refreshHandler);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildCategoryFilter(),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    final List<RawFavoriteCategory> categories =
        _page?.categories ?? const <RawFavoriteCategory>[];
    final String label =
        _selectedCategoryKey == RawFavoriteRepository.allCategoryKey
        ? '全部'
        : categories
                  .where(
                    (RawFavoriteCategory value) =>
                        value.key == _selectedCategoryKey,
                  )
                  .map((RawFavoriteCategory value) => value.label)
                  .firstOrNull ??
              '全部';
    return SizedBox(
      key: const Key('raw-favorite-category-filter'),
      height: 49,
      child: Column(
        children: <Widget>[
          Expanded(
            child: PopupMenuButton<String>(
              initialValue: _selectedCategoryKey,
              position: PopupMenuPosition.under,
              onSelected: _selectCategory,
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                CheckedPopupMenuItem<String>(
                  value: RawFavoriteRepository.allCategoryKey,
                  checked:
                      _selectedCategoryKey ==
                      RawFavoriteRepository.allCategoryKey,
                  child: const Text('全部'),
                ),
                ...categories
                    .where((RawFavoriteCategory value) => value.label != '全部')
                    .map(
                      (RawFavoriteCategory value) =>
                          CheckedPopupMenuItem<String>(
                            value: value.key,
                            checked: value.key == _selectedCategoryKey,
                            child: Text(value.label),
                          ),
                    ),
              ],
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
          Divider(
            height: 1,
            indent: 12,
            endIndent: 12,
            color: Colors.grey.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final RawFavoritePage? page = _page;
    if (_loading) {
      return const AppLoadingView(message: '正在读取全部收藏');
    }
    if (_error != null) {
      return AppErrorView(
        message: _error.toString(),
        onRetry: () => _load(reset: true),
      );
    }
    if (page == null || page.items.isEmpty) {
      return AppEmptyView(
        message: '当前分类暂无收藏',
        onRefresh: () => _load(reset: true),
      );
    }

    final Widget list = RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        key: const Key('raw-favorites-list'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount:
            page.items.length +
            (_loadingMore || _loadMoreError != null ? 1 : 0),
        separatorBuilder: (BuildContext context, int index) => Divider(
          height: 1,
          indent: 12,
          endIndent: 12,
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        itemBuilder: (BuildContext context, int index) {
          if (index >= page.items.length) {
            if (_loadMoreError != null) {
              return TextButton(
                key: const Key('raw-favorites-load-more-retry'),
                onPressed: () => unawaited(_load(reset: false)),
                child: Text('加载失败，点击重试：$_loadMoreError'),
              );
            }
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _buildItem(page.items[index], page.categories);
        },
      ),
    );
    if (!page.isFromCache) {
      return list;
    }
    final DateTime? updatedAt = page.cacheUpdatedAt;
    final String time = updatedAt == null
        ? ''
        : ' · ${DateFormat('MM-dd HH:mm').format(updatedAt)}';
    return Column(
      children: <Widget>[
        Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: <Widget>[
                const Icon(Icons.cloud_off_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '论坛不可用，当前显示只读收藏缓存$time',
                    style: const TextStyle(fontSize: 12),
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

  Widget _buildItem(
    RawFavoriteItem item,
    List<RawFavoriteCategory> categories,
  ) {
    final VoidCallback? onTap = switch (item.targetKind) {
      RawFavoriteTargetKind.thread
          when item.threadId != null && widget.onOpenThread != null =>
        () => widget.onOpenThread!(item),
      RawFavoriteTargetKind.board
          when item.boardId != null && widget.onOpenBoard != null =>
        () => widget.onOpenBoard!(item),
      RawFavoriteTargetKind.groupBoard ||
      RawFavoriteTargetKind.groupCategory ||
      RawFavoriteTargetKind.blog ||
      RawFavoriteTargetKind.album ||
      RawFavoriteTargetKind.userSpace
          when item.targetId != null && widget.onOpenTarget != null =>
        () => widget.onOpenTarget!(item),
      _ => null,
    };
    final String category =
        categories
            .where((RawFavoriteCategory value) => value.key == item.categoryKey)
            .map((RawFavoriteCategory value) => value.label)
            .firstOrNull ??
        _kindLabel(item.targetKind);
    final String subtitle = item.description.isEmpty
        ? category
        : '$category · ${item.description}';
    final int favoriteId = item.favoriteId ?? 0;
    final bool canRemoveBoard = _page?.isFromCache != true &&
        item.targetKind == RawFavoriteTargetKind.board &&
        item.boardId != null &&
        favoriteId > 0 &&
        item.deleteDialogUri != null;
    return ListTile(
      key: ValueKey<String>('raw-favorite-${item.identityKey}'),
      leading: Icon(_kindIcon(item.targetKind)),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onTap == null && !canRemoveBoard)
            const Text(
              '暂不支持',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded),
          if (canRemoveBoard)
            IconButton(
              key: ValueKey<String>('raw-remove-board-favorite-$favoriteId'),
              tooltip: '取消版块收藏',
              onPressed: _busyFavoriteIds.contains(favoriteId)
                  ? null
                  : () => _removeBoardFavorite(item),
              icon: _busyFavoriteIds.contains(favoriteId)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  Future<void> _removeBoardFavorite(RawFavoriteItem item) async {
    final int favoriteId = item.favoriteId ?? 0;
    if (favoriteId <= 0 || !_busyFavoriteIds.add(favoriteId)) {
      return;
    }
    if (mounted) {
      setState(() {});
    }
    try {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('取消版块收藏'),
          content: Text('确认从收藏中移除“${item.title}”？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认取消'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
      final bool changed = await ref
          .read(forumBoardFavoriteRepositoryProvider)
          .remove(item);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(changed ? '已取消版块收藏' : '该收藏已经不存在')),
      );
      await _load(reset: true);
    } on ForumBoardFavoriteBlockedException catch (blocked) {
      if (mounted) {
        await _resolveBoardFavoriteBlocked(blocked);
      }
    } on ForumSessionExpiredException {
      if (mounted) {
        ref.read(authControllerProvider.notifier).markSessionExpired();
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      _busyFavoriteIds.remove(favoriteId);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _resolveBoardFavoriteBlocked(
    ForumBoardFavoriteBlockedException blocked,
  ) async {
    final bool? shouldRead = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('取消结果尚未确认'),
        content: const Text('请求可能已经执行。请勿重复点击，可先完整回读版块收藏列表。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后处理'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重新回读'),
          ),
        ],
      ),
    );
    if (shouldRead != true || !mounted) {
      return;
    }
    try {
      final ForumBoardFavoriteRepository repository = ref.read(
        forumBoardFavoriteRepositoryProvider,
      );
      if (await repository.readback(blocked)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('收藏列表已确认取消结果')),
          );
          await _load(reset: true);
        }
        return;
      }
      if (!mounted) {
        return;
      }
      final bool? acknowledge = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('仍无法确认'),
          content: const Text(
            '只有在你已到论坛网页人工核对结果后，才能解除防重复封存。解除不会再次提交取消请求。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('保留封存'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('已人工核对，解除'),
            ),
          ],
        ),
      );
      if (acknowledge == true) {
        await repository.acknowledge(blocked);
      }
    } on ForumSessionExpiredException {
      if (mounted) {
        ref.read(authControllerProvider.notifier).markSessionExpired();
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  IconData _kindIcon(RawFavoriteTargetKind kind) {
    return switch (kind) {
      RawFavoriteTargetKind.thread => Icons.article_outlined,
      RawFavoriteTargetKind.board => Icons.view_list_outlined,
      RawFavoriteTargetKind.groupBoard => Icons.forum_outlined,
      RawFavoriteTargetKind.groupCategory => Icons.groups_outlined,
      RawFavoriteTargetKind.blog => Icons.notes_outlined,
      RawFavoriteTargetKind.album => Icons.photo_album_outlined,
      RawFavoriteTargetKind.userSpace => Icons.person_outline,
      RawFavoriteTargetKind.community => Icons.groups_outlined,
      RawFavoriteTargetKind.unknown => Icons.bookmark_outline,
    };
  }

  String _kindLabel(RawFavoriteTargetKind kind) {
    return switch (kind) {
      RawFavoriteTargetKind.thread => '主题',
      RawFavoriteTargetKind.board => '版块',
      RawFavoriteTargetKind.groupBoard => '群组版块',
      RawFavoriteTargetKind.groupCategory => '群组',
      RawFavoriteTargetKind.blog => '日志',
      RawFavoriteTargetKind.album => '相册',
      RawFavoriteTargetKind.userSpace => '用户',
      RawFavoriteTargetKind.community => '社区',
      RawFavoriteTargetKind.unknown => '其他',
    };
  }

  void _selectCategory(String categoryKey) {
    if (categoryKey == _selectedCategoryKey) {
      return;
    }
    setState(() {
      _selectedCategoryKey = categoryKey;
    });
    unawaited(_load(reset: true));
  }

  Future<void> _scrollToTopAndRefresh() async {
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    await _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loadingMore || _page?.hasNext != true)) {
      return;
    }
    final int generation = ++_generation;
    if (reset) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
        _loadMoreError = null;
      });
    } else {
      setState(() {
        _loadingMore = true;
        _loadMoreError = null;
      });
    }
    try {
      final RawFavoriteRepository repository = ref.read(
        rawFavoriteRepositoryProvider,
      );
      final RawFavoritePage page = reset
          ? await repository.loadInitial(
              categoryKey:
                  _selectedCategoryKey == RawFavoriteRepository.allCategoryKey
                  ? null
                  : _selectedCategoryKey,
            )
          : await repository.loadNext(_page!);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _page = page;
        _loading = false;
        _loadingMore = false;
        _error = null;
        _loadMoreError = null;
      });
    } on RawFavoriteRequestSupersededException {
      // 新请求已经接管页面状态。
    } on ForumSessionExpiredException {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      ref.read(authControllerProvider.notifier).markSessionExpired();
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) {
          _error = error;
        } else {
          _loadMoreError = error;
        }
      });
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 360 ||
        _loading ||
        _loadingMore ||
        _page?.isFromCache == true ||
        _page?.hasNext != true) {
      return;
    }
    unawaited(_load(reset: false));
  }
}
