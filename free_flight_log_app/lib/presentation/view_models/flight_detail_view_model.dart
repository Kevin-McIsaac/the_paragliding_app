import 'package:flutter/foundation.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../../data/repositories/flight_repository.dart';
import '../../data/repositories/site_repository.dart';
import '../../data/repositories/wing_repository.dart';
import '../../services/logging_service.dart';

/// View model for flight detail screen
/// Handles all business logic and state management
class FlightDetailViewModel extends ChangeNotifier {
  final FlightRepository _flightRepository;
  final SiteRepository _siteRepository;
  final WingRepository _wingRepository;

  FlightDetailViewModel({
    required FlightRepository flightRepository,
    required SiteRepository siteRepository,
    required WingRepository wingRepository,
  })  : _flightRepository = flightRepository,
        _siteRepository = siteRepository,
        _wingRepository = wingRepository;

  Flight? _flight;
  Site? _launchSite;
  Site? _landingSite;
  Wing? _wing;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  bool _flightModified = false;

  // Getters
  Flight? get flight => _flight;
  Site? get launchSite => _launchSite;
  Site? get landingSite => _landingSite;
  Wing? get wing => _wing;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  bool get flightModified => _flightModified;
  bool get hasError => _errorMessage != null;

  /// Load flight details including related sites and wing
  Future<void> loadFlightDetails(Flight flight) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _flight = flight;

      // Load related data in parallel
      final futures = <Future>[];

      // Load launch site
      if (flight.launchSiteId != null) {
        futures.add(
          _siteRepository.getSite(flight.launchSiteId!).then((site) {
            _launchSite = site;
          }),
        );
      }

      // For now, landing site is the same as launch site
      // TODO: Add landing site support when field is added to Flight model
      _landingSite = _launchSite;

      // Load wing
      if (flight.wingId != null) {
        futures.add(
          _wingRepository.getWing(flight.wingId!).then((wing) {
            _wing = wing;
          }),
        );
      }

      await Future.wait(futures);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      LoggingService.error('FlightDetailViewModel: Error loading flight details', e);
      _errorMessage = 'Failed to load flight details: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update flight notes
  Future<void> updateNotes(String notes) async {
    if (_flight == null) return;

    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _flight = _flight!.copyWith(notes: notes);
      await _flightRepository.updateFlight(_flight!);
      _flightModified = true;
      _isSaving = false;
      notifyListeners();
    } catch (e) {
      LoggingService.error('FlightDetailViewModel: Error updating notes', e);
      _errorMessage = 'Failed to save notes: $e';
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Update launch site
  Future<void> updateLaunchSite(Site site) async {
    if (_flight == null) return;

    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _flight = _flight!.copyWith(
        launchSiteId: site.id,
        launchSiteName: site.name,
      );
      await _flightRepository.updateFlight(_flight!);
      _launchSite = site;
      _flightModified = true;
      _isSaving = false;
      notifyListeners();
    } catch (e) {
      LoggingService.error('FlightDetailViewModel: Error updating launch site', e);
      _errorMessage = 'Failed to update launch site: $e';
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Update landing site
  Future<void> updateLandingSite(Site site) async {
    if (_flight == null) return;

    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // TODO: Add landing site support when field is added to Flight model
      // For now, we can only update landing coordinates
      _flight = _flight!.copyWith(
        landingLatitude: site.latitude,
        landingLongitude: site.longitude,
        landingDescription: site.name,
      );
      await _flightRepository.updateFlight(_flight!);
      _landingSite = site;
      _flightModified = true;
      _isSaving = false;
      notifyListeners();
    } catch (e) {
      LoggingService.error('FlightDetailViewModel: Error updating landing site', e);
      _errorMessage = 'Failed to update landing site: $e';
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Update wing
  Future<void> updateWing(Wing wing) async {
    if (_flight == null) return;

    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _flight = _flight!.copyWith(
        wingId: wing.id,
        // Note: wingName is not stored in Flight model, it's joined from wings table
      );
      await _flightRepository.updateFlight(_flight!);
      _wing = wing;
      _flightModified = true;
      _isSaving = false;
      notifyListeners();
    } catch (e) {
      LoggingService.error('FlightDetailViewModel: Error updating wing', e);
      _errorMessage = 'Failed to update wing: $e';
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Delete the current flight
  Future<bool> deleteFlight() async {
    if (_flight?.id == null) return false;

    try {
      await _flightRepository.deleteFlight(_flight!.id!);
      return true;
    } catch (e) {
      LoggingService.error('FlightDetailViewModel: Error deleting flight', e);
      _errorMessage = 'Failed to delete flight: $e';
      notifyListeners();
      return false;
    }
  }

  /// Reset modification flag
  void resetModificationFlag() {
    _flightModified = false;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}