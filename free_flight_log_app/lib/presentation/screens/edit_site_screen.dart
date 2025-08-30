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
  final Site? site;
  final ({double latitude, double longitude})? actualLaunchCoordinates;

  const EditSiteScreen({
    super.key, 
    this.site,
    this.actualLaunchCoordinates,
  });

  @override
  State<EditSiteScreen> createState() => _EditSiteScreenState();
}

class _EditSiteScreenState extends State<EditSiteScreen> {
  late TextEditingController _nameController;
  late TextEditingController _latitudeController;
  late TextEditingController _longitudeController;
  late TextEditingController _altitudeController;
  late TextEditingController _countryController;
  MapController? _mapController;
  MapProvider _selectedMapProvider = MapProvider.openStreetMap;
  
  // Constants
  static const String _mapProviderKey = 'edit_site_map_provider';
  static const double _defaultLatitude = 46.9480; // Swiss Alps
  static const double _defaultLongitude = 7.4474;
  static const double _initialZoom = 13.0;
  static const double _minZoom = 1.0;
  static const double _launchMarkerSize = 16.0;
  static const double _siteMarkerSize = 36.0;
  static const double _siteMarkerIconSize = 32.0;
  static const double _currentSiteMarkerSize = 40.0;
  static const double _boundsThreshold = 0.001;
  static const int _debounceDurationMs = 500;
  static const double _launchRadiusMeters = 500.0;
  
  // Site markers state
  List<Site> _localSites = [];
  List<ParaglidingSite> _apiSites = [];
  List<Flight> _launches = [];
  Timer? _debounceTimer;
  LatLngBounds? _currentBounds;
  bool _isLoadingSites = false;
  String? _lastLoadedBoundsKey;
  String? _lastLoadedLaunchesBoundsKey;
  Timer? _cacheRefreshTimer;
  
  // Drag and drop state - no longer needed as we use geographical distance
  
  // Flight count cache for tooltips
  Map<int, int> _siteFlightCounts = {};
  
