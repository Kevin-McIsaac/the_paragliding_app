import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';
import '../../services/igc_import_service.dart';
import '../../data/models/import_result.dart';
import '../../utils/import_error_helper.dart';
import '../../utils/preferences_helper.dart';
import '../widgets/flight_track_2d_widget.dart';
import '../widgets/flight_statistics_widget.dart';
import '../widgets/site_selection_dialog.dart';
import '../widgets/wing_selection_dialog.dart';

class FlightDetailScreen extends StatefulWidget {
  final Flight flight;

  const FlightDetailScreen({super.key, required this.flight});

  @override
  State<FlightDetailScreen> createState() => _FlightDetailScreenState();
}

class _FlightDetailScreenState extends State<FlightDetailScreen> with WidgetsBindingObserver {
  final DatabaseService _databaseService = DatabaseService.instance;
  final IgcImportService _igcImportService = IgcImportService.instance;
  
  late Flight _flight;
  Site? _launchSite;
  Wing? _wing;
  bool _isLoading = true;
  bool _flightModified = false;
  
  // Inline editing state
  bool _isEditingNotes = false;
  bool _isSaving = false;
  late TextEditingController _notesController;
  
  // Card expansion states
  bool _flightDetailsExpanded = true;
  bool _flightStatisticsExpanded = true;
  bool _flightTrackExpanded = true;
  bool _flightNotesExpanded = true;
  

