import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../screens/edit_wing_screen.dart';

/// Shared form widget for adding and editing flights
class FlightFormWidget extends StatefulWidget {
  final Flight? initialFlight;
  final List<Site> sites;
  final List<Wing> wings;
  final Function(Flight) onSave;
  final Function()? onWingsChanged;
  final bool isLoading;
  final bool allowAddWing;

  const FlightFormWidget({
    super.key,
    this.initialFlight,
    required this.sites,
    required this.wings,
    required this.onSave,
    this.onWingsChanged,
    this.isLoading = false,
    this.allowAddWing = false,
  });

  @override
  State<FlightFormWidget> createState() => _FlightFormWidgetState();
}

class _FlightFormWidgetState extends State<FlightFormWidget> {
  final _formKey = GlobalKey<FormState>();
  
  // Form controllers
  final _notesController = TextEditingController();
  final _maxAltitudeController = TextEditingController();
  final _distanceController = TextEditingController();
  final _straightDistanceController = TextEditingController();
  
  // Form data
  late DateTime _selectedDate;
  late TimeOfDay _launchTime;
  late TimeOfDay _landingTime;
  Site? _selectedLaunchSite;
  Wing? _selectedWing;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    if (widget.initialFlight != null) {
      // Edit mode
      final flight = widget.initialFlight!;
      _selectedDate = flight.date;
      
      _launchTime = TimeOfDay(
        hour: int.parse(flight.launchTime.split(':')[0]),
        minute: int.parse(flight.launchTime.split(':')[1]),
      );
      
      _landingTime = TimeOfDay(
        hour: int.parse(flight.landingTime.split(':')[0]),
        minute: int.parse(flight.landingTime.split(':')[1]),
      );
      
      _notesController.text = flight.notes ?? '';
      _maxAltitudeController.text = flight.maxAltitude?.toString() ?? '';
      _distanceController.text = flight.distance?.toString() ?? '';
      _straightDistanceController.text = flight.straightDistance?.toString() ?? '';
      
      // Find selected site and wing
      if (flight.launchSiteId != null && widget.sites.isNotEmpty) {
        try {
          _selectedLaunchSite = widget.sites.firstWhere(
            (site) => site.id == flight.launchSiteId,
          );
        } catch (e) {
          _selectedLaunchSite = widget.sites.first;
        }
      }
      
      if (flight.wingId != null && widget.wings.isNotEmpty) {
        try {
          _selectedWing = widget.wings.firstWhere(
            (wing) => wing.id == flight.wingId,
          );
        } catch (e) {
          _selectedWing = widget.wings.first;
        }
      }
    } else {
      // Add mode
      _selectedDate = DateTime.now();
      _launchTime = TimeOfDay.now();
      _landingTime = TimeOfDay.now();
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _maxAltitudeController.dispose();
    _distanceController.dispose();
    _straightDistanceController.dispose();
    super.dispose();
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
    
    // Handle flights crossing midnight
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

    if (result == true && widget.onWingsChanged != null) {
      widget.onWingsChanged!();
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Handle "Add New Wing" case for edit mode
    final wingId = (_selectedWing?.name == '__ADD_NEW__') ? null : _selectedWing?.id;

    final flight = Flight(
      id: widget.initialFlight?.id,
      date: _selectedDate,
      launchTime: _formatTime(_launchTime),
      landingTime: _formatTime(_landingTime),
      duration: _calculateDuration(),
      launchSiteId: _selectedLaunchSite?.id,
      wingId: wingId,
      // Preserve IGC data for edit mode
      launchLatitude: widget.initialFlight?.launchLatitude,
      launchLongitude: widget.initialFlight?.launchLongitude,
      launchAltitude: widget.initialFlight?.launchAltitude,
      landingLatitude: widget.initialFlight?.landingLatitude,
      landingLongitude: widget.initialFlight?.landingLongitude,
      landingAltitude: widget.initialFlight?.landingAltitude,
      landingDescription: widget.initialFlight?.landingDescription,
      maxClimbRate: widget.initialFlight?.maxClimbRate,
      maxSinkRate: widget.initialFlight?.maxSinkRate,
      maxClimbRate5Sec: widget.initialFlight?.maxClimbRate5Sec,
      maxSinkRate5Sec: widget.initialFlight?.maxSinkRate5Sec,
      trackLogPath: widget.initialFlight?.trackLogPath,
      originalFilename: widget.initialFlight?.originalFilename,
      // Allow overriding these values for manual entries
      maxAltitude: _maxAltitudeController.text.isNotEmpty 
          ? double.tryParse(_maxAltitudeController.text)
          : widget.initialFlight?.maxAltitude,
      distance: _distanceController.text.isNotEmpty
          ? double.tryParse(_distanceController.text)
          : widget.initialFlight?.distance,
      straightDistance: _straightDistanceController.text.isNotEmpty
          ? double.tryParse(_straightDistanceController.text)
          : widget.initialFlight?.straightDistance,
      notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      source: widget.initialFlight?.source ?? 'manual',
      timezone: widget.initialFlight?.timezone,
    );

    widget.onSave(flight);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Date
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                ),
                child: Text(DateFormat('MMM dd, yyyy').format(_selectedDate)),
              ),
            ),
            const SizedBox(height: 16),
            
            // Times
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _selectLaunchTime,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Launch Time',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(_formatTime(_launchTime)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: _selectLandingTime,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Landing Time',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(_formatTime(_landingTime)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Duration (calculated)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Duration',
                border: OutlineInputBorder(),
              ),
              child: Text('${_calculateDuration()} minutes'),
            ),
            const SizedBox(height: 16),
            
            // Launch site dropdown
            if (widget.sites.isNotEmpty) ...[
              DropdownButtonFormField<Site>(
                decoration: const InputDecoration(
                  labelText: 'Launch Site',
                  border: OutlineInputBorder(),
                ),
                initialValue: _selectedLaunchSite,
                hint: const Text('Select launch site'),
                isExpanded: true,
                selectedItemBuilder: (BuildContext context) {
                  return widget.sites.map<Widget>((Site site) {
                    return Text(
                      site.name,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    );
                  }).toList();
                },
                items: widget.sites.map((site) {
                  return DropdownMenuItem<Site>(
                    value: site,
                    child: Text(
                      site.name,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                }).toList(),
                onChanged: (Site? value) {
                  setState(() {
                    _selectedLaunchSite = value;
                  });
                },
              ),
              const SizedBox(height: 16),
            ],
            
            // Wing dropdown
            if (widget.wings.isNotEmpty) ...[
              DropdownButtonFormField<Wing>(
                decoration: const InputDecoration(
                  labelText: 'Wing',
                  border: OutlineInputBorder(),
                ),
                initialValue: _selectedWing,
                hint: const Text('Select wing'),
                isExpanded: true,
                selectedItemBuilder: (BuildContext context) {
                  return [
                    ...widget.wings.map<Widget>((Wing wing) {
                      return Text(
                        wing.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      );
                    }),
                    if (widget.allowAddWing)
                      const Text(
                        '+ Add New Wing',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                  ];
                },
                items: [
                  // Regular wings
                  ...widget.wings.map((wing) {
                    return DropdownMenuItem<Wing>(
                      value: wing,
                      child: Text(
                        wing.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }),
                  // Add "Add New Wing" option if allowed
                  if (widget.allowAddWing)
                    DropdownMenuItem<Wing>(
                      value: Wing(id: -1, name: '__ADD_NEW__'),
                      child: const Text('+ Add New Wing'),
                    ),
                ],
                onChanged: (Wing? value) async {
                  if (value?.name == '__ADD_NEW__') {
                    await _addNewWing();
                  } else {
                    setState(() {
                      _selectedWing = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
            
            // Max altitude
            TextFormField(
              controller: _maxAltitudeController,
              decoration: const InputDecoration(
                labelText: 'Max Altitude (m)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Distance
            TextFormField(
              controller: _distanceController,
              decoration: const InputDecoration(
                labelText: 'Distance (km)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Straight distance
            TextFormField(
              controller: _straightDistanceController,
              decoration: const InputDecoration(
                labelText: 'Straight Distance (km)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            
            // Save button
            ElevatedButton(
              onPressed: widget.isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: widget.isLoading
                  ? const CircularProgressIndicator()
                  : Text(widget.initialFlight != null ? 'Update Flight' : 'Save Flight'),
            ),
          ],
        ),
      ),
    );
  }
}