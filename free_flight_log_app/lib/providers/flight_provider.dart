import 'package:flutter/foundation.dart';
import '../data/models/flight.dart';
import '../data/repositories/flight_repository.dart';
import '../services/logging_service.dart';

/// State management for flight data
class FlightProvider extends ChangeNotifier {
  final FlightRepository _repository;
  
  FlightProvider(this._repository);

  List<Flight> _flights = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<Flight> get flights => _flights;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Load all flights from repository
  Future<void> loadFlights() async {
    _setLoading(true);
    _clearError();
    
    try {
      LoggingService.debug('FlightProvider: Loading flights from repository');
      final startTime = DateTime.now();
      
      _flights = await _repository.getAllFlights();
      
      final duration = DateTime.now().difference(startTime);
      LoggingService.performance('Load flights', duration, '${_flights.length} flights loaded');
      
      LoggingService.info('FlightProvider: Loaded ${_flights.length} flights');
      notifyListeners();
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to load flights', e);
      _setError('Failed to load flights: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Add a new flight
  Future<bool> addFlight(Flight flight) async {
    _clearError();
    
    try {
      LoggingService.debug('FlightProvider: Adding new flight');
      final id = await _repository.insertFlight(flight);
      
      // Add to local list with the new ID
      final newFlight = flight.copyWith(id: id);
      _flights.insert(0, newFlight); // Add to beginning (most recent first)
      
      LoggingService.info('FlightProvider: Added flight with ID $id');
      notifyListeners();
      return true;
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to add flight', e);
      _setError('Failed to add flight: $e');
      return false;
    }
  }

  /// Update an existing flight
  Future<bool> updateFlight(Flight flight) async {
    _clearError();
    
    try {
      LoggingService.debug('FlightProvider: Updating flight ${flight.id}');
      await _repository.updateFlight(flight);
      
      // Update in local list
      final index = _flights.indexWhere((f) => f.id == flight.id);
      if (index >= 0) {
        _flights[index] = flight;
        LoggingService.info('FlightProvider: Updated flight ${flight.id}');
        notifyListeners();
      }
      return true;
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to update flight', e);
      _setError('Failed to update flight: $e');
      return false;
    }
  }

  /// Delete a flight
  Future<bool> deleteFlight(int flightId) async {
    _clearError();
    
    try {
      LoggingService.debug('FlightProvider: Deleting flight $flightId');
      await _repository.deleteFlight(flightId);
      
      // Remove from local list
      _flights.removeWhere((f) => f.id == flightId);
      
      LoggingService.info('FlightProvider: Deleted flight $flightId');
      notifyListeners();
      return true;
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to delete flight', e);
      _setError('Failed to delete flight: $e');
      return false;
    }
  }

  /// Delete multiple flights
  Future<bool> deleteFlights(List<int> flightIds) async {
    _clearError();
    
    try {
      LoggingService.debug('FlightProvider: Deleting ${flightIds.length} flights');
      
      for (final id in flightIds) {
        await _repository.deleteFlight(id);
      }
      
      // Remove from local list
      _flights.removeWhere((f) => flightIds.contains(f.id));
      
      LoggingService.info('FlightProvider: Deleted ${flightIds.length} flights');
      notifyListeners();
      return true;
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to delete flights', e);
      _setError('Failed to delete flights: $e');
      return false;
    }
  }

  /// Get flight statistics
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      LoggingService.debug('FlightProvider: Loading statistics');
      return await _repository.getFlightStatistics();
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to load statistics', e);
      _setError('Failed to load statistics: $e');
      return {};
    }
  }

  /// Get yearly statistics
  Future<List<Map<String, dynamic>>> getYearlyStatistics() async {
    try {
      LoggingService.debug('FlightProvider: Loading yearly statistics');
      return await _repository.getYearlyStatistics();
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to load yearly statistics', e);
      _setError('Failed to load yearly statistics: $e');
      return [];
    }
  }

  /// Find duplicate flight
  Future<Flight?> findDuplicateFlight(DateTime date, String launchTime) async {
    try {
      return await _repository.findFlightByDateTime(date, launchTime);
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to check for duplicates', e);
      return null;
    }
  }

  /// Clear error message
  void clearError() {
    _clearError();
  }

  // Private methods
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
}