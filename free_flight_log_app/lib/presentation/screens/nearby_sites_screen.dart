import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../services/database_service.dart';
import '../../services/location_service.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';
import '../../utils/map_provider.dart';
import '../../utils/site_utils.dart';
import '../widgets/nearby_sites_map_widget.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/app_empty_state.dart';


class NearbySitesScreen extends StatefulWidget {
  const NearbySitesScreen({super.key});

  @override
  State<NearbySitesScreen> createState() => _NearbySitesScreenState();
}

class _NearbySitesScreenState extends State<NearbySitesScreen> {
  final DatabaseService _databaseService = DatabaseService.instance;
  final LocationService _locationService = LocationService.instance;
  final ParaglidingEarthApi _paraglidingEarthApi = ParaglidingEarthApi.instance;
  final TextEditingController _searchController = TextEditingController();
  
  // Constants for bounds-based loading (copied from EditSiteScreen)
  static const double _boundsThreshold = 0.001;
  static const int _debounceDurationMs = 500;
  
  // Unified state variables - all sites are ParaglidingSite objects from API
  List<ParaglidingSite> _allSites = [];
  List<ParaglidingSite> _displayedSites = [];
  Map<String, bool> _siteFlightStatus = {}; // Key: "lat,lng", Value: hasFlights
  Position? _userPosition;
  bool _isLoading = false;
  bool _isLocationLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  LatLng? _mapCenterPosition;
  
  // Map provider state
  MapProvider _selectedMapProvider = MapProvider.openStreetMap;
  static const String _mapProviderKey = 'nearby_sites_map_provider';
  
  // Legend state
  bool _isLegendExpanded = false;
  static const String _legendExpandedKey = 'nearby_sites_legend_expanded';
  
  // Bounds-based loading state (copied from EditSiteScreen)
  Timer? _debounceTimer;
  LatLngBounds? _currentBounds;
  bool _isLoadingSites = false;
  String? _lastLoadedBoundsKey;
  
  // Search state management
  bool _isSearchMode = false;
  List<ParaglidingSite> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;
  static const Duration _searchDebounceDelay = Duration(milliseconds: 300);
  
  // Smooth transition state management
  bool _pendingBoundsLoad = false;
  ParaglidingSite? _pinnedSite;
  

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadPreferences();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounceTimer?.cancel(); // Clean up timer
    _searchDebounce?.cancel(); // Clean up search debounce timer
    super.dispose();
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

  Future<void> _updateUserLocation() async {
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
        }
        _updateDisplayedSites();
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to get user location', e, stackTrace);
      if (mounted) {
        setState(() {
          _isLocationLoading = false;
        });
      }
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


  void _onSearchChanged() {
    final newQuery = _searchController.text.toLowerCase().trim();
    if (newQuery != _searchQuery) {
      setState(() {
        _searchQuery = newQuery;
        _updateDisplayedSites();
      });
    }
  }

  void _updateDisplayedSites() {
    final stopwatch = Stopwatch()..start();
    
    List<ParaglidingSite> filteredSites;
    
    // Use search results if we have them and are in search mode
    if (_searchQuery.isNotEmpty && _searchResults.isNotEmpty) {
      filteredSites = _searchResults;
      
      // Don't auto-center map during search to prevent jumping
      // Map will only center when user explicitly selects a result
    } else if (_searchQuery.isEmpty) {
      // No search - show bounds-based sites
      filteredSites = _allSites.toList(); // Create a copy to allow modifications
      
      // Add pinned site if we have one and it's not already in the list
      if (_pinnedSite != null) {
        final pinnedSiteKey = SiteUtils.createSiteKey(_pinnedSite!.latitude, _pinnedSite!.longitude);
        final alreadyExists = filteredSites.any((site) => 
          SiteUtils.createSiteKey(site.latitude, site.longitude) == pinnedSiteKey);
        
        if (!alreadyExists) {
          filteredSites.insert(0, _pinnedSite!); // Add at beginning for prominence
        }
      }
      
      // Don't reset map center automatically when clearing search
      // Let the user maintain their current view
    } else {
      // Search in progress or no results - keep current sites if we're pending a bounds load
      if (_pendingBoundsLoad && _displayedSites.isNotEmpty) {
        filteredSites = _displayedSites; // Keep showing current sites
      } else {
        filteredSites = [];
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
      'search_query': _searchQuery.isEmpty ? null : _searchQuery,
      'has_user_position': _userPosition != null,
      'filter_time_ms': stopwatch.elapsedMilliseconds,
    });
  }


