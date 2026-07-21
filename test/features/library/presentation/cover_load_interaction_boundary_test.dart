import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/presentation/cover_load_interaction_boundary.dart';

void main()
{
    testWidgets('触屏立即暂停且离手后等待惯性滚动结束', (
        WidgetTester tester,
    ) async
    {
        final CoverLoadCoordinator coordinator = CoverLoadCoordinator();
        final ScrollController scrollController = ScrollController();
        await tester.pumpWidget(
            MaterialApp(
                home: CoverLoadInteractionBoundary(
                    coordinator: coordinator,
                    child: ListView.builder(
                        controller: scrollController,
                        itemCount: 30,
                        itemBuilder: (BuildContext context, int index) =>
                                SizedBox(height: 80, child: Text('$index')),
                    ),
                ),
            ),
        );

        final TestGesture gesture = await tester.startGesture(
            tester.getCenter(find.text('2')),
            kind: PointerDeviceKind.touch,
        );
        expect(coordinator.paused, isTrue);

        final BuildContext listContext = tester.element(find.byType(ListView));
        ScrollStartNotification(
            metrics: scrollController.position,
            context: listContext,
        ).dispatch(listContext);
        await gesture.up();
        expect(coordinator.paused, isTrue);

        ScrollEndNotification(
            metrics: scrollController.position,
            context: listContext,
        ).dispatch(listContext);
        expect(coordinator.paused, isTrue);
        await tester.pump(const Duration(milliseconds: 140));
        expect(coordinator.paused, isTrue);
        await tester.pump(const Duration(milliseconds: 20));
        expect(coordinator.paused, isFalse);

        ScrollStartNotification(
            metrics: scrollController.position,
            context: listContext,
        ).dispatch(listContext);
        for (int index = 0; index < 6; index++)
        {
            await tester.pump(const Duration(milliseconds: 90));
            ScrollUpdateNotification(
                metrics: scrollController.position,
                context: listContext,
                scrollDelta: 1,
            ).dispatch(listContext);
        }
        expect(coordinator.paused, isTrue);
        await tester.pump(const Duration(milliseconds: 510));
        expect(coordinator.paused, isFalse);
        scrollController.dispose();
        coordinator.dispose();
    });
}
