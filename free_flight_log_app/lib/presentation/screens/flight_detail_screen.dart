import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../../data/repositories/flight_repository.dart';
import '../../data/repositories/site_repository.dart';
import '../../data/repositories/wing_repository.dart';
import 'edit_flight_screen.dart';
import 'flight_track_screen.dart';
import 'flight_track_canvas_screen.dart';
import 'dart:io' show Platform;

class FlightDetailScreen extends StatefulWidget {
  final Flight flight;

  const FlightDetailScreen({super.key, required this.flight});

  @override
  State<FlightDetailScreen> createState() => _FlightDetailScreenState();
}

class _FlightDetailScreenState extends State<FlightDetailScreen> {
  final FlightRepository _flightRepository = FlightRepository();
  final SiteRepository _siteRepository = SiteRepository();
  final WingRepository _wingRepository = WingRepository();
  
  late Flight _flight;
  Site? _launchSite;
  Site? _landingSite;
  Wing? _wing;
  bool _isLoading = true;
  bool _flightModified = false;

  @override
  void initState() {
    super.initState();
    _flight = widget.flight;
    _loadFlightDetails();
  }

  Future<void> _loadFlightDetails() async {
    try {
      if (_flight.launchSiteId != null) {
        _launchSite = await _siteRepository.getSite(_flight.launchSiteId!);
      }
      if (_flight.landingSiteId != null) {
        _landingSite = await _siteRepository.getSite(_flight.landingSiteId!);
      }
      if (_flight.wingId != null) {
        _wing = await _wingRepository.getWing(_flight.wingId!);
      }
    } catch (e) {
      print('Error loading flight details: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _editFlight() async {
    final updatedFlight = await Navigator.of(context).push<Flight>(
      MaterialPageRoute(
        builder: (context) => EditFlightScreen(flight: _flight),
      ),
    );

    if (updatedFlight != null) {
      setState(() {
        _flight = updatedFlight;
        _flightModified = true;
      });
      _loadFlightDetails();
    }
  }

  Future<void> _deleteFlight() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Flight'),
        content: const Text('Are you sure you want to delete this flight? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _flightRepository.deleteFlight(_flight.id!);
        if (mounted) {
          Navigator.of(context).pop(true); // Return true to indicate deletion
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting flight: $e')),
          );
        }
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEEE, MMMM d, y').format(date);
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flight ${_formatDate(_flight.date)}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_flightModified),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editFlight,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                _deleteFlight();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Flight', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Flight Overview Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Flight Overview',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  'Date',
                                  _formatDate(_flight.date),
                                  Icons.calendar_today,
                                ),
                              ),
                              Expanded(
                                child: _buildInfoTile(
                                  'Duration',
                                  _formatDuration(_flight.duration),
                                  Icons.access_time,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  'Launch',
                                  _flight.launchTime,
                                  Icons.flight_takeoff,
                                ),
                              ),
                              Expanded(
                                child: _buildInfoTile(
                                  'Landing',
                                  _flight.landingTime,
                                  Icons.flight_land,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Flight Statistics Card
                  if (_flight.maxAltitude != null || _flight.distance != null || 
                      _flight.maxClimbRate != null || _flight.maxSinkRate != null ||
                      _flight.maxClimbRate5Sec != null || _flight.maxSinkRate5Sec != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Flight Statistics',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                if (_flight.maxAltitude != null)
                                  Expanded(
                                    child: _buildInfoTile(
                                      'Max Altitude',
                                      '${_flight.maxAltitude!.toStringAsFixed(0)} m',
                                      Icons.height,
                                    ),
                                  ),
                                if (_flight.distance != null)
                                  Expanded(
                                    child: _buildInfoTile(
                                      'Ground Track',
                                      '${_flight.distance!.toStringAsFixed(1)} km',
                                      Icons.timeline,
                                    ),
                                  ),
                                if (_flight.straightDistance != null)
                                  Expanded(
                                    child: _buildInfoTile(
                                      'Straight Distance',
                                      '${_flight.straightDistance!.toStringAsFixed(1)} km',
                                      Icons.straighten,
                                    ),
                                  ),
                              ],
                            ),
                            if (_flight.maxClimbRate != null || _flight.maxSinkRate != null ||
                                _flight.maxClimbRate5Sec != null || _flight.maxSinkRate5Sec != null) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  if (_flight.maxClimbRate != null)
                                    Expanded(
                                      child: _buildInfoTile(
                                        'Max Climb',
                                        '${_flight.maxClimbRate!.toStringAsFixed(1)} m/s',
                                        Icons.trending_up,
                                      ),
                                    ),
                                  if (_flight.maxSinkRate != null)
                                    Expanded(
                                      child: _buildInfoTile(
                                        'Max Sink',
                                        '${_flight.maxSinkRate!.toStringAsFixed(1)} m/s',
                                        Icons.trending_down,
                                      ),
                                    ),
                                  if (_flight.maxClimbRate5Sec != null)
                                    Expanded(
                                      child: _buildInfoTile(
                                        'Max Climb (15s)',
                                        '${_flight.maxClimbRate5Sec!.toStringAsFixed(1)} m/s',
                                        Icons.trending_up,
                                      ),
                                    ),
                                  if (_flight.maxSinkRate5Sec != null)
                                    Expanded(
                                      child: _buildInfoTile(
                                        'Max Sink (15s)',
                                        '${_flight.maxSinkRate5Sec!.toStringAsFixed(1)} m/s',
                                        Icons.trending_down,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Sites Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sites',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          if (_launchSite != null)
                            ListTile(
                              leading: const Icon(Icons.flight_takeoff),
                              title: const Text('Launch Site'),
                              subtitle: Text(_launchSite!.name),
                              trailing: Text(
                                '${_launchSite!.latitude.toStringAsFixed(4)}, ${_launchSite!.longitude.toStringAsFixed(4)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          if (_landingSite != null)
                            ListTile(
                              leading: const Icon(Icons.flight_land),
                              title: const Text('Landing Site'),
                              subtitle: Text(_landingSite!.name),
                              trailing: Text(
                                '${_landingSite!.latitude.toStringAsFixed(4)}, ${_landingSite!.longitude.toStringAsFixed(4)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          if (_launchSite == null && _landingSite == null)
                            const ListTile(
                              leading: Icon(Icons.location_off),
                              title: Text('No site information'),
                              subtitle: Text('Sites were not recorded for this flight'),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Equipment Card
                  if (_wing != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Equipment',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: const Icon(Icons.paragliding),
                              title: Text(_wing!.manufacturer ?? 'Unknown'),
                              subtitle: Text(_wing!.model ?? 'Unknown'),
                              trailing: Text(_wing!.size ?? ''),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Notes Card
                  if (_flight.notes?.isNotEmpty == true)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notes',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            Text(_flight.notes!),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Track Log Card
                  if (_flight.trackLogPath != null && _flight.source == 'igc')
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Track Log',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: const Icon(Icons.show_chart),
                              title: const Text('View Flight Track'),
                              subtitle: const Text('GPS track from IGC file'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                // Show options for track visualization
                                showModalBottomSheet(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return SafeArea(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                            leading: const Icon(Icons.map),
                                            title: const Text('Google Maps View'),
                                            subtitle: const Text('Interactive map with satellite imagery'),
                                            onTap: () {
                                              Navigator.pop(context);
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (context) => FlightTrackScreen(flight: _flight),
                                                ),
                                              );
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(Icons.show_chart),
                                            title: const Text('Canvas Track View'),
                                            subtitle: const Text('Custom track visualization with altitude colors'),
                                            onTap: () {
                                              Navigator.pop(context);
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (context) => FlightTrackCanvasScreen(flight: _flight),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}