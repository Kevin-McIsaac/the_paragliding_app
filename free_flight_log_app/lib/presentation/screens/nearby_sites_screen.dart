import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/airspace_enums.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/flyability_status.dart';
import '../../services/location_service.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';
import '../../services/nearby_sites_search_state.dart';
import '../../services/nearby_sites_search_manager_v2.dart';
import '../../services/map_bounds_manager.dart';
import '../../services/weather_service.dart';
import '../../utils/map_provider.dart';
import '../../utils/site_utils.dart';
import '../../utils/site_marker_utils.dart';
import '../../utils/preferences_helper.dart';
import '../widgets/nearby_sites_map.dart';
import '../widgets/map_filter_dialog.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/map_loading_overlay.dart';
import '../widgets/wind_rose_widget.dart';
import '../../services/openaip_service.dart';


class NearbySitesScreen extends StatefulWidget {
  const NearbySitesScreen({super.key});

  @override
  State<NearbySitesScreen> createState() => _NearbySitesScreenState();
}

class _NearbySitesScreenState extends State<NearbySitesScreen> {
  final LocationService _locationService = LocationService.instance;
  final MapController _mapController = MapController();

  // Sites state - using ParaglidingSite directly (no more UnifiedSite)
  List<ParaglidingSite> _allSites = [];
  List<ParaglidingSite> _displayedSites = [];
  Map<String, bool> _siteFlightStatus = {}; // Key: "lat,lng", Value: hasFlights
  Position? _userPosition;
  bool _isLoading = false;
  bool _isLocationLoading = false;
  String? _errorMessage;
  LatLng? _mapCenterPosition;
  final double _mapZoom = 10.0; // Dynamic zoom level for map
  
  // Key to force map widget refresh when airspace settings change
  final Key _mapWidgetKey = UniqueKey();
  static const String _mapProviderKey = 'nearby_sites_map_provider';

  // Preference keys for filter states
  static const String _sitesEnabledKey = 'nearby_sites_sites_enabled';
  static const String _airspaceEnabledKey = 'nearby_sites_airspace_enabled';
  static const String _forecastEnabledKey = 'nearby_sites_forecast_enabled';
  
  // Bounds-based loading state using MapBoundsManager
  LatLngBounds? _currentBounds;
  
  // Search management - consolidated into SearchManager

  // Location notification state
  bool _showLocationNotification = false;
  Timer? _locationNotificationTimer;
  late final NearbySitesSearchManagerV2 _searchManager;

  // Search bar controller (persistent to fix backwards text issue)
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isUpdatingFromTextField = false;

  // Filter state for sites and airspace (defaults, will be loaded from preferences)
  bool _sitesEnabled = true; // Controls site loading and display
  bool _airspaceEnabled = true; // Controls airspace loading and display
  bool _forecastEnabled = true; // Controls wind forecast fetching and display
  bool _hasActiveFilters = false; // Cached value to avoid FutureBuilder rebuilds
  double _maxAltitudeFt = 10000.0; // Default altitude filter
  Map<IcaoClass, bool> _excludedIcaoClasses = {}; // Current ICAO class filter state
  final OpenAipService _openAipService = OpenAipService.instance;

  // Wind forecast state
  DateTime _selectedDateTime = DateTime.now();
  final Map<String, WindData> _siteWindData = {};
  final Map<String, FlyabilityStatus> _siteFlyabilityStatus = {};
  double _maxWindSpeed = 25.0;
  double _maxWindGusts = 30.0;
  bool _isWindBarExpanded = false; // Default to collapsed
  bool _isWindLoading = false; // Track wind data fetch status
  final WeatherService _weatherService = WeatherService.instance;
  static const String _windBarExpandedKey = 'nearby_sites_wind_bar_expanded';
  Timer? _windFetchDebounce;

  @override
  void initState() {
    super.initState();
    _initializeSearchManager();
    _loadPreferences();
    _loadFilterSettings();
    _loadWindPreferences();
    _updateActiveFiltersState(); // Initialize the cached active filters state
    _loadData();

    // Listen to search state changes to update controller
    _searchController.text = _searchManager.state.query;
  }

  @override
  void dispose() {
    MapBoundsManager.instance.cancelDebounce('nearby_sites'); // Clean up any pending debounce
    _locationNotificationTimer?.cancel(); // Clean up location notification timer
    _windFetchDebounce?.cancel(); // Clean up wind fetch debounce timer
    _searchManager.dispose(); // Clean up search manager
    _searchController.dispose(); // Dispose search controller
    _searchFocusNode.dispose(); // Dispose search focus node
    _mapController.dispose(); // Dispose map controller
    super.dispose();
  }

