import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/features/reader/data/reader_media_repository.dart';

class _MockForumClient extends Mock implements ForumClient
{
}

void main()
{
    late Directory directory;
    late _MockForumClient client;

    setUp(() async
    {
        directory = await Directory.systemTemp.createTemp(
            'page300_reader_media_test_',
        );
        client = _MockForumClient();
    });

    tearDown(() async
    {
        if (await directory.exists())
        {
            await directory.delete(recursive: true);
        }
    });

    test('在线图片落盘后新仓库实例也不重复请求', () async
    {
        final Uri source = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
        );
        when(
            () => client.getBytes(source, referer: 'thread'),
        ).thenAnswer((_) async => Uint8List.fromList(<int>[1, 2, 3]));
        final ReaderMediaRepository first = ReaderMediaRepository(
            client,
            cacheDirectory: () async => directory,
        );

        final Uri cached = await first.resolve(source, referer: 'thread');
        final ReaderMediaRepository second = ReaderMediaRepository(
            client,
            cacheDirectory: () async => directory,
        );
        final Uri restored = await second.resolve(source, referer: 'thread');

        expect(restored, cached);
        expect(await File.fromUri(cached).readAsBytes(), <int>[1, 2, 3]);
        verify(
            () => client.getBytes(source, referer: 'thread'),
        ).called(1);
    });

    test('同一图片并发请求复用一个下载任务', () async
    {
        final Uri source = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/page-2.jpg',
        );
        final Completer<Uint8List> response = Completer<Uint8List>();
        when(
            () => client.getBytes(source, referer: 'thread'),
        ).thenAnswer((_) => response.future);
        final ReaderMediaRepository repository = ReaderMediaRepository(
            client,
            cacheDirectory: () async => directory,
        );

        final Future<Uri> first = repository.resolve(source, referer: 'thread');
        final Future<Uri> second = repository.resolve(source, referer: 'thread');
        response.complete(Uint8List.fromList(<int>[4, 5, 6]));

        expect(await second, await first);
        verify(
            () => client.getBytes(source, referer: 'thread'),
        ).called(1);
    });

    test('清理临时缓存同时删除文件和内存快照', () async
    {
        final Uri source = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/page-3.jpg',
        );
        when(
            () => client.getBytes(source, referer: 'thread'),
        ).thenAnswer((_) async => Uint8List.fromList(<int>[7, 8, 9]));
        final ReaderMediaRepository repository = ReaderMediaRepository(
            client,
            cacheDirectory: () async => directory,
        );
        final Uri cached = await repository.resolve(source, referer: 'thread');

        await repository.clear();

        expect(repository.peek(source), isNull);
        expect(await File.fromUri(cached).exists(), isFalse);
        expect(await repository.cacheSizeBytes(), 0);
    });

    test('启动维护在超过上限时按最旧文件清理到目标容量', () async
    {
        final Directory root = Directory('${directory.path}/reader_media');
        await root.create();
        final DateTime base = DateTime(2026, 7, 1);
        final List<File> files = <File>[];
        for (int index = 0; index < 4; index++)
        {
            final File file = File('${root.path}/cache-$index.jpg');
            await file.writeAsBytes(<int>[1, 2, 3, 4]);
            await file.setLastModified(base.add(Duration(days: index)));
            files.add(file);
        }
        final ReaderMediaRepository repository = ReaderMediaRepository(
            client,
            cacheDirectory: () async => directory,
            maximumCacheBytes: 10,
            targetCacheBytes: 5,
        );

        await repository.maintainCache();

        expect(await files[0].exists(), isFalse);
        expect(await files[1].exists(), isFalse);
        expect(await files[2].exists(), isFalse);
        expect(await files[3].exists(), isTrue);
        expect(await repository.cacheSizeBytes(), 4);
    });

    test('固定自动清理水位为一 GB 到半 GB', ()
    {
        expect(
            ReaderMediaRepository.defaultMaximumCacheBytes,
            1024 * 1024 * 1024,
        );
        expect(
            ReaderMediaRepository.defaultTargetCacheBytes,
            512 * 1024 * 1024,
        );
    });
}
