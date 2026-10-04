import 'dart:io';

import 'package:integration_test/integration_test.dart';

import '../test/features/favorites/presentation/favorites_navigation_test.dart'
    as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.registerFavoritesNavigationTests(
    captureScreenshots: Platform.isLinux,
  );
}
