import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../widgets/flight_track_3d_widget.dart';

class FlightTrack3DFullscreenScreen extends StatelessWidget {
  final Flight flight;

  const FlightTrack3DFullscreenScreen({
    super.key,
    required this.flight,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Flight Track'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: FlightTrack3DWidget(
        flight: flight,
        config: FlightTrack3DConfig.fullScreen(),
        showPlaybackPanel: true,
      ),
    );
  }
}