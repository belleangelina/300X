import 'dart:convert';

import 'package:x300/features/library/domain/library_models.dart';

class WorkCodec
{
    const WorkCodec();

    String encode(Work work)
    {
        return _encode(work, includeSummaries: true);
    }

    String encodeIndex(Work work)
    {
        return _encode(work, includeSummaries: false);
    }

    String _encode(Work work, {required bool includeSummaries})
    {
        return jsonEncode(<String, Object?>{
            'id': work.id,
            'kind': work.kind.name,
            'title': work.title,
            'summary': includeSummaries ? work.summary : '',
            'author': work.author,
            'typeName': work.typeName,
            'sourceThreads': work.sourceThreads
                    .map(
                        (SourceThread thread) =>
                                _encodeSourceThread(thread, includeSummary: includeSummaries),
                    )
                .toList(growable: false),
            'chapters': work.chapters.map(_encodeChapter).toList(growable: false),
            'directories': work.directories
                    .map(_encodeDirectory)
                .toList(growable: false),
        });
    }

    Work decode(String value)
    {
        final Object? decoded = jsonDecode(value);
        if (decoded is! Map<String, dynamic>)
        {
            throw const FormatException('作品缓存格式无效');
        }
        final List<SourceThread> sourceThreads = _list(
            decoded['sourceThreads'],
        ).map(_decodeSourceThread).toList(growable: false);
        final List<Chapter> chapters = _list(
            decoded['chapters'],
        ).map(_decodeChapter).toList(growable: false);
        final List<WorkDirectory> directories = _list(
            decoded['directories'],
        ).map(_decodeDirectory).toList(growable: false);
        if (sourceThreads.isEmpty || chapters.isEmpty)
        {
            throw const FormatException('作品缓存缺少来源或章节');
        }
        return Work(
            id: _string(decoded['id']),
            kind: LibraryKind.values.byName(_string(decoded['kind'])),
            title: _string(decoded['title']),
            summary: _string(decoded['summary']),
            author: _string(decoded['author']),
            typeName: _string(decoded['typeName']),
            sourceThreads: sourceThreads,
            chapters: chapters,
            directories: directories,
        );
    }

    String encodeChapter(Chapter chapter)
    {
        return jsonEncode(_encodeChapter(chapter));
    }

    Chapter decodeChapter(String value)
    {
        final Object? decoded = jsonDecode(value);
        if (decoded is! Map<String, dynamic>)
        {
            throw const FormatException('章节缓存格式无效');
        }
        return _decodeChapter(decoded);
    }

    Map<String, Object?> _encodeSourceThread(
        SourceThread thread, {
        required bool includeSummary,
    })
    {
        return <String, Object?>{
            'tid': thread.tid,
            'board': thread.board.name,
            'typeId': thread.typeId,
            'typeName': thread.typeName,
            'title': thread.title,
            'summary': includeSummary ? thread.summary : '',
            'author': thread.author,
            'avatarUri': thread.avatarUri?.toString(),
            'timeLabel': thread.timeLabel,
            'postedAt': thread.postedAt?.toIso8601String(),
            'views': thread.views,
            'replies': thread.replies,
            'pinned': thread.pinned,
            'administrative': thread.administrative,
            'uri': thread.uri.toString(),
        };
    }

    SourceThread _decodeSourceThread(Map<String, dynamic> value)
    {
        final String avatarUri = _string(value['avatarUri']);
        final String postedAt = _string(value['postedAt']);
        return SourceThread(
            tid: _integer(value['tid']),
            board: ForumBoard.values.byName(_string(value['board'])),
            typeId: _nullableInteger(value['typeId']),
            typeName: _string(value['typeName']),
            title: _string(value['title']),
            summary: _string(value['summary']),
            author: _string(value['author']),
            avatarUri: avatarUri.isEmpty ? null : Uri.parse(avatarUri),
            timeLabel: _string(value['timeLabel']),
            postedAt: postedAt.isEmpty ? null : DateTime.parse(postedAt),
            views: _integer(value['views']),
            replies: _integer(value['replies']),
            pinned: value['pinned'] == true,
            administrative: value['administrative'] == true,
            uri: Uri.parse(_string(value['uri'])),
        );
    }

    Map<String, Object?> _encodeChapter(Chapter chapter)
    {
        return <String, Object?>{
            'id': chapter.id,
            'title': chapter.title,
            'sourceUri': chapter.sourceUri.toString(),
            'sourceTid': chapter.sourceTid,
            'sourcePid': chapter.sourcePid,
            'sourceEndPid': chapter.sourceEndPid,
            'sourceStartBlock': chapter.sourceStartBlock,
            'sourceEndBlock': chapter.sourceEndBlock,
            'order': chapter.order,
            'novelEdition': chapter.novelEdition?.name,
            'volumeTitle': chapter.volumeTitle,
            'volumeOrder': chapter.volumeOrder,
        };
    }

    Chapter _decodeChapter(Map<String, dynamic> value)
    {
        return Chapter(
            id: _string(value['id']),
            title: _string(value['title']),
            sourceUri: Uri.parse(_string(value['sourceUri'])),
            sourceTid: _integer(value['sourceTid']),
            sourcePid: _nullableInteger(value['sourcePid']),
            sourceEndPid: _nullableInteger(value['sourceEndPid']),
            sourceStartBlock: _nullableInteger(value['sourceStartBlock']),
            sourceEndBlock: _nullableInteger(value['sourceEndBlock']),
            order: _nullableDouble(value['order']),
            novelEdition: _novelEdition(value['novelEdition']),
            volumeTitle: _string(value['volumeTitle']),
            volumeOrder: _nullableDouble(value['volumeOrder']),
        );
    }

    NovelEdition? _novelEdition(Object? value)
    {
        final String name = _string(value);
        return name.isEmpty ? null : NovelEdition.values.byName(name);
    }

    Map<String, Object?> _encodeDirectory(WorkDirectory directory)
    {
        return <String, Object?>{
            'id': directory.id,
            'owner': directory.owner,
            'sourceTids': directory.sourceTids,
            'chapters': directory.chapters
                    .map(_encodeChapter)
                    .toList(growable: false),
        };
    }

    WorkDirectory _decodeDirectory(Map<String, dynamic> value)
    {
        final List<int> sourceTids = value['sourceTids'] is List<dynamic>
                ? (value['sourceTids'] as List<dynamic>)
                            .map(_integer)
                            .toList(growable: false)
                : const <int>[];
        return WorkDirectory(
            id: _string(value['id']),
            owner: _string(value['owner']),
            sourceTids: sourceTids,
            chapters: _list(
                value['chapters'],
            ).map(_decodeChapter).toList(growable: false),
        );
    }

    List<Map<String, dynamic>> _list(Object? value)
    {
        if (value is! List<dynamic>)
        {
            return const <Map<String, dynamic>>[];
        }
        return value.whereType<Map<String, dynamic>>().toList(growable: false);
    }

    String _string(Object? value)
    {
        return value?.toString() ?? '';
    }

    int _integer(Object? value)
    {
        return value is int ? value : int.parse(_string(value));
    }

    int? _nullableInteger(Object? value)
    {
        if (value == null)
        {
            return null;
        }
        return value is int ? value : int.tryParse(_string(value));
    }

    double? _nullableDouble(Object? value)
    {
        if (value == null)
        {
            return null;
        }
        return value is num ? value.toDouble() : double.tryParse(_string(value));
    }
}
