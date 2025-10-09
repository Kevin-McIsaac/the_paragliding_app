import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../widgets/flight_track_3d_widget.dart';

class FlightTrack3DScreen extends StatefulWidget {
  final Flight flight;

  const FlightTrack3DScreen({super.key, required this.flight});

  @override
  State<FlightTrack3DScreen> createState() => _FlightTrack3DScreenState();
}

class _FlightTrack3DScreenState extends State<FlightTrack3DScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Track 3D'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: FlightTrack3DWidget(
        flight: widget.flight,
        config: FlightTrack3DConfig.fullScreen(),
        showPlaybackPanel: true,
      ),
    );
  }
}