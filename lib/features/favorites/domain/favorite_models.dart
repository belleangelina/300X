import 'package:x300/features/library/domain/library_models.dart';

class CloudFavoriteRecord
{
    const CloudFavoriteRecord({
        required this.favoriteId,
        required this.threadId,
        required this.title,
        required this.threadUri,
        required this.deleteDialogUri,
    });

    final int favoriteId;
    final int threadId;
    final String title;
    final Uri threadUri;
    final Uri deleteDialogUri;
}

class ForumFavoriteListPage
{
    const ForumFavoriteListPage({
        required this.records,
        required this.currentPage,
        required this.totalPages,
        this.nextPageUri,
    });

    final List<CloudFavoriteRecord> records;
    final int currentPage;
    final int totalPages;
    final Uri? nextPageUri;

    bool get hasMore => nextPageUri != null;
}

class CloudFavoriteEntry
{
    const CloudFavoriteEntry({
        required this.record,
        required this.sourceThread,
    });

    final CloudFavoriteRecord record;
    final SourceThread sourceThread;
}

class CloudFavoritePage
{
    const CloudFavoritePage({
        required this.entries,
        required this.ignoredCount,
        required this.currentPage,
        required this.totalPages,
        this.nextPageUri,
    });

    final List<CloudFavoriteEntry> entries;
    final int ignoredCount;
    final int currentPage;
    final int totalPages;
    final Uri? nextPageUri;

    bool get hasMore => nextPageUri != null;
}

class FavoriteWork
{
    const FavoriteWork({
        required this.work,
        required this.records,
    });

    final Work work;
    final List<CloudFavoriteRecord> records;
}

class ForumFavoriteForm
{
    const ForumFavoriteForm({
        required this.actionUri,
        required this.fields,
    });

    final Uri actionUri;
    final Map<String, dynamic> fields;
}
