import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:x300/core/network/forum_client.dart';

final Provider<ReaderMediaRepository> readerMediaRepositoryProvider =
        Provider<ReaderMediaRepository>(
            (Ref ref) => ReaderMediaRepository(
                ref.watch(forumClientProvider),
            ),
        );

typedef ReaderMediaCacheDirectory = Future<Directory> Function();

class ReaderMediaRepository
{
    static const int defaultMaximumCacheBytes = 1024 * 1024 * 1024;
    static const int defaultTargetCacheBytes = 512 * 1024 * 1024;

    ReaderMediaRepository(
        this._client, {
        ReaderMediaCacheDirectory? cacheDirectory,
        this.maximumCacheBytes = defaultMaximumCacheBytes,
        this.targetCacheBytes = defaultTargetCacheBytes,
        DateTime Function()? now,
    })  : assert(targetCacheBytes < maximumCacheBytes),
          _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory,
          _now = now ?? DateTime.now;

    final ForumClient _client;
    final ReaderMediaCacheDirectory _cacheDirectory;
    final int maximumCacheBytes;
    final int targetCacheBytes;
    final DateTime Function() _now;
    final Map<String, Uri> _memory = <String, Uri>{};
    final Map<String, Future<Uri>> _pending = <String, Future<Uri>>{};
    int _generation = 0;
    int? _cachedSizeBytes;

    Uri? peek(Uri source)
    {
        return source.scheme == 'file' ? source : _memory[_key(source)];
    }

    Future<Uri> resolve(Uri source, {required String referer})
    {
        if (source.scheme == 'file')
        {
            return Future<Uri>.value(source);
        }
        final String key = _key(source);
        final Uri? cached = _memory[key];
        if (cached != null)
        {
            return Future<Uri>.value(cached);
        }
        final Future<Uri>? pending = _pending[key];
        if (pending != null)
        {
            return pending;
        }
        late final Future<Uri> future;
        final int generation = _generation;
        future = _resolve(
            source,
            referer: referer,
            generation: generation,
        ).whenComplete(()
        {
            if (identical(_pending[key], future))
            {
                _pending.remove(key);
            }
        });
        _pending[key] = future;
        return future;
    }

    Future<void> evict(Uri source) async
    {
        if (source.scheme == 'file')
        {
            return;
        }
        _memory.remove(_key(source));
        final File file = await _fileFor(source);
        if (await file.exists())
        {
            await file.delete();
            _cachedSizeBytes = null;
        }
    }

    Future<void> clear() async
    {
        _generation++;
        _memory.clear();
        final Directory root = await _root();
        if (await root.exists())
        {
            await root.delete(recursive: true);
        }
        _cachedSizeBytes = 0;
    }

    Future<void> maintainCache() async
    {
        final Directory root = await _root();
        if (!await root.exists())
        {
            _cachedSizeBytes = 0;
            return;
        }
        final DateTime stalePartialBefore = _now().subtract(
            const Duration(days: 1),
        );
        final Set<String> pendingKeys = _pending.keys.toSet();
        final List<_ReaderMediaFile> files = <_ReaderMediaFile>[];
        int totalBytes = 0;
        await for (final FileSystemEntity entity in root.list())
        {
            if (entity is! File)
            {
                continue;
            }
            try
            {
                final FileStat stat = await entity.stat();
                final String name = path.basename(entity.path);
                final bool pending = name.length >= 64 &&
                        pendingKeys.contains(name.substring(0, 64));
                if (name.endsWith('.part'))
                {
                    if (!pending && stat.modified.isBefore(stalePartialBefore))
                    {
                        await entity.delete();
                    }
                    continue;
                }
                if (stat.size <= 0)
                {
                    if (!pending)
                    {
                        await entity.delete();
                        _forget(entity.path);
                    }
                    continue;
                }
                totalBytes += stat.size;
                files.add(_ReaderMediaFile(
                    file: entity,
                    size: stat.size,
                    modifiedAt: stat.modified,
                    pending: pending,
                ));
            }
            on FileSystemException
            {
                continue;
            }
        }
        if (totalBytes <= maximumCacheBytes)
        {
            _cachedSizeBytes = totalBytes;
            return;
        }
        files.sort(
            (_ReaderMediaFile left, _ReaderMediaFile right) =>
                left.modifiedAt.compareTo(right.modifiedAt),
        );
        for (final _ReaderMediaFile entry in files)
        {
            if (totalBytes <= targetCacheBytes)
            {
                break;
            }
            if (entry.pending)
            {
                continue;
            }
            try
            {
                await entry.file.delete();
                totalBytes -= entry.size;
                _forget(entry.file.path);
            }
            on FileSystemException
            {
                continue;
            }
        }
        _cachedSizeBytes = totalBytes;
    }

