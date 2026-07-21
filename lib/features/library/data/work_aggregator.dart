import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/data/long_form_classifier.dart';
import 'package:x300/features/library/data/title_normalizer.dart';
import 'package:x300/features/library/domain/library_models.dart';

class WorkAggregator
{
    const WorkAggregator([
        this._normalizer = const TitleNormalizer(),
        this._longFormClassifier = const LongFormClassifier(),
    ]);

    final TitleNormalizer _normalizer;
    final LongFormClassifier _longFormClassifier;

    String? canonicalKeyForThread(SourceThread thread)
    {
        if (_longFormClassifier.isExplicitShortComicThread(thread))
        {
            return '${thread.board.kind.name}|short|tid=${thread.tid}';
        }
        final StructuredTitle title = _normalizer.analyze(thread.title);
        if (_titleKey(thread, title).isEmpty)
        {
            return null;
        }
        return _canonicalKey(<_Candidate>[_Candidate(thread, title)]);
    }

    String? canonicalKeyForWork(Work work)
    {
        if (_longFormClassifier.isExplicitShortComic(work))
        {
            return work.sourceThreads.isEmpty
                    ? null
                    : canonicalKeyForThread(work.sourceThreads.first);
        }
        final List<_Candidate> candidates = work.sourceThreads
                .map(
                    (SourceThread thread) =>
                            _Candidate(thread, _normalizer.analyze(thread.title)),
                )
                .where((_Candidate value) => _candidateTitleKey(value).isNotEmpty)
                .toList(growable: false);
        if (candidates.isEmpty)
        {
            return null;
        }
        final List<_Candidate> identityCandidates = _dominantIdentity(candidates);
        return _canonicalKey(identityCandidates);
    }

    bool hasStrongChapterMarker(Work work)
    {
        return work.sourceThreads.any(
            (SourceThread thread) =>
                    _normalizer.analyze(thread.title).hasChapterMarker,
        );
    }

    List<Chapter> smartChaptersForDirectories(List<WorkDirectory> directories)
    {
        final List<Chapter> chapters = <Chapter>[];
        final Set<String> selectedKeys = <String>{};
        for (final WorkDirectory directory in directories)
        {
            final Set<String> keysFromEarlierDirectories = <String>{...selectedKeys};
            for (final Chapter chapter in directory.chapters)
            {
                final String key = _smartChapterKey(chapter);
                if (keysFromEarlierDirectories.contains(key))
                {
                    continue;
                }
                chapters.add(chapter);
                selectedKeys.add(key);
            }
        }
        return chapters..sort(_compareChapters);
    }

    List<Chapter> smartNovelChaptersForDirectories(
        List<WorkDirectory> directories,
    )
    {
        return <Chapter>[
            ..._smartNovelSerialChapters(directories),
            ..._smartNovelBookChapters(directories),
        ];
    }

    List<Chapter> _smartNovelSerialChapters(List<WorkDirectory> directories)
    {
        final List<_NovelSerialVersion> versions = <_NovelSerialVersion>[];
        for (final WorkDirectory directory in directories)
        {
            final List<Chapter> chapters = directory.chapters
                    .where(
                        (Chapter chapter) =>
                                _novelEditionForChapter(chapter) == NovelEdition.serial,
                    )
                    .toList(growable: false);
            if (chapters.isEmpty)
            {
                continue;
            }
            final Set<String> coverage = <String>{};
            int reliableCount = 0;
            for (final Chapter chapter in chapters)
            {
                final Set<String>? keys = _reliableNovelChapterKeys(chapter);
                if (keys == null)
                {
                    continue;
                }
                reliableCount++;
                coverage.addAll(keys);
            }
            versions.add(
                _NovelSerialVersion(
                    owner: directory.owner,
                    chapters: chapters,
                    reliableCount: reliableCount,
                    reliableCoverage: coverage.length,
                    latestTid: chapters
                            .map((Chapter chapter) => chapter.sourceTid)
                            .reduce(
                                (int current, int next) => current > next ? current : next,
                            ),
                ),
            );
        }
        if (versions.isEmpty)
        {
            return <Chapter>[];
        }
        versions.sort(_compareNovelSerialVersions);

        final List<Chapter> selected = <Chapter>[...versions.first.chapters];
        final Set<String> coverage = <String>{};
        for (final Chapter chapter in versions.first.chapters)
        {
            coverage.addAll(_reliableNovelChapterKeys(chapter) ?? const <String>{});
        }
        for (final _NovelSerialVersion version in versions.skip(1))
        {
            for (final Chapter chapter in version.chapters)
            {
                final Set<String>? keys = _reliableNovelChapterKeys(chapter);
                if (keys == null || keys.every(coverage.contains))
                {
                    continue;
                }
                selected.add(chapter);
                coverage.addAll(keys);
            }
        }
        return selected..sort(_compareChapters);
    }

