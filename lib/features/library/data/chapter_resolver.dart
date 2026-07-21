import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/data/title_normalizer.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

enum ChapterResolutionEvidence
{
    none,
    inlineDirectory,
    forumTagDirectory,
    novelBlockSequence,
    novelPostSequence,
}

class ChapterResolution
{
    const ChapterResolution({
        required this.chapters,
        required this.evidence,
        this.relatedThreads = const <ThreadLink>[],
        this.batchThreads = const <ThreadLink>[],
        this.directoryLinks = const <ThreadLink>[],
    });

    final List<Chapter> chapters;
    final ChapterResolutionEvidence evidence;
    final List<ThreadLink> relatedThreads;
    final List<ThreadLink> batchThreads;
    final List<ThreadLink> directoryLinks;
}

class ChapterResolver
{
    const ChapterResolver([this._titleNormalizer = const TitleNormalizer()]);

    final TitleNormalizer _titleNormalizer;

    List<Chapter> resolve(Work work, ForumThreadPage page)
    {
        return resolveWithEvidence(work, page).chapters;
    }

    bool hasStrongComicDirectoryEvidence(
        Work work,
        ChapterResolution resolution,
    )
    {
        if (work.kind != LibraryKind.comic ||
                resolution.evidence != ChapterResolutionEvidence.inlineDirectory &&
                        resolution.evidence !=
                                ChapterResolutionEvidence.forumTagDirectory)
        {
            return false;
        }
        final Set<String> workTitleKeys = <String>{
            _titleNormalizer.analyze(work.title).titleKey,
            ...work.sourceThreads.map(
                (SourceThread thread) =>
                        _titleNormalizer.analyze(thread.title).titleKey,
            ),
        }..remove('');
        final Set<double> chapterOrders = <double>{};
        for (final ThreadLink link in resolution.directoryLinks)
        {
            final String label = _cleanDirectoryTitle(link.label);
            final StructuredTitle direct = _titleNormalizer.analyze(label);
            final bool directChapterOnly =
                    direct.chapterLabel.isNotEmpty && direct.displayTitle == label;
            final StructuredTitle structured = direct.chapterLabel.isEmpty
                    ? _titleNormalizer.analyze('${work.title} $label')
                    : direct;
            final bool syntheticChapterOnly =
                    direct.chapterLabel.isEmpty &&
                    _isPlausibleChapterLabel(label) &&
                    workTitleKeys.contains(structured.titleKey);
            if (!structured.hasChapterMarker ||
                    !directChapterOnly &&
                            !syntheticChapterOnly &&
                            !workTitleKeys.contains(direct.titleKey))
            {
                continue;
            }
            final double? order = structured.chapterOrder;
            if (order != null && order > 0 && order < 800000)
            {
                chapterOrders.add(order);
            }
        }
        return chapterOrders.length >= 2;
    }

    ChapterResolution resolveWithEvidence(
        Work work,
        ForumThreadPage page,
        {
        List<ThreadLink> tagDirectoryLinks = const <ThreadLink>[],
    })
    {
        final List<SourcePost> originalPosterPosts = page.posts
                .where((SourcePost post) => post.isOriginalPoster)
                .toList(growable: false);
        final List<ThreadLink> inlineDirectoryLinks = _inlineDirectoryLinks(
            originalPosterPosts,
            work.kind,
        );
        final List<ThreadLink> batchThreads = _batchDirectoryThreads(<ThreadLink>[
            ...tagDirectoryLinks,
            ...inlineDirectoryLinks,
            ...originalPosterPosts.expand((SourcePost post) => post.links),
        ]);
        final List<ThreadLink> relatedThreads = work.kind == LibraryKind.novel
                ? _novelRelatedThreads(
                    <ThreadLink>[
                        ...tagDirectoryLinks,
                        ...inlineDirectoryLinks,
                        ...originalPosterPosts.expand(
                            (SourcePost post) => post.links.where(
                                (ThreadLink link) =>
                                        link.kind == ThreadLinkKind.previous ||
                                        link.kind == ThreadLinkKind.next,
                            ),
                        ),
                    ],
                    page,
                )
                : const <ThreadLink>[];
        final List<ThreadLink> localTagDirectoryLinks =
                work.kind == LibraryKind.novel
                ? _localNovelDirectoryLinks(tagDirectoryLinks, page.tid)
                : tagDirectoryLinks;
        final List<ThreadLink> localInlineDirectoryLinks =
                work.kind == LibraryKind.novel
                ? _localNovelDirectoryLinks(inlineDirectoryLinks, page.tid)
                : inlineDirectoryLinks;
        final List<Chapter> parsedTagDirectory = _chaptersFromDirectory(
            localTagDirectoryLinks,
            originalPosterPosts,
            work,
            compactTitles: true,
        );
        final List<ThreadLink> combinedDirectoryLinks = <ThreadLink>[
            ...localTagDirectoryLinks,
            ...localInlineDirectoryLinks,
        ];
        final List<Chapter> combinedTagDirectory = _chaptersFromDirectory(
            combinedDirectoryLinks,
            originalPosterPosts,
            work,
            compactTitles: true,
        );
        if (parsedTagDirectory.length >= 2)
        {
            return ChapterResolution(
                chapters: _replaceCoarseChapters(work.chapters, combinedTagDirectory),
                evidence: ChapterResolutionEvidence.forumTagDirectory,
                relatedThreads: relatedThreads,
                batchThreads: batchThreads,
                directoryLinks: combinedDirectoryLinks,
            );
        }

        final List<Chapter> inlineDirectory = _chaptersFromDirectory(
            localInlineDirectoryLinks,
            originalPosterPosts,
            work,
            compactTitles: false,
        );
        if (inlineDirectory.length >= 2)
        {
            return ChapterResolution(
                chapters: _replaceCoarseChapters(work.chapters, inlineDirectory),
                evidence: ChapterResolutionEvidence.inlineDirectory,
                relatedThreads: relatedThreads,
                batchThreads: batchThreads,
                directoryLinks: localInlineDirectoryLinks,
            );
        }

        if (originalPosterPosts.isEmpty)
        {
            return ChapterResolution(
                chapters: work.chapters,
                evidence: ChapterResolutionEvidence.none,
                relatedThreads: relatedThreads,
                batchThreads: batchThreads,
            );
        }

        final List<ThreadLink> explicitLinks = originalPosterPosts
                .expand((SourcePost post) => post.links)
                .where(
                    (ThreadLink link) =>
                            link.kind != ThreadLinkKind.related &&
                            link.kind != ThreadLinkKind.directory,
                )
                .toList(growable: false);

        if (work.kind == LibraryKind.novel)
        {
            final List<Chapter> blockChapters = _chaptersFromSingleNovelPost(
                work,
                page,
                originalPosterPosts,
            );
            if (blockChapters.length >= 2)
            {
                return ChapterResolution(
                    chapters: _replaceCoarseChapters(work.chapters, blockChapters),
                    evidence: ChapterResolutionEvidence.novelBlockSequence,
                    relatedThreads: relatedThreads,
                    batchThreads: batchThreads,
                );
            }
            final List<Chapter> inferred = _chaptersFromNovelPosts(
                work,
                page,
                originalPosterPosts,
            );
            if (inferred.length >= 2)
            {
                return ChapterResolution(
                    chapters: _replaceCoarseChapters(work.chapters, inferred),
                    evidence: ChapterResolutionEvidence.novelPostSequence,
                    relatedThreads: relatedThreads,
                    batchThreads: batchThreads,
                );
            }
        }

        final List<Chapter> candidates = <Chapter>[];
        for (final ThreadLink link in explicitLinks.where(
            (ThreadLink value) =>
                    work.kind != LibraryKind.novel &&
                    value.kind == ThreadLinkKind.previous,
        ))
        {
            _addLink(candidates, link);
        }
        candidates.addAll(work.chapters);
        for (final ThreadLink link in localInlineDirectoryLinks)
        {
            _addLink(candidates, link);
        }
        for (final ThreadLink link in explicitLinks.where(
            (ThreadLink value) =>
                    work.kind != LibraryKind.novel && value.kind == ThreadLinkKind.next,
        ))
        {
            _addLink(candidates, link);
        }
        return ChapterResolution(
            chapters: _deduplicate(candidates),
            evidence: ChapterResolutionEvidence.none,
            relatedThreads: relatedThreads,
            batchThreads: batchThreads,
        );
    }

