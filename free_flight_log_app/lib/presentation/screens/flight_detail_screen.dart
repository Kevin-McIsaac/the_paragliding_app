import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../../data/repositories/flight_repository.dart';
import '../../data/repositories/site_repository.dart';
import '../../data/repositories/wing_repository.dart';
import '../widgets/flight_track_widget.dart';
import '../widgets/flight_statistics_widget.dart';
import '../widgets/edit_site_dialog.dart';
import '../widgets/site_selection_dialog.dart';
import '../widgets/wing_selection_dialog.dart';
import 'flight_track_screen.dart';
import '../../core/dependency_injection.dart';

class FlightDetailScreen extends StatefulWidget {
  final Flight flight;

  const FlightDetailScreen({super.key, required this.flight});

  @override
  State<FlightDetailScreen> createState() => _FlightDetailScreenState();
}

class _FlightDetailScreenState extends State<FlightDetailScreen> with WidgetsBindingObserver {
  final FlightRepository _flightRepository = serviceLocator<FlightRepository>();
  final SiteRepository _siteRepository = serviceLocator<SiteRepository>();
  final WingRepository _wingRepository = serviceLocator<WingRepository>();
  
  late Flight _flight;
  Site? _launchSite;
  Wing? _wing;
  bool _isLoading = true;
  bool _flightModified = false;
  
  // Inline editing state
  bool _isEditingNotes = false;
  bool _isSaving = false;
  late TextEditingController _notesController;
  
  // Map refresh management
  int _mapRefreshKey = 0;

  @override
  void initState() {
    super.initState();
    _flight = widget.flight;
    _notesController = TextEditingController(text: _flight.notes ?? '');
    _loadFlightDetails();
    WidgetsBinding.instance.addObserver(this);
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
      // Error loading flight details - UI will show loading state ended
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App returned to foreground, refresh map to pick up any config changes
      setState(() {
        _mapRefreshKey++;
      });
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEEE, MMM d, yyyy').format(date);
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
      
      final result = await showDialog<SiteSelectionResult>(
        context: context,
        builder: (context) => SiteSelectionDialog(
          sites: sites,
          currentSite: isLaunchSite ? _launchSite : null,
          title: isLaunchSite ? 'Select Launch Site' : 'Select Landing Site',
        ),
      );

      if (result != null && mounted) {
        if (isLaunchSite) {
          await _updateLaunchSite(result.selectedSite);
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

  Future<void> _editCurrentSite() async {
    if (_launchSite == null) return;
    
    try {
      final editedSite = await showDialog<Site>(
        context: context,
        builder: (context) => EditSiteDialog(site: _launchSite!),
      );
      
      if (editedSite != null && mounted) {
        await _siteRepository.updateSite(editedSite);
        
        // Update the current flight's site
        setState(() {
          _launchSite = editedSite;
          _flightModified = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Site "${editedSite.name}" updated')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating site: $e')),
        );
      }
    }
  }

  Future<void> _editWing() async {
    try {
      final wings = await _wingRepository.getAllWings();
      
      if (!mounted) return;
      
      final result = await showDialog<WingSelectionResult>(
        context: context,
        builder: (context) => WingSelectionDialog(
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
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Only handle the pop if it was prevented (didPop = false)
        if (!didPop) {
          // Return true if flight was modified to trigger refresh in calling screen
          Navigator.of(context).pop(_flightModified);
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
                                    onPressed: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => FlightTrackScreen(flight: _flight),
                                        ),
                                      );
                                      // Returned from Flight Track screen, refresh map to pick up config changes
                                      setState(() {
                                        _mapRefreshKey++;
                                      });
                                    },
                                    icon: const Icon(Icons.fullscreen),
                                    label: const Text('Full Screen'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              FlightTrackWidget(
                                key: ValueKey(_mapRefreshKey),
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
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                      WidgetSpan(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: GestureDetector(
                            onTap: _isSaving ? null : _editCurrentSite,
                            child: Icon(
                              Icons.edit,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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

