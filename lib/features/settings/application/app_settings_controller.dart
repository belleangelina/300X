import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';
import 'package:x300/features/settings/domain/app_settings.dart';

final NotifierProvider<AppSettingsController, AppSettings>
    appSettingsControllerProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
        AppSettingsController.new,
    );

class AppSettingsController extends Notifier<AppSettings>
{
    AppSettingsRepository get _repository => ref.read(
        appSettingsRepositoryProvider,
    );

    @override
    AppSettings build()
    {
        return _repository.load();
    }

    void update(AppSettings value)
    {
        state = value;
        unawaited(_repository.save(value));
    }
}