    List<ThreadLink> _batchDirectoryThreads(List<ThreadLink> links)
    {
        final List<ThreadLink> result = <ThreadLink>[];
        final Set<int> tids = <int>{};
        for (final ThreadLink link in links)
        {
            final int? tid = link.tid;
            if (tid == null ||
                    link.pid != null ||
                    _titleNormalizer.detectNumericChapterRange(link.label) == null ||
                    !tids.add(tid))
            {
                continue;
            }
            result.add(link);
        }
        return result;
    }

    List<ThreadLink> _localNovelDirectoryLinks(List<ThreadLink> links, int tid)
    {
        return links
                .where((ThreadLink link) => link.tid == tid && link.pid != null)
                .toList(growable: false);
    }

    List<ThreadLink> _novelRelatedThreads(
        List<ThreadLink> links,
        ForumThreadPage page,
    )
    {
        final List<ThreadLink> result = _deduplicateLinks(
            links
                    .where((ThreadLink link) => link.tid != null && link.pid == null)
                    .map(_normalizeNovelRelatedThread)
                    .toList(growable: false),
        );
        final NovelBareVolumeCandidate? candidate =
                _titleNormalizer.detectNovelAdjacentVolumeCandidate(page.title);
        if (candidate == null || result.any((ThreadLink link) => link.tid == page.tid))
        {
            return result;
        }
        final Set<int> volumeNumbers = result
                .map((ThreadLink link)
                {
                    final StructuredTitle title = _titleNormalizer.analyze(
                        '作品 ${link.label}',
                    );
                    return title.novelEdition == NovelEdition.book
                            ? title.volumeOrder?.toInt()
                            : null;
                })
                .whereType<int>()
                .toSet();
        if (volumeNumbers.length < 2 || volumeNumbers.contains(candidate.volumeNumber))
        {
            return result;
        }
        final Set<int> completeSeries = <int>{
            ...volumeNumbers,
            candidate.volumeNumber,
        };
        final int maximum = completeSeries.reduce(
            (int current, int next) => current > next ? current : next,
        );
        if (maximum != completeSeries.length)
        {
            return result;
        }
        return <ThreadLink>[
            ...result,
            ThreadLink(
                label: '第${candidate.volumeNumber}卷',
                uri: page.uri,
                kind: ThreadLinkKind.related,
                tid: page.tid,
            ),
        ];
    }

    ThreadLink _normalizeNovelRelatedThread(ThreadLink link)
    {
        final String? volumeLabel = _novelVolumeRelationLabel(link.label);
        if (volumeLabel == null)
        {
            return link;
        }
        return ThreadLink(
            label: volumeLabel,
            uri: link.uri,
            kind: link.kind,
            tid: link.tid,
            pid: link.pid,
        );
    }

    List<ThreadLink> _inlineDirectoryLinks(
        List<SourcePost> posts,
        LibraryKind kind,
    )
    {
        final List<ThreadLink> strong = <ThreadLink>[];
        final List<ThreadLink> looseChapters = <ThreadLink>[];
        for (final SourcePost post in posts)
        {
            final List<ThreadLink> chapters = post.links
                    .where((ThreadLink link) => link.kind == ThreadLinkKind.chapter)
                    .toList(growable: false);
            final List<ThreadLink> related = post.links
                    .where(
                        (ThreadLink link) =>
                                link.kind == ThreadLinkKind.related &&
                                link.tid != null &&
                                _isShortDirectoryLabel(link.label),
                    )
                    .toList(growable: false);
            final bool marked = RegExp(r'(目录|目錄|索引|合集|合輯)').hasMatch(post.plainText);
            final List<ThreadLink> clusteredRelated = marked
                    ? related
                    : _relatedDirectoryCluster(related);
            final Set<String> selected = <String>{
                ...chapters.map(_linkIdentity),
                ...clusteredRelated.map(_linkIdentity),
            };
            final List<ThreadLink> ordered = post.links
                    .where((ThreadLink link) => selected.contains(_linkIdentity(link)))
                    .toList(growable: false);
            if ((marked && chapters.length + related.length >= 2) ||
                    chapters.length >= 2 ||
                    clusteredRelated.length >= 2)
            {
                strong.addAll(ordered);
            } else
            {
                looseChapters.addAll(chapters);
            }
        }
        if (strong.isEmpty && looseChapters.length >= 2)
        {
            strong.addAll(looseChapters);
        }
        return kind == LibraryKind.novel
                ? _deduplicateDirectoryLinks(strong)
                : _deduplicateLinks(strong);
    }

