import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../../services/database_service.dart';
import 'edit_wing_screen.dart';

class EditFlightScreen extends StatefulWidget {
  final Flight flight;

  const EditFlightScreen({super.key, required this.flight});

  @override
  State<EditFlightScreen> createState() => _EditFlightScreenState();
}

class _EditFlightScreenState extends State<EditFlightScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _databaseService = DatabaseService.instance;

  late TextEditingController _notesController;

  late DateTime _selectedDate;
  late TimeOfDay _launchTime;
  late TimeOfDay _landingTime;
  
  List<Site> _sites = [];
  List<Wing> _wings = [];
  Site? _selectedLaunchSite;
  Site? _selectedLandingSite;
  Wing? _selectedWing;
  
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _loadSitesAndWings();
  }

  void _initializeData() {
    _selectedDate = widget.flight.date;
    
    _launchTime = TimeOfDay(
      hour: int.parse(widget.flight.launchTime.split(':')[0]),
      minute: int.parse(widget.flight.launchTime.split(':')[1]),
    );
    
    _landingTime = TimeOfDay(
      hour: int.parse(widget.flight.landingTime.split(':')[0]),
      minute: int.parse(widget.flight.landingTime.split(':')[1]),
    );

    _notesController = TextEditingController(text: widget.flight.notes ?? '');
  }

  Future<void> _loadSitesAndWings() async {
    try {
      final sites = await _databaseService.getAllSites();
      final wings = await _databaseService.getAllWings();
      
      setState(() {
        _sites = sites;
        _wings = wings;
        
        if (widget.flight.launchSiteId != null) {
          _selectedLaunchSite = sites.firstWhere(
            (site) => site.id == widget.flight.launchSiteId,
            orElse: () => sites.first,
          );
        }
        
        // Landing site selection removed - now using coordinates
        // Legacy flights may have had landing sites, but we now use coordinates
        
        if (widget.flight.wingId != null) {
          _selectedWing = wings.firstWhere(
            (wing) => wing.id == widget.flight.wingId,
            orElse: () => wings.first,
          );
        }
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectLaunchTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _launchTime,
    );
    if (picked != null && picked != _launchTime) {
      setState(() {
        _launchTime = picked;
      });
    }
  }

  Future<void> _selectLandingTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _landingTime,
    );
    if (picked != null && picked != _landingTime) {
      setState(() {
        _landingTime = picked;
      });
    }
  }

  int _calculateDuration() {
    final launchDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _launchTime.hour,
      _launchTime.minute,
    );
    
    var landingDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _landingTime.hour,
      _landingTime.minute,
    );
    
    // Handle case where landing is next day
    if (landingDateTime.isBefore(launchDateTime)) {
      landingDateTime = landingDateTime.add(const Duration(days: 1));
    }
    
    return landingDateTime.difference(launchDateTime).inMinutes;
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _addNewWing() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const EditWingScreen(),
      ),
    );

    if (result == true) {
      // Reload wings and select the newly created wing
      final oldWingsCount = _wings.length;
      await _loadSitesAndWings();
      
      // If we have more wings than before, select the newest one
      if (_wings.length > oldWingsCount) {
        // Get the wing with the highest ID (assuming auto-increment)
        final newestWing = _wings.reduce((a, b) => 
          (a.id ?? 0) > (b.id ?? 0) ? a : b
        );
        setState(() {
          _selectedWing = newestWing;
        });
      }
    }
  }

  Future<void> _saveFlight() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final updatedFlight = Flight(
        id: widget.flight.id,
        date: _selectedDate,
        launchTime: _formatTime(_launchTime),
        landingTime: _formatTime(_landingTime),
        duration: _calculateDuration(),
        launchSiteId: _selectedLaunchSite?.id,
        landingLatitude: widget.flight.landingLatitude,
        landingLongitude: widget.flight.landingLongitude,
        landingAltitude: widget.flight.landingAltitude,
        landingDescription: widget.flight.landingDescription,
        wingId: (_selectedWing?.name == '__ADD_NEW__') ? null : _selectedWing?.id,
        maxAltitude: widget.flight.maxAltitude,
        distance: widget.flight.distance,
        straightDistance: widget.flight.straightDistance,
        maxClimbRate: widget.flight.maxClimbRate,
        maxSinkRate: widget.flight.maxSinkRate,
        maxClimbRate5Sec: widget.flight.maxClimbRate5Sec,
        maxSinkRate5Sec: widget.flight.maxSinkRate5Sec,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        trackLogPath: widget.flight.trackLogPath,
        source: widget.flight.source,
        timezone: widget.flight.timezone,
      );

      await _databaseService.updateFlight(updatedFlight);

      if (mounted) {
        Navigator.of(context).pop(updatedFlight);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving flight: $e')),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
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
        title: const Text('Edit Flight'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveFlight,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date and Time Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date & Time',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: const Icon(Icons.calendar_today),
                              title: const Text('Flight Date'),
                              subtitle: Text(DateFormat('EEEE, MMMM d, y').format(_selectedDate)),
                              onTap: _selectDate,
                            ),
                            const Divider(),
                            Row(
                              children: [
                                Expanded(
                                  child: ListTile(
                                    leading: const Icon(Icons.flight_takeoff),
                                    title: const Text('Launch Time'),
                                    subtitle: Text(_formatTime(_launchTime)),
                                    onTap: _selectLaunchTime,
                                  ),
                                ),
                                Expanded(
                                  child: ListTile(
                                    leading: const Icon(Icons.flight_land),
                                    title: const Text('Landing Time'),
                                    subtitle: Text(_formatTime(_landingTime)),
                                    onTap: _selectLandingTime,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                'Duration: ${(_calculateDuration() / 60).floor()}h ${_calculateDuration() % 60}m',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Sites Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sites',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<Site>(
                              decoration: const InputDecoration(
                                labelText: 'Launch Site',
                                prefixIcon: Icon(Icons.flight_takeoff),
                              ),
                              value: _selectedLaunchSite,
                              items: [
                                const DropdownMenuItem<Site>(
                                  value: null,
                                  child: Text('No launch site'),
                                ),
                                ..._sites.map((site) => DropdownMenuItem<Site>(
                                  value: site,
                                  child: Text(site.name),
                                )),
                              ],
                              onChanged: (Site? value) {
                                setState(() {
                                  _selectedLaunchSite = value;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<Site>(
                              decoration: const InputDecoration(
                                labelText: 'Landing Site',
                                prefixIcon: Icon(Icons.flight_land),
                              ),
                              value: _selectedLandingSite,
                              items: [
                                const DropdownMenuItem<Site>(
                                  value: null,
                                  child: Text('No landing site'),
                                ),
                                ..._sites.map((site) => DropdownMenuItem<Site>(
                                  value: site,
                                  child: Text(site.name),
                                )),
                              ],
                              onChanged: (Site? value) {
                                setState(() {
                                  _selectedLandingSite = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Equipment Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Equipment',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<Wing>(
                              decoration: const InputDecoration(
                                labelText: 'Wing',
                                prefixIcon: Icon(Icons.paragliding),
                              ),
                              value: _selectedWing,
                              items: [
                                const DropdownMenuItem<Wing>(
                                  value: null,
                                  child: Text('No wing selected'),
                                ),
                                ..._wings.map((wing) => DropdownMenuItem<Wing>(
                                  value: wing,
                                  child: Text('${wing.manufacturer ?? ''} ${wing.model ?? ''}'.trim().isEmpty 
                                    ? wing.name 
                                    : '${wing.manufacturer ?? ''} ${wing.model ?? ''}'.trim()),
                                )),
                                DropdownMenuItem<Wing>(
                                  value: Wing(name: '__ADD_NEW__'), // Special marker wing
                                  child: const Row(
                                    children: [
                                      Icon(Icons.add, size: 16),
                                      SizedBox(width: 8),
                                      Text('Add New Wing'),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (Wing? value) async {
                                if (value?.name == '__ADD_NEW__') {
                                  // Handle add new wing
                                  await _addNewWing();
                                } else {
                                  setState(() {
                                    _selectedWing = value;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Notes Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notes',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _notesController,
                              decoration: const InputDecoration(
                                labelText: 'Flight notes',
                                prefixIcon: Icon(Icons.note),
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 4,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}