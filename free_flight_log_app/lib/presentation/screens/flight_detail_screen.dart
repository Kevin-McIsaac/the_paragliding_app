import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../../data/repositories/flight_repository.dart';
import '../../data/repositories/site_repository.dart';
import '../../data/repositories/wing_repository.dart';
import '../widgets/flight_track_widget.dart';
import '../widgets/flight_statistics_widget.dart';
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
  
  late Flight _flight;
  Site? _launchSite;
  Wing? _wing;
  bool _isLoading = true;
  bool _flightModified = false;
  
  // Inline editing state
  bool _isEditingNotes = false;
  bool _isSaving = false;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _flight = widget.flight;
    _notesController = TextEditingController(text: _flight.notes ?? '');
    _loadFlightDetails();
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

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEEE, MMM d, yyyy').format(date);
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  String _formatTimeWithTimezone(String timeStr, String? timezone) {
    if (timezone != null && timezone.isNotEmpty) {
      return '$timeStr $timezone';
    }
    return timeStr;
  }

  // Inline editing methods
  Future<void> _editDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _flight.date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (selectedDate != null && selectedDate != _flight.date) {
      await _updateFlightDate(selectedDate);
    }
  }

  Future<void> _editTime(bool isLaunchTime) async {
    final currentTimeStr = isLaunchTime ? _flight.launchTime : _flight.landingTime;
    // Parse the time string (HH:mm format)
    final timeParts = currentTimeStr.split(':');
    final currentHour = int.parse(timeParts[0]);
    final currentMinute = int.parse(timeParts[1]);
    
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: currentHour, minute: currentMinute),
    );

    if (selectedTime != null) {
      final newTimeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
      
      if (isLaunchTime) {
        await _updateFlightTimes(newTimeStr, _flight.landingTime);
      } else {
        await _updateFlightTimes(_flight.launchTime, newTimeStr);
      }
    }
  }

  Future<void> _editSite(bool isLaunchSite) async {
    try {
      final sites = await _siteRepository.getAllSites();
      
      if (!mounted) return;
      
      final result = await showDialog<_SiteSelectionResult>(
        context: context,
        builder: (context) => _SiteSelectionDialog(
          sites: sites,
          currentSite: isLaunchSite ? _launchSite : null,
          title: isLaunchSite ? 'Select Launch Site' : 'Select Landing Site',
        ),
      );

      if (result != null && mounted) {
        if (result.isEditAction) {
          // Handle edit action - open edit dialog
          final editedSite = await showDialog<Site>(
            context: context,
            builder: (context) => _EditSiteDialog(site: result.selectedSite!),
          );
          
          if (editedSite != null && mounted) {
            try {
              await _siteRepository.updateSite(editedSite);
              
              // Update the current flight's site if it's the same site being edited
              if (isLaunchSite && _flight.launchSiteId == editedSite.id) {
                _launchSite = editedSite;
                setState(() {});
              }
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Site "${editedSite.name}" updated')),
                );
                
                // After editing, re-open site selection to allow further selection
                await _editSite(isLaunchSite);
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error updating site: $e')),
                );
              }
            }
          }
        } else {
          // Handle selection action
          if (isLaunchSite) {
            await _updateLaunchSite(result.selectedSite);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sites: $e')),
        );
      }
    }
  }

  Future<void> _editWing() async {
    try {
      final wings = await _wingRepository.getAllWings();
      
      if (!mounted) return;
      
      final result = await showDialog<_WingSelectionResult>(
        context: context,
        builder: (context) => _WingSelectionDialog(
          wings: wings,
          currentWing: _wing,
        ),
      );

      if (result != null && mounted) {
        await _updateWing(result.selectedWing);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading wings: $e')),
        );
      }
    }
  }

  // Update methods
  Future<void> _updateFlightDate(DateTime newDate) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final updatedFlight = Flight(
        id: _flight.id,
        date: newDate,
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
          const SnackBar(content: Text('Date updated successfully')),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating date: $e')),
        );
      }
    }
  }

  Future<void> _updateFlightTimes(String newLaunchTime, String newLandingTime) async {
    setState(() {
      _isSaving = true;
    });

    try {
      // Calculate new duration from time strings
      final launchParts = newLaunchTime.split(':');
      final landingParts = newLandingTime.split(':');
      
      final launchMinutes = int.parse(launchParts[0]) * 60 + int.parse(launchParts[1]);
      final landingMinutes = int.parse(landingParts[0]) * 60 + int.parse(landingParts[1]);
      
      int duration = landingMinutes - launchMinutes;
      
      // Handle midnight crossing (negative duration)
      if (duration < 0) {
        duration += 24 * 60; // Add 24 hours
      }

      final updatedFlight = Flight(
        id: _flight.id,
        date: _flight.date,
        launchTime: newLaunchTime,
        landingTime: newLandingTime,
        duration: duration,
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
          const SnackBar(content: Text('Times updated successfully')),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating times: $e')),
        );
      }
    }
  }

  Future<void> _updateLaunchSite(Site? newSite) async {
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
        launchSiteId: newSite?.id,
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
        _launchSite = newSite;
        _flightModified = true;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Launch site updated successfully')),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating launch site: $e')),
        );
      }
    }
  }

  Future<void> _updateWing(Wing? newWing) async {
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
        _wing = newWing;
        _flightModified = true;
        _isSaving = false;
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
          const SnackBar(content: Text('Notes saved successfully')),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _flightModified) {
          // Return the updated flight when popping
          Navigator.of(context).pop(_flight);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Flight Details'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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

                    // Flight Statistics Card (if track data available)
                    if (_flight.trackLogPath != null)
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
                              FlightStatisticsWidget(flight: _flight),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Flight Track Visualization (if available)
                    if (_flight.trackLogPath != null)
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
                              FlightTrackWidget(
                                flight: _flight,
                                config: FlightTrackConfig.embeddedWithControls(),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Notes Card (Notes editing or display)
                    if (_isEditingNotes)
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
                                    'Notes',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: _isSaving ? null : _cancelNotesEdit,
                                        child: const Text('Cancel'),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton(
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
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _notesController,
                                decoration: const InputDecoration(
                                  hintText: 'Enter your flight notes here...',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 4,
                                enabled: !_isSaving,
                                autofocus: true,
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // Notes Display Card (when not editing)
                      if (_flight.notes?.isNotEmpty == true)
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
                                      'Notes',
                                      style: Theme.of(context).textTheme.titleLarge,
                                    ),
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
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_flight.notes?.isNotEmpty == true) ...[
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
                              ],
                            ),
                          ),
                        )
                      
                      // Add Notes Card (if no notes exist and not editing)
                      else if (_flight.notes?.isEmpty != false && !_isEditingNotes)
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
                                        border: Border.all(
                                          color: Colors.grey[300]!,
                                          style: BorderStyle.solid,
                                        ),
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.add,
                                              color: Colors.grey[600],
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Tap to add flight notes',
                                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                color: Colors.grey[600],
                                                fontStyle: FontStyle.italic,
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
                          ),
                        ),
                    ],
                  ],
                ),
              ),
      ),
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
  final bool isEditAction;
  
  const _SiteSelectionResult(this.selectedSite, {this.isEditAction = false});
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
                            trailing: IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => Navigator.of(context).pop(
                                _SiteSelectionResult(site, isEditAction: true),
                              ),
                              tooltip: 'Edit site',
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
          onPressed: () => Navigator.of(context).pop(_SiteSelectionResult(_selectedSite, isEditAction: false)),
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
              trailing: IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => Navigator.of(context).pop(
                  _SiteSelectionResult(site, isEditAction: true),
                ),
                tooltip: 'Edit site',
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

