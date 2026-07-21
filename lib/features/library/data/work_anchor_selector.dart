import 'package:collection/collection.dart';
import 'package:x300/features/library/data/title_normalizer.dart';
import 'package:x300/features/library/domain/library_models.dart';

class WorkAnchorSelector
{
    const WorkAnchorSelector();

    static const TitleNormalizer _titleNormalizer = TitleNormalizer();

    SourceThread select(Work work)
    {
        return selectFrom(work.sourceThreads);
    }

    SourceThread selectDefaultDirectory(Work work)
    {
        final WorkDirectory? directory = work.directories.firstOrNull;
        if (directory == null)
        {
            return select(work);
        }
        final Set<int> sourceTids = <int>{
            ...directory.sourceTids,
            ...directory.chapters.map((Chapter chapter) => chapter.sourceTid),
        };
        final Map<int, SourceThread> candidates = <int, SourceThread>{
            for (final SourceThread source in work.sourceThreads)
                if (sourceTids.contains(source.tid)) source.tid: source,
        };
        for (final Chapter chapter in directory.chapters)
        {
            candidates.putIfAbsent(
                chapter.sourceTid,
                () => SourceThread(
                    tid: chapter.sourceTid,
                    board: work.primaryBoard,
                    title: chapter.title,
                    uri: chapter.sourceUri,
                ),
            );
        }
        return candidates.isEmpty ? select(work) : selectFrom(candidates.values);
    }

    SourceThread selectFrom(Iterable<SourceThread> sources)
    {
        final Iterator<SourceThread> iterator = sources.iterator;
        if (!iterator.moveNext())
        {
            throw StateError('作品没有可用来源帖');
        }
        SourceThread result = iterator.current;
        while (iterator.moveNext())
        {
            if (compare(iterator.current, result) > 0)
            {
                result = iterator.current;
            }
        }
        return result;
    }

    int compare(SourceThread left, SourceThread right)
    {
        final double? leftOrder = _titleNormalizer.analyze(left.title).chapterOrder;
        final double? rightOrder = _titleNormalizer
                .analyze(right.title)
                .chapterOrder;
        final bool leftMain = leftOrder != null && leftOrder < 800000;
        final bool rightMain = rightOrder != null && rightOrder < 800000;
        if (leftMain != rightMain)
        {
            return leftMain ? 1 : -1;
        }
        if (leftMain && rightMain)
        {
            final int orderResult = leftOrder.compareTo(rightOrder);
            if (orderResult != 0)
            {
                return orderResult;
            }
        }
        final DateTime? leftTime = left.postedAt;
        final DateTime? rightTime = right.postedAt;
        if (leftTime != null || rightTime != null)
        {
            if (leftTime == null)
            {
                return -1;
            }
            if (rightTime == null)
            {
                return 1;
            }
            final int timeResult = leftTime.compareTo(rightTime);
            if (timeResult != 0)
            {
                return timeResult;
            }
        }
        return left.tid.compareTo(right.tid);
    }
}
