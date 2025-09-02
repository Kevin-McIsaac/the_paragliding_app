import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/flight.dart';
import '../../services/database_service.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';

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

class EditSiteScreen extends StatefulWidget {
  final ({double latitude, double longitude})? initialCoordinates;

  const EditSiteScreen({
    super.key, 
    this.initialCoordinates,
  });

  @override
  State<EditSiteScreen> createState() => _EditSiteScreenState();
}

class _EditSiteScreenState extends State<EditSiteScreen> {
  MapController? _mapController;
  MapProvider _selectedMapProvider = MapProvider.openStreetMap;
  
  // Constants
  static const String _mapProviderKey = 'edit_site_map_provider';
  static const String _helpShownKey = 'edit_site_help_shown';
  static const double _defaultLatitude = 46.9480; // Swiss Alps
  static const double _defaultLongitude = 7.4474;
  static const double _initialZoom = 13.0;
  static const double _minZoom = 1.0;
  static const double _launchMarkerSize = 15.0;
  static const double _siteMarkerSize = 72.0;
  static const double _siteMarkerIconSize = 66.0;
  static const double _boundsThreshold = 0.001;
  static const int _debounceDurationMs = 500;
  static const double _launchRadiusMeters = 500.0;
  
  // Common UI shadows
  static const BoxShadow _standardElevatedShadow = BoxShadow(
    color: Colors.black26,
    blurRadius: 4,
    offset: Offset(0, 2),
  );
  static const BoxShadow _bottomNavigationShadow = BoxShadow(
    color: Colors.black12,
    blurRadius: 4,
    offset: Offset(0, -2),
  );
  
  // Site markers state
  List<Site> _localSites = [];
  List<ParaglidingSite> _apiSites = [];
  List<Flight> _launches = [];
  Timer? _debounceTimer;
  LatLngBounds? _currentBounds;
  bool _isLoadingSites = false;
  String? _lastLoadedBoundsKey;
  String? _lastLoadedLaunchesBoundsKey;
  
  // Merge mode state
  Site? _selectedSourceSite;
  bool _isMergeMode = false;
  Timer? _cacheRefreshTimer;
  
  // Drag and drop hover state
  Site? _currentlyDraggedSite;
  dynamic _hoveredTargetSite; // Can be Site or ParaglidingSite
  
  // Flight count cache for tooltips
  Map<int, int> _siteFlightCounts = {};
  
  // Services
  final DatabaseService _databaseService = DatabaseService.instance;
  final ParaglidingEarthApi _apiService = ParaglidingEarthApi.instance;