    List<Chapter> _smartNovelBookChapters(List<WorkDirectory> directories)
    {
        final Map<String, List<_NovelBookVersion>> versionsByVolume =
                <String, List<_NovelBookVersion>>{};
        for (final WorkDirectory directory in directories)
        {
            final Map<String, List<Chapter>> chaptersByVolume =
                    <String, List<Chapter>>{};
            for (final Chapter chapter in directory.chapters)
            {
                if (_novelEditionForChapter(chapter) != NovelEdition.book)
                {
                    continue;
                }
                chaptersByVolume
                        .putIfAbsent(_novelBookVolumeKey(chapter), () => <Chapter>[])
                        .add(chapter);
            }
            for (final MapEntry<String, List<Chapter>> entry
                    in chaptersByVolume.entries)
            {
                final bool hasSplitChapter = entry.value.any(
                    (Chapter chapter) => !_isWholeBookChapter(chapter),
                );
                final List<Chapter> chapters = hasSplitChapter
                        ? entry.value
                                    .where((Chapter chapter) => !_isWholeBookChapter(chapter))
                                    .toList(growable: false)
                        : entry.value;
                final Chapter sample = chapters.first;
                versionsByVolume
                        .putIfAbsent(entry.key, () => <_NovelBookVersion>[])
                        .add(
                            _NovelBookVersion(
                                key: entry.key,
                                owner: directory.owner,
                                chapters: chapters,
                                split: hasSplitChapter,
                                latestTid: chapters
                                        .map((Chapter chapter) => chapter.sourceTid)
                                        .reduce(
                                            (int current, int next) =>
                                                    current > next ? current : next,
                                        ),
                                volumeOrder: sample.volumeOrder,
                                volumeTitle: sample.volumeTitle,
                            ),
                        );
            }
        }

        final List<_NovelBookVersion> selected = <_NovelBookVersion>[];
        for (final List<_NovelBookVersion> versions in versionsByVolume.values)
        {
            selected.add(
                versions.reduce((_NovelBookVersion current, _NovelBookVersion next)
        {
                    return _preferNovelBookVersion(next, current) ? next : current;
                }),
            );
        }
        selected.sort(_compareNovelBookVolumes);
        return selected
                .expand((_NovelBookVersion version)
        {
                    return <Chapter>[...version.chapters]..sort(_compareChapters);
                })
                .toList(growable: false);
    }

    int _compareNovelSerialVersions(
        _NovelSerialVersion left,
        _NovelSerialVersion right,
    )
    {
        int result = right.reliableCoverage.compareTo(left.reliableCoverage);
        if (result != 0)
        {
            return result;
        }
        result = right.reliableCount.compareTo(left.reliableCount);
        if (result != 0)
        {
            return result;
        }
        result = right.chapters.length.compareTo(left.chapters.length);
        if (result != 0)
        {
            return result;
        }
        result = right.latestTid.compareTo(left.latestTid);
        return result != 0 ? result : left.owner.compareTo(right.owner);
    }

    bool _preferNovelBookVersion(
        _NovelBookVersion candidate,
        _NovelBookVersion current,
    )
    {
        if (candidate.split != current.split)
        {
            return candidate.split;
        }
        if (candidate.chapters.length != current.chapters.length)
        {
            return candidate.chapters.length > current.chapters.length;
        }
        if (candidate.latestTid != current.latestTid)
        {
            return candidate.latestTid > current.latestTid;
        }
        return candidate.owner.compareTo(current.owner) < 0;
    }

