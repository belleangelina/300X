import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/domain/library_models.dart';

class NumericChapterRange
{
    const NumericChapterRange({
        required this.start,
        required this.end,
        required this.label,
    });

    final int start;
    final int end;
    final String label;
}

class NovelBareVolumeCandidate
{
    const NovelBareVolumeCandidate({
        required this.displayTitle,
        required this.titleKey,
        required this.creatorKey,
        required this.volumeNumber,
    });

    final String displayTitle;
    final String titleKey;
    final String creatorKey;
    final int volumeNumber;
}

class TitleNormalizer
{
    const TitleNormalizer();

    NumericChapterRange? detectNumericChapterRange(String value)
    {
        final String normalized = normalizeForumText(_toHalfWidth(value));
        final Match? match = RegExp(
            r'(?:第\s*)?(\d{1,4})\s*(?:-|~|～|—|–|至)\s*'
            r'(?:第\s*)?(\d{1,4})\s*(?:话|話|章|回|节|節)',
            caseSensitive: false,
        ).firstMatch(normalized);
        if (match == null)
        {
            return null;
        }
        final int? start = int.tryParse(match.group(1)!);
        final int? end = int.tryParse(match.group(2)!);
        if (start == null || end == null || start <= 0 || end <= start)
        {
            return null;
        }
        return NumericChapterRange(
            start: start,
            end: end,
            label: normalizeForumText(match.group(0)!),
        );
    }

    NovelBareVolumeCandidate? detectNovelBareVolumeCandidate(String original)
    {
        final String normalized = normalizeForumText(_toHalfWidth(original));
        final ({String title, String authorMarker}) metadata =
                _stripLeadingMetadata(_stripTrailingReleaseMetadata(normalized));
        final String working = _stripCompletionMarker(metadata.title);
        final Match? match = RegExp(
            r'^(.*?)\s+(0*[1-9]\d?)\s*$',
        ).firstMatch(working);
        if (match == null || _keyText(match.group(1)!).length < 2)
        {
            return null;
        }
        final int volumeNumber = int.parse(match.group(2)!);
        final StructuredTitle title = analyze(original);
        if (title.novelEdition != null ||
                !title.hasChapterMarker ||
                title.chapterOrder != volumeNumber)
        {
            return null;
        }
        return NovelBareVolumeCandidate(
            displayTitle: title.novelDisplayTitle,
            titleKey: title.novelTitleKey,
            creatorKey: title.creatorKey,
            volumeNumber: volumeNumber,
        );
    }

    NovelBareVolumeCandidate? detectNovelAdjacentVolumeCandidate(String original)
    {
        final String normalized = normalizeForumText(_toHalfWidth(original));
        final ({String title, String authorMarker}) metadata =
                _stripLeadingMetadata(_stripTrailingReleaseMetadata(normalized));
        final String working = _stripCompletionMarker(metadata.title);
        final Match? match = RegExp(r'^(.*[^\d\s])(\d{1,2})$').firstMatch(working);
        if (match == null || _keyText(match.group(1)!).length < 2)
        {
            return null;
        }
        final int? volumeNumber = int.tryParse(match.group(2)!);
        if (volumeNumber == null || volumeNumber <= 0)
        {
            return null;
        }
        final String displayTitle = normalizeForumText(match.group(1)!);
        return NovelBareVolumeCandidate(
            displayTitle: displayTitle,
            titleKey: _keyText(displayTitle),
            creatorKey: metadata.authorMarker,
            volumeNumber: volumeNumber,
        );
    }

