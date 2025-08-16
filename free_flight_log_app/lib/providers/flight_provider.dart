import 'package:flutter/foundation.dart';
import '../data/models/flight.dart';
import '../data/models/import_result.dart';
import '../data/repositories/flight_repository.dart';
import '../data/services/flight_query_service.dart';
import '../data/services/flight_statistics_service.dart';
import '../services/igc_import_service.dart';
import '../services/logging_service.dart';

/// State management for flight data
class FlightProvider extends ChangeNotifier {
  // Singleton pattern
  static FlightProvider? _instance;
  static FlightProvider get instance {
    _instance ??= FlightProvider._internal();
    return _instance!;
  }
  
  FlightProvider._internal();
  
  final FlightRepository _repository = FlightRepository.instance;
  final FlightQueryService _queryService = FlightQueryService.instance;
  final FlightStatisticsService _statisticsService = FlightStatisticsService.instance;
  final IgcImportService _igcImportService = IgcImportService.instance;

  List<Flight> _flights = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  // Statistics state
  int _totalFlights = 0;
  int _totalDuration = 0;
  
  // Statistics state
  List<Map<String, dynamic>> _yearlyStats = [];
  List<Map<String, dynamic>> _wingStats = [];
  List<Map<String, dynamic>> _siteStats = [];
  bool _statisticsLoaded = false;
  
  // Sorting state and cache
  String _sortColumn = 'datetime';
  bool _sortAscending = false; // Default to newest first
  List<Flight>? _sortedFlightsCache;
  String? _lastSortColumn;
  bool? _lastSortAscending;
  int? _lastFlightDataHash;

  // Getters
  List<Flight> get flights => _flights;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get totalFlights => _totalFlights;
  int get totalDuration => _totalDuration;
  List<Map<String, dynamic>> get yearlyStats => _yearlyStats;
  List<Map<String, dynamic>> get wingStats => _wingStats;
  List<Map<String, dynamic>> get siteStats => _siteStats;
  bool get statisticsLoaded => _statisticsLoaded;
  String get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  
  /// Get sorted flights with caching
  List<Flight> get sortedFlights {
    // Check if cache is valid
    if (_sortedFlightsCache == null || 
        _lastSortColumn != _sortColumn || 
        _lastSortAscending != _sortAscending || 
        _lastFlightDataHash != _calculateFlightDataHash(_flights)) {
      
      // Cache miss - need to sort
      _sortedFlightsCache = _getSortedFlights(_flights);
      _lastSortColumn = _sortColumn;
      _lastSortAscending = _sortAscending;
      _lastFlightDataHash = _calculateFlightDataHash(_flights);
    }
    
    return _sortedFlightsCache!;
  }

