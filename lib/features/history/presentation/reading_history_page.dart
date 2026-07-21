import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:x300/features/history/data/reading_history_repository.dart';
import 'package:x300/features/history/domain/reading_history_models.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/presentation/work_detail_page.dart';
import 'package:x300/features/library/presentation/work_widgets.dart';
import 'package:x300/shared/presentation/app_empty_view.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';

enum _HistoryFilter
{
    all('全部'),
    comic('漫画'),
    novel('小说');

    const _HistoryFilter(this.label);

    final String label;

    LibraryKind? get kind
    {
        return switch (this)
        {
            _HistoryFilter.all => null,
            _HistoryFilter.comic => LibraryKind.comic,
            _HistoryFilter.novel => LibraryKind.novel,
        };
    }
}

class ReadingHistoryPage extends ConsumerStatefulWidget
{
    const ReadingHistoryPage({this.kind, super.key});

    final LibraryKind? kind;

    @override
    ConsumerState<ReadingHistoryPage> createState()
    {
        return _ReadingHistoryPageState();
    }
}

class _ReadingHistoryPageState extends ConsumerState<ReadingHistoryPage>
{
    _HistoryFilter _filter = _HistoryFilter.all;
    late final ReadingHistoryRepository _repository;
    late Stream<List<ReadingHistoryEntry>> _stream;

    @override
    void initState()
    {
        super.initState();
        _repository = ref.read(readingHistoryRepositoryProvider);
        _stream = _repository.watch(kind: widget.kind);
    }

    @override
    void didUpdateWidget(covariant ReadingHistoryPage oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        if (oldWidget.kind != widget.kind)
        {
            _stream = _repository.watch(kind: widget.kind ?? _filter.kind);
        }
    }

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            appBar: AppBar(
                title: Text(switch (widget.kind)
                {
                    LibraryKind.comic => '漫画记录',
                    LibraryKind.novel => '小说记录',
                    null => '本机记录',
                }),
            ),
            body: Column(
                children: <Widget>[
                    if (widget.kind == null)
                        SizedBox(
                            height: 48,
                            child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                ),
                                children: _HistoryFilter.values.map(
                                    (_HistoryFilter value) => Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: ChoiceChip(
                                            label: Text(value.label),
                                            selected: value == _filter,
                                            onSelected: (bool selected)
                                            {
                                                if (selected)
                                                {
                                                    setState(()
                                                    {
                                                        _filter = value;
                                                        _stream = _repository.watch(
                                                            kind: value.kind,
                                                        );
                                                    });
                                                }
                                            },
                                        ),
                                    ),
                                ).toList(growable: false),
                            ),
                        ),
                    Expanded(
                        child: StreamBuilder<List<ReadingHistoryEntry>>(
                            stream: _stream,
                            builder: (
                                BuildContext context,
                                AsyncSnapshot<List<ReadingHistoryEntry>> snapshot,
                            )
                            {
                                if (snapshot.hasError)
                                {
                                    return AppErrorView(
                                        message: '读取本机记录失败：${snapshot.error}',
                                        onRetry: () => setState(() {}),
                                    );
                                }
                                if (!snapshot.hasData)
                                {
                                    return const AppLoadingView();
                                }
                                final List<ReadingHistoryEntry> entries =
                                    snapshot.data!;
                                if (entries.isEmpty)
                                {
                                    return const AppEmptyView(
                                        message: '还没有阅读记录',
                                    );
                                }
                                return ListView.separated(
                                    itemCount: entries.length,
                                    separatorBuilder: (
                                        BuildContext context,
                                        int index,
                                    ) => const Divider(height: 1),
                                    itemBuilder: (
                                        BuildContext context,
                                        int index,
                                    ) => _buildEntry(entries[index]),
                                );
                            },
                        ),
                    ),
                ],
            ),
        );
    }

    Widget _buildEntry(ReadingHistoryEntry entry)
    {
        final int percent = (entry.progress * 100).round();
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
                WorkListTile(
                    work: entry.work,
                    onTap: () => _openWork(entry.work),
                    trailing: IconButton(
                        tooltip: '删除记录',
                        onPressed: () => _delete(entry),
                        icon: const Icon(Icons.delete_outline),
                    ),
                ),
                Padding(
                    padding: const EdgeInsets.fromLTRB(104, 0, 48, 10),
                    child: Text(
                        '上次看到：${entry.chapterTitle} · $percent% · '
                        '${DateFormat('MM-dd HH:mm').format(entry.updatedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                        ),
                    ),
                ),
            ],
        );
    }

    Future<void> _delete(ReadingHistoryEntry entry) async
    {
        final bool confirmed = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                    title: const Text('删除本机记录'),
                    content: Text('确定删除“${entry.work.title}”的阅读记录吗？'),
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
        await ref.read(readingHistoryRepositoryProvider).delete(
            entry.work.id,
        );
    }

    void _openWork(Work work)
    {
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => WorkDetailPage(
                    work: work,
                    resolveOnOpen: true,
                ),
            ),
        );
    }
}