    List<ThreadLink> _deduplicateDirectoryLinks(List<ThreadLink> links)
    {
        final Map<String, ThreadLink> result = <String, ThreadLink>{};
        for (final ThreadLink link in links)
        {
            final String label = _normalizedDirectoryHeading(link.label);
            final String key = '${_linkIdentity(link)}:$label';
            result.putIfAbsent(key, () => link);
        }
        return result.values.toList(growable: false);
    }

    List<ThreadLink> _relatedDirectoryCluster(List<ThreadLink> links)
    {
        final List<int> plausibleIndexes = <int>[];
        for (int index = 0; index < links.length; index++)
        {
            if (_isPlausibleChapterLabel(links[index].label))
            {
                plausibleIndexes.add(index);
            }
        }
        if (plausibleIndexes.length < 2)
        {
            return const <ThreadLink>[];
        }
        final int start = plausibleIndexes.first;
        final int last = plausibleIndexes.last;
        final String prefix = _directoryTitlePrefix(
            links[plausibleIndexes.first].label,
        );
        int end = last + 1;
        while (end < links.length &&
                (_isTrailingBonusLabel(links[end].label) ||
                        _sharesDirectoryPrefix(links[end].label, prefix)))
        {
            end++;
        }
        return links.sublist(start, end);
    }

    String _directoryTitlePrefix(String value)
    {
        final String label = normalizeForumText(value);
        final StructuredTitle direct = _titleNormalizer.analyze(label);
        if (direct.hasChapterMarker && direct.displayTitle != label)
        {
            return direct.displayTitle;
        }
        final StructuredTitle synthetic = _titleNormalizer.analyze('作品 $label');
        return synthetic.hasChapterMarker && synthetic.displayTitle != '作品'
                ? synthetic.displayTitle.replaceFirst(RegExp(r'^作品\s*'), '')
                : '';
    }

    bool _sharesDirectoryPrefix(String value, String prefix)
    {
        if (prefix.length < 2)
        {
            return false;
        }
        final String label = normalizeForumText(value);
        if (!label.startsWith(prefix))
        {
            return false;
        }
        final String remainder = label.substring(prefix.length);
        return remainder.isEmpty || RegExp(r'^[\s_\-—:：]').hasMatch(remainder);
    }

    bool _isTrailingBonusLabel(String value)
    {
        return RegExp(
            r'(番外|特典|附录|附錄|后记|後記|终章|終章|最终|最終|祝词|祝詞)',
        ).hasMatch(normalizeForumText(value));
    }

    bool _isShortDirectoryLabel(String value)
    {
        final String label = normalizeForumText(value);
        return label.isNotEmpty &&
                label.length <= 30 &&
                !RegExp(
                    r'^(原帖链接|原帖連結|查看|跳转|跳轉|here|上一|下一|'
                    r'作者.*作品|其他作品|其它作品|漫画汇总|漫畫彙總|作品汇总|作品彙總|'
                    r'(?:原作|原著|原文|小说|小説|漫画|漫畫|小说原作|小説原作|'
                    r'漫画原作|漫畫原作|原作小说|原作小説|原作漫画|原作漫畫)'
                    r'(?:地址|链接|連結|原帖)?)$',
                    caseSensitive: false,
                ).hasMatch(label);
    }

    bool _isPlausibleChapterLabel(String value)
    {
        final String label = normalizeForumText(value);
        if (_novelVolumeRelationLabel(label) != null)
        {
            return true;
        }
        if (RegExp(
            r'^\d{1,4}(?:\.\d+)?(?:\s*(?:前|后|後|上|中|下)(?:篇|編)?)?(?:[（(]\d+[）)])?$',
        ).hasMatch(label))
        {
            return true;
        }
        return _titleNormalizer.analyze('作品 $label').hasChapterMarker;
    }

    List<ThreadLink> _deduplicateLinks(List<ThreadLink> links)
    {
        final Map<String, ThreadLink> result = <String, ThreadLink>{};
        for (final ThreadLink link in links)
        {
            final String key = _linkIdentity(link);
            result.putIfAbsent(key, () => link);
        }
        return result.values.toList(growable: false);
    }

    String _linkIdentity(ThreadLink link)
    {
        return '${link.tid ?? 0}:${link.pid ?? 0}';
    }