  void _onRefreshLocation() async {
    LoggingService.action('NearbySites', 'refresh_location', {});
    _locationService.clearCache();
    await _updateUserLocation();
    
    // Refresh sites via bounds-based loading when position updates
    _updateDisplayedSites();
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

  void _selectMapProvider(MapProvider provider) async {
    setState(() {
      _selectedMapProvider = provider;
    });
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_mapProviderKey, provider.index);
    } catch (e) {
      LoggingService.error('Failed to save map provider preference', e);
    }
    
    LoggingService.action('NearbySites', 'map_provider_changed', {
      'provider': provider.shortName,
    });
  }

  // Search methods
  void _enterSearchMode() {
    setState(() {
      _isSearchMode = true;
    });
  }
  
  void _exitSearchMode({bool preserveDisplayedSites = false}) {
    _searchController.clear();
    _searchDebounce?.cancel();
    setState(() {
      _isSearchMode = false;
      _searchResults.clear();
      _isSearching = false;
      
      // Don't automatically update displayed sites if we want to preserve them
      // This prevents the jarring site disappearance during transitions
      if (!preserveDisplayedSites) {
        _updateDisplayedSites();
      }
    });
  }
  
  void _onSearchTextChanged(String query) {
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults.clear();
        _isSearching = false;
      });
      return;
    }
    
    if (query.length < 2) return;
    
    setState(() {
      _isSearching = true;
    });
    
    _searchDebounce = Timer(_searchDebounceDelay, () {
      _performSearch(query);
    });
  }
  
  Future<void> _performSearch(String query) async {
    try {
      final results = await _paraglidingEarthApi.searchSitesByName(query);
      if (mounted) {
        setState(() {
          _searchResults = results.take(15).toList(); // Limit to 15 results for better selection
          _isSearching = false;
        });
        
        LoggingService.action('NearbySites', 'search_performed', {
          'query': query,
          'results_count': results.length,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchResults.clear();
          _isSearching = false;
        });
      }
      LoggingService.error('Search failed', e);
    }
  }
  
  void _selectSearchResult(ParaglidingSite site) {
    // Pin the selected site to keep it visible during transition
    _pinnedSite = site;
    
    // Center map on selected site
    _mapCenterPosition = LatLng(site.latitude, site.longitude);
    
    // Mark that we're starting a bounds load for smooth transition
    setState(() {
      _pendingBoundsLoad = true;
    });
    
    // Exit search mode but preserve displayed sites for smooth transition
    _exitSearchMode(preserveDisplayedSites: true);
    
    // Immediately trigger bounds-based loading without delay for responsiveness
    final newCenter = LatLng(site.latitude, site.longitude);
    final bounds = LatLngBounds(
      LatLng(newCenter.latitude - 0.05, newCenter.longitude - 0.05),
      LatLng(newCenter.latitude + 0.05, newCenter.longitude + 0.05),
    );
    
    // Use a very short delay just to allow the map to update its center
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _onBoundsChanged(bounds);
      }
    });
    
    LoggingService.action('NearbySites', 'search_result_selected', {
      'site_name': site.name,
      'country': site.country,
    });
  }

  /// Perform API search using Paragliding Earth search endpoint
  Future<void> _performAPISearch(String query) async {
    if (query.length < 2) return; // Don't search for very short queries
    
    // Cancel any existing search
    _searchDebounce?.cancel();
    
    setState(() {
      _isSearching = true;
    });
    
    // Debounce the search to avoid too many API calls
    _searchDebounce = Timer(_searchDebounceDelay, () async {
      try {
        final results = await _paraglidingEarthApi.searchSitesByName(query);
        
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
            _updateDisplayedSites();
          });
          
          LoggingService.action('NearbySites', 'api_search_performed', {
            'query': query,
            'results_count': results.length,
          });
        }
      } catch (e) {
        LoggingService.error('API search failed', e);
        
        if (mounted) {
          setState(() {
            _searchResults.clear();
            _isSearching = false;
            _updateDisplayedSites();
          });
        }
      }
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
    if (_isLoadingSites) return;
    
    // Create a unique key for these bounds to prevent duplicate requests
    final boundsKey = '${bounds.north.toStringAsFixed(6)}_${bounds.south.toStringAsFixed(6)}_${bounds.east.toStringAsFixed(6)}_${bounds.west.toStringAsFixed(6)}';
    if (_lastLoadedBoundsKey == boundsKey) {
      return; // Same bounds already loaded
    }
    
    setState(() {
      _isLoadingSites = true;
    });
    
    try {
      // 1. Load local sites from DB to check flight status
      final localSites = await _databaseService.getSitesInBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      );
      
      // 2. Load API sites within bounds
      final apiSites = await _paraglidingEarthApi.getSitesInBounds(
        bounds.north,
        bounds.south,
        bounds.east,
        bounds.west,
        limit: 50,
        detailed: false,
      );
      
      // 3. For each local site, try to find its corresponding API data
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
      
      if (mounted) {
        setState(() {
          _allSites = unifiedSites;
          _siteFlightStatus = siteFlightStatus;
          _isLoadingSites = false;
          
          // Clear pending bounds load state and pinned site now that new data is loaded
          _pendingBoundsLoad = false;
          _pinnedSite = null;
          
          // Update displayed sites with the new bounds data
          _updateDisplayedSites();
        });
        
        // Mark these bounds as loaded to prevent duplicate requests
        _lastLoadedBoundsKey = boundsKey;
        
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
          // Clear pending state even on error to prevent UI from getting stuck
          _pendingBoundsLoad = false;
          _pinnedSite = null;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearchMode 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search sites worldwide...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: _onSearchTextChanged,
            )
          : const Text('Nearby Sites'),
        actions: [
          _isSearchMode 
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSearchMode,
              )
            : IconButton(
                icon: const Icon(Icons.search),
                onPressed: _enterSearchMode,
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
                : (_allSites.isEmpty && _lastLoadedBoundsKey != null)
                    ? const AppEmptyState(
                        title: 'No sites found',
                        message: 'No sites found in this area',
                        icon: Icons.location_on,
                      )
                    : Stack(
                      children: [
                        // Map
                        NearbySitesMapWidget(
                          sites: _displayedSites,
                          siteFlightStatus: _siteFlightStatus,
                          userPosition: _userPosition,
                          centerPosition: _mapCenterPosition,
                          initialZoom: _searchQuery.isNotEmpty ? 12.0 : 10.0,
                          mapProvider: _selectedMapProvider,
                          isLegendExpanded: _isLegendExpanded,
                          onToggleLegend: _toggleLegend,
                          onMapProviderChanged: _selectMapProvider,
                          onSiteSelected: _onSiteSelected,
                          onBoundsChanged: _onBoundsChanged,
                          searchQuery: _searchQuery,
                          onSearchChanged: (query) {
                            final trimmedQuery = query.trim();
                            setState(() {
                              _searchQuery = trimmedQuery;
                            });
                            
                            // Trigger API search if query is not empty
                            if (trimmedQuery.isNotEmpty && trimmedQuery.length >= 2) {
                              _performAPISearch(trimmedQuery);
                            } else {
                              // Clear search results and show normal bounds-based sites
                              setState(() {
                                _searchResults.clear();
                                _isSearching = false;
                                _updateDisplayedSites();
                              });
                            }
                          },
                          onRefreshLocation: _onRefreshLocation,
                          isLocationLoading: _isLocationLoading,
                          searchResults: _searchResults,
                          isSearching: _isSearching,
                          onSearchResultSelected: (site) {
                            _selectSearchResult(site);
                          },
                        ),
                        
                        // Loading overlay for dynamic site loading
                        if (_isLoadingSites)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Loading nearby sites...',
                                    style: TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
          
          // Search dropdown overlay
          if (_isSearchMode && (_searchResults.isNotEmpty || _isSearching))
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
                  child: _isSearching
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
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final site = _searchResults[index];
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
                            onTap: () => _selectSearchResult(site),
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