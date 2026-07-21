import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/features/downloads/application/download_manager.dart';
import 'package:x300/features/library/data/work_index_repository.dart';
import 'package:x300/features/settings/application/app_settings_controller.dart';
import 'package:x300/features/settings/data/cache_maintenance_repository.dart';
import 'package:x300/features/settings/domain/app_settings.dart';
import 'package:x300/shared/presentation/app_snack_bar.dart';

class SettingsPage extends ConsumerStatefulWidget
{
    const SettingsPage({this.initialIndex = 0, super.key});

    final int initialIndex;

    @override
    ConsumerState<SettingsPage> createState()
    {
        return _SettingsPageState();
    }
}

class _SettingsPageState extends ConsumerState<SettingsPage>
{
    bool _clearing = false;
    bool _clearingCovers = false;
    bool _clearingIndex = false;
    bool _measuringCache = true;
    CacheUsageSnapshot? _cacheUsage;

    @override
    void initState()
    {
        super.initState();
        WidgetsBinding.instance.addPostFrameCallback((Duration _)
        {
            if (mounted)
            {
                unawaited(_refreshCacheUsage());
            }
        });
    }

    @override
    Widget build(BuildContext context)
    {
        final AppSettings settings = ref.watch(
            appSettingsControllerProvider,
        );
        return DefaultTabController(
            length: 4,
            initialIndex: widget.initialIndex,
            child: Scaffold(
                appBar: AppBar(title: const Text('更多设置')),
                body: TabBarView(
                    children: <Widget>[
                        _buildGeneral(settings),
                        _buildComic(settings),
                        _buildNovel(settings),
                        _buildDownloads(settings),
                    ],
                ),
                bottomNavigationBar: Material(
                    key: const Key('settings-bottom-tabs'),
                    elevation: 8,
                    color: Theme.of(context).colorScheme.surface,
                    child: SafeArea(
                        top: false,
                        child: TabBar(
                            indicatorSize: TabBarIndicatorSize.label,
                            indicatorColor:
                                Theme.of(context).colorScheme.primary,
                            labelColor:
                                Theme.of(context).colorScheme.primary,
                            unselectedLabelColor:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white70
                                    : Colors.black87,
                            tabs: const <Tab>[
                                Tab(text: '常规'),
                                Tab(text: '漫画'),
                                Tab(text: '小说'),
                                Tab(text: '下载'),
                            ],
                        ),
                    ),
                ),
            ),
        );
    }