    Future<int> cacheSizeBytes() async
    {
        final int? cached = _cachedSizeBytes;
        if (cached != null)
        {
            return cached;
        }
        final Directory root = await _root();
        if (!await root.exists())
        {
            _cachedSizeBytes = 0;
            return 0;
        }
        int totalBytes = 0;
        await for (final FileSystemEntity entity in root.list())
        {
            if (entity is! File)
            {
                continue;
            }
            try
            {
                totalBytes += await entity.length();
            }
            on FileSystemException
            {
                continue;
            }
        }
        _cachedSizeBytes = totalBytes;
        return totalBytes;
    }

    Future<Uri> _resolve(
        Uri source, {
        required String referer,
        required int generation,
    }) async
    {
        final File target = await _fileFor(source);
        final FileStat cachedStat = await target.stat();
        if (cachedStat.type == FileSystemEntityType.file && cachedStat.size > 0)
        {
            await _touchIfStale(target, cachedStat.modified);
            return _remember(source, target.uri);
        }
        final Uint8List bytes = await _client.getBytes(
            source,
            referer: referer,
        );
        if (bytes.isEmpty)
        {
            throw StateError('论坛图片内容为空');
        }
        if (generation != _generation)
        {
            throw StateError('图片缓存已清理');
        }
        await target.parent.create(recursive: true);
        final File partial = File('${target.path}.part');
        await partial.writeAsBytes(bytes, flush: true);
        if (generation != _generation)
        {
            await partial.delete();
            throw StateError('图片缓存已清理');
        }
        if (await target.exists())
        {
            await partial.delete();
        } else
        {
            await partial.rename(target.path);
            _cachedSizeBytes = null;
        }
        return _remember(source, target.uri);
    }

    Uri _remember(Uri source, Uri cached)
    {
        _memory[_key(source)] = cached;
        return cached;
    }

    void _forget(String filePath)
    {
        _memory.removeWhere(
            (String _, Uri cached) =>
                cached.scheme == 'file' && cached.toFilePath() == filePath,
        );
    }

    Future<void> _touchIfStale(File file, DateTime modifiedAt) async
    {
        try
        {
            final DateTime now = _now();
            if (now.difference(modifiedAt) >= const Duration(days: 1))
            {
                await file.setLastModified(now);
            }
        }
        on FileSystemException
        {
            return;
        }
    }

    Future<Directory> _root() async
    {
        return Directory(
            path.join((await _cacheDirectory()).path, 'reader_media'),
        );
    }

    Future<File> _fileFor(Uri source) async
    {
        final Directory root = await _root();
        return File(
            path.join(
                root.path,
                '${_key(source)}${_safeExtension(source)}',
            ),
        );
    }

    String _key(Uri source)
    {
        return sha256.convert(source.toString().codeUnits).toString();
    }

    String _safeExtension(Uri source)
    {
        final String extension = path.extension(source.path).toLowerCase();
        return const <String>{'.jpg', '.jpeg', '.png', '.webp', '.gif'}
                .contains(extension)
                ? extension
                : '.img';
    }
}

class _ReaderMediaFile
{
    const _ReaderMediaFile({
        required this.file,
        required this.size,
        required this.modifiedAt,
        required this.pending,
    });

    final File file;
    final int size;
    final DateTime modifiedAt;
    final bool pending;
}
