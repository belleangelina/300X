import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

class ChapterContentSelector
{
    const ChapterContentSelector();

    List<PostContentBlock> select(ForumThreadPage page, Chapter chapter)
    {
        final List<PostContentBlock> blocks = _select(page, chapter);
        if (_isPermissionStub(blocks))
        {
            return const <PostContentBlock>[];
        }
        if (!blocks.any((PostContentBlock block) => block.substantiveQuote))
        {
            return blocks;
        }
        return blocks
                .where((PostContentBlock block) => block.substantiveQuote)
                .toList(growable: false);
    }

    bool _isPermissionStub(List<PostContentBlock> blocks)
    {
        if (blocks.any((PostContentBlock block) => block is PostImageBlock))
        {
            return false;
        }
        final String text = blocks
                .whereType<PostTextBlock>()
                .map((PostTextBlock block) => block.text)
                .join(' ')
                .trim();
        return text.length < 200 && RegExp(r'积分\s*\d+').hasMatch(text);
    }

    List<PostContentBlock> _select(ForumThreadPage page, Chapter chapter)
    {
        if (page.posts.isEmpty)
        {
            return const <PostContentBlock>[];
        }

        final int? sourcePid = chapter.sourcePid;
        List<SourcePost> posts;
        if (sourcePid != null)
        {
            final int start = page.posts.indexWhere(
                (SourcePost post) => post.pid == sourcePid,
            );
            if (start < 0)
            {
                return const <PostContentBlock>[];
            }
            int end = page.posts.length;
            final int? sourceEndPid = chapter.sourceEndPid;
            if (sourceEndPid != null)
            {
                final int candidate = page.posts.indexWhere(
                    (SourcePost post) => post.pid == sourceEndPid,
                );
                if (candidate > start)
                {
                    end = candidate;
                }
            }
            final SourcePost target = page.posts[start];
            posts = page.posts
                    .sublist(start, end)
                    .where(
                        (SourcePost post) => post.pid == sourcePid ||
                                target.author.isNotEmpty &&
                                        post.author == target.author,
                    )
                    .toList(growable: false);
        }
        else
        {
            posts = page.posts
                    .where((SourcePost post) => post.isOriginalPoster)
                    .toList(growable: false);
            if (posts.isEmpty)
            {
                posts = page.posts;
            }
        }

        final int? sourceStartBlock = chapter.sourceStartBlock;
        final int? sourceEndBlock = chapter.sourceEndBlock;
        if (sourceStartBlock != null || sourceEndBlock != null)
        {
            if (sourcePid == null)
            {
                return const <PostContentBlock>[];
            }
            final List<PostContentBlock> blocks = posts.first.blocks;
            final int blockStart = sourceStartBlock ?? 0;
            final int blockEnd = sourceEndBlock ?? blocks.length;
            if (blockStart < 0 || blockEnd < blockStart || blockEnd > blocks.length)
            {
                return const <PostContentBlock>[];
            }
            return blocks.sublist(blockStart, blockEnd);
        }
        return posts
                .expand((SourcePost post) => post.blocks)
                .toList(growable: false);
    }
}
