import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/features/favorites/data/forum_favorite_repository.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/library/domain/library_models.dart';

class _MockForumClient extends Mock implements ForumClient
{
}

void main()
{
    test('同作品跨帖收藏聚合为一个作品并保留全部云端记录', ()
    {
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            _MockForumClient(),
        );
        final List<CloudFavoriteEntry> entries = <CloudFavoriteEntry>[
            _entry(tid: 501, favoriteId: 9001, title: '测试作品 第1章'),
            _entry(tid: 502, favoriteId: 9002, title: '测试作品 第2章'),
        ];

        final List<FavoriteWork> works = repository.aggregateEntries(entries);

        expect(works, hasLength(1));
        expect(works.single.work.chapters, hasLength(2));
        expect(
            works.single.records
                .map((CloudFavoriteRecord value) => value.favoriteId),
            <int>[9001, 9002],
        );
    });
}

CloudFavoriteEntry _entry({
    required int tid,
    required int favoriteId,
    required String title,
})
{
    final Uri threadUri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
    return CloudFavoriteEntry(
        record: CloudFavoriteRecord(
            favoriteId: favoriteId,
            threadId: tid,
            title: title,
            threadUri: threadUri,
            deleteDialogUri: Uri.parse(
                'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&favid=$favoriteId',
            ),
        ),
        sourceThread: SourceThread(
            tid: tid,
            board: ForumBoard.literature,
            typeId: 49,
            title: title,
            uri: threadUri,
        ),
    );
}
