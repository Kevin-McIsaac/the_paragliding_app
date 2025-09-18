import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/airspace_enums.dart';
import '../../services/database_service.dart';
import '../../services/location_service.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';
import '../../services/nearby_sites_search_state.dart';
import '../../services/nearby_sites_search_manager.dart';
import '../../services/site_bounds_loader.dart';
import '../../data/models/unified_site.dart';
import '../../utils/map_provider.dart';
import '../../utils/site_utils.dart';
import '../widgets/nearby_sites_map_widget.dart';
import '../widgets/map_filter_dialog.dart';
import '../widgets/common/app_error_state.dart';
import '../../services/openaip_service.dart';


class NearbySitesScreen extends StatefulWidget {
  const NearbySitesScreen({super.key});

  @override
  State<NearbySitesScreen> createState() => _NearbySitesScreenState();
}

class _NearbySitesScreenState extends State<NearbySitesScreen> {
  final LocationService _locationService = LocationService.instance;
  
  // Constants for bounds-based loading (copied from EditSiteScreen)
  static const double _boundsThreshold = 0.001;
  static const int _debounceDurationMs = 750; // Increased debounce to reduce API calls
  
  // Unified state variables using new UnifiedSite model
  List<UnifiedSite> _allUnifiedSites = [];
  List<ParaglidingSite> _displayedSites = [];  // Keep as ParaglidingSite for widget compatibility
  Map<String, bool> _siteFlightStatus = {}; // Key: "lat,lng", Value: hasFlights
  Position? _userPosition;
  bool _isLoading = false;
  bool _isLocationLoading = false;
  String? _errorMessage;
  LatLng? _mapCenterPosition;
  double _mapZoom = 10.0; // Dynamic zoom level for map
  LatLngBounds? _boundsToFit; // Exact bounds for map fitting after site jump
  
  // Map provider state
  MapProvider _selectedMapProvider = MapProvider.openStreetMap;
  
  // Key to force map widget refresh when airspace settings change
  Key _mapWidgetKey = UniqueKey();
  static const String _mapProviderKey = 'nearby_sites_map_provider';
  
  // Legend state
  bool _isLegendExpanded = false;
  static const String _legendExpandedKey = 'nearby_sites_legend_expanded';
  
  // Bounds-based loading state (copied from EditSiteScreen)
  Timer? _debounceTimer;
  LatLngBounds? _currentBounds;
  bool _isLoadingSites = false;
  String? _lastLoadedBoundsKey;
  
  // Search management - consolidated into SearchManager

  // Location notification state
  bool _showLocationNotification = false;
  Timer? _locationNotificationTimer;
  late final NearbySitesSearchManager _searchManager;

  // Filter state for sites and airspace
  bool _sitesEnabled = true; // Controls site loading and display
  bool _airspaceEnabled = true; // Controls airspace loading and display
  double _maxAltitudeFt = 10000.0; // Default altitude filter
  int _filterUpdateCounter = 0; // Increments when any filter changes to trigger map refresh
  Map<IcaoClass, bool> _excludedIcaoClasses = {}; // Current ICAO class filter state
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
      _allUnifiedSites = [];
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

    // Convert UnifiedSites to ParaglidingSites for backward compatibility
    final paraglidingSites = _allUnifiedSites.map((s) => s.toParaglidingSite()).toList();

    // Use SearchManager's computed property for cleaner logic
    List<ParaglidingSite> filteredSites = _searchManager.getDisplayedSites(paraglidingSites);
    
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

    LoggingService.info('Starting site load for bounds using SiteBoundsLoader: $boundsKey');

