import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<SearchCooldown> searchCooldownProvider =
    Provider<SearchCooldown>((Ref ref) => SearchCooldown());

class SearchCooldown
{
    SearchCooldown({
        DateTime Function()? now,
        this.interval = const Duration(seconds: 10),
    }) : _now = now ?? DateTime.now;

    final DateTime Function() _now;
    final Duration interval;

    DateTime? _lastAcceptedAt;
    bool _inFlight = false;

    bool get inFlight => _inFlight;

    DateTime? get lastAcceptedAt => _lastAcceptedAt;

    Duration get remaining => remainingAt(_now());

    int get remainingSeconds
    {
        final int milliseconds = remaining.inMilliseconds;
        if (milliseconds <= 0)
        {
            return 0;
        }
        return (milliseconds + 999) ~/ 1000;
    }

    bool tryBegin()
    {
        if (_inFlight || remaining > Duration.zero)
        {
            return false;
        }
        _inFlight = true;
        return true;
    }

    void accepted()
    {
        _lastAcceptedAt = _now();
        _inFlight = false;
    }

    void failed()
    {
        _inFlight = false;
    }

    Duration remainingAt(DateTime value)
    {
        final DateTime? acceptedAt = _lastAcceptedAt;
        if (acceptedAt == null)
        {
            return Duration.zero;
        }
        final Duration elapsed = value.difference(acceptedAt);
        if (elapsed >= interval)
        {
            return Duration.zero;
        }
        if (elapsed.isNegative)
        {
            return interval;
        }
        return interval - elapsed;
    }
}
