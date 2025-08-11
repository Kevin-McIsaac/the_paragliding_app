import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';
import '../../services/logging_service.dart';
import 'cesium_3d_map_inappwebview.dart';
import 'cesium_3d_controls_widget.dart';
import 'cesium_3d_playback_widget.dart';
import 'cesium/cesium_webview_controller.dart';

/// Configuration for the 3D flight track visualization
class FlightTrack3DConfig {
  final bool embedded;
  final bool showControls;
  final bool showPlayback;
  final double? height;

  const FlightTrack3DConfig({
    this.embedded = false,
    this.showControls = true,
    this.showPlayback = true,
    this.height,
  });

  FlightTrack3DConfig.embedded()
      : embedded = true,
        showControls = true,
        showPlayback = true,
        height = 500;

  FlightTrack3DConfig.fullScreen()
      : embedded = false,
        showControls = true,
        showPlayback = true,
        height = null;
}

/// Widget to display a 3D visualization of a flight track using Cesium
class FlightTrack3DWidget extends StatefulWidget {
  final Flight flight;
  final FlightTrack3DConfig config;
  final bool showPlaybackPanel;
  
  const FlightTrack3DWidget({
    super.key,
    required this.flight,
    this.config = const FlightTrack3DConfig(),
    this.showPlaybackPanel = true,
  });

  @override
  State<FlightTrack3DWidget> createState() => _FlightTrack3DWidgetState();
}

class _FlightTrack3DWidgetState extends State<FlightTrack3DWidget> {
  final CesiumWebViewController _cesiumController = CesiumWebViewController();
  final IgcImportService _igcService = IgcImportService();
  
  List<IgcPoint> _trackPoints = [];
  List<double> _fifteenSecondRates = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrackData();
  }

  @override
  void dispose() {
    _cesiumController.dispose();
    super.dispose();
  }

  Future<void> _loadTrackData() async {
    if (widget.flight.trackLogPath == null) {
      setState(() {
        _error = 'No track data available for this flight';
        _isLoading = false;
      });
      return;
    }

    try {
      final trackPoints = await _igcService.getTrackPoints(widget.flight.trackLogPath!);
      
      if (trackPoints.isEmpty) {
        setState(() {
          _error = 'No track points found';
          _isLoading = false;
        });
        return;
      }

      // Calculate climb rates from IGC data
      final fifteenSecondRates = _calculateGPS15SecondClimbRates(trackPoints);

      setState(() {
        _trackPoints = trackPoints;
        _fifteenSecondRates = fifteenSecondRates;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _error = 'Error loading track data: $e';
        _isLoading = false;
      });
    }
  }

  /// Calculate 15-second averaged climb rates from GPS altitude
  List<double> _calculateGPS15SecondClimbRates(List<IgcPoint> points) {
    if (points.isEmpty) return [];
    
    final rates = <double>[];
    const windowSize = 15; // seconds
    
    for (int i = 0; i < points.length; i++) {
      // Find points approximately 15 seconds before and after
      int startIdx = i;
      int endIdx = i;
      
      // Look back up to windowSize/2 seconds
      for (int j = i - 1; j >= 0; j--) {
        final timeDiff = points[i].timestamp.difference(points[j].timestamp).inSeconds;
        if (timeDiff > windowSize ~/ 2) break;
        startIdx = j;
      }
      
      // Look forward up to windowSize/2 seconds
      for (int j = i + 1; j < points.length; j++) {
        final timeDiff = points[j].timestamp.difference(points[i].timestamp).inSeconds;
        if (timeDiff > windowSize ~/ 2) break;
        endIdx = j;
      }
      
      // Calculate average climb rate over the window
      if (endIdx > startIdx) {
        final altDiff = points[endIdx].gpsAltitude - points[startIdx].gpsAltitude;
        final timeDiff = points[endIdx].timestamp.difference(points[startIdx].timestamp).inSeconds;
        
        if (timeDiff > 0) {
          rates.add(altDiff / timeDiff);
        } else {
          rates.add(0.0);
        }
      } else {
        rates.add(0.0);
      }
    }
    
    return rates;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: widget.config.height ?? 500,
        decoration: BoxDecoration(
          borderRadius: widget.config.embedded ? BorderRadius.circular(8) : null,
          color: Colors.grey[100],
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading 3D track data...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        height: widget.config.height ?? 500,
        decoration: BoxDecoration(
          borderRadius: widget.config.embedded ? BorderRadius.circular(8) : null,
          color: Colors.grey[100],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                '3D Track Not Available',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Convert IgcPoints to format expected by Cesium widget
    final trackPointsForCesium = _trackPoints.map((point) => {
      'latitude': point.latitude,
      'longitude': point.longitude,
      'altitude': point.gpsAltitude,
      'timestamp': point.timestamp.toIso8601String(),
      'climbRate': _trackPoints.indexOf(point) < _fifteenSecondRates.length 
          ? _fifteenSecondRates[_trackPoints.indexOf(point)] 
          : 0.0,
    }).toList();

    // Build the 3D map widget
    Widget cesiumWidget = Cesium3DMapInAppWebView(
      initialLat: _trackPoints.isNotEmpty ? _trackPoints.first.latitude : 46.8182,
      initialLon: _trackPoints.isNotEmpty ? _trackPoints.first.longitude : 8.2275,
      initialAltitude: 10000, // 10km for better initial view
      trackPoints: trackPointsForCesium,
      onControllerCreated: (controller) {
        _cesiumController.setController(controller);
      },
    );

    // Add controls and playback if configured
    if (widget.config.showControls || widget.config.showPlayback) {
      cesiumWidget = Stack(
        children: [
          cesiumWidget,
          // Add Cesium controls at top left
          if (widget.config.showControls)
            Positioned(
              left: 8,
              top: 8,
              child: Cesium3DControlsWidget(
                controller: _cesiumController,
                onClose: () {
                  // Optional: Add close behavior if needed
                },
              ),
            ),
          // Add playback controls at bottom center
          if (widget.config.showPlayback && widget.showPlaybackPanel && trackPointsForCesium.isNotEmpty)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Cesium3DPlaybackWidget(
                  controller: _cesiumController,
                  trackPoints: trackPointsForCesium,
                  onClose: () {
                    // Optional: Add close behavior if needed
                  },
                ),
              ),
            ),
        ],
      );
    }

    // Apply container with height if embedded
    if (widget.config.embedded) {
      return Container(
        height: widget.config.height ?? 500,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: cesiumWidget,
      );
    }

    return cesiumWidget;
  }
}