  @override
  void initState() {
    super.initState();
    _flight = widget.flight;
    _notesController = TextEditingController(text: _flight.notes ?? '');
    _loadFlightDetails();
    _loadCardExpansionStates();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _loadFlightDetails() async {
    try {
      if (_flight.launchSiteId != null) {
        _launchSite = await _databaseService.getSite(_flight.launchSiteId!);
      }
      if (_flight.wingId != null) {
        _wing = await _databaseService.getWing(_flight.wingId!);
      }
    } catch (e) {
      // Error loading flight details - UI will show loading state ended
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCardExpansionStates() async {
    try {
      _flightDetailsExpanded = await PreferencesHelper.getFlightDetailsCardExpanded();
      _flightStatisticsExpanded = await PreferencesHelper.getFlightStatisticsCardExpanded();
      _flightTrackExpanded = await PreferencesHelper.getFlightTrackCardExpanded();
      _flightNotesExpanded = await PreferencesHelper.getFlightNotesCardExpanded();
      setState(() {
        // Update UI with loaded expansion states
      });
    } catch (e) {
      // Error loading preferences - use defaults
      LoggingService.error('Failed to load card expansion states', e);
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
        // Force rebuild to pick up any config changes
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

  String _getWingDisplayName(Wing wing) {
    List<String> parts = [];
    if (wing.manufacturer != null && wing.manufacturer!.isNotEmpty) {
      parts.add(wing.manufacturer!);
    }
    if (wing.model != null && wing.model!.isNotEmpty) {
      parts.add(wing.model!);
    }
    
    // If we have manufacturer/model, use them
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    
    // Otherwise fall back to name
    return wing.name;
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
      final sites = await _databaseService.getAllSites();
      
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


  Future<void> _editWing() async {
    try {
      final wings = await _databaseService.getAllWings();
      
      if (!mounted) return;
      
      final result = await showDialog<Wing?>(
        context: context,
        builder: (context) => WingSelectionDialog(
          wings: wings,
          currentWing: _wing,
        ),
      );

      if (result != null && mounted) {
        await _updateWing(result);
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

      await _databaseService.updateFlight(updatedFlight);
      
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

      await _databaseService.updateFlight(updatedFlight);
      
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

      await _databaseService.updateFlight(updatedFlight);
      
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

      await _databaseService.updateFlight(updatedFlight);
      
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

      await _databaseService.updateFlight(updatedFlight);
      
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

  Future<void> _showReimportConfirmation() async {
    final launchSiteName = _launchSite?.name ?? 'Unknown';
    final flightDate = _formatDate(_flight.date);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Reimport Flight?'),
          content: Text(
            'Reimport the flight from $launchSiteName on $flightDate?\n\n'
            'This will:\n'
            '• Recalculate all flight statistics\n'
            '• Recalculate triangle detection\n'
            '• Update launch/landing sites based on current database\n'
            '• Preserve your manual edits (date, times, sites, wing, notes)\n'
            '• Use the latest parsing algorithms\n\n'
            'Original IGC file: ${_flight.originalFilename ?? path.basename(_flight.trackLogPath!)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reimport'),
            ),
          ],
        );
      },
    );
    
    if (confirmed == true) {
      _reprocessFlight();
    }
  }

  Future<void> _reprocessFlight() async {
    setState(() {
      _isSaving = true;
    });

    try {
      LoggingService.info('FlightDetailScreen: Starting flight reprocessing for flight ${_flight.id}');
      
      // Check if IGC file exists
      final file = File(_flight.trackLogPath!);
      if (!await file.exists()) {
        throw Exception('File not found: The original IGC file could not be found at ${_flight.trackLogPath}');
      }
      
      // Use IGC import service to reprocess the flight
      final importResult = await _igcImportService.importIgcFileWithDuplicateHandling(
        _flight.trackLogPath!,
        replace: true,
      );
      
      if (importResult.type == ImportResultType.replaced) {
        LoggingService.info('FlightDetailScreen: Flight reprocessing completed successfully');
        
        // Refresh flight data from database
        final updatedFlight = await _databaseService.getFlight(_flight.id!);
        if (updatedFlight != null) {
          setState(() {
            _flight = updatedFlight;
            _flightModified = true;
            _isSaving = false;
          });
          
          // Reload flight details (sites, wing)
          await _loadFlightDetails();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Flight reimported successfully'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          throw Exception('Database error: Could not reload flight data after reprocessing. The import succeeded but the updated flight could not be retrieved from the database.');
        }
      } else {
        // Use the error message from the import result which should now be user-friendly
        throw Exception(importResult.errorMessage ?? 'Import failed with unknown error');
      }
    } catch (e) {
      LoggingService.error('FlightDetailScreen: Failed to reprocess flight', e);
      
      setState(() {
        _isSaving = false;
      });
      
      if (mounted) {
        final errorResult = ImportErrorHelper.processError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Failed to reprocess flight: ${ImportErrorHelper.getErrorTitle(errorResult.category)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  errorResult.message,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8), // Longer duration for detailed message
          ),
        );
      }
    }
  }

  Future<void> _showDeleteConfirmation() async {
    final launchSiteName = _launchSite?.name ?? 'Unknown';
    final flightDate = _formatDate(_flight.date);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Flight?'),
          content: Text(
            'Are you sure you want to delete the flight from $launchSiteName on $flightDate?\n\n'
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    
    if (confirmed == true) {
      _deleteFlight();
    }
  }

  Future<void> _deleteFlight() async {
    try {
      LoggingService.debug('FlightDetailScreen: Deleting flight ${_flight.id}');
      
      // Delete the flight
      await _databaseService.deleteFlight(_flight.id!);
      
      LoggingService.info('FlightDetailScreen: Flight ${_flight.id} deleted successfully');
      
      if (mounted) {
        // Show success toast
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flight deleted successfully'),
            duration: Duration(seconds: 2),
          ),
        );
        
        // Navigate back and signal that the list should be refreshed
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      LoggingService.error('FlightDetailScreen: Failed to delete flight', e);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete flight: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
          actions: [
            // Show reimport button only for IGC-sourced flights
            if (_flight.source == 'igc' && _flight.trackLogPath != null)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _showReimportConfirmation,
                tooltip: 'Reimport Flight',
              ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _showDeleteConfirmation,
              tooltip: 'Delete Flight',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Flight Details Card (Combined Overview, Sites, and Equipment)
                    Card(
                      child: ExpansionTile(
                        key: const PageStorageKey('flight_details'),
                        title: Text(
                          'Flight Details',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        initiallyExpanded: _flightDetailsExpanded,
                        onExpansionChanged: (expanded) {
                          _flightDetailsExpanded = expanded;
                          PreferencesHelper.setFlightDetailsCardExpanded(expanded);
                        },
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: _buildFlightDetailsContent(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Flight Statistics Card (if track data available)
                    if (_flight.trackLogPath != null)
                      Card(
                        child: ExpansionTile(
                          key: const PageStorageKey('flight_statistics'),
                          title: Text(
                            'Flight Statistics',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          initiallyExpanded: _flightStatisticsExpanded,
                          onExpansionChanged: (expanded) {
                            _flightStatisticsExpanded = expanded;
                            PreferencesHelper.setFlightStatisticsCardExpanded(expanded);
                          },
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: FlightStatisticsWidget(flight: _flight),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Flight Track Map (if track data available)
                    if (_flight.trackLogPath != null)
                      Card(
                        child: ExpansionTile(
                          key: const PageStorageKey('flight_track'),
                          title: Text(
                            'Flight Track',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          initiallyExpanded: _flightTrackExpanded,
                          onExpansionChanged: (expanded) {
                            _flightTrackExpanded = expanded;
                            PreferencesHelper.setFlightTrackCardExpanded(expanded);
                          },
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: FlightTrack2DWidget(
                                flight: _flight,
                                height: 732,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Hidden: Flight Track 3D Visualization (accessible via 2D map button)
                    // if (_flight.trackLogPath != null)
                    //   Card(
                    //     child: Padding(
                    //       padding: const EdgeInsets.all(16.0),
                    //       child: Column(
                    //         crossAxisAlignment: CrossAxisAlignment.start,
                    //         children: [
                    //           Text(
                    //             'Flight Track',
                    //             style: Theme.of(context).textTheme.titleLarge,
                    //           ),
                    //           const SizedBox(height: 16),
                    //           FlightTrack3DWidget(
                    //             flight: _flight,
                    //             config: FlightTrack3DConfig.embedded(),
                    //             showPlaybackPanel: true,
                    //           ),
                    //         ],
                    //       ),
                    //     ),
                    //   ),

                    const SizedBox(height: 16),

                    // Notes Card (Notes editing or display)
                    if (_isEditingNotes)
                      Card(
                        child: ExpansionTile(
                          key: const PageStorageKey('notes_edit'),
                          title: Text('Notes', style: Theme.of(context).textTheme.titleLarge),
                          initiallyExpanded: _flightNotesExpanded,
                          onExpansionChanged: (expanded) {
                            _flightNotesExpanded = expanded;
                            PreferencesHelper.setFlightNotesCardExpanded(expanded);
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
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
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: TextFormField(
                                controller: _notesController,
                                decoration: const InputDecoration(
                                  hintText: 'Enter your flight notes here...',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 4,
                                enabled: !_isSaving,
                                autofocus: true,
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      // Notes Display Card (when not editing)
                      if (_flight.notes?.isNotEmpty == true)
                        Card(
                          child: ExpansionTile(
                            key: const PageStorageKey('notes_display'),
                            title: Text('Notes', style: Theme.of(context).textTheme.titleLarge),
                            initiallyExpanded: _flightNotesExpanded,
                            onExpansionChanged: (expanded) {
                              _flightNotesExpanded = expanded;
                              PreferencesHelper.setFlightNotesCardExpanded(expanded);
                            },
                            trailing: IconButton(
                              onPressed: () {
                                setState(() {
                                  _isEditingNotes = true;
                                });
                              },
                              icon: const Icon(Icons.edit, size: 20),
                              tooltip: 'Edit notes',
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
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
                              ),
                            ],
                          ),
                        )
                      
                      // Add Notes Card (if no notes exist and not editing)
                      else if (_flight.notes?.isEmpty != false && !_isEditingNotes)
                        Card(
                          child: ExpansionTile(
                            key: const PageStorageKey('notes_add'),
                            title: Text('Notes', style: Theme.of(context).textTheme.titleLarge),
                            initiallyExpanded: _flightNotesExpanded,
                            onExpansionChanged: (expanded) {
                              _flightNotesExpanded = expanded;
                              PreferencesHelper.setFlightNotesCardExpanded(expanded);
                            },
                            trailing: IconButton(
                              onPressed: () {
                                setState(() {
                                  _isEditingNotes = true;
                                });
                              },
                              icon: const Icon(Icons.add, size: 20),
                              tooltip: 'Add notes',
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
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
                            ],
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
        // Line 1: Date
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.calendar_today, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  GestureDetector(
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
                  const Spacer(),
                ],
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
                              _formatTimeWithTimezone(_flight.effectiveLaunchTime, _flight.timezone),
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
                              _formatTimeWithTimezone(_flight.effectiveLaunchTime, _flight.timezone),
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
                              _formatTimeWithTimezone(_flight.effectiveLandingTime, _flight.timezone),
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
                              _formatTimeWithTimezone(_flight.effectiveLandingTime, _flight.timezone),
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
        const SizedBox(height: 12),
        
        // Line 4: Wing/Equipment
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.paragliding, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium,
                  children: [
                    if (_wing != null) ...[
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
                              _getWingDisplayName(_wing!),
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
                              '(tap to set equipment)',
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

      await _databaseService.updateFlight(updatedFlight);
      
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

