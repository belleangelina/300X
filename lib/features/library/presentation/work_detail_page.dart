import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x300/features/downloads/application/download_manager.dart';
import 'package:x300/features/downloads/data/download_repository.dart';
import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/favorites/data/forum_favorite_repository.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/history/data/reading_history_repository.dart';
import 'package:x300/features/history/domain/reading_history_models.dart';
import 'package:x300/features/library/application/work_index_coordinator.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/data/work_index_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/reader/presentation/chapter_reader_page.dart';
import 'package:x300/features/search/presentation/search_page.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/shared/presentation/app_snack_bar.dart';

const String _smartDirectoryId = 'display:smart';

typedef WorkDetailResolver =
        Future<WorkIndexResult> Function(
            WorkIndexCancellation cancellation,
            WorkIndexProgress onProgress,
        );

class WorkDetailPage extends ConsumerStatefulWidget
{
    const WorkDetailPage({
        required this.work,
        this.embedded = false,
        this.initialSourceTid,
        this.resolveOnOpen = false,
        this.resolver,
        this.rawSourceMode = false,
        super.key,
    });

    final Work work;
    final bool embedded;
    final int? initialSourceTid;
    final bool resolveOnOpen;
    final WorkDetailResolver? resolver;
    final bool rawSourceMode;

    @override
    ConsumerState<WorkDetailPage> createState()
    {
        return _WorkDetailPageState();
    }
}

class _WorkDetailPageState extends ConsumerState<WorkDetailPage>
{
    late Work _work;
    late Future<List<CloudFavoriteRecord>> _favoriteFuture;
    late Future<ReadingHistoryEntry?> _historyFuture;
    bool _favoriteBusy = false;
    bool _refreshing = false;
    String _refreshMessage = '正在更新作品索引';
    double? _refreshProgress;
    bool _resolving = false;
    bool _coverFinalized = false;
    bool _coverRefreshing = false;
    String _resolutionMessage = '正在检查本机作品索引';
    double? _resolutionProgress;
    Object? _resolutionError;
    String? _resolutionWarning;
    WorkIndexCancellation? _indexCancellation;
    bool _chaptersAscending = true;
    bool _showAllChapters = false;
    bool _summaryExpanded = false;
    String? _selectedDirectoryId;
    NovelEdition? _selectedNovelEdition;
    late _ChapterDirectoryView _directoryView;

    @override
    void initState()
    {
        super.initState();
        _work = widget.work;
        _selectedDirectoryId = _initialDirectoryId(_work, widget.initialSourceTid);
        _selectedNovelEdition = _initialNovelEdition(
            _work,
            _selectedDirectoryId!,
            widget.initialSourceTid,
        );
        _favoriteFuture = _loadFavoriteStatus();
        _historyFuture = _loadHistory();
        _restoreSelectionFromHistory();
        _restoreDirectoryPreferences();
        if (!widget.rawSourceMode)
        {
            if (_shouldResolveOnOpen)
            {
                unawaited(_resolveInitialWork());
            } else
            {
                unawaited(_restoreIndexedWork());
            }
        }
    }

    @override
    void didUpdateWidget(covariant WorkDetailPage oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        if (!identical(oldWidget.work, widget.work))
        {
            _indexCancellation?.cancel();
            _refreshing = false;
            _resolving = false;
            final bool changedWork = oldWidget.work.id != widget.work.id;
            _work = widget.work;
            _coverFinalized = false;
            if (changedWork)
            {
                _favoriteFuture = _loadFavoriteStatus();
                _historyFuture = _loadHistory();
                _favoriteBusy = false;
                _showAllChapters = false;
                _summaryExpanded = false;
                _selectedDirectoryId = _initialDirectoryId(
                    _work,
                    widget.initialSourceTid,
                );
                _selectedNovelEdition = _initialNovelEdition(
                    _work,
                    _selectedDirectoryId!,
                    widget.initialSourceTid,
                );
                _restoreDirectoryPreferences();
            }
            _resolutionError = null;
            _resolutionWarning = null;
            if (changedWork)
            {
                _restoreSelectionFromHistory();
            }
            if (!widget.rawSourceMode)
            {
                if (_shouldResolveOnOpen)
                {
                    unawaited(_resolveInitialWork());
                } else
                {
                    unawaited(_restoreIndexedWork());
                }
            }
        }
    }

    @override
    void dispose()
    {
        _indexCancellation?.cancel();
        super.dispose();
    }

