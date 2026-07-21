import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/downloads/data/download_repository.dart';
import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/library/data/chapter_content_selector.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';

final Provider<DownloadManager> downloadManagerProvider =
        Provider<DownloadManager>((Ref ref)
        {
            final DownloadManager manager = DownloadManager(
                ref.watch(downloadRepositoryProvider),
                ref.watch(forumLibraryRepositoryProvider),
                ref.watch(forumClientProvider),
                ref.watch(appSettingsRepositoryProvider),
            );
            ref.onDispose(manager.dispose);
            return manager;
        });

class DownloadManager
{
    DownloadManager(
        this._repository,
        this._libraryRepository,
        this._client,
        this._settingsRepository,
    );

    final DownloadRepository _repository;
    final ForumLibraryRepository _libraryRepository;
    final ForumClient _client;
    final AppSettingsRepository _settingsRepository;
    static const ChapterContentSelector _contentSelector =
        ChapterContentSelector();
    final Set<String> _pausedIds = <String>{};
    final Set<String> _deletedIds = <String>{};
    final Map<String, LibraryKind> _activeTasks = <String, LibraryKind>{};

    bool _started = false;
    bool _scheduling = false;
    bool _rescheduleRequested = false;
    bool _disposed = false;

    Future<void> start() async
    {
        if (_started)
        {
            return;
        }
        _started = true;
        await _repository.restoreInterrupted();
        _ensureProcessing();
    }

    Future<void> enqueue(Work work, List<Chapter> chapters) async
    {
        final Directory supportDirectory = await getApplicationSupportDirectory();
        for (final Chapter chapter in chapters)
        {
            final String digest = sha256
                    .convert(utf8.encode('${work.id}:${chapter.id}'))
                    .toString()
                    .substring(0, 24);
            final Directory directory = Directory(
                path.join(supportDirectory.path, 'downloads', digest),
            );
            await directory.create(recursive: true);
            await _repository.enqueue(
                work: work,
                chapter: chapter,
                directoryPath: directory.path,
            );
        }
        _ensureProcessing();
    }

    Future<void> pause(String id) async
    {
        _pausedIds.add(id);
        await _repository.setStatus(id, DownloadStatus.paused);
    }

    Future<void> resume(String id) async
    {
        _pausedIds.remove(id);
        _deletedIds.remove(id);
        await _repository.setStatus(id, DownloadStatus.queued);
        _ensureProcessing();
    }

    Future<void> delete(DownloadTaskEntry task) async
    {
        _deletedIds.add(task.id);
        await _repository.delete(task.id);
        final Directory directory = Directory(task.directoryPath);
        if (await directory.exists())
        {
            await directory.delete(recursive: true);
        }
    }

    void dispose()
    {
        _disposed = true;
    }

    void refreshLimits()
    {
        _ensureProcessing();
    }

    void _ensureProcessing()
    {
        if (_disposed)
        {
            return;
        }
        if (_scheduling)
        {
            _rescheduleRequested = true;
            return;
        }
        _scheduling = true;
        unawaited(_scheduleQueue());
    }

    Future<void> _scheduleQueue() async
    {
        try
        {
            do
            {
                _rescheduleRequested = false;
                for (final LibraryKind kind in LibraryKind.values)
                {
                    final int maximum = _maximumTasks(kind);
                    while (!_disposed && _activeCount(kind) < maximum)
                    {
                        final DownloadTaskEntry? task = await _repository
                            .claimNextQueued(kind);
                        if (task == null)
                        {
                            break;
                        }
                        _activeTasks[task.id] = kind;
                        unawaited(_runDownload(task));
                    }
                }
            }
            while (_rescheduleRequested && !_disposed);
        }
        finally
        {
            _scheduling = false;
            if (_rescheduleRequested && !_disposed)
            {
                _ensureProcessing();
            }
        }
    }

    Future<void> _runDownload(DownloadTaskEntry task) async
    {
        try
        {
            await _download(task);
        }
        finally
        {
            _activeTasks.remove(task.id);
            _ensureProcessing();
        }
    }

    int _activeCount(LibraryKind kind)
    {
        return _activeTasks.values
            .where((LibraryKind value) => value == kind)
            .length;
    }

    int _maximumTasks(LibraryKind kind)
    {
        final settings = _settingsRepository.load();
        return kind == LibraryKind.comic
            ? settings.comicMaximumDownloads
            : settings.novelMaximumDownloads;
    }

