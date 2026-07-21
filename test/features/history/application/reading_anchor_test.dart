import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/history/application/reading_anchor.dart';

void main()
{
    test('进度与图片索引或字符锚点稳定换算', ()
    {
        expect(ReadingAnchor.positionForProgress(0, 9), 0);
        expect(ReadingAnchor.positionForProgress(0.5, 9), 5);
        expect(ReadingAnchor.positionForProgress(1, 1200), 1200);
        expect(ReadingAnchor.positionForProgress(-1, 9), 0);
        expect(ReadingAnchor.positionForProgress(2, 9), 9);
    });

    test('分页索引按可用页数恢复并限制边界', ()
    {
        expect(ReadingAnchor.progressForPage(0, 10), 0);
        expect(ReadingAnchor.progressForPage(9, 10), 1);
        expect(ReadingAnchor.pageForProgress(0.5, 10), 5);
        expect(ReadingAnchor.pageForProgress(1, 10), 9);
        expect(ReadingAnchor.pageForProgress(1, 1), 0);
    });
}
