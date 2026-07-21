import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/library/data/long_form_classifier.dart';
import 'package:x300/features/library/domain/library_models.dart';

void main()
{
    const LongFormClassifier classifier = LongFormClassifier();

    test('四个漫画长篇分类的繁简名称与 typeId 都可识别', ()
    {
        for (final ({int id, String name}) value in <({int id, String name})>[
            (id: 69, name: '#長篇連載'),
            (id: 398, name: '#韩国漫画'),
            (id: 503, name: '＃泰國漫畫'),
            (id: 504, name: ' # 欧美其他 '),
        ])
        {
            expect(
                classifier.isExplicitLongComic(
                    _work(typeId: value.id, typeName: value.name),
                ),
                isTrue,
            );
        }
    });

    test('短篇漫画与小说不属于明确长篇漫画', ()
    {
        expect(
            classifier.isExplicitLongComic(
                _work(typeId: 68, typeName: '#短篇漫画'),
            ),
            isFalse,
        );
        expect(
            classifier.isExplicitLongComic(
                _work(
                    typeId: 69,
                    typeName: '#長篇連載',
                    board: ForumBoard.literature,
                ),
            ),
            isFalse,
        );
    });

    test('短篇漫画的真实 typeId 和繁简名称均可识别', ()
    {
        expect(
            classifier.isExplicitShortComic(
                _work(typeId: 68, typeName: ''),
            ),
            isTrue,
        );
        expect(
            classifier.isExplicitShortComic(
                _work(typeId: 0, typeName: ' # 短篇漫畫 '),
            ),
            isTrue,
        );
        expect(
            classifier.isExplicitShortComic(
                _work(typeId: 66, typeName: '#百合雜誌'),
            ),
            isFalse,
        );
    });

    test('分类编号和分类名称可以独立识别', ()
    {
        expect(
            classifier.isExplicitLongComic(
                _work(typeId: 398, typeName: ''),
            ),
            isTrue,
        );
        expect(
            classifier.isExplicitLongComic(
                _work(typeId: 0, typeName: '#泰国漫画'),
            ),
            isTrue,
        );
    });
}

Work _work({
    required int typeId,
    required String typeName,
    ForumBoard board = ForumBoard.comic,
})
{
    final Uri uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2',
    );
    return Work(
        id: 'forum-thread:1',
        kind: board.kind,
        title: '测试作品',
        typeName: typeName,
        sourceThreads: <SourceThread>[
            SourceThread(
                tid: 1,
                board: board,
                typeId: typeId,
                typeName: typeName,
                title: '测试作品',
                uri: uri,
            ),
        ],
        chapters: <Chapter>[
            Chapter(
                id: 'forum-thread:1',
                title: '正文',
                sourceUri: uri,
                sourceTid: 1,
            ),
        ],
    );
}
