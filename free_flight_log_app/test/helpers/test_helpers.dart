import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log_app/data/models/flight.dart';
import 'package:free_flight_log_app/data/models/site.dart';
import 'package:free_flight_log_app/data/models/wing.dart';

/// Test helper utilities for widget testing
class TestHelpers {
  
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