    StructuredTitle analyze(String original)
    {
        final String normalizedOriginal = normalizeForumText(
            _toHalfWidth(original),
        );
        NovelEdition? novelEdition = _explicitNovelEdition(normalizedOriginal);
        final ({String title, String authorMarker}) metadata =
                _stripLeadingMetadata(
                    _stripTrailingReleaseMetadata(normalizedOriginal),
                );
        String working = metadata.title;
        String authorMarker = metadata.authorMarker;

        final Match? author = RegExp(
            r'^\s*[\(（]([^\(\)（）]{1,30})[\)）]\s*(?=\S{3,})',
        ).firstMatch(working);
        if (author != null && !_looksLikeVersionOrUpdate(author.group(1)!))
        {
            authorMarker = authorMarker.isEmpty
                    ? _keyText(author.group(1)!)
                    : authorMarker;
            working = working.substring(author.end).trim();
        }

        working = working.replaceAll(
            RegExp(
                r'\s*[\(（][^\(\)（）]{0,24}(?:更新至|更新到|連載至|连载至)[^\(\)（）]{0,24}[\)）]\s*$',
                caseSensitive: false,
            ),
            '',
        );
        working = _stripTrailingContinuationNote(working);
        working = _stripCompletionMarker(working);
        working = _unwrapTrailingVolumeMarker(working);

        String chapterLabel = '';
        double? chapterOrder;
        bool hasChapterMarker = false;
        final Match? indexedExtra = RegExp(
            r'(番外(?:篇)?\s*(\d+(?:\.\d+)?))\s*$',
            caseSensitive: false,
        ).firstMatch(working);
        if (indexedExtra != null)
        {
            chapterLabel = normalizeForumText(indexedExtra.group(1)!);
            chapterOrder = 900000 + (double.tryParse(indexedExtra.group(2)!) ?? 0);
            hasChapterMarker = true;
            working = working.substring(0, indexedExtra.start).trim();
        }

        final Match? decimalRangeChapter = hasChapterMarker
                ? null
                : RegExp(
                        r'^(.*?)(?:\s+|[_\-—#])'
                        r'(\d{1,4}(?:\.\d+)?)\s*'
                        r'(~|～|-|—|–|至)\s*'
                        r'(\d{1,4}(?:\.\d+)?)\s*$',
                    ).firstMatch(working) ??
                        RegExp(
                            r'^()(\d{1,4}(?:\.\d+)?)\s*'
                            r'(~|～|-|—|–|至)\s*'
                            r'(\d{1,4}(?:\.\d+)?)\s*$',
                        ).firstMatch(working);
        if (decimalRangeChapter != null)
        {
            final String startLabel = decimalRangeChapter.group(2)!;
            final String endLabel = decimalRangeChapter.group(4)!;
            final double? start = double.tryParse(startLabel);
            final double? end = double.tryParse(endLabel);
            final String base = normalizeForumText(decimalRangeChapter.group(1)!);
            final bool decimalRange =
                    startLabel.contains('.') || endLabel.contains('.');
            final bool integerRange =
                    !decimalRange &&
                    start != null &&
                    end != null &&
                    start <= 999 &&
                    end <= 999 &&
                    !RegExp(
                        r'(?:^|\s)p\.?\s*$',
                        caseSensitive: false,
                    ).hasMatch(base);
            if ((decimalRange || integerRange) &&
                    start != null &&
                    end != null &&
                    end > start &&
                    (base.isEmpty || _keyText(base).length >= 2))
            {
                chapterLabel = '$startLabel${decimalRangeChapter.group(3)}$endLabel';
                chapterOrder = start;
                hasChapterMarker = true;
                working = base;
            }
        }

        final Match? numericChapter = hasChapterMarker
                ? null
                : RegExp(
                        r'((?:第\s*)?(\d+(?:\.\d+)?)(?:\s*(?:-|~|～|—|–|至)\s*(?:第\s*)?(\d+(?:\.\d+)?))?\s*(?:话|話|章|回|节|節)|ch(?:apter)?\.?\s*(\d+(?:\.\d+)?))(?:\s*[-—:：#]?\s*(.{1,48}))?\s*$',
                        caseSensitive: false,
                    ).firstMatch(working);
        if (numericChapter != null)
        {
            chapterLabel = _chapterLabel(
                numericChapter.group(1)!,
                numericChapter.group(5),
            );
            chapterOrder = double.tryParse(
                numericChapter.group(2) ?? numericChapter.group(4) ?? '',
            );
            if (_isEventOrdinal(
                numericChapter.group(1)!,
                numericChapter.group(5) ?? '',
            ))
            {
                chapterOrder = 800000;
            }
            hasChapterMarker = true;
            working = working.substring(0, numericChapter.start).trim();
        } else if (!hasChapterMarker)
        {
            final Match? chineseChapter = RegExp(
                r'((?:第\s*)?([零〇一二三四五六七八九十百两兩]+)\s*(?:话|話|章|回|节|節))(?:\s*[-—:：#]?\s*(.{1,48}))?\s*$',
                caseSensitive: false,
            ).firstMatch(working);
            final double? chineseOrder = chineseChapter == null
                    ? null
                    : _chineseChapterOrder(chineseChapter.group(2)!);
            if (chineseChapter != null && chineseOrder != null)
            {
                chapterLabel = _chapterLabel(
                    chineseChapter.group(1)!,
                    chineseChapter.group(3),
                );
                chapterOrder = chineseOrder;
                hasChapterMarker = true;
                working = working.substring(0, chineseChapter.start).trim();
            } else
            {
                final ({int start, String label, double order})? ordinal =
                        _legacyOrdinalChapter(working, allowed: authorMarker.isNotEmpty);
                if (ordinal != null)
                {
                    chapterLabel = ordinal.label;
                    chapterOrder = ordinal.order;
                    hasChapterMarker = true;
                    working = working.substring(0, ordinal.start).trim();
                } else
                {
                    final Match? bareChapter = RegExp(
                        r'^(.*?)(?:\s+|[_\-—#])'
                        r'(\d{1,4}(?:\.\d+)?)'
                        r'(\s*(?:'
                        r'[（(][^（）()]{1,40}[）)]|'
                        r'(?:前|后|後|上|中|下)\s*(?:篇|編)?'
                        r'(?:\s+[\u3040-\u30ff\u3400-\u9fff]\S.{0,46})?|'
                        r'part\s*\d+|'
                        r'[.．]\s*(?!\d)\S.{0,47}|'
                        r'[\-—:：&]\s*\S.{0,47}|'
                        r'\s+[\u3040-\u30ff\u3400-\u9fff]\S.{0,47}'
                        r'))?\s*$',
                        caseSensitive: false,
                    ).firstMatch(working);
                    if (bareChapter != null &&
                            _isBareChapter(bareChapter.group(1)!, bareChapter.group(2)!))
                    {
                        final String rawNote = bareChapter.group(3) ?? '';
                        final String note = normalizeForumText(rawNote);
                        chapterLabel = _bareChapterLabel(
                            bareChapter.group(2)!,
                            note,
                            attachedPart: RegExp(r'^(?:前|后|後|上|中|下)').hasMatch(rawNote),
                        );
                        chapterOrder = _bareChapterOrder(bareChapter.group(2)!, note);
                        hasChapterMarker = true;
                        working = bareChapter.group(1)!.trim();
                    } else
                    {
                        final Match? attachedChapter = RegExp(
                            r'^(.{2,}?)(\d{1,3}(?:\.\d+)?)'
                            r'(\s*(?:'
                            r'[（(][^（）()]{1,40}[）)]|'
                            r'(?:前|后|後|上|中|下)\s*(?:篇|編)?'
                            r'(?:\s+[\u3040-\u30ff\u3400-\u9fff]\S.{0,46})?|'
                            r'[.．]\s*(?!\d)\S.{0,47}|'
                            r'[\-—:：&]\s*\S.{0,47}|'
                            r'\s+[\u3040-\u30ff\u3400-\u9fff]\S.{0,47}'
                            r'))?\s*$',
                            caseSensitive: false,
                        ).firstMatch(working);
                        if (attachedChapter != null &&
                                _isAttachedChapter(
                                    attachedChapter.group(1)!,
                                    attachedChapter.group(2)!,
                                    authorMarker,
                                ))
                        {
                            final String note = normalizeForumText(
                                attachedChapter.group(3) ?? '',
                            );
                            chapterLabel = _bareChapterLabel(attachedChapter.group(2)!, note);
                            chapterOrder = _bareChapterOrder(attachedChapter.group(2)!, note);
                            hasChapterMarker = true;
                            working = attachedChapter.group(1)!.trim();
                        } else
                        {
                            final Match? splitChapter = RegExp(
                                r'^(.*?)[\s_\-—:：]+(上|中|下)(?:篇|部)?\s*$',
                            ).firstMatch(working);
                            if (splitChapter != null &&
                                    normalizeForumText(splitChapter.group(1)!).length >= 2)
                            {
                                chapterLabel = '${splitChapter.group(2)}篇';
                                chapterOrder = _splitChapterOrder(splitChapter.group(2)!);
                                hasChapterMarker = true;
                                working = splitChapter.group(1)!.trim();
                            } else
                            {
                                final Match? namedChapter = RegExp(
                                    r'(?:[<《【\[（(]\s*)?(最终话|最終話|终话|終話|终章|終章|最终回|最終回|最终囘|最終囘|番外(?:篇)?|特典|附录|附錄|卷彩页|卷彩頁)(?:\s*[>》】\]）)])?\s*$',
                                    caseSensitive: false,
                                ).firstMatch(working);
                                if (namedChapter != null)
                                {
                                    chapterLabel = namedChapter.group(1)!;
                                    chapterOrder = _namedChapterOrder(chapterLabel);
                                    hasChapterMarker = true;
                                    working = working.substring(0, namedChapter.start).trim();
                                }
                            }
                        }
                    }
                }
            }
        }

        String volumeTitle = '';
        double? volumeOrder;
        final bool hadChapterBeforeVolume = hasChapterMarker;
        final Match? volume = RegExp(
            r'((?:第\s*)?([零〇一二三四五六七八九十百两兩\d]+)\s*卷|vol(?:ume)?\.?\s*(\d+))(?:\s*[-—:：#]?\s*(.{1,48}))?\s*$',
            caseSensitive: false,
        ).firstMatch(working);
        if (volume != null)
        {
            volumeOrder = _numberOrder(volume.group(2) ?? volume.group(3) ?? '');
            if (volumeOrder != null)
            {
                volumeTitle = normalizeForumText(volume.group(1)!);
                final String subtitle = normalizeForumText(volume.group(4) ?? '');
                if (hasChapterMarker)
                {
                    chapterLabel = '$volumeTitle $chapterLabel';
                    chapterOrder = volumeOrder * 10000 + (chapterOrder ?? 0);
                } else
                {
                    chapterLabel = subtitle.isEmpty
                            ? volumeTitle
                            : '$volumeTitle $subtitle';
                    chapterOrder = volumeOrder * 10000;
                    hasChapterMarker = true;
                }
                working = working.substring(0, volume.start).trim();
                if (!hadChapterBeforeVolume && novelEdition == null)
                {
                    novelEdition = NovelEdition.book;
                }
            }
        }

        working = working.replaceAll(RegExp(r'[\s\-_:：|/\\—–]+$'), '');
        final String displayTitle = working.isEmpty ? normalizedOriginal : working;
        final String detectedVersion = _extractVersionMarker(displayTitle);
        final String versionMarker = detectedVersion.isNotEmpty
                ? detectedVersion
                : novelEdition?.label ?? '';
        final String keyBase = _keyText(displayTitle);
        final String strippedNovelTitle = _stripNovelEditionMarkers(displayTitle);
        final String novelDisplayTitle = strippedNovelTitle.isEmpty
                ? displayTitle
                : strippedNovelTitle;
        final String novelTitleKey = _keyText(novelDisplayTitle);
        final String workKey = <String>[
            keyBase,
            if (authorMarker.isNotEmpty) 'author=$authorMarker',
            if (versionMarker.isNotEmpty) 'version=${_keyText(versionMarker)}',
        ].join('|');

        return StructuredTitle(
            original: normalizedOriginal,
            displayTitle: displayTitle,
            titleKey: keyBase,
            creatorKey: authorMarker,
            workKey: workKey,
            chapterLabel: chapterLabel,
            chapterOrder: chapterOrder,
            versionMarker: versionMarker,
            hasChapterMarker: hasChapterMarker && keyBase.length >= 2,
            novelDisplayTitle: novelDisplayTitle,
            novelTitleKey: novelTitleKey,
            novelEdition: novelEdition,
            volumeTitle: volumeTitle,
            volumeOrder: volumeOrder,
        );
    }