    Widget _buildGeneral(AppSettings settings)
    {
        return ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
                ListTile(
                    title: const Text('清除临时缓存'),
                    subtitle: Text(
                        '${_cacheSizeText(_cacheUsage?.temporaryBytes)}\n'
                        '清除搜索、云收藏和在线正文图片缓存，'
                        '保留作品索引、历史与离线下载',
                    ),
                    trailing: OutlinedButton(
                        onPressed: _clearing ? null : _clearCaches,
                        child: Text(_clearing ? '清理中' : '清除'),
                    ),
                ),
                ListTile(
                    title: const Text('清除封面缓存'),
                    subtitle: Text(
                        '${_cacheSizeText(_cacheUsage?.coverBytes)}\n'
                        '删除已缓存的漫画和小说封面，'
                        '不影响作品索引、历史与离线下载',
                    ),
                    trailing: OutlinedButton(
                        onPressed:
                            _clearingCovers ? null : _clearCoverCaches,
                        child: Text(_clearingCovers ? '清理中' : '清除'),
                    ),
                ),
                ListTile(
                    title: const Text('清除作品索引'),
                    subtitle: const Text(
                        '删除已建立的漫画和小说目录索引，不删除历史与离线下载',
                    ),
                    trailing: OutlinedButton(
                        onPressed: _clearingIndex ? null : _clearWorkIndexes,
                        child: Text(_clearingIndex ? '清理中' : '清除'),
                    ),
                ),
                SwitchListTile(
                    value: settings.useSystemTextScale,
                    onChanged: (bool value) => _update(
                        settings.copyWith(useSystemTextScale: value),
                    ),
                    title: const Text('字体大小跟随系统'),
                    subtitle: const Text('关闭后使用应用设计字号'),
                ),
            ],
        );
    }

    Widget _buildComic(AppSettings settings)
    {
        return ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
                _DirectionTile(
                    value: settings.comicDirection,
                    onChanged: (ReaderDirection value) => _update(
                        settings.copyWith(comicDirection: value),
                    ),
                ),
                SwitchListTile(
                    value: settings.comicReverseControls,
                    onChanged: (bool value) => _update(
                        settings.copyWith(comicReverseControls: value),
                    ),
                    title: const Text('操作反转'),
                    subtitle: const Text('点击左侧下一页，右侧上一页'),
                ),
                SwitchListTile(
                    value: settings.comicFullScreen,
                    onChanged: (bool value) => _update(
                        settings.copyWith(comicFullScreen: value),
                    ),
                    title: const Text('全屏阅读'),
                ),
                SwitchListTile(
                    value: settings.comicShowStatus,
                    onChanged: (bool value) => _update(
                        settings.copyWith(comicShowStatus: value),
                    ),
                    title: const Text('显示状态信息'),
                ),
                SwitchListTile(
                    value: settings.comicPageAnimation,
                    onChanged: (bool value) => _update(
                        settings.copyWith(comicPageAnimation: value),
                    ),
                    title: const Text('翻页动画'),
                ),
                ListTile(
                    title: const Text('预加载'),
                    trailing: SegmentedButton<int>(
                        segments: const <ButtonSegment<int>>[
                            ButtonSegment<int>(
                                value: 1,
                                label: Text('1页'),
                            ),
                            ButtonSegment<int>(
                                value: 3,
                                label: Text('3页'),
                            ),
                            ButtonSegment<int>(
                                value: 5,
                                label: Text('5页'),
                            ),
                        ],
                        selected: <int>{settings.comicPreloadPages},
                        showSelectedIcon: false,
                        onSelectionChanged: (Set<int> values) => _update(
                            settings.copyWith(
                                comicPreloadPages: values.first,
                            ),
                        ),
                    ),
                ),
            ],
        );
    }

    Widget _buildNovel(AppSettings settings)
    {
        final Color background = _novelBackground(settings.novelPalette);
        final Color foreground = _novelForeground(settings.novelPalette);
        return ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
                _DirectionTile(
                    value: settings.novelDirection,
                    onChanged: (ReaderDirection value) => _update(
                        settings.copyWith(novelDirection: value),
                    ),
                ),
                SwitchListTile(
                    value: settings.novelReverseControls,
                    onChanged: (bool value) => _update(
                        settings.copyWith(novelReverseControls: value),
                    ),
                    title: const Text('操作反转'),
                    subtitle: const Text('点击左侧下一页，右侧上一页'),
                ),
                SwitchListTile(
                    value: settings.novelShowStatus,
                    onChanged: (bool value) => _update(
                        settings.copyWith(novelShowStatus: value),
                    ),
                    title: const Text('显示状态信息'),
                ),
                SwitchListTile(
                    value: settings.novelPageAnimation,
                    onChanged: (bool value) => _update(
                        settings.copyWith(novelPageAnimation: value),
                    ),
                    title: const Text('翻页动画'),
                ),
                ListTile(
                    title: const Text('字体大小'),
                    subtitle: Slider(
                        value: settings.novelFontSize,
                        min: 13,
                        max: 30,
                        divisions: 17,
                        label: settings.novelFontSize.round().toString(),
                        onChanged: (double value) => _update(
                            settings.copyWith(novelFontSize: value),
                        ),
                    ),
                    trailing: Text('${settings.novelFontSize.round()}'),
                ),
                ListTile(
                    title: const Text('行距'),
                    subtitle: Slider(
                        value: settings.novelLineHeight,
                        min: 1.3,
                        max: 2.3,
                        divisions: 10,
                        label: settings.novelLineHeight.toStringAsFixed(1),
                        onChanged: (double value) => _update(
                            settings.copyWith(novelLineHeight: value),
                        ),
                    ),
                    trailing: Text(
                        settings.novelLineHeight.toStringAsFixed(1),
                    ),
                ),
                ListTile(
                    title: const Text('阅读主题'),
                    trailing: SegmentedButton<NovelReaderPalette>(
                        segments: NovelReaderPalette.values
                            .map(
                                (NovelReaderPalette value) =>
                                    ButtonSegment<NovelReaderPalette>(
                                        value: value,
                                        label: Text(value.label),
                                    ),
                            )
                            .toList(growable: false),
                        selected: <NovelReaderPalette>{
                            settings.novelPalette,
                        },
                        showSelectedIcon: false,
                        onSelectionChanged: (
                            Set<NovelReaderPalette> values,
                        ) => _update(
                            settings.copyWith(
                                novelPalette: values.first,
                            ),
                        ),
                    ),
                ),
                Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                        '这是一段测试文字，可以预览上面的字号、行距和阅读主题。\n\n'
                        '保持从容阅读，让设置在下一次打开章节时继续生效。',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                            color: foreground,
                            fontSize: settings.novelFontSize,
                            height: settings.novelLineHeight,
                        ),
                    ),
                ),
            ],
        );
    }

    Widget _buildDownloads(AppSettings settings)
    {
        return ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
                SwitchListTile(
                    value: settings.allowMobileDownloads,
                    onChanged: (bool value) => _update(
                        settings.copyWith(allowMobileDownloads: value),
                    ),
                    title: const Text('允许使用移动网络下载'),
                    subtitle: const Text('关闭时 Android/iOS 仅在 Wi-Fi 或有线网络下载'),
                ),
                ListTile(
                    title: const Text('漫画最大任务数'),
                    trailing: _TaskLimitValue(
                        value: settings.comicMaximumDownloads,
                    ),
                    onTap: () => _showDownloadLimit(
                        settings: settings,
                        comic: true,
                    ),
                ),
                ListTile(
                    title: const Text('小说最大任务数'),
                    trailing: _TaskLimitValue(
                        value: settings.novelMaximumDownloads,
                    ),
                    onTap: () => _showDownloadLimit(
                        settings: settings,
                        comic: false,
                    ),
                ),
            ],
        );
    }

    void _update(AppSettings settings)
    {
        ref.read(appSettingsControllerProvider.notifier).update(settings);
    }

    Future<void> _showDownloadLimit({
        required AppSettings settings,
        required bool comic,
    }) async
    {
        final int current = comic
            ? settings.comicMaximumDownloads
            : settings.novelMaximumDownloads;
        final int? selected = await showDialog<int>(
            context: context,
            builder: (BuildContext context) => SimpleDialog(
                title: Text(comic ? '漫画最大任务数' : '小说最大任务数'),
                children: List<Widget>.generate(5, (int index)
                {
                    final int value = index + 1;
                    return SimpleDialogOption(
                        onPressed: () => Navigator.of(context).pop(value),
                        child: Row(
                            children: <Widget>[
                                Icon(
                                    value == current
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: value == current
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey,
                                ),
                                const SizedBox(width: 12),
                                Text('$value 个'),
                            ],
                        ),
                    );
                }),
            ),
        );
        if (selected == null || !mounted)
        {
            return;
        }
        _update(
            comic
                ? settings.copyWith(comicMaximumDownloads: selected)
                : settings.copyWith(novelMaximumDownloads: selected),
        );
        ref.read(downloadManagerProvider).refreshLimits();
    }

    Future<void> _clearCaches() async
    {
        final bool? confirmed = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
                title: const Text('清除临时缓存？'),
                content: const Text(
                    '将删除搜索、云收藏和在线正文图片缓存。'
                    '作品索引、阅读历史和离线下载不会被删除。',
                ),
                actions: <Widget>[
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                    ),
                    FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('确认清除'),
                    ),
                ],
            ),
        );
        if (confirmed != true || !mounted)
        {
            return;
        }
        setState(()
        {
            _clearing = true;
        });
        try
        {
            await ref
                .read(cacheMaintenanceRepositoryProvider)
                .clearTemporaryCaches();
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
            await _refreshCacheUsage(showLoading: false);
            if (mounted)
            {
                ScaffoldMessenger.of(context).showSnackBar(
                    const AppSnackBar(content: Text('临时缓存已清除')),
                );
            }
        }
        finally
        {
            if (mounted)
            {
                setState(()
                {
                    _clearing = false;
                });
            }
        }
    }

    Future<void> _clearCoverCaches() async
    {
        final bool? confirmed = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
                title: const Text('清除封面缓存？'),
                content: const Text(
                    '将删除已缓存的漫画和小说封面。作品索引、阅读历史和离线下载不会被删除。',
                ),
                actions: <Widget>[
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                    ),
                    FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('确认清除'),
                    ),
                ],
            ),
        );
        if (confirmed != true || !mounted)
        {
            return;
        }
        setState(()
        {
            _clearingCovers = true;
        });
        try
        {
            await ref
                .read(cacheMaintenanceRepositoryProvider)
                .clearCoverCaches();
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
            await _refreshCacheUsage(showLoading: false);
            if (mounted)
            {
                ScaffoldMessenger.of(context).showSnackBar(
                    const AppSnackBar(content: Text('封面缓存已清除')),
                );
            }
        }
        finally
        {
            if (mounted)
            {
                setState(()
                {
                    _clearingCovers = false;
                });
            }
        }
    }

    Future<void> _refreshCacheUsage({bool showLoading = true}) async
    {
        if (showLoading && mounted)
        {
            setState(()
            {
                _measuringCache = true;
            });
        }
        try
        {
            final CacheUsageSnapshot usage = await ref
                .read(cacheMaintenanceRepositoryProvider)
                .measureUsage();
            if (mounted)
            {
                setState(()
                {
                    _cacheUsage = usage;
                    _measuringCache = false;
                });
            }
        }
        on Object
        {
            if (mounted)
            {
                setState(()
                {
                    _cacheUsage = null;
                    _measuringCache = false;
                });
            }
        }
    }

    String _cacheSizeText(int? bytes)
    {
        if (_measuringCache)
        {
            return '当前大小：正在计算';
        }
        if (bytes == null)
        {
            return '当前大小：暂时无法统计';
        }
        return '当前大小：约 ${_formatBytes(bytes)}';
    }

    String _formatBytes(int bytes)
    {
        if (bytes < 1024)
        {
            return '$bytes B';
        }
        final double kibibytes = bytes / 1024;
        if (kibibytes < 1024)
        {
            return '${kibibytes.toStringAsFixed(1)} KB';
        }
        final double mebibytes = kibibytes / 1024;
        if (mebibytes < 1024)
        {
            return '${mebibytes.toStringAsFixed(1)} MB';
        }
        return '${(mebibytes / 1024).toStringAsFixed(1)} GB';
    }

    Future<void> _clearWorkIndexes() async
    {
        final bool? confirmed = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
                title: const Text('清除作品索引？'),
                content: const Text(
                    '下次从主页打开作品时会重新解析目录。阅读历史和离线下载不会被删除。',
                ),
                actions: <Widget>[
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                    ),
                    FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('确认清除'),
                    ),
                ],
            ),
        );
        if (confirmed != true || !mounted)
        {
            return;
        }
        setState(()
        {
            _clearingIndex = true;
        });
        try
        {
            await ref.read(workIndexRepositoryProvider).clearAll();
            if (mounted)
            {
                ScaffoldMessenger.of(context).showSnackBar(
                    const AppSnackBar(content: Text('作品索引已清除')),
                );
            }
        }
        finally
        {
            if (mounted)
            {
                setState(()
                {
                    _clearingIndex = false;
                });
            }
        }
    }

    Color _novelBackground(NovelReaderPalette palette)
    {
        return switch (palette)
        {
            NovelReaderPalette.light => const Color(0xfffafafa),
            NovelReaderPalette.sepia => const Color(0xfff4ecd8),
            NovelReaderPalette.dark => const Color(0xff171717),
        };
    }

    Color _novelForeground(NovelReaderPalette palette)
    {
        return palette == NovelReaderPalette.dark
            ? const Color(0xffdddddd)
            : const Color(0xff333333);
    }
}

