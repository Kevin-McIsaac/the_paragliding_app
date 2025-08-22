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

class EditSiteDialog extends StatefulWidget {
  final Site site;

  const EditSiteDialog({super.key, required this.site});

  @override
  State<EditSiteDialog> createState() => _EditSiteDialogState();
}

class _EditSiteDialogState extends State<EditSiteDialog> with SingleTickerProviderStateMixin {
  late TextEditingController _nameController;
  late TextEditingController _latitudeController;
  late TextEditingController _longitudeController;
  late TextEditingController _altitudeController;
  late TextEditingController _countryController;
  late TabController _tabController;
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
    _tabController = TabController(length: 2, vsync: this);
    _nameController = TextEditingController(text: widget.site.name);
    _latitudeController = TextEditingController(text: widget.site.latitude.toString());
    _longitudeController = TextEditingController(text: widget.site.longitude.toString());
    _altitudeController = TextEditingController(
      text: widget.site.altitude?.toString() ?? '',
    );
    _countryController = TextEditingController(
      text: widget.site.country ?? '',
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabController.dispose();
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _altitudeController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header with title and close button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'Edit Site',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // Tab bar
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(
                  icon: Icon(Icons.edit),
                  text: 'Details',
                ),
                Tab(
                  icon: Icon(Icons.map),
                  text: 'Location',
                ),
              ],
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDetailsTab(),
                  _buildLocationTab(),
                ],
              ),
            ),
            // Action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Site Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Site name is required';
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
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        final lat = double.tryParse(value.trim());
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
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        final lon = double.tryParse(value.trim());
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
                  labelText: 'Altitude (m)',
                  border: OutlineInputBorder(),
                  hintText: 'Optional',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final alt = double.tryParse(value.trim());
                    if (alt == null) {
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
                  hintText: 'Optional',
                ),
                validator: (value) {
                  // Country is optional, no validation needed
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            widget.site.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.site.latitude.toStringAsFixed(6)}, ${widget.site.longitude.toStringAsFixed(6)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _buildLocationMap(),
          ),
        ],
      ),
    );
  }

  void _saveChanges() {
    if (_formKey.currentState!.validate()) {
      final updatedSite = widget.site.copyWith(
        name: _nameController.text.trim(),
        latitude: double.parse(_latitudeController.text.trim()),
        longitude: double.parse(_longitudeController.text.trim()),
        altitude: _altitudeController.text.trim().isEmpty
            ? null
            : double.parse(_altitudeController.text.trim()),
        country: _countryController.text.trim().isEmpty
            ? null
            : _countryController.text.trim(),
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
  
  void _onMapEvent(MapEvent event) {
    // Only react to movement end events to avoid excessive API calls
    if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _updateMapBounds();
      });
    }
  }
  
  void _updateMapBounds() {
    if (_mapController == null) return;
    
    final bounds = _mapController!.camera.visibleBounds;
    
    // Check if bounds changed significantly (>10%)
    if (_currentBounds != null) {
      final latChange = (bounds.north - _currentBounds!.north).abs() / 
                        (_currentBounds!.north - _currentBounds!.south).abs();
      final lngChange = (bounds.east - _currentBounds!.east).abs() / 
                        (_currentBounds!.east - _currentBounds!.west).abs();
      
      if (latChange < 0.1 && lngChange < 0.1) {
        return; // Bounds haven't changed significantly
      }
    }
    
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
        
        LoggingService.info('EditSiteDialog: Loaded ${_localSites.length} local sites and ${_apiSites.length} API sites');
      }
    } catch (e) {
      LoggingService.error('EditSiteDialog: Error loading sites', e);
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

  Widget _buildLocationMap() {
    _mapController ??= MapController();
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(widget.site.latitude, widget.site.longitude),
            initialZoom: 14.0,
            minZoom: 5.0,
            maxZoom: 18.0,
            onMapReady: () {
              // Load sites for initial bounds
              Future.delayed(const Duration(milliseconds: 100), () {
                _updateMapBounds();
              });
            },
            onMapEvent: _onMapEvent,
          ),
          children: [
            TileLayer(
              urlTemplate: _showSatelliteView 
                ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.freeflightlog.free_flight_log_app',
            ),
            // Local database sites (blue markers)
            MarkerLayer(
              markers: _localSites
                  .where((site) => 
                      site.latitude != widget.site.latitude || 
                      site.longitude != widget.site.longitude) // Exclude current site
                  .map((site) => Marker(
                        point: LatLng(site.latitude, site.longitude),
                        width: 30,
                        height: 30,
                        child: Tooltip(
                          message: '${site.name}${site.country != null ? '\n${site.country}' : ''}',
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.blue,
                            size: 30,
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
                        child: Tooltip(
                          message: '${site.name}${site.country != null ? '\n${site.country}' : ''}',
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.green,
                            size: 30,
                          ),
                        ),
                      ))
                  .toList(),
            ),
            // Current site (red marker, on top)
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(widget.site.latitude, widget.site.longitude),
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_pin,
                    color: Colors.red,
                    size: 40,
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
                          LoggingService.error('EditSiteDialog: Could not launch URL', e);
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
                      const Icon(Icons.location_pin, color: Colors.red, size: 16),
                      const SizedBox(width: 4),
                      Text('Current Site', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, color: Colors.blue, size: 16),
                      const SizedBox(width: 4),
                      Text('Local Sites', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                  if (_showApiSites) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on, color: Colors.green, size: 16),
                        const SizedBox(width: 4),
                        Text('ParaglidingEarth', style: TextStyle(fontSize: 11)),
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
              bottom: 60,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Loading sites...', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}