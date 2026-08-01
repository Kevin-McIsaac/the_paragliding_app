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
  // SiteMatchingService.initialize()/reload() reaches the incremental PGE sync,
  // which is a live HTTP call. No test should depend on - or be slowed and
  // destabilised by - a background network request it never asked for.
  AppInitializationService.backgroundSyncEnabled = false;

  await TestHelpers.initializeDatabaseForTesting();
  tearDownAll(TestHelpers.cleanupDatabaseForTesting);
  await testMain();
}