    List<Chapter> _chaptersFromDirectory(
        List<ThreadLink> links,
        List<SourcePost> posts,
        Work work,
        {
        required bool compactTitles,
    })
    {
        final Map<int, SourcePost> postsByPid = <int, SourcePost>{
            for (final SourcePost post in posts) post.pid: post,
        };
        final List<String> cleanedTitles = links
                .map((ThreadLink link) => _cleanDirectoryTitle(link.label))
                .toList(growable: false);
        final Map<String, int> cleanedTitleCounts = <String, int>{};
        for (final String title in cleanedTitles)
        {
            cleanedTitleCounts.update(
                _normalizedDirectoryHeading(title),
                (int value) => value + 1,
                ifAbsent: () => 1,
            );
        }
        final Map<int, _NovelDirectoryBlockSection> blockSections =
                work.kind == LibraryKind.novel
                ? _novelDirectoryBlockSections(links, postsByPid)
                : const <int, _NovelDirectoryBlockSection>{};
        final List<StructuredTitle> directTitles = cleanedTitles
                .map(_titleNormalizer.analyze)
                .toList(growable: false);
        final List<bool> syntheticTitles = List<bool>.generate(
            cleanedTitles.length,
            (int index)
            {
                return directTitles[index].chapterLabel.isEmpty &&
                        _isShortDirectoryLabel(cleanedTitles[index]);
            },
            growable: false,
        );
        final List<StructuredTitle> structuredTitles =
                List<StructuredTitle>.generate(cleanedTitles.length, (int index)
            {
                    return syntheticTitles[index]
                            ? _titleNormalizer.analyze('作品 ${cleanedTitles[index]}')
                            : directTitles[index];
                }, growable: false);
        final List<bool> chapterOnlyTitles = List<bool>.generate(
            cleanedTitles.length,
            (int index)
            {
                final StructuredTitle direct = directTitles[index];
                return syntheticTitles[index] ||
                        (direct.chapterLabel.isNotEmpty &&
                                direct.displayTitle == cleanedTitles[index]);
            },
            growable: false,
        );
        final String commonBase = _commonDirectoryBase(structuredTitles);
        final List<double?> explicitOrders = _directoryOrders(
            structuredTitles,
            commonBase,
            chapterOnlyTitles,
        );
        if (work.kind == LibraryKind.novel)
        {
            for (int index = 0; index < cleanedTitles.length; index++)
            {
                final double? sideStoryOrder = _novelSideStoryOrder(
                    cleanedTitles[index],
                );
                if (sideStoryOrder != null)
                {
                    explicitOrders[index] = sideStoryOrder;
                }
            }
        }
        final List<Chapter> result = <Chapter>[];
        for (int index = 0; index < links.length; index++)
        {
            final ThreadLink link = links[index];
            final int? tid = link.tid;
            if (tid == null)
            {
                continue;
            }
            final ThreadLink? next = index + 1 < links.length
                    ? links[index + 1]
                    : null;
            final SourcePost? targetPost = link.pid == null
                    ? null
                    : postsByPid[link.pid];
            final String cleanedTitle = cleanedTitles[index];
            final StructuredTitle structured = structuredTitles[index];
            final _NovelDirectoryBlockSection? blockSection = blockSections[index];
            final String? specificPostTitle = blockSection?.title ??
                    (work.kind == LibraryKind.novel &&
                            ((cleanedTitleCounts[
                                        _normalizedDirectoryHeading(cleanedTitle)
                                    ] ??
                                    0) >
                                1 ||
                                    _novelSideStoryOrder(cleanedTitle) != null)
                            ? _specificNovelDirectoryPostTitle(
                                targetPost,
                                cleanedTitle,
                            )
                            : null);
            final String title = specificPostTitle ??
                    (_isGenericLinkTitle(cleanedTitle)
                    ? _postTitle(targetPost, index, work.kind)
                    : _directoryChapterTitle(
                            cleanedTitle,
                            syntheticTitles[index]
                                    ? directTitles[index].displayTitle
                                    : structured.displayTitle,
                            structured,
                            commonBase,
                            compactTitles,
                        ));
            result.add(
                Chapter(
                    id: blockSection != null
                            ? 'forum-post:$tid:${link.pid}:block:${blockSection.start}'
                            : link.pid == null
                            ? 'forum-thread:$tid'
                            : 'forum-post:$tid:${link.pid}',
                    title: title,
                    sourceUri: link.uri,
                    sourceTid: tid,
                    sourcePid: link.pid,
                    sourceEndPid: blockSection == null && next?.tid == tid
                            ? next?.pid
                            : null,
                    sourceStartBlock: blockSection?.start,
                    sourceEndBlock: blockSection?.end,
                    order:
                            explicitOrders[index] ??
                            _directoryFallbackOrder(explicitOrders, index),
                ),
            );
        }
        return _deduplicate(result);
    }

    Map<int, _NovelDirectoryBlockSection> _novelDirectoryBlockSections(
        List<ThreadLink> links,
        Map<int, SourcePost> postsByPid,
    )
    {
        final Map<String, List<int>> groupedIndexes = <String, List<int>>{};
        for (int index = 0; index < links.length; index++)
        {
            final ThreadLink link = links[index];
            if (link.tid == null || link.pid == null)
            {
                continue;
            }
            groupedIndexes
                    .putIfAbsent('${link.tid}:${link.pid}', () => <int>[])
                    .add(index);
        }
        final Map<int, _NovelDirectoryBlockSection> result =
                <int, _NovelDirectoryBlockSection>{};
        for (final List<int> indexes in groupedIndexes.values)
        {
            if (indexes.length < 2)
            {
                continue;
            }
            final SourcePost? post = postsByPid[links[indexes.first].pid];
            if (post == null)
            {
                continue;
            }
            final List<_NovelDirectoryBlockSection> sections =
                    <_NovelDirectoryBlockSection>[];
            final Set<int> usedStarts = <int>{};
            bool complete = true;
            for (final int linkIndex in indexes)
            {
                _NovelDirectoryBlockSection? selected;
                for (int blockIndex = 0; blockIndex < post.blocks.length; blockIndex++)
                {
                    final PostContentBlock block = post.blocks[blockIndex];
                    if (block is! PostTextBlock)
                    {
                        continue;
                    }
                    final String heading = _firstDirectoryHeadingLine(block.text);
                    if (_directoryHeadingMatches(links[linkIndex].label, heading))
                    {
                        selected = _NovelDirectoryBlockSection(
                            start: blockIndex,
                            end: post.blocks.length,
                            title: _shortTitle(heading),
                        );
                    }
                }
                if (selected == null || !usedStarts.add(selected.start))
                {
                    complete = false;
                    break;
                }
                sections.add(selected);
            }
            if (!complete)
            {
                continue;
            }
            for (int index = 0; index < sections.length; index++)
            {
                final _NovelDirectoryBlockSection current = sections[index];
                final int end = index + 1 < sections.length
                        ? sections[index + 1].start
                        : post.blocks.length;
                if (end <= current.start ||
                        !_novelBlockRangeHasSubstance(
                            post.blocks,
                            current.start,
                            end,
                        ))
                {
                    complete = false;
                    break;
                }
                sections[index] = _NovelDirectoryBlockSection(
                    start: current.start,
                    end: end,
                    title: current.title,
                );
            }
            if (!complete)
            {
                continue;
            }
            for (int index = 0; index < indexes.length; index++)
            {
                result[indexes[index]] = sections[index];
            }
        }
        return result;
    }

