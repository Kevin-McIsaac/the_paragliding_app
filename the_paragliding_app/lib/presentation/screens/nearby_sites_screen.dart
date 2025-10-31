import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/airspace_enums.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/flyability_status.dart';
import '../../data/models/weather_station.dart';
import '../../data/models/weather_station_source.dart';
import '../../services/location_service.dart';
import '../../services/logging_service.dart';
import '../../services/map_bounds_manager.dart';
import '../../services/weather_service.dart';
import '../../services/weather_station_service.dart';
import '../../services/weather_providers/weather_station_provider_registry.dart';
import '../../utils/map_constants.dart';
import '../../utils/site_utils.dart';
import '../../utils/preferences_helper.dart';
import '../../utils/flyability_helper.dart';
import '../../utils/ui_utils.dart';
import '../widgets/nearby_sites_map.dart';
import '../widgets/map_filter_dialog.dart';
import '../widgets/site_details_dialog.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/map_loading_overlay.dart';
import '../widgets/common/app_menu_button.dart';
import '../widgets/common/map_settings_menu.dart';
import '../widgets/common/base_map_widget.dart';
import '../../utils/map_provider.dart';
import '../../services/openaip_service.dart';
import '../../services/database_service.dart';
import '../../services/pge_sites_database_service.dart';

/// Loading states for different operations
enum LoadingOperation {
  idle,
  initialLoad,
  location,
  wind,
  weatherStations,
  favorites,
}

class NearbySitesScreen extends StatefulWidget {
  /// Optional callback to reload data after database changes.
  /// Used by MainNavigationScreen to coordinate refreshes across all tabs.
  final VoidCallback? onDataChanged;
  final Future<void> Function()? onRefreshAllTabs;

  const NearbySitesScreen({
    super.key,
    this.onDataChanged,
    this.onRefreshAllTabs,
  });

  @override
  State<NearbySitesScreen> createState() => NearbySitesScreenState();
}

/// State class for NearbySitesScreen.
///
/// Made public (not prefixed with _) to allow parent widgets to access
/// the refreshData() method through GlobalKey in a type-safe manner.
///
/// Example:
/// ```dart
/// final key = GlobalKey<NearbySitesScreenState>();
/// // ...
/// await key.currentState?.refreshData();
/// ```
class NearbySitesScreenState extends State<NearbySitesScreen> with WidgetsBindingObserver {
  final LocationService _locationService = LocationService.instance;
  final MapController _mapController = MapController();
  final GlobalKey<State<NearbySitesMap>> _mapKey = GlobalKey();

  // Sites state - using ParaglidingSite directly (no more UnifiedSite)
  List<ParaglidingSite> _allSites = [];
  List<ParaglidingSite> _displayedSites = [];
  Map<String, bool> _siteFlightStatus = {}; // Key: "lat,lng", Value: hasFlights
  Position? _userPosition;

  // Consolidated loading state
  final Set<LoadingOperation> _activeLoadingOperations = {};
  String? _errorMessage;
  LatLng? _mapCenterPosition;
  bool _mapReady = false; // Track if map is initialized
  double _currentZoom = 10.0; // Current zoom level (updated reactively)
  int _airspaceDataVersion = 0; // Increment to trigger airspace reload without full widget recreation
  int _sitesDataVersion = 0; // Increment to trigger sites reload when site data changes (e.g., deletion)

  // Preference keys for filter states
  static const String _sitesEnabledKey = 'nearby_sites_sites_enabled';
  static const String _airspaceEnabledKey = 'nearby_sites_airspace_enabled';
  static const String _forecastEnabledKey = 'nearby_sites_forecast_enabled';
  static const String _weatherStationsEnabledKey = 'nearby_sites_weather_stations_enabled';

  // Bounds-based loading state using MapBoundsManager
  LatLngBounds? _currentBounds;

  // Location notification state
  bool _showLocationNotification = false;
  Timer? _locationNotificationTimer;

  // Simple inline search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<ParaglidingSite> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  // Filter state for sites and airspace (defaults, will be loaded from preferences)
  bool _sitesEnabled = true; // Controls site loading and display
  bool _airspaceEnabled = true; // Controls airspace loading and display
  bool _forecastEnabled = true; // Controls wind forecast fetching and display
  bool _weatherStationsEnabled = true; // Controls weather station loading and display (default: enabled)
  bool _metarEnabled = true; // METAR provider enabled (default: true)
  bool _nwsEnabled = true; // NWS provider enabled (default: true, free/no API key)
  bool _pioupiouEnabled = true; // Pioupiou provider enabled (default: true, free/no API key)
  bool _ffvlEnabled = true; // FFVL provider enabled (default: true, has API key)
  bool _bomEnabled = true; // BOM provider enabled (default: true, free/no API key)
  bool _hasActiveFilters = false; // Cached value to avoid FutureBuilder rebuilds
  double _maxAltitudeFt = 10000.0; // Default altitude filter
  bool _airspaceClippingEnabled = true; // Default clipping enabled
  Map<IcaoClass, bool> _excludedIcaoClasses = {}; // Current ICAO class filter state
  final OpenAipService _openAipService = OpenAipService.instance;