  void _initializeSearchManager() {
    _searchManager = NearbySitesSearchManagerV2(
      onStateChanged: (SearchState state) {
        setState(() {
          // Update displayed sites when search state changes
          _updateDisplayedSites();

          // Only update search controller if the change came from outside the TextField
          if (!_isUpdatingFromTextField && _searchController.text != state.query) {
            _searchController.text = state.query;
            // Move cursor to end
            _searchController.selection = TextSelection.fromPosition(
              TextPosition(offset: state.query.length),
            );
          }
        });
      },
      onAutoJump: (ParaglidingSite site) {
        _jumpToLocation(site, keepSearchActive: true);
      },
    );
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProviderName = prefs.getString(_mapProviderKey);
      final sitesEnabled = prefs.getBool(_sitesEnabledKey) ?? true;
      final airspaceEnabled = prefs.getBool(_airspaceEnabledKey) ?? true;
      final forecastEnabled = prefs.getBool(_forecastEnabledKey) ?? true;

      MapProvider selectedProvider = MapProvider.openStreetMap;
      if (savedProviderName != null) {
        selectedProvider = MapProvider.values.firstWhere(
          (p) => p.name == savedProviderName,
          orElse: () => MapProvider.openStreetMap,
        );
      }

      if (mounted) {
        setState(() {
          _sitesEnabled = sitesEnabled;
          _airspaceEnabled = airspaceEnabled;
          _forecastEnabled = forecastEnabled;
        });
      }
    } catch (e) {
      LoggingService.error('Failed to load preferences', e);
    }
  }

  Future<void> _loadFilterSettings() async {
    try {
      final icaoClasses = await _openAipService.getExcludedIcaoClasses();
      if (mounted) {
        setState(() {
          _excludedIcaoClasses = icaoClasses;
        });
      }
    } catch (e) {
      LoggingService.error('Failed to load filter settings', e);
    }
  }

  Future<void> _loadWindPreferences() async {
    try {
      _maxWindSpeed = await PreferencesHelper.getMaxWindSpeed();
      _maxWindGusts = await PreferencesHelper.getMaxWindGusts();

      // Load wind bar expanded state (default to collapsed)
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isWindBarExpanded = prefs.getBool(_windBarExpandedKey) ?? false;
      });
    } catch (e) {
      LoggingService.error('Failed to load wind preferences', e);
    }
  }

  Future<void> _showDateTimePicker() async {
    // Show date picker (max 7 days future)
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );

    if (date != null && mounted) {
      // Show time picker
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
      );

      if (time != null && mounted) {
        setState(() {
          _selectedDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
        _fetchWindDataForSites();
      }
    }
  }

  Future<void> _fetchWindDataForSites() async {
    // Skip fetching if sites or forecast are disabled
    if (!_sitesEnabled || !_forecastEnabled) {
      LoggingService.info('Skipping wind fetch: sites or forecast disabled');
      return;
    }

    if (_displayedSites.isEmpty) {
      LoggingService.info('Skipping wind fetch: no displayed sites');
      return;
    }

    // Cancel any pending debounced fetch
    _windFetchDebounce?.cancel();

    // Only fetch wind data if zoom level is high enough (≥10)
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom < 10) {
      LoggingService.info('Skipping wind fetch: zoom level $currentZoom < 10');
      // Mark sites as unknown if they don't have wind data
      setState(() {
        for (final site in _displayedSites) {
          final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
          if (!_siteWindData.containsKey(key)) {
            _siteFlyabilityStatus[key] = FlyabilityStatus.unknown;
          }
        }
      });
      return;
    }

    LoggingService.info('Wind fetch triggered at zoom $currentZoom, starting debounce timer');

    // Debounce wind fetches to avoid rapid API calls on map movement
    _windFetchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      setState(() {
        _isWindLoading = true;
        // Mark all sites as loading
        for (final site in _displayedSites) {
          final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
          if (!_siteWindData.containsKey(key)) {
            _siteFlyabilityStatus[key] = FlyabilityStatus.loading;
          }
        }
      });

      try {
        // Build list of locations to fetch (deduplicate by lat/lon)
        final locationsToFetch = <LatLng>[];
        final seenKeys = <String>{};

        for (final site in _displayedSites) {
          final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            locationsToFetch.add(LatLng(site.latitude, site.longitude));
          }
        }

        LoggingService.structured('WIND_FETCH_START', {
          'total_sites': _displayedSites.length,
          'unique_locations': locationsToFetch.length,
          'zoom_level': currentZoom,
        });

        // Fetch wind data in batch
        final windDataResults = await _weatherService.getWindDataBatch(
          locationsToFetch,
          _selectedDateTime,
        );

        if (!mounted) return;

        // Update wind data map and flyability status with setState for immediate UI update
        setState(() {
          _isWindLoading = false;
          _siteWindData.addAll(windDataResults);
          // Force recalculation because we have fresh wind data
          _updateFlyabilityStatus(forceRecalculation: true);
        });

        LoggingService.structured('WIND_DATA_FETCHED', {
          'sites_count': _displayedSites.length,
          'fetched_count': windDataResults.length,
          'time': _selectedDateTime.toIso8601String(),
          'zoom_level': currentZoom,
        });
      } catch (e, stackTrace) {
        LoggingService.error('Failed to fetch wind data', e, stackTrace);
        if (mounted) {
          setState(() {
            _isWindLoading = false;
            // Mark failed sites as unknown
            for (final site in _displayedSites) {
              final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
              if (!_siteWindData.containsKey(key)) {
                _siteFlyabilityStatus[key] = FlyabilityStatus.unknown;
              }
            }
          });
        }
      }
    });
  }

  /// Check if any displayed site is missing wind data
  bool _hasMissingWindData({bool includeUnknownStatus = false}) {
    return _displayedSites.any((site) {
      final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
      if (includeUnknownStatus) {
        // Missing if: no wind data OR status is unknown/loading OR no status at all
        final hasWindData = _siteWindData.containsKey(key);
        final status = _siteFlyabilityStatus[key];
        final isMissing = !hasWindData ||
               status == FlyabilityStatus.unknown ||
               status == FlyabilityStatus.loading ||
               !_siteFlyabilityStatus.containsKey(key);
        LoggingService.debug('Site ${site.name}: hasWindData=$hasWindData, status=$status, isMissing=$isMissing');
        return isMissing;
      }
      return !_siteWindData.containsKey(key) && !_siteFlyabilityStatus.containsKey(key);
    });
  }

  /// Calculate flyability status for all displayed sites
  ///
  /// Uses intelligent caching to avoid redundant calculations:
  /// - Only recalculates sites that don't have cached status (unless forced)
  /// - Preserves existing cache entries for unchanged sites
  /// - Provides summary logging for performance tracking
  void _updateFlyabilityStatus({bool forceRecalculation = false}) {
    int calculated = 0;
    int flyable = 0;
    int notFlyable = 0;
    int unknown = 0;

    for (final site in _displayedSites) {
      final key = SiteUtils.createSiteKey(site.latitude, site.longitude);

      // Skip if already calculated and not forcing recalc
      if (!forceRecalculation && _siteFlyabilityStatus.containsKey(key)) {
        // Count existing status for summary
        final status = _siteFlyabilityStatus[key];
        if (status == FlyabilityStatus.flyable) {
          flyable++;
        } else if (status == FlyabilityStatus.notFlyable) {
          notFlyable++;
        } else {
          unknown++;
        }
        continue;
      }

      calculated++;
      final wind = _siteWindData[key];

      if (wind == null) {
        _siteFlyabilityStatus[key] = FlyabilityStatus.unknown;
        unknown++;
      } else if (site.windDirections.isEmpty) {
        _siteFlyabilityStatus[key] = FlyabilityStatus.unknown;
        unknown++;
      } else {
        final isFlyable = wind.isFlyable(
          site.windDirections,
          _maxWindSpeed,
          _maxWindGusts,
        );
        _siteFlyabilityStatus[key] = isFlyable
            ? FlyabilityStatus.flyable
            : FlyabilityStatus.notFlyable;

        if (isFlyable) {
          flyable++;
        } else {
          notFlyable++;
        }
      }
    }

    // Summary logging for Claude analysis
    if (calculated > 0 || forceRecalculation) {
      LoggingService.structured('FLYABILITY_UPDATE', {
        'total_sites': _displayedSites.length,
        'recalculated': calculated,
        'flyable': flyable,
        'not_flyable': notFlyable,
        'unknown': unknown,
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final stopwatch = Stopwatch()..start();
      
      // Start location request in background - don't wait for it
      _updateUserLocation();
      
      // Set initial map center based on user's flight sites
      _mapCenterPosition = await _getInitialMapCenter();
      
      // Sites will be loaded dynamically via bounds-based loading
      // Initialize empty structure
      _allSites = [];
      _displayedSites = [];
      _siteFlightStatus = {};
      
      stopwatch.stop();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        LoggingService.performance(
          'Load Nearby Sites Data',
          Duration(milliseconds: stopwatch.elapsedMilliseconds),
          'Initialized for bounds-based loading',
        );
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to load nearby sites data', e, stackTrace);
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load sites: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<Position?> _updateUserLocation() async {
    if (!mounted) return null;

    setState(() {
      _isLocationLoading = true;
    });

    try {
      final position = await _locationService.getCurrentPosition();
      if (mounted) {
        setState(() {
          _userPosition = position;
          _isLocationLoading = false;
        });

        // Update map center to user position when location is acquired
        if (position != null) {
          _mapCenterPosition = LatLng(position.latitude, position.longitude);
          // Hide location notification if location was successfully obtained
          _hideLocationNotification();
        }
        _updateDisplayedSites();
        return position;
      }
      return null;
    } catch (e, stackTrace) {
      LoggingService.error('Failed to get user location', e, stackTrace);
      if (mounted) {
        setState(() {
          _isLocationLoading = false;
        });
        // Show auto-dismissing notification when location fails
        _showLocationNotificationBriefly();
      }
      return null;
    }
  }

  /// Show location notification briefly and auto-dismiss after 4 seconds
  void _showLocationNotificationBriefly() {
    // Cancel any existing timer
    _locationNotificationTimer?.cancel();

    if (mounted) {
      setState(() {
        _showLocationNotification = true;
      });

      // Auto-dismiss after 4 seconds
      _locationNotificationTimer = Timer(const Duration(seconds: 4), () {
        _hideLocationNotification();
      });
    }
  }

  /// Hide location notification
  void _hideLocationNotification() {
    _locationNotificationTimer?.cancel();
    _locationNotificationTimer = null;

    if (mounted) {
      setState(() {
        _showLocationNotification = false;
      });
    }
  }

  /// Get initial map center based on last known location or fallback
  Future<LatLng> _getInitialMapCenter() async {
    try {
      // Use location service fallback hierarchy
      final position = await LocationService.instance.getLastKnownOrDefault();
      LoggingService.info('Using position from LocationService fallback hierarchy');
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      LoggingService.error('Failed to get position from LocationService', e);
      // Final fallback to Perth if everything fails
      LoggingService.info('Using final Perth fallback');
      return const LatLng(-31.9505, 115.8605);
    }
  }


  void _updateDisplayedSites() {
    // Skip all site processing if sites are disabled
    if (!_sitesEnabled) {
      // Clear displayed sites to ensure UI is consistent
      if (mounted) {
        setState(() {
          _displayedSites = [];
        });
      }
      return;
    }

    final stopwatch = Stopwatch()..start();

    // Sites are already ParaglidingSite objects - no conversion needed!

    // Use SearchManager's computed property for cleaner logic
    List<ParaglidingSite> filteredSites = _searchManager.getDisplayedSites(_allSites);
    
    // Add pinned site if we have one and it's not already in the list
    final pinnedSite = _searchManager.state.pinnedSite;
    if (pinnedSite != null && _searchManager.state.query.isEmpty) {
      final pinnedSiteKey = SiteUtils.createSiteKey(pinnedSite.latitude, pinnedSite.longitude);
      final alreadyExists = filteredSites.any((site) => 
        SiteUtils.createSiteKey(site.latitude, site.longitude) == pinnedSiteKey);
      
      if (!alreadyExists) {
        filteredSites = List.from(filteredSites);
        filteredSites.insert(0, pinnedSite); // Add at beginning for prominence
      }
    }
    
    // Sites are loaded via bounds-based filtering, no distance filtering needed
    
    stopwatch.stop();

    if (mounted) {
      setState(() {
        _displayedSites = filteredSites;
      });
    }
    
    // Count flown vs new sites for logging
    final flownSites = filteredSites.where((site) {
      final siteKey = SiteUtils.createSiteKey(site.latitude, site.longitude);
      return _siteFlightStatus[siteKey] ?? false;
    }).length;
    final newSites = filteredSites.length - flownSites;
    
    LoggingService.structured('NEARBY_SITES_FILTERED', {
      'total_local_sites': flownSites,
      'total_api_sites': newSites,
      'displayed_local_sites': flownSites,
      'displayed_api_sites': newSites,
      'search_query': _searchManager.state.query.isEmpty ? null : _searchManager.state.query,
      'has_user_position': _userPosition != null,
      'filter_time_ms': stopwatch.elapsedMilliseconds,
    });
  }


  void _onRefreshLocation() async {
    LoggingService.action('NearbySites', 'refresh_location', {});
    _locationService.clearCache();
    final position = await _updateUserLocation();
    
    // Trigger bounds loading for the user's location area
    if (position != null) {
      final userLocation = LatLng(position.latitude, position.longitude);
      final bounds = LatLngBounds(
        LatLng(userLocation.latitude - 0.5, userLocation.longitude - 0.5),
        LatLng(userLocation.latitude + 0.5, userLocation.longitude + 0.5),
      );
      
      // Use a short delay to allow the map to update its center
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _onBoundsChanged(bounds);
        }
      });
    } else {
      // Fallback if location couldn't be obtained
      _updateDisplayedSites();
    }
  }

  void _onSiteSelected(ParaglidingSite site) {
    final siteKey = SiteUtils.createSiteKey(site.latitude, site.longitude);
    final hasFlights = _siteFlightStatus[siteKey] ?? false;

    // Debug logging for site 21842
    if (site.id == 21842) {
      LoggingService.debug('_onSiteSelected for site 21842: windDirections=${site.windDirections}');
    }

    LoggingService.action('NearbySites', hasFlights ? 'flown_site_selected' : 'new_site_selected', {
      'site_id': site.id,
      'site_name': site.name,
      'site_type': site.siteType,
      'rating': site.rating,
      'has_flights': hasFlights,
    });
    _showSiteDetailsDialog(paraglidingSite: site);
  }

  // Callback for search result selection (prevents creating new function on every build)
  void _onSearchResultSelected(ParaglidingSite site) {
    _searchManager.selectSearchResult(site);
    // Also jump to location for smooth UX
    _jumpToLocation(site);
  }



  /// Jump to a location without dismissing search results
  void _jumpToLocation(ParaglidingSite site, {bool keepSearchActive = false}) {
    // Create exact bounds for API search (±0.05 degrees)
    final newCenter = LatLng(site.latitude, site.longitude);
    final bounds = LatLngBounds(
      LatLng(newCenter.latitude - 0.05, newCenter.longitude - 0.05),
      LatLng(newCenter.latitude + 0.05, newCenter.longitude + 0.05),
    );

    // Update state for initial position (in case widget rebuilds)
    setState(() {
      _mapCenterPosition = newCenter;
    });

    // Use the MapController to move the map
    _mapController.move(newCenter, 14.0);

    // Trigger bounds changed callback after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _onBoundsChanged(bounds);
      }
    });

    LoggingService.action('NearbySites', 'location_jumped', {
      'site_name': site.name,
      'country': site.country,
      'keep_search_active': keepSearchActive,
    });
  }


  // Bounds-based loading methods (copied from EditSiteScreen)
  void _onBoundsChanged(LatLngBounds bounds) {
    final currentZoom = _mapController.camera.zoom;
    LoggingService.debug('_onBoundsChanged called: zoom=$currentZoom');

    // Skip bounds processing if sites are disabled
    if (!_sitesEnabled) {
      LoggingService.debug('Sites disabled, skipping bounds change');
      return;
    }

    // Check if bounds have changed significantly using MapBoundsManager
    if (!MapBoundsManager.instance.haveBoundsChangedSignificantly('nearby_sites', bounds, _currentBounds)) {
      LoggingService.debug('Bounds have not changed significantly, skipping load');
      return;
    }

    _currentBounds = bounds;
    LoggingService.info('Bounds changed significantly, loading sites at zoom=$currentZoom');

    // Use MapBoundsManager for debounced loading with caching
    MapBoundsManager.instance.loadSitesForBoundsDebounced(
      context: 'nearby_sites',
      bounds: bounds,
      zoomLevel: _mapController.camera.zoom,
      onLoaded: (result) {
        if (mounted) {
          setState(() {
            _allSites = result.sites;
            _siteFlightStatus = {};

            // Clean up stale flyability status and wind data for sites no longer visible
            final currentSiteKeys = result.sites.map((site) => SiteUtils.createSiteKey(site.latitude, site.longitude)).toSet();
            _siteFlyabilityStatus.removeWhere((key, value) => !currentSiteKeys.contains(key));
            _siteWindData.removeWhere((key, value) => !currentSiteKeys.contains(key));

            for (final site in result.sites) {
              final siteKey = SiteUtils.createSiteKey(site.latitude, site.longitude);
              _siteFlightStatus[siteKey] = site.hasFlights;
            }
            _updateDisplayedSites();
          });

          LoggingService.structured('NEARBY_SITES_LOADED', {
            'sites_count': result.sites.length,
            'flown_sites': result.sitesWithFlights.length,
            'new_sites': result.sitesWithoutFlights.length,
            'from_cache': MapBoundsManager.instance.areBoundsAlreadyLoaded('nearby_sites', bounds),
          });

          // Auto-fetch wind data when sites are loaded for the first time
          // or when navigating to new sites that don't have wind data
          // Use a short delay to ensure _displayedSites is fully updated
          Future.delayed(const Duration(milliseconds: 50), () {
            if (!mounted) return;
            if (_displayedSites.isNotEmpty && (_hasMissingWindData() || _siteWindData.isEmpty)) {
              _fetchWindDataForSites();
            }
          });
        }
      },
      siteLimit: 50,
      includeFlightCounts: true,
    ).then((_) {
      // Loading completed - also check for missing wind data
      // This handles the case when sites come from cache and onLoaded isn't called
      LoggingService.info('Bounds load completed, checking for missing wind data after animation delay');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) {
          LoggingService.info('Not mounted, skipping wind check');
          return;
        }
        // Capture zoom AFTER delay, when cluster zoom animation is complete
        final currentZoom = _mapController.camera.zoom;
        LoggingService.info('Wind check: sites=${_displayedSites.length}, zoom=$currentZoom');

        if (_displayedSites.isNotEmpty && currentZoom >= 10) {
          final missingWindData = _hasMissingWindData(includeUnknownStatus: true);
          LoggingService.info('Missing wind data check: $missingWindData');
          if (missingWindData) {
            LoggingService.info('Triggering wind fetch after bounds load completion');
            _fetchWindDataForSites();
          }
        }
      });
    }).catchError((error) {
      LoggingService.error('Failed to load sites for bounds', error);
    });
  }




  void _showSiteDetailsDialog({required ParaglidingSite paraglidingSite}) {
    // Get wind data for this site
    final windKey = SiteUtils.createSiteKey(paraglidingSite.latitude, paraglidingSite.longitude);
    final windData = _siteWindData[windKey];

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (context) => _SiteDetailsDialog(
        site: null,
        paraglidingSite: paraglidingSite,
        userPosition: _userPosition,
        windData: windData,
        onWindDataFetched: (fetchedWindData) {
          // Update parent's cache when dialog fetches wind data
          setState(() {
            _siteWindData[windKey] = fetchedWindData;
            _updateFlyabilityStatus(forceRecalculation: true);
          });
        },
      ),
    );
  }

  /// Show map filter dialog
  void _showMapFilterDialog() async {
    try {
      // Get current filter states
      final airspaceTypesEnum = await _openAipService.getExcludedAirspaceTypes();
      final icaoClassesEnum = await _openAipService.getExcludedIcaoClasses();
      final clippingEnabled = await _openAipService.isClippingEnabled();

      // Convert enum maps to string maps for dialog
      final airspaceTypes = <String, bool>{
        for (final entry in airspaceTypesEnum.entries)
          entry.key.abbreviation: entry.value
      };
      final icaoClasses = <String, bool>{
        for (final entry in icaoClassesEnum.entries)
          entry.key.abbreviation: entry.value
      };

      if (!mounted) return;

      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (context) => _DraggableFilterDialog(
          sitesEnabled: _sitesEnabled,
          airspaceEnabled: _airspaceEnabled,
          forecastEnabled: _forecastEnabled,
          airspaceTypes: airspaceTypes,
          icaoClasses: icaoClasses,
          maxAltitudeFt: _maxAltitudeFt,
          clippingEnabled: clippingEnabled,
          onApply: _handleFilterApply,
        ),
      );
    } catch (error, stackTrace) {
      LoggingService.error('Failed to show map filter dialog', error, stackTrace);
    }
  }

  // Update the cached active filters state
  void _updateActiveFiltersState() async {
    try {
      final types = await _openAipService.getExcludedAirspaceTypes();
      final classes = await _openAipService.getExcludedIcaoClasses();

      // Consider filters active if any type/class is disabled or sites/forecast are disabled
      final hasDisabledTypes = types.values.contains(false);
      final hasDisabledClasses = classes.values.contains(false);

      setState(() {
        _hasActiveFilters = !_sitesEnabled || !_forecastEnabled || hasDisabledTypes || hasDisabledClasses;
      });
    } catch (e) {
      LoggingService.error('Failed to update active filters state', e);
    }
  }

  /// Handle filter apply from dialog
  void _handleFilterApply(bool sitesEnabled, bool airspaceEnabled, bool forecastEnabled, Map<String, bool> types, Map<String, bool> classes, double maxAltitudeFt, bool clippingEnabled) async {
    try {
      // Update filter states
      final previousSitesEnabled = _sitesEnabled;
      final previousAirspaceEnabled = _airspaceEnabled;
      final previousForecastEnabled = _forecastEnabled;

      setState(() {
        _sitesEnabled = sitesEnabled;
        _airspaceEnabled = airspaceEnabled;
        _forecastEnabled = forecastEnabled;
        _maxAltitudeFt = maxAltitudeFt;
      });

      // Save the enabled states to preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sitesEnabledKey, sitesEnabled);
      await prefs.setBool(_airspaceEnabledKey, airspaceEnabled);
      await prefs.setBool(_forecastEnabledKey, forecastEnabled);

      // Handle sites visibility changes
      if (!sitesEnabled && previousSitesEnabled) {
        // Sites were disabled - clear displayed sites and reset the bounds key
        setState(() {
          _displayedSites.clear();
          _allSites.clear();
        });
        // Clear cache so sites reload when re-enabled
        MapBoundsManager.instance.clearCache('nearby_sites');
        LoggingService.action('MapFilter', 'sites_disabled', {'cleared_sites_count': _displayedSites.length});
      } else if (sitesEnabled && !previousSitesEnabled) {
        // Sites were enabled - reload sites for current bounds or trigger map refresh
        if (_currentBounds != null) {
          // Force reload using MapBoundsManager
          MapBoundsManager.instance.clearCache('nearby_sites');
          if (_currentBounds != null) {
            _onBoundsChanged(_currentBounds!);
          }
        }
        LoggingService.action('MapFilter', 'sites_enabled', {'reloading_sites': true, 'has_bounds': _currentBounds != null});
      }

      // Handle forecast visibility changes
      if (!forecastEnabled && previousForecastEnabled) {
        // Forecast was disabled - clear wind data and flyability status
        setState(() {
          _siteWindData.clear();
          _siteFlyabilityStatus.clear();
        });
        LoggingService.action('MapFilter', 'forecast_disabled', {'cleared_wind_data': true});
      } else if (forecastEnabled && !previousForecastEnabled) {
        // Forecast was enabled - fetch wind data for visible sites if zoomed in
        final currentZoom = _mapController.camera.zoom;
        if (_displayedSites.isNotEmpty && currentZoom >= 10) {
          _fetchWindDataForSites();
        }
        LoggingService.action('MapFilter', 'forecast_enabled', {'will_fetch': currentZoom >= 10});
      }

      // Handle airspace visibility changes
      if (airspaceEnabled) {
        // Convert string maps back to enum maps
        final typesEnum = <AirspaceType, bool>{
          for (final entry in types.entries)
            AirspaceType.values.where((t) => t.abbreviation == entry.key).firstOrNull ?? AirspaceType.other: entry.value
        };
        final classesEnum = <IcaoClass, bool>{
          for (final entry in classes.entries)
            IcaoClass.values.where((c) => c.abbreviation == entry.key).firstOrNull ?? IcaoClass.none: entry.value
        };

        // Enable airspace and update filters
        await _openAipService.setAirspaceEnabled(true);
        await _openAipService.setExcludedAirspaceTypes(typesEnum);
        await _openAipService.setExcludedIcaoClasses(classesEnum);
        await _openAipService.setClippingEnabled(clippingEnabled);

        // Update local state for immediate UI updates
        setState(() {
          _excludedIcaoClasses = classesEnum;
        });

        if (!previousAirspaceEnabled) {
          LoggingService.action('MapFilter', 'airspace_enabled');
        }
      } else if (!airspaceEnabled) {
        // Disable airspace completely
        await _openAipService.setAirspaceEnabled(false);

        // Note: We preserve _excludedIcaoClasses in memory so filters are retained
        // when airspace is re-enabled. This provides better UX for quick toggles.

        if (previousAirspaceEnabled) {
          LoggingService.action('MapFilter', 'airspace_disabled', {
            'preserved_filter_count': _excludedIcaoClasses.values.where((v) => v).length,
            'filters_preserved': true,
          });
        }
      }


      // Refresh map to apply airspace filter changes
      setState(() {
        // This preserves the map position and zoom level
      });

      LoggingService.structured('MAP_FILTER_APPLIED_SUCCESS', {
        'sites_enabled': sitesEnabled,
        'airspace_enabled': airspaceEnabled,
        'sites_changed': sitesEnabled != previousSitesEnabled,
        'airspace_changed': airspaceEnabled != previousAirspaceEnabled,
        'selected_types': types.values.where((v) => v).length,
        'selected_classes': classes.values.where((v) => v).length,
        'max_altitude_ft': maxAltitudeFt,
      });

      // Update the cached active filters state
      _updateActiveFiltersState();
    } catch (error, stackTrace) {
      LoggingService.error('Failed to apply map filters', error, stackTrace);
    }
  }

  Widget _buildSearchResults() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: _searchManager.state.isSearching
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              itemCount: _searchManager.state.results.length,
              itemBuilder: (context, index) {
                final site = _searchManager.state.results[index];
                return ListTile(
                  leading: Icon(
                    Icons.location_on,
                    color: site.hasFlights ? Colors.blue : Colors.deepPurple,
                  ),
                  title: Text(site.name),
                  subtitle: Text(
                    site.hasFlights
                        ? '${site.flightCount} flights'
                        : 'New site',
                  ),
                  onTap: () => _onSearchResultSelected(site),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: (value) {
              _isUpdatingFromTextField = true;
              _searchManager.onSearchQueryChanged(value);
              _isUpdatingFromTextField = false;
            },
            style: const TextStyle(fontSize: 16, color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search nearby sites...',
              hintStyle: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.7)),
              prefixIcon: const Icon(Icons.search, size: 20, color: Colors.white),
              suffixIcon: _searchManager.state.query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: Colors.white),
                      onPressed: () {
                        _isUpdatingFromTextField = true;
                        _searchController.clear();
                        _searchManager.onSearchQueryChanged('');
                        _isUpdatingFromTextField = false;
                      },
                      padding: EdgeInsets.zero,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.access_time),
            onPressed: _showDateTimePicker,
            tooltip: 'Wind Forecast Time',
          ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _hasActiveFilters ? Colors.orange : null,
            ),
            onPressed: _showMapFilterDialog,
            tooltip: 'Map Filters',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? AppErrorState(
                    message: _errorMessage!,
                    onRetry: _loadData,
                  )
                : Stack(
                      children: [
                        // Map - using new BaseMapWidget-based implementation
                        NearbySitesMap(
                          key: _mapWidgetKey, // Force rebuild when settings change
                          mapController: _mapController,
                          sites: _displayedSites,
                          userLocation: _userPosition != null
                              ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
                              : null,
                          airspaceEnabled: _airspaceEnabled,
                          maxAltitudeFt: _maxAltitudeFt,
                          onSiteSelected: _onSiteSelected,
                          onLocationRequest: _onRefreshLocation,
                          siteWindData: _siteWindData,
                          siteFlyabilityStatus: _siteFlyabilityStatus,
                          maxWindSpeed: _maxWindSpeed,
                          maxWindGusts: _maxWindGusts,
                          selectedDateTime: _selectedDateTime,
                          forecastEnabled: _forecastEnabled,
                          onBoundsChanged: _onBoundsChanged,
                          showUserLocation: true,
                          isLocationLoading: _isLocationLoading,
                          initialCenter: _mapCenterPosition,
                          initialZoom: _mapZoom,
                        ),

                        // Search results overlay - below AppBar
                        if (_searchManager.state.isSearching || _searchManager.state.results.isNotEmpty)
                          Positioned(
                            top: 8,  // Below the AppBar
                            left: 16,
                            right: 16,
                            child: _buildSearchResults(),
                          ),

                        // Auto-dismissing location notification
                        if (_showLocationNotification)
                          Positioned(
                            bottom: 120,
                            left: 16,
                            right: 16,
                            child: AnimatedOpacity(
                              opacity: _showLocationNotification ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.location_off,
                                      color: Colors.white.withValues(alpha: 0.9),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Location unavailable',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

          // Wind loading overlay
          if (_isWindLoading)
            MapLoadingOverlay.single(
              label: 'Loading wind forecast',
              icon: Icons.air,
              iconColor: Colors.lightBlue,
              count: _displayedSites.length,
            ),

          // Search dropdown overlay
          if (_searchManager.shouldShowSearchDropdown())
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                elevation: 8,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _searchManager.state.isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Searching sites...'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchManager.state.results.length,
                        itemBuilder: (context, index) {
                          final site = _searchManager.state.results[index];
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                              child: Text(
                                site.country?.toUpperCase().substring(0, 2) ?? '??',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            ),
                            title: Text(
                              site.name,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(site.country ?? 'Unknown'),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () {
                              _searchManager.selectSearchResult(site);
                              _jumpToLocation(site);
                            },
                          );
                        },
                      ),
                ),
              ),
            ),

        ],
      ),
    );
  }
}