    int _compareNovelBookVolumes(
        _NovelBookVersion left,
        _NovelBookVersion right,
    )
    {
        final double leftOrder = left.volumeOrder ?? double.infinity;
        final double rightOrder = right.volumeOrder ?? double.infinity;
        int result = leftOrder.compareTo(rightOrder);
        if (result != 0)
        {
            return result;
        }
        result = left.volumeTitle.compareTo(right.volumeTitle);
        return result != 0 ? result : left.key.compareTo(right.key);
    }

    Set<String>? _reliableNovelChapterKeys(Chapter chapter)
    {
        final String title = normalizeForumText(chapter.title).trim();
        final NumericChapterRange? range = _normalizer.detectNumericChapterRange(
            title,
        );
        if (range != null)
        {
            if (range.end - range.start <= 200)
            {
                return <String>{
                    for (int number = range.start; number <= range.end; number++)
                        'number:$number',
                };
            }
            return <String>{'range:${range.start}-${range.end}'};
        }

        final Match? numeric = RegExp(
            r'^(第\s*)?(\d{1,4}(?:\.\d+)?)\s*(话|話|章|回|节|節)?'
            r'(?=\s|[.．\-—:：#（(]|$)',
            caseSensitive: false,
        ).firstMatch(title);
        if (numeric != null)
        {
            final String marker = numeric.group(2)!;
            final double? number = double.tryParse(marker);
            final bool explicit =
                    numeric.group(1) != null ||
                    numeric.group(3) != null ||
                    marker.startsWith('0') ||
                    number != null && number <= 999;
            if (number != null && explicit)
            {
                return <String>{_novelNumberKey(number)};
            }
        }

        if (RegExp(r'^第\s*[零〇一二三四五六七八九十百两兩]+\s*(?:话|話|章|回|节|節)').hasMatch(title))
        {
            final StructuredTitle parsed = _normalizer.analyze('作品 $title');
            final double? order = parsed.chapterOrder;
            if (parsed.hasChapterMarker && order != null && order < 800000)
            {
                return <String>{_novelNumberKey(order)};
            }
        }

        final Match? named = RegExp(
            r'^(序章|序幕|楔子|引子|终章|終章|最终章|最終章|'
            r'最终话|最終話|终话|終話|尾声|尾聲|后记|後記|'
            r'幕间|幕間|间章|間章|番外(?:篇|章)?|特典|外传|外傳|'
            r'prologue|epilogue|afterword|interlude|extra|'
            r'bonus\s*track|last\s*track)\s*(\d+(?:\.\d+)?)?',
            caseSensitive: false,
        ).firstMatch(title);
        if (named == null)
        {
            return null;
        }
        final String marker = _novelNamedMarkerKey(named.group(1)!);
        final String? number = named.group(2);
        if (number != null)
        {
            return <String>{'named:$marker:${double.parse(number)}'};
        }
        if (<String>
        {
            '番外',
            '幕间',
            '间章',
            '特典',
            '外传',
            'interlude',
            'extra',
        }.contains(marker))
        {
            final String remainder = _novelTextKey(title.substring(named.end));
            return <String>{
                remainder.isEmpty ? 'named:$marker' : 'named:$marker:$remainder',
            };
        }
        return <String>{'named:$marker'};
    }

    String _novelNumberKey(double number)
    {
        return number == number.roundToDouble()
                ? 'number:${number.toInt()}'
                : 'number:$number';
    }

    String _novelNamedMarkerKey(String value)
    {
        final String marker = normalizeForumText(value).toLowerCase();
        return switch (marker)
        {
            '終章' => '终章',
            '最終章' => '最终章',
            '最終話' => '最终话',
            '終話' => '终话',
            '尾聲' => '尾声',
            '後記' => '后记',
            '幕間' => '幕间',
            '間章' => '间章',
            '外傳' => '外传',
            String value when value.startsWith('番外') => '番外',
            _ => marker,
        };
    }

    String _novelTextKey(String value)
    {
        return normalizeForumText(
            value,
        ).toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');
    }

    NovelEdition _novelEditionForChapter(Chapter chapter)
    {
        return chapter.novelEdition ?? NovelEdition.serial;
    }