    double? _novelSideStoryOrder(String value)
    {
        final String title = normalizeForumText(value).trim();
        final Match? bonus = RegExp(
            r'^bonus\s*track\s*0*(\d+)',
            caseSensitive: false,
        ).firstMatch(title);
        if (bonus != null)
        {
            return 900000 + (double.tryParse(bonus.group(1)!) ?? 0);
        }
        if (RegExp(r'^last\s*track(?:\s|$)', caseSensitive: false).hasMatch(title))
        {
            return 910000;
        }
        return null;
    }

    String? _specificNovelDirectoryPostTitle(
        SourcePost? post,
        String directoryTitle,
    )
    {
        if (post == null)
        {
            return null;
        }
        String? result;
        final String normalizedDirectory = _normalizedDirectoryHeading(
            directoryTitle,
        );
        for (final PostTextBlock block in post.blocks.whereType<PostTextBlock>())
        {
            final String heading = _firstDirectoryHeadingLine(block.text);
            if (_directoryHeadingMatches(directoryTitle, heading) &&
                    _normalizedDirectoryHeading(heading) != normalizedDirectory)
            {
                result = _shortTitle(heading);
            }
        }
        return result;
    }

    String _firstDirectoryHeadingLine(String value)
    {
        return value
                .split(RegExp(r'[\r\n]+'))
                .map(normalizeForumText)
                .map((String line) => line.trim())
                .firstWhere((String line) => line.isNotEmpty, orElse: () => '');
    }

    bool _directoryHeadingMatches(String directoryTitle, String heading)
    {
        if (heading.isEmpty || heading.length > 100)
        {
            return false;
        }
        final String directory = _normalizedDirectoryHeading(directoryTitle);
        final String candidate = _normalizedDirectoryHeading(heading);
        if (directory.isNotEmpty &&
                (candidate == directory ||
                        candidate.startsWith('$directory ') ||
                        candidate.startsWith('$directory-') ||
                        candidate.startsWith('$directory—') ||
                        candidate.startsWith('$directory:') ||
                        candidate.startsWith('$directory：')))
        {
            return true;
        }
        final StructuredTitle expected = _titleNormalizer.analyze(
            '作品 $directoryTitle',
        );
        final StructuredTitle actual = _titleNormalizer.analyze('作品 $heading');
        return expected.hasChapterMarker &&
                actual.hasChapterMarker &&
                expected.chapterOrder != null &&
                expected.chapterOrder == actual.chapterOrder;
    }

    String _normalizedDirectoryHeading(String value)
    {
        return normalizeForumText(value)
                .toLowerCase()
                .replaceAllMapped(
                    RegExp(r'\d+'),
                    (Match match) =>
                            (int.tryParse(match.group(0)!) ?? match.group(0)!).toString(),
                )
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
    }

    String _commonDirectoryBase(List<StructuredTitle> titles)
    {
        final Map<String, int> counts = <String, int>{};
        String result = '';
        int resultCount = 0;
        for (final StructuredTitle title in titles)
        {
            final double? order = title.chapterOrder;
            final String base = title.displayTitle.trim();
            if (order == null || order >= 800000 || base.length < 2)
            {
                continue;
            }
            final int count = counts.update(
                base,
                (int value) => value + 1,
                ifAbsent: () => 1,
            );
            if (count > resultCount)
            {
                result = base;
                resultCount = count;
            }
        }
        return result;
    }

    List<double?> _directoryOrders(
        List<StructuredTitle> titles,
        String commonBase,
        List<bool> chapterOnlyTitles,
    )
    {
        final List<double?> result = <double?>[];
        double? latestMainOrder;
        for (int index = 0; index < titles.length; index++)
        {
            final StructuredTitle title = titles[index];
            double? order = title.chapterOrder;
            final bool sameBase = _sameDirectoryBase(title.displayTitle, commonBase);
            if (order != null && order < 800000)
            {
                if (latestMainOrder != null &&
                        order < latestMainOrder &&
                        !sameBase &&
                        !chapterOnlyTitles[index])
                {
                    order = null;
                } else if ((sameBase || chapterOnlyTitles[index]) &&
                        (latestMainOrder == null || order > latestMainOrder))
                {
                    latestMainOrder = order;
                }
            }
            result.add(order);
        }
        return result;
    }

    String _directoryChapterTitle(
        String cleanedTitle,
        String displayValue,
        StructuredTitle structured,
        String commonBase,
        bool compactTitles,
    )
    {
        final String displayTitle = displayValue.trim();
        final String variant = _stripDirectoryBase(displayTitle, commonBase);
        final bool sharesBase =
                commonBase.isNotEmpty &&
                (_sameDirectoryBase(displayTitle, commonBase) ||
                        displayTitle.startsWith(commonBase));
        if (structured.chapterLabel.isNotEmpty)
        {
            return !sharesBase ||
                            variant.isEmpty ||
                            variant == structured.chapterLabel
                    ? structured.chapterLabel
                    : '$variant ${structured.chapterLabel}';
        }
        if (compactTitles)
        {
            return _compactDirectoryTitle(displayTitle, commonBase);
        }
        return cleanedTitle.isEmpty ? displayTitle : cleanedTitle;
    }

    String _compactDirectoryTitle(String value, String commonBase)
    {
        final String cleaned = normalizeForumText(value).replaceAll(
            RegExp(r'(?:\s*(?:\[[^\]]{1,60}\]|【[^】]{1,60}】)){2,}\s*'),
            ' ',
        );
        if (cleaned.isEmpty ||
                commonBase.isEmpty ||
                _sameDirectoryBase(cleaned, commonBase))
        {
            return cleaned;
        }
        final int baseIndex = cleaned.toLowerCase().indexOf(
            commonBase.toLowerCase(),
        );
        if (baseIndex < 0)
        {
            return cleaned;
        }
        final String prefix = cleaned
                .substring(0, baseIndex)
                .replaceFirst(RegExp(r'[\s_\-—:：]+$'), '')
                .trim();
        final String suffix = cleaned
                .substring(baseIndex + commonBase.length)
                .replaceFirst(RegExp(r'^[\s_\-—:：]+'), '')
                .trim();
        if (prefix.isEmpty)
        {
            return suffix.isEmpty ? cleaned : suffix;
        }
        return suffix.isEmpty ? prefix : '$prefix · $suffix';
    }