class _SiteDetailsDialog extends StatefulWidget {
  final Site? site;
  final ParaglidingSite? paraglidingSite;
  final Position? userPosition;
  final WindData? windData;
  final Function(WindData)? onWindDataFetched;

  const _SiteDetailsDialog({
    this.site,
    this.paraglidingSite,
    this.userPosition,
    this.windData,
    this.onWindDataFetched,
  });

  @override
  State<_SiteDetailsDialog> createState() => _SiteDetailsDialogState();
}

class _SiteDetailsDialogState extends State<_SiteDetailsDialog> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _detailedData;
  bool _isLoadingDetails = false;
  String? _loadingError;
  TabController? _tabController;

  // Wind data state
  WindData? _windData;
  bool _isLoadingWind = false;

  @override
  void initState() {
    super.initState();
    // Create tab controller for both local and API sites - both can have detailed data
    _tabController = TabController(length: 2, vsync: this); // 2 tabs: Takeoff, Weather
    _loadSiteDetails();
    _loadWindData();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadSiteDetails() async {
    // Load detailed data from API for both local sites and API sites
    double latitude;
    double longitude;
    
    if (widget.paraglidingSite != null) {
      // API site - use its coordinates
      latitude = widget.paraglidingSite!.latitude;
      longitude = widget.paraglidingSite!.longitude;
    } else if (widget.site != null) {
      // Local site - use its coordinates to fetch API data
      latitude = widget.site!.latitude;
      longitude = widget.site!.longitude;
    } else {
      return; // No site data available
    }
    
    setState(() {
      _isLoadingDetails = true;
      _loadingError = null;
    });

    try {
      final details = await ParaglidingEarthApi.instance.getSiteDetails(
        latitude,
        longitude,
      );
      
      if (mounted) {
        setState(() {
          _detailedData = details;
          _isLoadingDetails = false;
        });
        // Debug: Log all available fields
        if (details != null) {
          LoggingService.info('Site details fields: ${details.keys.toList()}');
          LoggingService.info('Has landing_altitude: ${details.containsKey('landing_altitude')}');
          LoggingService.info('Has landing_description: ${details.containsKey('landing_description')}');
          LoggingService.info('Has lz_altitude: ${details.containsKey('lz_altitude')}');
          LoggingService.info('Has lz_description: ${details.containsKey('lz_description')}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
          _loadingError = 'Failed to load detailed information';
        });
        LoggingService.error('Error loading site details', e);
      }
    }
  }

  Future<void> _loadWindData() async {
    // If wind data was already provided by parent, use it
    if (widget.windData != null) {
      _windData = widget.windData;
      return;
    }

    // Otherwise, fetch wind data ourselves
    setState(() => _isLoadingWind = true);

    try {
      // Get coordinates from either paraglidingSite or site
      double latitude;
      double longitude;

      if (widget.paraglidingSite != null) {
        latitude = widget.paraglidingSite!.latitude;
        longitude = widget.paraglidingSite!.longitude;
      } else if (widget.site != null) {
        latitude = widget.site!.latitude;
        longitude = widget.site!.longitude;
      } else {
        setState(() => _isLoadingWind = false);
        return;
      }

      LoggingService.info('[SITE_DIALOG] Fetching wind data for site at $latitude, $longitude');

      final windData = await WeatherService.instance.getWindData(
        latitude,
        longitude,
        DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _windData = windData;
          _isLoadingWind = false;
        });

        // Notify parent to update its cache
        if (windData != null && widget.onWindDataFetched != null) {
          widget.onWindDataFetched!(windData);
        }

        LoggingService.info('[SITE_DIALOG] Wind data fetched successfully: ${windData?.compassDirection} ${windData?.speedKmh}km/h');
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() => _isLoadingWind = false);
      }
      LoggingService.error('Failed to fetch wind data for site dialog', e, stackTrace);
    }
  }

  /// Get the center dot color based on flyability status
  Color? _getCenterDotColor(List<String> windDirections) {
    // If no wind data available, return null to use default color
    if (_windData == null) {
      return null;
    }

    // If no wind directions defined, return grey (can't evaluate flyability)
    if (windDirections.isEmpty) {
      return SiteMarkerUtils.unknownFlyabilitySiteColor;
    }

    // Calculate flyability using the same logic as nearby_sites_screen
    final isFlyable = _windData!.isFlyable(
      windDirections,
      25.0, // Default max wind speed
      30.0, // Default max gusts
    );

    return isFlyable
        ? SiteMarkerUtils.flyableSiteColor
        : SiteMarkerUtils.notFlyableSiteColor;
  }

  /// Get the center dot tooltip showing flyability reason
  String? _getCenterDotTooltip(List<String> windDirections) {
    // If no wind data, no tooltip
    if (_windData == null) {
      return null;
    }

    // If no wind directions, explain why we can't evaluate
    if (windDirections.isEmpty) {
      return 'No wind directions defined for site';
    }

    // Use WindData's built-in flyability reason
    return _windData!.getFlyabilityReason(
      windDirections,
      25.0, // Default max wind speed
      30.0, // Default max gusts
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine which site data to use
    final String name = widget.site?.name ?? widget.paraglidingSite?.name ?? 'Unknown Site';
    final double latitude = widget.site?.latitude ?? widget.paraglidingSite?.latitude ?? 0.0;
    final double longitude = widget.site?.longitude ?? widget.paraglidingSite?.longitude ?? 0.0;
    final int? altitude = widget.site?.altitude?.toInt() ?? widget.paraglidingSite?.altitude ?? _detailedData?['altitude'];
    final String? country = widget.site?.country ?? widget.paraglidingSite?.country ?? _detailedData?['country'];
    // Extract data from ParaglidingSite OR from fetched API data for local sites
    final String? region = widget.paraglidingSite?.region ?? _detailedData?['region'];
    final String? description = widget.paraglidingSite?.description ?? _detailedData?['description'];
    final int? rating = widget.paraglidingSite?.rating ?? _detailedData?['rating'];
    // Check for both null and empty wind directions to ensure fallback to API data
    final List<String> windDirections =
        (widget.paraglidingSite?.windDirections.isNotEmpty == true
            ? widget.paraglidingSite!.windDirections
            : (_detailedData?['wind_directions'] as List<dynamic>?)?.cast<String>()) ?? [];

    // Debug logging for Annecy - Planfait site and Mt Bakewell
    if (name.contains('Annecy') || name.contains('Planfait') || name.contains('Bakewell')) {
      LoggingService.debug('Site debug: name=$name');
      LoggingService.debug('Site debug: widget.paraglidingSite?.id=${widget.paraglidingSite?.id}');
      LoggingService.debug('Site debug: widget.paraglidingSite?.windDirections=${widget.paraglidingSite?.windDirections}');
      LoggingService.debug('Site debug: _detailedData wind_directions=${_detailedData?['wind_directions']}');
      LoggingService.debug('Site debug: final windDirections=$windDirections');
    }
    final String? siteType = widget.paraglidingSite?.siteType ?? _detailedData?['site_type'];
    final int? flightCount = widget.site?.flightCount;
    
    // Calculate distance if user position is available
    String? distanceText;
    if (widget.userPosition != null) {
      final distance = LocationService.instance.calculateDistance(
        widget.userPosition!.latitude,
        widget.userPosition!.longitude,
        latitude,
        longitude,
      );
      distanceText = LocationService.formatDistance(distance);
    }

    return Dialog(
      elevation: 16,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with name, rating, and close button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Make name clickable if PGE link is available
                      if (_detailedData?['pge_link'] != null)
                        InkWell(
                          onTap: () => _launchUrl(_detailedData!['pge_link']),
                          child: Text(
                            name,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        )
                      else
                        Text(
                          name,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Show detailed view if we have a tab controller and either ParaglidingSite or fetched API data
            if (_tabController != null && (_detailedData != null || widget.paraglidingSite != null)) ...[
              // Overview content (always visible)
              ..._buildOverviewContent(name, latitude, longitude, altitude, country, region, rating, siteType, windDirections, flightCount, distanceText),
              
              const SizedBox(height: 8),
              
              // Tabs for detailed information
              if (_tabController != null)
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 40,
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: false,
                          tabAlignment: TabAlignment.fill,
                          labelPadding: EdgeInsets.symmetric(horizontal: 8),
                          indicatorWeight: 1.0,
                          indicatorPadding: EdgeInsets.zero,
                        tabs: const [
                          Tab(icon: Tooltip(message: 'Site Information', child: Icon(Icons.info_outline, size: 18))),
                          Tab(icon: Tooltip(message: 'Site Weather', child: Icon(Icons.air, size: 18))),
                        ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildTakeoffTab(),
                            _buildWeatherTab(windDirections),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ] else
              ..._buildSimpleContent(name, latitude, longitude, altitude, country, region, rating, siteType, windDirections, flightCount, distanceText, description),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildOverviewContent(String name, double latitude, double longitude, int? altitude, String? country, String? region, int? rating, String? siteType, List<String> windDirections, int? flightCount, String? distanceText) {
    return [
            // Row 2: Site Type + Altitude + Wind + Directions
            Row(
              children: [
                // Site type with characteristics tooltip on icon
                if (siteType != null) ...[
                  Tooltip(
                    message: _buildSiteCharacteristicsTooltip(),
                    child: Icon(
                      _getSiteTypeIcon(siteType),
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatSiteType(siteType),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Text(':', style: TextStyle(color: Colors.grey)),
                ],
                // Show altitude (prefer takeoff_altitude from API, fallback to general altitude)
                if (_detailedData?['takeoff_altitude'] != null || altitude != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.terrain, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${_detailedData?['takeoff_altitude'] ?? altitude}m',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                // Wind directions (compact)
                if (windDirections.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.air, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      windDirections.join(', '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                // Map icon - opens maps app (directly after wind directions)
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => _launchMap(latitude, longitude),
                  child: const Icon(
                    Icons.map,
                    size: 16,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),

            // Landing information row (if available)
            if (_detailedData?['landing_altitude'] != null || _detailedData?['landing_description'] != null || _detailedData?['landing_lat'] != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  // Landing icon with tooltip
                  Tooltip(
                    message: 'Landing information',
                    child: const Icon(
                      Icons.flight_land,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Landing Site',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Text(':', style: TextStyle(color: Colors.grey)),
                  // Landing altitude
                  if (_detailedData?['landing_altitude'] != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.terrain, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${_detailedData!['landing_altitude']}m',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  // Map icon for landing - uses landing coordinates if available
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () {
                      final landingLat = double.tryParse(_detailedData?['landing_lat']?.toString() ?? '');
                      final landingLng = double.tryParse(_detailedData?['landing_lng']?.toString() ?? '');
                      if (landingLat != null && landingLng != null) {
                        _launchMap(landingLat, landingLng);
                      } else {
                        _launchMap(latitude, longitude);
                      }
                    },
                    child: const Icon(
                      Icons.map,
                      size: 16,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ],

            // Flight count (for local sites) - only show if present
            if (flightCount != null && flightCount > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.flight, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    '$flightCount ${flightCount == 1 ? 'flight' : 'flights'} logged',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
    ];
  }

  Widget _buildTakeoffTab() {
    return Scrollbar(
      child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          if (_isLoadingDetails)
            const Center(child: CircularProgressIndicator())
          else if (_loadingError != null)
            Center(child: Text(_loadingError!, style: TextStyle(color: Colors.red)))
          else if (_detailedData != null) ...[
            // ===== TAKEOFF SECTION =====
            Row(
              children: [
                Icon(Icons.flight_takeoff, size: 18, color: Colors.grey[300]),
                const SizedBox(width: 8),
                Text(
                  'Takeoff',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[300],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Takeoff instructions
            if (_detailedData!['takeoff_description'] != null && _detailedData!['takeoff_description']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['takeoff_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // ===== LANDING SECTION =====
            if (_detailedData!['landing_description'] != null && _detailedData!['landing_description']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.flight_land, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Landing',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _detailedData!['landing_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            
            // Parking information
            if (_detailedData!['takeoff_parking_description'] != null && _detailedData!['takeoff_parking_description']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.local_parking, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Parking Information',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _detailedData!['takeoff_parking_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              // Add navigation to parking location if coordinates available
              if (_detailedData!['landing'] != null &&
                  _detailedData!['landing']['landing_parking_lat'] != null &&
                  _detailedData!['landing']['landing_parking_lng'] != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    final lat = double.tryParse(_detailedData!['landing']['landing_parking_lat'].toString());
                    final lng = double.tryParse(_detailedData!['landing']['landing_parking_lng'].toString());
                    if (lat != null && lng != null) {
                      _launchNavigation(lat, lng);
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.directions, size: 16, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text(
                        'Navigate to parking',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],

            // Flight Rules section
            if (_detailedData!['flight_rules'] != null && _detailedData!['flight_rules']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.policy, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Flight Rules & Regulations',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _detailedData!['flight_rules']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // Access Instructions section
            if (_detailedData!['going_there'] != null && _detailedData!['going_there']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.directions_car, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Access Instructions',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildLinkableText(_detailedData!['going_there']!.toString()),
              const SizedBox(height: 16),
            ],

            // Community Comments section
            if (_detailedData!['comments'] != null && _detailedData!['comments']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Local Information',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildLinkableText(_detailedData!['comments']!.toString()),
              const SizedBox(height: 16),
            ],

            // Alternate Takeoffs section
            if (_detailedData!['alternate_takeoffs'] != null && _hasAlternateTakeoffs(_detailedData!['alternate_takeoffs'])) ...[
              Row(
                children: [
                  Icon(Icons.alt_route, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Alternative Launch Points',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildAlternateTakeoffs(_detailedData!['alternate_takeoffs']),
              const SizedBox(height: 16),
            ],

            // Alternate Landings section
            if (_detailedData!['landing'] != null && _detailedData!['landing']['alternate_landings'] != null) ...[
              Row(
                children: [
                  Icon(Icons.alt_route, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Alternative Landing Zones',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildAlternateLandings(_detailedData!['landing']['alternate_landings']),
            ],

            // Last updated information
            if (_detailedData!['last_edit'] != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.update, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'Last updated: ${_detailedData!['last_edit']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ] else
            const Center(child: Text('No takeoff information available')),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildWeatherTab(List<String> windDirections) {
    // Extract weather information early for better layout control
    final weatherInfo = _detailedData?['weather']?.toString();
    final thermalFlag = _detailedData?['thermals']?.toString();
    final soaringFlag = _detailedData?['soaring']?.toString();
    final xcFlag = _detailedData?['xc']?.toString();

    return Scrollbar(
      child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoadingDetails)
              const Center(child: CircularProgressIndicator())
            else if (_loadingError != null)
              Center(child: Text(_loadingError!, style: TextStyle(color: Colors.red)))
            else if (windDirections.isNotEmpty) ...[
              // Compact single-column layout with inline wind rose
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Wind rose on the left
                      Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: WindRoseWidget(
                          launchableDirections: windDirections,
                          size: 100.0,
                          windSpeed: _windData?.speedKmh,
                          windDirection: _windData?.directionDegrees,
                          centerDotColor: _getCenterDotColor(windDirections),
                          centerDotTooltip: _getCenterDotTooltip(windDirections),
                        ),
                      ),
                      // Weather text on the right, flexible to use remaining space
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Weather description
                            if (weatherInfo != null && weatherInfo.isNotEmpty) ...[
                              Text(
                                weatherInfo,
                                style: Theme.of(context).textTheme.bodyMedium,
                                softWrap: true,
                              ),
                              const SizedBox(height: 8),
                            ],

                            // Flight characteristics
                            if (thermalFlag == '1' || soaringFlag == '1' || xcFlag == '1') ...[
                              _buildCompactFlightCharacteristics(thermalFlag, soaringFlag, xcFlag),
                            ],

                            // If no weather content at all
                            if ((weatherInfo == null || weatherInfo.isEmpty) &&
                                thermalFlag != '1' && soaringFlag != '1' && xcFlag != '1') ...[
                              Text(
                                'No weather information available for this site.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                                softWrap: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              // No wind directions - center message
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No wind direction restrictions',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This site has no specific wind direction requirements.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildCompactFlightCharacteristics(String? thermalFlag, String? soaringFlag, String? xcFlag) {
    final characteristics = <String>[];

    if (thermalFlag == '1') characteristics.add('Thermals');
    if (soaringFlag == '1') characteristics.add('Soaring');
    if (xcFlag == '1') characteristics.add('Cross Country');

    if (characteristics.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.flight,
              size: 16,
              color: Colors.green,
            ),
            const SizedBox(width: 6),
            Text(
              'Good for:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          characteristics.join(' • '),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildWeatherInfoSection({
    required String title,
    required String content,
    required IconData icon,
    required Color iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: iconColor,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildFlightCharacteristicsSection(String? thermalFlag, String? soaringFlag, String? xcFlag) {
    final characteristics = <String>[];

    if (thermalFlag == '1') characteristics.add('Thermals');
    if (soaringFlag == '1') characteristics.add('Soaring');
    if (xcFlag == '1') characteristics.add('Cross Country (XC)');

    if (characteristics.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.flight,
              size: 16,
              color: Colors.green,
            ),
            const SizedBox(width: 6),
            Text(
              'Flight Characteristics',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Good conditions for: ${characteristics.join(', ')}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  /// Launch navigation to coordinates
  Future<void> _launchNavigation(double latitude, double longitude) async {
    final uri = Uri.parse('https://maps.google.com/?daddr=$latitude,$longitude');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      LoggingService.action('NearbySites', 'launch_navigation', {
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (e) {
      LoggingService.error('NearbySites: Could not launch navigation', e);
    }
  }

  /// Launch map to view a location (not navigate)
  Future<void> _launchMap(double latitude, double longitude) async {
    final uri = Uri.parse('https://maps.google.com/?q=$latitude,$longitude');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      LoggingService.action('NearbySites', 'launch_map', {
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (e) {
      LoggingService.error('NearbySites: Could not launch map', e);
    }
  }

  /// Launch URL in external browser
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      LoggingService.action('NearbySites', 'launch_url', {'url': url});
    } catch (e) {
      LoggingService.error('NearbySites: Could not launch URL', e);
    }
  }


  List<Widget> _buildSimpleContent(String name, double latitude, double longitude, int? altitude, String? country, String? region, int? rating, String? siteType, List<String> windDirections, int? flightCount, String? distanceText, String? description) {
    return [
      // Simple layout for local sites or sites without detailed data
      
      // Location info
      if (region != null || country != null) ...[
        Row(
          children: [
            const Icon(Icons.location_on, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [region, country].where((s) => s != null && s.isNotEmpty).join(', '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      
      // Altitude
      if (altitude != null) ...[
        Row(
          children: [
            const Icon(Icons.terrain, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              '${altitude}m altitude',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      
      // Distance
      if (distanceText != null) ...[
        Row(
          children: [
            const Icon(Icons.straighten, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              '$distanceText away',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      
      // Flight count (for local sites)
      if (flightCount != null && flightCount > 0) ...[
        Row(
          children: [
            const Icon(Icons.flight, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              '$flightCount ${flightCount == 1 ? 'flight' : 'flights'} logged',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      
      // Site type (for API sites)
      if (siteType != null) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.info_outline, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              'Type: ${_formatSiteType(siteType)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
      
      // Wind directions (for API sites)
      if (windDirections.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.air, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Wind: ${windDirections.join(', ')}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
      
      // Description (fallback for local sites)
      if (description != null && description.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(
          'Description',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ];
  }
  
  String _formatSiteType(String siteType) {
    switch (siteType.toLowerCase()) {
      case 'launch':
        return 'Launch Site';
      case 'landing':
        return 'Landing Zone';
      case 'both':
        return 'Launch & Landing';
      default:
        return siteType;
    }
  }

  IconData _getSiteTypeIcon(String siteType) {
    switch (siteType.toLowerCase()) {
      case 'launch':
        return Icons.flight_takeoff;
      case 'landing':
        return Icons.flight_land;
      case 'both':
        return Icons.flight;
      default:
        return Icons.location_on;
    }
  }

  String _buildSiteCharacteristicsTooltip() {
    if (_detailedData == null) return 'Site information';
    
    List<String> characteristics = [];
    
    // Check all possible characteristics that can have value "1"
    final characteristicMap = {
      'paragliding': 'Paragliding',
      'hanggliding': 'Hanggliding', 
      'hike': 'Hike',
      'thermals': 'Thermals',
      'soaring': 'Soaring',
      'xc': 'XC',
      'flatland': 'Flatland',
      'winch': 'Winch',
    };
    
    characteristicMap.forEach((key, label) {
      if (_detailedData![key]?.toString() == '1') {
        characteristics.add(label);
      }
    });
    
    return characteristics.isNotEmpty
        ? characteristics.join(', ')
        : 'Site information';
  }

  /// Build clickable text that turns URLs into links
  Widget _buildLinkableText(String text) {
    // Simple URL detection - matches http/https URLs
    final urlRegex = RegExp(r'https?://[^\s]+');
    final matches = urlRegex.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      // Add text before the URL
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: Theme.of(context).textTheme.bodyMedium,
        ));
      }

      // Add the clickable URL
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(url),
      ));

      lastEnd = match.end;
    }

    // Add remaining text after the last URL
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: Theme.of(context).textTheme.bodyMedium,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  /// Check if alternate takeoffs data has valid content
  bool _hasAlternateTakeoffs(dynamic alternateData) {
    if (alternateData == null) return false;

    List<dynamic> alternates = [];
    if (alternateData is Map && alternateData.containsKey('alternate_takeoff')) {
      final alt = alternateData['alternate_takeoff'];
      if (alt is List) {
        alternates = alt;
      } else {
        alternates = [alt];
      }
    } else if (alternateData is List) {
      alternates = alternateData;
    } else {
      alternates = [alternateData];
    }

    // Check if any alternate has meaningful data (lat/lng or description)
    for (final alternate in alternates) {
      if (alternate is Map) {
        final hasCoords = alternate['lat'] != null || alternate['lng'] != null;
        final hasDesc = alternate['description']?.toString().isNotEmpty == true;
        final hasName = alternate['name']?.toString().isNotEmpty == true;
        if (hasCoords || hasDesc || hasName) {
          return true;
        }
      }
    }
    return false;
  }

  /// Build alternate takeoffs section
  Widget _buildAlternateTakeoffs(dynamic alternateData) {
    if (alternateData == null) {
      return const SizedBox.shrink();
    }

    // Handle both single alternate takeoff and list of alternates
    List<dynamic> alternates = [];
    if (alternateData is Map && alternateData.containsKey('alternate_takeoff')) {
      final alt = alternateData['alternate_takeoff'];
      if (alt is List) {
        alternates = alt;
      } else {
        alternates = [alt];
      }
    } else if (alternateData is List) {
      alternates = alternateData;
    } else {
      alternates = [alternateData];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: alternates.asMap().entries.map((entry) {
        final index = entry.key;
        final alternate = entry.value;

        if (alternate is! Map) return const SizedBox.shrink();

        final name = alternate['name']?.toString();
        final lat = double.tryParse(alternate['lat']?.toString() ?? '');
        final lng = double.tryParse(alternate['lng']?.toString() ?? '');
        final altitude = alternate['altitude']?.toString();
        final description = alternate['description']?.toString();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.flag, size: 16, color: Colors.purple.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name?.isNotEmpty == true ? name! : 'Alternate ${index + 1}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (lat != null && lng != null)
                    InkWell(
                      onTap: () => _launchNavigation(lat, lng),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(
                            'Navigate',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (altitude != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.terrain, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${altitude}m',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
              if (description?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Build alternate landings section
  Widget _buildAlternateLandings(dynamic alternateData) {
    if (alternateData == null) {
      return const SizedBox.shrink();
    }

    // Handle both single alternate landing and list of alternates
    List<dynamic> alternates = [];
    if (alternateData is Map && alternateData.containsKey('alternate_landing')) {
      final alt = alternateData['alternate_landing'];
      if (alt is List) {
        alternates = alt;
      } else {
        alternates = [alt];
      }
    } else if (alternateData is List) {
      alternates = alternateData;
    } else {
      alternates = [alternateData];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: alternates.asMap().entries.map((entry) {
        final index = entry.key;
        final alternate = entry.value;

        if (alternate is! Map) return const SizedBox.shrink();

        final name = alternate['name']?.toString();
        final lat = double.tryParse(alternate['lat']?.toString() ?? '');
        final lng = double.tryParse(alternate['lng']?.toString() ?? '');
        final altitude = alternate['altitude']?.toString();
        final description = alternate['description']?.toString();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.teal.shade200),
            borderRadius: BorderRadius.circular(8),
            color: Colors.teal.shade50,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.teal.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name?.isNotEmpty == true ? name! : 'Alternate Landing ${index + 1}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (lat != null && lng != null)
                    InkWell(
                      onTap: () => _launchNavigation(lat, lng),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(
                            'Navigate',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (altitude != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.terrain, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${altitude}m',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
              if (description?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Draggable dialog widget for the map filter
class _DraggableFilterDialog extends StatefulWidget {
  final bool sitesEnabled;
  final bool airspaceEnabled;
  final bool forecastEnabled;
  final Map<String, bool> airspaceTypes;
  final Map<String, bool> icaoClasses;
  final double maxAltitudeFt;
  final bool clippingEnabled;
  final Function(bool sitesEnabled, bool airspaceEnabled, bool forecastEnabled, Map<String, bool> types, Map<String, bool> classes, double maxAltitudeFt, bool clippingEnabled) onApply;

  const _DraggableFilterDialog({
    required this.sitesEnabled,
    required this.airspaceEnabled,
    required this.forecastEnabled,
    required this.airspaceTypes,
    required this.icaoClasses,
    required this.maxAltitudeFt,
    required this.clippingEnabled,
    required this.onApply,
  });

  @override
  State<_DraggableFilterDialog> createState() => _DraggableFilterDialogState();
}

class _DraggableFilterDialogState extends State<_DraggableFilterDialog> {
  late Offset _position = const Offset(16, 80); // Start in top-left

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Positioned dialog
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _position += details.delta;
                // Keep dialog within screen bounds
                final screenSize = MediaQuery.of(context).size;
                _position = Offset(
                  _position.dx.clamp(0, screenSize.width - 300), // Assume dialog width ~300
                  _position.dy.clamp(0, screenSize.height - 400), // Assume dialog height ~400
                );
              });
            },
            child: Material(
              color: Colors.transparent,
              child: MapFilterDialog(
                sitesEnabled: widget.sitesEnabled,
                airspaceEnabled: widget.airspaceEnabled,
                forecastEnabled: widget.forecastEnabled,
                airspaceTypes: widget.airspaceTypes,
                icaoClasses: widget.icaoClasses,
                maxAltitudeFt: widget.maxAltitudeFt,
                clippingEnabled: widget.clippingEnabled,
                onApply: widget.onApply,
              ),
            ),
          ),
        ),
      ],
    );
  }
}