    String _novelBookVolumeKey(Chapter chapter)
    {
        double? order = chapter.volumeOrder;
        if (order == null && chapter.volumeTitle.isNotEmpty)
        {
            order = _normalizer.analyze('作品 ${chapter.volumeTitle}').volumeOrder;
        }
        if (order != null)
        {
            return 'order:$order';
        }
        final String title = _novelTextKey(chapter.volumeTitle);
        return title.isEmpty ? 'source:${chapter.sourceTid}' : 'title:$title';
    }

    bool _isWholeBookChapter(Chapter chapter)
    {
        final String title = _novelTextKey(chapter.title);
        if (<String>{'整卷', '整卷阅读', '全文', '全文阅读'}.contains(title))
        {
            return true;
        }
        return chapter.sourcePid == null &&
                chapter.sourceStartBlock == null &&
                chapter.sourceEndBlock == null;
    }

    String workIdForCanonicalKey(String canonicalKey)
    {
        final String digest = sha256
                .convert(utf8.encode(canonicalKey))
                .toString()
                .substring(0, 20);
        return 'forum-work:$digest';
    }

    bool matches(Work left, Work right)
    {
        if (sharesSource(left, right))
        {
            return true;
        }
        final _WorkIdentity? leftIdentity = _identityForWork(left);
        final _WorkIdentity? rightIdentity = _identityForWork(right);
        if (leftIdentity == null || rightIdentity == null)
        {
            return false;
        }
        if (leftIdentity.kind != rightIdentity.kind ||
                leftIdentity.titleKey != rightIdentity.titleKey)
        {
            return false;
        }
        if (leftIdentity.creatorKeys.isNotEmpty &&
                rightIdentity.creatorKeys.isNotEmpty &&
                leftIdentity.creatorKeys
                        .intersection(rightIdentity.creatorKeys)
                        .isEmpty)
        {
            return false;
        }
        return leftIdentity.typeIds.isEmpty ||
                rightIdentity.typeIds.isEmpty ||
                leftIdentity.typeIds.intersection(rightIdentity.typeIds).isNotEmpty;
    }

    bool sharesSource(Work left, Work right)
    {
        final Set<int> tids = <int>{
            ...left.sourceThreads.map((SourceThread thread) => thread.tid),
            ...left.chapters.map((Chapter chapter) => chapter.sourceTid),
            ...left.directories.expand(
                (WorkDirectory directory) => directory.sourceTids,
            ),
        };
        return right.sourceThreads.any(
                    (SourceThread thread) => tids.contains(thread.tid),
                ) ||
                right.chapters.any(
                    (Chapter chapter) => tids.contains(chapter.sourceTid),
                ) ||
                right.directories.any(
                    (WorkDirectory directory) => directory.sourceTids.any(tids.contains),
                );
    }

    List<Work> aggregate(List<SourceThread> sourceThreads)
    {
        final Map<int, int> sourceOrder = <int, int>{
            for (int index = 0; index < sourceThreads.length; index++)
                sourceThreads[index].tid: index,
        };
        final List<_Candidate> standalone = <_Candidate>[];
        final Map<String, List<_Candidate>> coarseGroups =
                <String, List<_Candidate>>{};

        for (final SourceThread thread in sourceThreads)
        {
            if (thread.administrative)
            {
                continue;
            }
            final StructuredTitle title = _normalizer.analyze(thread.title);
            final _Candidate candidate = _Candidate(thread, title);
            final bool novelEditionRoot =
                    thread.board.kind == LibraryKind.novel && title.novelEdition != null;
            if (_longFormClassifier.isExplicitShortComicThread(thread) ||
                    !title.hasChapterMarker && !novelEditionRoot ||
                    _candidateTitleKey(candidate).isEmpty)
            {
                standalone.add(candidate);
                continue;
            }
            final String groupKey = _coarseKey(candidate);
            coarseGroups.putIfAbsent(groupKey, () => <_Candidate>[]).add(candidate);
        }

        final List<Work> result = <Work>[...standalone.map(_standaloneWork)];
        for (final List<_Candidate> coarseGroup in coarseGroups.values)
        {
            for (final List<_Candidate> candidates in _partitionCompatible(
                coarseGroup,
            ))
            {
                if (candidates.length < 2)
                {
                    result.add(_standaloneWork(candidates.single));
                } else
                {
                    result.add(_groupedWork(candidates));
                }
            }
        }

        result.sort((Work left, Work right)
        {
            final int leftIndex = left.sourceThreads
                    .map((SourceThread value) => sourceOrder[value.tid]!)
                    .reduce((int current, int next) => current < next ? current : next);
            final int rightIndex = right.sourceThreads
                    .map((SourceThread value) => sourceOrder[value.tid]!)
                    .reduce((int current, int next) => current < next ? current : next);
            return leftIndex.compareTo(rightIndex);
        });
        return result;
    }

