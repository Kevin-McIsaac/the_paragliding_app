import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../data/models/flight.dart';
import '../../utils/date_time_utils.dart';
import '../../providers/flight_provider.dart';

class AddFlightScreen extends StatefulWidget {
  const AddFlightScreen({super.key});

  @override
  State<AddFlightScreen> createState() => _AddFlightScreenState();
}

class _AddFlightScreenState extends State<AddFlightScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Form controllers
  final _notesController = TextEditingController();
  final _maxAltitudeController = TextEditingController();
  final _distanceController = TextEditingController();
  final _straightDistanceController = TextEditingController();
  
  // Form data
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _launchTime = TimeOfDay.now();
  TimeOfDay _landingTime = TimeOfDay.now();

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
    final launchMinutes = _launchTime.hour * 60 + _launchTime.minute;
    final landingMinutes = _landingTime.hour * 60 + _landingTime.minute;
    int duration = landingMinutes - launchMinutes;
    
    if (duration < 0) {
      duration += 24 * 60;
    }
    
    return duration;
  }


  Future<void> _saveFlight() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

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
      straightDistance: _straightDistanceController.text.isNotEmpty
          ? double.tryParse(_straightDistanceController.text)
          : null,
      notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      source: 'manual',
      timezone: null, // Manual flights don't have timezone info
    );

    final success = await context.read<FlightProvider>().addFlight(flight);

    if (mounted) {
      if (success) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flight saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final errorMessage = context.read<FlightProvider>().errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage ?? 'Error saving flight'),
            backgroundColor: Colors.red,
          ),
        );
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
          Consumer<FlightProvider>(
            builder: (context, flightProvider, child) {
              if (flightProvider.isLoading) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              return TextButton(
                onPressed: _saveFlight,
                child: const Text('SAVE'),
              );
            },
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
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
                subtitle: Text(DateTimeUtils.formatDuration(duration)),
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
                labelText: 'Ground Track Distance (km)',
                hintText: 'e.g. 25.5',
                prefixIcon: Icon(Icons.timeline),
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
              controller: _straightDistanceController,
              decoration: const InputDecoration(
                labelText: 'Straight Distance (km)',
                hintText: 'e.g. 15.2',
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
            Consumer<FlightProvider>(
              builder: (context, flightProvider, child) {
                return ElevatedButton.icon(
                  onPressed: flightProvider.isLoading ? null : _saveFlight,
                  icon: flightProvider.isLoading 
                      ? const SizedBox(
                          width: 20, 
                          height: 20, 
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(flightProvider.isLoading ? 'Saving...' : 'Save Flight'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}