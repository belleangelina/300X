import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/search/application/search_cooldown.dart';

void main()
{
    test('服务器接受搜索后精确冷却十秒', ()
    {
        DateTime now = DateTime(2026, 7, 10, 17);
        final SearchCooldown cooldown = SearchCooldown(now: () => now);

        expect(cooldown.tryBegin(), isTrue);
        expect(cooldown.inFlight, isTrue);
        cooldown.accepted();
        expect(cooldown.remainingSeconds, 10);
        expect(cooldown.tryBegin(), isFalse);

        now = now.add(const Duration(milliseconds: 9999));
        expect(cooldown.remaining, const Duration(milliseconds: 1));
        expect(cooldown.remainingSeconds, 1);
        expect(cooldown.tryBegin(), isFalse);

        now = now.add(const Duration(milliseconds: 1));
        expect(cooldown.remaining, Duration.zero);
        expect(cooldown.tryBegin(), isTrue);
    });

    test('失败的搜索释放进行中状态且不启动冷却', ()
    {
        final SearchCooldown cooldown = SearchCooldown();

        expect(cooldown.tryBegin(), isTrue);
        cooldown.failed();

        expect(cooldown.inFlight, isFalse);
        expect(cooldown.remaining, Duration.zero);
        expect(cooldown.tryBegin(), isTrue);
    });
}
