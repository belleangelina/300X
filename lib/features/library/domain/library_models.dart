
enum LibraryKind { comic, novel }

enum NovelEdition
{
    serial('连载版'),
    book('单行本');

    const NovelEdition(this.label);

    final String label;
}

enum ForumBoard
{
    comic(fid: 30, label: '漫画区', kind: LibraryKind.comic),
    literature(fid: 49, label: '文学区', kind: LibraryKind.novel),
    lightNovel(fid: 55, label: '轻小说', kind: LibraryKind.novel);

    const ForumBoard({
        required this.fid,
        required this.label,
        required this.kind,
    });

    final int fid;
    final String label;
    final LibraryKind kind;

    static ForumBoard? fromFid(int fid)
    {
        for (final ForumBoard board in values)
        {
            if (board.fid == fid)
            {
                return board;
            }
        }
        return null;
    }
}

enum CatalogSection
{
    recommended('推荐'),
    updated('更新'),
    categories('分类'),
    ranking('排行');

    const CatalogSection(this.label);

    final String label;
}

enum NovelSourceFilter
{
    all('全部'),
    literature('文学区'),
    lightNovel('轻小说');

    const NovelSourceFilter(this.label);

    final String label;

    List<ForumBoard> get boards
    {
        return switch (this)
        {
            NovelSourceFilter.all => const <ForumBoard>[
                ForumBoard.literature,
                ForumBoard.lightNovel,
            ],
            NovelSourceFilter.literature => const <ForumBoard>[ForumBoard.literature],
            NovelSourceFilter.lightNovel => const <ForumBoard>[ForumBoard.lightNovel],
        };
    }
}

class ForumCategory
{
    const ForumCategory({
        required this.board,
        required this.typeId,
        required this.name,
        required this.uri,
    });

    final ForumBoard board;
    final int typeId;
    final String name;
    final Uri uri;
}

class SourceThread
{
    const SourceThread({
        required this.tid,
        required this.board,
        required this.title,
        required this.uri,
        this.typeId,
        this.typeName = '',
        this.summary = '',
        this.author = '',
        this.avatarUri,
        this.timeLabel = '',
        this.postedAt,
        this.views = 0,
        this.replies = 0,
        this.pinned = false,
        this.administrative = false,
    });

    final int tid;
    final ForumBoard board;
    final int? typeId;
    final String typeName;
    final String title;
    final String summary;
    final String author;
    final Uri? avatarUri;
    final String timeLabel;
    final DateTime? postedAt;
    final int views;
    final int replies;
    final bool pinned;
    final bool administrative;
    final Uri uri;
}

class ForumCatalogPage
{
    const ForumCatalogPage({
        required this.board,
        required this.threads,
        required this.pinnedThreads,
        required this.categories,
        required this.currentPage,
        required this.totalPages,
        this.nextPageUri,
    });

    final ForumBoard board;
    final List<SourceThread> threads;
    final List<SourceThread> pinnedThreads;
    final List<ForumCategory> categories;
    final int currentPage;
    final int totalPages;
    final Uri? nextPageUri;

    bool get hasMore => nextPageUri != null;
}

class StructuredTitle
{
    const StructuredTitle({
        required this.original,
        required this.displayTitle,
        required this.titleKey,
        required this.creatorKey,
        required this.workKey,
        required this.chapterLabel,
        required this.chapterOrder,
        required this.versionMarker,
        required this.hasChapterMarker,
        required this.novelDisplayTitle,
        required this.novelTitleKey,
        required this.novelEdition,
        required this.volumeTitle,
        required this.volumeOrder,
    });

    final String original;
    final String displayTitle;
    final String titleKey;
    final String creatorKey;
    final String workKey;
    final String chapterLabel;
    final double? chapterOrder;
    final String versionMarker;
    final bool hasChapterMarker;
    final String novelDisplayTitle;
    final String novelTitleKey;
    final NovelEdition? novelEdition;
    final String volumeTitle;
    final double? volumeOrder;
}

class Chapter
{
    const Chapter({
        required this.id,
        required this.title,
        required this.sourceUri,
        required this.sourceTid,
        this.sourcePid,
        this.sourceEndPid,
        this.sourceStartBlock,
        this.sourceEndBlock,
        this.order,
        this.novelEdition,
        this.volumeTitle = '',
        this.volumeOrder,
    });

    final String id;
    final String title;
    final Uri sourceUri;
    final int sourceTid;
    final int? sourcePid;
    final int? sourceEndPid;
    final int? sourceStartBlock;
    final int? sourceEndBlock;
    final double? order;
    final NovelEdition? novelEdition;
    final String volumeTitle;
    final double? volumeOrder;
}

class WorkDirectory
{
    const WorkDirectory({
        required this.id,
        required this.owner,
        required this.sourceTids,
        required this.chapters,
    });

    final String id;
    final String owner;
    final List<int> sourceTids;
    final List<Chapter> chapters;
}

class Work
{
    const Work({
        required this.id,
        required this.kind,
        required this.title,
        required this.sourceThreads,
        required this.chapters,
        this.directories = const <WorkDirectory>[],
        this.summary = '',
        this.author = '',
        this.typeName = '',
    });

    final String id;
    final LibraryKind kind;
    final String title;
    final String summary;
    final String author;
    final String typeName;
    final List<SourceThread> sourceThreads;
    final List<Chapter> chapters;
    final List<WorkDirectory> directories;

    SourceThread get primarySourceThread
    {
        if (directories.isNotEmpty)
        {
            final Set<int> sourceTids = directories.first.sourceTids.toSet();
            for (final SourceThread thread in sourceThreads)
            {
                if (sourceTids.contains(thread.tid))
                {
                    return thread;
                }
            }
        }
        return sourceThreads.first;
    }

    int get primarySourceTid => primarySourceThread.tid;

    ForumBoard get primaryBoard => primarySourceThread.board;

    Uri get primaryUri => primarySourceThread.uri;

    DateTime? get latestSourceTime
    {
        DateTime? result;
        for (final SourceThread thread in sourceThreads)
        {
            final DateTime? value = thread.postedAt;
            if (value != null && (result == null || value.isAfter(result)))
            {
                result = value;
            }
        }
        return result;
    }
}

class WorkCatalogPage
{
    const WorkCatalogPage({
        required this.works,
        required this.sourceThreads,
        required this.categories,
        required this.pages,
    });

    final List<Work> works;
    final List<SourceThread> sourceThreads;
    final List<ForumCategory> categories;
    final Map<ForumBoard, ForumCatalogPage> pages;

    bool get hasMore => pages.values.any((ForumCatalogPage page) => page.hasMore);
}
