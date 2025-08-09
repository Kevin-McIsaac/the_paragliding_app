import 'package:flutter/foundation.dart';
import 'package:free_flight_log_app/data/models/flight.dart';
import 'package:free_flight_log_app/data/models/site.dart';
import 'package:free_flight_log_app/data/models/wing.dart';
import 'package:free_flight_log_app/data/repositories/flight_repository.dart';
import 'package:free_flight_log_app/data/repositories/site_repository.dart';
import 'package:free_flight_log_app/data/repositories/wing_repository.dart';

/// Mock FlightProvider for testing
class MockFlightProvider extends ChangeNotifier {
  final List<Flight> _flights = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Flight> get flights => _flights;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  void addFlightForTesting(Flight flight) {
    _flights.add(flight);
    notifyListeners();
  }

  void clearFlights() {
    _flights.clear();
    notifyListeners();
  }

  void setLoadingState(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> loadFlights() async {
    // Mock implementation - does nothing
  }

  Future<void> deleteFlight(int id) async {
    _flights.removeWhere((f) => f.id == id);
    notifyListeners();
  }
}

/// Mock SiteProvider for testing
class MockSiteProvider extends ChangeNotifier {
  final List<Site> _sites = [];
  final bool _isLoading = false;
  String? _errorMessage;

  List<Site> get sites => _sites;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void addSiteForTesting(Site site) {
    _sites.add(site);
    notifyListeners();
  }

  Future<void> loadSites() async {
    // Mock implementation
  }

  Site? getSiteById(int? id) {
    if (id == null) return null;
    return _sites.firstWhere((s) => s.id == id, 
        orElse: () => Site(id: id, name: 'Unknown Site', country: 'Unknown'));
  }
}

/// Mock WingProvider for testing  
class MockWingProvider extends ChangeNotifier {
  final List<Wing> _wings = [];
  final bool _isLoading = false;
  String? _errorMessage;

  List<Wing> get wings => _wings;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void addWingForTesting(Wing wing) {
    _wings.add(wing);
    notifyListeners();
  }

  Future<void> loadWings() async {
    // Mock implementation
  }

  Wing? getWingById(int? id) {
    if (id == null) return null;
    return _wings.firstWhere((w) => w.id == id,
        orElse: () => Wing(id: id, manufacturer: 'Unknown', model: 'Unknown'));
  }
}

/// Mock repositories for testing
class MockFlightRepository extends FlightRepository {
  MockFlightRepository(super.dataSource);

  @override
  Future<List<Flight>> getAllFlights() async {
    return [];
  }

  @override
  Future<Flight?> getFlightById(int id) async {
    return null;
  }

  @override
  Future<int> insertFlight(Flight flight) async {
    return 1;
  }

  @override
  Future<void> updateFlight(Flight flight) async {
    // Mock implementation
  }

  @override
  Future<void> deleteFlight(int id) async {
    // Mock implementation
  }
}

class MockSiteRepository extends SiteRepository {
  MockSiteRepository(super.dataSource);

  @override
  Future<List<Site>> getAllSites() async {
    return [];
  }
}

class MockWingRepository extends WingRepository {
  MockWingRepository(super.dataSource);

  @override
  Future<List<Wing>> getAllWings() async {
    return [];
  }
}