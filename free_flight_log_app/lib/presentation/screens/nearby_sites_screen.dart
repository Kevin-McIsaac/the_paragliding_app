import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/airspace_enums.dart';
import '../../services/database_service.dart';
import '../../services/location_service.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';
import '../../services/nearby_sites_search_state.dart';
import '../../services/nearby_sites_search_manager.dart';
import '../../utils/map_provider.dart';
import '../../utils/site_utils.dart';
import '../widgets/nearby_sites_map_widget.dart';
import '../widgets/map_filter_dialog.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/site_details_dialog.dart';
import '../../services/openaip_service.dart';
import '../../utils/performance_monitor.dart';


class NearbySitesScreen extends StatefulWidget {
  const NearbySitesScreen({super.key});

  @override
  State<NearbySitesScreen> createState() => _NearbySitesScreenState();
}

class _NearbySitesScreenState extends State<NearbySitesScreen> {
  final DatabaseService _databaseService = DatabaseService.instance;
  final LocationService _locationService = LocationService.instance;
  final ParaglidingEarthApi _paraglidingEarthApi = ParaglidingEarthApi.instance;
  
  // Constants for bounds-based loading (copied from EditSiteScreen)
  static const double _boundsThreshold = 0.001;
  static const int _debounceDurationMs = 750; // Increased debounce to reduce API calls
  
  // Unified state variables - all sites are ParaglidingSite objects from API
  List<ParaglidingSite> _allSites = [];
  List<ParaglidingSite> _displayedSites = [];
  Map<String, bool> _siteFlightStatus = {}; // Key: "lat,lng", Value: hasFlights
  Position? _userPosition;
  bool _isLoading = false;
  bool _isLocationLoading = false;
  String? _errorMessage;
  LatLng? _mapCenterPosition;
  final double _mapZoom = 10.0; // Dynamic zoom level for map
  LatLngBounds? _boundsToFit; // Exact bounds for map fitting after site jump
  
  // Map provider state
  MapProvider _selectedMapProvider = MapProvider.openStreetMap;
  
  // Key to force map widget refresh when airspace settings change
  final Key _mapWidgetKey = UniqueKey();
  static const String _mapProviderKey = 'nearby_sites_map_provider';

  // Legend state
  bool _isLegendExpanded = false;
  static const String _legendExpandedKey = 'nearby_sites_legend_expanded';

  // Bounds-based loading state
  Timer? _debounceTimer;
  LatLngBounds? _currentBounds;
  bool _isLoadingSites = false;
  String? _lastLoadedBoundsKey;

  // Location notification state
  bool _showLocationNotification = false;
  Timer? _locationNotificationTimer;
  late final NearbySitesSearchManager _searchManager;

  // Filter state for sites and airspace
  bool _sitesEnabled = true;
  bool _airspaceEnabled = true;
  double _maxAltitudeFt = 10000.0;
  int _filterUpdateCounter = 0;
  Map<IcaoClass, bool> _excludedIcaoClasses = {};
  final OpenAipService _openAipService = OpenAipService.instance;
  

  @override
  void initState() {
    super.initState();
    _initializeSearchManager();
    _loadPreferences();
    _loadFilterSettings();
    _loadData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel(); // Clean up timer
    _locationNotificationTimer?.cancel(); // Clean up location notification timer
    _searchManager.dispose(); // Clean up search manager
    super.dispose();
  }