    NovelEdition? _explicitNovelEdition(String value)
    {
        if (RegExp(
            r'(web\s*版?|网络(?:连载|連載)?版?|網路(?:連載)?版?|正式\s*(?:连载|連載)\s*版|连载版|連載版)',
            caseSensitive: false,
        ).hasMatch(value))
        {
            return NovelEdition.serial;
        }
        if (RegExp(
            r'((?:文库|文庫)(?:版)?|书籍版|書籍版|实体版|實體版|[\[【（(]\s*(?:单行本|單行本)(?:版)?\s*[\]】）)])',
            caseSensitive: false,
        ).hasMatch(value))
        {
            return NovelEdition.book;
        }
        return null;
    }

    String _stripTrailingContinuationNote(String value)
    {
        return value
                .replaceFirst(
                    RegExp(
                        r'\s*[（(][^（）()]{0,40}(?:另?开(?:坑|帖)|另開(?:坑|帖)|新帖|新貼|见新帖|見新帖|移步)[^（）()]{0,40}[）)]\s*$',
                        caseSensitive: false,
                    ),
                    '',
                )
                .trim();
    }

    String _unwrapTrailingVolumeMarker(String value)
    {
        return value.replaceFirstMapped(
            RegExp(
                r'[\[【（(]\s*((?:第\s*)?[零〇一二三四五六七八九十百两兩\d]+\s*卷|vol(?:ume)?\.?\s*\d+)\s*[\]】）)]\s*$',
                caseSensitive: false,
            ),
            (Match match) => match.group(1)!,
        );
    }