class _TaskLimitValue extends StatelessWidget
{
    const _TaskLimitValue({required this.value});

    final int value;

    @override
    Widget build(BuildContext context)
    {
        return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
                Text('$value'),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.grey),
            ],
        );
    }
}

class _DirectionTile extends StatelessWidget
{
    const _DirectionTile({required this.value, required this.onChanged});

    final ReaderDirection value;
    final ValueChanged<ReaderDirection> onChanged;

    @override
    Widget build(BuildContext context)
    {
        return ListTile(
            title: const Text('阅读方向'),
            trailing: SegmentedButton<ReaderDirection>(
                segments: const <ButtonSegment<ReaderDirection>>[
                    ButtonSegment<ReaderDirection>(
                        value: ReaderDirection.leftToRight,
                        icon: Icon(Icons.arrow_forward),
                    ),
                    ButtonSegment<ReaderDirection>(
                        value: ReaderDirection.rightToLeft,
                        icon: Icon(Icons.arrow_back),
                    ),
                    ButtonSegment<ReaderDirection>(
                        value: ReaderDirection.vertical,
                        icon: Icon(Icons.arrow_downward),
                    ),
                ],
                selected: <ReaderDirection>{value},
                showSelectedIcon: false,
                onSelectionChanged: (Set<ReaderDirection> values) =>
                    onChanged(values.first),
            ),
        );
    }
}