    String _stripDirectoryBase(String value, String commonBase)
    {
        if (value.isEmpty || commonBase.isEmpty)
        {
            return value;
        }
        if (_sameDirectoryBase(value, commonBase))
        {
            return '';
        }
        if (!value.startsWith(commonBase))
        {
            return value;
        }
        return value
                .substring(commonBase.length)
                .replaceFirst(RegExp(r'^[\s_\-—:：]+'), '')
                .trim();
    }

    bool _sameDirectoryBase(String left, String right)
    {
        final String normalizedLeft = normalizeForumText(left).toLowerCase();
        final String normalizedRight = normalizeForumText(right).toLowerCase();
        if (normalizedLeft == normalizedRight)
        {
            return true;
        }
        if (normalizedLeft.length != normalizedRight.length ||
                normalizedLeft.length < 3)
        {
            return false;
        }
        int differences = 0;
        for (int index = 0; index < normalizedLeft.length; index++)
        {
            if (normalizedLeft.codeUnitAt(index) !=
                    normalizedRight.codeUnitAt(index))
            {
                differences++;
                if (differences > 1)
                {
                    return false;
                }
            }
        }
        return true;
    }

    double _directoryFallbackOrder(List<double?> orders, int index)
    {
        int? previousIndex;
        int? nextIndex;
        for (int candidate = index - 1; candidate >= 0; candidate--)
        {
            if (orders[candidate] != null)
            {
                previousIndex = candidate;
                break;
            }
        }
        for (int candidate = index + 1; candidate < orders.length; candidate++)
        {
            if (orders[candidate] != null)
            {
                nextIndex = candidate;
                break;
            }
        }
        final double? previous = previousIndex == null
                ? null
                : orders[previousIndex];
        final double? next = nextIndex == null ? null : orders[nextIndex];
        if (previous != null && next != null && next > previous)
        {
            final double position =
                    (index - previousIndex!) / (nextIndex! - previousIndex);
            return previous + (next - previous) * position;
        }
        if (previous != null)
        {
            return previous + (index - previousIndex!) / 1000;
        }
        if (next != null)
        {
            return next - (nextIndex! - index) / 1000;
        }
        return index + 1 + (index + 1) / 1000000;
    }

    List<Chapter> _chaptersFromSingleNovelPost(
        Work work,
        ForumThreadPage page,
        List<SourcePost> posts,
    )
    {
        if (_isNonWorkNovelType(work.typeName))
        {
            return const <Chapter>[];
        }
        final List<SourcePost> readable = posts
                .where(_isReadableNovelPost)
                .toList(growable: false);
        if (readable.length != 1)
        {
            return const <Chapter>[];
        }

        final SourcePost post = readable.single;
        final List<_NovelBlockHeading> headings = <_NovelBlockHeading>[];
        for (int index = 0; index < post.blocks.length; index++)
        {
            final PostContentBlock block = post.blocks[index];
            if (block is! PostTextBlock)
            {
                continue;
            }
            final _NovelBlockHeading? heading = _novelBlockHeading(block, index);
            if (heading != null)
            {
                headings.add(heading);
            }
        }
        if (headings.length < 2)
        {
            return const <Chapter>[];
        }

        final Set<int> excluded = _directoryHeadingIndexes(headings, post.blocks);
        final Map<String, int> lastHeadingByIdentity = <String, int>{};
        for (int index = 0; index < headings.length; index++)
        {
            if (!excluded.contains(index))
            {
                lastHeadingByIdentity[headings[index].identity] = index;
            }
        }
        List<_NovelBlockHeading> selected = <_NovelBlockHeading>[
            for (int index = 0; index < headings.length; index++)
                if (!excluded.contains(index) &&
                        lastHeadingByIdentity[headings[index].identity] == index)
                    headings[index],
        ];
        selected = <_NovelBlockHeading>[
            for (int index = 0; index < selected.length; index++)
                if (_novelBlockRangeHasSubstance(
                    post.blocks,
                    selected[index].blockIndex,
                    index + 1 < selected.length
                            ? selected[index + 1].blockIndex
                            : post.blocks.length,
                ))
                    selected[index],
        ];
        if (selected.length < 2)
        {
            return const <Chapter>[];
        }

        return <Chapter>[
            for (int index = 0; index < selected.length; index++)
                Chapter(
                    id:
                            'forum-post:${page.tid}:${post.pid}:block:'
                            '${selected[index].blockIndex}',
                    title: _shortTitle(selected[index].title),
                    sourceUri: page.uri,
                    sourceTid: page.tid,
                    sourcePid: post.pid,
                    sourceStartBlock: selected[index].blockIndex,
                    sourceEndBlock: index + 1 < selected.length
                            ? selected[index + 1].blockIndex
                            : post.blocks.length,
                    order: (index + 1).toDouble(),
                ),
        ];
    }

