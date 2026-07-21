import 'package:flutter/material.dart';
import 'package:x300/app/app_dependencies.dart';
import 'package:x300/app/app_licenses.dart';
import 'package:x300/app/x300_app.dart';

Future<void> main() async
{
    WidgetsFlutterBinding.ensureInitialized();
    registerX300Licenses();

    final AppDependencies dependencies = await AppDependencies.create();

    runApp(dependencies.buildScope(const X300App()));
}
