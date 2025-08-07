import 'package:flutter/foundation.dart';
import '../data/models/wing.dart';
import '../data/repositories/wing_repository.dart';
import '../data/repositories/flight_repository.dart';
import '../services/logging_service.dart';

/// State management for wing data
class WingProvider extends ChangeNotifier {
  final WingRepository _repository;
  
  WingProvider(this._repository);

  List<Wing> _wings = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<Wing> get wings => _wings;
  List<Wing> get activeWings => _wings.where((w) => w.active).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Load all wings from repository
  Future<void> loadWings() async {
    _setLoading(true);
    _clearError();
    
    try {
      LoggingService.debug('WingProvider: Loading wings from repository');
      final startTime = DateTime.now();
      
      _wings = await _repository.getAllWings();
      
      final duration = DateTime.now().difference(startTime);
      LoggingService.performance('Load wings', duration, '${_wings.length} wings loaded');
      
      LoggingService.info('WingProvider: Loaded ${_wings.length} wings');
      notifyListeners();
    } catch (e) {
      LoggingService.error('WingProvider: Failed to load wings', e);
      _setError('Failed to load wings: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Add a new wing
  Future<bool> addWing(Wing wing) async {
    _clearError();
    
    try {
      LoggingService.debug('WingProvider: Adding new wing');
      final id = await _repository.insertWing(wing);
      
      // Add to local list with the new ID
      final newWing = wing.copyWith(id: id);
      _wings.add(newWing);
      
      LoggingService.info('WingProvider: Added wing with ID $id');
      notifyListeners();
      return true;
    } catch (e) {
      LoggingService.error('WingProvider: Failed to add wing', e);
      _setError('Failed to add wing: $e');
      return false;
    }
  }

  /// Update an existing wing
  Future<bool> updateWing(Wing wing) async {
    _clearError();
    
    try {
      LoggingService.debug('WingProvider: Updating wing ${wing.id}');
      await _repository.updateWing(wing);
      
      // Update in local list
      final index = _wings.indexWhere((w) => w.id == wing.id);
      if (index >= 0) {
        _wings[index] = wing;
        LoggingService.info('WingProvider: Updated wing ${wing.id}');
        notifyListeners();
      }
      return true;
    } catch (e) {
      LoggingService.error('WingProvider: Failed to update wing', e);
      _setError('Failed to update wing: $e');
      return false;
    }
  }

  /// Delete a wing
  Future<bool> deleteWing(int wingId) async {
    _clearError();
    
    try {
      // Check if wing can be deleted
      final canDelete = await _repository.canDeleteWing(wingId);
      if (!canDelete) {
        _setError('Cannot delete wing - it is used in flight records');
        return false;
      }
      
      LoggingService.debug('WingProvider: Deleting wing $wingId');
      await _repository.deleteWing(wingId);
      
      // Remove from local list
      _wings.removeWhere((w) => w.id == wingId);
      
      LoggingService.info('WingProvider: Deleted wing $wingId');
      notifyListeners();
      return true;
    } catch (e) {
      LoggingService.error('WingProvider: Failed to delete wing', e);
      _setError('Failed to delete wing: $e');
      return false;
    }
  }

  /// Deactivate a wing (soft delete)
  Future<bool> deactivateWing(int wingId) async {
    _clearError();
    
    try {
      LoggingService.debug('WingProvider: Deactivating wing $wingId');
      
      final wing = _wings.firstWhere((w) => w.id == wingId);
      final deactivatedWing = wing.copyWith(active: false);
      
      await _repository.updateWing(deactivatedWing);
      
      // Update in local list
      final index = _wings.indexWhere((w) => w.id == wingId);
      if (index >= 0) {
        _wings[index] = deactivatedWing;
        LoggingService.info('WingProvider: Deactivated wing $wingId');
        notifyListeners();
      }
      return true;
    } catch (e) {
      LoggingService.error('WingProvider: Failed to deactivate wing', e);
      _setError('Failed to deactivate wing: $e');
      return false;
    }
  }

  /// Find or create a wing by name and details
  Future<Wing?> findOrCreateWing({
    required String name,
    String? manufacturer,
    String? model,
    String? size,
    String? color,
  }) async {
    try {
      LoggingService.debug('WingProvider: Finding or creating wing: $name');
      
      // Check if wing already exists
      final existingWing = _wings.where((w) => 
        w.name == name &&
        w.manufacturer == manufacturer &&
        w.model == model
      ).firstOrNull;
      
      if (existingWing != null) {
        LoggingService.info('WingProvider: Found existing wing ${existingWing.id}: $name');
        return existingWing;
      }
      
      // Create new wing
      final wing = Wing(
        name: name,
        manufacturer: manufacturer,
        model: model,
        size: size,
        color: color,
        active: true,
      );
      
      final success = await addWing(wing);
      if (success) {
        final createdWing = _wings.last; // Should be the newly added wing
        LoggingService.info('WingProvider: Created wing ${createdWing.id}: $name');
        return createdWing;
      }
      
      return null;
    } catch (e) {
      LoggingService.error('WingProvider: Failed to find/create wing', e);
      _setError('Failed to find/create wing: $e');
      return null;
    }
  }

  /// Get wings with flight statistics
  Future<List<Map<String, dynamic>>> getWingStatistics() async {
    try {
      LoggingService.debug('WingProvider: Loading wing statistics');
      final flightRepository = FlightRepository();
      return await flightRepository.getWingStatistics();
    } catch (e) {
      LoggingService.error('WingProvider: Failed to load wing statistics', e);
      _setError('Failed to load wing statistics: $e');
      return [];
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