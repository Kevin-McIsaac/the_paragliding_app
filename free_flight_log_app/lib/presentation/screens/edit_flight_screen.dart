import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/wing.dart';
import '../../services/database_service.dart';
import '../widgets/flight_form_widget.dart';

class EditFlightScreen extends StatefulWidget {
  final Flight flight;

  const EditFlightScreen({super.key, required this.flight});

  @override
  State<EditFlightScreen> createState() => _EditFlightScreenState();
}

class _EditFlightScreenState extends State<EditFlightScreen> {
  final DatabaseService _databaseService = DatabaseService.instance;
  
  List<Site> _sites = [];
  List<Wing> _wings = [];
  bool _isLoading = true;
  bool _isSaving = false;

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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  void _onWingsChanged() async {
    // Reload wings after a new wing was added
    await _loadData();
  }

  Future<void> _saveFlight(Flight flight) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _databaseService.updateFlight(flight);

      if (mounted) {
        Navigator.of(context).pop(flight);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving flight: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Flight'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FlightFormWidget(
              initialFlight: widget.flight,
              sites: _sites,
              wings: _wings,
              onSave: _saveFlight,
              onWingsChanged: _onWingsChanged,
              isLoading: _isSaving,
              allowAddWing: true,
            ),
    );
  }
}