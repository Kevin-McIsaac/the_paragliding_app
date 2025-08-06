import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/site.dart';

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
      child: Container(
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
            '${widget.site.name}',
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
          ),
          children: [
            TileLayer(
              urlTemplate: _showSatelliteView 
                ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.freeflightlog.free_flight_log_app',
            ),
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
                          print('Could not launch URL: $e');
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
          // Satellite toggle button
          Positioned(
            top: 8,
            right: 8,
            child: Container(
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
          ),
        ],
      ),
    );
  }
}