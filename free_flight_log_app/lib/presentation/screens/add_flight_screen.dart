import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/flight.dart';
import '../../data/repositories/flight_repository.dart';

class AddFlightScreen extends StatefulWidget {
  const AddFlightScreen({super.key});

  @override
  State<AddFlightScreen> createState() => _AddFlightScreenState();
}

class _AddFlightScreenState extends State<AddFlightScreen> {
  final _formKey = GlobalKey<FormState>();
  final FlightRepository _flightRepository = FlightRepository();
  
  // Form controllers
  final _notesController = TextEditingController();
  final _maxAltitudeController = TextEditingController();
  final _distanceController = TextEditingController();
  
  // Form data
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _launchTime = TimeOfDay.now();
  TimeOfDay _landingTime = TimeOfDay.now();
  bool _isLoading = false;

  @override
  void dispose() {
    _notesController.dispose();
    _maxAltitudeController.dispose();
    _distanceController.dispose();
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
    final launchMinutes = _launchTime.hour * 60 + _launchTime.minute;
    final landingMinutes = _landingTime.hour * 60 + _landingTime.minute;
    int duration = landingMinutes - launchMinutes;
    
    if (duration < 0) {
      duration += 24 * 60;
    }
    
    return duration;
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }

  Future<void> _saveFlight() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final flight = Flight(
        date: _selectedDate,
        launchTime: _launchTime.format(context),
        landingTime: _landingTime.format(context),
        duration: _calculateDuration(),
        maxAltitude: _maxAltitudeController.text.isNotEmpty 
            ? double.tryParse(_maxAltitudeController.text)
            : null,
        distance: _distanceController.text.isNotEmpty
            ? double.tryParse(_distanceController.text)
            : null,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        source: 'manual',
      );

      await _flightRepository.insertFlight(flight);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flight saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving flight: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = _calculateDuration();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Flight'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveFlight,
              child: const Text('SAVE'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Date Selection
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Flight Date'),
                subtitle: Text(DateFormat('EEEE, MMMM dd, yyyy').format(_selectedDate)),
                trailing: const Icon(Icons.edit),
                onTap: _selectDate,
              ),
            ),
            const SizedBox(height: 16),

            // Time Selection
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.flight_takeoff),
                      title: const Text('Launch Time'),
                      subtitle: Text(_launchTime.format(context)),
                      onTap: _selectLaunchTime,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.flight_land),
                      title: const Text('Landing Time'),
                      subtitle: Text(_landingTime.format(context)),
                      onTap: _selectLandingTime,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Duration Display
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('Flight Duration'),
                subtitle: Text(_formatDuration(duration)),
                trailing: duration < 5 
                    ? Icon(Icons.warning, color: Colors.orange)
                    : duration > 480 
                        ? Icon(Icons.warning, color: Colors.red)
                        : Icon(Icons.check, color: Colors.green),
              ),
            ),
            const SizedBox(height: 24),

            // Flight Data
            TextFormField(
              controller: _maxAltitudeController,
              decoration: const InputDecoration(
                labelText: 'Maximum Altitude (m)',
                hintText: 'e.g. 1200',
                prefixIcon: Icon(Icons.height),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final altitude = double.tryParse(value);
                  if (altitude == null) {
                    return 'Please enter a valid number';
                  }
                  if (altitude < 0 || altitude > 10000) {
                    return 'Altitude must be between 0 and 10,000m';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _distanceController,
              decoration: const InputDecoration(
                labelText: 'Distance (km)',
                hintText: 'e.g. 25.5',
                prefixIcon: Icon(Icons.straighten),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final distance = double.tryParse(value);
                  if (distance == null) {
                    return 'Please enter a valid number';
                  }
                  if (distance < 0 || distance > 1000) {
                    return 'Distance must be between 0 and 1,000km';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Weather conditions, thermals, landing notes...',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 32),

            // Save Button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveFlight,
              icon: _isLoading 
                  ? const SizedBox(
                      width: 20, 
                      height: 20, 
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_isLoading ? 'Saving...' : 'Save Flight'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}