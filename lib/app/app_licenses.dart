import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerX300Licenses()
{
    LicenseRegistry.addLicense(() async* {
        final String license = await rootBundle.loadString('LICENSE');
        yield LicenseEntryWithLineBreaks(<String>[
            '300X',
            'flutter_dmzj-derived code',
        ], license);
    });
}
