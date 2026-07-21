import 'package:x300/features/library/domain/library_models.dart';

sealed class PostContentBlock
{
    const PostContentBlock({this.substantiveQuote = false});

    final bool substantiveQuote;
}

class PostTextBlock extends PostContentBlock
{
    const PostTextBlock({
        required this.text,
        this.heading = false,
        super.substantiveQuote,
    });

    final String text;
    final bool heading;
}

class PostImageBlock extends PostContentBlock
{
    const PostImageBlock({
        required this.uri,
        this.alt = '',
        super.substantiveQuote,
    });

    final Uri uri;
    final String alt;
}

enum ThreadLinkKind { previous, next, chapter, directory, related }

class ThreadLink
{
    const ThreadLink({
        required this.label,
        required this.uri,
        required this.kind,
        this.tid,
        this.pid,
    });

    final String label;
    final Uri uri;
    final ThreadLinkKind kind;
    final int? tid;
    final int? pid;
}

class SourcePost
{
    const SourcePost({
        required this.pid,
        required this.tid,
        required this.page,
        required this.floor,
        required this.author,
        required this.timeLabel,
        required this.isOriginalPoster,
        required this.blocks,
        required this.links,
    });

    final int pid;
    final int tid;
    final int page;
    final int floor;
    final String author;
    final String timeLabel;
    final bool isOriginalPoster;
    final List<PostContentBlock> blocks;
    final List<ThreadLink> links;

    List<Uri> get imageUris => blocks
            .whereType<PostImageBlock>()
            .map((PostImageBlock block) => block.uri)
            .toList(growable: false);

    String get plainText => blocks
            .whereType<PostTextBlock>()
            .map((PostTextBlock block) => block.text)
            .join('\n\n');
}

class ForumThreadPage
{
    const ForumThreadPage({
        required this.tid,
        required this.board,
        required this.title,
        required this.uri,
        required this.posts,
        required this.currentPage,
        required this.totalPages,
        this.typeName = '',
        this.nextPageUri,
        this.originalPosterUri,
    });

    final int tid;
    final ForumBoard board;
    final String title;
    final Uri uri;
    final List<SourcePost> posts;
    final int currentPage;
    final int totalPages;
    final String typeName;
    final Uri? nextPageUri;
    final Uri? originalPosterUri;

    SourcePost? get originalPost
    {
        for (final SourcePost post in posts)
        {
            if (post.isOriginalPoster && post.floor == 1)
            {
                return post;
            }
        }
        for (final SourcePost post in posts)
        {
            if (post.isOriginalPoster)
            {
                return post;
            }
        }
        return posts.isEmpty ? null : posts.first;
    }
}
