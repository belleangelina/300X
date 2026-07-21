import 'package:x300/features/library/domain/library_models.dart';

class ReadingHistoryEntry
{
    const ReadingHistoryEntry({
        required this.work,
        required this.chapterId,
        required this.chapterTitle,
        required this.chapterIndex,
        required this.position,
        required this.progress,
        required this.updatedAt,
    });

    final Work work;
    final String chapterId;
    final String chapterTitle;
    final int chapterIndex;
    final int position;
    final double progress;
    final DateTime updatedAt;
}
