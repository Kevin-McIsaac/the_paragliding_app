import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../widgets/flight_track_widget.dart';

class FlightTrackScreen extends StatefulWidget {
  final Flight flight;

  const FlightTrackScreen({super.key, required this.flight});

  @override
  State<FlightTrackScreen> createState() => _FlightTrackScreenState();
}

class _FlightTrackScreenState extends State<FlightTrackScreen> {
  void _onPointSelected(int pointIndex) {
    // Point selection is now handled by the shared widget
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Track'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: FlightTrackWidget(
        flight: widget.flight,
        config: FlightTrackConfig.fullScreen(),
        onPointSelected: _onPointSelected,
      ),
    );
  }
}