    try {
      // Use the new unified SiteBoundsLoader
      final result = await SiteBoundsLoader.instance.loadSitesForBounds(
        bounds,
        apiLimit: 50,
        includeFlightCounts: true,
      );

      if (mounted) {
        setState(() {
          // Store unified sites
          _allUnifiedSites = result.sites;

          // Build flight status map for backward compatibility
          _siteFlightStatus = {};
          for (final site in result.sites) {
            final siteKey = SiteUtils.createSiteKey(site.latitude, site.longitude);
            _siteFlightStatus[siteKey] = site.hasFlights;
          }

          _isLoadingSites = false;

          // Clear pinned site only if not from auto-jump or search is no longer active
          if (!_searchManager.state.pinnedSiteIsFromAutoJump || _searchManager.state.query.isEmpty) {
            // Note: SearchManager handles pinned site clearing internally
            // No need to manually clear here anymore
          }

          // Update displayed sites with the new bounds data
          _updateDisplayedSites();
        });

        // Mark these bounds as loaded to prevent duplicate requests
        _lastLoadedBoundsKey = boundsKey;

        LoggingService.structured('BOUNDS_SITES_LOADED', {
          'total_sites': result.sites.length,
          'flown_sites': result.flownSites.length,
          'new_sites': result.newSites.length,
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
      builder: (context) => _SiteDetailsDialog(
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
          _allUnifiedSites.clear();
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

class _SiteDetailsDialog extends StatefulWidget {
  final Site? site;
  final ParaglidingSite? paraglidingSite;
  final Position? userPosition;

  const _SiteDetailsDialog({
    this.site,
    this.paraglidingSite,
    this.userPosition,
  });

  @override
  State<_SiteDetailsDialog> createState() => _SiteDetailsDialogState();
}

class _SiteDetailsDialogState extends State<_SiteDetailsDialog> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _detailedData;
  bool _isLoadingDetails = false;
  String? _loadingError;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    // Create tab controller for both local and API sites - both can have detailed data
    _tabController = TabController(length: 5, vsync: this); // 5 tabs: Takeoff, Rules, Access, Weather, Comments
    _loadSiteDetails();
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
    final List<String> windDirections = widget.paraglidingSite?.windDirections ?? 
        (_detailedData?['wind_directions'] as List<dynamic>?)?.cast<String>() ?? [];
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
                          Tab(icon: Tooltip(message: 'Takeoff', child: Icon(Icons.flight_takeoff, size: 18))),
                          Tab(icon: Tooltip(message: 'Rules', child: Icon(Icons.policy, size: 18))),
                          Tab(icon: Tooltip(message: 'Access', child: Icon(Icons.location_on, size: 18))),
                          Tab(icon: Tooltip(message: 'Weather', child: Icon(Icons.cloud, size: 18))),
                          Tab(icon: Tooltip(message: 'Comments', child: Icon(Icons.comment, size: 18))),
                        ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildTakeoffTab(),
                            _buildRulesTab(),
                            _buildAccessTab(),
                            _buildWeatherTab(),
                            _buildCommentsTab(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildActionButtons(name, latitude, longitude),
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
            // Row 1: Location + Distance + Rating (moved to header)
            Row(
              children: [
                // Location info
                if (region != null || country != null) ...[
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      [region, country].where((s) => s != null && s.isNotEmpty).join(', '),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                // Distance
                if (distanceText != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.straighten, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '$distanceText away',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            
            // Row 2: Site Type + Altitude + Wind
            Row(
              children: [
                // Site type with characteristics tooltip
                if (siteType != null) ...[
                  Icon(
                    _getSiteTypeIcon(siteType), 
                    size: 16, 
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: _buildSiteCharacteristicsTooltip(),
                    child: Text(
                      _formatSiteType(siteType),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  ),
                  // Takeoff altitude from API data (if available)
                  if (_detailedData?['takeoff_altitude'] != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.height, size: 14, color: Colors.grey),
                    const SizedBox(width: 2),
                    Text(
                      '${_detailedData!['takeoff_altitude']}m',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
                // Altitude (existing site data)
                if (altitude != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.terrain, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${altitude}m',
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
              ],
            ),
            
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
            // Takeoff instructions
            if (_detailedData!['takeoff_description'] != null && _detailedData!['takeoff_description']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['takeoff_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            
            // Landing information
            if (_detailedData!['landing_description'] != null && _detailedData!['landing_description']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['landing_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            
            // Parking information
            if (_detailedData!['takeoff_parking_description'] != null && _detailedData!['takeoff_parking_description']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['takeoff_parking_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            
            // Altitude information
            if (widget.paraglidingSite?.altitude != null) ...[
              Text(
                '${widget.paraglidingSite!.altitude}m above sea level',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
          ] else
            const Center(child: Text('No takeoff information available')),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildRulesTab() {
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
            else if (_detailedData != null && _detailedData!['flight_rules'] != null && _detailedData!['flight_rules']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['flight_rules']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else
              const Center(child: Text('No flight rules available')),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildAccessTab() {
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
            else if (_detailedData != null && _detailedData!['going_there'] != null && _detailedData!['going_there']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['going_there']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else
              const Center(child: Text('No access information available')),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildWeatherTab() {
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
            else if (_detailedData != null && _detailedData!['weather'] != null && _detailedData!['weather']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['weather']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else
              const Center(child: Text('No weather information available')),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildCommentsTab() {
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
            // Pilot comments
            if (_detailedData!['comments'] != null && _detailedData!['comments']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['comments']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else
              const Center(child: Text('No pilot comments available')),
            ] else
              const Center(child: Text('No pilot comments available')),
          ],
        ),
      ),
      ),
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

  Widget _buildActionButtons(String name, double latitude, double longitude) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _launchNavigation(latitude, longitude);
            },
            icon: const Icon(Icons.navigation),
            label: const Text('Navigate'),
          ),
        ),
        // View on PGE button for API sites
        if (widget.paraglidingSite != null && _detailedData != null && _detailedData!['pgeid'] != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                final pgeUrl = 'https://www.paraglidingearth.com/pgearth/index.php?site=${_detailedData!['pgeid']}';
                _launchUrl(pgeUrl);
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('View Full Details on ParaglidingEarth'),
            ),
          ),
        ],
      ],
    );
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
      
      const SizedBox(height: 20),
      
      // Action buttons
      _buildActionButtons(name, latitude, longitude),
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