    Work _standaloneWork(_Candidate candidate)
    {
        final SourceThread thread = candidate.thread;
        final Chapter chapter = Chapter(
            id: 'forum-thread:${thread.tid}',
            title: candidate.title.chapterLabel.isEmpty
                    ? '正文'
                    : candidate.title.chapterLabel,
            sourceUri: thread.uri,
            sourceTid: thread.tid,
            order: candidate.title.chapterOrder,
            novelEdition: thread.board.kind == LibraryKind.novel
                    ? candidate.title.novelEdition ?? NovelEdition.serial
                    : null,
            volumeTitle: candidate.title.volumeTitle,
            volumeOrder: candidate.title.volumeOrder,
        );
        final WorkDirectory directory = _directoryForCandidates(
            <_Candidate>[candidate],
            chapters: <Chapter>[chapter],
        );
        return Work(
            id: 'forum-thread:${thread.tid}',
            kind: thread.board.kind,
            title: _candidateDisplayTitle(candidate),
            summary: thread.summary,
            author: thread.author,
            typeName: thread.typeName,
            sourceThreads: <SourceThread>[thread],
            chapters: <Chapter>[chapter],
            directories: <WorkDirectory>[directory],
        );
    }

    Work _groupedWork(List<_Candidate> candidates)
    {
        final List<_Candidate> ordered = <_Candidate>[...candidates]
            ..sort(_compareCandidates);
        final _Candidate primary = ordered.reduce((
            _Candidate current,
            _Candidate next,
        )
        {
            final DateTime? currentTime = current.thread.postedAt;
            final DateTime? nextTime = next.thread.postedAt;
            if (currentTime == null)
            {
                return nextTime == null ? current : next;
            }
            return nextTime != null && nextTime.isAfter(currentTime) ? next : current;
        });
        final List<WorkDirectory> directories = _directoriesForCandidates(ordered);
        final WorkDirectory defaultDirectory = directories.first;
        final String groupKey = _canonicalKey(ordered);
        return Work(
            id: workIdForCanonicalKey(groupKey),
            kind: primary.thread.board.kind,
            title: _candidateDisplayTitle(primary),
            summary: ordered
                    .map((_Candidate value) => value.thread.summary)
                    .firstWhere((String value) => value.isNotEmpty, orElse: () => ''),
            author: defaultDirectory.owner,
            typeName: primary.thread.typeName,
            sourceThreads: ordered
                    .map((_Candidate value) => value.thread)
                    .toList(growable: false),
            chapters: primary.thread.board.kind == LibraryKind.novel
                    ? smartNovelChaptersForDirectories(directories)
                    : smartChaptersForDirectories(directories),
            directories: directories,
        );
    }

    List<WorkDirectory> _directoriesForCandidates(List<_Candidate> candidates)
    {
        final Map<String, List<_Candidate>> ownerGroups =
                <String, List<_Candidate>>{};
        for (final _Candidate candidate in candidates)
        {
            ownerGroups
                    .putIfAbsent(_ownerKey(candidate.thread.author), () => <_Candidate>[])
                    .add(candidate);
        }
        final List<WorkDirectory> directories =
                ownerGroups.values.map(_directoryForCandidates).toList(growable: true)
                    ..sort(_compareDirectories);
        return directories;
    }

    WorkDirectory _directoryForCandidates(
        List<_Candidate> candidates,
        {
        List<Chapter>? chapters,
    })
    {
        final String owner = normalizeForumText(candidates.first.thread.author);
        final List<int> sourceTids =
                candidates
                        .map((_Candidate value) => value.thread.tid)
                        .toSet()
                        .toList(growable: true)
                    ..sort();
        return WorkDirectory(
            id: _directoryId(owner),
            owner: owner,
            sourceTids: sourceTids,
            chapters: chapters ?? _chaptersForCandidates(candidates),
        );
    }

