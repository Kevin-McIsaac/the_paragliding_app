import 'package:flutter/foundation.dart';
import '../data/models/site.dart';
import '../data/repositories/site_repository.dart';
import '../data/services/flight_statistics_service.dart';
import '../services/logging_service.dart';

/// State management for site data
class SiteProvider extends ChangeNotifier {
  // Singleton pattern
  static SiteProvider? _instance;
  static SiteProvider get instance {
    _instance ??= SiteProvider._internal();
    return _instance!;
  }
  
  SiteProvider._internal();
  
  final SiteRepository _repository = SiteRepository.instance;
  final FlightStatisticsService _statisticsService = FlightStatisticsService.instance;

  List<Site> _sites = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<Site> get sites => _sites;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Load all sites from repository
  Future<void> loadSites() async {
    _setLoading(true);
    _clearError();
    
    try {
      LoggingService.debug('SiteProvider: Loading sites from repository');
      final startTime = DateTime.now();
      
      _sites = await _repository.getAllSites();
      
      final duration = DateTime.now().difference(startTime);
      LoggingService.performance('Load sites', duration, '${_sites.length} sites loaded');
      
      LoggingService.info('SiteProvider: Loaded ${_sites.length} sites');
      notifyListeners();
    } catch (e) {
      LoggingService.error('SiteProvider: Failed to load sites', e);
      _setError('Failed to load sites: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Load sites with flight counts from repository
  Future<void> loadSitesWithFlightCounts() async {
    _setLoading(true);
    _clearError();
    
    try {
      LoggingService.debug('SiteProvider: Loading sites with flight counts from repository');
      final startTime = DateTime.now();
      
      _sites = await _repository.getSitesWithFlightCounts();
      
      final duration = DateTime.now().difference(startTime);
      LoggingService.performance('Load sites with flight counts', duration, '${_sites.length} sites loaded');
      
      LoggingService.info('SiteProvider: Loaded ${_sites.length} sites with flight counts');
      notifyListeners();
    } catch (e) {
      LoggingService.error('SiteProvider: Failed to load sites with flight counts', e);
      _setError('Failed to load sites with flight counts: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Add a new site
  Future<bool> addSite(Site site) async {
    _clearError();
    
    try {
      LoggingService.debug('SiteProvider: Adding new site');
      final id = await _repository.insertSite(site);
      
      // Add to local list with the new ID
      final newSite = site.copyWith(id: id);
      _sites.add(newSite);
      
      LoggingService.info('SiteProvider: Added site with ID $id');
      notifyListeners();
      return true;
    } catch (e) {
      LoggingService.error('SiteProvider: Failed to add site', e);
      _setError('Failed to add site: $e');
      return false;
    }
  }

  /// Update an existing site
  Future<bool> updateSite(Site site) async {
    _clearError();
    
    try {
      LoggingService.debug('SiteProvider: Updating site ${site.id}');
      await _repository.updateSite(site);
      
      // Update in local list
      final index = _sites.indexWhere((s) => s.id == site.id);
      if (index >= 0) {
        _sites[index] = site;
        LoggingService.info('SiteProvider: Updated site ${site.id}');
        notifyListeners();
      }
      return true;
    } catch (e) {
      LoggingService.error('SiteProvider: Failed to update site', e);
      _setError('Failed to update site: $e');
      return false;
    }
  }

  /// Delete a site
  Future<bool> deleteSite(int siteId) async {
    _clearError();
    
    try {
      // Check if site can be deleted
      final canDelete = await _repository.canDeleteSite(siteId);
      if (!canDelete) {
        _setError('Cannot delete site - it is used in flight records');
        return false;
      }
      
      LoggingService.debug('SiteProvider: Deleting site $siteId');
      await _repository.deleteSite(siteId);
      
      // Remove from local list
      _sites.removeWhere((s) => s.id == siteId);
      
      LoggingService.info('SiteProvider: Deleted site $siteId');
      notifyListeners();
      return true;
    } catch (e) {
      LoggingService.error('SiteProvider: Failed to delete site', e);
      _setError('Failed to delete site: $e');
      return false;
    }
  }

  /// Find or create a site by name and coordinates
  Future<Site?> findOrCreateSite({
    required String name,
    required double latitude,
    required double longitude,
    double? altitude,
    String? country,
  }) async {
    try {
      LoggingService.debug('SiteProvider: Finding or creating site: $name');
      
      final site = await _repository.findOrCreateSite(
        name: name,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        country: country,
      );
      
      // Add to local list if it's new
      final existingIndex = _sites.indexWhere((s) => s.id == site.id);
      if (existingIndex == -1) {
        _sites.add(site);
        notifyListeners();
      }
      
      LoggingService.info('SiteProvider: Found/created site ${site.id}: $name');
      return site;
    } catch (e) {
      LoggingService.error('SiteProvider: Failed to find/create site', e);
      _setError('Failed to find/create site: $e');
      return null;
    }
  }

  /// Get sites with flight statistics
  Future<List<Map<String, dynamic>>> getSiteStatistics() async {
    try {
      LoggingService.debug('SiteProvider: Loading site statistics');
      return await _statisticsService.getSiteStatistics();
    } catch (e) {
      LoggingService.error('SiteProvider: Failed to load site statistics', e);
      _setError('Failed to load site statistics: $e');
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