import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../data/models/paragliding_site.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/paragliding_earth_api.dart';
import '../services/logging_service.dart';
import '../utils/site_utils.dart';

/// Controller for nearby sites screen business logic
///
/// Extracts all business logic from the UI widget for better separation of concerns
/// and easier testing. Uses ChangeNotifier for simple state management.
class NearbySitesController extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService.instance;
  final LocationService _locationService = LocationService.instance;
  final ParaglidingEarthApi _api = ParaglidingEarthApi.instance;

  // Throttling for notifications
  Timer? _notificationThrottler;
  bool _hasPendingNotification = false;
  static const Duration _notificationDelay = Duration(milliseconds: 100);

  // Consolidated state
  bool _isLoading = false;
  bool _isLocationLoading = false;
  String? _errorMessage;
  Position? _userPosition;
  LatLng? _mapCenter;
  bool _hasUserInteractedWithMap = false; // Track if user has moved the map

  // Sites state
  List<ParaglidingSite> _allSites = [];
  List<ParaglidingSite> _displayedSites = [];
  Map<String, bool> _siteFlightStatus = {};

  // Search state
  String _searchQuery = '';
  List<ParaglidingSite> _searchResults = [];
  bool _isSearching = false;
  ParaglidingSite? _pinnedSite;

  // Loading debouncing
  Timer? _boundsDebouncer;
  LatLngBounds? _lastLoadedBounds;
  bool _sitesLoading = false;

  // Constants
  static const Duration _debounceDelay = Duration(milliseconds: 500);
  static const double _boundsThreshold = 0.01; // ~1km threshold

  // Getters for UI
  bool get isLoading => _isLoading;
  bool get isLocationLoading => _isLocationLoading;
  String? get errorMessage => _errorMessage;
  Position? get userPosition => _userPosition;
  LatLng? get mapCenter => _mapCenter;
  List<ParaglidingSite> get displayedSites => _displayedSites;
  Map<String, bool> get siteFlightStatus => _siteFlightStatus;
  String get searchQuery => _searchQuery;
  List<ParaglidingSite> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  ParaglidingSite? get pinnedSite => _pinnedSite;
  bool get hasSearchResults => _searchResults.isNotEmpty;
  bool get sitesLoading => _sitesLoading;

  /// Initialize the controller
  Future<void> initialize() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Get initial map center (don't wait for current location)
      _mapCenter = await _getInitialMapCenter();

      // Start location request in background
      _updateUserLocation();

      _isLoading = false;
      notifyListeners();

      LoggingService.info('NearbySitesController initialized');
    } catch (e, stackTrace) {
      LoggingService.error('Failed to initialize nearby sites controller', e, stackTrace);
      _errorMessage = 'Failed to initialize: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get user location
  Future<void> _updateUserLocation() async {
    _isLocationLoading = true;
    notifyListeners();

    try {
      final result = await _locationService.getCurrentLocation();
      _userPosition = result.position;

      // Only auto-center map if user hasn't interacted with it yet
      if (!_hasUserInteractedWithMap) {
        _mapCenter = LatLng(result.position.latitude, result.position.longitude);
      }

      _isLocationLoading = false;
      notifyListeners();

      LoggingService.info('User location updated: ${result.statusMessage}');
    } catch (e, stackTrace) {
      LoggingService.error('Failed to get user location', e, stackTrace);
      _isLocationLoading = false;
      notifyListeners();
    }
  }

  /// Refresh user location (clear cache first)
  Future<void> refreshLocation() async {
    _locationService.clearCache();

    // Reset interaction flag to allow auto-centering when user explicitly refreshes
    _hasUserInteractedWithMap = false;

    await _updateUserLocation();

    // Reload sites around new location if available
    if (_userPosition != null) {
      final bounds = _createBoundsAroundPosition(_userPosition!);
      await _loadSitesForBounds(bounds);
    }

    LoggingService.action('NearbySites', 'refresh_location', {});
  }

  /// Handle map bounds change with debouncing
  void onBoundsChanged(LatLngBounds bounds) {
    // Mark that user has interacted with the map to prevent auto-centering
    _hasUserInteractedWithMap = true;

    _boundsDebouncer?.cancel();
    _boundsDebouncer = Timer(_debounceDelay, () {
      _loadSitesForBounds(bounds);
    });
  }

  /// Load sites for given bounds
  Future<void> _loadSitesForBounds(LatLngBounds bounds) async {
    // Check if bounds have changed significantly
    if (_lastLoadedBounds != null && _boundsAreSimilar(bounds, _lastLoadedBounds!)) {
      return;
    }

    if (_sitesLoading) return;

    _sitesLoading = true;
    notifyListeners();

    try {
      final stopwatch = Stopwatch()..start();

      // Load local sites for flight status
      final localSites = await _databaseService.getSitesInBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      );

      // Load API sites using bounding box to get all visible sites
      final apiSites = await _api.getSitesInBounds(
        bounds.north,
        bounds.south,
        bounds.east,
        bounds.west,
        limit: 100,
        detailed: false, // We don't need detailed info for the list view
      );

      // Combine and deduplicate sites
      final allSites = <ParaglidingSite>[];
      final siteStatus = <String, bool>{};

      // Add API sites with flight status
      for (final apiSite in apiSites) {
        final siteKey = SiteUtils.createSiteKey(apiSite.latitude, apiSite.longitude);
        final hasFlights = localSites.any((local) =>
          (local.latitude - apiSite.latitude).abs() < 0.0001 &&
          (local.longitude - apiSite.longitude).abs() < 0.0001);

        siteStatus[siteKey] = hasFlights;
        allSites.add(apiSite);
      }

      // Add local-only sites
      for (final localSite in localSites) {
        final siteKey = SiteUtils.createSiteKey(localSite.latitude, localSite.longitude);
        if (!siteStatus.containsKey(siteKey)) {
          // Create minimal API site from local data
          final apiSite = ParaglidingSite(
            name: localSite.name,
            latitude: localSite.latitude,
            longitude: localSite.longitude,
            altitude: localSite.altitude?.toInt(),
            siteType: 'launch',
            country: localSite.country ?? '',
          );
          siteStatus[siteKey] = true;
          allSites.add(apiSite);
        }
      }

      // Only update and notify if sites actually changed
      final sitesChanged = _sitesListsAreDifferent(_allSites, allSites);
      final statusChanged = !_mapsAreEqual(_siteFlightStatus, siteStatus);

      if (sitesChanged || statusChanged) {
        _allSites = allSites;
        _siteFlightStatus = siteStatus;
        _updateDisplayedSites();
      }
      _lastLoadedBounds = bounds;

      stopwatch.stop();
      LoggingService.structured('SITES_LOADED', {
        'local_count': localSites.length,
        'api_count': apiSites.length,
        'total_count': allSites.length,
        'load_time_ms': stopwatch.elapsedMilliseconds,
      });

    } catch (e, stackTrace) {
      LoggingService.error('Failed to load sites for bounds', e, stackTrace);
    } finally {
      _sitesLoading = false;
      notifyListeners();
    }
  }

  /// Handle search query change
  void onSearchQueryChanged(String query) {
    final newQuery = query.trim();

    // Only update if query actually changed
    if (_searchQuery == newQuery) return;

    _searchQuery = newQuery;

    if (_searchQuery.isEmpty) {
      final stateChanged = _searchResults.isNotEmpty || _pinnedSite != null || _isSearching;
      _searchResults = [];
      _pinnedSite = null;
      _isSearching = false;
      _updateDisplayedSites();

      if (stateChanged) {
        notifyListeners();
      }
      return;
    }

    if (_searchQuery.length < 2) {
      if (_isSearching) {
        _isSearching = false;
        notifyListeners();
      }
      return;
    }

    _performSearch(_searchQuery);
  }

  /// Perform search with debouncing
  Timer? _searchTimer;
  void _performSearch(String query) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () async {
      _isSearching = true;
      notifyListeners();

      try {
        final results = await _api.searchSitesByName(query);
        _searchResults = results.take(15).toList();

        // Auto-select single result
        if (_searchResults.length == 1) {
          _pinnedSite = _searchResults.first;
        }

        _isSearching = false;
        _updateDisplayedSites();
        notifyListeners();

        LoggingService.action('NearbySites', 'search_performed', {
          'query': query,
          'results_count': results.length,
        });

      } catch (e, stackTrace) {
        LoggingService.error('Search failed', e, stackTrace);
        _searchResults = [];
        _isSearching = false;
        notifyListeners();
      }
    });
  }

  /// Select search result
  void selectSearchResult(ParaglidingSite site) {
    _pinnedSite = site;
    _searchQuery = '';
    _searchResults = [];
    _isSearching = false;
    _updateDisplayedSites();
    notifyListeners();

    LoggingService.action('NearbySites', 'search_result_selected', {
      'site_name': site.name,
      'country': site.country,
    });
  }

  /// Update displayed sites based on current state
  void _updateDisplayedSites() {
    List<ParaglidingSite> newDisplayedSites;

    if (_searchQuery.isNotEmpty && _searchResults.isNotEmpty) {
      newDisplayedSites = _searchResults;
    } else if (_pinnedSite != null && _searchQuery.isEmpty) {
      // Show pinned site + nearby sites
      final nearby = _allSites.where((site) => site != _pinnedSite).toList();
      newDisplayedSites = [_pinnedSite!, ...nearby];
    } else {
      newDisplayedSites = _allSites;
    }

    // Only update if the sites actually changed to prevent excessive rebuilds
    if (_sitesListsAreDifferent(_displayedSites, newDisplayedSites)) {
      _displayedSites = newDisplayedSites;
      // Note: notifyListeners() will be called by the parent method when needed
    }
  }

  /// Check if two site lists are different (by content, not reference)
  bool _sitesListsAreDifferent(List<ParaglidingSite> list1, List<ParaglidingSite> list2) {
    if (list1.length != list2.length) return true;

    for (int i = 0; i < list1.length; i++) {
      if (list1[i].name != list2[i].name ||
          list1[i].latitude != list2[i].latitude ||
          list1[i].longitude != list2[i].longitude) {
        return true;
      }
    }
    return false;
  }

  /// Check if two maps are equal by content
  bool _mapsAreEqual<K, V>(Map<K, V> map1, Map<K, V> map2) {
    if (map1.length != map2.length) return false;

    for (final key in map1.keys) {
      if (!map2.containsKey(key) || map1[key] != map2[key]) {
        return false;
      }
    }
    return true;
  }

  /// Get initial map center
  Future<LatLng> _getInitialMapCenter() async {
    try {
      final position = await _locationService.getInitialLocation();
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      LoggingService.error('Failed to get initial map center', e);
      return const LatLng(-31.9505, 115.8605); // Perth fallback
    }
  }

  /// Create bounds around position
  LatLngBounds _createBoundsAroundPosition(Position position) {
    const offset = 0.25; // ~25km
    return LatLngBounds(
      LatLng(position.latitude - offset, position.longitude - offset),
      LatLng(position.latitude + offset, position.longitude + offset),
    );
  }

  /// Check if bounds are similar enough to skip reload
  bool _boundsAreSimilar(LatLngBounds a, LatLngBounds b) {
    return (a.north - b.north).abs() < _boundsThreshold &&
           (a.south - b.south).abs() < _boundsThreshold &&
           (a.east - b.east).abs() < _boundsThreshold &&
           (a.west - b.west).abs() < _boundsThreshold;
  }

  /// Jump to site location
  LatLngBounds getBoundsForSite(ParaglidingSite site) {
    const offset = 0.05; // ~5km around site
    return LatLngBounds(
      LatLng(site.latitude - offset, site.longitude - offset),
      LatLng(site.latitude + offset, site.longitude + offset),
    );
  }

  /// Throttled notification to prevent excessive rebuilds
  void _throttledNotifyListeners() {
    if (_notificationThrottler?.isActive == true) {
      _hasPendingNotification = true;
      return;
    }

    _notificationThrottler = Timer(_notificationDelay, () {
      super.notifyListeners();
      if (_hasPendingNotification) {
        _hasPendingNotification = false;
        _throttledNotifyListeners(); // Handle pending notification
      }
    });
  }

  @override
  void notifyListeners() {
    _throttledNotifyListeners();
  }

  @override
  void dispose() {
    _boundsDebouncer?.cancel();
    _searchTimer?.cancel();
    _notificationThrottler?.cancel();
    super.dispose();
  }
}