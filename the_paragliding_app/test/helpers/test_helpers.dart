import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/data/models/flight.dart';
import 'package:the_paragliding_app/data/models/site.dart';
import 'package:the_paragliding_app/data/models/wing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Test helper utilities for widget testing
class TestHelpers {

  static bool _initialized = false;

  /// Point sqflite at an in-memory database for this test process.
  ///
  /// Each test file runs in its own process, so an in-memory database is
  /// private to that file. Nothing touches the ffi default
  /// (`.dart_tool/sqflite_common_ffi/databases/FlightLog.db`, which is also the
  /// desktop dev app's database), and there is no temp directory to leak - the
  /// previous approach left 46 `/tmp/paragliding_app_test_db_*` directories
  /// behind, because a test file that times out never reaches its teardown.
  ///
  /// It is also far cheaper. Building the schema and seeding 249 country codes
  /// against a file cost ~250ms; in memory it is microseconds. That margin is
  /// what pushed DB-touching test files past the 30s default timeout when
  /// `flutter test` was compiling the next file on another core (issue #280).
  ///
  /// Called automatically for every test file by `test/flutter_test_config.dart`;
  /// safe to call again from a test's `setUpAll`.
  static Future<void> initializeDatabaseForTesting() async {
    if (_initialized) return; // Already initialized in this process.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.databasePathOverride = inMemoryDatabasePath;
    _initialized = true;
  }

  /// Close the in-memory database, which is what discards its contents.
  static Future<void> cleanupDatabaseForTesting() async {
    if (!_initialized) return;
    await DatabaseHelper.instance.close();
  }

  static Directory? _fixtureDirCache;

  /// Directory private to this test process for fixture files.
  ///
  /// Tests used to write IGC fixtures to fixed paths like `/tmp/test_india.igc`
  /// - which two different test files both wrote - and read them straight back.
  /// A baseline run of issue #280 failed with `Parsed 0 track points, pilot:
  /// Unknown` because one such fixture read back empty. A per-process directory
  /// removes the whole class, including interference from anything else on the
  /// machine that happens to use `/tmp`.
  static Directory get _fixtureDir => _fixtureDirCache ??=
      Directory.systemTemp.createTempSync('paragliding_app_fixtures_');

  /// Absolute path for a fixture file called [name], private to this process.
  static String fixturePath(String name) => '${_fixtureDir.path}/$name';

  /// Remove this process's fixture directory (best effort).
  static void cleanupFixtures() {
    final dir = _fixtureDirCache;
    _fixtureDirCache = null;
    if (dir == null) return;
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // A leftover temp directory must never fail a test run.
    }
  }

  /// Create a test app wrapper
  static Widget createTestApp({
    required Widget child,
  }) {
    return MaterialApp(
      home: child,
      theme: ThemeData.light(),
      // Disable animations for testing
      debugShowCheckedModeBanner: false,
    );
  }

  /// Create a test flight with default values
  static Flight createTestFlight({
    int? id,
    DateTime? date,
    String? launchTime,
    String? landingTime,
    int? duration,
    int? launchSiteId,
    double? maxAltitude,
    double? maxClimbRate,
    double? maxSinkRate,
    double? distance,
    double? straightDistance,
    int? wingId,
    String? notes,
  }) {
    final now = DateTime.now();
    return Flight(
      id: id ?? 1,
      date: date ?? now,
      launchTime: launchTime ?? '10:00',
      landingTime: landingTime ?? '12:00',
      duration: duration ?? 120,
      launchSiteId: launchSiteId ?? 1,
      maxAltitude: maxAltitude ?? 2000.0,
      maxClimbRate: maxClimbRate ?? 3.0,
      maxSinkRate: maxSinkRate ?? -1.5,
      distance: distance ?? 12.5,
      straightDistance: straightDistance ?? 10.0,
      wingId: wingId ?? 1,
      notes: notes ?? 'Test flight',
      source: 'test',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create a test site with default values
  static Site createTestSite({
    int? id,
    String? name,
    double? latitude,
    double? longitude,
    double? altitude,
    String? country,
  }) {
    return Site(
      id: id ?? 1,
      name: name ?? 'Test Launch Site',
      latitude: latitude ?? 46.5197,
      longitude: longitude ?? 6.6323,
      altitude: altitude ?? 1500.0,
      country: country ?? 'Switzerland',
      customName: false,
      createdAt: DateTime.now(),
    );
  }

  /// Create a test wing with default values
  static Wing createTestWing({
    int? id,
    String? name,
    String? manufacturer,
    String? model,
    String? size,
  }) {
    return Wing(
      id: id ?? 1,
      name: name ?? 'Test Wing',
      manufacturer: manufacturer ?? 'Test Manufacturer',
      model: model ?? 'Test Wing',
      size: size ?? 'M',
      notes: 'Test wing for unit tests',
      active: true,
      createdAt: DateTime.now(),
    );
  }

  /// Wait for animations and async operations to complete
  static Future<void> settleAnimations(WidgetTester tester) async {
    await tester.pumpAndSettle(Duration(seconds: 2));
  }

  /// Find widget by text content (case insensitive)
  static Finder findTextContaining(String text) {
    return find.byWidgetPredicate(
      (widget) => widget is Text && 
                  widget.data != null && 
                  widget.data!.toLowerCase().contains(text.toLowerCase()),
    );
  }

  /// Tap and wait for animations
  static Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await settleAnimations(tester);
  }

  /// Enter text and wait for animations
  static Future<void> enterTextAndSettle(
    WidgetTester tester, 
    Finder finder, 
    String text
  ) async {
    await tester.enterText(finder, text);
    await settleAnimations(tester);
  }

  /// Verify error state widgets are displayed correctly
  static void verifyErrorState({
    required String expectedMessage,
    bool expectRetryButton = true,
  }) {
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.textContaining(expectedMessage), findsOneWidget);
    if (expectRetryButton) {
      expect(find.textContaining('Retry'), findsOneWidget);
    }
  }

  /// Verify loading state widgets are displayed correctly
  static void verifyLoadingState() {
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  }

  /// Verify empty state widgets are displayed correctly
  static void verifyEmptyState({
    required String expectedMessage,
    IconData? expectedIcon,
  }) {
    expect(find.textContaining(expectedMessage), findsOneWidget);
    if (expectedIcon != null) {
      expect(find.byIcon(expectedIcon), findsOneWidget);
    }
  }
}