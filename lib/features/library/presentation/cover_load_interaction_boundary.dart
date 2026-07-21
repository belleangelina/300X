import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:x300/features/library/data/cover_repository.dart';

class CoverLoadInteractionBoundary extends StatelessWidget
{
    const CoverLoadInteractionBoundary({
        required this.coordinator,
        required this.child,
        super.key,
    });

    static final Object _fallbackScrollKey = Object();

    final CoverLoadCoordinator coordinator;
    final Widget child;

    @override
    Widget build(BuildContext context)
    {
        return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (PointerDownEvent event)
            {
                if (_pausesImmediately(event.kind))
                {
                    coordinator.pointerDown(event.pointer);
                }
            },
            onPointerUp: (PointerUpEvent event) =>
                    coordinator.pointerUp(event.pointer),
            onPointerCancel: (PointerCancelEvent event) =>
                    coordinator.pointerUp(event.pointer),
            child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: child,
            ),
        );
    }

    bool _handleScrollNotification(ScrollNotification notification)
    {
        final Object key = notification.context ?? _fallbackScrollKey;
        if (notification is ScrollEndNotification)
        {
            coordinator.scrollEnded(key);
        }
        else if (notification is ScrollStartNotification ||
                notification is ScrollUpdateNotification ||
                notification is OverscrollNotification)
        {
            coordinator.scrollActive(key);
        }
        return false;
    }

    bool _pausesImmediately(PointerDeviceKind kind)
    {
        return kind == PointerDeviceKind.touch ||
                kind == PointerDeviceKind.stylus ||
                kind == PointerDeviceKind.invertedStylus;
    }
}
