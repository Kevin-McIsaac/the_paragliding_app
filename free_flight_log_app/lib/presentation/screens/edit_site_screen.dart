import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../services/database_service.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';

class EditSiteScreen extends StatefulWidget {
  final Site site;
  final ({double latitude, double longitude})? actualLaunchCoordinates;

  const EditSiteScreen({
    super.key, 
    required this.site,
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
  bool _showSatelliteView = false;
  final _formKey = GlobalKey<FormState>();
  
  // Site markers state
  List<Site> _localSites = [];
  List<ParaglidingSite> _apiSites = [];
  Timer? _debounceTimer;
  LatLngBounds? _currentBounds;
  bool _isLoadingSites = false;
  bool _showApiSites = true;
  
  // Services
  final DatabaseService _databaseService = DatabaseService.instance;
  final ParaglidingEarthApi _apiService = ParaglidingEarthApi.instance;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.site.name);
    _latitudeController = TextEditingController(text: widget.site.latitude.toString());
    _longitudeController = TextEditingController(text: widget.site.longitude.toString());
    _altitudeController = TextEditingController(text: widget.site.altitude?.toString() ?? '');
    _countryController = TextEditingController(text: widget.site.country ?? '');
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
        title: const Text('Edit Site'),
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
      final updatedSite = widget.site.copyWith(
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

      Navigator.of(context).pop(updatedSite);
    }
  }

  void _toggleSatelliteView() {
    setState(() {
      _showSatelliteView = !_showSatelliteView;
    });
  }
  
  void _onMapReady() {
    // Initial load of sites
    if (_mapController != null) {
      final bounds = _mapController!.camera.visibleBounds;
      _currentBounds = bounds;
      _loadSitesForBounds(bounds);
    }
  }
  