  // Wind forecast state
  // Round to nearest hour to prevent constant rebuilds while keeping automatic updates
  DateTime get _selectedDateTime {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour);
  }
  final Map<String, WindData> _siteWindData = {};
  final Map<String, FlyabilityStatus> _siteFlyabilityStatus = {};
  double _maxWindSpeed = 25.0;
  double _cautionWindSpeed = 20.0;
  final WeatherService _weatherService = WeatherService.instance;
  Timer? _windFetchDebounce;

  // Weather station state
  List<WeatherStation> _weatherStations = [];
  final Map<String, WindData> _stationWindData = {};
  final Map<WeatherStationSource, LoadingItemState> _providerStates = {};
  final Set<WeatherStationSource> _providersActuallyLoading = {}; // Track providers making API calls
  final Map<WeatherStationSource, Timer> _providerDismissTimers = {}; // Auto-dismiss timers for provider states
  final WeatherStationService _weatherStationService = WeatherStationService.instance;
  Timer? _stationFetchDebounce;

  // Wind forecast state
  bool _forecastActuallyCallingApi = false; // Track if forecast API is being called
  bool _forecastHasError = false; // Track if forecast API call failed

  // Favorites state
  List<ParaglidingSite> _favoriteSites = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
    _loadFilterSettings();
    _loadWindPreferences();
    _updateActiveFiltersState(); // Initialize the cached active filters state
    _loadData();
    _loadFavorites(); // Pre-load favorites so they're ready on first popup open
  }

  /// Public method to refresh sites and airspace data.
  ///
  /// This method can be called by parent widgets using a GlobalKey:
  /// ```dart
  /// final key = GlobalKey<NearbySitesScreenState>();
  /// // ...
  /// await key.currentState?.refreshData();
  /// ```
  ///
  /// This clears the MapBoundsManager cache and reloads both sites and airspace
  /// for the current map bounds, which is useful after database changes
  /// (e.g., Import IGC, Manage Sites, or downloading new airspace data).
  Future<void> refreshData() async {
    final currentPosition = _mapController.camera.center;
    final currentZoom = _mapController.camera.zoom;

    LoggingService.info('[REFRESH] Starting refresh | position=$currentPosition | zoom=$currentZoom');

    // Clear the cache to force fresh data load
    MapBoundsManager.instance.clearCache('nearby_sites');

    // Trigger rebuild - Flutter will naturally preserve map position via mapController
    // Increment data versions to trigger didUpdateWidget in map, causing both airspace and sites reload
    if (mounted) {
      setState(() {
        _airspaceDataVersion++; // Triggers didUpdateWidget without full widget recreation
        _sitesDataVersion++; // Also increment sites version for consistency
      });

      // Schedule bounds reload after widget rebuild completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentBounds != null) {
          final newPosition = _mapController.camera.center;
          LoggingService.info('[REFRESH] Post-rebuild | old_position=$currentPosition | new_position=$newPosition | position_preserved=${currentPosition.latitude == newPosition.latitude && currentPosition.longitude == newPosition.longitude}');
          _onBoundsChanged(_currentBounds!);
        }
      });
    }
  }

  /// Unified handler for site data changes - consolidates duplicate handlers.
  ///
  /// This replaces _handleSiteDataChanged() and _handleSitesVersionChanged() with
  /// a single method that handles all site reload scenarios consistently.
  void _handleSiteDataChanged() {
    LoggingService.info('[SITE_DATA] Site data changed, clearing cache and incrementing version | old_version=$_sitesDataVersion');

    // Clear the cache to force fresh data load
    MapBoundsManager.instance.clearCache('nearby_sites');

    // Increment sites data version to trigger immediate map update
    if (mounted) {
      setState(() {
        _sitesDataVersion++;
      });
    }
  }

  /// Handle sites version change by reloading sites immediately.
  /// Called from NearbySitesMap when sitesDataVersion changes.
  Future<void> _handleSitesVersionChanged() async {
    if (_currentBounds == null) return;

    // Load sites immediately without debouncing
    await MapBoundsManager.instance.loadSitesForBoundsImmediate(
      context: 'nearby_sites',
      bounds: _currentBounds!,
      zoomLevel: _mapController.camera.zoom,
      onLoaded: (result) {
        if (mounted) {
          setState(() {
            _processSitesLoaded(result, fetchWindData: true);
          });
        }
      },
    );
  }

  /// Process loaded sites - consolidates site handling logic.
  void _processSitesLoaded(dynamic result, {bool fetchWindData = false}) {
    _allSites = result.sites;
    _siteFlightStatus = {};

    // Clean up stale data
    final currentSiteKeys = result.sites.map((site) => SiteUtils.createSiteKey(site.latitude, site.longitude)).toSet();
    _siteFlyabilityStatus.removeWhere((key, value) => !currentSiteKeys.contains(key));
    _siteWindData.removeWhere((key, value) => !currentSiteKeys.contains(key));

    for (final site in result.sites) {
      final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
      _siteFlightStatus[key] = site.hasFlights;
    }

    _updateDisplayedSites();

    if (fetchWindData && _forecastEnabled && result.sites.isNotEmpty) {
      _fetchWindDataForSites();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MapBoundsManager.instance.cancelDebounce('nearby_sites'); // Clean up any pending debounce
    _locationNotificationTimer?.cancel(); // Clean up location notification timer
    _windFetchDebounce?.cancel(); // Clean up wind fetch debounce timer
    _stationFetchDebounce?.cancel(); // Clean up station fetch debounce timer
    for (var timer in _providerDismissTimers.values) {
      timer.cancel(); // Clean up all provider dismiss timers
    }
    _searchDebounce?.cancel(); // Clean up search debounce timer
    _searchController.dispose(); // Dispose search controller
    _searchFocusNode.dispose(); // Dispose search focus node
    _mapController.dispose(); // Dispose map controller
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Check if any cached forecasts are stale
      final stats = WeatherService.instance.getCacheStats();
      if (stats['stale_forecasts'] > 0) {
        LoggingService.info('[LIFECYCLE] App resumed with ${stats['stale_forecasts']} stale forecasts, refreshing...');
        _fetchWindDataForSites(); // Reload wind data for sites
      }
    }
  }

  /// Handle search query changes with debouncing
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();

    setState(() {
      _searchQuery = query.trim();
    });

    if (_searchQuery.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    if (_searchQuery.length < 2) {
      return; // Don't search for very short queries
    }

    // Debounce the search
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isSearching = true);

      try {
        final results = await PgeSitesDatabaseService.instance.searchSitesByName(
          query: _searchQuery,
        );

        if (mounted) {
          setState(() {
            _searchResults = results.take(15).toList();
            _isSearching = false;
          });

          // Auto-jump to single result
          if (_searchResults.length == 1) {
            _jumpToLocation(_searchResults.first, keepSearchActive: false);
            setState(() {
              _searchController.clear();
              _searchQuery = '';
              _searchResults = [];
            });
          }
        }
      } catch (e) {
        LoggingService.error('Search failed', e);
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
      }
    });
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sitesEnabled = prefs.getBool(_sitesEnabledKey) ?? true;
      final airspaceEnabled = prefs.getBool(_airspaceEnabledKey) ?? true;
      final forecastEnabled = prefs.getBool(_forecastEnabledKey) ?? true;
      final weatherStationsEnabled = prefs.getBool(_weatherStationsEnabledKey) ?? true;
      final metarEnabled = prefs.getBool('weather_provider_${WeatherStationSource.awcMetar.name}_enabled') ?? true;
      final nwsEnabled = prefs.getBool('weather_provider_${WeatherStationSource.nws.name}_enabled') ?? true;
      final pioupiouEnabled = prefs.getBool('weather_provider_${WeatherStationSource.pioupiou.name}_enabled') ?? true;
      final ffvlEnabled = prefs.getBool('weather_provider_${WeatherStationSource.ffvl.name}_enabled') ?? true;
      final bomEnabled = prefs.getBool('weather_provider_${WeatherStationSource.bom.name}_enabled') ?? true;

      if (mounted) {
        setState(() {
          _sitesEnabled = sitesEnabled;
          _airspaceEnabled = airspaceEnabled;
          _forecastEnabled = forecastEnabled;
          _weatherStationsEnabled = weatherStationsEnabled;
          _metarEnabled = metarEnabled;
          _nwsEnabled = nwsEnabled;
          _pioupiouEnabled = pioupiouEnabled;
          _ffvlEnabled = ffvlEnabled;
          _bomEnabled = bomEnabled;
        });
      }
    } catch (e) {
      LoggingService.error('Failed to load preferences', e);
    }
  }

  Future<void> _loadFilterSettings() async {
    try {
      final icaoClasses = await _openAipService.getExcludedIcaoClasses();
      final clippingEnabled = await _openAipService.isClippingEnabled();
      if (mounted) {
        setState(() {
          _excludedIcaoClasses = icaoClasses;
          _airspaceClippingEnabled = clippingEnabled;
        });
      }
    } catch (e) {
      LoggingService.error('Failed to load filter settings', e);
    }
  }

  Future<void> _loadWindPreferences() async {
    try {
      _maxWindSpeed = await PreferencesHelper.getMaxWindSpeed();
      _cautionWindSpeed = await PreferencesHelper.getCautionWindSpeed();

      // Wind bar state preferences could be loaded here if needed
    } catch (e) {
      LoggingService.error('Failed to load wind preferences', e);
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
    final currentZoom = MapConstants.roundZoomForDisplay(_mapController.camera.zoom);
    if (currentZoom < MapConstants.minForecastZoom) {
      LoggingService.info('Skipping wind fetch: zoom level $currentZoom < ${MapConstants.minForecastZoom}');
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
        // Don't add LoadingOperation.wind yet - wait until we know if API will be called
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
          'zoom_level': currentZoom.toStringAsFixed(2),
        });

        // Fetch wind data in batch with callback for API call tracking
        final windDataResults = await _weatherService.getWindDataBatch(
          locationsToFetch,
          _selectedDateTime,
          onApiCallStart: () {
            // Callback when forecast API is actually being called (not cached)
            LoggingService.info('Wind forecast API call started (cache miss)');
            setState(() {
              _activeLoadingOperations.add(LoadingOperation.wind);
              _forecastActuallyCallingApi = true;
              _forecastHasError = false; // Reset error state when starting new call
            });
          },
        );

        if (!mounted) return;

        // Update wind data map and flyability status with setState for immediate UI update
        setState(() {
          _activeLoadingOperations.remove(LoadingOperation.wind);
          _siteWindData.addAll(windDataResults);
          // Force recalculation because we have fresh wind data
          _updateFlyabilityStatus(forceRecalculation: true);

          // If forecast API was called, immediately remove from overlay (success)
          if (_forecastActuallyCallingApi) {
            _forecastActuallyCallingApi = false;
            _forecastHasError = false;
          }
        });

        LoggingService.structured('WIND_DATA_FETCHED', {
          'sites_count': _displayedSites.length,
          'fetched_count': windDataResults.length,
          'time': _selectedDateTime.toIso8601String(),
          'zoom_level': currentZoom.toStringAsFixed(2),
        });
      } catch (e, stackTrace) {
        LoggingService.error('Failed to fetch wind data', e, stackTrace);
        if (mounted) {
          setState(() {
            _activeLoadingOperations.remove(LoadingOperation.wind);
            // Keep _forecastActuallyCallingApi = true for persistent red cross on error
            _forecastHasError = true; // Mark as error for red cross display
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

  Future<void> _fetchWeatherStations() async {
    // Skip fetching if weather stations are disabled
    if (!_weatherStationsEnabled) {
      LoggingService.info('Skipping station fetch: weather stations disabled');
      return;
    }

    if (_currentBounds == null) {
      LoggingService.info('Skipping station fetch: no current bounds');
      return;
    }

    // Cancel any pending debounced fetch
    _stationFetchDebounce?.cancel();

    // Only fetch weather stations if zoom level is high enough (≥10)
    final currentZoom = MapConstants.roundZoomForDisplay(_mapController.camera.zoom);
    if (currentZoom < MapConstants.minForecastZoom) {
      LoggingService.info('Skipping station fetch: zoom level $currentZoom < ${MapConstants.minForecastZoom} (keeping cached stations)');
      return;  // Skip fetch but preserve existing cached stations
    }

    LoggingService.info('Station fetch triggered at zoom $currentZoom, starting debounce timer');

    // Debounce station fetches to avoid rapid API calls on map movement
    // 600ms allows typical API requests (400-500ms) to complete before new request
    _stationFetchDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;

      setState(() {
        _activeLoadingOperations.add(LoadingOperation.weatherStations);
        _providerStates.clear();
        _providersActuallyLoading.clear();  // Clear previous providers
      });

      try {
        // Log before fetching stations
        LoggingService.structured('STATION_FETCH_START', {
          'zoom_level': currentZoom.toStringAsFixed(2),
          'bounds': _currentBounds.toString(),
        });

        // Fetch stations in visible bounds with progressive updates
        final stations = await _weatherStationService.getStationsInBounds(
          _currentBounds!,
          onProgress: ({
            required source,
            required displayName,
            required success,
            required stationCount,
            required stations,
          }) async {
            if (mounted) {
              // Check if this provider is already in the loading set
              final isAlreadyLoading = _providersActuallyLoading.contains(source);

              // If not already loading and this is the initial call (stationCount=0, success=true)
              if (!isAlreadyLoading && success && stationCount == 0) {
                // Provider is starting an API call
                LoggingService.structured('PROVIDER_API_START', {
                  'provider': displayName,
                  'source': source.name,
                });
                setState(() {
                  _providersActuallyLoading.add(source);
                  _providerStates[source] = LoadingItemState.loading;
                });
              }
              // If already loading, this must be the completion (even with 0 stations)
              else if (isAlreadyLoading) {
                LoggingService.structured('PROVIDER_API_COMPLETE', {
                  'provider': displayName,
                  'success': success,
                  'station_count': stationCount,
                });
                setState(() {
                  // Set completion state (green check or red error icon)
                  _providerStates[source] = success
                      ? LoadingItemState.completed
                      : LoadingItemState.error;

                  // Cancel any existing dismiss timer for this provider
                  _providerDismissTimers[source]?.cancel();

                  // Auto-dismiss after 2 seconds (both success and error)
                  _providerDismissTimers[source] = Timer(const Duration(seconds: 2), () {
                    if (mounted) {
                      setState(() {
                        _providersActuallyLoading.remove(source);
                        _providerStates.remove(source);
                        _providerDismissTimers.remove(source);
                      });
                    }
                  });
                });
              }
              // Handle non-loading providers that return data immediately (cache hit)
              else if (!isAlreadyLoading && stationCount > 0) {
                LoggingService.structured('PROVIDER_CACHE_HIT', {
                  'provider': displayName,
                  'station_count': stationCount,
                });
                // Don't show in overlay - this was a cache hit
              }

              // Cumulative update: Replace all stations with deduplicated cumulative list
              // This creates progressive appearance as cumulative list grows with each provider
              if (stations.isNotEmpty) {
                final weatherData = await _weatherStationService.getWeatherForStations(stations);

                if (mounted) {
                  setState(() {
                    _weatherStations = stations;  // Replace (not add) with cumulative deduplicated stations
                    _stationWindData.clear();
                    _stationWindData.addAll(weatherData);
                  });

                  LoggingService.structured('STATION_PROGRESSIVE_UPDATE', {
                    'provider': source.name,
                    'station_count': stations.length,
                    'stations_with_data': weatherData.length,
                  });
                }
              }
            }
          },
        );

        LoggingService.structured('STATION_FETCH_RECEIVED', {
          'station_count': stations.length,
          'zoom_level': currentZoom.toStringAsFixed(2),
        });

        // Fetch weather data for stations (METAR always returns current data)
        final weatherData = await _weatherStationService.getWeatherForStations(
          stations,
        );

        if (mounted) {
          setState(() {
            _weatherStations = stations;
            _stationWindData.clear();
            _stationWindData.addAll(weatherData);
          });

          LoggingService.structured('STATION_FETCH_SUCCESS', {
            'total_stations': stations.length,
            'stations_with_data': weatherData.length,
            'time': _selectedDateTime.toIso8601String(),
            'zoom_level': currentZoom.toStringAsFixed(2),
          });

          // Remove the loading operation immediately after all providers complete
          setState(() {
            _activeLoadingOperations.remove(LoadingOperation.weatherStations);
            // Don't clear _providerStates or _providersActuallyLoading here
            // They are managed individually with timers for green ticks
          });
        }
      } catch (e, stackTrace) {
        LoggingService.error('Failed to fetch weather stations', e, stackTrace);

        // Show user-friendly error message
        if (mounted && context.mounted) {
          UiUtils.showErrorMessage(
            context,
            'Unable to load weather stations. Check your connection.',
          );
        }

        if (mounted) {
          setState(() {
            _activeLoadingOperations.remove(LoadingOperation.weatherStations);
            // Keep existing stations visible on error instead of clearing
            // Providers with errors will keep their red cross state
          });
        }
      }
    });
  }

  /// Refresh all weather data (stations and forecasts) by clearing caches
  /// and re-fetching from APIs
  Future<void> _refreshAllWeatherData() async {
    LoggingService.action('NearbySites', 'refresh_all_weather');

    // Clear all caches to force fresh data fetch
    _weatherStationService.clearCache();
    _weatherService.clearCache();

    // Re-fetch both weather stations and wind forecasts
    // The existing fetch methods handle loading states, debouncing, and UI updates
    await _fetchWeatherStations();
    await _fetchWindDataForSites();
  }

  /// Load favorite sites from database tables
  /// Queries both local sites table and PGE sites table for favorites
  /// Deduplicates sites that exist in both databases (prefer PGE version)
  Future<void> _loadFavorites() async {
    setState(() {
      _activeLoadingOperations.add(LoadingOperation.favorites);
    });

    try {
      // Get favorites from both database tables
      final localFavorites = await DatabaseService.instance.getFavoriteSites();
      final pgeFavorites = await PgeSitesDatabaseService.instance.getFavoriteSites();

      // Deduplicate: Remove local favorites that have pge_site_id matching a PGE favorite
      // This ensures we don't show duplicate sites when one exists in both databases
      final deduplicatedLocalFavorites = localFavorites.where((localSite) {
        // Keep custom local sites (no pge_site_id) always
        // Only exclude if this local site's pge_site_id matches a PGE favorite
        // NOTE: We can't directly access pge_site_id from ParaglidingSite, but we can
        // infer from the Site object if we had it. For now, we'll keep all local favorites
        // since they represent flown sites and should appear in the list.
        // TODO: May need to refine this logic based on actual usage patterns
        return true; // Keep all for now - will be addressed in database query optimization
      }).toList();

      // Combine PGE favorites with deduplicated local favorites
      final sites = <ParaglidingSite>[...pgeFavorites, ...deduplicatedLocalFavorites];

      LoggingService.action('NearbySites', 'favorites_menu_opened', {
        'local_favorites': localFavorites.length,
        'pge_favorites': pgeFavorites.length,
        'deduplicated_local': deduplicatedLocalFavorites.length,
        'total_favorites': sites.length,
      });

      // Sort by distance from user position if available
      if (_userPosition != null && sites.isNotEmpty) {
        sites.sort((a, b) {
          final distA = Geolocator.distanceBetween(
            _userPosition!.latitude,
            _userPosition!.longitude,
            a.latitude,
            a.longitude,
          );
          final distB = Geolocator.distanceBetween(
            _userPosition!.latitude,
            _userPosition!.longitude,
            b.latitude,
            b.longitude,
          );
          return distA.compareTo(distB);
        });
      }

      if (mounted) {
        setState(() {
          _favoriteSites = sites;
          _activeLoadingOperations.remove(LoadingOperation.favorites);
        });

        LoggingService.structured('FAVORITES_LOADED', {
          'local_favorites': localFavorites.length,
          'pge_favorites': pgeFavorites.length,
          'total_sites': sites.length,
          'sorted_by_distance': _userPosition != null,
        });
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to load favorites', e, stackTrace);
      if (mounted) {
        setState(() {
          _favoriteSites = [];
          _activeLoadingOperations.remove(LoadingOperation.favorites);
        });
      }
    }
  }

  /// Handle favorite site selection - navigate map to the selected site
  void _onFavoriteSelected(ParaglidingSite site) {
    LoggingService.action('NearbySites', 'favorite_selected', {
      'site_name': site.name,
      'latitude': site.latitude,
      'longitude': site.longitude,
    });

    // Navigate map to the favorite site
    _jumpToLocation(site, keepSearchActive: false);
  }

  /// Format distance for display in favorites menu
  String _formatDistance(double distanceMeters) {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()}m';
    } else {
      return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
    }
  }

  /// Check if any displayed site is missing wind data
  bool _hasMissingWindData({bool includeUnknownStatus = false}) {
    // Track statistics for summary logging
    int flyable = 0;
    int caution = 0;
    int notFlyable = 0;
    int loading = 0;
    int unknown = 0;
    int missing = 0;
    int total = _displayedSites.length;

    final hasMissing = _displayedSites.any((site) {
      final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
      if (includeUnknownStatus) {
        // Missing if: no wind data OR status is unknown/loading OR no status at all
        final hasWindData = _siteWindData.containsKey(key);
        final status = _siteFlyabilityStatus[key];
        final isMissing = !hasWindData ||
               status == FlyabilityStatus.unknown ||
               status == FlyabilityStatus.loading ||
               !_siteFlyabilityStatus.containsKey(key);

        // Collect statistics
        if (isMissing) {
          missing++;
        } else {
          switch (status) {
            case FlyabilityStatus.flyable:
              flyable++;
              break;
            case FlyabilityStatus.caution:
              caution++;
              break;
            case FlyabilityStatus.notFlyable:
              notFlyable++;
              break;
            case FlyabilityStatus.loading:
              loading++;
              break;
            case FlyabilityStatus.unknown:
              unknown++;
              break;
            default:
              break;
          }
        }

        return isMissing;
      }
      return !_siteWindData.containsKey(key) && !_siteFlyabilityStatus.containsKey(key);
    });

    // Log consolidated summary
    if (includeUnknownStatus && total > 0) {
      LoggingService.info('Wind check complete: $total sites | flyable=$flyable, caution=$caution, notFlyable=$notFlyable, loading=$loading, unknown=$unknown, missing=$missing');
    }

    return hasMissing;
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
    int caution = 0;
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
        } else if (status == FlyabilityStatus.caution) {
          caution++;
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
        // Note: daylight times not passed here to avoid async forecast fetching in sync method
        // This is acceptable as map markers show basic flyability without daylight filtering
        // Detailed daylight-aware flyability is shown in site details dialog and forecast tables
        // Use FlyabilityHelper for consistent 3-level logic
        final flyabilityLevel = FlyabilityHelper.getFlyabilityLevel(
          windData: wind,
          siteDirections: site.windDirections,
          maxSpeed: _maxWindSpeed,
          cautionSpeed: _cautionWindSpeed,
        );

        // Convert FlyabilityLevel to FlyabilityStatus
        switch (flyabilityLevel) {
          case FlyabilityLevel.safe:
            _siteFlyabilityStatus[key] = FlyabilityStatus.flyable;
            flyable++;
            break;
          case FlyabilityLevel.caution:
            _siteFlyabilityStatus[key] = FlyabilityStatus.caution;
            caution++;
            break;
          case FlyabilityLevel.unsafe:
            _siteFlyabilityStatus[key] = FlyabilityStatus.notFlyable;
            notFlyable++;
            break;
          case FlyabilityLevel.unknown:
            _siteFlyabilityStatus[key] = FlyabilityStatus.unknown;
            unknown++;
            break;
        }
      }
    }

    // Summary logging for Claude analysis
    if (calculated > 0 || forceRecalculation) {
      LoggingService.structured('FLYABILITY_UPDATE', {
        'total_sites': _displayedSites.length,
        'recalculated': calculated,
        'flyable': flyable,
        'caution': caution,
        'not_flyable': notFlyable,
        'unknown': unknown,
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _activeLoadingOperations.add(LoadingOperation.initialLoad);
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
          _activeLoadingOperations.remove(LoadingOperation.initialLoad);
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
          _activeLoadingOperations.remove(LoadingOperation.initialLoad);
        });
      }
    }
  }

  Future<Position?> _updateUserLocation() async {
    if (!mounted) return null;

    setState(() {
      _activeLoadingOperations.add(LoadingOperation.location);
    });

    try {
      final position = await _locationService.getCurrentPosition();
      if (mounted) {
        setState(() {
          _userPosition = position;
          _activeLoadingOperations.remove(LoadingOperation.location);
        });

        // Hide location notification if location was successfully obtained
        if (position != null) {
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
          _activeLoadingOperations.remove(LoadingOperation.location);
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

    // Simple inline filtering: show search results if searching, otherwise show all sites
    List<ParaglidingSite> filteredSites = _searchQuery.isNotEmpty && _searchResults.isNotEmpty
        ? _searchResults
        : _allSites;

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
      'search_query': _searchQuery.isEmpty ? null : _searchQuery,
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

      // Explicitly center map on user location (only when user requests it)
      _mapCenterPosition = userLocation;
      _mapController.move(userLocation, MapConstants.minForecastZoom);

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

    LoggingService.action('NearbySites', hasFlights ? 'flown_site_selected' : 'new_site_selected', {
      'site_id': site.id,
      'site_name': site.name,
      'site_type': site.siteType,
      'rating': site.rating,
      'has_flights': hasFlights,
    });
    _showSiteDetailsDialog(paraglidingSite: site);
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
    final newCenter = _mapController.camera.center;

    // Always update center position for map refresh (captures pans AND zooms)
    _mapCenterPosition = newCenter;

    // Update zoom overlay in real-time (also set map ready on first call)
    if (!_mapReady || _currentZoom != currentZoom) {
      setState(() {
        _mapReady = true;
        _currentZoom = currentZoom;
      });
    }

    // Check if bounds have changed significantly using MapBoundsManager
    // This prevents unnecessary reloads during minor map movements
    final boundsChangedSignificantly = MapBoundsManager.instance.haveBoundsChangedSignificantly('nearby_sites', bounds, _currentBounds);

    if (!boundsChangedSignificantly) {
      // Silently skip - no logging needed for normal map panning/zooming
      return;
    }

    _currentBounds = bounds;

    // Load sites if sites are enabled
    if (!_sitesEnabled) {
      // Still fetch weather stations even if sites are disabled
      _fetchWeatherStations();
      return;
    }

    // Use MapBoundsManager for debounced loading with caching
    MapBoundsManager.instance.loadSitesForBoundsDebounced(
      context: 'nearby_sites',
      bounds: bounds,
      zoomLevel: _mapController.camera.zoom,
      onLoaded: (result) {
        if (mounted) {
          setState(() {
            _processSitesLoaded(result);
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
              if (!_activeLoadingOperations.contains(LoadingOperation.wind)) {
                _fetchWindDataForSites();
              } else {
                LoggingService.debug('Skipping wind fetch (already loading)');
              }
            }
            // Also fetch weather stations
            _fetchWeatherStations();
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
        final currentZoom = MapConstants.roundZoomForDisplay(_mapController.camera.zoom);

        if (_displayedSites.isNotEmpty && currentZoom >= MapConstants.minForecastZoom) {
          final missingWindData = _hasMissingWindData(includeUnknownStatus: true);
          if (missingWindData) {
            if (!_activeLoadingOperations.contains(LoadingOperation.wind)) {
              LoggingService.info('Triggering wind fetch after bounds load completion');
              _fetchWindDataForSites();
            } else {
              LoggingService.debug('Skipping duplicate wind fetch (already loading)');
            }
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SiteDetailsDialog(
        site: null,
        paraglidingSite: paraglidingSite,
        userPosition: _userPosition,
        windData: windData,
        maxWindSpeed: _maxWindSpeed,
        cautionWindSpeed: _cautionWindSpeed,
        onWindDataFetched: (fetchedWindData) {
          // Update parent's cache when dialog fetches wind data
          setState(() {
            _siteWindData[windKey] = fetchedWindData;
            _updateFlyabilityStatus(forceRecalculation: true);
          });
        },
        onFavoriteToggled: () {
          // Reload favorites list when favorite is toggled
          _loadFavorites();
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
          weatherStationsEnabled: _weatherStationsEnabled,
          metarEnabled: _metarEnabled,
          nwsEnabled: _nwsEnabled,
          pioupiouEnabled: _pioupiouEnabled,
          ffvlEnabled: _ffvlEnabled,
          bomEnabled: _bomEnabled,
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
  void _handleFilterApply(bool sitesEnabled, bool airspaceEnabled, bool forecastEnabled, bool weatherStationsEnabled, bool metarEnabled, bool nwsEnabled, bool pioupiouEnabled, bool ffvlEnabled, bool bomEnabled, Map<String, bool> types, Map<String, bool> classes, double maxAltitudeFt, bool clippingEnabled) async {
    try {
      // Update filter states
      final previousSitesEnabled = _sitesEnabled;
      final previousAirspaceEnabled = _airspaceEnabled;
      final previousForecastEnabled = _forecastEnabled;
      final previousWeatherStationsEnabled = _weatherStationsEnabled;
      final previousMetarEnabled = _metarEnabled;
      final previousNwsEnabled = _nwsEnabled;
      final previousPioupiouEnabled = _pioupiouEnabled;
      final previousFfvlEnabled = _ffvlEnabled;
      final previousBomEnabled = _bomEnabled;

      // Update non-airspace states immediately
      setState(() {
        _sitesEnabled = sitesEnabled;
        // Don't update _airspaceEnabled yet - will be set after async operations complete
        _forecastEnabled = forecastEnabled;
        _weatherStationsEnabled = weatherStationsEnabled;
        _metarEnabled = metarEnabled;
        _nwsEnabled = nwsEnabled;
        _pioupiouEnabled = pioupiouEnabled;
        _ffvlEnabled = ffvlEnabled;
        _bomEnabled = bomEnabled;
        _maxAltitudeFt = maxAltitudeFt;
      });

      // Save the enabled states to preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sitesEnabledKey, sitesEnabled);
      await prefs.setBool(_airspaceEnabledKey, airspaceEnabled);
      await prefs.setBool(_forecastEnabledKey, forecastEnabled);
      await prefs.setBool(_weatherStationsEnabledKey, weatherStationsEnabled);
      await prefs.setBool('weather_provider_${WeatherStationSource.awcMetar.name}_enabled', metarEnabled);
      await prefs.setBool('weather_provider_${WeatherStationSource.nws.name}_enabled', nwsEnabled);
      await prefs.setBool('weather_provider_${WeatherStationSource.pioupiou.name}_enabled', pioupiouEnabled);
      await prefs.setBool('weather_provider_${WeatherStationSource.ffvl.name}_enabled', ffvlEnabled);
      await prefs.setBool('weather_provider_${WeatherStationSource.bom.name}_enabled', bomEnabled);

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
        // Sites were enabled - reload sites immediately (no debouncing for user toggle)
        if (_currentBounds != null) {
          // Clear cache and load immediately
          MapBoundsManager.instance.clearCache('nearby_sites');
          await MapBoundsManager.instance.loadSitesForBoundsImmediate(
            context: 'nearby_sites',
            bounds: _currentBounds!,
            zoomLevel: _mapController.camera.zoom,
            onLoaded: (result) {
              if (mounted) {
                setState(() {
                  _processSitesLoaded(result);
                });

                LoggingService.structured('NEARBY_SITES_ENABLED_LOADED', {
                  'sites_count': result.sites.length,
                  'flown_sites': result.sitesWithFlights.length,
                  'new_sites': result.sitesWithoutFlights.length,
                });

                // Fetch wind data if forecast enabled and zoomed in enough
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (!mounted) return;
                  if (_displayedSites.isNotEmpty && (_hasMissingWindData() || _siteWindData.isEmpty)) {
                    _fetchWindDataForSites();
                  }
                  // Also fetch weather stations
                  _fetchWeatherStations();
                });
              }
            },
          );
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
        final currentZoom = MapConstants.roundZoomForDisplay(_mapController.camera.zoom);
        if (_displayedSites.isNotEmpty && currentZoom >= MapConstants.minForecastZoom) {
          _fetchWindDataForSites();
        }
        LoggingService.action('MapFilter', 'forecast_enabled', {'will_fetch': currentZoom >= MapConstants.minForecastZoom});
      }

      // Handle weather stations visibility changes
      if (!weatherStationsEnabled && previousWeatherStationsEnabled) {
        // Weather stations were disabled - clear station data and cache
        setState(() {
          _weatherStations.clear();
          _stationWindData.clear();
        });
        WeatherStationService.instance.clearCache();
        LoggingService.action('MapFilter', 'weather_stations_disabled', {'cleared_stations': true, 'cleared_cache': true});
      } else if (weatherStationsEnabled && !previousWeatherStationsEnabled) {
        // Weather stations were enabled - fetch stations if zoomed in
        final currentZoom = MapConstants.roundZoomForDisplay(_mapController.camera.zoom);
        if (currentZoom >= MapConstants.minForecastZoom) {
          _fetchWeatherStations();
        }
        LoggingService.action('MapFilter', 'weather_stations_enabled', {'will_fetch': currentZoom >= MapConstants.minForecastZoom});
      } else if (weatherStationsEnabled && (metarEnabled != previousMetarEnabled || nwsEnabled != previousNwsEnabled || pioupiouEnabled != previousPioupiouEnabled || ffvlEnabled != previousFfvlEnabled || bomEnabled != previousBomEnabled)) {
        // Weather station providers changed - refresh stations
        final currentZoom = MapConstants.roundZoomForDisplay(_mapController.camera.zoom);
        if (currentZoom >= MapConstants.minForecastZoom) {
          // Clear existing stations and re-fetch with new provider configuration
          WeatherStationService.instance.clearCache();
          _fetchWeatherStations();
        }
        LoggingService.action('MapFilter', 'weather_providers_changed', {
          'metar_enabled': metarEnabled,
          'nws_enabled': nwsEnabled,
          'pioupiou_enabled': pioupiouEnabled,
          'ffvl_enabled': ffvlEnabled,
          'bom_enabled': bomEnabled,
          'metar_changed': metarEnabled != previousMetarEnabled,
          'nws_changed': nwsEnabled != previousNwsEnabled,
          'pioupiou_changed': pioupiouEnabled != previousPioupiouEnabled,
          'ffvl_changed': ffvlEnabled != previousFfvlEnabled,
          'bom_changed': bomEnabled != previousBomEnabled,
        });
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

        // Update filters first, then enable airspace
        await _openAipService.setExcludedAirspaceTypes(typesEnum);
        await _openAipService.setExcludedIcaoClasses(classesEnum);
        await _openAipService.setClippingEnabled(clippingEnabled);
        await _openAipService.setAirspaceEnabled(true);

        // Check if filters changed (requires reload even if airspace was already enabled)
        final filtersChanged = _excludedIcaoClasses != classesEnum ||
                               _maxAltitudeFt != maxAltitudeFt ||
                               _airspaceClippingEnabled != clippingEnabled;

        // Update local state AFTER all async operations complete
        // This ensures the map widget rebuilds with correct service state
        setState(() {
          _excludedIcaoClasses = classesEnum;
          _maxAltitudeFt = maxAltitudeFt;
          _airspaceEnabled = true;
          _airspaceClippingEnabled = clippingEnabled;
          // Increment version to trigger immediate airspace reload
          if (filtersChanged || !previousAirspaceEnabled) {
            _airspaceDataVersion++;
          }
        });

        if (!previousAirspaceEnabled) {
          LoggingService.action('MapFilter', 'airspace_enabled');
        } else if (filtersChanged) {
          LoggingService.action('MapFilter', 'airspace_filters_changed', {
            'classes_changed': _excludedIcaoClasses != classesEnum,
            'altitude_changed': _maxAltitudeFt != maxAltitudeFt,
            'clipping_changed': _airspaceClippingEnabled != clippingEnabled,
          });
        }
      } else if (!airspaceEnabled) {
        // Disable airspace completely
        await _openAipService.setAirspaceEnabled(false);

        // Update local state AFTER async operation completes
        setState(() {
          _airspaceEnabled = false;
        });

        // Note: We preserve _excludedIcaoClasses in memory so filters are retained
        // when airspace is re-enabled. This provides better UX for quick toggles.

        if (previousAirspaceEnabled) {
          LoggingService.action('MapFilter', 'airspace_disabled', {
            'preserved_filter_count': _excludedIcaoClasses.values.where((v) => v).length,
            'filters_preserved': true,
          });
        }
      }

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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onSearchChanged,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search nearby sites...',
              hintStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.7)),
              prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: Colors.white),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
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
          // Favorites PopupMenuButton
          PopupMenuButton<ParaglidingSite>(
            icon: const Icon(Icons.favorite),
            tooltip: 'Favorites',
            enabled: !_activeLoadingOperations.contains(LoadingOperation.favorites),
            onOpened: _loadFavorites,
            itemBuilder: (context) {
              if (_activeLoadingOperations.contains(LoadingOperation.favorites)) {
                return [
                  const PopupMenuItem(
                    enabled: false,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Loading favorites...'),
                      ],
                    ),
                  ),
                ];
              }

              if (_favoriteSites.isEmpty) {
                return [
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('No favorites yet'),
                  ),
                ];
              }

              return _favoriteSites.map((site) {
                String distanceText = '';
                if (_userPosition != null) {
                  final distance = Geolocator.distanceBetween(
                    _userPosition!.latitude,
                    _userPosition!.longitude,
                    site.latitude,
                    site.longitude,
                  );
                  distanceText = ' • ${_formatDistance(distance)}';
                }

                return PopupMenuItem<ParaglidingSite>(
                  value: site,
                  child: Row(
                    children: [
                      const Icon(Icons.place, size: 18, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${site.name}$distanceText',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            onSelected: _onFavoriteSelected,
          ),
          MapSettingsMenu(
            selectedMapProvider: (_mapKey.currentState as BaseMapState?)?.selectedMapProvider ?? MapProvider.openStreetMap,
            onMapProviderSelected: (provider) {
              (_mapKey.currentState as BaseMapState?)?.selectMapProvider(provider);
              setState(() {}); // Force rebuild to update checkbox
            },
            onRefreshAll: _refreshAllWeatherData,
            onMapFilters: _showMapFilterDialog,
            refreshDisabled: _activeLoadingOperations.contains(LoadingOperation.weatherStations) ||
                             _activeLoadingOperations.contains(LoadingOperation.wind),
            hasActiveFilters: _hasActiveFilters,
          ),
          AppMenuButton(
            onDataChanged: _handleSiteDataChanged, // Call local handler which clears cache and reloads
            onRefreshAllTabs: widget.onRefreshAllTabs,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          _activeLoadingOperations.contains(LoadingOperation.initialLoad)
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
                          key: _mapKey,
                          mapController: _mapController,
                          airspaceDataVersion: _airspaceDataVersion,
                          sitesDataVersion: _sitesDataVersion,
                          sites: _displayedSites,
                          userLocation: _userPosition != null
                              ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
                              : null,
                          airspaceEnabled: _airspaceEnabled,
                          maxAltitudeFt: _maxAltitudeFt,
                          airspaceClippingEnabled: _airspaceClippingEnabled,
                          onSiteSelected: _onSiteSelected,
                          onLocationRequest: _onRefreshLocation,
                          onSitesDataVersionChanged: _handleSitesVersionChanged,
                          siteWindData: _siteWindData,
                          siteFlyabilityStatus: _siteFlyabilityStatus,
                          maxWindSpeed: _maxWindSpeed,
                          cautionWindSpeed: _cautionWindSpeed,
                          selectedDateTime: _selectedDateTime,
                          forecastEnabled: _forecastEnabled,
                          weatherStations: _weatherStations,
                          stationWindData: _stationWindData,
                          weatherStationsEnabled: _weatherStationsEnabled,
                          onBoundsChanged: _onBoundsChanged,
                          showUserLocation: true,
                          isLocationLoading: _activeLoadingOperations.contains(LoadingOperation.location),
                          initialCenter: _mapCenterPosition,
                          initialZoom: _currentZoom,
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

          // Combined loading overlay for sites, wind, and weather stations
          // Only show if there are actually things loading
          if (MapBoundsManager.instance.isLoading('nearby_sites') ||
              _forecastActuallyCallingApi ||
              _providersActuallyLoading.isNotEmpty)
            MapLoadingOverlay.multiple(
              items: [
                if (MapBoundsManager.instance.isLoading('nearby_sites'))
                  const MapLoadingItem(
                    label: 'Sites',
                    icon: Icons.place,
                    iconColor: Colors.blue,
                  ),
                // Only show wind forecast when it's actually calling API (not cached)
                if (_forecastActuallyCallingApi)
                  MapLoadingItem(
                    label: 'Wind forecast',
                    icon: Icons.air,
                    iconColor: Colors.lightBlue,
                    count: _displayedSites.length,
                    state: _activeLoadingOperations.contains(LoadingOperation.wind)
                        ? LoadingItemState.loading
                        : _forecastHasError
                            ? LoadingItemState.error  // Show red cross on error
                            : LoadingItemState.completed,  // Show green tick on success
                  ),
                // Only show weather station providers that are actually making API calls
                ..._providersActuallyLoading.map((source) {
                  final provider = WeatherStationProviderRegistry.getProvider(source);
                  final state = _providerStates[source] ?? LoadingItemState.loading;

                  return MapLoadingItem(
                    label: provider.displayName,
                    icon: Icons.cloud,
                    iconColor: Colors.orange,
                    state: state,
                  );
                }),
              ],
            ),

          // Zoom level indicator overlay (bottom-left) - only show when map is ready
          if (_mapReady)
            Positioned(
              bottom: 20,
              left: 16,
              child: Tooltip(
                message: MapConstants.roundZoomForDisplay(_currentZoom) < MapConstants.minForecastZoom
                    ? 'Zoom in to 10 or greater to see flyability forecasts and weather station observations'
                    : 'Zoom level',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Z${MapConstants.roundZoomForDisplay(_currentZoom).toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),

          // Search dropdown overlay
          if (_searchQuery.isNotEmpty && (_isSearching || _searchResults.isNotEmpty))
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _isSearching
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Searching sites...',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final site = _searchResults[index];
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: Text(
                                (site.country != null && site.country!.length >= 2)
                                    ? site.country!.toUpperCase().substring(0, 2)
                                    : '??',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            title: Text(
                              site.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              site.country ?? 'Unknown',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            onTap: () {
                              _jumpToLocation(site, keepSearchActive: false);
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                                _searchResults = [];
                              });
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

class _DraggableFilterDialog extends StatefulWidget {
  final bool sitesEnabled;
  final bool airspaceEnabled;
  final bool forecastEnabled;
  final bool weatherStationsEnabled;
  final bool metarEnabled;
  final bool nwsEnabled;
  final bool pioupiouEnabled;
  final bool ffvlEnabled;
  final bool bomEnabled;
  final Map<String, bool> airspaceTypes;
  final Map<String, bool> icaoClasses;
  final double maxAltitudeFt;
  final bool clippingEnabled;
  final Function(
    bool sitesEnabled,
    bool airspaceEnabled,
    bool forecastEnabled,
    bool weatherStationsEnabled,
    bool metarEnabled,
    bool nwsEnabled,
    bool pioupiouEnabled,
    bool ffvlEnabled,
    bool bomEnabled,
    Map<String, bool> types,
    Map<String, bool> classes,
    double maxAltitudeFt,
    bool clippingEnabled,
  ) onApply;

  const _DraggableFilterDialog({
    required this.sitesEnabled,
    required this.airspaceEnabled,
    required this.forecastEnabled,
    required this.weatherStationsEnabled,
    required this.metarEnabled,
    required this.nwsEnabled,
    required this.pioupiouEnabled,
    required this.ffvlEnabled,
    required this.bomEnabled,
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
                  _position.dy.clamp(0, screenSize.height - 600), // Assume dialog height ~600
                );
              });
            },
            child: Material(
              color: Colors.transparent,
              child: MapFilterDialog(
                sitesEnabled: widget.sitesEnabled,
                airspaceEnabled: widget.airspaceEnabled,
                forecastEnabled: widget.forecastEnabled,
                weatherStationsEnabled: widget.weatherStationsEnabled,
                metarEnabled: widget.metarEnabled,
                nwsEnabled: widget.nwsEnabled,
                pioupiouEnabled: widget.pioupiouEnabled,
                ffvlEnabled: widget.ffvlEnabled,
                bomEnabled: widget.bomEnabled,
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