  @override
  void initState() {
    super.initState();
    _loadMapProviderPreference();
    _loadFlightCounts(); // Load flight counts for sites
    _checkAndShowHelpOnFirstVisit(); // Show help dialog on first visit
    
    // Start cache refresh timer for debug overlay (debug mode only)
    if (kDebugMode) {
      _cacheRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) setState(() {});
      });
    }
  }
  
  /// Load the saved map provider preference
  Future<void> _loadMapProviderPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check for legacy satellite view preference first
      final legacySatelliteView = prefs.getBool('edit_site_satellite_view');
      String? savedProviderName;
      
      if (legacySatelliteView == true) {
        // Migrate legacy preference: satellite view = Google Satellite
        savedProviderName = MapProvider.googleSatellite.name;
        await prefs.setString(_mapProviderKey, savedProviderName);
        await prefs.remove('edit_site_satellite_view'); // Clean up legacy key
      } else if (legacySatelliteView == false) {
        // Migrate legacy preference: street view = OpenStreetMap
        savedProviderName = MapProvider.openStreetMap.name;
        await prefs.setString(_mapProviderKey, savedProviderName);
        await prefs.remove('edit_site_satellite_view'); // Clean up legacy key
      } else {
        // Load current preference
        savedProviderName = prefs.getString(_mapProviderKey);
      }
      
      MapProvider selectedProvider = MapProvider.openStreetMap; // Default
      if (savedProviderName != null) {
        try {
          selectedProvider = MapProvider.values.firstWhere(
            (provider) => provider.name == savedProviderName,
            orElse: () => MapProvider.openStreetMap,
          );
        } catch (e) {
          LoggingService.warning('EditSiteScreen: Unknown map provider: $savedProviderName, using default');
        }
      }
      
      if (mounted) {
        setState(() {
          _selectedMapProvider = selectedProvider;
        });
        LoggingService.debug('EditSiteScreen: Loaded map provider preference: ${selectedProvider.displayName}');
      }
    } catch (e) {
      LoggingService.error('EditSiteScreen: Error loading map provider preference', e);
    }
  }

  /// Check if this is the first visit and show help dialog if needed
  Future<void> _checkAndShowHelpOnFirstVisit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final helpShown = prefs.getBool(_helpShownKey) ?? false;
      
      if (!helpShown && mounted) {
        // Show help dialog after a short delay to ensure the screen is fully loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showHelpDialog(markAsShown: true);
          }
        });
      }
    } catch (e) {
      LoggingService.error('EditSiteScreen: Error checking first visit help', e);
    }
  }

  /// Show help dialog with map usage instructions
  void _showHelpDialog({bool markAsShown = false}) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline),
            SizedBox(width: 8),
            Text('Using the Sites Map'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 12),
            _HelpItem(
              icon: Icons.edit,
              title: 'Edit Site',
              description: 'Long press on a Site to see and edit the details,  e.g, name, country, latitude, longitude and altitude.',
            ),
            SizedBox(height: 12),
            _HelpItem(
              icon: Icons.merge,
              title: 'Merge Sites',
              description: 'Either drag a Site onto another, or long press a Site then select the other, to merge into a single Site.',
            ),
            SizedBox(height: 12),
            _HelpItem(
              icon: Icons.add_location,
              title: 'Create Site',
              description: 'Long press on the map or a Launch to create a new Site at that location.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    ).then((_) async {
      if (markAsShown) {
        // Mark help as shown after dialog is dismissed
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_helpShownKey, true);
          LoggingService.debug('EditSiteScreen: Marked help dialog as shown for first-time user');
        } catch (e) {
          LoggingService.error('EditSiteScreen: Error saving help shown preference', e);
        }
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _cacheRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isMergeMode ? 'Merge: Select Target Site' : 'Site Map'),
        surfaceTintColor: _isMergeMode ? Colors.orange : null,
        actions: [
          if (_isMergeMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _exitMergeMode,
              tooltip: 'Cancel merge',
            )
          else
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: _showHelpDialog,
              tooltip: 'Show map usage instructions',
            ),
        ],
      ),
      body: _buildMapSection(),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [_bottomNavigationShadow],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildMapSection() {
    return Container(
      height: double.infinity,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildLocationMap(),
    );
  }


  void _selectMapProvider(MapProvider provider) {
    setState(() {
      _selectedMapProvider = provider;
    });
    
    // Enforce zoom limits for the new provider
    _enforceZoomLimits();
    
    _saveMapProviderPreference();
  }

  /// Get the appropriate icon for a map provider
  IconData _getProviderIcon(MapProvider provider) {
    switch (provider) {
      case MapProvider.openStreetMap:
        return Icons.map;
      case MapProvider.googleSatellite:
        return Icons.satellite;
      case MapProvider.esriWorldImagery:
        return Icons.terrain;
    }
  }

  /// Create a launch marker with consistent styling
  Marker _buildLaunchMarker(Flight launch) {
    final markerColor = Colors.blue;
    
    // Build site name for launch marker - used in tooltip/debugging
    
    return Marker(
      point: LatLng(launch.launchLatitude!, launch.launchLongitude!),
      width: _launchMarkerSize,
      height: _launchMarkerSize,
      child: GestureDetector(
        onLongPress: () => _handleSiteCreationAtPoint(
          LatLng(launch.launchLatitude!, launch.launchLongitude!),
          siteName: 'Launch ${launch.date.toLocal().toString().split(' ')[0]}',
          altitude: launch.launchAltitude,
        ),
        child: Container(
          width: _launchMarkerSize,
          height: _launchMarkerSize,
          decoration: BoxDecoration(
            color: markerColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }


  /// Build the tile layer for the selected map provider
  TileLayer _buildTileLayer() {
    return TileLayer(
      urlTemplate: _selectedMapProvider.urlTemplate,
      userAgentPackageName: 'com.freeflightlog.free_flight_log_app',
      maxNativeZoom: _selectedMapProvider.maxZoom,
      maxZoom: _selectedMapProvider.maxZoom.toDouble(),
      tileProvider: kDebugMode 
        ? _DebugNetworkTileProvider(
            headers: {
              'User-Agent': 'FreeFlightLog/1.0',
              'Cache-Control': 'max-age=31536000', // 12 months cache
            },
          )
        : NetworkTileProvider(
            headers: {
              'User-Agent': 'FreeFlightLog/1.0',
              'Cache-Control': 'max-age=31536000', // 12 months cache
            },
          ),
      // Add debug logging in debug mode only
      errorTileCallback: kDebugMode ? (tile, error, stackTrace) {
        LoggingService.debug('Tile error: ${tile.coordinates} - $error');
      } : null,
    );
  }

  /// Build the launch markers layer
  MarkerLayer _buildLaunchesLayer() {
    return MarkerLayer(
      markers: _launches
          .where((launch) => launch.launchLatitude != null && launch.launchLongitude != null)
          .map(_buildLaunchMarker)
          .toList(),
    );
  }




  /// Build the map controls (legend and provider selector)
  Widget _buildMapControls() {
    return Column(
      children: [
        // Map provider selector
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [_standardElevatedShadow],
          ),
          child: PopupMenuButton<MapProvider>(
            onSelected: _selectMapProvider,
            initialValue: _selectedMapProvider,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getProviderIcon(_selectedMapProvider),
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  Icon(
                    Icons.arrow_drop_down, 
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ],
              ),
            ),
            itemBuilder: (context) => MapProvider.values.map((provider) => 
              PopupMenuItem<MapProvider>(
                value: provider,
                child: Row(
                  children: [
                    Icon(
                      _getProviderIcon(provider),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(provider.displayName),
                    ),
                  ],
                ),
              )
            ).toList(),
          ),
        ),
      ],
    );
  }

  /// Build the attribution widget
  Widget _buildAttribution() {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(2),
        ),
        child: GestureDetector(
          onTap: () async {
            // Open appropriate copyright page based on provider
            String url;
            switch (_selectedMapProvider) {
              case MapProvider.openStreetMap:
                url = 'https://www.openstreetmap.org/copyright';
                break;
              case MapProvider.googleSatellite:
                url = 'https://www.google.com/permissions/geoguidelines/';
                break;
              case MapProvider.esriWorldImagery:
                url = 'https://www.esri.com/en-us/legal/terms/full-master-agreement';
                break;
            }
            final uri = Uri.parse(url);
            try {
              await launchUrl(uri, mode: LaunchMode.platformDefault);
            } catch (e) {
              LoggingService.error('EditSiteScreen: Could not launch URL', e);
            }
          },
          child: Text(
            _selectedMapProvider.attribution,
            style: TextStyle(
              fontSize: 10,
              color: Colors.blue[800],
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }

  /// Build the legend widget
  Widget _buildLegend() {
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [_standardElevatedShadow],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_launches.isNotEmpty) ...[
              _buildLegendItem(null, Colors.blue, 'Launches', isCircle: true),
              const SizedBox(height: 4),
            ],
            _buildLegendItem(Icons.location_on, Colors.blue, 'Flown Sites'),
            const SizedBox(height: 4),
            _buildLegendItem(Icons.location_on, Colors.green, 'New Sites'),
          ],
        ),
      ),
    );
  }

  /// Build a single legend item
  Widget _buildLegendItem(IconData? icon, Color color, String label, {bool isCircle = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCircle)
          Container(
            width: _launchMarkerSize,
            height: _launchMarkerSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          )
        else
          Icon(icon!, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  /// Build the loading indicator
  Widget? _buildLoadingIndicator() {
    if (!_isLoadingSites) return null;
    
    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Loading sites...',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Enforce zoom limits for the current map provider
  void _enforceZoomLimits() {
    if (_mapController == null) return;
    
    final currentZoom = _mapController!.camera.zoom;
    final maxZoom = _selectedMapProvider.maxZoom.toDouble();
    
    if (currentZoom > maxZoom) {
      _mapController!.move(_mapController!.camera.center, maxZoom);
    }
  }
  
  /// Save the map provider preference
  Future<void> _saveMapProviderPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_mapProviderKey, _selectedMapProvider.name);
    } catch (e) {
      LoggingService.error('EditSiteScreen: Error saving map provider preference', e);
    }
  }
  
  void _onMapReady() {
    // Initial load of sites and launches
    if (_mapController != null) {
      final bounds = _mapController!.camera.visibleBounds;
      _currentBounds = bounds;
      _loadSitesForBounds(bounds);
      _loadAllLaunchesInBounds(bounds);
    }
  }
  
  void _onMapEvent(MapEvent event) {
    // Enforce zoom limits
    _enforceZoomLimits();
    
    // React to all movement and zoom end events to reload sites
    if (event is MapEventMoveEnd || 
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd ||
        event is MapEventScrollWheelZoom) {
      
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: _debounceDurationMs), () {
        _updateMapBounds();
      });
    }
  }
  
  void _onMapTap(TapPosition tapPosition, LatLng point) {
    _handleSiteCreationAtPoint(
      point,
      siteName: 'Map ${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
    );
  }

  void _updateMapBounds() {
    if (_mapController == null) return;
    
    final bounds = _mapController!.camera.visibleBounds;
    
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
    _loadAllLaunchesInBounds(bounds);
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
      
      // Load API sites
      final apiSitesFuture = _apiService.getSitesInBounds(
        bounds.north,
        bounds.south,
        bounds.east,
        bounds.west,
        limit: 50,
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
          _isLoadingSites = false;
        });
        
        // Mark these bounds as loaded to prevent duplicate requests
        _lastLoadedBoundsKey = boundsKey;
        
        // Load flight counts for the newly loaded sites
        _loadFlightCounts();
      }
    } catch (e) {
      LoggingService.error('EditSiteScreen: Error loading sites', e);
      if (mounted) {
        setState(() {
          _isLoadingSites = false;
        });
      }
    }
  }

  /// Check if an API site duplicates a local site (same coordinates)
  bool _isDuplicateApiSite(ParaglidingSite apiSite) {
    const double tolerance = 0.000001; // ~0.1 meter tolerance for floating point comparison
    
    return _localSites.any((localSite) =>
      (localSite.latitude - apiSite.latitude).abs() < tolerance &&
      (localSite.longitude - apiSite.longitude).abs() < tolerance
    );
  }

  /// Clear cache keys to force refresh of map data
  void _clearMapDataCache() {
    _lastLoadedBoundsKey = null;
    _lastLoadedLaunchesBoundsKey = null;
    _siteFlightCounts.clear(); // Clear flight count cache too
  }
  
  /// Load flight counts for local sites
  Future<void> _loadFlightCounts() async {
    try {
      final Map<int, int> flightCounts = {};
      
      // Load flight counts for all local sites
      for (final site in _localSites) {
        if (site.id != null) {
          final count = await _databaseService.getFlightCountForSite(site.id!);
          flightCounts[site.id!] = count;
        }
      }
      
      if (mounted) {
        setState(() {
          _siteFlightCounts = flightCounts;
        });
      }
    } catch (e) {
      LoggingService.error('EditSiteScreen: Error loading flight counts', e);
    }
  }
  

  /// Load all launches in the current viewport bounds
  Future<void> _loadAllLaunchesInBounds(LatLngBounds bounds) async {
    // Create a unique key for these bounds to prevent duplicate requests
    final boundsKey = '${bounds.north.toStringAsFixed(6)}_${bounds.south.toStringAsFixed(6)}_${bounds.east.toStringAsFixed(6)}_${bounds.west.toStringAsFixed(6)}';
    if (_lastLoadedLaunchesBoundsKey == boundsKey) {
      return; // Same bounds already loaded
    }
    
    try {
      final launches = await _databaseService.getAllLaunchesInBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      );
      
      if (mounted) {
        setState(() {
          _launches = launches;
        });
        
        // Mark these bounds as loaded to prevent duplicate requests
        _lastLoadedLaunchesBoundsKey = boundsKey;
        LoggingService.info('EditSiteScreen: Loaded ${launches.length} launches in viewport');
      }
    } catch (e) {
      LoggingService.error('EditSiteScreen: Error loading launches in bounds', e);
    }
  }




  /// Handle tap on a ParaglidingEarth API site marker

  /// Calculate distance between two points in meters using Haversine formula
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth radius in meters
    
    final double lat1Rad = point1.latitude * (math.pi / 180);
    final double lat2Rad = point2.latitude * (math.pi / 180);
    final double deltaLatRad = (point2.latitude - point1.latitude) * (math.pi / 180);
    final double deltaLngRad = (point2.longitude - point1.longitude) * (math.pi / 180);
    
    final double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLngRad / 2) * math.sin(deltaLngRad / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  /// Find all launches within specified radius of a point
  List<Flight> _findLaunchesWithinRadius(LatLng center, double radiusMeters) {
    return _launches.where((launch) {
      if (launch.launchLatitude == null || launch.launchLongitude == null) {
        return false;
      }
      final launchPoint = LatLng(launch.launchLatitude!, launch.launchLongitude!);
      return _calculateDistance(center, launchPoint) <= radiusMeters;
    }).toList();
  }


  /// Filter launches to only include those closer to the new point than to existing sites
  List<Flight> _filterLaunchesCloserToPoint(List<Flight> launches, LatLng newPoint) {
    return launches.where((launch) {
      final launchPoint = LatLng(launch.launchLatitude!, launch.launchLongitude!);
      final distanceToNewPoint = _calculateDistance(newPoint, launchPoint);
      
      // Check against all existing sites
      for (final site in _localSites) {
        final sitePoint = LatLng(site.latitude, site.longitude);
        final distanceToExistingSite = _calculateDistance(sitePoint, launchPoint);
        if (distanceToExistingSite <= distanceToNewPoint) {
          return false; // Launch is closer to existing site
        }
      }
      
      
      return true; // Launch is closest to new point
    }).toList();
  }

  /// Find the nearest launch with altitude data to a given point
  (Flight?, double?) _findNearestLaunchWithAltitude(LatLng point) {
    Flight? nearestLaunch;
    double? nearestDistance;
    
    for (final launch in _launches) {
      // Skip launches without coordinates or altitude
      if (launch.launchLatitude == null || 
          launch.launchLongitude == null || 
          launch.launchAltitude == null) {
        continue;
      }
      
      final launchPoint = LatLng(launch.launchLatitude!, launch.launchLongitude!);
      final distance = _calculateDistance(point, launchPoint);
      
      if (nearestLaunch == null || distance < nearestDistance!) {
        nearestLaunch = launch;
        nearestDistance = distance;
      }
    }
    
    return (nearestLaunch, nearestDistance);
  }

  /// Find the nearest site with country data for new site creation
  String? _findNearestSiteCountry(LatLng point) {
    String? nearestCountry;
    double? nearestDistance;
    
    // Check local sites first
    for (final site in _localSites) {
      if (site.country == null || site.country!.isEmpty) {
        continue;
      }
      
      final sitePoint = LatLng(site.latitude, site.longitude);
      final distance = _calculateDistance(point, sitePoint);
      
      if (nearestDistance == null || distance < nearestDistance) {
        nearestCountry = site.country;
        nearestDistance = distance;
      }
    }
    
    // Check API sites if no local site found
    if (nearestCountry == null) {
      for (final site in _apiSites) {
        if (site.country == null || site.country!.isEmpty) {
          continue;
        }
        
        final sitePoint = LatLng(site.latitude, site.longitude);
        final distance = _calculateDistance(point, sitePoint);
        
        if (nearestDistance == null || distance < nearestDistance) {
          nearestCountry = site.country;
          nearestDistance = distance;
        }
      }
    }
    
    return nearestCountry;
  }


  /// Handle site creation at a specific point (from map tap or launch click)
  Future<void> _handleSiteCreationAtPoint(LatLng point, {String? siteName, String? country, double? altitude}) async {
    // Find launches within specified radius
    final launchesNearby = _findLaunchesWithinRadius(point, _launchRadiusMeters);
    
    // Filter to only those closer to this point than to existing sites
    final eligibleLaunches = _filterLaunchesCloserToPoint(launchesNearby, point);
    final eligibleLaunchCount = eligibleLaunches.length;
    
    final result = await _showSiteCreationDialog(
      point, 
      eligibleLaunchCount,
      siteName: siteName,
      country: country,
      altitude: altitude,
    );
    
    if (result != null && mounted) {
      await _createSiteAndReassignFlights(
        point: point,
        name: result['name'],
        altitude: result['altitude'],
        country: result['country'],
        eligibleLaunches: eligibleLaunches,
      );
    }
  }

  /// Show the site creation dialog
  Future<Map<String, dynamic>?> _showSiteCreationDialog(
    LatLng point, 
    int eligibleLaunchCount,
    {String? siteName, String? country, double? altitude}
  ) async {
    // Find altitude from nearest launch if not provided
    double? finalAltitude = altitude;
    if (finalAltitude == null) {
      final (nearestLaunch, distance) = _findNearestLaunchWithAltitude(point);
      if (nearestLaunch != null && nearestLaunch.launchAltitude != null) {
        finalAltitude = nearestLaunch.launchAltitude!.toDouble();
      }
    }

    // Auto-populate country from nearest site if not provided
    String? finalCountry = country;
    if (finalCountry == null || finalCountry.isEmpty) {
      finalCountry = _findNearestSiteCountry(point);
    }
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SiteCreationDialog(
        point: point,
        eligibleLaunchCount: eligibleLaunchCount,
        launchRadiusMeters: _launchRadiusMeters,
        siteName: siteName,
        country: finalCountry,
        altitude: finalAltitude,
      ),
    );
  }

  /// Show site edit dialog for any site (current, local, or newly created)
  Future<void> _showSiteEditDialog(Site site) async {
    final nameController = TextEditingController(text: site.name);
    final latitudeController = TextEditingController(text: site.latitude.toString());
    final longitudeController = TextEditingController(text: site.longitude.toString());
    final altitudeController = TextEditingController(text: site.altitude?.toString() ?? '');
    final countryController = TextEditingController(text: site.country ?? '');
    
    final formKey = GlobalKey<FormState>();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Site'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Site Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a site name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: latitudeController,
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_searching),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Required';
                          }
                          final lat = double.tryParse(value);
                          if (lat == null || lat < -90 || lat > 90) {
                            return 'Invalid latitude';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: longitudeController,
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.explore),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Required';
                          }
                          final lon = double.tryParse(value);
                          if (lon == null || lon < -180 || lon > 180) {
                            return 'Invalid longitude';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: altitudeController,
                  decoration: const InputDecoration(
                    labelText: 'Altitude (meters)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.terrain),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final altitude = double.tryParse(value);
                      if (altitude == null) {
                        return 'Invalid altitude';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: countryController,
                  decoration: const InputDecoration(
                    labelText: 'Country',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flag),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (result == true && mounted) {
      try {
        // Update the site with new data
        final updatedSite = site.copyWith(
          name: nameController.text.trim(),
          latitude: double.parse(latitudeController.text.trim()),
          longitude: double.parse(longitudeController.text.trim()),
          altitude: altitudeController.text.trim().isEmpty 
              ? null 
              : double.parse(altitudeController.text.trim()),
          country: countryController.text.trim().isEmpty 
              ? null 
              : countryController.text.trim(),
          customName: true, // Mark as custom since user edited it
        );
        
        await _databaseService.updateSite(updatedSite);
        
        LoggingService.info('EditSiteScreen: Updated site ${updatedSite.id}: ${updatedSite.name}');
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Site "${updatedSite.name}" updated successfully'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          
          // Refresh the map to show updated site data
          _clearMapDataCache();
          if (_currentBounds != null) {
            await _loadSitesForBounds(_currentBounds!);
          }
          await _loadFlightCounts(); // Refresh flight counts
        }
      } catch (e) {
        LoggingService.error('EditSiteScreen: Error updating site', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating site: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
    
    // Clean up controllers
    nameController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
    altitudeController.dispose();
    countryController.dispose();
  }

  /// Handle API site click - create local site first, then edit
  Future<void> _handleApiSiteClick(ParaglidingSite apiSite) async {
    try {
      // Create a new local site from the API site data
      final newSite = Site(
        name: apiSite.name,
        latitude: apiSite.latitude,
        longitude: apiSite.longitude,
        altitude: apiSite.altitude?.toDouble(),
        country: apiSite.country,
        customName: false, // Mark as not custom since from API
      );
      
      final newSiteId = await _databaseService.insertSite(newSite);
      final createdSite = newSite.copyWith(id: newSiteId);
      
      LoggingService.info('EditSiteScreen: Created local site from API site: ${createdSite.name}');
      
      // Find and reassign nearby launches, just like clicking on empty map area
      final sitePoint = LatLng(apiSite.latitude, apiSite.longitude);
      final launchesNearby = _findLaunchesWithinRadius(sitePoint, _launchRadiusMeters);
      final eligibleLaunches = _filterLaunchesCloserToPoint(launchesNearby, sitePoint);
      
      // Reassign eligible flights if any
      if (eligibleLaunches.isNotEmpty) {
        final flightIds = eligibleLaunches.map((f) => f.id!).toList();
        await _databaseService.bulkUpdateFlightSites(flightIds, newSiteId);
        LoggingService.info('EditSiteScreen: Reassigned ${flightIds.length} flights from API site "${apiSite.name}" to new local site');
      }
      
      // Refresh the map to show the new local site
      if (mounted) {
        _clearMapDataCache();
        _updateMapBounds();
        await _loadFlightCounts(); // Refresh flight counts
        
        // Now open the edit dialog for the newly created site
        await _showSiteEditDialog(createdSite);
      }
    } catch (e) {
      LoggingService.error('EditSiteScreen: Error creating site from API site', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating site: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Create the new site and reassign eligible flights
  Future<void> _createSiteAndReassignFlights({
    required LatLng point,
    required String name,
    required double? altitude,
    required String? country,
    required List<Flight> eligibleLaunches,
  }) async {
    try {
      // Create the new site
      final newSite = Site(
        name: name,
        latitude: point.latitude,
        longitude: point.longitude,
        altitude: altitude,
        country: country,
        customName: true,
      );
      
      final newSiteId = await _databaseService.insertSite(newSite);
      LoggingService.info('EditSiteScreen: Created new site "$name" with ID $newSiteId');
      
      // Reassign eligible flights if any
      if (eligibleLaunches.isNotEmpty) {
        final flightIds = eligibleLaunches.map((f) => f.id!).toList();
        await _databaseService.bulkUpdateFlightSites(flightIds, newSiteId);
        LoggingService.info('EditSiteScreen: Reassigned ${flightIds.length} flights to new site');
      }
      
      // Clear cache and refresh the map data
      _clearMapDataCache();
      if (_currentBounds != null) {
        await _loadSitesForBounds(_currentBounds!);
        await _loadAllLaunchesInBounds(_currentBounds!);
      }
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(eligibleLaunches.isEmpty
                ? 'Site "$name" created successfully.'
                : 'Site "$name" created and ${eligibleLaunches.length} flight${eligibleLaunches.length == 1 ? '' : 's'} reassigned.'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
      
    } catch (e) {
      LoggingService.error('EditSiteScreen: Error creating site and reassigning flights', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating site: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Build the drag markers layer containing all draggable site markers
  DragMarkers _buildDragMarkersLayer() {
    List<DragMarker> dragMarkers = [];
    
    // Add local sites markers
    dragMarkers.addAll(_localSites.map(_buildLocalSiteDragMarker));
    
    // Add API sites markers (excluding duplicates)
    dragMarkers.addAll(_apiSites
        .where((site) => !_isDuplicateApiSite(site))
        .map(_buildApiSiteDragMarker));
    
    return DragMarkers(markers: dragMarkers);
  }


  /// Build local site drag marker (blue, draggable)
  DragMarker _buildLocalSiteDragMarker(Site site) {
    final launchCount = site.id != null ? _siteFlightCounts[site.id!] : null;
    
    return DragMarker(
      point: LatLng(site.latitude, site.longitude),
      size: const Size(300, 120), // Wider and taller to accommodate text
      offset: const Offset(0, -_siteMarkerSize / 2),
      dragOffset: const Offset(0, -70), // Move marker well above finger during drag
      onTap: (point) => _isMergeMode ? _handleMergeTarget(site) : _enterMergeMode(site),
      onLongPress: (point) => _isMergeMode ? null : _showSiteEditDialog(site),
      onDragStart: (details, point) {
        setState(() {
          _currentlyDraggedSite = site;
        });
      },
      onDragUpdate: (details, point) => _updateDragHoverState(point),
      builder: (ctx, point, isDragging) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // White outline
              const Icon(
                Icons.location_on,
                color: Colors.white,
                size: _siteMarkerSize,
              ),
              // Blue marker with visual feedback for merge mode
              Icon(
                Icons.location_on,
                color: Colors.blue,
                size: _siteMarkerIconSize,
              ),
              // Merge mode indicator
              if (_isMergeMode && _selectedSourceSite?.id == site.id)
                Container(
                  width: _siteMarkerSize + 8,
                  height: _siteMarkerSize + 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orange, width: 3),
                  ),
                ),
              // Valid merge target indicator
              if (_isMergeMode && _selectedSourceSite?.id != site.id)
                Container(
                  width: _siteMarkerSize + 4,
                  height: _siteMarkerSize + 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                ),
              // Drag hover target indicator
              if (_currentlyDraggedSite != null && 
                  _hoveredTargetSite == site && 
                  _currentlyDraggedSite!.id != site.id)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: _siteMarkerSize + 12,
                  height: _siteMarkerSize + 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 4),
                  ),
                ),
            ],
          ),
          // Text label
          IntrinsicWidth(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 140),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    site.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (launchCount != null && launchCount > 0)
                    Text(
                      '$launchCount flight${launchCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      onDragEnd: (details, point) {
        _clearDragState();
        _handleFlownSiteDrop(site, point);
      },
    );
  }

  /// Build API site drag marker (green, not draggable - only drop target)
  DragMarker _buildApiSiteDragMarker(ParaglidingSite site) {
    // API sites have no local flight counts, always 0
    
    return DragMarker(
      point: LatLng(site.latitude, site.longitude),
      size: const Size(300, 120), // Wider and taller to accommodate text
      offset: const Offset(0, -_siteMarkerSize / 2),
      disableDrag: true, // Cannot drag API sites, only drop onto them
      onTap: (point) => _isMergeMode ? _handleMergeIntoApiSite(site) : null,
      onLongPress: (point) => _isMergeMode ? null : _handleApiSiteClick(site),
      builder: (ctx, point, isDragging) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // White outline
              const Icon(
                Icons.location_on,
                color: Colors.white,
                size: _siteMarkerSize,
              ),
              // Green marker
              const Icon(
                Icons.location_on,
                color: Colors.green,
                size: _siteMarkerIconSize,
              ),
              // Merge target indicator
              if (_isMergeMode && _selectedSourceSite != null)
                Container(
                  width: _siteMarkerSize + 4,
                  height: _siteMarkerSize + 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                ),
              // Drag hover target indicator
              if (_currentlyDraggedSite != null && _hoveredTargetSite == site)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: _siteMarkerSize + 12,
                  height: _siteMarkerSize + 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green, width: 4),
                  ),
                ),
            ],
          ),
          // Text label - API sites show only name
          IntrinsicWidth(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 140),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                site.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }


  /// Get marker color based on state

  /// Enter merge mode
  void _enterMergeMode(Site sourceSite) {
    setState(() {
      _selectedSourceSite = sourceSite;
      _isMergeMode = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Select target site to merge "${sourceSite.name}" into'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Cancel',
          onPressed: _exitMergeMode,
        ),
      ),
    );
  }

  /// Exit merge mode
  void _exitMergeMode() {
    setState(() {
      _selectedSourceSite = null;
      _isMergeMode = false;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// Handle merge target selection
  void _handleMergeTarget(Site targetSite) {
    if (_selectedSourceSite == null || _selectedSourceSite!.id == targetSite.id) {
      return;
    }

    // Perform the merge
    _mergeFlownIntoFlownSite(_selectedSourceSite!, targetSite);
    _exitMergeMode();
  }

  /// Handle merge into API site target
  void _handleMergeIntoApiSite(ParaglidingSite apiSite) {
    if (_selectedSourceSite == null) {
      return;
    }

    // Perform the merge
    _mergeFlownIntoApiSite(_selectedSourceSite!, apiSite);
    _exitMergeMode();
  }


  /// Handle flown site drop - check for merge with any site
  Future<void> _handleFlownSiteDrop(Site sourceSite, LatLng dropPoint) async {
    // Check if marker snapped back to original position (timeout/cancelled drag)
    const double snapBackTolerance = 0.000001; // ~0.1 meters tolerance for GPS/rounding differences
    final originalPosition = LatLng(sourceSite.latitude, sourceSite.longitude);
    if ((dropPoint.latitude - originalPosition.latitude).abs() < snapBackTolerance &&
        (dropPoint.longitude - originalPosition.longitude).abs() < snapBackTolerance) {
      // Ignore snap-back events - marker returned to original position due to timeout
      return;
    }
    
    // Find if dropped on any site
    final targetSite = _findSiteAtPoint(dropPoint);
    if (targetSite == null) return;
    
    // Handle different target site types
    if (targetSite is Site) {
      // Dropped on another flown site - merge flown into flown
      await _mergeFlownIntoFlownSite(sourceSite, targetSite);
    } else if (targetSite is ParaglidingSite) {
      // Dropped on API site - merge flown into API site
      await _mergeFlownIntoApiSite(sourceSite, targetSite);
    }
  }

  /// Find site at the given point using screen-based pixel hit detection
  dynamic _findSiteAtPoint(LatLng point) {
    if (_mapController == null) return null;
    
    final camera = _mapController!.camera;
    final dropPixel = camera.projectAtZoom(point, camera.zoom);
    
    // Use marker visual size for hit detection
    const double hitRadius = 18.0; // Half of 36px marker size
    
    // Check local sites (flown sites)
    for (final site in _localSites) {
      final sitePixel = camera.projectAtZoom(LatLng(site.latitude, site.longitude), camera.zoom);
      final distance = (dropPixel - sitePixel).distance;
      if (distance <= hitRadius) {
        return site;
      }
    }
    
    // Check API sites (new sites) 
    for (final site in _apiSites) {
      if (_isDuplicateApiSite(site)) continue; // Skip duplicates
      
      final sitePixel = camera.projectAtZoom(LatLng(site.latitude, site.longitude), camera.zoom);
      final distance = (dropPixel - sitePixel).distance;
      if (distance <= hitRadius) {
        return site;
      }
    }
    
    return null;
  }

  /// Update drag hover state based on current drag position
  void _updateDragHoverState(LatLng dragPosition) {
    final hoveredSite = _findSiteAtPoint(dragPosition);
    
    // Only update if the hovered site has changed
    if (_hoveredTargetSite != hoveredSite) {
      setState(() {
        _hoveredTargetSite = hoveredSite;
      });
    }
  }

  /// Clear all drag-related state
  void _clearDragState() {
    setState(() {
      _currentlyDraggedSite = null;
      _hoveredTargetSite = null;
    });
  }




  /// Merge flown site into another flown site
  Future<void> _mergeFlownIntoFlownSite(Site sourceSite, Site targetSite) async {
    // Get the flights that will be affected
    final affectedFlights = await _databaseService.getFlightsBySite(sourceSite.id!);
    
    if (!mounted) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge sites?'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Merge "${sourceSite.name}" into "${targetSite.name}"?'),
              const SizedBox(height: 16),
              Text(
                'This will move ${affectedFlights.length} flight${affectedFlights.length == 1 ? '' : 's'} from "${sourceSite.name}" to "${targetSite.name}".',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge Sites'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      try {
        // Move source site's flights to target site
        await _databaseService.reassignFlights(sourceSite.id!, targetSite.id!);
        
        // Delete source site
        await _databaseService.deleteSite(sourceSite.id!);
        
        LoggingService.info('EditSiteScreen: Moved ${affectedFlights.length} flights from "${sourceSite.name}" to "${targetSite.name}"');
        
        // Clear cache and refresh the map data to show changes
        _clearMapDataCache();
        if (_currentBounds != null) {
          await _loadSitesForBounds(_currentBounds!);
          await _loadAllLaunchesInBounds(_currentBounds!);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Merged "${sourceSite.name}" into "${targetSite.name}" successfully'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      } catch (e) {
        LoggingService.error('EditSiteScreen: Error merging flown sites', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error merging sites: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  /// Merge flown site into an API site
  Future<void> _mergeFlownIntoApiSite(Site sourceSite, ParaglidingSite apiSite) async {
    // Get the flights that will be affected
    final affectedFlights = await _databaseService.getFlightsBySite(sourceSite.id!);
    
    if (!mounted) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge sites?'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Merge "${sourceSite.name}" into "${apiSite.name}"?'),
              const SizedBox(height: 16),
              Text(
                'This will move ${affectedFlights.length} flight${affectedFlights.length == 1 ? '' : 's'} from "${sourceSite.name}" to the new site "${apiSite.name}".',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge Sites'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      try {
        // Create the API site in database
        final newSite = Site(
          name: apiSite.name,
          latitude: apiSite.latitude,
          longitude: apiSite.longitude,
          altitude: apiSite.altitude?.toDouble(),
          country: apiSite.country,
          customName: false, // Mark as not custom since from API
        );
        
        final newSiteId = await _databaseService.insertSite(newSite);
        LoggingService.info('EditSiteScreen: Created new site "${apiSite.name}" with ID $newSiteId from API data');
        
        // Move source site's flights to new API site
        await _databaseService.reassignFlights(sourceSite.id!, newSiteId);
        
        // Delete source site
        await _databaseService.deleteSite(sourceSite.id!);
        
        LoggingService.info('EditSiteScreen: Moved ${affectedFlights.length} flights from "${sourceSite.name}" to API site "${apiSite.name}"');
        
        // Clear cache and refresh the map data to show changes
        _clearMapDataCache();
        if (_currentBounds != null) {
          await _loadSitesForBounds(_currentBounds!);
          await _loadAllLaunchesInBounds(_currentBounds!);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Merged "${sourceSite.name}" into new site "${apiSite.name}" successfully'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      } catch (e) {
        LoggingService.error('EditSiteScreen: Error merging flown site into API site', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error merging sites: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildLocationMap() {
    _mapController ??= MapController();
    
    // Use provided coordinates or default location
    final initialLat = widget.initialCoordinates?.latitude ?? _defaultLatitude;
    final initialLon = widget.initialCoordinates?.longitude ?? _defaultLongitude;
    
    return Stack(
      children: [
        FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(initialLat, initialLon),
        initialZoom: _initialZoom,
        onMapReady: _onMapReady,
        onMapEvent: _onMapEvent,
        onLongPress: _onMapTap,
        // Dynamic zoom limits based on selected provider
        minZoom: _minZoom,
        maxZoom: _selectedMapProvider.maxZoom.toDouble(),
      ),
      children: [
        // Map layers in order (bottom to top)
        _buildTileLayer(),
        _buildLaunchesLayer(),
        // DragMarkers layer must be last to handle gestures properly
        _buildDragMarkersLayer(),
      ],
    ),
        // Map overlays
        _buildAttribution(),
        Positioned(
          top: 8,
          right: 8,
          child: _buildMapControls(),
        ),
        _buildLegend(),
        if (_buildLoadingIndicator() != null) _buildLoadingIndicator()!,
      ],
    );
  }

}

/// Site creation dialog widget that properly manages its own state and controllers
class SiteCreationDialog extends StatefulWidget {
  final LatLng? point;
  final int eligibleLaunchCount;
  final String? siteName;
  final String? country;
  final double? altitude;
  final double launchRadiusMeters;

  const SiteCreationDialog({
    super.key,
    this.point,
    required this.eligibleLaunchCount,
    required this.launchRadiusMeters,
    this.siteName,
    this.country,
    this.altitude,
  });

  @override
  State<SiteCreationDialog> createState() => _SiteCreationDialogState();
}

class _SiteCreationDialogState extends State<SiteCreationDialog> {
  late TextEditingController _nameController;
  late TextEditingController _latitudeController;
  late TextEditingController _longitudeController;
  late TextEditingController _altitudeController;
  late TextEditingController _countryController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.siteName ?? '');
    _latitudeController = TextEditingController(text: widget.point != null ? widget.point!.latitude.toStringAsFixed(6) : '');
    _longitudeController = TextEditingController(text: widget.point != null ? widget.point!.longitude.toStringAsFixed(6) : '');
    _altitudeController = TextEditingController(text: widget.altitude?.toStringAsFixed(0) ?? '');
    _countryController = TextEditingController(text: widget.country ?? '');

    // Add listeners to trigger rebuilds when text changes
    _nameController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onTextChanged);
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _altitudeController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {}); // Trigger rebuild to update button state
  }


  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Site'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Site details form
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Site Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latitudeController,
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _longitudeController,
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _altitudeController,
                    decoration: const InputDecoration(
                      labelText: 'Altitude (m)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _countryController,
                    decoration: const InputDecoration(
                      labelText: 'Country',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            
            if (widget.eligibleLaunchCount > 0) ...[
              const SizedBox(height: 16),
              Text(
                '${widget.eligibleLaunchCount} flight${widget.eligibleLaunchCount == 1 ? '' : 's'} within ${widget.launchRadiusMeters.toInt()}m will be reassigned to this new site.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _nameController.text.trim().isEmpty ? null : () {
            final latitude = double.tryParse(_latitudeController.text.trim());
            final longitude = double.tryParse(_longitudeController.text.trim());
            
            if (latitude == null || longitude == null) {
              // Show error for invalid coordinates
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enter valid latitude and longitude values'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            
            if (latitude < -90 || latitude > 90) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Latitude must be between -90 and 90'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            
            if (longitude < -180 || longitude > 180) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Longitude must be between -180 and 180'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            
            Navigator.of(context).pop({
              'name': _nameController.text.trim(),
              'latitude': latitude,
              'longitude': longitude,
              'altitude': _altitudeController.text.trim().isEmpty ? null : double.tryParse(_altitudeController.text.trim()),
              'country': _countryController.text.trim().isEmpty ? null : _countryController.text.trim(),
            });
          },
          child: Text('Create Site${widget.eligibleLaunchCount > 0 ? ' & Reassign Flights' : ''}'),
        ),
      ],
    );
  }
}

/// Help item widget for the instructions dialog
class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _HelpItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Debug tile provider that logs actual network requests (not cached tiles)
class _DebugNetworkTileProvider extends NetworkTileProvider {
  _DebugNetworkTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    LoggingService.debug('Network tile request: z${coordinates.z}/${coordinates.x}/${coordinates.y}');
    return super.getImage(coordinates, options);
  }
}