    String _stripNovelEditionMarkers(String value)
    {
        return normalizeForumText(
            value.replaceAll(
                RegExp(
                    r'(?:[\[【（(]\s*)?(?:web\s*版?|网络(?:连载|連載)?版?|網路(?:連載)?版?|正式\s*(?:连载|連載)\s*版|连载版|連載版|(?:文库|文庫)(?:版)?|单行本|單行本|书籍版|書籍版|实体版|實體版)(?:\s*[\]】）)])?',
                    caseSensitive: false,
                ),
                ' ',
            ),
        ).replaceAll(RegExp(r'^[\s\-_:：|/\\—–]+|[\s\-_:：|/\\—–]+$'), '');
    }

    String _stripTrailingReleaseMetadata(String value)
    {
        final RegExp bracket = RegExp(
            r'\s*(?:\[([^\]]{1,60})\]|【([^】]{1,60})】|[（(]([^（）()]{1,60})[）)])\s*$',
        );
        String working = value;
        while (true)
        {
            final Match? match = bracket.firstMatch(working);
            if (match == null ||
                    !_isTrailingReleaseMetadata(_metadataMarker(match)))
            {
                break;
            }
            working = working.substring(0, match.start).trim();
        }
        return working;
    }

    bool _isTrailingReleaseMetadata(String value)
    {
        final String marker = normalizeForumText(_toHalfWidth(value));
        return RegExp(
            r'^(?:(?:日|中|英|韩|韓|泰)\s*翻(?:译|譯)?'
            r'(?:\s*/\s*(?:简|簡|繁)(?:体|體)?)?|'
            r'(?:简|簡|繁)(?:体|體)?\s*/\s*'
            r'(?:日|中|英|韩|韓|泰)\s*翻(?:译|譯)?|'
            r'更新(?:至|到)?(?:\s.*|[:：#].*|\d.*)?|'
            r'(?:请|請)看(?:一|1)(?:楼|樓).*|'
            r'(?:严禁|嚴禁|禁止).*(?:传播|傳播|转载|轉載|资源|資源))$',
            caseSensitive: false,
        ).hasMatch(marker);
    }

