import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/services/app_initialization_service.dart';

import 'helpers/test_helpers.dart';

/// Runs once per test file, before that file's `main()` declares its tests.
///
/// Points sqflite at a temporary databases directory unique to this test
/// process, so no test can touch the developer's
/// `.dart_tool/sqflite_common_ffi/databases/FlightLog.db`, and test files that
/// `flutter test` runs concurrently cannot see each other's data.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // SiteMatchingService.initialize()/reload() reaches deferred background
  // initialization: a rootBundle asset import that cannot work without a Flutter
  // binding, and a live HTTP sync. Neither can succeed here, and the failing
  // import took long enough to time out unrelated test files. Tests that need
  // PGE rows seed them directly.
  AppInitializationService.backgroundInitEnabled = false;

  await TestHelpers.initializeDatabaseForTesting();
  tearDownAll(TestHelpers.cleanupDatabaseForTesting);
  await testMain();
}