  void _initializeSearchManager() {
    _searchManager = NearbySitesSearchManager(
      onStateChanged: (SearchState state) {
        setState(() {
          // Update displayed sites when search state changes
          _updateDisplayedSites();
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
      final providerIndex = prefs.getInt(_mapProviderKey) ?? MapProvider.openStreetMap.index;
      final legendExpanded = prefs.getBool(_legendExpandedKey) ?? false;

      if (mounted) {
        setState(() {
          _selectedMapProvider = MapProvider.values[providerIndex];
          _isLegendExpanded = legendExpanded;
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
      // Initialize empty unified structure
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
    final stopwatch = Stopwatch()..start();
    
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
    
    setState(() {
      _displayedSites = filteredSites;
    });
    
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
    
    LoggingService.action('NearbySites', hasFlights ? 'flown_site_selected' : 'new_site_selected', {
      'site_id': site.id,
      'site_name': site.name,
      'site_type': site.siteType,
      'rating': site.rating,
      'has_flights': hasFlights,
    });
    _showSiteDetailsDialog(paraglidingSite: site);
  }

  void _toggleLegend() async {
    setState(() {
      _isLegendExpanded = !_isLegendExpanded;
    });
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_legendExpandedKey, _isLegendExpanded);
    } catch (e) {
      LoggingService.error('Failed to save legend preference', e);
    }
  }


  /// Jump to a location without dismissing search results
  void _jumpToLocation(ParaglidingSite site, {bool keepSearchActive = false}) {
    // Create exact bounds for API search (±0.05 degrees)
    final newCenter = LatLng(site.latitude, site.longitude);
    final bounds = LatLngBounds(
      LatLng(newCenter.latitude - 0.05, newCenter.longitude - 0.05),
      LatLng(newCenter.latitude + 0.05, newCenter.longitude + 0.05),
    );
    
    setState(() {
      // Set map to fit exactly the bounds used for API search
      _mapCenterPosition = newCenter;
      _boundsToFit = bounds; // This will trigger exact bounds fitting in map widget
    });
    
    // Use a very short delay just to allow the map to update its center
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _onBoundsChanged(bounds);
      }
    });
    
    // Clear bounds after map has fitted to allow normal navigation
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _boundsToFit = null; // Clear bounds to allow normal map navigation
        });
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
    // Debounce the bounds change to prevent excessive API calls
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: _debounceDurationMs), () {
      _updateMapBounds(bounds);
    });
  }

  void _updateMapBounds(LatLngBounds bounds) {
    // Check if bounds have changed significantly
    if (_currentBounds != null) {
      // Check if any corner of the bounds has moved more than the threshold
      if ((bounds.north - _currentBounds!.north).abs() < _boundsThreshold &&
          (bounds.south - _currentBounds!.south).abs() < _boundsThreshold &&
          (bounds.east - _currentBounds!.east).abs() < _boundsThreshold &&
          (bounds.west - _currentBounds!.west).abs() < _boundsThreshold) {
        return; // Bounds haven't changed significantly
      }
    }
    _currentBounds = bounds;
    _loadSitesForBounds(bounds);
  }

  Future<void> _loadSitesForBounds(LatLngBounds bounds) async {
    if (_isLoadingSites) {
      return;
    }

    // Skip loading sites if they're disabled
    if (!_sitesEnabled) {
      return;
    }

    // Create a unique key for these bounds to prevent duplicate requests
    final boundsKey = '${bounds.north.toStringAsFixed(6)}_${bounds.south.toStringAsFixed(6)}_${bounds.east.toStringAsFixed(6)}_${bounds.west.toStringAsFixed(6)}';
    if (_lastLoadedBoundsKey == boundsKey) {
      LoggingService.info('Sites loading skipped - same bounds already loaded');
      return; // Same bounds already loaded
    }

    setState(() {
      _isLoadingSites = true;
    });

    LoggingService.info('Starting site load for bounds: $boundsKey');
    final totalStopwatch = Stopwatch()..start();
    final memoryBefore = PerformanceMonitor.getMemoryUsageMB();

    try {
      // 1. Load local sites from DB to check flight status
      final dbStopwatch = Stopwatch()..start();
      final localSites = await _databaseService.getSitesInBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      );
      dbStopwatch.stop();

      LoggingService.performance(
        'Sites DB Query',
        Duration(milliseconds: dbStopwatch.elapsedMilliseconds),
        'sites=${localSites.length}'
      );

      // 2. Load API sites within bounds
      final apiStopwatch = Stopwatch()..start();
      final apiSites = await _paraglidingEarthApi.getSitesInBounds(
        bounds.north,
        bounds.south,
        bounds.east,
        bounds.west,
        limit: 50,
        detailed: false,
      );
      apiStopwatch.stop();

      LoggingService.performance(
        'Sites API Fetch',
        Duration(milliseconds: apiStopwatch.elapsedMilliseconds),
        'sites=${apiSites.length}, bounds=${bounds.west},${bounds.south},${bounds.east},${bounds.north}'
      );
      
      // 3. For each local site, try to find its corresponding API data
      final dedupStopwatch = Stopwatch()..start();
      final unifiedSites = <ParaglidingSite>[];
      final siteFlightStatus = <String, bool>{};

      // Add API sites with flight status checking
      for (final apiSite in apiSites) {
        final siteKey = SiteUtils.createSiteKey(apiSite.latitude, apiSite.longitude);
        
        // Check if this API site matches any local site (has been flown)
        final hasFlights = localSites.any((localSite) =>
          (localSite.latitude - apiSite.latitude).abs() < 0.000001 &&
          (localSite.longitude - apiSite.longitude).abs() < 0.000001);
          
        siteFlightStatus[siteKey] = hasFlights;
        unifiedSites.add(apiSite);
      }
      
      // 4. For local sites not found in API, create minimal representations
      for (final localSite in localSites) {
        final siteKey = SiteUtils.createSiteKey(localSite.latitude, localSite.longitude);
        
        // Skip if already found in API sites
        if (siteFlightStatus.containsKey(siteKey)) continue;
        
        // Create a minimal ParaglidingSite from local data without API lookup
        final minimalApiSite = ParaglidingSite(
          name: localSite.name,
          latitude: localSite.latitude,
          longitude: localSite.longitude,
          altitude: localSite.altitude?.toInt(),
          siteType: 'launch', // Default to launch for local sites
          country: localSite.country ?? '',
          // Other fields will be null/empty
        );
        siteFlightStatus[siteKey] = true; // Local site has flights
        unifiedSites.add(minimalApiSite);
      }
      dedupStopwatch.stop();

      // 4. UI update
      final uiUpdateStopwatch = Stopwatch()..start();
      if (mounted) {
        setState(() {
          _allSites = unifiedSites;
          _siteFlightStatus = siteFlightStatus;
          _isLoadingSites = false;
          
          // Clear pinned site only if not from auto-jump or search is no longer active
          if (!_searchManager.state.pinnedSiteIsFromAutoJump || _searchManager.state.query.isEmpty) {
            // Note: SearchManager handles pinned site clearing internally
            // No need to manually clear here anymore
          }
          
          // Update displayed sites with the new bounds data
          _updateDisplayedSites();
        });
        uiUpdateStopwatch.stop();

        // Mark these bounds as loaded to prevent duplicate requests
        _lastLoadedBoundsKey = boundsKey;

        // Log detailed site loading breakdown
        totalStopwatch.stop();
        final memoryAfter = PerformanceMonitor.getMemoryUsageMB();

        LoggingService.structured('SITES_BREAKDOWN', {
          'db_query_ms': dbStopwatch.elapsedMilliseconds,
          'api_call_ms': apiStopwatch.elapsedMilliseconds,
          'dedup_ms': dedupStopwatch.elapsedMilliseconds,
          'ui_update_ms': uiUpdateStopwatch.elapsedMilliseconds,
          'total_ms': totalStopwatch.elapsedMilliseconds,
          'local_sites': localSites.length,
          'api_sites': apiSites.length,
          'unified_sites': unifiedSites.length,
          'memory_before_mb': memoryBefore.toStringAsFixed(1),
          'memory_after_mb': memoryAfter.toStringAsFixed(1),
          'memory_delta_mb': (memoryAfter - memoryBefore).toStringAsFixed(1),
        });
        
        LoggingService.structured('BOUNDS_SITES_LOADED', {
          'local_sites_count': localSites.length,
          'api_sites_count': apiSites.length,
          'unified_sites_count': unifiedSites.length,
          'bounds_key': boundsKey,
        });
      }
    } catch (e) {
      LoggingService.error('NearbySitesScreen: Error loading sites for bounds', e);
      if (mounted) {
        setState(() {
          _isLoadingSites = false;
          // Note: SearchManager handles pinned site state internally
        });
      }
    }
  }


  void _showSiteDetailsDialog({required ParaglidingSite paraglidingSite}) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (context) => SiteDetailsDialog(
        site: null,
        paraglidingSite: paraglidingSite,
        userPosition: _userPosition,
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
          airspaceTypes: airspaceTypes,
          icaoClasses: icaoClasses,
          maxAltitudeFt: _maxAltitudeFt,
          clippingEnabled: clippingEnabled,
          mapProvider: _selectedMapProvider,
          onApply: _handleFilterApply,
        ),
      );
    } catch (error, stackTrace) {
      LoggingService.error('Failed to show map filter dialog', error, stackTrace);
    }
  }

  /// Handle filter apply from dialog
  void _handleFilterApply(bool sitesEnabled, bool airspaceEnabled, Map<String, bool> types, Map<String, bool> classes, double maxAltitudeFt, bool clippingEnabled, MapProvider mapProvider) async {
    try {
      // Update filter states
      final previousSitesEnabled = _sitesEnabled;
      final previousAirspaceEnabled = _airspaceEnabled;
      final previousMapProvider = _selectedMapProvider;

      setState(() {
        _sitesEnabled = sitesEnabled;
        _airspaceEnabled = airspaceEnabled;
        _maxAltitudeFt = maxAltitudeFt;
        _selectedMapProvider = mapProvider;
      });

      // Handle sites visibility changes
      if (!sitesEnabled && previousSitesEnabled) {
        // Sites were disabled - clear displayed sites and reset the bounds key
        setState(() {
          _displayedSites.clear();
          _allSites.clear();
          _lastLoadedBoundsKey = ''; // Clear the bounds key so sites reload when re-enabled
        });
        LoggingService.action('MapFilter', 'sites_disabled', {'cleared_sites_count': _displayedSites.length});
      } else if (sitesEnabled && !previousSitesEnabled) {
        // Sites were enabled - reload sites for current bounds or trigger map refresh
        if (_currentBounds != null) {
          // Force reload by clearing the last loaded bounds key
          _lastLoadedBoundsKey = '';
          _loadSitesForBounds(_currentBounds!);
        }
        LoggingService.action('MapFilter', 'sites_enabled', {'reloading_sites': true, 'has_bounds': _currentBounds != null});
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

      // Handle map provider changes
      if (mapProvider != previousMapProvider) {
        await _saveMapProviderPreference(mapProvider);
        LoggingService.action('MapFilter', 'map_provider_changed', {'provider': mapProvider.displayName});
      }

      // Refresh map to apply airspace filter changes
      setState(() {
        // Increment counter to trigger map overlay refresh
        _filterUpdateCounter++;
        // This preserves the map position and zoom level
      });

      LoggingService.structured('MAP_FILTER_APPLIED_SUCCESS', {
        'sites_enabled': sitesEnabled,
        'airspace_enabled': airspaceEnabled,
        'sites_changed': sitesEnabled != previousSitesEnabled,
        'airspace_changed': airspaceEnabled != previousAirspaceEnabled,
        'map_provider_changed': mapProvider != previousMapProvider,
        'selected_types': types.values.where((v) => v).length,
        'selected_classes': classes.values.where((v) => v).length,
        'max_altitude_ft': maxAltitudeFt,
        'map_provider': mapProvider.displayName,
      });
    } catch (error, stackTrace) {
      LoggingService.error('Failed to apply map filters', error, stackTrace);
    }
  }

  /// Save map provider preference
  Future<void> _saveMapProviderPreference(MapProvider provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_mapProviderKey, provider.index);
    } catch (e) {
      LoggingService.error('Failed to save map provider preference', e);
    }
  }

  /// Check if filters are currently active (for FAB indicator)
  Future<bool> _hasActiveFilters() async {
    try {
      // Check if any airspace types or classes are disabled from defaults
      final types = await _openAipService.getExcludedAirspaceTypes();
      final classes = await _openAipService.getExcludedIcaoClasses();

      // Consider filters active if any type/class is disabled or sites are disabled
      final hasDisabledTypes = types.values.contains(false);
      final hasDisabledClasses = classes.values.contains(false);

      return !_sitesEnabled || hasDisabledTypes || hasDisabledClasses;
    } catch (error) {
      LoggingService.error('Failed to check active filters', error);
      return false; // Assume no active filters on error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Sites'),
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
                        // Map
                        FutureBuilder<bool>(
                          future: _hasActiveFilters(),
                          builder: (context, snapshot) {
                            final hasActiveFilters = snapshot.data ?? false;
                            return NearbySitesMapWidget(
                              key: _mapWidgetKey, // Force rebuild when airspace settings change
                              sites: _displayedSites,
                              siteFlightStatus: _siteFlightStatus,
                              userPosition: _userPosition,
                              centerPosition: _mapCenterPosition,
                              boundsToFit: _boundsToFit,
                              initialZoom: _mapZoom,
                              mapProvider: _selectedMapProvider,
                              isLegendExpanded: _isLegendExpanded,
                              onToggleLegend: _toggleLegend,
                                              onSiteSelected: _onSiteSelected,
                              onBoundsChanged: _onBoundsChanged,
                              searchQuery: _searchManager.state.query,
                              onSearchChanged: _searchManager.onSearchQueryChanged,
                              onRefreshLocation: _onRefreshLocation,
                              isLocationLoading: _isLocationLoading,
                              searchResults: _searchManager.state.results,
                              isSearching: _searchManager.state.isSearching,
                              onSearchResultSelected: (site) {
                                _searchManager.selectSearchResult(site);
                                // Also jump to location for smooth UX
                                _jumpToLocation(site);
                              },
                              onShowMapFilter: _showMapFilterDialog,
                              hasActiveFilters: hasActiveFilters,
                              sitesEnabled: _sitesEnabled,
                              maxAltitudeFt: _maxAltitudeFt,
                              filterUpdateCounter: _filterUpdateCounter,
                              excludedIcaoClasses: _excludedIcaoClasses,
                            );
                          },
                        ),
                        
                        // Loading overlay for dynamic site loading
                        if (_isLoadingSites)
                          Positioned(
                            top: 60, // Moved down to avoid controls
                            right: 16, // Positioned on right for better visibility
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                      strokeCap: StrokeCap.round,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Loading nearby sites...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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


/// Draggable dialog widget for the map filter
class _DraggableFilterDialog extends StatefulWidget {
  final bool sitesEnabled;
  final bool airspaceEnabled;
  final Map<String, bool> airspaceTypes;
  final Map<String, bool> icaoClasses;
  final double maxAltitudeFt;
  final bool clippingEnabled;
  final MapProvider mapProvider;
  final Function(bool sitesEnabled, bool airspaceEnabled, Map<String, bool> types, Map<String, bool> classes, double maxAltitudeFt, bool clippingEnabled, MapProvider mapProvider) onApply;

  const _DraggableFilterDialog({
    required this.sitesEnabled,
    required this.airspaceEnabled,
    required this.airspaceTypes,
    required this.icaoClasses,
    required this.maxAltitudeFt,
    required this.clippingEnabled,
    required this.mapProvider,
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
                airspaceTypes: widget.airspaceTypes,
                icaoClasses: widget.icaoClasses,
                maxAltitudeFt: widget.maxAltitudeFt,
                clippingEnabled: widget.clippingEnabled,
                mapProvider: widget.mapProvider,
                onApply: widget.onApply,
              ),
            ),
          ),
        ),
      ],
    );
  }
}