    ({String title, String authorMarker}) _stripLeadingMetadata(String value)
    {
        final RegExp bracket = RegExp(
            r'^\s*(?:\[([^\]]{1,40})\]|【([^】]{1,40})】|[（(]([^（）()]{1,40})[）)])\s*',
        );
        final Match? first = bracket.firstMatch(value);
        if (first == null)
        {
            return (title: value, authorMarker: '');
        }
        final String remainder = value.substring(first.end).trim();
        final bool hasSecond = bracket.hasMatch(remainder);
        final String firstMarker = _metadataMarker(first);
        final bool hasOwnTitle = _hasOwnTitleBeforeChapter(remainder);
        if (!_isReleaseTag(firstMarker) &&
                !_isCreatorMarker(firstMarker) &&
                !hasSecond &&
                !_isWrappedWorkTitle(firstMarker, remainder) &&
                !hasOwnTitle)
        {
            return (title: value, authorMarker: '');
        }

        String working = value;
        String authorMarker = '';
        while (true)
        {
            final Match? match = bracket.firstMatch(working);
            if (match == null)
            {
                break;
            }
            final String marker = _metadataMarker(match);
            final String remainder = working.substring(match.end).trim();
            if (_isWrappedWorkTitle(marker, remainder))
            {
                working = '$marker $remainder'.trim();
                break;
            }
            if (_isCreatorMarker(marker))
            {
                authorMarker = _creatorKey(marker);
            } else if (!_isReleaseTag(marker) && !bracket.hasMatch(remainder))
            {
                authorMarker = _keyText(marker);
            } else if (!_isReleaseTag(marker))
            {
                final Match? next = bracket.firstMatch(remainder);
                if (next != null &&
                        _isWrappedWorkTitle(
                            _metadataMarker(next),
                            remainder.substring(next.end).trim(),
                        ))
                {
                    authorMarker = _keyText(marker);
                }
            }
            working = remainder;
        }
        return (title: working, authorMarker: authorMarker);
    }

