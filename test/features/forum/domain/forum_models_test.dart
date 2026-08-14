import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

void main()
{
    test('旧缓存构造 ForumPost 时结构化正文默认为空', ()
    {
        final ForumPost post = ForumPost(
            id: 10,
            threadId: 20,
            floor: 1,
            author: '用户',
            timeLabel: '刚刚',
            messageHtml: '<p>兼容正文</p>',
            uri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=20&mobile=2#pid10',
            ),
        );

        expect(post.contentBlocks, isEmpty);
        expect(post.comments, isEmpty);
        expect(post.ratingSummary, isNull);
        expect(post.messageHtml, contains('兼容正文'));
    });

    test('正文领域模型只表达不可执行的块和行内语义', ()
    {
        final Uri uri = Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=20&pid=10',
        );
        final ForumPostContentBlock block = ForumPostQuoteBlock(
            inlines: <ForumPostInline>[
                const ForumPostTextInline(
                    text: '引用',
                    bold: true,
                    italic: true,
                ),
                const ForumPostLineBreakInline(),
                ForumPostLinkInline(
                    label: '原楼层',
                    uri: uri,
                    kind: ForumPostLinkKind.internalPost,
                    threadId: 20,
                    postId: 10,
                ),
            ],
        );

        expect(block, isA<ForumPostQuoteBlock>());
        expect(block.inlines, hasLength(3));
        expect((block.inlines.first as ForumPostTextInline).bold, isTrue);
        expect(
            (block.inlines.last as ForumPostLinkInline).kind,
            ForumPostLinkKind.internalPost,
        );
    });
}
