import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';
import '../widgets/flight_form_widget.dart';

class AddFlightScreen extends StatefulWidget {
  const AddFlightScreen({super.key});

  @override
  State<AddFlightScreen> createState() => _AddFlightScreenState();
}

class _AddFlightScreenState extends State<AddFlightScreen> {
  final DatabaseService _databaseService = DatabaseService.instance;
  
  List<Site> _sites = [];
  List<Wing> _wings = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final sites = await _databaseService.getAllSites();
      final wings = await _databaseService.getAllWings();
      
      if (mounted) {
        setState(() {
          _sites = sites;
          _wings = wings;
          _isLoading = false;
        });
      }
    } catch (e) {
      LoggingService.error('AddFlightScreen: Failed to load data', e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load data: $e';
        });
      }
    }
  }

  Future<void> _saveFlight(Flight flight) async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      LoggingService.debug('AddFlightScreen: Saving new flight');
      final flightId = await _databaseService.insertFlight(flight);
      LoggingService.info('AddFlightScreen: Flight saved with ID: $flightId');

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
      LoggingService.error('AddFlightScreen: Failed to save flight', e);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save flight: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage ?? 'Error saving flight'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Flight'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _errorMessage = null;
                            _isLoading = true;
                          });
                          _loadData();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : FlightFormWidget(
                  sites: _sites,
                  wings: _wings,
                  onSave: _saveFlight,
                  isLoading: _isSaving,
                ),
    );
  }
}