    bool _isWrappedWorkTitle(String marker, String remainder)
    {
        if (_isStandaloneReleaseTag(marker) ||
                _isCreatorMarker(marker) ||
                _keyText(marker).length < 2)
        {
            return false;
        }
        final String suffix = _stripCompletionMarker(
            _stripTrailingReleaseMetadata(remainder),
        );
        return RegExp(
            r'^(?:0*[1-9]\d?|'
            r'(?:第\s*)?[零〇一二三四五六七八九十百两兩\d]+(?:\.\d+)?'
            r'(?:\s*(?:-|~|～|—|–|至)\s*(?:第\s*)?\d+(?:\.\d+)?)?'
            r'\s*(?:话|話|章|回|节|節)(?:\s*[-—:：#]?\s*.{1,48})?|'
            r'(?:第\s*)?[零〇一二三四五六七八九十百两兩\d]+\s*卷|'
            r'vol(?:ume)?\.?\s*\d+)\s*$',
            caseSensitive: false,
        ).hasMatch(suffix);
    }

    bool _hasOwnTitleBeforeChapter(String value)
    {
        final String normalized = normalizeForumText(_toHalfWidth(value));
        final StructuredTitle title = analyze(normalized);
        return title.hasChapterMarker &&
                title.displayTitle != normalized &&
                title.titleKey.length >= 2;
    }

    bool _isStandaloneReleaseTag(String value)
    {
        return RegExp(
            r'^(?:汉化|漢化|翻译|翻譯|自翻|个人|個人|授权|授權|'
            r'转载|轉載|搬运|搬運|生肉|熟肉|漫画|漫畫|小说|小說|'
            r'轻小说|輕小說|短篇|连载|連載|web|文库|文庫|'
            r'单行本|單行本|完结|完結|更新|無銘|无铭)$',
            caseSensitive: false,
        ).hasMatch(normalizeForumText(value).trim());
    }

    String _metadataMarker(Match match)
    {
        return match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
    }

    String _stripCompletionMarker(String value)
    {
        return value
                .replaceFirst(
                    RegExp(
                        r'\s*(?:(?:[\[【<（(]\s*)?(?:完|完结|完結|end)(?:\s*[\]】>）)])?)\s*$',
                        caseSensitive: false,
                    ),
                    '',
                )
                .trim();
    }

    String _chapterLabel(String marker, String? subtitle)
    {
        final String normalizedMarker = normalizeForumText(marker);
        final String normalizedSubtitle = normalizeForumText(subtitle ?? '');
        return normalizedSubtitle.isEmpty
                ? normalizedMarker
                : '$normalizedMarker $normalizedSubtitle';
    }

    bool _isEventOrdinal(String marker, String subtitle)
    {
        if (!RegExp(r'(?:回|囘)\s*$', caseSensitive: false).hasMatch(marker))
        {
            return false;
        }
        return RegExp(
            r'(漫画祭|漫畫祭|祭り|小册|小冊|特典|活动|活動|纪念|紀念|展|フェア)',
            caseSensitive: false,
        ).hasMatch(subtitle);
    }

