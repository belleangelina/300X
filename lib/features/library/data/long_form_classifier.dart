import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/domain/library_models.dart';

class LongFormClassifier
{
    const LongFormClassifier();

    static const Set<int> _comicTypeIds = <int>{69, 398, 503, 504};
    static const Set<int> _shortComicTypeIds = <int>{68};
    static const Set<String> _comicTypeNames = <String>{
        '长篇连载',
        '長篇連載',
        '韩国漫画',
        '韓國漫畫',
        '泰国漫画',
        '泰國漫畫',
        '欧美其他',
        '歐美其他',
    };
    static const Set<String> _shortComicTypeNames = <String>{
        '短篇漫画',
        '短篇漫畫',
    };

    bool isExplicitLongComic(Work work)
    {
        if (work.kind != LibraryKind.comic)
        {
            return false;
        }
        if (_matchesName(work.typeName, _comicTypeNames))
        {
            return true;
        }
        return work.sourceThreads.any(
            (SourceThread thread) =>
                _comicTypeIds.contains(thread.typeId) ||
                _matchesName(thread.typeName, _comicTypeNames),
        );
    }

    bool isExplicitShortComic(Work work)
    {
        if (work.kind != LibraryKind.comic)
        {
            return false;
        }
        if (_matchesName(work.typeName, _shortComicTypeNames))
        {
            return true;
        }
        return work.sourceThreads.any(
            isExplicitShortComicThread,
        );
    }

    bool isExplicitShortComicThread(SourceThread thread)
    {
        return thread.board.kind == LibraryKind.comic &&
            (_shortComicTypeIds.contains(thread.typeId) ||
                _matchesName(thread.typeName, _shortComicTypeNames));
    }

    bool _matchesName(String value, Set<String> names)
    {
        final String normalized = normalizeForumText(value)
            .replaceAll(RegExp(r'^[#＃]+'), '')
            .replaceAll(RegExp(r'\s+'), '');
        return names.contains(normalized);
    }
}