  void _onMapEvent(MapEvent event) {
    // React to all movement and zoom end events to reload sites
    if (event is MapEventMoveEnd || 
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd ||
        event is MapEventScrollWheelZoom) {
      
      // Debug logging to verify events are captured
      LoggingService.debug('EditSiteScreen: Map event triggered: ${event.runtimeType}');
      
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _updateMapBounds();
      });
    }
  }
  
  void _updateMapBounds() {
    if (_mapController == null) return;
    
    final bounds = _mapController!.camera.visibleBounds;
    
    // Check if bounds have changed significantly
    if (_currentBounds != null) {
      // Use a simple threshold: ~100m in degrees (approximately 0.001 degrees)
      const threshold = 0.001;
      
      // Check if any corner of the bounds has moved more than the threshold
      if ((bounds.north - _currentBounds!.north).abs() < threshold &&
          (bounds.south - _currentBounds!.south).abs() < threshold &&
          (bounds.east - _currentBounds!.east).abs() < threshold &&
          (bounds.west - _currentBounds!.west).abs() < threshold) {
        LoggingService.debug('EditSiteScreen: Bounds change too small, skipping reload');
        return; // Bounds haven't changed significantly
      }
    }
    
    LoggingService.debug('EditSiteScreen: Bounds changed significantly, reloading sites');
    _currentBounds = bounds;
    _loadSitesForBounds(bounds);
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
      
      // Load API sites if enabled
      Future<List<ParaglidingSite>> apiSitesFuture;
      if (_showApiSites) {
        apiSitesFuture = _apiService.getSitesInBounds(
          bounds.north,
          bounds.south,
          bounds.east,
          bounds.west,
          limit: 50,
        );
      } else {
        apiSitesFuture = Future.value([]);
      }
      
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
        
        LoggingService.info('EditSiteScreen: Loaded ${_localSites.length} local sites and ${_apiSites.length} API sites');
        
        // Debug problematic site names
        for (var site in _apiSites) {
          if (site.name.trim().isEmpty) {
            LoggingService.warning('EditSiteScreen: API site with empty name at ${site.latitude}, ${site.longitude}');
          }
        }
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
  
  void _toggleApiSites() {
    setState(() {
      _showApiSites = !_showApiSites;
      if (_showApiSites && _currentBounds != null) {
        _loadSitesForBounds(_currentBounds!);
      } else {
        _apiSites = [];
      }
    });
  }

  /// Handle tap on a local site marker
  Future<void> _onLocalSiteMarkerTap(Site localSite) async {
    // Count how many flights will be affected
    final flightCount = await _databaseService.getFlightCountForSite(widget.site.id!);
    
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
            Text('Do you want to reassign all flights from "${widget.site.name}" to "${localSite.name}"?'),
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
        await _databaseService.reassignFlights(widget.site.id!, localSite.id!);
        
        // Delete the current site (it's no longer needed)
        await _databaseService.deleteSite(widget.site.id!);
        
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
    
    return Stack(
      children: [
        FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(widget.site.latitude, widget.site.longitude),
        initialZoom: 13.0,
        onMapReady: _onMapReady,
        onMapEvent: _onMapEvent,
      ),
      children: [
        // Base tile layer (OpenStreetMap or satellite)
        TileLayer(
          urlTemplate: _showSatelliteView
              ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
              : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: _showSatelliteView ? [] : const ['a', 'b', 'c'],
          userAgentPackageName: 'com.freeflightlog.free_flight_log_app',
        ),
        // Local sites (blue markers)
        MarkerLayer(
          markers: _localSites
              .where((site) => site.id != widget.site.id) // Exclude current site
              .map((site) => Marker(
                    point: LatLng(site.latitude, site.longitude),
                    width: 30,
                    height: 30,
                    child: GestureDetector(
                      onTap: () => _onLocalSiteMarkerTap(site),
                      child: Tooltip(
                        message: site.name.trim().isEmpty 
                            ? 'Unknown Site${site.country != null ? '\n${site.country}' : ''}'
                            : '${site.name}${site.country != null ? '\n${site.country}' : ''}',
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.blue,
                          size: 30,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        // API sites (green markers)
        MarkerLayer(
          markers: _apiSites
              .where((site) => 
                  site.latitude != widget.site.latitude || 
                  site.longitude != widget.site.longitude) // Exclude current site
              .map((site) => Marker(
                    point: LatLng(site.latitude, site.longitude),
                    width: 30,
                    height: 30,
                    child: GestureDetector(
                      onTap: () => _onApiSiteMarkerTap(site),
                      child: Tooltip(
                        message: site.name.trim().isEmpty 
                            ? 'Unknown Site${site.country != null ? '\n${site.country}' : ''}'
                            : '${site.name}${site.country != null ? '\n${site.country}' : ''}',
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.green,
                          size: 30,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        // Actual launch point from GPS track (yellow marker)
        if (widget.actualLaunchCoordinates != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  widget.actualLaunchCoordinates!.latitude,
                  widget.actualLaunchCoordinates!.longitude,
                ),
                width: 30,
                height: 30,
                child: Tooltip(
                  message: 'Actual Launch\n${widget.actualLaunchCoordinates!.latitude.toStringAsFixed(6)}, ${widget.actualLaunchCoordinates!.longitude.toStringAsFixed(6)}',
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.amber,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
        // Current site (red marker, on top)
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(widget.site.latitude, widget.site.longitude),
              width: 40,
              height: 40,
              child: Tooltip(
                message: '${widget.site.name} (Current Site)${widget.site.country != null ? '\n${widget.site.country}' : ''}',
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 40,
                ),
              ),
            ),
          ],
        ),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_showSatelliteView) ...[
                  Text(
                    'Powered by Esri',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.black87,
                    ),
                  ),
                  const Text(' | ', style: TextStyle(fontSize: 10, color: Colors.black54)),
                ],
                GestureDetector(
                  onTap: () async {
                    final uri = Uri.parse('https://www.openstreetmap.org/copyright');
                    try {
                      await launchUrl(uri, mode: LaunchMode.platformDefault);
                    } catch (e) {
                      LoggingService.error('EditSiteScreen: Could not launch URL', e);
                    }
                  },
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue[800],
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
        // Map controls
        Positioned(
        top: 8,
        right: 8,
        child: Column(
          children: [
            // Satellite toggle button
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
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
                onPressed: _toggleSatelliteView,
                icon: Icon(
                  _showSatelliteView ? Icons.map : Icons.satellite_alt,
                  size: 20,
                ),
                tooltip: _showSatelliteView ? 'Street View' : 'Satellite View',
              ),
            ),
            const SizedBox(height: 8),
            // API sites toggle
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
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
                onPressed: _toggleApiSites,
                icon: Icon(
                  Icons.public,
                  size: 20,
                  color: _showApiSites ? Colors.green : Colors.grey,
                ),
                tooltip: _showApiSites ? 'Hide ParaglidingEarth Sites' : 'Show ParaglidingEarth Sites',
              ),
            ),
          ],
        ),
      ),
      // Legend
      Positioned(
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_pin, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  const Text('Current Site', style: TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  const Text('Local Sites', style: TextStyle(fontSize: 12)),
                ],
              ),
              if (widget.actualLaunchCoordinates != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    const Text('Actual Launch', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
              if (_showApiSites) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Text('ParaglidingEarth', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      // Loading indicator
      if (_isLoadingSites)
        Positioned(
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
        ),
      ],
    );
  }
}