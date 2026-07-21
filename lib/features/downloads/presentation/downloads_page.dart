import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:x300/features/downloads/application/download_manager.dart';
import 'package:x300/features/downloads/data/download_repository.dart';
import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/features/reader/presentation/chapter_reader_page.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

class DownloadsPage extends ConsumerStatefulWidget
{
    const DownloadsPage({required this.kind, super.key});

    final LibraryKind kind;

    @override
    ConsumerState<DownloadsPage> createState()
    {
        return _DownloadsPageState();
    }
}

class _DownloadsPageState extends ConsumerState<DownloadsPage>
{
    late Stream<List<DownloadTaskEntry>> _tasks;

    @override
    void initState()
    {
        super.initState();
        _tasks = ref.read(downloadRepositoryProvider).watch(kind: widget.kind);
    }

    @override
    Widget build(BuildContext context)
    {
        final String title = widget.kind == LibraryKind.comic ? '漫画下载' : '小说下载';
        return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: StreamBuilder<List<DownloadTaskEntry>>(
                stream: _tasks,
                builder:
                        (
                            BuildContext context,
                            AsyncSnapshot<List<DownloadTaskEntry>> snapshot,
                        )
                        {
                            if (snapshot.hasError)
                            {
                                return AppErrorView(
                                    message: '读取下载任务失败：${snapshot.error}',
                                    onRetry: () => setState(()
                                    {
                                        _tasks = ref
                                                .read(downloadRepositoryProvider)
                                                .watch(kind: widget.kind);
                                    }),
                                );
                            }
                            if (!snapshot.hasData)
                            {
                                return const AppLoadingView();
                            }
                            final List<DownloadTaskEntry> tasks = snapshot.data!;
                            if (tasks.isEmpty)
                            {
                                return const AppEmptyView(message: '还没有离线下载\n请在作品详情页选择章节');
                            }
                            final List<_DownloadWorkGroup> groups =
                                    _groupTasks(tasks);
                            return ListView.separated(
                                itemCount: groups.length,
                                separatorBuilder: (BuildContext context, int index) =>
                                        const Divider(height: 1),
                                itemBuilder: (BuildContext context, int index) =>
                                        WorkListTile(
                                            work: groups[index].work,
                                            onTap: () => _openWork(
                                                groups[index],
                                            ),
                                        ),
                            );
                        },
            ),
        );
    }

    List<_DownloadWorkGroup> _groupTasks(List<DownloadTaskEntry> tasks)
    {
        final Map<String, List<DownloadTaskEntry>> byWork =
                <String, List<DownloadTaskEntry>>{};
        for (final DownloadTaskEntry task in tasks)
        {
            byWork.putIfAbsent(task.work.id, () => <DownloadTaskEntry>[]).add(
                task,
            );
        }
        return byWork.values
                .map(_DownloadWorkGroup.new)
                .toList(growable: false);
    }

    void _openWork(_DownloadWorkGroup group)
    {
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => _DownloadWorkPage(
                    workId: group.work.id,
                    kind: widget.kind,
                    title: group.work.title,
                ),
            ),
        );
    }
}

class _DownloadWorkGroup
{
    _DownloadWorkGroup(this.tasks);

    final List<DownloadTaskEntry> tasks;

    Work get work
    {
        final Work source = tasks.first.work;
        final Map<String, Chapter> chapters = <String, Chapter>{
            for (final DownloadTaskEntry task in tasks)
                task.chapter.id: task.chapter,
        };
        return Work(
            id: source.id,
            kind: source.kind,
            title: source.title,
            sourceThreads: source.sourceThreads,
            chapters: chapters.values.toList(growable: false),
            directories: source.directories,
            summary: source.summary,
            author: source.author,
            typeName: source.typeName,
        );
    }
}

class _DownloadWorkPage extends ConsumerStatefulWidget
{
    const _DownloadWorkPage({
        required this.workId,
        required this.kind,
        required this.title,
    });

    final String workId;
    final LibraryKind kind;
    final String title;

    @override
    ConsumerState<_DownloadWorkPage> createState()
    {
        return _DownloadWorkPageState();
    }
}

class _DownloadWorkPageState extends ConsumerState<_DownloadWorkPage>
{
    late Stream<List<DownloadTaskEntry>> _tasks;