    bool get _shouldResolveOnOpen =>
            widget.resolveOnOpen || widget.resolver != null;

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            appBar: widget.embedded
                    ? null
                    : AppBar(
                            title: InkWell(
                                onTap: _showFullTitles,
                                child: Text(
                                    _work.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                ),
                            ),
                            actions: widget.rawSourceMode
                                    ? null
                                    : <Widget>[
                                            IconButton(
                                                tooltip: '搜索原始帖子',
                                                onPressed: _resolving
                                                        ? null
                                                        : _openSourceSearch,
                                                icon: const Icon(Icons.search),
                                            ),
                                        ],
                        ),
            body: _buildDetail(),
            bottomNavigationBar: _buildBottomActionBar(),
        );
    }

    Future<void> _resolveInitialWork() async
    {
        _indexCancellation?.cancel();
        final WorkIndexCancellation cancellation = WorkIndexCancellation();
        _indexCancellation = cancellation;
        if (mounted)
        {
            setState(()
        {
                _resolving = true;
                _resolutionMessage = '正在检查本机作品索引';
                _resolutionProgress = null;
                _resolutionError = null;
                _resolutionWarning = null;
            });
        }
        final CoverLoadCoordinator coverCoordinator = ref.read(
            coverLoadCoordinatorProvider,
        );
        coverCoordinator.beginCriticalOperation();
        try
        {
            final WorkDetailResolver resolver =
                    widget.resolver ??
                    (WorkIndexCancellation cancellation, WorkIndexProgress onProgress) =>
                            ref
                                    .read(workIndexCoordinatorProvider)
                                    .ensure(
                                        _work,
                                        onProgress: onProgress,
                                        cancellation: cancellation,
                                    );
            final WorkIndexResult result = await resolver(
                cancellation,
                _updateResolutionProgress,
            );
            cancellation.throwIfCancelled();
            if (!mounted || !identical(_indexCancellation, cancellation))
            {
                return;
            }
            final bool changedId = _work.id != result.work.id;
            setState(()
            {
                _work = result.work;
                _coverFinalized = true;
                _selectedDirectoryId = _initialDirectoryId(
                    result.work,
                    widget.initialSourceTid,
                );
                _selectedNovelEdition = _initialNovelEdition(
                    result.work,
                    _selectedDirectoryId!,
                    widget.initialSourceTid,
                );
                _resolving = false;
                _showAllChapters = false;
                _resolutionWarning =
                        result.warning ??
                        (result.updateAvailable ? '发现可能的新章节，可下拉刷新作品索引。' : null);
                _favoriteFuture = _loadFavoriteStatus();
                if (changedId)
                {
                    _historyFuture = _loadHistory();
                }
            });
            if (changedId)
            {
                _restoreSelectionFromHistory();
            }
        } on WorkIndexCancelledException
        {
            return;
        } on Object catch (error)
        {
            if (!mounted || !identical(_indexCancellation, cancellation))
            {
                return;
            }
            setState(()
            {
                _resolving = false;
                _resolutionError = error;
            });
        }
        finally
        {
            coverCoordinator.endCriticalOperation();
        }
    }

    void _updateResolutionProgress(String message)
    {
        if (mounted && _resolving)
        {
            setState(()
        {
                _resolutionMessage = message;
                _resolutionProgress = _progressValue(message);
            });
        }
    }

    Future<void> _restoreIndexedWork() async
    {
        final Work requested = _work;
        WorkIndexRecord? record;
        try
        {
            record = await ref.read(workIndexCoordinatorProvider).lookup(requested);
        } on Object
        {
            return;
        }
        if (!mounted || record == null || _work.id != requested.id)
        {
            return;
        }
        final Work indexedWork = record.work;
        setState(()
        {
            final bool changedId = _work.id != indexedWork.id;
            _work = indexedWork;
            _coverFinalized = true;
            _selectedDirectoryId = _restoredDirectoryId(indexedWork);
            _selectedNovelEdition = _restoredNovelEdition(
                indexedWork,
                _selectedDirectoryId!,
            );
            _favoriteFuture = _loadFavoriteStatus();
            if (changedId)
            {
                _historyFuture = _loadHistory();
            }
        });
    }

    Future<List<CloudFavoriteRecord>> _loadFavoriteStatus()
    {
        return ref.read(forumFavoriteRepositoryProvider).findForWork(_work);
    }

    Future<ReadingHistoryEntry?> _loadHistory()
    {
        return ref.read(readingHistoryRepositoryProvider).get(_work.id);
    }

    void _restoreSelectionFromHistory()
    {
        if (_work.kind != LibraryKind.novel)
        {
            return;
        }
        final Work requested = _work;
        unawaited(
            _historyFuture.then((ReadingHistoryEntry? history)
        {
                if (!mounted || history == null || _work.id != requested.id)
                {
                    return;
                }
                for (final WorkDirectory directory in _directoriesFor(_work))
                {
                    for (final Chapter chapter in directory.chapters)
                    {
                        if (chapter.id != history.chapterId)
                        {
                            continue;
                        }
                        setState(()
                        {
                            _selectedDirectoryId = directory.id;
                            _selectedNovelEdition = _novelEditionForChapter(chapter);
                            _showAllChapters = false;
                        });
                        return;
                    }
                }
            }),
        );
    }

    List<WorkDirectory> _directoriesFor(Work work)
    {
        if (work.directories.isNotEmpty)
        {
            if (!_shouldShowSmartDirectory(work))
            {
                return work.directories;
            }
            return <WorkDirectory>[
                WorkDirectory(
                    id: _smartDirectoryId,
                    owner: '智能聚合',
                    sourceTids: work.chapters
                            .map((Chapter chapter) => chapter.sourceTid)
                            .toSet()
                            .toList(growable: false),
                    chapters: work.chapters,
                ),
                ...work.directories,
            ];
        }
        return <WorkDirectory>[
            WorkDirectory(
                id: 'display:default',
                owner: work.author,
                sourceTids: <int>{
                    ...work.sourceThreads.map((SourceThread thread) => thread.tid),
                    ...work.chapters.map((Chapter chapter) => chapter.sourceTid),
                }.toList(growable: false),
                chapters: work.chapters,
            ),
        ];
    }

    bool _shouldShowSmartDirectory(Work work)
    {
        if (work.directories.length < 2)
        {
            return false;
        }
        if (work.kind != LibraryKind.novel)
        {
            return true;
        }
        final Set<String> smartChapterIds = work.chapters
                .map((Chapter chapter) => chapter.id)
                .toSet();
        int sourceCount = 0;
        for (final WorkDirectory directory in work.directories)
        {
            if (!directory.chapters.any(
                (Chapter chapter) => smartChapterIds.contains(chapter.id),
            ))
            {
                continue;
            }
            sourceCount++;
            if (sourceCount >= 2)
            {
                return true;
            }
        }
        return false;
    }

    String _initialDirectoryId(Work work, int? sourceTid)
    {
        final List<WorkDirectory> directories = _directoriesFor(work);
        if (directories.first.id == _smartDirectoryId)
        {
            return _smartDirectoryId;
        }
        if (sourceTid != null)
        {
            for (final WorkDirectory directory in directories)
            {
                if (directory.sourceTids.contains(sourceTid))
                {
                    return directory.id;
                }
            }
        }
        return directories.first.id;
    }

    NovelEdition? _initialNovelEdition(
        Work work,
        String directoryId,
        int? sourceTid,
    )
    {
        if (work.kind != LibraryKind.novel)
        {
            return null;
        }
        final WorkDirectory directory = _directoriesFor(work).firstWhere(
            (WorkDirectory value) => value.id == directoryId,
            orElse: () => _directoriesFor(work).first,
        );
        if (sourceTid != null)
        {
            for (final Chapter chapter in directory.chapters)
            {
                if (chapter.sourceTid == sourceTid)
                {
                    return _novelEditionForChapter(chapter);
                }
            }
        }
        return _mostCompleteNovelEdition(directory);
    }

    NovelEdition? _restoredNovelEdition(Work work, String directoryId)
    {
        if (work.kind != LibraryKind.novel)
        {
            return null;
        }
        final WorkDirectory directory = _directoriesFor(work).firstWhere(
            (WorkDirectory value) => value.id == directoryId,
            orElse: () => _directoriesFor(work).first,
        );
        final List<NovelEdition> editions = _novelEditionsFor(directory);
        if (_selectedNovelEdition != null &&
                editions.contains(_selectedNovelEdition))
        {
            return _selectedNovelEdition;
        }
        return _mostCompleteNovelEdition(directory);
    }

    NovelEdition _mostCompleteNovelEdition(WorkDirectory directory)
    {
        final Map<NovelEdition, int> counts = <NovelEdition, int>{
            for (final NovelEdition edition in NovelEdition.values) edition: 0,
        };
        for (final Chapter chapter in directory.chapters)
        {
            final NovelEdition edition = _novelEditionForChapter(chapter);
            counts[edition] = counts[edition]! + 1;
        }
        return counts[NovelEdition.book]! > counts[NovelEdition.serial]!
                ? NovelEdition.book
                : NovelEdition.serial;
    }

    NovelEdition _novelEditionForChapter(Chapter chapter)
    {
        return chapter.novelEdition ?? NovelEdition.serial;
    }

    List<NovelEdition> _novelEditionsFor(WorkDirectory directory)
    {
        return NovelEdition.values
                .where(
                    (NovelEdition edition) => directory.chapters.any(
                        (Chapter chapter) => _novelEditionForChapter(chapter) == edition,
                    ),
                )
                .toList(growable: false);
    }

    List<Chapter> _chaptersForDirectory(WorkDirectory directory)
    {
        if (_work.kind != LibraryKind.novel)
        {
            return directory.chapters;
        }
        final NovelEdition edition =
                _selectedNovelEdition ?? _mostCompleteNovelEdition(directory);
        return directory.chapters
                .where((Chapter chapter) => _novelEditionForChapter(chapter) == edition)
                .toList(growable: false);
    }

    String _restoredDirectoryId(Work work)
    {
        final List<WorkDirectory> directories = _directoriesFor(work);
        if (directories.any(
            (WorkDirectory directory) => directory.id == _selectedDirectoryId,
        ))
        {
            return _selectedDirectoryId!;
        }
        return directories.first.id;
    }

    WorkDirectory get _selectedDirectory
    {
        final List<WorkDirectory> directories = _directoriesFor(_work);
        return directories.firstWhere(
            (WorkDirectory directory) => directory.id == _selectedDirectoryId,
            orElse: () => directories.first,
        );
    }

    Work get _selectedWork
    {
        final WorkDirectory directory = _selectedDirectory;
        final List<Chapter> chapters = _chaptersForDirectory(directory);
        final Set<int> tids = chapters
                .map((Chapter chapter) => chapter.sourceTid)
                .toSet();
        final List<SourceThread> sourceThreads = _work.sourceThreads
                .where((SourceThread thread) => tids.contains(thread.tid))
                .toList(growable: false);
        return Work(
            id: _work.id,
            kind: _work.kind,
            title: _work.title,
            summary: _work.summary,
            author: directory.id == _smartDirectoryId
                    ? _work.author
                    : directory.owner,
            typeName: _work.typeName,
            sourceThreads: sourceThreads.isEmpty
                    ? _work.sourceThreads
                    : sourceThreads,
            chapters: chapters,
            directories: _work.directories,
        );
    }

    Widget _buildDetail()
    {
        final List<Chapter> chapters = _chaptersForDirectory(_selectedDirectory);
        final Widget content = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
                if (_refreshing) ...<Widget>[
                    LinearProgressIndicator(value: _refreshProgress),
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                            _refreshMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                    ),
                ],
                _WorkHeader(
                    work: _selectedWork,
                    coverFinalized: _coverFinalized,
                    coverEntryTid: widget.initialSourceTid,
                    onReparseCover: _coverFinalized && !_coverRefreshing
                            ? _reparseCover
                            : null,
                    summary: _work.summary,
                    summaryExpanded: _summaryExpanded,
                    onSearch: widget.embedded &&
                                    !widget.rawSourceMode &&
                                    !_resolving
                            ? _openSourceSearch
                            : null,
                    onShowFullTitles: _showFullTitles,
                    onToggleSummary: () => setState(()
                {
                        _summaryExpanded = !_summaryExpanded;
                    }),
                ),
                if (widget.rawSourceMode)
                    _buildDetailNotice(
                        icon: Icons.warning_amber_rounded,
                        message: '当前显示原始帖子，未进行作品聚合；目录可能不完整。',
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                    ),
                if (_resolving) _buildResolutionProgress(),
                if (_resolutionError != null)
                    _buildDetailNotice(
                        icon: Icons.sync_problem_outlined,
                        message: '目录解析失败：$_resolutionError',
                        color: Theme.of(context).colorScheme.errorContainer,
                        actionLabel: '重试',
                        onAction: _resolveInitialWork,
                    ),
                if (_resolutionWarning != null)
                    _buildDetailNotice(
                        icon: Icons.info_outline,
                        message: _resolutionWarning!,
                        color: Theme.of(context).colorScheme.secondaryContainer,
                    ),
                if (!_resolving) ...<Widget>[
                    _buildHistoryEntry(chapters),
                    Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: Colors.grey.withValues(alpha: 0.2),
                    ),
                    _buildDirectoryHeader(chapters),
                    if (chapters.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                '未解析到可读章节，请从原帖查看权限提示。',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                            ),
                        )
                    else
                        _buildChapterDirectory(chapters),
                ],
            ],
        );
        if (widget.rawSourceMode || _resolving)
        {
            return content;
        }
        return RefreshIndicator(onRefresh: _refreshIndex, child: content);
    }

    Widget _buildResolutionProgress()
    {
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        children: <Widget>[
                            LinearProgressIndicator(value: _resolutionProgress),
                            const SizedBox(height: 14),
                            Text(_resolutionMessage, textAlign: TextAlign.center),
                            const SizedBox(height: 6),
                            const Text(
                                '退出当前详情页会取消解析',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                        ],
                    ),
                ),
            ),
        );
    }

    Widget _buildDetailNotice({
        required IconData icon,
        required String message,
        required Color color,
        String? actionLabel,
        VoidCallback? onAction,
    })
    {
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Material(
                color: color,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                        children: <Widget>[
                            Icon(icon, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(message, style: const TextStyle(fontSize: 12)),
                            ),
                            if (actionLabel != null)
                                TextButton(onPressed: onAction, child: Text(actionLabel)),
                        ],
                    ),
                ),
            ),
        );
    }

    Widget _buildBottomActionBar()
    {
        final List<Chapter> chapters = _resolving
                ? const <Chapter>[]
                : _chaptersForDirectory(_selectedDirectory);
        return BottomAppBar(
            child: SafeArea(
                top: false,
                child: SizedBox(
                    height: 56,
                    child: Row(
                        children: <Widget>[
                            Expanded(
                                child: TextButton.icon(
                                    onPressed: _openOriginal,
                                    icon: const Icon(Icons.open_in_browser_outlined),
                                    label: const Text('原帖'),
                                ),
                            ),
                            Expanded(
                                child: TextButton.icon(
                                    onPressed: chapters.isEmpty
                                            ? null
                                            : () => _chooseDownloads(chapters),
                                    icon: const Icon(Icons.download_outlined),
                                    label: const Text('下载'),
                                ),
                            ),
                            Expanded(child: _buildFavoriteButton()),
                            Expanded(child: _buildReadButton(chapters)),
                        ],
                    ),
                ),
            ),
        );
    }

    Widget _buildReadButton(List<Chapter> chapters)
    {
        return FutureBuilder<ReadingHistoryEntry?>(
            future: _historyFuture,
            builder:
                    (BuildContext context, AsyncSnapshot<ReadingHistoryEntry?> snapshot)
                    {
                        final ReadingHistoryEntry? history = snapshot.data;
                        Chapter? target;
                        if (chapters.isNotEmpty)
                        {
                            target = chapters.first;
                            if (history != null)
                            {
                                for (final Chapter chapter in chapters)
                                {
                                    if (chapter.id == history.chapterId)
                                    {
                                        target = chapter;
                                        break;
                                    }
                                }
                            }
                        }
                        return TextButton.icon(
                            onPressed: target == null
                                    ? null
                                    : () => _openChapter(target!, chapters),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(history == null ? '阅读' : '续读'),
                        );
                    },
        );
    }

    Widget _buildHistoryEntry(List<Chapter> chapters)
    {
        return FutureBuilder<ReadingHistoryEntry?>(
            future: _historyFuture,
            builder:
                    (BuildContext context, AsyncSnapshot<ReadingHistoryEntry?> snapshot)
                    {
                        final ReadingHistoryEntry? history = snapshot.data;
                        if (history == null)
                        {
                            return const SizedBox(height: 8);
                        }
                        final Chapter? chapter = _chapterForHistory(chapters, history);
                        return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            leading: const Icon(Icons.history, color: Colors.grey),
                            title: Text(
                                '上次看到：${history.chapterTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                                '阅读进度 ${(history.progress * 100).round()}%',
                                style: const TextStyle(fontSize: 12),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: chapter == null
                                    ? null
                                    : () => _openChapter(chapter, chapters),
                        );
                    },
        );
    }

    Widget _buildDirectoryHeader(List<Chapter> chapters)
    {
        final List<WorkDirectory> directories = _directoriesFor(_work);
        final List<_DirectoryOption> options = _directoryOptions(directories);
        final _DirectoryOption selected = options.firstWhere(
            (_DirectoryOption option) =>
                    option.directory.id == _selectedDirectory.id &&
                    option.edition == _selectedNovelEdition,
            orElse: () => options.first,
        );
        final String directoryLabel = _work.kind == LibraryKind.comic &&
                options.length < 2
                ? '章节目录'
                : selected.label;
        final String countLabel = '$directoryLabel ·${chapters.length}'
                '${_work.kind == LibraryKind.comic ? '话' : '章'}';
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
                children: <Widget>[
                    Expanded(
                        child: options.length < 2
                                ? Text(
                                        countLabel,
                                        style: Theme.of(context).textTheme.titleSmall,
                                    )
                                : Align(
                                        alignment: Alignment.centerLeft,
                                        child: PopupMenuButton<String>(
                                            tooltip: '筛选来源',
                                            initialValue: selected.key,
                                            onSelected: (String key)
                                            {
                                                final _DirectoryOption option = options.firstWhere(
                                                    (_DirectoryOption value) => value.key == key,
                                                );
                                                setState(()
                                                {
                                                    _selectedDirectoryId = option.directory.id;
                                                    _selectedNovelEdition = option.edition;
                                                    _showAllChapters = false;
                                                });
                                            },
                                            itemBuilder: (BuildContext context) => options
                                                    .map((_DirectoryOption option)
                                                    {
                                                        return PopupMenuItem<String>(
                                                            value: option.key,
                                                            child: Text(option.menuLabel),
                                                        );
                                                    })
                                                    .toList(growable: false),
                                            child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: <Widget>[
                                                    Flexible(
                                                        child: Text(
                                                            countLabel,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: Theme.of(context).textTheme.titleSmall,
                                                        ),
                                                    ),
                                                    const Icon(Icons.arrow_drop_down),
                                                ],
                                            ),
                                        ),
                                    ),
                    ),
                    IconButton(
                        tooltip: _directoryView == _ChapterDirectoryView.grid
                                ? '切换为列表视图'
                                : '切换为网格视图',
                        onPressed: _toggleDirectoryView,
                        icon: Icon(
                            _directoryView == _ChapterDirectoryView.grid
                                    ? Icons.view_list
                                    : Icons.grid_view,
                            size: 20,
                        ),
                    ),
                    IconButton(
                        tooltip: _chaptersAscending ? '切换为倒序' : '切换为正序',
                        onPressed: _toggleChapterOrder,
                        icon: Icon(
                            _chaptersAscending ? Icons.arrow_upward : Icons.arrow_downward,
                            size: 20,
                        ),
                    ),
                ],
            ),
        );
    }

    void _restoreDirectoryPreferences()
    {
        final AppSettingsRepository settings = ref.read(
            appSettingsRepositoryProvider,
        );
        final String scope = _work.kind.name;
        _chaptersAscending = settings.workDirectoryAscending(scope);
        _directoryView = settings.workDirectoryUsesGrid(
                scope,
                defaultValue: _work.kind == LibraryKind.comic,
            )
            ? _ChapterDirectoryView.grid
            : _ChapterDirectoryView.list;
    }

    void _toggleDirectoryView()
    {
        final _ChapterDirectoryView next =
                _directoryView == _ChapterDirectoryView.grid
            ? _ChapterDirectoryView.list
            : _ChapterDirectoryView.grid;
        setState(()
        {
            _directoryView = next;
        });
        unawaited(
            ref.read(appSettingsRepositoryProvider).saveWorkDirectoryUsesGrid(
                _work.kind.name,
                next == _ChapterDirectoryView.grid,
            ),
        );
    }

    void _toggleChapterOrder()
    {
        final bool next = !_chaptersAscending;
        setState(()
        {
            _chaptersAscending = next;
        });
        unawaited(
            ref.read(appSettingsRepositoryProvider).saveWorkDirectoryAscending(
                _work.kind.name,
                next,
            ),
        );
    }

    List<_DirectoryOption> _directoryOptions(List<WorkDirectory> directories)
    {
        final List<_DirectoryOption> result = <_DirectoryOption>[];
        for (int index = 0; index < directories.length; index++)
        {
            final WorkDirectory directory = directories[index];
            final String owner = directory.owner.isEmpty
                    ? '来源 ${index + 1}'
                    : directory.owner;
            if (_work.kind != LibraryKind.novel)
            {
                result.add(
                    _DirectoryOption(
                        key: directory.id,
                        directory: directory,
                        label: owner,
                        menuLabel:
                                '$owner · ${directory.chapters.length}$unitLabel',
                    ),
                );
                continue;
            }
            final List<NovelEdition> editions = _novelEditionsFor(directory);
            for (final NovelEdition edition
                    in editions.isEmpty
                            ? const <NovelEdition>[NovelEdition.serial]
                            : editions)
            {
                final int count = directory.chapters
                        .where(
                            (Chapter chapter) => _novelEditionForChapter(chapter) == edition,
                        )
                        .length;
                final String label = directories.length > 1
                        ? '$owner · ${edition.label}'
                        : edition.label;
                result.add(
                    _DirectoryOption(
                        key: '${directory.id}|${edition.name}',
                        directory: directory,
                        edition: edition,
                        label: label,
                        menuLabel: '$label · $count$unitLabel',
                    ),
                );
            }
        }
        return result;
    }

    Widget _buildChapterDirectory(List<Chapter> chapters)
    {
        final List<Chapter> ordered = _chaptersAscending
                ? chapters
                : chapters.reversed.toList(growable: false);
        final int visibleCount = _showAllChapters || ordered.length <= 15
                ? ordered.length
                : 15;
        return FutureBuilder<ReadingHistoryEntry?>(
            future: _historyFuture,
            builder:
                    (BuildContext context, AsyncSnapshot<ReadingHistoryEntry?> snapshot)
                    {
                        final String? historyChapterId = snapshot.data?.chapterId;
                        final List<Chapter> visible = ordered
                                .take(visibleCount)
                                .toList(growable: false);
                        return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                                children: <Widget>[
                                    if (_work.kind == LibraryKind.novel &&
                                            _selectedNovelEdition == NovelEdition.book)
                                        _buildBookVolumeDirectory(
                                            chapters,
                                            visible,
                                            historyChapterId,
                                        )
                                    else if (_directoryView == _ChapterDirectoryView.grid)
                                        _buildChapterGrid(chapters, visible, historyChapterId)
                                    else
                                        _buildChapterList(chapters, visible, historyChapterId),
                                    if (visibleCount < ordered.length)
                                        TextButton.icon(
                                            onPressed: () => setState(()
                                    {
                                                _showAllChapters = true;
                                            }),
                                            icon: const Icon(Icons.expand_more),
                                            label: Text('展开全部 ${ordered.length} $unitLabel'),
                                        ),
                                ],
                            ),
                        );
                    },
        );
    }

    Widget _buildBookVolumeDirectory(
        List<Chapter> chapters,
        List<Chapter> visible,
        String? historyChapterId,
    )
    {
        final Map<String, List<Chapter>> volumes = <String, List<Chapter>>{};
        for (final Chapter chapter in visible)
        {
            final String title = chapter.volumeTitle.isEmpty
                    ? '单行本'
                    : chapter.volumeTitle;
            volumes.putIfAbsent(title, () => <Chapter>[]).add(chapter);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: volumes.entries
                    .expand((MapEntry<String, List<Chapter>> entry)
        {
                        return <Widget>[
                            Padding(
                                padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                                child: Text(
                                    entry.key,
                                    style: Theme.of(context).textTheme.titleSmall,
                                ),
                            ),
                            if (_directoryView == _ChapterDirectoryView.grid)
                                _buildChapterGrid(chapters, entry.value, historyChapterId)
                            else
                                _buildChapterList(chapters, entry.value, historyChapterId),
                        ];
                    })
                    .toList(growable: false),
        );
    }

    Widget _buildChapterGrid(
        List<Chapter> chapters,
        List<Chapter> visible,
        String? historyChapterId,
    )
    {
        return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints)
            {
                final int count = (constraints.maxWidth ~/ 150).clamp(3, 6);
                return GridView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: count,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        mainAxisExtent: 42,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (BuildContext context, int index)
                    {
                        final Chapter chapter = visible[index];
                        final bool selected = chapter.id == historyChapterId;
                        return OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () => _openChapter(
                                chapter,
                                chapters,
                                restoreProgress: false,
                            ),
                            child: Text(
                                _chapterDisplayTitle(chapter, includeSequence: true),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                            ),
                        );
                    },
                );
            },
        );
    }

    Widget _buildChapterList(
        List<Chapter> chapters,
        List<Chapter> visible,
        String? historyChapterId,
    )
    {
        return Column(
            children: visible
                    .map((Chapter chapter)
                    {
                        final String title = _chapterDisplayTitle(
                            chapter,
                            includeSequence: true,
                        );
                        final bool selected = chapter.id == historyChapterId;
                        return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            title: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: selected
                                            ? Theme.of(context).colorScheme.primary
                                            : null,
                                ),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 20),
                            onTap: () => _openChapter(
                                chapter,
                                chapters,
                                restoreProgress: false,
                            ),
                        );
                    })
                    .toList(growable: false),
        );
    }

    String get unitLabel => _work.kind == LibraryKind.comic ? '话' : '章';

    String? _chapterSequenceLabel(Chapter chapter)
    {
        final ({String number, String subtitle})? numbered = _numberedChapterTitle(
            chapter.title.trim(),
        );
        return numbered == null ? null : '第${numbered.number}$unitLabel';
    }

    String _chapterDisplayTitle(
        Chapter chapter,
        {
        required bool includeSequence,
    })
    {
        final String title = chapter.title.trim();
        if (title.isEmpty)
        {
            return '正文';
        }
        final ({String number, String subtitle})? numbered = _numberedChapterTitle(
            title,
        );
        if (numbered == null)
        {
            return title;
        }
        final String sequence = _chapterSequenceLabel(chapter)!;
        if (numbered.subtitle.isEmpty)
        {
            return sequence;
        }
        return includeSequence
                ? '$sequence ${numbered.subtitle}'
                : numbered.subtitle;
    }

    ({String number, String subtitle})? _numberedChapterTitle(String value)
    {
        final Match? explicit = RegExp(
            r'^第\s*(\d+(?:\.\d+)?(?:\s*(?:-|~|～|—|–|至)\s*'
            r'\d+(?:\.\d+)?)?)\s*(?:话|話|章|回|节|節)'
            r'(?:\s*[-—:：]?\s*(.*))?$',
        ).firstMatch(value);
        final Match? bare = explicit == null
                ? RegExp(
                        r'^0*(\d+(?:\.\d+)?(?:\s*(?:-|~|～|—|–|至)\s*'
                        r'\d+(?:\.\d+)?)?)'
                        r'(?=$|[\s（(前后後上中下\-—:：&])'
                        r'(.*)$',
                    ).firstMatch(value)
                : null;
        final Match? match = explicit ?? bare;
        if (match == null)
        {
            return null;
        }
        final String rawNumber = match.group(1)!;
        final Match? range = RegExp(
            r'^(\d+(?:\.\d+)?)\s*(?:-|~|～|—|–|至)\s*(\d+(?:\.\d+)?)$',
        ).firstMatch(rawNumber);
        final String number = range == null
                ? _normalizeChapterNumber(rawNumber)
                : '${_normalizeChapterNumber(range.group(1)!)}～'
                            '${_normalizeChapterNumber(range.group(2)!)}';
        String subtitle = (match.group(2) ?? '')
                .replaceFirst(RegExp(r'^[\s\-—:：&]+'), '')
                .trim();
        if (RegExp(
            r'^[（(]\s*\d+\s*(?:p|page|页|頁)\s*[）)]$',
            caseSensitive: false,
        ).hasMatch(subtitle))
        {
            subtitle = '';
        }
        return (number: number, subtitle: subtitle);
    }

    String _normalizeChapterNumber(String value)
    {
        return value.contains('.')
                ? value.replaceFirst(RegExp(r'\.0+$'), '')
                : (int.tryParse(value)?.toString() ?? value);
    }

    Chapter? _chapterForHistory(
        List<Chapter> chapters,
        ReadingHistoryEntry history,
    )
    {
        for (final Chapter chapter in chapters)
        {
            if (chapter.id == history.chapterId)
            {
                return chapter;
            }
        }
        return null;
    }

    Future<void> _openChapter(
        Chapter chapter,
        List<Chapter> chapters,
        {
        bool restoreProgress = true,
    }) async
    {
        await Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => ChapterReaderPage(
                    work: _selectedWork,
                    chapter: chapter,
                    chapters: chapters,
                    restoreProgress: restoreProgress,
                ),
            ),
        );
        if (mounted)
        {
            setState(()
        {
                _historyFuture = _loadHistory();
            });
        }
    }

    Future<void> _chooseDownloads(List<Chapter> chapters) async
    {
        final List<DownloadTaskEntry> existingTasks = await ref
                .read(downloadRepositoryProvider)
                .listForWork(_selectedWork.id);
        if (!mounted)
        {
            return;
        }
        final Map<String, DownloadStatus> existingStatuses =
                <String, DownloadStatus>{
                    for (final DownloadTaskEntry task in existingTasks)
                        task.chapter.id: task.status,
                };
        final List<Chapter> availableChapters = chapters
                .where(
                    (Chapter chapter) =>
                            !existingStatuses.containsKey(chapter.id),
                )
                .toList(growable: false);
        final Set<String> selectedIds = <String>{};
        final List<Chapter>? selected = await showDialog<List<Chapter>>(
            context: context,
            builder: (BuildContext context) => StatefulBuilder(
                builder: (BuildContext context, StateSetter setDialogState)
        {
                    final bool allSelected = availableChapters.isNotEmpty &&
                            selectedIds.length == availableChapters.length;
                    return AlertDialog(
                        title: const Text('选择下载章节'),
                        content: SizedBox(
                            width: 420,
                            height: 420,
                            child: Column(
                                children: <Widget>[
                                    CheckboxListTile(
                                        value: allSelected,
                                        title: const Text('全选'),
                                        controlAffinity: ListTileControlAffinity.leading,
                                        onChanged: availableChapters.isEmpty
                                                ? null
                                                : (bool? value) => setDialogState(()
        {
                                            selectedIds.clear();
                                            if (value == true)
                                            {
                                                selectedIds.addAll(
                                                    availableChapters.map(
                                                        (Chapter value) => value.id,
                                                    ),
                                                );
                                            }
                                        }),
                                    ),
                                    const Divider(height: 1),
                                    Expanded(
                                        child: ListView.builder(
                                            itemCount: chapters.length,
                                            itemBuilder: (BuildContext context, int index)
                                            {
                                                final Chapter chapter = chapters[index];
                                                final DownloadStatus? status =
                                                        existingStatuses[chapter.id];
                                                return CheckboxListTile(
                                                    value: status != null ||
                                                            selectedIds.contains(chapter.id),
                                                    title: Text(chapter.title),
                                                    subtitle: status == null
                                                            ? null
                                                            : Text(status.label),
                                                    controlAffinity: ListTileControlAffinity.leading,
                                                    onChanged: status == null
                                                            ? (bool? value) => setDialogState(()
                                            {
                                                        if (value == true)
                                                        {
                                                            selectedIds.add(chapter.id);
                                                        } else
                                                        {
                                                            selectedIds.remove(chapter.id);
                                                        }
                                                    })
                                                            : null,
                                                );
                                            },
                                        ),
                                    ),
                                ],
                            ),
                        ),
                        actions: <Widget>[
                            TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('取消'),
                            ),
                            FilledButton(
                                onPressed: selectedIds.isEmpty
                                        ? null
                                        : () => Navigator.of(context).pop(
                                                chapters
                                                        .where(
                                                            (Chapter value) => selectedIds.contains(value.id),
                                                        )
                                                        .toList(growable: false),
                                            ),
                                child: Text('下载 ${selectedIds.length} 章'),
                            ),
                        ],
                    );
                },
            ),
        );
        if (selected == null || selected.isEmpty || !mounted)
        {
            return;
        }
        await ref.read(downloadManagerProvider).enqueue(_selectedWork, selected);
        if (!mounted)
        {
            return;
        }
        ScaffoldMessenger.of(
            context,
        ).showSnackBar(AppSnackBar(content: Text('已加入 ${selected.length} 个下载任务')));
    }

    Future<void> _refreshIndex() async
    {
        if (_refreshing || _resolving || widget.rawSourceMode)
        {
            return;
        }
        _indexCancellation?.cancel();
        final WorkIndexCancellation cancellation = WorkIndexCancellation();
        _indexCancellation = cancellation;
        setState(()
        {
            _refreshing = true;
            _refreshMessage = '正在更新作品索引';
            _refreshProgress = null;
        });
        final CoverLoadCoordinator coverCoordinator = ref.read(
            coverLoadCoordinatorProvider,
        );
        coverCoordinator.beginCriticalOperation();
        try
        {
            final WorkIndexResult result = await ref
                    .read(workIndexCoordinatorProvider)
                    .refresh(
                        _work,
                        cancellation: cancellation,
                        onProgress: (String message)
        {
                            if (mounted)
                            {
                                setState(()
                            {
                                    _refreshMessage = message;
                                    _refreshProgress = _progressValue(message);
                                });
                            }
                        },
                    );
            cancellation.throwIfCancelled();
            if (!mounted)
            {
                return;
            }
            final bool changedId = _work.id != result.work.id;
            setState(()
            {
                _work = result.work;
                _coverFinalized = true;
                _selectedDirectoryId = _restoredDirectoryId(result.work);
                _selectedNovelEdition = _restoredNovelEdition(
                    result.work,
                    _selectedDirectoryId!,
                );
                _refreshing = false;
                _showAllChapters = false;
                if (changedId)
                {
                    _favoriteFuture = _loadFavoriteStatus();
                    _historyFuture = _loadHistory();
                }
            });
            ScaffoldMessenger.of(context).showSnackBar(
                AppSnackBar(
                    content: Text(
                        result.warning ??
                                '作品索引已更新，当前来源共 '
                                        '${_chaptersForDirectory(_selectedDirectory).length} 章',
                    ),
                ),
            );
        } on WorkIndexCancelledException
        {
            return;
        } on Object catch (error)
        {
            if (!mounted)
            {
                return;
            }
            setState(()
            {
                _refreshing = false;
            });
            ScaffoldMessenger.of(
                context,
            ).showSnackBar(AppSnackBar(content: Text('更新失败，已保留上次索引：$error')));
        }
        finally
        {
            coverCoordinator.endCriticalOperation();
        }
    }

    double? _progressValue(String message)
    {
        final RegExpMatch? match = RegExp(r'（(\d+)/(\d+)）').firstMatch(message);
        final int? completed = int.tryParse(match?.group(1) ?? '');
        final int? total = int.tryParse(match?.group(2) ?? '');
        if (completed == null || total == null || total <= 0)
        {
            return null;
        }
        return (completed / total).clamp(0.0, 1.0);
    }

    Future<void> _reparseCover() async
    {
        if (_coverRefreshing || !_coverFinalized)
        {
            return;
        }
        final Work work = _selectedWork;
        final CoverRequest request = CoverRequest(
            work: work,
            finalized: true,
            entryTid: widget.initialSourceTid,
        );
        final CoverRepository repository = ref.read(coverRepositoryProvider);
        final Uri? previous = repository.peek(request);
        setState(()
        {
            _coverRefreshing = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const AppSnackBar(content: Text('正在后台重新解析封面，当前封面会继续保留')),
        );
        try
        {
            final Uri? updated = await repository.resolve(
                work,
                finalize: true,
                entryTid: widget.initialSourceTid,
                force: true,
            );
            if (!mounted)
            {
                return;
            }
            ref.invalidate(workCoverProvider(request));
            final String message;
            if (updated == null)
            {
                message = '没有找到可用图片，继续使用文字封面';
            } else if (updated == previous)
            {
                message = '没有找到更合适的图片，已保留当前封面';
            } else
            {
                message = '封面已更新';
            }
            final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(AppSnackBar(content: Text(message)));
        }
        finally
        {
            if (mounted)
            {
                setState(()
                {
                    _coverRefreshing = false;
                });
            }
        }
    }

    Widget _buildFavoriteButton()
    {
        return FutureBuilder<List<CloudFavoriteRecord>>(
            future: _favoriteFuture,
            builder:
                    (
                        BuildContext context,
                        AsyncSnapshot<List<CloudFavoriteRecord>> snapshot,
                    )
            {
                        if (snapshot.connectionState != ConnectionState.done)
                        {
                            return TextButton.icon(
                                onPressed: null,
                                icon: const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                label: const Text('收藏'),
                            );
                        }
                        if (snapshot.hasError)
                        {
                            return TextButton.icon(
                                onPressed: _reloadFavoriteStatus,
                                icon: const Icon(Icons.sync_problem),
                                label: const Text('重试'),
                            );
                        }
                        final List<CloudFavoriteRecord> records =
                                snapshot.data ?? const <CloudFavoriteRecord>[];
                        return TextButton.icon(
                            onPressed: _favoriteBusy ? null : () => _toggleFavorite(records),
                            icon: Icon(
                                records.isEmpty ? Icons.favorite_border : Icons.favorite,
                            ),
                            label: const Text('收藏'),
                        );
                    },
        );
    }

    Future<void> _toggleFavorite(List<CloudFavoriteRecord> records) async
    {
        if (records.isNotEmpty)
        {
            final bool confirmed =
                    await showDialog<bool>(
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                            title: const Text('取消云端收藏'),
                            content: Text(
                                records.length == 1
                                        ? '确定取消收藏“${_work.title}”吗？'
                                        : '将取消与“${_work.title}”匹配的 '
                                                '${records.length} 条论坛收藏，是否继续？',
                            ),
                            actions: <Widget>[
                                TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('取消'),
                                ),
                                FilledButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('确定'),
                                ),
                            ],
                        ),
                    ) ??
                    false;
            if (!confirmed || !mounted)
            {
                return;
            }
        }

        setState(()
        {
            _favoriteBusy = true;
        });
        try
        {
            final ForumFavoriteRepository repository = ref.read(
                forumFavoriteRepositoryProvider,
            );
            final List<CloudFavoriteRecord> updated;
            if (records.isEmpty)
            {
                updated = await repository.addWork(_work);
            } else
            {
                await repository.removeWork(_work, records);
                updated = const <CloudFavoriteRecord>[];
            }
            if (!mounted)
            {
                return;
            }
            setState(()
            {
                _favoriteBusy = false;
                _favoriteFuture = Future<List<CloudFavoriteRecord>>.value(updated);
            });
            ScaffoldMessenger.of(context).showSnackBar(
                AppSnackBar(content: Text(records.isEmpty ? '已加入云端收藏' : '已取消云端收藏')),
            );
        } on Object catch (error)
        {
            if (!mounted)
            {
                return;
            }
            setState(()
            {
                _favoriteBusy = false;
                _favoriteFuture = _loadFavoriteStatus();
            });
            ScaffoldMessenger.of(
                context,
            ).showSnackBar(AppSnackBar(content: Text('云端收藏操作失败：$error')));
        }
    }

    void _reloadFavoriteStatus()
    {
        setState(()
        {
            _favoriteFuture = _loadFavoriteStatus();
        });
    }

    Future<void> _openOriginal() async
    {
        final List<Chapter> chapters = _chaptersForDirectory(_selectedDirectory);
        Chapter? latestMain;
        for (final Chapter chapter in chapters.reversed)
        {
            if (chapter.order != null && chapter.order! < 800000)
            {
                latestMain = chapter;
                break;
            }
        }
        final Uri target = latestMain?.sourceUri ?? _selectedWork.primaryUri;
        final bool confirmed = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                    title: const Text('打开原帖'),
                    content: const Text('即将在系统浏览器中打开原帖，是否继续？'),
                    actions: <Widget>[
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                        ),
                        FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('继续'),
                        ),
                    ],
                ),
            ) ??
            false;
        if (!confirmed)
        {
            return;
        }
        await launchUrl(
            target,
            mode: LaunchMode.externalApplication,
        );
    }

    Future<void> _showFullTitles() async
    {
        await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (BuildContext context)
            {
                final List<SourceThread> sources = _work.sourceThreads;
                return SafeArea(
                    child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                        ),
                        child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                            children: <Widget>[
                                Text(
                                    '完整标题',
                                    style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 10),
                                SelectableText(
                                    _work.title,
                                    style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(height: 1.35),
                                ),
                                const SizedBox(height: 20),
                                ...sources.indexed.map(
                                    ((int, SourceThread) entry)
                                    {
                                        final int index = entry.$1;
                                        final SourceThread source = entry.$2;
                                        final String owner = source.author.isEmpty
                                                ? ''
                                                : ' · 楼主：${source.author}';
                                        return Padding(
                                            padding: const EdgeInsets.only(bottom: 16),
                                            child: Column(
                                                crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                children: <Widget>[
                                                    Text(
                                                        '来源 ${index + 1}$owner',
                                                        style: const TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12,
                                                        ),
                                                    ),
                                                    const SizedBox(height: 5),
                                                    SelectableText(
                                                        source.title,
                                                        style: const TextStyle(height: 1.4),
                                                    ),
                                                ],
                                            ),
                                        );
                                    },
                                ),
                            ],
                        ),
                    ),
                );
            },
        );
    }

    Future<void> _openSourceSearch() async
    {
        await Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => SearchPage(
                    kind: _work.kind,
                    initialKeyword: _work.title,
                    initialResultMode: SearchResultMode.raw,
                    autoSubmit: true,
                ),
            ),
        );
    }
}

