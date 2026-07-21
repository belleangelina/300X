import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/reader/data/reader_media_repository.dart';
import 'package:x300/shared/presentation/forum_image.dart';

class _MockReaderMediaRepository extends Mock
    implements ReaderMediaRepository
{
}

void main()
{
    testWidgets('已加载的在线图片重建时同步复用本地缓存', (
        WidgetTester tester,
    ) async
    {
        final Uri source = Uri.parse(
            'https://bbs.yamibo.com/data/attachment/forum/page.png',
        );
        final _MockReaderMediaRepository repository =
                _MockReaderMediaRepository();
        when(
            () => repository.peek(source),
        ).thenReturn(Uri.file('/tmp/page300-cached-page.png'));

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    readerMediaRepositoryProvider.overrideWithValue(repository),
                ],
                child: MaterialApp(
                    home: Scaffold(
                        body: ForumImage(uri: source, referer: 'thread'),
                    ),
                ),
            ),
        );

        expect(find.byType(Image), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        verify(() => repository.peek(source)).called(1);
        verifyNever(
            () => repository.resolve(source, referer: any(named: 'referer')),
        );
    });
}
