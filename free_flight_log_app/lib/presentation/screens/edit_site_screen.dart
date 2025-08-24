import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/flight.dart';
import '../../services/database_service.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';
import '../../utils/cache_utils.dart';

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
  final _formKey = GlobalKey<FormState>();
  
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
  
  // Services
  final DatabaseService _databaseService = DatabaseService.instance;
  final ParaglidingEarthApi _apiService = ParaglidingEarthApi.instance;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.site?.name ?? '');
    _latitudeController = TextEditingController(text: widget.site?.latitude.toString() ?? '');
    _longitudeController = TextEditingController(text: widget.site?.longitude.toString() ?? '');
    _altitudeController = TextEditingController(text: widget.site?.altitude?.toString() ?? '');
    _countryController = TextEditingController(text: widget.site?.country ?? '');
    _loadMapProviderPreference();
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
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildDetailsSection(),
              _buildMapSection(),
            ],
          ),
        ),
      ),
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saveChanges,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              TextFormField(
                controller: _nameController,
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
                      controller: _latitudeController,
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
                      controller: _longitudeController,
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
                controller: _altitudeController,
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
                controller: _countryController,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.flag),
                ),
                validator: (value) {
                  // Country is optional, no validation needed
                  return null;
                },
              ),
            ],
          ),
    );
  }

  Widget _buildMapSection() {
    return Column(
      children: [
        Container(
          height: 400,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildLocationMap(),
        ),
      ],
    );
  }

  void _saveChanges() {
    if (_formKey.currentState!.validate()) {
      final Site resultSite;
      if (widget.site != null) {
        // Edit mode: update existing site
        resultSite = widget.site!.copyWith(
          name: _nameController.text,
          latitude: double.parse(_latitudeController.text),
          longitude: double.parse(_longitudeController.text),
          altitude: _altitudeController.text.isNotEmpty 
              ? double.parse(_altitudeController.text) 
              : null,
          country: _countryController.text.isNotEmpty 
              ? _countryController.text 
              : null,
          customName: true, // Mark as custom since user edited it
        );
      } else {
        // Create mode: create new site
        resultSite = Site(
          name: _nameController.text,
          latitude: double.parse(_latitudeController.text),
          longitude: double.parse(_longitudeController.text),
          altitude: _altitudeController.text.isNotEmpty 
              ? double.parse(_altitudeController.text) 
              : null,
          country: _countryController.text.isNotEmpty 
              ? _countryController.text 
              : null,
          customName: true, // Mark as custom since user created it
        );
      }

      Navigator.of(context).pop(resultSite);
    }
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
        onTap: () => _onLaunchMarkerTap(launch),
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
                  color: Colors.black.withOpacity(0.3),
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

  /// Create a site marker with consistent styling
  Marker _buildSiteMarker({
    required double latitude,
    required double longitude,
    required String name,
    String? country,
    required Color color,
    required VoidCallback onTap,
  }) {
    final tooltipMessage = name.trim().isEmpty 
        ? 'Unknown Site${country != null ? '\n$country' : ''}'
        : '$name${country != null ? '\n$country' : ''}';
    
    return Marker(
      point: LatLng(latitude, longitude),
      width: _siteMarkerSize,
      height: _siteMarkerSize,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
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
              // Colored marker
              Icon(
                Icons.location_on,
                color: color,
                size: _siteMarkerIconSize,
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

  /// Build the local sites markers layer  
  MarkerLayer _buildLocalSitesLayer() {
    return MarkerLayer(
      markers: _localSites
          .where((site) => widget.site == null || site.id != widget.site!.id) // Exclude current site when editing
          .map((site) => _buildSiteMarker(
                latitude: site.latitude,
                longitude: site.longitude,
                name: site.name,
                country: site.country,
                color: Colors.blue,
                onTap: () => _onLocalSiteMarkerTap(site),
              ))
          .toList(),
    );
  }

  /// Build the API sites markers layer
  MarkerLayer _buildApiSitesLayer() {
    return MarkerLayer(
      markers: _apiSites
          .where((site) => 
              !_isDuplicateApiSite(site) && // Exclude duplicates with local sites
              (widget.site == null || 
               site.latitude != widget.site!.latitude || 
               site.longitude != widget.site!.longitude)) // Exclude current site when editing
          .map((site) => _buildSiteMarker(
                latitude: site.latitude,
                longitude: site.longitude,
                name: site.name,
                country: site.country,
                color: Colors.green,
                onTap: () => _onApiSiteMarkerTap(site),
              ))
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

  /// Build the current site marker layer (if editing)
  MarkerLayer? _buildCurrentSiteLayer() {
    if (widget.site == null) return null;
    
    return MarkerLayer(
      markers: [
        Marker(
          point: LatLng(widget.site!.latitude, widget.site!.longitude),
          width: _currentSiteMarkerSize,
          height: _currentSiteMarkerSize,
          child: Tooltip(
            message: '${widget.site!.name} (Current Site)${widget.site!.country != null ? '\n${widget.site!.country}' : ''}',
            child: Stack(
              alignment: Alignment.center,
              children: [
                // White outline
                const Icon(
                  Icons.location_on,
                  color: Colors.white,
                  size: _currentSiteMarkerSize,
                ),
                // Red marker
                const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: _siteMarkerSize,
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
    _handleSiteCreationAtPoint(point, null);
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

  /// Load all launches in the current viewport bounds
  Future<void> _loadAllLaunchesInBounds(LatLngBounds bounds) async {
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

  /// Handle tap on a local site marker
  Future<void> _onLocalSiteMarkerTap(Site localSite) async {
    // Only allow merging when editing an existing site
    if (widget.site == null || widget.site!.id == null) return;
    
    // Count how many flights will be affected
    final flightCount = await _databaseService.getFlightCountForSite(widget.site!.id!);
    
    if (!mounted) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge with Existing Site?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Do you want to reassign all flights from "${widget.site!.name}" to "${localSite.name}"?'),
            const SizedBox(height: 16),
            Text(
              'This will update $flightCount flight${flightCount == 1 ? '' : 's'}.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Note: The current site will be deleted after merging.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
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
        // Reassign all flights to the selected site
        await _databaseService.reassignFlights(widget.site!.id!, localSite.id!);
        
        // Delete the current site (it's no longer needed)
        await _databaseService.deleteSite(widget.site!.id!);
        
        if (mounted) {
          // Return the local site as the result (site was merged)
          Navigator.of(context).pop(localSite);
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

  /// Handle tap on a ParaglidingEarth API site marker
  Future<void> _onApiSiteMarkerTap(ParaglidingSite apiSite) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use ParaglidingEarth Data?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Replace current site data with:'),
            const SizedBox(height: 16),
            _buildInfoRow('Name:', apiSite.name),
            _buildInfoRow('Location:', '${apiSite.latitude.toStringAsFixed(6)}, ${apiSite.longitude.toStringAsFixed(6)}'),
            if (apiSite.altitude != null)
              _buildInfoRow('Altitude:', '${apiSite.altitude}m'),
            if (apiSite.country != null)
              _buildInfoRow('Country:', apiSite.country!),
            const SizedBox(height: 16),
            Text(
              'This will update the current site with data from ParaglidingEarth.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use This Data'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      // Update the form fields with API data
      setState(() {
        _nameController.text = apiSite.name;
        _latitudeController.text = apiSite.latitude.toString();
        _longitudeController.text = apiSite.longitude.toString();
        if (apiSite.altitude != null) {
          _altitudeController.text = apiSite.altitude.toString();
        }
        if (apiSite.country != null) {
          _countryController.text = apiSite.country!;
        }
      });
      
      // Show a snackbar to confirm the update
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Site data updated. Remember to save your changes.'),
        ),
      );
    }
  }

  /// Handle tap on a launch marker - delegates to unified site creation
  void _onLaunchMarkerTap(Flight launch) {
    final point = LatLng(launch.launchLatitude!, launch.launchLongitude!);
    LoggingService.debug('EditSiteScreen: Launch marker tapped at ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}');
    _handleSiteCreationAtPoint(point, launch);
  }

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
  Future<void> _handleSiteCreationAtPoint(LatLng point, Flight? sourceLaunch) async {
    // Find launches within specified radius
    final launchesNearby = _findLaunchesWithinRadius(point, _launchRadiusMeters);
    
    // Filter to only those closer to this point than to existing sites
    final eligibleLaunches = _filterLaunchesCloserToPoint(launchesNearby, point);
    
    
    await _showSiteCreationDialog(point, eligibleLaunches, sourceLaunch);
  }

  /// Show the site creation dialog
  Future<void> _showSiteCreationDialog(LatLng point, List<Flight> eligibleLaunches, Flight? sourceLaunch) async {
    final nameController = TextEditingController();
    final altitudeController = TextEditingController();
    final countryController = TextEditingController();
    
    // Pre-populate name and altitude if source launch exists
    if (sourceLaunch != null) {
      nameController.text = 'Launch ${sourceLaunch.date.toLocal().toString().split(' ')[0]}';
      if (sourceLaunch.launchAltitude != null) {
        altitudeController.text = sourceLaunch.launchAltitude!.toStringAsFixed(0);
      }
    } else {
      // No source launch - find nearest launch with altitude data
      final (nearestLaunch, distance) = _findNearestLaunchWithAltitude(point);
      if (nearestLaunch != null && nearestLaunch.launchAltitude != null) {
        altitudeController.text = nearestLaunch.launchAltitude!.toStringAsFixed(0);
      }
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(sourceLaunch != null ? 'Create Site from Launch' : 'Create New Site'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Location:', '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}'),
                if (sourceLaunch != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow('From flight:', '${sourceLaunch.date.toLocal().toString().split(' ')[0]} at ${sourceLaunch.launchTime}'),
                  if (sourceLaunch.launchAltitude != null)
                    _buildInfoRow('Launch altitude:', '${sourceLaunch.launchAltitude!.toStringAsFixed(0)}m'),
                ],
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
              
              if (eligibleLaunches.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Flight Reassignment',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${eligibleLaunches.length} flight${eligibleLaunches.length == 1 ? '' : 's'} within ${_launchRadiusMeters.toInt()}m will be reassigned to this new site:',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    itemCount: eligibleLaunches.length,
                    itemBuilder: (context, index) {
                      final launch = eligibleLaunches[index];
                      final distance = _calculateDistance(point, LatLng(launch.launchLatitude!, launch.launchLongitude!));
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${launch.launchSiteName ?? 'Unknown Site'}: ${launch.date.toLocal().toString().split(' ')[0]} at ${launch.launchTime}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: Text(
                          '${distance.toStringAsFixed(0)}m',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Text(
                  'No flights within ${_launchRadiusMeters.toInt()}m need reassignment.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: nameController.text.trim().isEmpty ? null : () => Navigator.of(context).pop(true),
              child: Text('Create Site${eligibleLaunches.isNotEmpty ? ' & Reassign Flights' : ''}'),
            ),
          ],
        ),
      ),
    );
    
    if (confirmed == true && mounted) {
      await _createSiteAndReassignFlights(
        point: point,
        name: nameController.text.trim(),
        altitude: altitudeController.text.trim().isEmpty ? null : double.tryParse(altitudeController.text.trim()),
        country: countryController.text.trim().isEmpty ? null : countryController.text.trim(),
        eligibleLaunches: eligibleLaunches,
      );
    }
    
    // Clean up controllers
    nameController.dispose();
    altitudeController.dispose();
    countryController.dispose();
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
      
      // Refresh the map data
      await _loadLaunchesForSite();
      if (_currentBounds != null) {
        await _loadSitesForBounds(_currentBounds!);
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
        _buildLocalSitesLayer(),
        _buildApiSitesLayer(),
        if (widget.actualLaunchCoordinates != null) _buildActualLaunchLayer()!,
        if (widget.site != null) _buildCurrentSiteLayer()!,
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
        // Debug cache test button (development only)
        if (kDebugMode)
          Positioned(
            top: 60,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.purple,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _testCacheFunction,
                icon: const Icon(Icons.bug_report, color: Colors.white, size: 16),
                tooltip: 'Test Cache',
              ),
            ),
          ),
        _buildLegend(),
        if (_buildLoadingIndicator() != null) _buildLoadingIndicator()!,
        // Debug cache overlay (development only)
        if (kDebugMode)
          Positioned(
            bottom: 60,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Cache: ${CacheUtils.getCacheInfo()}',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }

  /// Test cache functionality (debug mode only)
  void _testCacheFunction() {
    if (!kDebugMode) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test Map Cache'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current cache: ${CacheUtils.getCacheInfo()}'),
            const SizedBox(height: 16),
            const Text('To test cache functionality:\n'
                '1. Note current cache size\n'
                '2. Pan to new area and zoom\n'
                '3. Check cache size increased\n'
                '4. Pan back to original area\n'
                '5. Tiles should load instantly\n'
                '6. Turn on airplane mode\n'
                '7. Previously viewed areas should still load'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => CacheUtils.clearMapCache(),
            child: const Text('Clear Cache'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
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
