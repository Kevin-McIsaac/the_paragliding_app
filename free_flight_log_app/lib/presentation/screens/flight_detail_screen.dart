import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../../data/models/igc_file.dart';
import '../../data/repositories/flight_repository.dart';
import '../../data/repositories/site_repository.dart';
import '../../data/repositories/wing_repository.dart';
import '../../services/igc_import_service.dart';
import 'flight_track_screen.dart';

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
  final IgcImportService _igcService = IgcImportService();
  
  late Flight _flight;
  Site? _launchSite;
  Wing? _wing;
  bool _isLoading = true;
  bool _flightModified = false;
  
  // Inline editing state
  bool _isEditingNotes = false;
  bool _isSaving = false;
  late TextEditingController _notesController;
  
  // Map-related state
  MapController? _mapController;
  List<IgcPoint> _trackPoints = [];
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];
  bool _isTrackLoading = false;
  String? _trackError;

  @override
  void initState() {
    super.initState();
    _flight = widget.flight;
    _notesController = TextEditingController(text: _flight.notes ?? '');
    _loadFlightDetails();
    _loadTrackData();
  }

  Future<void> _loadFlightDetails() async {
    try {
      if (_flight.launchSiteId != null) {
        _launchSite = await _siteRepository.getSite(_flight.launchSiteId!);
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

  Future<void> _loadTrackData() async {
    if (_flight.trackLogPath == null) {
      return;
    }

    setState(() {
      _isTrackLoading = true;
      _trackError = null;
    });

    try {
      final trackPoints = await _igcService.getTrackPoints(_flight.trackLogPath!);
      
      if (trackPoints.isEmpty) {
        setState(() {
          _trackError = 'No track points found';
          _isTrackLoading = false;
        });
        return;
      }

      setState(() {
        _trackPoints = trackPoints;
        _isTrackLoading = false;
      });
      
      _createPolylines();
      _createMarkers();
      
    } catch (e) {
      setState(() {
        _trackError = 'Error loading track data: $e';
        _isTrackLoading = false;
      });
    }
  }

  void _createPolylines() {
    if (_trackPoints.isEmpty) return;

    final polylines = <Polyline>[];

    // Create main track polyline
    final trackCoordinates = _trackPoints
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();

    final trackPolyline = Polyline(
      points: trackCoordinates,
      color: Colors.blue,
      strokeWidth: 3.0,
    );
    polylines.add(trackPolyline);

    // Create straight line polyline if we have enough points
    if (_trackPoints.length >= 2 && _flight.straightDistance != null) {
      final launchPoint = LatLng(_trackPoints.first.latitude, _trackPoints.first.longitude);
      final landingPoint = LatLng(_trackPoints.last.latitude, _trackPoints.last.longitude);
      
      final straightLinePolyline = Polyline(
        points: [launchPoint, landingPoint],
        color: Colors.orange,
        strokeWidth: 4.0,
        isDotted: true,
      );
      polylines.add(straightLinePolyline);
    }

    setState(() {
      _polylines = polylines;
    });
  }

  void _createMarkers() {
    if (_trackPoints.isEmpty) {
      setState(() {
        _markers = [];
      });
      return;
    }

    final startPoint = _trackPoints.first;
    final endPoint = _trackPoints.last;
    
    // Find highest point
    final highestPoint = _trackPoints.reduce(
      (a, b) => a.gpsAltitude > b.gpsAltitude ? a : b
    );

    final markers = <Marker>[
      Marker(
        point: LatLng(startPoint.latitude, startPoint.longitude),
        child: _buildMarkerIcon(Colors.green, 'L'),
        width: 40,
        height: 40,
      ),
      Marker(
        point: LatLng(endPoint.latitude, endPoint.longitude),
        child: _buildMarkerIcon(Colors.red, 'X'),
        width: 40,
        height: 40,
      ),
      Marker(
        point: LatLng(highestPoint.latitude, highestPoint.longitude),
        child: _buildMarkerIcon(Colors.blue, 'H'),
        width: 40,
        height: 40,
      ),
    ];

    // Add straight distance marker at midpoint if showing straight line
    if (_trackPoints.length >= 2 && _flight.straightDistance != null) {
      final startPoint = _trackPoints.first;
      final endPoint = _trackPoints.last;
      final midLat = (startPoint.latitude + endPoint.latitude) / 2;
      final midLng = (startPoint.longitude + endPoint.longitude) / 2;
      
      markers.add(
        Marker(
          point: LatLng(midLat, midLng),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: Text(
              '${_flight.straightDistance!.toStringAsFixed(1)} km',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          width: 60,
          height: 20,
        ),
      );
    }

    setState(() {
      _markers = markers;
    });
  }

  Widget _buildMarkerIcon(Color color, String label) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
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

  /// Format time with timezone information
  String _formatTimeWithTimezone(String time, String? timezone) {
    if (timezone != null) {
      return '$time $timezone';
    }
    return time;
  }

  Future<void> _saveNotes() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final updatedFlight = Flight(
        id: _flight.id,
        date: _flight.date,
        launchTime: _flight.launchTime,
        landingTime: _flight.landingTime,
        duration: _flight.duration,
        launchSiteId: _flight.launchSiteId,
        landingLatitude: _flight.landingLatitude,
        landingLongitude: _flight.landingLongitude,
        landingAltitude: _flight.landingAltitude,
        landingDescription: _flight.landingDescription,
        wingId: _flight.wingId,
        maxAltitude: _flight.maxAltitude,
        maxClimbRate: _flight.maxClimbRate,
        maxSinkRate: _flight.maxSinkRate,
        maxClimbRate5Sec: _flight.maxClimbRate5Sec,
        maxSinkRate5Sec: _flight.maxSinkRate5Sec,
        distance: _flight.distance,
        straightDistance: _flight.straightDistance,
        trackLogPath: _flight.trackLogPath,
        source: _flight.source,
        timezone: _flight.timezone,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        createdAt: _flight.createdAt,
      );

      await _flightRepository.updateFlight(updatedFlight);
      
      setState(() {
        _flight = updatedFlight;
        _flightModified = true;
        _isEditingNotes = false;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notes updated successfully')),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving notes: $e')),
        );
      }
    }
  }

  void _cancelNotesEdit() {
    setState(() {
      _notesController.text = _flight.notes ?? '';
      _isEditingNotes = false;
    });
  }

  Future<void> _editDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _flight.date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    
    if (picked != null && picked != _flight.date) {
      await _updateFlightField('date', picked);
    }
  }

  Future<void> _editTime(bool isLaunchTime) async {
    final currentTime = isLaunchTime ? _flight.launchTime : _flight.landingTime;
    final timeParts = currentTime.split(':');
    final currentTimeOfDay = TimeOfDay(
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
    );

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: currentTimeOfDay,
    );
    
    if (picked != null) {
      final formattedTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      await _updateFlightField(isLaunchTime ? 'launchTime' : 'landingTime', formattedTime);
    }
  }

  Future<void> _updateFlightField(String field, dynamic value) async {
    setState(() {
      _isSaving = true;
    });

    try {
      // Calculate new duration if times changed
      int newDuration = _flight.duration;
      String newLaunchTime = _flight.launchTime;
      String newLandingTime = _flight.landingTime;
      DateTime newDate = _flight.date;

      if (field == 'date') {
        newDate = value as DateTime;
      } else if (field == 'launchTime') {
        newLaunchTime = value as String;
      } else if (field == 'landingTime') {
        newLandingTime = value as String;
      }

      // Recalculate duration if times changed
      if (field == 'launchTime' || field == 'landingTime') {
        newDuration = _calculateDurationFromTimes(newDate, newLaunchTime, newLandingTime);
      }

      final updatedFlight = Flight(
        id: _flight.id,
        date: newDate,
        launchTime: newLaunchTime,
        landingTime: newLandingTime,
        duration: newDuration,
        launchSiteId: _flight.launchSiteId,
        landingLatitude: _flight.landingLatitude,
        landingLongitude: _flight.landingLongitude,
        landingAltitude: _flight.landingAltitude,
        landingDescription: _flight.landingDescription,
        wingId: _flight.wingId,
        maxAltitude: _flight.maxAltitude,
        maxClimbRate: _flight.maxClimbRate,
        maxSinkRate: _flight.maxSinkRate,
        maxClimbRate5Sec: _flight.maxClimbRate5Sec,
        maxSinkRate5Sec: _flight.maxSinkRate5Sec,
        distance: _flight.distance,
        straightDistance: _flight.straightDistance,
        trackLogPath: _flight.trackLogPath,
        source: _flight.source,
        timezone: _flight.timezone,
        notes: _flight.notes,
        createdAt: _flight.createdAt,
      );

      await _flightRepository.updateFlight(updatedFlight);
      
      setState(() {
        _flight = updatedFlight;
        _flightModified = true;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${field == 'date' ? 'Date' : field == 'launchTime' ? 'Launch time' : 'Landing time'} updated successfully')),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating flight: $e')),
        );
      }
    }
  }

  int _calculateDurationFromTimes(DateTime date, String launchTime, String landingTime) {
    final launchParts = launchTime.split(':');
    final landingParts = landingTime.split(':');
    
    final launchDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(launchParts[0]),
      int.parse(launchParts[1]),
    );
    
    var landingDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(landingParts[0]),
      int.parse(landingParts[1]),
    );
    
    // Handle case where landing is next day
    if (landingDateTime.isBefore(launchDateTime)) {
      landingDateTime = landingDateTime.add(const Duration(days: 1));
    }
    
    return landingDateTime.difference(launchDateTime).inMinutes;
  }

  Future<void> _editSite(bool isLaunchSite) async {
    final sites = await _siteRepository.getAllSites();
    final currentSite = _launchSite;
    
    if (!mounted) return;
    
    final _SiteSelectionResult? result = await showDialog<_SiteSelectionResult>(
      context: context,
      builder: (context) => _SiteSelectionDialog(
        sites: sites,
        currentSite: currentSite,
        title: 'Select ${isLaunchSite ? 'Launch' : 'Landing'} Site',
      ),
    );

    // Only update if a selection was made (not cancelled)
    if (result != null && result.selectedSite != currentSite) {
      await _updateFlightSite(isLaunchSite, result.selectedSite);
    }
  }

  Future<void> _editWing() async {
    final wings = await _wingRepository.getAllWings();
    
    if (!mounted) return;
    
    final _WingSelectionResult? result = await showDialog<_WingSelectionResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Wing'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('No wing'),
                leading: Radio<Wing?>(
                  value: null,
                  groupValue: _wing,
                  onChanged: (Wing? value) {
                    Navigator.of(context).pop(_WingSelectionResult(value));
                  },
                ),
                onTap: () => Navigator.of(context).pop(_WingSelectionResult(null)),
              ),
              const Divider(),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: wings.length,
                  itemBuilder: (context, index) {
                    final wing = wings[index];
                    final displayName = '${wing.manufacturer ?? ''} ${wing.model ?? ''}'.trim();
                    return ListTile(
                      title: Text(displayName.isEmpty ? wing.name : displayName),
                      subtitle: wing.size != null ? Text('Size: ${wing.size}') : null,
                      leading: Radio<Wing>(
                        value: wing,
                        groupValue: _wing,
                        onChanged: (Wing? value) {
                          Navigator.of(context).pop(_WingSelectionResult(value));
                        },
                      ),
                      onTap: () => Navigator.of(context).pop(_WingSelectionResult(wing)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(), // Return null for cancellation
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    // Only update if a selection was made (not cancelled)
    if (result != null && result.selectedWing != _wing) {
      await _updateFlightWing(result.selectedWing);
    }
  }

  Future<void> _updateFlightSite(bool isLaunchSite, Site? newSite) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final updatedFlight = Flight(
        id: _flight.id,
        date: _flight.date,
        launchTime: _flight.launchTime,
        landingTime: _flight.landingTime,
        duration: _flight.duration,
        launchSiteId: isLaunchSite ? newSite?.id : _flight.launchSiteId,
        landingLatitude: _flight.landingLatitude,
        landingLongitude: _flight.landingLongitude,
        landingAltitude: _flight.landingAltitude,
        landingDescription: _flight.landingDescription,
        wingId: _flight.wingId,
        maxAltitude: _flight.maxAltitude,
        maxClimbRate: _flight.maxClimbRate,
        maxSinkRate: _flight.maxSinkRate,
        maxClimbRate5Sec: _flight.maxClimbRate5Sec,
        maxSinkRate5Sec: _flight.maxSinkRate5Sec,
        distance: _flight.distance,
        straightDistance: _flight.straightDistance,
        trackLogPath: _flight.trackLogPath,
        source: _flight.source,
        timezone: _flight.timezone,
        notes: _flight.notes,
        createdAt: _flight.createdAt,
      );

      await _flightRepository.updateFlight(updatedFlight);
      
      setState(() {
        _flight = updatedFlight;
        _flightModified = true;
        _isSaving = false;
        if (isLaunchSite) {
          _launchSite = newSite;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${isLaunchSite ? 'Launch' : 'Landing'} site updated successfully')),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating site: $e')),
        );
      }
    }
  }

  Future<void> _updateFlightWing(Wing? newWing) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final updatedFlight = Flight(
        id: _flight.id,
        date: _flight.date,
        launchTime: _flight.launchTime,
        landingTime: _flight.landingTime,
        duration: _flight.duration,
        launchSiteId: _flight.launchSiteId,
        landingLatitude: _flight.landingLatitude,
        landingLongitude: _flight.landingLongitude,
        landingAltitude: _flight.landingAltitude,
        landingDescription: _flight.landingDescription,
        wingId: newWing?.id,
        maxAltitude: _flight.maxAltitude,
        maxClimbRate: _flight.maxClimbRate,
        maxSinkRate: _flight.maxSinkRate,
        maxClimbRate5Sec: _flight.maxClimbRate5Sec,
        maxSinkRate5Sec: _flight.maxSinkRate5Sec,
        distance: _flight.distance,
        straightDistance: _flight.straightDistance,
        trackLogPath: _flight.trackLogPath,
        source: _flight.source,
        timezone: _flight.timezone,
        notes: _flight.notes,
        createdAt: _flight.createdAt,
      );

      await _flightRepository.updateFlight(updatedFlight);
      
      setState(() {
        _flight = updatedFlight;
        _flightModified = true;
        _isSaving = false;
        _wing = newWing;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wing updated successfully')),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating wing: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
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

                  // Flight Track with Statistics Card
                  if (_flight.trackLogPath != null && _flight.source == 'igc')
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Flight Track',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => FlightTrackScreen(flight: _flight),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.fullscreen),
                                  label: const Text('Full Screen'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (_trackPoints.isNotEmpty) _buildStatsBar(),
                            const SizedBox(height: 16),
                            _buildEmbeddedMap(),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Flight Details Card (Combined Overview, Sites, and Equipment)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Flight Details',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          _buildFlightDetailsContent(),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Notes Card (Full Width) - Always show if has notes or in edit mode
                  if (_flight.notes?.isNotEmpty == true || _isEditingNotes)
                    SizedBox(
                      width: double.infinity,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Notes',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  if (!_isEditingNotes)
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _isEditingNotes = true;
                                        });
                                      },
                                      icon: const Icon(Icons.edit, size: 20),
                                      tooltip: 'Edit notes',
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (_isEditingNotes) ...[
                                TextFormField(
                                  controller: _notesController,
                                  decoration: const InputDecoration(
                                    hintText: 'Enter flight notes...',
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLines: 4,
                                  autofocus: true,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: _isSaving ? null : _cancelNotesEdit,
                                      child: const Text('Cancel'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: _isSaving ? null : _saveNotes,
                                      child: _isSaving
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Text('Save'),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _isEditingNotes = true;
                                    });
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (_flight.notes!.isNotEmpty) ...[
                                          Text(
                                            _flight.notes!,
                                            style: Theme.of(context).textTheme.bodyMedium,
                                          ),
                                          if (_flight.source == 'igc' && _flight.trackLogPath != null) ...[
                                            const SizedBox(height: 12),
                                            const Divider(),
                                            const SizedBox(height: 8),
                                          ],
                                        ],
                                        if (_flight.source == 'igc' && _flight.trackLogPath != null) ...[
                                          Text(
                                            'IGC Source:',
                                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          SelectableText(
                                            _flight.trackLogPath!,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              fontFamily: 'monospace',
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  
                  // Add Notes Card (if no notes exist and not editing)
                  if (_flight.notes?.isEmpty != false && !_isEditingNotes)
                    SizedBox(
                      width: double.infinity,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Notes',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _isEditingNotes = true;
                                      });
                                    },
                                    icon: const Icon(Icons.add, size: 20),
                                    tooltip: 'Add notes',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              
                              // Show IGC source info if available, even without user notes
                              if (_flight.source == 'igc' && _flight.trackLogPath != null) ...[
                                Text(
                                  'IGC Source:',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  _flight.trackLogPath!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isEditingNotes = true;
                                  });
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Tap to add notes',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
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
            ),
    );
  }

  Widget _buildEmbeddedMap() {
    if (_isTrackLoading) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[100],
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading track data...'),
            ],
          ),
        ),
      );
    }

    if (_trackError != null) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[100],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Track Not Available',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _trackError!,
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_trackPoints.isEmpty) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[100],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No Track Data',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    _mapController ??= MapController();

    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _trackPoints.isNotEmpty
                ? LatLng(_trackPoints.first.latitude, _trackPoints.first.longitude)
                : const LatLng(0, 0),
            initialZoom: 12,
            onMapReady: () {
              _fitMapToBounds();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.free_flight_log_app',
            ),
            if (_polylines.isNotEmpty)
              PolylineLayer(
                polylines: _polylines,
              ),
            if (_markers.isNotEmpty)
              MarkerLayer(
                markers: _markers,
              ),
          ],
        ),
      ),
    );
  }

  void _fitMapToBounds() {
    if (_trackPoints.isEmpty || _mapController == null) return;

    final latitudes = _trackPoints.map((p) => p.latitude);
    final longitudes = _trackPoints.map((p) => p.longitude);
    
    final minLat = latitudes.reduce((a, b) => a < b ? a : b);
    final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
    final minLng = longitudes.reduce((a, b) => a < b ? a : b);
    final maxLng = longitudes.reduce((a, b) => a > b ? a : b);

    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    _mapController!.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(20.0)),
    );
  }

  Widget _buildStatsBar() {
    final duration = _formatDuration(_flight.duration);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'Duration',
                duration,
                Icons.access_time,
              ),
              _buildStatItem(
                'Track Distance',
                _flight.distance != null 
                    ? '${_flight.distance!.toStringAsFixed(1)} km'
                    : 'N/A',
                Icons.timeline,
              ),
              _buildStatItem(
                'Max Alt',
                _flight.maxAltitude != null
                    ? '${_flight.maxAltitude!.toInt()} m'
                    : 'N/A',
                Icons.height,
              ),
            ],
          ),
          if (_flight.maxClimbRate != null || _flight.maxSinkRate != null ||
              _flight.maxClimbRate5Sec != null || _flight.maxSinkRate5Sec != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                if (_flight.maxClimbRate != null)
                  _buildStatItem(
                    'Max Climb (Inst)',
                    '${_flight.maxClimbRate!.toStringAsFixed(1)} m/s',
                    Icons.trending_up,
                  ),
                if (_flight.maxSinkRate != null)
                  _buildStatItem(
                    'Max Sink (Inst)',
                    '${_flight.maxSinkRate!.toStringAsFixed(1)} m/s',
                    Icons.trending_down,
                  ),
                if (_flight.maxClimbRate5Sec != null)
                  _buildStatItem(
                    'Max Climb (15s)',
                    '${_flight.maxClimbRate5Sec!.toStringAsFixed(1)} m/s',
                    Icons.trending_up,
                  ),
                if (_flight.maxSinkRate5Sec != null)
                  _buildStatItem(
                    'Max Sink (15s)',
                    '${_flight.maxSinkRate5Sec!.toStringAsFixed(1)} m/s',
                    Icons.trending_down,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildFlightDetailsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Line 1: Date, Duration, and Equipment
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.calendar_today, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium,
                  children: [
                    WidgetSpan(
                      child: GestureDetector(
                        onTap: _isSaving ? null : _editDate,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Text(
                            _formatDate(_flight.date),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: ' for '),
                    TextSpan(text: _formatDuration(_flight.duration)),
                    if (_wing != null) ...[
                      const TextSpan(text: ' using '),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: _isSaving ? null : _editWing,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              '${_wing!.manufacturer ?? 'Unknown'} ${_wing!.model ?? 'Unknown'}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: _isSaving ? null : _editWing,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              ' (tap to set equipment)',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Line 2: Launch Time and Site
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.flight_takeoff, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium,
                  children: [
                    if (_launchSite != null) ...[
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: _isSaving ? null : () => _editSite(true),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              _launchSite!.name,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(
                        text: ' @ ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: _isSaving ? null : () => _editTime(true),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              _formatTimeWithTimezone(_flight.launchTime, _flight.timezone),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: _isSaving ? null : () => _editTime(true),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              _formatTimeWithTimezone(_flight.launchTime, _flight.timezone),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: _isSaving ? null : () => _editSite(true),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              ' (tap to set location)',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Line 3: Landing Time and Site
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.flight_land, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium,
                  children: [
                    if (_flight.landingLatitude != null && _flight.landingLongitude != null) ...[
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: _isSaving ? null : () => _editLandingLocation(),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              _flight.landingDescription ?? 
                              '${_flight.landingLatitude!.toStringAsFixed(4)}, ${_flight.landingLongitude!.toStringAsFixed(4)}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(
                        text: ' @ ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: _isSaving ? null : () => _editTime(false),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              _formatTimeWithTimezone(_flight.landingTime, _flight.timezone),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: _isSaving ? null : () => _editTime(false),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              _formatTimeWithTimezone(_flight.landingTime, _flight.timezone),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: _isSaving ? null : () => _editLandingLocation(),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              ' (tap to set location)',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editLandingLocation() async {
    final latController = TextEditingController(
      text: _flight.landingLatitude?.toString() ?? '',
    );
    final lonController = TextEditingController(
      text: _flight.landingLongitude?.toString() ?? '',
    );
    final altController = TextEditingController(
      text: _flight.landingAltitude?.toString() ?? '',
    );
    final descController = TextEditingController(
      text: _flight.landingDescription ?? '',
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Landing Location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: latController,
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lonController,
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: altController,
                decoration: const InputDecoration(
                  labelText: 'Altitude (m)',
                  border: OutlineInputBorder(),
                  hintText: 'Optional',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  hintText: 'Optional description (e.g., "Field near highway")',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final lat = double.tryParse(latController.text);
              final lon = double.tryParse(lonController.text);
              final alt = altController.text.isEmpty ? null : double.tryParse(altController.text);
              final desc = descController.text.isEmpty ? null : descController.text;
              
              if (lat == null || lon == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter valid latitude and longitude')),
                );
                return;
              }
              
              Navigator.of(context).pop({
                'latitude': lat,
                'longitude': lon,
                'altitude': alt,
                'description': desc,
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _updateLandingLocation(
        result['latitude'],
        result['longitude'],
        result['altitude'],
        result['description'],
      );
    }

    latController.dispose();
    lonController.dispose();
    altController.dispose();
    descController.dispose();
  }

  Future<void> _updateLandingLocation(
    double latitude,
    double longitude,
    double? altitude,
    String? description,
  ) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final updatedFlight = Flight(
        id: _flight.id,
        date: _flight.date,
        launchTime: _flight.launchTime,
        landingTime: _flight.landingTime,
        duration: _flight.duration,
        launchSiteId: _flight.launchSiteId,
        landingLatitude: latitude,
        landingLongitude: longitude,
        landingAltitude: altitude,
        landingDescription: description,
        wingId: _flight.wingId,
        maxAltitude: _flight.maxAltitude,
        maxClimbRate: _flight.maxClimbRate,
        maxSinkRate: _flight.maxSinkRate,
        maxClimbRate5Sec: _flight.maxClimbRate5Sec,
        maxSinkRate5Sec: _flight.maxSinkRate5Sec,
        distance: _flight.distance,
        straightDistance: _flight.straightDistance,
        trackLogPath: _flight.trackLogPath,
        source: _flight.source,
        timezone: _flight.timezone,
        notes: _flight.notes,
        createdAt: _flight.createdAt,
      );

      await _flightRepository.updateFlight(updatedFlight);
      
      setState(() {
        _flight = updatedFlight;
        _flightModified = true;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Landing location updated successfully')),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating landing location: $e')),
        );
      }
    }
  }

}

// Result wrapper to distinguish between cancellation and selection
class _SiteSelectionResult {
  final Site? selectedSite;
  
  const _SiteSelectionResult(this.selectedSite);
}

// Result wrapper for wing selection
class _WingSelectionResult {
  final Wing? selectedWing;
  
  const _WingSelectionResult(this.selectedWing);
}

// Custom dialog for site selection with search functionality
class _SiteSelectionDialog extends StatefulWidget {
  final List<Site> sites;
  final Site? currentSite;
  final String title;

  const _SiteSelectionDialog({
    required this.sites,
    required this.currentSite,
    required this.title,
  });

  @override
  State<_SiteSelectionDialog> createState() => _SiteSelectionDialogState();
}

class _SiteSelectionDialogState extends State<_SiteSelectionDialog> {
  late List<Site> _filteredSites;
  final TextEditingController _searchController = TextEditingController();
  Site? _selectedSite;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredSites = widget.sites;
    _selectedSite = widget.currentSite;
    
    // Sort sites alphabetically for easier browsing
    _filteredSites.sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterSites(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredSites = List.from(widget.sites)
          ..sort((a, b) => a.name.compareTo(b.name));
      } else {
        _filteredSites = widget.sites
            .where((site) => 
                site.name.toLowerCase().contains(_searchQuery) ||
                (site.country?.toLowerCase().contains(_searchQuery) ?? false))
            .toList()
          ..sort((a, b) {
            // Prioritize sites that start with the search query
            final aStarts = a.name.toLowerCase().startsWith(_searchQuery);
            final bStarts = b.name.toLowerCase().startsWith(_searchQuery);
            if (aStarts && !bStarts) return -1;
            if (!aStarts && bStarts) return 1;
            return a.name.compareTo(b.name);
          });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Group sites by country for better organization
    final Map<String, List<Site>> countryGroupedSites = {};
    for (final site in _filteredSites) {
      final country = site.country ?? 'Unknown Country';
      countryGroupedSites.putIfAbsent(country, () => []).add(site);
    }
    
    // Sort countries alphabetically, but keep "Unknown Country" at the end
    final sortedCountries = countryGroupedSites.keys.toList()..sort((a, b) {
      if (a == 'Unknown Country' && b != 'Unknown Country') return 1;
      if (a != 'Unknown Country' && b == 'Unknown Country') return -1;
      return a.compareTo(b);
    });
    
    // Sort sites within each country
    for (final country in sortedCountries) {
      countryGroupedSites[country]!.sort((a, b) => a.name.compareTo(b.name));
    }

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search sites or countries...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterSites('');
                      },
                    )
                  : null,
            ),
            onChanged: _filterSites,
            autofocus: true,
          ),
          if (_filteredSites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_filteredSites.length} site${_filteredSites.length != 1 ? 's' : ''} found',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400, // Fixed height for better UX
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // No site option
            ListTile(
              title: const Text('No site'),
              leading: Radio<Site?>(
                value: null,
                groupValue: _selectedSite,
                onChanged: (Site? value) {
                  setState(() {
                    _selectedSite = value;
                  });
                },
              ),
              onTap: () {
                setState(() {
                  _selectedSite = null;
                });
              },
              dense: true,
            ),
            const Divider(),
            // Site list
            Expanded(
              child: _filteredSites.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, 
                               size: 48, 
                               color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No sites match your search',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _searchQuery.isEmpty 
                          ? sortedCountries.fold<int>(0, (count, country) => 
                              count + 1 + countryGroupedSites[country]!.length) // Country header + sites
                          : _filteredSites.length,
                      itemBuilder: (context, index) {
                        if (_searchQuery.isNotEmpty) {
                          // When searching, show flat list
                          final site = _filteredSites[index];
                          return ListTile(
                            title: Text(
                              site.name,
                              style: site.name == 'Unknown'
                                  ? TextStyle(fontStyle: FontStyle.italic,
                                            color: Colors.grey[600])
                                  : null,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (site.altitude != null)
                                  Text('${site.altitude!.toInt()} m'),
                                if (site.country != null)
                                  Text(
                                    site.country!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                            leading: Radio<Site>(
                              value: site,
                              groupValue: _selectedSite,
                              onChanged: (Site? value) {
                                setState(() {
                                  _selectedSite = value;
                                });
                              },
                            ),
                            onTap: () {
                              setState(() {
                                _selectedSite = site;
                              });
                            },
                            dense: true,
                          );
                        } else {
                          // When not searching, show hierarchical structure
                          return _buildHierarchicalItem(index, countryGroupedSites);
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // Return null for cancellation
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_SiteSelectionResult(_selectedSite)),
          child: const Text('Select'),
        ),
      ],
    );
  }

  Widget _buildHierarchicalItem(int index, Map<String, List<Site>> countryGroupedSites) {
    // Calculate which item we're showing based on the hierarchical structure
    int currentIndex = 0;
    
    for (final country in countryGroupedSites.keys.toList()..sort((a, b) {
      if (a == 'Unknown Country' && b != 'Unknown Country') return 1;
      if (a != 'Unknown Country' && b == 'Unknown Country') return -1;
      return a.compareTo(b);
    })) {
      if (currentIndex == index) {
        // Country header
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          margin: const EdgeInsets.only(top: 8),
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          child: Text(
            country,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      }
      currentIndex++;
      
      final sites = countryGroupedSites[country]!;
      for (final site in sites) {
        if (currentIndex == index) {
          // Site item
          return Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ListTile(
              title: Text(
                site.name,
                style: site.name == 'Unknown'
                    ? TextStyle(fontStyle: FontStyle.italic,
                              color: Colors.grey[600])
                    : null,
              ),
              subtitle: site.altitude != null
                  ? Text('${site.altitude!.toInt()} m')
                  : null,
              leading: Radio<Site>(
                value: site,
                groupValue: _selectedSite,
                onChanged: (Site? value) {
                  setState(() {
                    _selectedSite = value;
                  });
                },
              ),
              onTap: () {
                setState(() {
                  _selectedSite = site;
                });
              },
              dense: true,
            ),
          );
        }
        currentIndex++;
      }
    }
    
    // Fallback (shouldn't reach here)
    return const SizedBox.shrink();
  }
}