  // Services
  final DatabaseService _databaseService = DatabaseService.instance;
  final ParaglidingEarthApi _apiService = ParaglidingEarthApi.instance;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _latitudeController = TextEditingController();
    _longitudeController = TextEditingController();
    _altitudeController = TextEditingController();
    _countryController = TextEditingController();
    _loadMapProviderPreference();
    _loadFlightCounts(); // Load flight counts for current site
    
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

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _cacheRefreshTimer?.cancel();
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _altitudeController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.site == null ? 'Add Site' : 'Edit Site'),
      ),
      body: _buildMapSection(),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, -2),
            ),
          ],
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
    final isFromCurrentSite = widget.site != null && launch.launchSiteId == widget.site!.id;
    final markerColor = isFromCurrentSite ? Colors.red : Colors.blue;
    
    // Build tooltip message with site name and date
    final siteName = launch.launchSiteName ?? 'Unknown Site';
    final date = launch.date.toLocal().toString().split(' ')[0];
    final tooltipMessage = '$siteName\n$date';
    
    return Marker(
      point: LatLng(launch.launchLatitude!, launch.launchLongitude!),
      width: _launchMarkerSize,
      height: _launchMarkerSize,
      child: GestureDetector(
        onTap: () => _handleSiteCreationAtPoint(
          LatLng(launch.launchLatitude!, launch.launchLongitude!),
          siteName: 'Launch ${launch.date.toLocal().toString().split(' ')[0]}',
          country: 'Unknown',
          altitude: launch.launchAltitude,
        ),
        child: Tooltip(
          message: tooltipMessage,
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


  /// Build the actual launch coordinates layer (if available)
  MarkerLayer? _buildActualLaunchLayer() {
    if (widget.actualLaunchCoordinates == null) return null;
    
    return MarkerLayer(
      markers: [
        Marker(
          point: LatLng(
            widget.actualLaunchCoordinates!.latitude,
            widget.actualLaunchCoordinates!.longitude,
          ),
          width: _siteMarkerSize,
          height: _siteMarkerSize,
          child: Tooltip(
            message: 'Actual Launch\n${widget.actualLaunchCoordinates!.latitude.toStringAsFixed(6)}, ${widget.actualLaunchCoordinates!.longitude.toStringAsFixed(6)}',
            child: Stack(
              alignment: Alignment.center,
              children: [
                // White outline
                const Icon(
                  Icons.location_on,
                  color: Colors.white,
                  size: _siteMarkerSize,
                ),
                // Amber marker
                const Icon(
                  Icons.location_on,
                  color: Colors.amber,
                  size: _siteMarkerIconSize,
                ),
              ],
            ),
          ),
        ),
      ],
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
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
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
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.site != null) ...[
              _buildLegendItem(Icons.location_pin, Colors.red, 'Current Site'),
              const SizedBox(height: 4),
            ],
            if (_launches.isNotEmpty) ...[
              _buildLegendItem(null, Colors.red, 'Launches (current)', isCircle: true),
              const SizedBox(height: 4),
              _buildLegendItem(null, Colors.blue, 'Launches (others)', isCircle: true),
              const SizedBox(height: 4),
            ],
            if (widget.actualLaunchCoordinates != null) ...[
              _buildLegendItem(Icons.location_on, Colors.amber, 'Actual Launch'),
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
      country: 'Unknown',
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
      
      // Load flight counts for all local sites (including current site)
      final allSites = [..._localSites];
      if (widget.site?.id != null) {
        allSites.add(widget.site!);
      }
      
      for (final site in allSites) {
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
  
  /// Create consistent tooltip format for all site types
  String _createSiteTooltip(String name, String? country, int? launchCount) {
    final parts = <String>[];
    
    // Name (or fallback)
    parts.add(name.trim().isEmpty ? 'Unknown Site' : name);
    
    // Country
    if (country != null && country.isNotEmpty) {
      parts.add(country);
    }
    
    // Launches count
    final count = launchCount ?? 0;
    parts.add('$count launch${count == 1 ? '' : 'es'}');
    
    return parts.join('\n');
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

  /// Load launches for the current site being edited (legacy method for initial bounds adjustment)
  Future<void> _loadLaunchesForSite() async {
    if (widget.site?.id == null) return;
    
    try {
      final launches = await _databaseService.getFlightsWithLaunchCoordinatesForSite(widget.site!.id!);
      
      if (mounted) {
        setState(() {
          _launches = launches;
        });
        
        LoggingService.info('EditSiteScreen: Loaded ${launches.length} launches for site');
        
        // Adjust map bounds to include all launches if we have them
        if (launches.isNotEmpty && _mapController != null) {
          _adjustMapBoundsToIncludeLaunches();
        }
      }
    } catch (e) {
      LoggingService.error('EditSiteScreen: Error loading launches', e);
    }
  }

  /// Adjust map bounds to include all launches
  void _adjustMapBoundsToIncludeLaunches() {
    if (_launches.isEmpty || _mapController == null) return;
    
    double minLat = widget.site!.latitude;
    double maxLat = widget.site!.latitude;
    double minLng = widget.site!.longitude;
    double maxLng = widget.site!.longitude;
    
    for (final launch in _launches) {
      if (launch.launchLatitude != null && launch.launchLongitude != null) {
        minLat = math.min(minLat, launch.launchLatitude!);
        maxLat = math.max(maxLat, launch.launchLatitude!);
        minLng = math.min(minLng, launch.launchLongitude!);
        maxLng = math.max(maxLng, launch.launchLongitude!);
      }
    }
    
    // Add some padding
    const padding = 0.005; // ~500m
    final bounds = LatLngBounds(
      LatLng(minLat - padding, minLng - padding),
      LatLng(maxLat + padding, maxLng + padding),
    );
    
    _mapController!.fitCamera(CameraFit.bounds(bounds: bounds));
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
      
      // Check against API sites (excluding duplicates)
      for (final site in _apiSites) {
        if (!_isDuplicateApiSite(site)) {
          final sitePoint = LatLng(site.latitude, site.longitude);
          final distanceToExistingSite = _calculateDistance(sitePoint, launchPoint);
          if (distanceToExistingSite <= distanceToNewPoint) {
            return false; // Launch is closer to existing site
          }
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
    final nameController = TextEditingController();
    final altitudeController = TextEditingController();
    final countryController = TextEditingController();
    
    // Pre-populate fields with passed values
    nameController.text = siteName ?? '';
    countryController.text = country ?? '';
    
    if (altitude != null) {
      altitudeController.text = altitude.toStringAsFixed(0);
    } else {
      // No altitude provided - find nearest launch with altitude data
      final (nearestLaunch, distance) = _findNearestLaunchWithAltitude(point);
      if (nearestLaunch != null && nearestLaunch.launchAltitude != null) {
        altitudeController.text = nearestLaunch.launchAltitude!.toStringAsFixed(0);
      }
    }
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create New Site'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Location:', '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}'),
                const SizedBox(height: 16),
                
                // Site details form
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Site Name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() {}), // Trigger rebuild when text changes
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: altitudeController,
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
                      controller: countryController,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              
              if (eligibleLaunchCount > 0) ...[
                const SizedBox(height: 16),
                Text(
                  '$eligibleLaunchCount flight${eligibleLaunchCount == 1 ? '' : 's'} within ${_launchRadiusMeters.toInt()}m will be reassigned to this new site.',
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
              onPressed: nameController.text.trim().isEmpty ? null : () => Navigator.of(context).pop({
                'name': nameController.text.trim(),
                'altitude': altitudeController.text.trim().isEmpty ? null : double.tryParse(altitudeController.text.trim()),
                'country': countryController.text.trim().isEmpty ? null : countryController.text.trim(),
              }),
              child: Text('Create Site${eligibleLaunchCount > 0 ? ' & Reassign Flights' : ''}'),
            ),
          ],
        ),
      ),
    );
    
    // Clean up controllers
    nameController.dispose();
    altitudeController.dispose();
    countryController.dispose();
    
    return result;
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
        
        // Refresh the map to show updated site data
        if (mounted) {
          _clearMapDataCache();
          _updateMapBounds();
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
      await _loadLaunchesForSite();
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
    
    // Add current site marker (if editing)
    if (widget.site != null) {
      dragMarkers.add(_buildCurrentSiteDragMarker());
    }
    
    // Add local sites markers (excluding current site when editing)
    dragMarkers.addAll(_localSites
        .where((site) => widget.site == null || site.id != widget.site!.id)
        .map(_buildLocalSiteDragMarker));
    
    // Add API sites markers (excluding duplicates and current site)
    dragMarkers.addAll(_apiSites
        .where((site) => 
            !_isDuplicateApiSite(site) && 
            (widget.site == null || 
             site.latitude != widget.site!.latitude || 
             site.longitude != widget.site!.longitude))
        .map(_buildApiSiteDragMarker));
    
    return DragMarkers(markers: dragMarkers);
  }

  /// Build current site drag marker (red, draggable)
  DragMarker _buildCurrentSiteDragMarker() {
    final launchCount = widget.site!.id != null ? _siteFlightCounts[widget.site!.id!] : null;
    final tooltipMessage = _createSiteTooltip(widget.site!.name, widget.site!.country, launchCount);
        
    return DragMarker(
      point: LatLng(widget.site!.latitude, widget.site!.longitude),
      size: const Size.square(_currentSiteMarkerSize),
      offset: const Offset(0, -_currentSiteMarkerSize / 2),
      onTap: (point) => _showSiteEditDialog(widget.site!),
      builder: (ctx, point, isDragging) => Tooltip(
        message: tooltipMessage,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // White outline
            Icon(
              Icons.location_on,
              color: Colors.white,
              size: _currentSiteMarkerSize,
            ),
            // Red marker with opacity during drag
            Icon(
              Icons.location_on,
              color: isDragging ? Colors.red.withValues(alpha: 0.7) : Colors.red,
              size: _siteMarkerSize,
            ),
          ],
        ),
      ),
      onDragEnd: (details, point) => _handleCurrentSiteDrop(details, point),
    );
  }

  /// Build local site drag marker (blue, draggable)
  DragMarker _buildLocalSiteDragMarker(Site site) {
    final launchCount = site.id != null ? _siteFlightCounts[site.id!] : null;
    final tooltipMessage = _createSiteTooltip(site.name, site.country, launchCount);
    
    return DragMarker(
      point: LatLng(site.latitude, site.longitude),
      size: const Size.square(_siteMarkerSize),
      offset: const Offset(0, -_siteMarkerSize / 2),
      onTap: (point) => _showSiteEditDialog(site),
      builder: (ctx, point, isDragging) => Tooltip(
        message: tooltipMessage,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // White outline
            const Icon(
              Icons.location_on,
              color: Colors.white,
              size: _siteMarkerSize,
            ),
            // Blue marker with opacity during drag
            Icon(
              Icons.location_on,
              color: isDragging ? Colors.blue.withValues(alpha: 0.7) : Colors.blue,
              size: _siteMarkerIconSize,
            ),
          ],
        ),
      ),
      onDragEnd: (details, point) => _handleFlownSiteDrop(site, point),
    );
  }

  /// Build API site drag marker (green, not draggable - only drop target)
  DragMarker _buildApiSiteDragMarker(ParaglidingSite site) {
    // API sites have no local flight counts, always 0
    final tooltipMessage = _createSiteTooltip(site.name, site.country, 0);
    
    return DragMarker(
      point: LatLng(site.latitude, site.longitude),
      size: const Size.square(_siteMarkerSize),
      offset: const Offset(0, -_siteMarkerSize / 2),
      disableDrag: true, // Cannot drag API sites, only drop onto them
      onTap: (point) => _handleApiSiteClick(site),
      builder: (ctx, point, isDragging) => Tooltip(
        message: tooltipMessage,
        child: Stack(
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
          ],
        ),
      ),
    );
  }

  /// Build an info row for the dialog
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  /// Handle current site drop - check for merge with flown or new sites
  Future<void> _handleCurrentSiteDrop(DragEndDetails details, LatLng dropPoint) async {
    if (widget.site == null) return;
    
    // Check if marker snapped back to original position (timeout/cancelled drag)
    const double snapBackTolerance = 0.000001; // ~0.1 meters tolerance for GPS/rounding differences
    final originalPosition = LatLng(widget.site!.latitude, widget.site!.longitude);
    if ((dropPoint.latitude - originalPosition.latitude).abs() < snapBackTolerance &&
        (dropPoint.longitude - originalPosition.longitude).abs() < snapBackTolerance) {
      // Ignore snap-back events - marker returned to original position due to timeout
      return;
    }
    
    // Find if dropped on another site
    final targetSite = _findSiteAtPoint(dropPoint);
    if (targetSite == null) return;
    
    // Only allow dropping current site on flown (local) or new (API) sites
    if (targetSite is Site) {
      // Dropped on flown site - merge current into flown
      await _mergeCurrentIntoFlownSite(targetSite);
    } else if (targetSite is ParaglidingSite) {
      // Dropped on new (API) site - merge current into API site
      await _mergeCurrentIntoApiSite(targetSite);
    }
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
    
    // Find if dropped on any site (including current site)
    final targetSite = _findSiteAtPoint(dropPoint, includeCurrentSite: true);
    if (targetSite == null) return;
    
    // Handle different target site types
    if (targetSite == widget.site) {
      // Dropped on current site - merge flown into current
      await _mergeFlownIntoCurrent(sourceSite);
    } else if (targetSite is Site) {
      // Dropped on another flown site - merge flown into flown
      await _mergeFlownIntoFlownSite(sourceSite, targetSite);
    } else if (targetSite is ParaglidingSite) {
      // Dropped on API site - merge flown into API site
      await _mergeFlownIntoApiSite(sourceSite, targetSite);
    }
  }

  /// Find site at the given point using screen-based pixel hit detection
  dynamic _findSiteAtPoint(LatLng point, {bool includeCurrentSite = false}) {
    if (_mapController == null) return null;
    
    final camera = _mapController!.camera;
    final dropPixel = camera.projectAtZoom(point, camera.zoom);
    
    // Use marker visual size for hit detection
    // Current site: 40px, Other sites: 36px - use half as hit radius
    const double normalHitRadius = 18.0; // Half of 36px marker size
    const double currentSiteHitRadius = 20.0; // Half of 40px current site marker size
    
    // Check current site if requested and editing
    if (includeCurrentSite && widget.site != null) {
      final sitePixel = camera.projectAtZoom(LatLng(widget.site!.latitude, widget.site!.longitude), camera.zoom);
      final distance = (dropPixel - sitePixel).distance;
      if (distance <= currentSiteHitRadius) {
        return widget.site;
      }
    }
    
    // Check local sites (flown sites)
    for (final site in _localSites) {
      if (widget.site != null && site.id == widget.site!.id) continue; // Skip current site
      
      final sitePixel = camera.projectAtZoom(LatLng(site.latitude, site.longitude), camera.zoom);
      final distance = (dropPixel - sitePixel).distance;
      if (distance <= normalHitRadius) {
        return site;
      }
    }
    
    // Check API sites (new sites) 
    for (final site in _apiSites) {
      if (_isDuplicateApiSite(site)) continue; // Skip duplicates
      if (widget.site != null && 
          site.latitude == widget.site!.latitude && 
          site.longitude == widget.site!.longitude) {
        continue; // Skip current site
      }
      
      final sitePixel = camera.projectAtZoom(LatLng(site.latitude, site.longitude), camera.zoom);
      final distance = (dropPixel - sitePixel).distance;
      if (distance <= normalHitRadius) {
        return site;
      }
    }
    
    return null;
  }

  /// Merge current site into a flown (local) site
  Future<void> _mergeCurrentIntoFlownSite(Site targetSite) async {
    if (widget.site == null || widget.site!.id == null) return;
    
    // Get the flights that will be affected
    final affectedFlights = await _databaseService.getFlightsBySite(widget.site!.id!);
    
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
              Text('Merge "${widget.site!.name}" into "${targetSite.name}"?'),
              const SizedBox(height: 16),
              Text(
                'This will move ${affectedFlights.length} flight${affectedFlights.length == 1 ? '' : 's'} from "${widget.site!.name}" to "${targetSite.name}".',
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
        // Move current site's flights to target site
        await _databaseService.reassignFlights(widget.site!.id!, targetSite.id!);
        
        // Delete current site
        await _databaseService.deleteSite(widget.site!.id!);
        
        LoggingService.info('EditSiteScreen: Merged "${widget.site!.name}" into "${targetSite.name}"');
        
        if (mounted) {
          // Replace current EditSiteScreen with one editing the target site
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => EditSiteScreen(site: targetSite),
            ),
          );
        }
      } catch (e) {
        LoggingService.error('EditSiteScreen: Error merging sites', e);
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

  /// Merge current site into an API site
  Future<void> _mergeCurrentIntoApiSite(ParaglidingSite targetSite) async {
    if (widget.site == null || widget.site!.id == null) return;
    
    // Get the flights that will be affected
    final affectedFlights = await _databaseService.getFlightsBySite(widget.site!.id!);
    
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
              Text('Merge "${widget.site!.name}" into "${targetSite.name}"?'),
              const SizedBox(height: 16),
              Text(
                'This will move ${affectedFlights.length} flight${affectedFlights.length == 1 ? '' : 's'} from "${widget.site!.name}" to a new site using "${targetSite.name}" data.',
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
        // Create a new site from the API site data
        final newSite = Site(
          name: targetSite.name,
          latitude: targetSite.latitude,
          longitude: targetSite.longitude,
          altitude: targetSite.altitude?.toDouble(),
          country: targetSite.country,
          customName: false, // Mark as not custom since from API
        );
        final newSiteId = await _databaseService.insertSite(newSite);
        final createdSite = newSite.copyWith(id: newSiteId);
        
        // Move current site's flights to the new site
        await _databaseService.reassignFlights(widget.site!.id!, newSiteId);
        
        // Delete current site
        await _databaseService.deleteSite(widget.site!.id!);
        
        LoggingService.info('EditSiteScreen: Merged "${widget.site!.name}" into "${targetSite.name}"');
        
        if (mounted) {
          // Replace current EditSiteScreen with one editing the new site
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => EditSiteScreen(site: createdSite),
            ),
          );
        }
      } catch (e) {
        LoggingService.error('EditSiteScreen: Error updating site with API data', e);
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
  }

  /// Merge flown site into current site
  Future<void> _mergeFlownIntoCurrent(Site sourceSite) async {
    if (widget.site == null || widget.site!.id == null) return;
    
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
              Text('Merge "${sourceSite.name}" into "${widget.site!.name}"?'),
              const SizedBox(height: 16),
              Text(
                'This will move ${affectedFlights.length} flight${affectedFlights.length == 1 ? '' : 's'} from "${sourceSite.name}" to "${widget.site!.name}".',
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
        // Move source site's flights to current site
        await _databaseService.reassignFlights(sourceSite.id!, widget.site!.id!);
        
        // Delete source site
        await _databaseService.deleteSite(sourceSite.id!);
        
        LoggingService.info('EditSiteScreen: Moved ${affectedFlights.length} flights from "${sourceSite.name}" to "${widget.site!.name}"');
        
        // Clear cache and refresh the map data to show changes
        _clearMapDataCache();
        await _loadLaunchesForSite();
        if (_currentBounds != null) {
          await _loadSitesForBounds(_currentBounds!);
          await _loadAllLaunchesInBounds(_currentBounds!);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Merged "${sourceSite.name}" into "${widget.site!.name}" successfully'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      } catch (e) {
        LoggingService.error('EditSiteScreen: Error merging sites', e);
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
              const SizedBox(height: 8),
              Text(
                'The source site "${sourceSite.name}" will be deleted after merging.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
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
        await _loadLaunchesForSite();
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
        await _loadLaunchesForSite();
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
    
    // Use site coordinates if editing, otherwise use default location
    final initialLat = widget.site?.latitude ?? _defaultLatitude;
    final initialLon = widget.site?.longitude ?? _defaultLongitude;
    
    return Stack(
      children: [
        FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(initialLat, initialLon),
        initialZoom: _initialZoom,
        onMapReady: _onMapReady,
        onMapEvent: _onMapEvent,
        onTap: _onMapTap,
        // Dynamic zoom limits based on selected provider
        minZoom: _minZoom,
        maxZoom: _selectedMapProvider.maxZoom.toDouble(),
      ),
      children: [
        // Map layers in order (bottom to top)
        _buildTileLayer(),
        _buildLaunchesLayer(),
        if (widget.actualLaunchCoordinates != null) _buildActualLaunchLayer()!,
        // DragMarkers layer must be last to handle gestures properly
        _buildDragMarkersLayer(),
        // Attribution overlay - required for OSM and satellite tiles
        Align(
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
        ),
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

/// Debug tile provider that logs actual network requests (not cached tiles)
class _DebugNetworkTileProvider extends NetworkTileProvider {
  _DebugNetworkTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    LoggingService.debug('Network tile request: z${coordinates.z}/${coordinates.x}/${coordinates.y}');
    return super.getImage(coordinates, options);
  }
}