// Custom wing selection dialog
class _WingSelectionDialog extends StatefulWidget {
  final List<Wing> wings;
  final Wing? currentWing;

  const _WingSelectionDialog({
    required this.wings,
    required this.currentWing,
  });

  @override
  State<_WingSelectionDialog> createState() => _WingSelectionDialogState();
}

class _WingSelectionDialogState extends State<_WingSelectionDialog> {
  late List<Wing> _filteredWings;
  final TextEditingController _searchController = TextEditingController();
  Wing? _selectedWing;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredWings = widget.wings;
    _selectedWing = widget.currentWing;
    
    // Sort wings by manufacturer and model for easier browsing
    _filteredWings.sort((a, b) {
      final aManufacturer = a.manufacturer ?? '';
      final bManufacturer = b.manufacturer ?? '';
      final manufacturerCompare = aManufacturer.compareTo(bManufacturer);
      if (manufacturerCompare != 0) return manufacturerCompare;
      
      final aModel = a.model ?? '';
      final bModel = b.model ?? '';
      return aModel.compareTo(bModel);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterWings(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredWings = List.from(widget.wings)
          ..sort((a, b) {
            final aManufacturer = a.manufacturer ?? '';
            final bManufacturer = b.manufacturer ?? '';
            final manufacturerCompare = aManufacturer.compareTo(bManufacturer);
            if (manufacturerCompare != 0) return manufacturerCompare;
            
            final aModel = a.model ?? '';
            final bModel = b.model ?? '';
            return aModel.compareTo(bModel);
          });
      } else {
        _filteredWings = widget.wings
            .where((wing) => 
                (wing.manufacturer?.toLowerCase().contains(_searchQuery) ?? false) ||
                (wing.model?.toLowerCase().contains(_searchQuery) ?? false))
            .toList()
          ..sort((a, b) {
            final aManufacturer = a.manufacturer ?? '';
            final bManufacturer = b.manufacturer ?? '';
            final manufacturerCompare = aManufacturer.compareTo(bManufacturer);
            if (manufacturerCompare != 0) return manufacturerCompare;
            
            final aModel = a.model ?? '';
            final bModel = b.model ?? '';
            return aModel.compareTo(bModel);
          });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select Wing'),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search manufacturer or model...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterWings('');
                      },
                    )
                  : null,
            ),
            onChanged: _filterWings,
            autofocus: true,
          ),
          if (_filteredWings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_filteredWings.length} wing${_filteredWings.length != 1 ? 's' : ''} found',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // No wing option
            ListTile(
              title: const Text('No wing'),
              leading: Radio<Wing?>(
                value: null,
                groupValue: _selectedWing,
                onChanged: (Wing? value) {
                  setState(() {
                    _selectedWing = value;
                  });
                },
              ),
              onTap: () {
                setState(() {
                  _selectedWing = null;
                });
              },
              dense: true,
            ),
            const Divider(),
            // Wing list
            Expanded(
              child: _filteredWings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, 
                               size: 48, 
                               color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No wings match your search',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredWings.length,
                      itemBuilder: (context, index) {
                        final wing = _filteredWings[index];
                        return ListTile(
                          title: Text('${wing.manufacturer ?? 'Unknown'} ${wing.model ?? 'Unknown'}'),
                          subtitle: wing.size != null
                              ? Text('Size: ${wing.size}')
                              : null,
                          leading: Radio<Wing>(
                            value: wing,
                            groupValue: _selectedWing,
                            onChanged: (Wing? value) {
                              setState(() {
                                _selectedWing = value;
                              });
                            },
                          ),
                          onTap: () {
                            setState(() {
                              _selectedWing = wing;
                            });
                          },
                          dense: true,
                        );
                      },
                    ),
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
          onPressed: () => Navigator.of(context).pop(_WingSelectionResult(_selectedWing)),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

// Site edit dialog - reused from manage sites screen
class _EditSiteDialog extends StatefulWidget {
  final Site site;

  const _EditSiteDialog({required this.site});

  @override
  State<_EditSiteDialog> createState() => _EditSiteDialogState();
}

class _EditSiteDialogState extends State<_EditSiteDialog> with SingleTickerProviderStateMixin {
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
                  userAgentPackageName: 'com.example.free_flight_log_app',
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
                // Attribution overlay for satellite tiles
                if (_showSatelliteView)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        'Powered by Esri',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.black87,
                        ),
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