    ({int start, String label, double order})? _legacyOrdinalChapter(
        String value,
        {
        required bool allowed,
    })
    {
        if (!allowed)
        {
            return null;
        }
        final Match? match = RegExp(
            r'之([零〇一二三四五六七八九十百两兩]+(?:[、,，][零〇一二三四五六七八九十百两兩]+)*)\s*$',
        ).firstMatch(value);
        if (match == null)
        {
            return null;
        }
        final List<double?> orders = match
                .group(1)!
                .split(RegExp(r'[、,，]'))
                .map(_chineseChapterOrder)
                .toList(growable: false);
        if (orders.any((double? order) => order == null))
        {
            return null;
        }
        final List<int> numbers = orders
                .cast<double>()
                .map((double order) => order.toInt())
                .toList(growable: false);
        return (
            start: match.start,
            label: '第${numbers.join('、')}话',
            order: orders.first!,
        );
    }

    bool _isBareChapter(String base, String number)
    {
        if (RegExp(
            r'(?:^|\s)p\.?\s*\d+\s*$',
            caseSensitive: false,
        ).hasMatch(base))
        {
            return false;
        }
        final int? integer = int.tryParse(number);
        if (!number.contains('.') &&
                number.length == 4 &&
                integer != null &&
                integer >= 1900 &&
                integer <= 2099)
        {
            return false;
        }
        return !RegExp(r'vol(?:ume)?\.?\s*$', caseSensitive: false).hasMatch(base);
    }

    bool _isAttachedChapter(String base, String number, String authorMarker)
    {
        final String normalizedBase = normalizeForumText(base);
        if (normalizedBase.isEmpty || RegExp(r'\d$').hasMatch(normalizedBase))
        {
            return false;
        }
        if (RegExp(
            r'(?:^|\s)p\.?\s*(?:\d+\s*[-—]\s*)?$',
            caseSensitive: false,
        ).hasMatch(normalizedBase))
        {
            return false;
        }
        if (number.length > 1 && number.startsWith('0'))
        {
            return true;
        }
        if (RegExp(r'[\)\]】》」』!?！？~～]$').hasMatch(normalizedBase))
        {
            return true;
        }
        if (normalizedBase.length <= 30 && authorMarker.isNotEmpty)
        {
            return true;
        }
        return normalizedBase.length <= 30 &&
                RegExp(r'[぀-ヿ㐀-鿿]$').hasMatch(normalizedBase);
    }

    double? _numberOrder(String value)
    {
        return double.tryParse(value) ?? _chineseChapterOrder(value);
    }

    double? _bareChapterOrder(String number, String note)
    {
        final double? order = double.tryParse(number);
        if (order == null)
        {
            return null;
        }
        int? part = int.tryParse(
            RegExp(r'^[（(]\s*(\d+)\s*[）)]$').firstMatch(note)?.group(1) ?? '',
        );
        part ??= int.tryParse(
            RegExp(
                        r'^part\s*(\d+)$',
                        caseSensitive: false,
                    ).firstMatch(note)?.group(1) ??
                    '',
        );
        if (part == null && RegExp(r'^(前|上)\s*(?:篇|編)?(?:\s|$)').hasMatch(note))
        {
            part = 1;
        } else if (part == null &&
                RegExp(r'^中\s*(?:篇|編)?(?:\s|$)').hasMatch(note))
        {
            part = 2;
        } else if (part == null &&
                RegExp(r'^(后|後|下)\s*(?:篇|編)?(?:\s|$)').hasMatch(note))
        {
            part = 3;
        }
        return part == null ? order : order + part / 1000;
    }

    String _bareChapterLabel(
        String number,
        String note,
        {
        bool attachedPart = false,
    })
    {
        final String subtitle = note
                .replaceFirst(RegExp(r'^[.．\-—:：&]\s*'), '')
                .trim();
        if (subtitle.isEmpty)
        {
            return number;
        }
        final Match? split = RegExp(
            r'^(前|后|後|上|中|下)\s*(篇|編)?(?:\s+(.*))?$',
        ).firstMatch(subtitle);
        if (split != null && attachedPart)
        {
            final String marker = '${split.group(1)}${split.group(2) ?? ''}';
            final String suffix = split.group(3)?.trim() ?? '';
            return suffix.isEmpty ? '$number$marker' : '$number$marker $suffix';
        }
        return subtitle.startsWith('(') ||
                        subtitle.startsWith('（') ||
                        RegExp(r'^(前|后|後|上|中|下)$').hasMatch(subtitle)
                ? '$number$subtitle'
                : '$number $subtitle';
    }