    _NovelBlockHeading? _novelBlockHeading(PostTextBlock block, int blockIndex)
    {
        String candidate = block.text
                .split(RegExp(r'[\r\n]+'))
                .map(normalizeForumText)
                .map((String value) => value.trim())
                .firstWhere((String value) => value.isNotEmpty, orElse: () => '');
        if (candidate.isEmpty || candidate.length > 100)
        {
            return null;
        }
        final Match? quoted = RegExp(
            r'^[《【「『]\s*(.*?)\s*[》】」』]$',
        ).firstMatch(candidate);
        candidate = quoted?.group(1)?.trim() ?? candidate;

        final Match? numbered = RegExp(
            r'^(?:第\s*)?([零〇一二三四五六七八九十百两兩\d０-９]+)\s*'
            r'(章|话|話|回|节|節)(?:\s+|[:：、.．-]|$)',
        ).firstMatch(candidate);
        if (numbered != null)
        {
            return _NovelBlockHeading(
                blockIndex: blockIndex,
                title: candidate,
                identity: 'numbered:${_normalizedHeadingNumber(numbered.group(1)!)}',
            );
        }

        final Match? bareNumber = RegExp(
            r'^([\d０-９]{1,3})(?:\s+|[、.．]\s*)\S',
        ).firstMatch(candidate);
        if (bareNumber != null)
        {
            return _NovelBlockHeading(
                blockIndex: blockIndex,
                title: candidate,
                identity: 'section:${_normalizedHeadingNumber(bareNumber.group(1)!)}',
            );
        }

        final Match? special = RegExp(
            r'^(序章|终章|終章|尾声|尾聲|后记|後記|'
            r'幕间|幕間|间章|間章|番外(?:篇)?)'
            r'\s*([零〇一二三四五六七八九十百两兩\d０-９]*)',
        ).firstMatch(candidate);
        if (special == null)
        {
            return null;
        }
        final String marker = special.group(1)!;
        final String number = special.group(2)!.isEmpty
                ? ''
                : _normalizedHeadingNumber(special.group(2)!);
        return _NovelBlockHeading(
            blockIndex: blockIndex,
            title: candidate,
            identity: 'special:$marker:$number',
        );
    }

    Set<int> _directoryHeadingIndexes(
        List<_NovelBlockHeading> headings,
        List<PostContentBlock> blocks,
    )
    {
        final Set<int> excluded = <int>{};
        int start = 0;
        while (start < headings.length)
        {
            int end = start + 1;
            while (end < headings.length &&
                    headings[end].blockIndex == headings[end - 1].blockIndex + 1)
            {
                end++;
            }
            if (end - start >= 3)
            {
                final Map<String, int> seen = <String, int>{};
                int? firstRepeat;
                for (int index = start; index < end; index++)
                {
                    if (seen.containsKey(headings[index].identity))
                    {
                        firstRepeat = index;
                        break;
                    }
                    seen[headings[index].identity] = index;
                }
                if (firstRepeat != null)
                {
                    excluded.addAll(<int>[
                        for (int index = start; index < firstRepeat; index++) index,
                    ]);
                } else if (_hasContentsMarkerBefore(
                    blocks,
                    headings[start].blockIndex,
                ))
                {
                    excluded.addAll(<int>[
                        for (int index = start; index < end; index++) index,
                    ]);
                }
            }
            start = end;
        }
        return excluded;
    }

    bool _hasContentsMarkerBefore(List<PostContentBlock> blocks, int blockIndex)
    {
        final int first = blockIndex > 3 ? blockIndex - 3 : 0;
        for (int index = first; index < blockIndex; index++)
        {
            final PostContentBlock block = blocks[index];
            if (block is PostTextBlock &&
                    RegExp(
                        r'^(?:contents|目录|目錄)$',
                        caseSensitive: false,
                    ).hasMatch(normalizeForumText(block.text).trim()))
            {
                return true;
            }
        }
        return false;
    }

    bool _novelBlockRangeHasSubstance(
        List<PostContentBlock> blocks,
        int start,
        int end,
    )
    {
        int score = 0;
        for (int index = start; index < end; index++)
        {
            final PostContentBlock block = blocks[index];
            if (block is PostTextBlock)
            {
                score += normalizeForumText(
                    block.text,
                ).replaceAll(RegExp(r'\s+'), '').length;
            } else if (block is PostImageBlock)
            {
                score += 200;
            }
            if (score >= 80)
            {
                return true;
            }
        }
        return false;
    }

    String _normalizedHeadingNumber(String value)
    {
        final String ascii = value.replaceAllMapped(
            RegExp(r'[０-９]'),
            (Match match) =>
                    String.fromCharCode(match.group(0)!.codeUnitAt(0) - 0xfee0),
        );
        final int? numeric = int.tryParse(ascii);
        return numeric?.toString() ?? ascii;
    }

    List<Chapter> _chaptersFromNovelPosts(
        Work work,
        ForumThreadPage page,
        List<SourcePost> posts,
    )
    {
        if (_isNonWorkNovelType(work.typeName))
        {
            return const <Chapter>[];
        }
        final List<SourcePost> readable = posts
                .where(_isReadableNovelPost)
                .toList(growable: true);
        if (readable.length < 2)
        {
            return const <Chapter>[];
        }
        final SourcePost first = readable.first;
        if (RegExp(r'(目录|目錄|索引)').hasMatch(first.plainText) &&
                first.plainText.length < 800)
        {
            readable.removeAt(0);
        }
        if (readable.length < 2)
        {
            return const <Chapter>[];
        }

        final List<Chapter> result = <Chapter>[];
        final Map<int, int?> nextPostPid = <int, int?>{
            for (int index = 0; index < posts.length; index++)
                posts[index].pid: index + 1 < posts.length
                        ? posts[index + 1].pid
                        : null,
        };
        for (int index = 0; index < readable.length; index++)
        {
            final SourcePost post = readable[index];
            result.add(
                Chapter(
                    id: 'forum-post:${page.tid}:${post.pid}',
                    title: _novelPostTitle(post, index),
                    sourceUri: page.uri,
                    sourceTid: page.tid,
                    sourcePid: post.pid,
                    sourceEndPid: nextPostPid[post.pid],
                    order: (index + 1).toDouble(),
                ),
            );
        }
        return result;
    }

    bool _isNonWorkNovelType(String value)
    {
        return RegExp(
            r'(其它|其他|公告|推荐|推薦|讨论|討論|求助|资料|資料|综合|綜合)',
        ).hasMatch(normalizeForumText(value));
    }

    bool _isReadableNovelPost(SourcePost post)
    {
        final String text = post.plainText.trim();
        return text.length >= 600 ||
                text.length >= 80 && _novelHeading(post) != null;
    }

    String _novelPostTitle(SourcePost post, int index)
    {
        return _novelHeading(post) ?? _postTitle(post, index, LibraryKind.novel);
    }

