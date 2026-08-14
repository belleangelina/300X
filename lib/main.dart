import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:x300/app/app_dependencies.dart';
import 'package:x300/app/app_licenses.dart';
import 'package:x300/app/x300_app.dart';
import 'package:x300/core/debug/debug_ui_automation.dart';

Future<void> main() async
{
    WidgetsFlutterBinding.ensureInitialized();
    registerX300Licenses();
    if (kDebugMode)
    {
        await DebugUiAutomation.install();
    }

    final AppDependencies dependencies = await AppDependencies.create();

    runApp(dependencies.buildScope(const X300App()));
}