    List<Chapter> _chaptersForCandidates(List<_Candidate> candidates)
    {
        final List<_Candidate> selected = <_Candidate>[];
        final Map<String, int> numericIndexes = <String, int>{};
        for (final _Candidate candidate in candidates)
        {
            final double? order = candidate.title.chapterOrder;
            if (order == null || order >= 800000)
            {
                selected.add(candidate);
                continue;
            }
            final String key = _numberedChapterKey(
                order,
                candidate.title.chapterLabel,
            );
            final int? existingIndex = numericIndexes[key];
            if (existingIndex == null)
            {
                numericIndexes[key] = selected.length;
                selected.add(candidate);
                continue;
            }
            if (_prefer(candidate, selected[existingIndex]))
            {
                selected[existingIndex] = candidate;
            }
        }

        final Map<String, int> titleCounts = <String, int>{};
        for (final _Candidate candidate in selected)
        {
            titleCounts.update(
                candidate.title.chapterLabel,
                (int value) => value + 1,
                ifAbsent: () => 1,
            );
        }
        final Map<String, int> titleIndexes = <String, int>{};
        return selected
                .map((_Candidate candidate)
        {
                    final String baseTitle = candidate.title.chapterLabel.isEmpty
                            ? '正文'
                            : candidate.title.chapterLabel;
                    String title = baseTitle;
                    if ((titleCounts[baseTitle] ?? 0) > 1)
                    {
                        final int index = titleIndexes.update(
                            baseTitle,
                            (int value) => value + 1,
                            ifAbsent: () => 1,
                        );
                        title = '$baseTitle $index';
                    }
                    return Chapter(
                        id: 'forum-thread:${candidate.thread.tid}',
                        title: title,
                        sourceUri: candidate.thread.uri,
                        sourceTid: candidate.thread.tid,
                        order: candidate.title.chapterOrder,
                        novelEdition: candidate.thread.board.kind == LibraryKind.novel
                                ? candidate.title.novelEdition ?? NovelEdition.serial
                                : null,
                        volumeTitle: candidate.title.volumeTitle,
                        volumeOrder: candidate.title.volumeOrder,
                    );
                })
                .toList(growable: false);
    }

    bool _prefer(_Candidate candidate, _Candidate current)
    {
        final DateTime? candidateTime = candidate.thread.postedAt;
        final DateTime? currentTime = current.thread.postedAt;
        if (candidateTime != null && currentTime != null)
        {
            return candidateTime.isAfter(currentTime);
        }
        if (candidateTime != null)
        {
            return true;
        }
        if (currentTime != null)
        {
            return false;
        }
        return candidate.thread.tid > current.thread.tid;
    }

    List<List<_Candidate>> _partitionCompatible(List<_Candidate> candidates)
    {
        final List<List<_Candidate>> typeGroups = _partitionByType(candidates);
        return typeGroups.expand(_partitionByCreator).toList(growable: false);
    }

    List<List<_Candidate>> _partitionByType(List<_Candidate> candidates)
    {
        final Map<int, List<_Candidate>> typed = <int, List<_Candidate>>{};
        final List<_Candidate> unknown = <_Candidate>[];
        for (final _Candidate candidate in candidates)
        {
            final int? typeId = candidate.thread.typeId;
            if (typeId == null)
            {
                unknown.add(candidate);
            } else
            {
                typed.putIfAbsent(typeId, () => <_Candidate>[]).add(candidate);
            }
        }
        if (typed.length <= 1)
        {
            final List<_Candidate> values = typed.isEmpty
                    ? <_Candidate>[]
                    : <_Candidate>[...typed.values.single];
            values.addAll(unknown);
            return <List<_Candidate>>[values];
        }
        return <List<_Candidate>>[...typed.values, if (unknown.isNotEmpty) unknown];
    }