    @override
    void initState()
    {
        super.initState();
        _tasks = ref.read(downloadRepositoryProvider).watch(kind: widget.kind);
    }

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: StreamBuilder<List<DownloadTaskEntry>>(
                stream: _tasks,
                builder: (
                    BuildContext context,
                    AsyncSnapshot<List<DownloadTaskEntry>> snapshot,
                )
                {
                    if (snapshot.hasError)
                    {
                        return AppErrorView(
                            message: '读取下载任务失败：${snapshot.error}',
                            onRetry: () => setState(()
                            {
                                _tasks = ref
                                        .read(downloadRepositoryProvider)
                                        .watch(kind: widget.kind);
                            }),
                        );
                    }
                    if (!snapshot.hasData)
                    {
                        return const AppLoadingView();
                    }
                    final List<DownloadTaskEntry> tasks = snapshot.data!
                            .where(
                                (DownloadTaskEntry task) =>
                                        task.work.id == widget.workId,
                            )
                            .toList(growable: false);
                    if (tasks.isEmpty)
                    {
                        return const AppEmptyView(message: '该作品暂无离线章节');
                    }
                    return ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (
                            BuildContext context,
                            int index,
                        ) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) =>
                                _buildTask(tasks[index], tasks),
                    );
                },
            ),
        );
    }

    Widget _buildTask(
        DownloadTaskEntry task,
        List<DownloadTaskEntry> tasks,
    )
    {
        final int percent = (task.progress * 100).round();
        final String detail = task.errorMessage.isNotEmpty
                ? task.errorMessage
                : '${task.status.label} · $percent% · '
                        '${DateFormat('MM-dd HH:mm').format(task.updatedAt)}';
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
                ListTile(
                    title: Text(task.chapter.title),
                    subtitle: Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: task.status == DownloadStatus.failed
                                    ? Theme.of(context).colorScheme.error
                                    : Colors.grey,
                        ),
                    ),
                    onTap: task.status == DownloadStatus.completed
                            ? () => _open(task, tasks)
                            : null,
                    trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                            _buildStatusAction(task, tasks),
                            IconButton(
                                tooltip: '删除下载',
                                onPressed: () => _delete(task),
                                icon: const Icon(Icons.delete_outline),
                            ),
                        ],
                    ),
                ),
                if (task.status == DownloadStatus.downloading ||
                        task.status == DownloadStatus.queued)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: LinearProgressIndicator(
                            value: task.totalItems == 0 ? null : task.progress,
                        ),
                    ),
            ],
        );
    }

    Widget _buildStatusAction(
        DownloadTaskEntry task,
        List<DownloadTaskEntry> tasks,
    )
    {
        return switch (task.status)
        {
            DownloadStatus.queued || DownloadStatus.downloading => IconButton(
                tooltip: '暂停',
                onPressed: () => ref.read(downloadManagerProvider).pause(task.id),
                icon: const Icon(Icons.pause),
            ),
            DownloadStatus.paused || DownloadStatus.failed => IconButton(
                tooltip: '继续下载',
                onPressed: () => ref.read(downloadManagerProvider).resume(task.id),
                icon: const Icon(Icons.play_arrow),
            ),
            DownloadStatus.completed => IconButton(
                tooltip: '离线阅读',
                onPressed: () => _open(task, tasks),
                icon: const Icon(Icons.menu_book_outlined),
            ),
        };
    }

    Future<void> _delete(DownloadTaskEntry task) async
    {
        final bool confirmed =
                await showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                        title: const Text('删除离线章节'),
                        content: Text('确定删除“${task.chapter.title}”吗？'),
                        actions: <Widget>[
                            TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('取消'),
                            ),
                            FilledButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('删除'),
                            ),
                        ],
                    ),
                ) ??
                false;
        if (!confirmed || !mounted)
        {
            return;
        }
        await ref.read(downloadManagerProvider).delete(task);
    }

    void _open(
        DownloadTaskEntry task,
        List<DownloadTaskEntry> tasks,
    )
    {
        final List<Chapter> chapters = _completedChapters(task, tasks);
        final Work work = Work(
            id: task.work.id,
            kind: task.work.kind,
            title: task.work.title,
            sourceThreads: task.work.sourceThreads,
            chapters: chapters,
            summary: task.work.summary,
            author: task.work.author,
            typeName: task.work.typeName,
        );
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => ChapterReaderPage(
                    work: work,
                    chapter: task.chapter,
                    chapters: chapters,
                ),
            ),
        );
    }

    List<Chapter> _completedChapters(
        DownloadTaskEntry selected,
        List<DownloadTaskEntry> tasks,
    )
    {
        final Map<String, Chapter> chapters = <String, Chapter>{};
        for (final DownloadTaskEntry task in tasks)
        {
            if (task.work.id == selected.work.id &&
                task.status == DownloadStatus.completed)
            {
                chapters[task.chapter.id] = task.chapter;
            }
        }
        chapters[selected.chapter.id] = selected.chapter;
        final List<Chapter> result = chapters.values.toList();
        result.sort((Chapter left, Chapter right)
        {
            final double? leftOrder = left.order;
            final double? rightOrder = right.order;
            if (leftOrder != null || rightOrder != null)
            {
                return (leftOrder ?? double.infinity).compareTo(
                    rightOrder ?? double.infinity,
                );
            }
            return left.title.compareTo(right.title);
        });
        return result;
    }
}