class _DirectoryOption
{
    const _DirectoryOption({
        required this.key,
        required this.directory,
        required this.label,
        required this.menuLabel,
        this.edition,
    });

    final String key;
    final WorkDirectory directory;
    final NovelEdition? edition;
    final String label;
    final String menuLabel;
}

enum _ChapterDirectoryView { grid, list }

class _WorkHeader extends StatelessWidget
{
    const _WorkHeader({
        required this.work,
        required this.coverFinalized,
        this.coverEntryTid,
        this.onReparseCover,
        this.summary = '',
        this.summaryExpanded = false,
        this.onSearch,
        this.onShowFullTitles,
        this.onToggleSummary,
    });

    final Work work;
    final bool coverFinalized;
    final int? coverEntryTid;
    final VoidCallback? onReparseCover;
    final String summary;
    final bool summaryExpanded;
    final VoidCallback? onSearch;
    final VoidCallback? onShowFullTitles;
    final VoidCallback? onToggleSummary;

    @override
    Widget build(BuildContext context)
    {
        final SourceThread source = work.sourceThreads.reduce((
            SourceThread current,
            SourceThread next,
        )
        {
            final DateTime? currentTime = current.postedAt;
            final DateTime? nextTime = next.postedAt;
            if (currentTime == null)
            {
                return nextTime == null ? current : next;
            }
            return nextTime != null && nextTime.isAfter(currentTime) ? next : current;
        });
        return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                            _buildCover(context),
                            const SizedBox(width: 12),
                            Expanded(
                                child: SizedBox(
                                    height: 160,
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                            Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: <Widget>[
                                                    Expanded(
                                                        child: Tooltip(
                                                            message: '查看完整标题',
                                                            child: InkWell(
                                                                onTap: onShowFullTitles,
                                                                borderRadius:
                                                                        BorderRadius.circular(4),
                                                                child: Padding(
                                                                    padding:
                                                                            const EdgeInsets.symmetric(
                                                                        vertical: 2,
                                                                    ),
                                                                    child: Text(
                                                                        work.title,
                                                                        maxLines: 4,
                                                                        overflow:
                                                                                TextOverflow.ellipsis,
                                                                        style: Theme.of(context)
                                                                                .textTheme
                                                                                .titleMedium
                                                                                ?.copyWith(
                                                                                    fontWeight:
                                                                                            FontWeight.w600,
                                                                                    height: 1.25,
                                                                                ),
                                                                    ),
                                                                ),
                                                            ),
                                                        ),
                                                    ),
                                                    if (onSearch != null)
                                                        IconButton(
                                                            tooltip: '搜索原始帖子',
                                                            onPressed: onSearch,
                                                            icon: const Icon(Icons.search),
                                                            visualDensity: VisualDensity.compact,
                                                        ),
                                                ],
                                            ),
                                            const Spacer(),
                                            if (work.typeName.isNotEmpty)
                                                _WorkInfoLine(
                                                    icon: Icons.sell_outlined,
                                                    text: work.typeName,
                                                ),
                                            _WorkInfoLine(
                                                icon: Icons.visibility_outlined,
                                                text: '${source.views} 浏览 · ${source.replies} 回复',
                                            ),
                                            if (source.timeLabel.isNotEmpty)
                                                _WorkInfoLine(
                                                    icon: Icons.schedule,
                                                    text: source.timeLabel,
                                                ),
                                        ],
                                    ),
                                ),
                            ),
                        ],
                    ),
                    if (summary.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        InkWell(
                            onTap: onToggleSummary,
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: <Widget>[
                                    Expanded(
                                        child: Text(
                                            summary,
                                            maxLines: summaryExpanded ? null : 2,
                                            overflow: summaryExpanded
                                                    ? TextOverflow.visible
                                                    : TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 14,
                                                height: 1.45,
                                            ),
                                        ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                        summaryExpanded ? Icons.expand_less : Icons.expand_more,
                                        size: 20,
                                        color: Colors.grey,
                                    ),
                                ],
                            ),
                        ),
                    ],
                    const SizedBox(height: 12),
                    Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
                ],
            ),
        );
    }

    Widget _buildCover(BuildContext context)
    {
        final Widget cover = WorkCover(
            work: work,
            width: 120,
            height: 160,
            borderRadius: 4,
            finalized: coverFinalized,
            entryTid: coverEntryTid,
        );
        final VoidCallback? onReparse = onReparseCover;
        if (onReparse == null)
        {
            return cover;
        }
        return Tooltip(
            message: '长按重新解析封面',
            child: GestureDetector(
                onLongPress: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (BuildContext context)
                    {
                        return SafeArea(
                            child: ListTile(
                                leading: const Icon(Icons.refresh),
                                title: const Text('重新解析封面'),
                                subtitle: const Text('找到新封面前会保留当前图片'),
                                onTap: ()
                                {
                                    Navigator.of(context).pop();
                                    onReparse();
                                },
                            ),
                        );
                    },
                ),
                child: cover,
            ),
        );
    }
}

class _WorkInfoLine extends StatelessWidget
{
    const _WorkInfoLine({required this.icon, required this.text});

    final IconData icon;
    final String text;

    @override
    Widget build(BuildContext context)
    {
        return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
                children: <Widget>[
                    Icon(icon, size: 16, color: Colors.grey),
                    const SizedBox(width: 7),
                    Expanded(
                        child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                    ),
                ],
            ),
        );
    }
}