    double? _chineseChapterOrder(String value)
    {
        const Map<String, int> digits = <String, int>{
            '零': 0,
            '〇': 0,
            '一': 1,
            '二': 2,
            '两': 2,
            '兩': 2,
            '三': 3,
            '四': 4,
            '五': 5,
            '六': 6,
            '七': 7,
            '八': 8,
            '九': 9,
        };
        int total = 0;
        int current = 0;
        for (final String character in value.split(''))
        {
            if (character == '十' || character == '百')
            {
                final int unit = character == '十' ? 10 : 100;
                total += (current == 0 ? 1 : current) * unit;
                current = 0;
                continue;
            }
            final int? digit = digits[character];
            if (digit == null)
            {
                return null;
            }
            current = current * 10 + digit;
        }
        return (total + current).toDouble();
    }

    bool _isReleaseTag(String value)
    {
        return RegExp(
            r'(汉化|漢化|翻译|翻譯|自翻|个人|個人|授权|授權|转载|轉載|搬运|搬運|生肉|熟肉|漫画|漫畫|小说|小說|轻小说|輕小說|短篇|连载|連載|web|文库|文庫|单行本|單行本|完结|完結|更新|無銘|无铭)',
            caseSensitive: false,
        ).hasMatch(value);
    }

    bool _isCreatorMarker(String value)
    {
        return RegExp(
            r'(?:原作|漫画|漫畫|作画|作畫|绘师|繪師|脚本|劇本|剧本)\s*[:：]',
            caseSensitive: false,
        ).hasMatch(value);
    }

    String _creatorKey(String value)
    {
        final List<String> names =
                normalizeForumText(_toHalfWidth(value))
                        .split(RegExp(r'[×xX/&＆]'))
                        .map((String part)
            {
                            return _keyText(
                                part.replaceFirst(
                                    RegExp(
                                        r'^\s*(?:原作|漫画|漫畫|作画|作畫|绘师|繪師|脚本|劇本|剧本)\s*[:：]\s*',
                                        caseSensitive: false,
                                    ),
                                    '',
                                ),
                            );
                        })
                        .where((String name) => name.isNotEmpty)
                        .toList(growable: true)
                    ..sort();
        return names.join('+');
    }

    bool _looksLikeVersionOrUpdate(String value)
    {
        return RegExp(
            r'(更新|第\s*\d+\s*(部|季)|web|单行本|單行本|连载版|連載版)',
            caseSensitive: false,
        ).hasMatch(value);
    }

    String _extractVersionMarker(String value)
    {
        final Iterable<Match> matches = RegExp(
            r'(第\s*[一二三四五六七八九十0-9]+\s*部|第\s*[一二三四五六七八九十0-9]+\s*季|web\s*版?|正式\s*(?:连载|連載)\s*版|单行本|單行本)',
            caseSensitive: false,
        ).allMatches(value);
        return matches.map((Match match) => match.group(1)!).join(' ');
    }

    double _namedChapterOrder(String value)
    {
        if (RegExp(r'(最终|最終|终话|終話|终章|終章)').hasMatch(value))
        {
            return 1000000;
        }
        if (value.contains('番外'))
        {
            return 900000;
        }
        return 800000;
    }

    double _splitChapterOrder(String value)
    {
        return switch (value)
        {
            '上' => 700001,
            '中' => 700002,
            _ => 700003,
        };
    }

    String _keyText(String value)
    {
        return _toHalfWidth(value)
                .toLowerCase()
                .replaceAll('+', ' plus ')
                .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');
    }

    String _toHalfWidth(String value)
    {
        final StringBuffer result = StringBuffer();
        for (final int rune in value.runes)
        {
            if (rune == 0x3000)
            {
                result.write(' ');
            } else if (rune >= 0xff01 && rune <= 0xff5e)
            {
                result.writeCharCode(rune - 0xfee0);
            } else
            {
                result.writeCharCode(rune);
            }
        }
        return result.toString();
    }
}
