import 'package:x300/features/library/data/work_anchor_selector.dart';
import 'package:x300/features/library/domain/library_models.dart';

class FavoriteWorkPolicy
{
    const FavoriteWorkPolicy([
        this._anchorSelector = const WorkAnchorSelector(),
    ]);

    final WorkAnchorSelector _anchorSelector;

    Set<int> sourceTids(Work work)
    {
        return <int>{
            ...work.sourceThreads.map((SourceThread source) => source.tid),
            ...work.chapters.map((Chapter chapter) => chapter.sourceTid),
            ...work.directories.expand(
                (WorkDirectory directory) => directory.sourceTids,
            ),
            ...work.directories.expand(
                (WorkDirectory directory) => directory.chapters.map(
                    (Chapter chapter) => chapter.sourceTid,
                ),
            ),
        };
    }

    SourceThread anchor(Work work)
    {
        return _anchorSelector.selectDefaultDirectory(work);
    }
}
