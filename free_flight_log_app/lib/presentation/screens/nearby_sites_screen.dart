import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../services/database_service.dart';
import '../../services/location_service.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';
import '../widgets/nearby_sites_map_widget.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/app_empty_state.dart';

enum MapProvider {
  openStreetMap('Street Map', 'OSM', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', 18, '© OpenStreetMap contributors'),
  googleSatellite('Google Satellite', 'Google', 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}', 18, '© Google'),
  esriWorldImagery('Esri Satellite', 'Esri', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', 18, '© Esri');

  const MapProvider(this.displayName, this.shortName, this.urlTemplate, this.maxZoom, this.attribution);
  
  final String displayName;
  final String shortName;
  final String urlTemplate;
  final int maxZoom;
  final String attribution;
}

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
  
  // State variables
  List<Site> _localSites = [];
  List<ParaglidingSite> _apiSites = [];
  List<Site> _displayedSites = [];
  List<ParaglidingSite> _displayedApiSites = [];
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
      
      // Load local sites from database
      final localSites = await _databaseService.getSitesWithFlightCounts();
      
      // Get user location
      await _updateUserLocation();
      
      // API sites will be loaded dynamically via bounds-based loading
      
      stopwatch.stop();
      
      if (mounted) {
        setState(() {
          _localSites = localSites;
          _apiSites = []; // Will be loaded via bounds-based loading
          _updateDisplayedSites();
          _isLoading = false;
        });
        
        LoggingService.performance(
          'Load Nearby Sites Data',
          Duration(milliseconds: stopwatch.elapsedMilliseconds),
          '${localSites.length} local sites loaded (API sites via bounds-based loading)',
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
    
    List<Site> filteredLocalSites = _localSites;
    List<ParaglidingSite> filteredApiSites = _apiSites;
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filteredLocalSites = filteredLocalSites.where((site) =>
        site.name.toLowerCase().contains(_searchQuery) ||
        (site.country?.toLowerCase().contains(_searchQuery) ?? false)
      ).toList();
      
      filteredApiSites = filteredApiSites.where((site) =>
        site.name.toLowerCase().contains(_searchQuery) ||
        (site.country?.toLowerCase().contains(_searchQuery) ?? false)
      ).toList();
      
      // If search found specific sites, center map on them
      final totalResults = filteredLocalSites.length + filteredApiSites.length;
      if (totalResults == 1) {
        if (filteredLocalSites.isNotEmpty) {
          final site = filteredLocalSites.first;
          _mapCenterPosition = LatLng(site.latitude, site.longitude);
        } else {
          final site = filteredApiSites.first;
          _mapCenterPosition = LatLng(site.latitude, site.longitude);
        }
      } else if (totalResults > 1 && totalResults < 20) {
        // Center on average position of found sites
        final allLats = [
          ...filteredLocalSites.map((s) => s.latitude),
          ...filteredApiSites.map((s) => s.latitude)
        ];
        final allLngs = [
          ...filteredLocalSites.map((s) => s.longitude),
          ...filteredApiSites.map((s) => s.longitude)
        ];
        
        if (allLats.isNotEmpty) {
          double avgLat = allLats.reduce((a, b) => a + b) / allLats.length;
          double avgLng = allLngs.reduce((a, b) => a + b) / allLngs.length;
          _mapCenterPosition = LatLng(avgLat, avgLng);
        }
      }
    } else {
      // Reset map center to user position when clearing search
      if (_userPosition != null) {
        _mapCenterPosition = LatLng(_userPosition!.latitude, _userPosition!.longitude);
      }
    }
    
    // Sites are loaded via bounds-based filtering, no distance filtering needed
    
    stopwatch.stop();
    
    setState(() {
      _displayedSites = filteredLocalSites;
      _displayedApiSites = filteredApiSites;
    });
    
    LoggingService.structured('NEARBY_SITES_FILTERED', {
      'total_local_sites': _localSites.length,
      'total_api_sites': _apiSites.length,
      'displayed_local_sites': _displayedSites.length,
      'displayed_api_sites': _displayedApiSites.length,
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

  void _onSiteSelected(Site site) {
    LoggingService.action('NearbySites', 'site_selected', {
      'site_id': site.id,
      'site_name': site.name,
      'flight_count': site.flightCount ?? 0,
    });
    _showSiteDetailsDialog(site: site);
  }

  void _onApiSiteSelected(ParaglidingSite site) {
    LoggingService.action('NearbySites', 'api_site_selected', {
      'site_id': site.id,
      'site_name': site.name,
      'site_type': site.siteType,
      'rating': site.rating,
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
      // Load local sites
      final localSitesFuture = _databaseService.getSitesInBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      );
      
      // Load API sites with basic data only for map display
      final apiSitesFuture = _paraglidingEarthApi.getSitesInBounds(
        bounds.north,
        bounds.south,
        bounds.east,
        bounds.west,
        limit: 50,
        detailed: false,
      );
      
      // Wait for both to complete
      final results = await Future.wait([
        localSitesFuture,
        apiSitesFuture,
      ]);
      
      if (mounted) {
        setState(() {
          _localSites = results[0] as List<Site>;
          _apiSites = results[1] as List<ParaglidingSite>;
          
          // Filter displayed sites based on search query
          _updateDisplayedSites();
          
          _isLoadingSites = false;
        });
        
        // Mark these bounds as loaded to prevent duplicate requests
        _lastLoadedBoundsKey = boundsKey;
        
        LoggingService.structured('BOUNDS_SITES_LOADED', {
          'local_sites_count': _localSites.length,
          'api_sites_count': _apiSites.length,
          'bounds_key': boundsKey,
        });
      }
    } catch (e) {
      LoggingService.error('NearbySitesScreen: Error loading sites for bounds', e);
      if (mounted) {
        setState(() {
          _isLoadingSites = false;
        });
      }
    }
  }


  void _showSiteDetailsDialog({Site? site, ParaglidingSite? paraglidingSite}) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (context) => _SiteDetailsDialog(
        site: site,
        paraglidingSite: paraglidingSite,
        userPosition: _userPosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Sites'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? AppErrorState(
                  message: _errorMessage!,
                  onRetry: _loadData,
                )
              : (_localSites.isEmpty && _apiSites.isEmpty)
                  ? const AppEmptyState(
                      title: 'No sites found',
                      message: 'Import flights to add sites to your collection',
                      icon: Icons.location_on,
                    )
                  : Stack(
                      children: [
                        // Map
                        NearbySitesMapWidget(
                          localSites: _displayedSites,
                          apiSites: _displayedApiSites,
                          userPosition: _userPosition,
                          centerPosition: _mapCenterPosition,
                          initialZoom: _searchQuery.isNotEmpty ? 12.0 : 10.0,
                          mapProvider: _selectedMapProvider,
                          isLegendExpanded: _isLegendExpanded,
                          onToggleLegend: _toggleLegend,
                          onMapProviderChanged: _selectMapProvider,
                          onSiteSelected: _onSiteSelected,
                          onApiSiteSelected: _onApiSiteSelected,
                          onBoundsChanged: _onBoundsChanged,
                        ),
                        
                        // Search overlay
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 80,
                          child: Card(
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Search sites by name or country...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        onPressed: () {
                                          _searchController.clear();
                                        },
                                        icon: const Icon(Icons.clear),
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        
                        // Location button
                        Positioned(
                          top: 16,
                          right: 16,
                          child: FloatingActionButton.small(
                            heroTag: "location",
                            onPressed: _isLocationLoading ? null : _onRefreshLocation,
                            child: _isLocationLoading 
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.my_location),
                          ),
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

class _SiteDetailsDialogState extends State<_SiteDetailsDialog> {
  Map<String, dynamic>? _detailedData;
  bool _isLoadingDetails = false;
  String? _loadingError;

  @override
  void initState() {
    super.initState();
    _loadSiteDetails();
  }

  Future<void> _loadSiteDetails() async {
    // Only load detailed data for API sites (ParaglidingSite)
    if (widget.paraglidingSite == null) return;
    
    setState(() {
      _isLoadingDetails = true;
      _loadingError = null;
    });

    try {
      final details = await ParaglidingEarthApi.instance.getSiteDetails(
        widget.paraglidingSite!.latitude,
        widget.paraglidingSite!.longitude,
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
    final int? altitude = widget.site?.altitude?.toInt() ?? widget.paraglidingSite?.altitude;
    final String? country = widget.site?.country ?? widget.paraglidingSite?.country;
    final String? region = widget.paraglidingSite?.region; // Only API sites have region
    final String? description = widget.paraglidingSite?.description; // Only API sites have description
    final int? rating = widget.paraglidingSite?.rating;
    final List<String> windDirections = widget.paraglidingSite?.windDirections ?? [];
    final String? siteType = widget.paraglidingSite?.siteType;
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
        constraints: const BoxConstraints(maxWidth: 400),
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
            // Header with name and close button
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Rating (for API sites)
            if (rating != null && rating > 0) ...[
              Row(
                children: [
                  ...List.generate(5, (index) => Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 20,
                  )),
                  const SizedBox(width: 8),
                  Text('($rating.0)', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
              const SizedBox(height: 12),
            ],
            
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
            
            // Loading state for detailed data
            if (_isLoadingDetails) ...[
              const SizedBox(height: 16),
              const Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Loading detailed information...',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
            
            // Error state
            if (_loadingError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loadingError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Site characteristics (for API sites with detailed data)
            if (_detailedData != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (_detailedData!['thermals']?.toString() == '1') 
                    Chip(
                      label: Text('Thermals', style: TextStyle(fontSize: 12)),
                      backgroundColor: Colors.orange.withValues(alpha: 0.2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (_detailedData!['soaring']?.toString() == '1')
                    Chip(
                      label: Text('Soaring', style: TextStyle(fontSize: 12)),
                      backgroundColor: Colors.blue.withValues(alpha: 0.2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (_detailedData!['xc']?.toString() == '1')
                    Chip(
                      label: Text('XC', style: TextStyle(fontSize: 12)),
                      backgroundColor: Colors.green.withValues(alpha: 0.2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (_detailedData!['winch']?.toString() == '1')
                    Chip(
                      label: Text('Winch', style: TextStyle(fontSize: 12)),
                      backgroundColor: Colors.purple.withValues(alpha: 0.2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (_detailedData!['flatland']?.toString() == '1')
                    Chip(
                      label: Text('Flatland', style: TextStyle(fontSize: 12)),
                      backgroundColor: Colors.amber.withValues(alpha: 0.2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            
            // Detailed information sections (loaded on demand)
            if (_detailedData != null) ...[
              // Takeoff instructions
              if (_detailedData!['takeoff_description'] != null && _detailedData!['takeoff_description']!.toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Takeoff Instructions',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  child: SingleChildScrollView(
                    child: Text(
                      _detailedData!['takeoff_description']!.toString(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
              
              // Flight rules
              if (_detailedData!['flight_rules'] != null && _detailedData!['flight_rules']!.toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Flight Rules',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 80),
                  child: SingleChildScrollView(
                    child: Text(
                      _detailedData!['flight_rules']!.toString(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
              
              // Access information
              if (_detailedData!['going_there'] != null && _detailedData!['going_there']!.toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Getting There',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 80),
                  child: SingleChildScrollView(
                    child: Text(
                      _detailedData!['going_there']!.toString(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
              
              // Pilot comments
              if (_detailedData!['comments'] != null && _detailedData!['comments']!.toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Pilot Comments',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(
                      _detailedData!['comments']!.toString(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
              
              // Weather notes
              if (_detailedData!['weather'] != null && _detailedData!['weather']!.toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Weather Information',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 80),
                  child: SingleChildScrollView(
                    child: Text(
                      _detailedData!['weather']!.toString(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
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
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            
            // Action buttons
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // Open in maps app
                          Navigator.of(context).pop();
                          // TODO: Implement navigation functionality
                          LoggingService.info('Navigate to site: $name');
                        },
                        icon: const Icon(Icons.navigation),
                        label: const Text('Navigate'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          // TODO: Implement add to favorites functionality
                          LoggingService.info('Add to favorites: $name');
                        },
                        icon: const Icon(Icons.favorite_border),
                        label: const Text('Favorite'),
                      ),
                    ),
                  ],
                ),
                // View on PGE button for API sites
                if (widget.paraglidingSite != null && _detailedData != null && _detailedData!['pgeid'] != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        final pgeUrl = 'https://www.paraglidingearth.com/pgearth/index.php?site=${_detailedData!['pgeid']}';
                        // TODO: Launch URL
                        LoggingService.info('Open PGE link: $pgeUrl');
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('View Full Details on ParaglidingEarth'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
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
}