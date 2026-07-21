import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

enum DownloadStatus
{
    queued('等待中'),
    downloading('下载中'),
    paused('已暂停'),
    failed('失败'),
    completed('已完成');

    const DownloadStatus(this.label);

    final String label;
}

class DownloadTaskEntry
{
    const DownloadTaskEntry({
        required this.id,
        required this.work,
        required this.chapter,
        required this.status,
        required this.completedItems,
        required this.totalItems,
        required this.directoryPath,
        required this.payloadJson,
        required this.errorMessage,
        required this.updatedAt,
    });

    final String id;
    final Work work;
    final Chapter chapter;
    final DownloadStatus status;
    final int completedItems;
    final int totalItems;
    final String directoryPath;
    final String payloadJson;
    final String errorMessage;
    final DateTime updatedAt;

    double get progress
    {
        if (totalItems <= 0)
        {
            return status == DownloadStatus.completed ? 1 : 0;
        }
        return (completedItems / totalItems).clamp(0.0, 1.0);
    }
}

class OfflineChapterContent
{
    const OfflineChapterContent({
        required this.blocks,
        required this.referer,
    });

    final List<PostContentBlock> blocks;
    final Uri referer;
}