    List<List<_Candidate>> _partitionByCreator(List<_Candidate> candidates)
    {
        final Map<String, List<_Candidate>> creators = <String, List<_Candidate>>{};
        final List<_Candidate> unknown = <_Candidate>[];
        for (final _Candidate candidate in candidates)
        {
            final String creatorKey = candidate.title.creatorKey;
            if (creatorKey.isEmpty)
            {
                unknown.add(candidate);
            } else
            {
                creators.putIfAbsent(creatorKey, () => <_Candidate>[]).add(candidate);
            }
        }
        if (creators.length <= 1)
        {
            final List<_Candidate> values = creators.isEmpty
                    ? <_Candidate>[]
                    : <_Candidate>[...creators.values.single];
            values.addAll(unknown);
            return <List<_Candidate>>[values];
        }
        return <List<_Candidate>>[
            ...creators.values,
            if (unknown.isNotEmpty) unknown,
        ];
    }

    String _coarseKey(_Candidate candidate)
    {
        return <String>[
            candidate.thread.board.kind.name,
            _candidateTitleKey(candidate),
        ].join('|');
    }

    String _canonicalKey(List<_Candidate> candidates)
    {
        final _WorkIdentity identity = _identityForCandidates(candidates);
        return <String>[
            identity.kind.name,
            identity.titleKey,
            if (identity.creatorKeys.length == 1)
                'author=${identity.creatorKeys.single}',
            if (identity.creatorKeys.length > 1)
                'authors=${identity.creatorKeys.toList()..sort()}',
            if (identity.typeIds.length == 1)
                'type=${identity.typeIds.single}'
            else
                'type=none',
        ].join('|');
    }

    _WorkIdentity? _identityForWork(Work work)
    {
        final List<_Candidate> candidates = work.sourceThreads
                .map(
                    (SourceThread thread) =>
                            _Candidate(thread, _normalizer.analyze(thread.title)),
                )
                .where((_Candidate value) => _candidateTitleKey(value).isNotEmpty)
                .toList(growable: false);
        if (candidates.isEmpty)
        {
            return null;
        }
        return _identityForCandidates(_dominantIdentity(candidates));
    }

    List<_Candidate> _dominantIdentity(List<_Candidate> candidates)
    {
        final Map<String, List<_Candidate>> groups = <String, List<_Candidate>>{};
        for (final _Candidate candidate in candidates)
        {
            groups
                    .putIfAbsent(_coarseKey(candidate), () => <_Candidate>[])
                    .add(candidate);
        }
        return groups.values.reduce((
            List<_Candidate> current,
            List<_Candidate> next,
        )
        {
            final int currentStrong = current
                    .where((_Candidate value) => value.title.hasChapterMarker)
                    .length;
            final int nextStrong = next
                    .where((_Candidate value) => value.title.hasChapterMarker)
                    .length;
            if (nextStrong != currentStrong)
            {
                return nextStrong > currentStrong ? next : current;
            }
            return next.length > current.length ? next : current;
        });
    }

    _WorkIdentity _identityForCandidates(List<_Candidate> candidates)
    {
        return _WorkIdentity(
            kind: candidates.first.thread.board.kind,
            titleKey: _candidateTitleKey(candidates.first),
            creatorKeys: candidates
                    .map((_Candidate value) => value.title.creatorKey)
                    .where((String value) => value.isNotEmpty)
                    .toSet(),
            typeIds: candidates
                    .map((_Candidate value) => value.thread.typeId)
                    .whereType<int>()
                    .toSet(),
        );
    }

    int _compareCandidates(_Candidate left, _Candidate right)
    {
        final double? leftOrder = left.title.chapterOrder;
        final double? rightOrder = right.title.chapterOrder;
        if (leftOrder != null && rightOrder != null)
        {
            final int result = leftOrder.compareTo(rightOrder);
            if (result != 0)
            {
                return result;
            }
        } else if (leftOrder != null)
        {
            return -1;
        } else if (rightOrder != null)
        {
            return 1;
        }
        return left.thread.tid.compareTo(right.thread.tid);
    }

    String _smartChapterKey(Chapter chapter)
    {
        final double? order = chapter.order;
        if (order != null && order < 800000)
        {
            return _numberedChapterKey(order, chapter.title);
        }
        final String title = normalizeForumText(
            chapter.title,
        ).toLowerCase().replaceAll(RegExp(r'[\s\-—–_:：·・,，。.!！?？()（）\[\]【】]+'), '');
        return title.isEmpty
                ? 'source:${chapter.sourceTid}:${chapter.sourcePid ?? 0}'
                : 'named:$title';
    }