    Future<void> _download(DownloadTaskEntry task) async
    {
        try
        {
            if (!await _networkAllowed())
            {
                await _repository.setStatus(
                    task.id,
                    DownloadStatus.paused,
                    errorMessage: '等待 Wi-Fi 网络',
                );
                return;
            }
            final ForumThreadPage page = await _libraryRepository.loadChapterPage(
                task.chapter,
                task.work.primaryBoard,
            );
            final List<PostContentBlock> selectedBlocks =
                _contentSelector.select(page, task.chapter);
            if (selectedBlocks.isEmpty)
            {
                throw const ForumParseException('章节中没有可下载的正文');
            }
            final List<PostContentBlock> sourceBlocks =
                    task.work.kind == LibraryKind.comic
                    ? selectedBlocks
                        .whereType<PostImageBlock>()
                        .toList(growable: false)
                    : selectedBlocks;
            if (sourceBlocks.isEmpty)
            {
                throw const ForumParseException('章节中没有可下载的内容');
            }
            await _repository.updateProgress(
                task.id,
                completedItems: 0,
                totalItems: sourceBlocks.length,
            );

            final List<PostContentBlock> localBlocks = <PostContentBlock>[];
            int completed = 0;
            for (int index = 0; index < sourceBlocks.length; index++)
            {
                _checkTaskState(task.id);
                final PostContentBlock block = sourceBlocks[index];
                if (block is PostTextBlock)
                {
                    localBlocks.add(block);
                }
                else if (block is PostImageBlock)
                {
                    final File file = File(
                        path.join(
                            task.directoryPath,
                            'image_${index.toString().padLeft(4, '0')}'
                            '${_extension(block.uri)}',
                        ),
                    );
                    if (!await file.exists() || await file.length() == 0)
                    {
                        final Uint8List bytes = await _downloadBytes(
                            block.uri,
                            page.uri.toString(),
                        );
                        _checkTaskState(task.id);
                        final File partial = File('${file.path}.part');
                        await partial.writeAsBytes(bytes, flush: true);
                        await partial.rename(file.path);
                    }
                    localBlocks.add(
                        PostImageBlock(uri: Uri.file(file.path), alt: block.alt),
                    );
                }
                completed++;
                await _repository.updateProgress(
                    task.id,
                    completedItems: completed,
                    totalItems: sourceBlocks.length,
                );
            }
            _checkTaskState(task.id);
            await _repository.complete(
                task.id,
                blocks: localBlocks,
                referer: page.uri,
            );
        }
        on _DownloadPaused
        {
            return;
        }
        on _DownloadDeleted
        {
            return;
        }
        on ForumSessionExpiredException
        {
            await _repository.setStatus(
                task.id,
                DownloadStatus.paused,
                errorMessage: '登录状态已失效，请重新登录后继续',
            );
        }
        on ForumException catch (error)
        {
            await _repository.setStatus(
                task.id,
                DownloadStatus.failed,
                errorMessage: error.message,
            );
        }
        on FileSystemException
        {
            await _repository.setStatus(
                task.id,
                DownloadStatus.failed,
                errorMessage: '无法写入本地文件，请检查存储空间',
            );
        }
        on Object
        {
            await _repository.setStatus(
                task.id,
                DownloadStatus.failed,
                errorMessage: '下载失败，请稍后重试',
            );
        }
    }

    Future<Uint8List> _downloadBytes(Uri uri, String referer) async
    {
        ForumConnectionException? lastError;
        for (int attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                return await _client.getBytes(uri, referer: referer);
            }
            on ForumConnectionException catch (error)
            {
                lastError = error;
                if (attempt < 2)
                {
                    await Future<void>.delayed(
                        Duration(milliseconds: 400 * (attempt + 1)),
                    );
                }
            }
        }
        throw lastError ?? const ForumConnectionException();
    }

    Future<bool> _networkAllowed() async
    {
        if (Platform.isLinux)
        {
            return true;
        }
        final SharedPreferences preferences = await SharedPreferences.getInstance();
        if (preferences.getBool(
                AppSettingsRepository.allowMobilePreference,
            ) ==
            true)
        {
            return true;
        }
        final List<ConnectivityResult> results = await Connectivity()
                .checkConnectivity();
        return results.contains(ConnectivityResult.wifi) ||
                results.contains(ConnectivityResult.ethernet);
    }

    void _checkTaskState(String id)
    {
        if (_deletedIds.contains(id))
        {
            throw const _DownloadDeleted();
        }
        if (_pausedIds.contains(id))
        {
            throw const _DownloadPaused();
        }
    }

    String _extension(Uri uri)
    {
        final String extension = path.extension(uri.path).toLowerCase();
        if (<String>{
            '.jpg',
            '.jpeg',
            '.png',
            '.gif',
            '.webp',
        }.contains(extension))
        {
            return extension;
        }
        return '.img';
    }
}

class _DownloadPaused implements Exception
{
    const _DownloadPaused();
}

class _DownloadDeleted implements Exception
{
    const _DownloadDeleted();
}
