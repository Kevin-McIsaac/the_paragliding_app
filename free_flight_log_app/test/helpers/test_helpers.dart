import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:free_flight_log_app/providers/flight_provider.dart';
import 'package:free_flight_log_app/providers/site_provider.dart';
import 'package:free_flight_log_app/providers/wing_provider.dart';
import 'package:free_flight_log_app/data/models/flight.dart';
import 'package:free_flight_log_app/data/models/site.dart';
import 'package:free_flight_log_app/data/models/wing.dart';

/// Test helper utilities for widget testing
class TestHelpers {
  
  /// Create a test app wrapper with all necessary providers
  static Widget createTestApp({
    required Widget child,
    FlightProvider? flightProvider,
    SiteProvider? siteProvider,
    WingProvider? wingProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FlightProvider>.value(
          value: flightProvider ?? MockFlightProvider(),
        ),
        ChangeNotifierProvider<SiteProvider>.value(
          value: siteProvider ?? MockSiteProvider(),
        ),
        ChangeNotifierProvider<WingProvider>.value(
          value: wingProvider ?? MockWingProvider(),
        ),
      ],
      child: MaterialApp(
        home: child,
        theme: ThemeData.light(),
        // Disable animations for testing
        debugShowCheckedModeBanner: false,
      ),
    );
  }

  /// Create a test flight with default values
  static Flight createTestFlight({
    int? id,
    DateTime? date,
    DateTime? launchTime,
    DateTime? landingTime,
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
      launchTime: launchTime ?? now.subtract(Duration(hours: 2)),
      landingTime: landingTime ?? now,
      duration: duration ?? 120,
      launchSiteId: launchSiteId ?? 1,
      maxAltitude: maxAltitude ?? 2000.0,
      maxClimbRate: maxClimbRate ?? 3.0,
      maxSinkRate: maxSinkRate ?? -1.5,
      distance: distance ?? 12.5,
      straightDistance: straightDistance ?? 10.0,
      wingId: wingId ?? 1,
      notes: notes ?? 'Test flight',
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
    String? manufacturer,
    String? model,
    String? size,
    String? certification,
  }) {
    return Wing(
      id: id ?? 1,
      manufacturer: manufacturer ?? 'Test Manufacturer',
      model: model ?? 'Test Wing',
      size: size ?? 'M',
      certification: certification ?? 'EN-A',
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

/// Mock Flight Provider for testing
class MockFlightProvider extends ChangeNotifier implements FlightProvider {
  final List<Flight> _flights = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  List<Flight> get flights => _flights;

  @override
  bool get isLoading => _isLoading;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> loadFlights() async {
    _isLoading = true;
    notifyListeners();

    // Simulate loading delay
    await Future.delayed(Duration(milliseconds: 100));

    _isLoading = false;
    notifyListeners();
  }

  @override
  Future<bool> addFlight(Flight flight) async {
    _flights.add(flight);
    notifyListeners();
    return true;
  }

  @override
  Future<bool> updateFlight(Flight flight) async {
    final index = _flights.indexWhere((f) => f.id == flight.id);
    if (index != -1) {
      _flights[index] = flight;
      notifyListeners();
      return true;
    }
    return false;
  }

  @override
  Future<bool> deleteFlight(int id) async {
    _flights.removeWhere((f) => f.id == id);
    notifyListeners();
    return true;
  }

  @override
  Future<bool> deleteFlights(List<int> ids) async {
    _flights.removeWhere((f) => ids.contains(f.id));
    notifyListeners();
    return true;
  }

  // Test helper methods
  void addFlightForTesting(Flight flight) {
    _flights.add(flight);
    notifyListeners();
  }

  void clearFlights() {
    _flights.clear();
    notifyListeners();
  }

  void setLoadingState(bool isLoading) {
    _isLoading = isLoading;
    notifyListeners();
  }

  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }
}

/// Mock Site Provider for testing
class MockSiteProvider extends ChangeNotifier implements SiteProvider {
  final List<Site> _sites = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  List<Site> get sites => _sites;

  @override
  bool get isLoading => _isLoading;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> loadSites() async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(Duration(milliseconds: 100));

    _isLoading = false;
    notifyListeners();
  }

  @override
  Future<bool> addSite(Site site) async {
    _sites.add(site);
    notifyListeners();
    return true;
  }

  @override
  Future<bool> updateSite(Site site) async {
    final index = _sites.indexWhere((s) => s.id == site.id);
    if (index != -1) {
      _sites[index] = site;
      notifyListeners();
      return true;
    }
    return false;
  }

  @override
  Future<bool> deleteSite(int id) async {
    _sites.removeWhere((s) => s.id == id);
    notifyListeners();
    return true;
  }

  // Test helper methods
  void addSiteForTesting(Site site) {
    _sites.add(site);
    notifyListeners();
  }

  void clearSites() {
    _sites.clear();
    notifyListeners();
  }
}

/// Mock Wing Provider for testing
class MockWingProvider extends ChangeNotifier implements WingProvider {
  final List<Wing> _wings = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  List<Wing> get wings => _wings;

  @override
  bool get isLoading => _isLoading;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> loadWings() async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(Duration(milliseconds: 100));

    _isLoading = false;
    notifyListeners();
  }

  @override
  Future<bool> addWing(Wing wing) async {
    _wings.add(wing);
    notifyListeners();
    return true;
  }

  @override
  Future<bool> updateWing(Wing wing) async {
    final index = _wings.indexWhere((w) => w.id == wing.id);
    if (index != -1) {
      _wings[index] = wing;
      notifyListeners();
      return true;
    }
    return false;
  }

  @override
  Future<bool> deleteWing(int id) async {
    _wings.removeWhere((w) => w.id == id);
    notifyListeners();
    return true;
  }

  // Test helper methods
  void addWingForTesting(Wing wing) {
    _wings.add(wing);
    notifyListeners();
  }

  void clearWings() {
    _wings.clear();
    notifyListeners();
  }
}