    String _numberedChapterKey(double order, String title)
    {
        final Match? part = RegExp(
            r'(?:其(?:之|の)|part|pt\.?)\s*'
            r'([零〇一二三四五六七八九十百两兩\d]+)\s*$',
            caseSensitive: false,
        ).firstMatch(normalizeForumText(title));
        return part == null
                ? 'main:$order'
                : 'main:$order:part:${part.group(1)!.toLowerCase()}';
    }

    int _compareChapters(Chapter left, Chapter right)
    {
        final double? leftOrder = left.order;
        final double? rightOrder = right.order;
        if (leftOrder != null && rightOrder != null)
        {
            final int result = leftOrder.compareTo(rightOrder);
            if (result != 0)
            {
                return result;
            }
        } else if (leftOrder != null)
        {
            return -1;
        } else if (rightOrder != null)
        {
            return 1;
        }
        final int tidResult = left.sourceTid.compareTo(right.sourceTid);
        return tidResult != 0
                ? tidResult
                : (left.sourcePid ?? 0).compareTo(right.sourcePid ?? 0);
    }

    int _compareDirectories(WorkDirectory left, WorkDirectory right)
    {
        final List<double> leftMain = left.chapters
                .map((Chapter value) => value.order)
                .whereType<double>()
                .where((double value) => value < 800000)
                .toList(growable: false);
        final List<double> rightMain = right.chapters
                .map((Chapter value) => value.order)
                .whereType<double>()
                .where((double value) => value < 800000)
                .toList(growable: false);
        int result = rightMain.length.compareTo(leftMain.length);
        if (result != 0)
        {
            return result;
        }
        final double leftLatest = leftMain.isEmpty
                ? double.negativeInfinity
                : leftMain.reduce((double a, double b) => a > b ? a : b);
        final double rightLatest = rightMain.isEmpty
                ? double.negativeInfinity
                : rightMain.reduce((double a, double b) => a > b ? a : b);
        result = rightLatest.compareTo(leftLatest);
        if (result != 0)
        {
            return result;
        }
        result = right.chapters.length.compareTo(left.chapters.length);
        return result != 0 ? result : left.owner.compareTo(right.owner);
    }

    String _directoryId(String owner)
    {
        final String key = _ownerKey(owner);
        if (key.isEmpty)
        {
            return 'owner:unknown';
        }
        final String digest = sha256
                .convert(utf8.encode(key))
                .toString()
                .substring(0, 16);
        return 'owner:$digest';
    }

    String _ownerKey(String value)
    {
        return normalizeForumText(value).toLowerCase();
    }

    String _titleKey(SourceThread thread, StructuredTitle title)
    {
        return thread.board.kind == LibraryKind.novel
                ? title.novelTitleKey
                : title.titleKey;
    }

    String _candidateTitleKey(_Candidate candidate)
    {
        return _titleKey(candidate.thread, candidate.title);
    }

    String _candidateDisplayTitle(_Candidate candidate)
    {
        return candidate.thread.board.kind == LibraryKind.novel
                ? candidate.title.novelDisplayTitle
                : candidate.title.displayTitle;
    }
}

class _Candidate
{
    const _Candidate(this.thread, this.title);

    final SourceThread thread;
    final StructuredTitle title;
}

class _NovelSerialVersion
{
    const _NovelSerialVersion({
        required this.owner,
        required this.chapters,
        required this.reliableCount,
        required this.reliableCoverage,
        required this.latestTid,
    });

    final String owner;
    final List<Chapter> chapters;
    final int reliableCount;
    final int reliableCoverage;
    final int latestTid;
}

class _NovelBookVersion
{
    const _NovelBookVersion({
        required this.key,
        required this.owner,
        required this.chapters,
        required this.split,
        required this.latestTid,
        required this.volumeOrder,
        required this.volumeTitle,
    });

    final String key;
    final String owner;
    final List<Chapter> chapters;
    final bool split;
    final int latestTid;
    final double? volumeOrder;
    final String volumeTitle;
}

class _WorkIdentity
{
    const _WorkIdentity({
        required this.kind,
        required this.titleKey,
        required this.creatorKeys,
        required this.typeIds,
    });

    final LibraryKind kind;
    final String titleKey;
    final Set<String> creatorKeys;
    final Set<int> typeIds;
}