  /// Load all flights from repository  
  Future<void> loadFlights() async {
    _setLoading(true);
    _clearError();
    
    try {
      LoggingService.debug('FlightProvider: Loading all flights from repository');
      final startTime = DateTime.now();
      
      // Get overall statistics (total count and duration)
      final stats = await _statisticsService.getOverallStatistics();
      _totalFlights = stats['totalFlights'] ?? 0;
      _totalDuration = stats['totalDuration'] ?? 0;
      
      // Load all flights at once
      _flights = await _repository.getAllFlights();
      
      final duration = DateTime.now().difference(startTime);
      LoggingService.performance('Load all flights', duration, '${_flights.length} flights loaded');
      
      LoggingService.info('FlightProvider: Loaded ${_flights.length} flights');
      _invalidateCache();
      notifyListeners();
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to load flights', e);
      _setError('Failed to load flights: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Load all flights (for operations that need complete data)
  Future<void> loadAllFlights() async {
    _setLoading(true);
    _clearError();
    
    try {
      LoggingService.debug('FlightProvider: Loading all flights from repository');
      final startTime = DateTime.now();
      
      // Load all flights at once
      _flights = await _repository.getAllFlights();
      _totalFlights = _flights.length;
      
      final duration = DateTime.now().difference(startTime);
      LoggingService.performance('Load all flights', duration, '${_flights.length} flights loaded');
      
      LoggingService.info('FlightProvider: Loaded all ${_flights.length} flights');
      _invalidateCache();
      notifyListeners();
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to load all flights', e);
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
      _invalidateCache();
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
        _invalidateCache();
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
    
    // Check if flight exists in local list to prevent duplicate deletion
    if (!_flights.any((f) => f.id == flightId)) {
      LoggingService.warning('FlightProvider: Flight $flightId not found in local list, skipping deletion');
      return false;
    }
    
    try {
      LoggingService.debug('FlightProvider: Deleting flight $flightId');
      await _repository.deleteFlight(flightId);
      
      // Remove from local list
      _flights.removeWhere((f) => f.id == flightId);
      _totalFlights--; // Update total count
      
      LoggingService.info('FlightProvider: Deleted flight $flightId');
      _invalidateCache();
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
    
    // Filter to only include flights that exist in local list
    final existingIds = flightIds.where((id) => _flights.any((f) => f.id == id)).toList();
    
    if (existingIds.isEmpty) {
      LoggingService.warning('FlightProvider: No flights found for deletion in local list');
      return false;
    }
    
    if (existingIds.length != flightIds.length) {
      LoggingService.warning('FlightProvider: Some flights already deleted, proceeding with ${existingIds.length}/${flightIds.length} flights');
    }
    
    try {
      LoggingService.debug('FlightProvider: Deleting ${existingIds.length} flights');
      
      for (final id in existingIds) {
        await _repository.deleteFlight(id);
      }
      
      // Remove from local list
      _flights.removeWhere((f) => existingIds.contains(f.id));
      _totalFlights -= existingIds.length; // Update total count
      
      LoggingService.info('FlightProvider: Deleted ${existingIds.length} flights');
      _invalidateCache();
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
      return await _statisticsService.getOverallStatistics();
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
      return await _statisticsService.getYearlyStatistics();
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to load yearly statistics', e);
      _setError('Failed to load yearly statistics: $e');
      return [];
    }
  }

  /// Get wing statistics
  Future<List<Map<String, dynamic>>> getWingStatistics() async {
    try {
      LoggingService.debug('FlightProvider: Loading wing statistics');
      return await _statisticsService.getWingStatistics();
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to load wing statistics', e);
      _setError('Failed to load wing statistics: $e');
      return [];
    }
  }

  /// Get site statistics
  Future<List<Map<String, dynamic>>> getSiteStatistics() async {
    try {
      LoggingService.debug('FlightProvider: Loading site statistics');
      return await _statisticsService.getSiteStatistics();
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to load site statistics', e);
      _setError('Failed to load site statistics: $e');
      return [];
    }
  }

  /// Load all statistics data
  Future<void> loadAllStatistics() async {
    _setLoading(true);
    _clearError();
    
    try {
      LoggingService.debug('FlightProvider: Loading all statistics');
      final startTime = DateTime.now();
      
      // Load all statistics in parallel
      final results = await Future.wait([
        _statisticsService.getYearlyStatistics(),
        _statisticsService.getWingStatistics(),
        _statisticsService.getSiteStatistics(),
      ]);
      
      _yearlyStats = results[0];
      _wingStats = results[1];
      _siteStats = results[2];
      _statisticsLoaded = true;
      
      final duration = DateTime.now().difference(startTime);
      LoggingService.performance('Load all statistics', duration, 
          '${_yearlyStats.length} yearly, ${_wingStats.length} wing, ${_siteStats.length} site stats loaded');
      
      LoggingService.info('FlightProvider: Loaded all statistics successfully');
      notifyListeners();
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to load statistics', e);
      _setError('Failed to load statistics: $e');
      _statisticsLoaded = false;
    } finally {
      _setLoading(false);
    }
  }

  /// Find duplicate flight
  Future<Flight?> findDuplicateFlight(DateTime date, String launchTime) async {
    try {
      return await _queryService.findFlightByDateTime(date, launchTime);
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to check for duplicates', e);
      return null;
    }
  }
  
  /// Phase 1: Quick check for duplicate by filename (no parsing needed)
  Future<Flight?> checkForDuplicateByFilename(String filename) async {
    try {
      return await _igcImportService.checkForDuplicateByFilename(filename);
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to check filename for duplicates', e);
      return null;
    }
  }
  
  /// Phase 2: Check if an IGC file would be a duplicate import (requires parsing)
  Future<Flight?> checkIgcForDuplicate(String filePath) async {
    try {
      return await _igcImportService.checkForDuplicate(filePath);
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to check IGC for duplicates', e);
      return null;
    }
  }
  
  /// Import an IGC file with duplicate handling
  Future<ImportResult> importIgcFile(
    String filePath, {
    bool replaceDuplicate = false,
    bool skipDuplicate = false,
  }) async {
    try {
      LoggingService.debug('FlightProvider: Importing IGC file: $filePath');
      
      final result = await _igcImportService.importIgcFileWithDuplicateHandling(
        filePath,
        replace: replaceDuplicate && !skipDuplicate,
      );
      
      // Reload flights if import was successful
      if (result.type == ImportResultType.imported || 
          result.type == ImportResultType.replaced) {
        await loadFlights();
      }
      
      LoggingService.info('FlightProvider: IGC import completed with status: ${result.type}');
      return result;
    } catch (e) {
      LoggingService.error('FlightProvider: Failed to import IGC file', e);
      return ImportResult.failed(
        fileName: filePath.split('/').last,
        errorMessage: 'Failed to import: $e',
      );
    }
  }
  
  /// Import multiple IGC files
  Future<List<ImportResult>> importMultipleIgcFiles(
    List<String> filePaths, {
    bool skipAllDuplicates = false,
    bool replaceAllDuplicates = false,
  }) async {
    final results = <ImportResult>[];
    
    for (final filePath in filePaths) {
      try {
        final result = await importIgcFile(
          filePath,
          replaceDuplicate: replaceAllDuplicates,
          skipDuplicate: skipAllDuplicates,
        );
        results.add(result);
      } catch (e) {
        results.add(ImportResult.failed(
          fileName: filePath.split('/').last,
          errorMessage: 'Failed to import: $e',
        ));
      }
    }
    
    // Reload flights once after all imports
    if (results.any((r) => 
        r.type == ImportResultType.imported || 
        r.type == ImportResultType.replaced)) {
      await loadFlights();
    }
    
    return results;
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
  
  /// Update sorting configuration
  void setSorting(String column, bool ascending) {
    if (_sortColumn != column || _sortAscending != ascending) {
      _sortColumn = column;
      _sortAscending = ascending;
      _invalidateCache();
      notifyListeners();
    }
  }
  
  /// Invalidate the sorting cache
  void _invalidateCache() {
    _sortedFlightsCache = null;
    _lastSortColumn = null;
    _lastSortAscending = null;
    _lastFlightDataHash = null;
  }
  
  /// Calculate a simple hash of flight data for change detection
  int _calculateFlightDataHash(List<Flight> flights) {
    int hash = flights.length;
    for (int i = 0; i < flights.length && i < 10; i++) {
      hash = hash * 31 + (flights[i].id ?? 0);
    }
    return hash;
  }
  
  /// Sort flights based on current settings
  List<Flight> _getSortedFlights(List<Flight> flights) {
    final sortedFlights = List<Flight>.from(flights);
    
    sortedFlights.sort((a, b) {
      int comparison;
      
      switch (_sortColumn) {
        case 'datetime':
          // Sort by date first, then by launch time
          comparison = a.date.compareTo(b.date);
          if (comparison == 0) {
            comparison = a.launchTime.compareTo(b.launchTime);
          }
          break;
        case 'duration':
          comparison = (a.duration ?? 0).compareTo(b.duration ?? 0);
          break;
        case 'altitude':
          comparison = (a.maxAltitude ?? 0).compareTo(b.maxAltitude ?? 0);
          break;
        case 'distance':
          comparison = (a.straightDistance ?? 0).compareTo(b.straightDistance ?? 0);
          break;
        case 'track_distance':
          comparison = (a.distance ?? 0).compareTo(b.distance ?? 0);
          break;
        case 'launch_site':
          comparison = (a.launchSiteName ?? '').compareTo(b.launchSiteName ?? '');
          break;
        default:
          comparison = 0;
      }
      
      return _sortAscending ? comparison : -comparison;
    });
    
    return sortedFlights;
  }
}