    String? _novelHeading(SourcePost post)
    {
        for (final PostTextBlock block in post.blocks.whereType<PostTextBlock>())
        {
            for (final String line in block.text.split(RegExp(r'[\r\n]+')))
            {
                String candidate = normalizeForumText(line).trim();
                if (candidate.isEmpty || candidate.length > 80)
                {
                    continue;
                }
                final Match? quoted = RegExp(
                    r'^[《【「『]\s*(.*?)\s*[》】」』]$',
                ).firstMatch(candidate);
                candidate = quoted?.group(1)?.trim() ?? candidate;
                if (RegExp(
                    r'^(?:(?:第\s*)?[零〇一二三四五六七八九十百两兩\d０-９]+\s*(?:章|话|話|回|节|節)(?:\s|$)|[零〇一二三四五六七八九十百两兩\d０-９]{1,4}[、.．]\s*\S|(?:序章|终章|終章|尾声|尾聲|后记|後記|幕间|幕間|间章|間章|番外)(?:\s|$))',
                ).hasMatch(candidate))
                {
                    return _shortTitle(candidate);
                }
            }
        }
        return null;
    }

    List<Chapter> _replaceCoarseChapters(
        List<Chapter> source,
        List<Chapter> detailed,
    )
    {
        if (detailed.isEmpty)
        {
            return source;
        }
        final Set<int> detailedTids = detailed
                .map((Chapter chapter) => chapter.sourceTid)
                .toSet();
        final List<Chapter> result = <Chapter>[];
        bool inserted = false;
        for (final Chapter chapter in source)
        {
            if (detailedTids.contains(chapter.sourceTid))
            {
                if (!inserted)
                {
                    result.addAll(detailed);
                    inserted = true;
                }
                continue;
            }
            result.add(chapter);
        }
        if (!inserted)
        {
            result.insertAll(0, detailed);
        }
        return _deduplicate(result);
    }

    void _addLink(List<Chapter> result, ThreadLink link)
    {
        final int? tid = link.tid;
        if (tid == null)
        {
            return;
        }
        final String title = _cleanDirectoryTitle(link.label);
        final StructuredTitle structured = _titleNormalizer.analyze(title);
        result.add(
            Chapter(
                id: link.pid == null
                        ? 'forum-thread:$tid'
                        : 'forum-post:$tid:${link.pid}',
                title: title,
                sourceUri: link.uri,
                sourceTid: tid,
                sourcePid: link.pid,
                order: structured.chapterOrder,
            ),
        );
    }

    List<Chapter> _deduplicate(List<Chapter> chapters)
    {
        final Map<String, Chapter> deduplicated = <String, Chapter>{};
        for (final Chapter chapter in chapters)
        {
            final String blockRange =
                    chapter.sourceStartBlock == null && chapter.sourceEndBlock == null
                    ? ''
                    : ':${chapter.sourceStartBlock ?? 0}:'
                                '${chapter.sourceEndBlock ?? -1}';
            final String key =
                    '${chapter.sourceTid}:${chapter.sourcePid ?? 0}'
                    '$blockRange';
            deduplicated.putIfAbsent(key, () => chapter);
        }
        return deduplicated.values.toList(growable: false);
    }

    String _cleanDirectoryTitle(String value)
    {
        final String cleaned = normalizeForumText(value)
                .replaceFirst(RegExp(r'^#\s*\d+\s*'), '')
                .replaceFirst(RegExp(r'^\d+\s*[#＃]\s*'), '')
                .trim();
        return _stripOuterDirectoryBrackets(cleaned)
                .replaceFirst(
                    RegExp(r'\s*(?:传送门?|傳送門?|链接|連結)$'),
                    '',
                )
                .trim();
    }

    String? _novelVolumeRelationLabel(String value)
    {
        final String label = _stripOuterDirectoryBrackets(
            normalizeForumText(value),
        );
        final Match? match = RegExp(
            r'^(?:第\s*)?([零〇一二三四五六七八九十百两兩\d]+)\s*部\s*'
            r'(?:传送门?|傳送門?|链接|連結|入口)?$',
        ).firstMatch(label);
        return match == null ? null : '第${match.group(1)}卷';
    }

    String _stripOuterDirectoryBrackets(String value)
    {
        const Map<String, String> brackets = <String, String>{
            '【': '】',
            '[': ']',
            '（': '）',
            '(': ')',
            '「': '」',
            '『': '』',
            '《': '》',
        };
        if (value.length >= 2 && brackets[value[0]] == value[value.length - 1])
        {
            return value.substring(1, value.length - 1).trim();
        }
        return value;
    }

    bool _isGenericLinkTitle(String value)
    {
        return value.isEmpty ||
                RegExp(
                    r'^(跳转|跳轉|原帖链接|原帖連結|查看|here)$',
                    caseSensitive: false,
                ).hasMatch(value);
    }

    String _postTitle(SourcePost? post, int index, LibraryKind kind)
    {
        if (post != null)
        {
            final List<PostTextBlock> blocks = post.blocks
                    .whereType<PostTextBlock>()
                    .toList(growable: false);
            for (final PostTextBlock block in blocks)
            {
                if (block.heading)
                {
                    return _shortTitle(block.text);
                }
            }
            if (blocks.isNotEmpty)
            {
                return _shortTitle(blocks.first.text);
            }
        }
        final String unit = kind == LibraryKind.comic ? '话' : '章';
        return '第${index + 1}$unit';
    }

    String _shortTitle(String value)
    {
        final String normalized = normalizeForumText(value);
        final Match? quoted = RegExp(
            r'^[『《【「]([^』》】」]{1,40})[』》】」]',
        ).firstMatch(normalized);
        if (quoted != null)
        {
            return quoted.group(1)!;
        }
        final Match? sentence = RegExp(
            r'^(.{1,40}?)(?:[。！？]|$)',
        ).firstMatch(normalized);
        final String title = sentence?.group(1)?.trim() ?? normalized;
        return title.length <= 40 ? title : '${title.substring(0, 40)}…';
    }
}

class _NovelBlockHeading
{
    const _NovelBlockHeading({
        required this.blockIndex,
        required this.title,
        required this.identity,
    });

    final int blockIndex;
    final String title;
    final String identity;
}

class _NovelDirectoryBlockSection
{
    const _NovelDirectoryBlockSection({
        required this.start,
        required this.end,
        required this.title,
    });

    final int start;
    final int end;
    final String title;
}
