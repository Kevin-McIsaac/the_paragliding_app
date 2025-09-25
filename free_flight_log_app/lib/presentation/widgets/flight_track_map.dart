import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../services/logging_service.dart';
import '../../utils/map_calculation_utils.dart';
import '../../utils/site_marker_utils.dart';
import '../../utils/ui_utils.dart';
import 'common/base_map_widget.dart';
import 'common/site_marker_layer.dart';

/// Specialized map widget for flight track display
/// Extends BaseMapWidget to reuse common functionality
class FlightTrackMap extends BaseMapWidget {
  final Flight flight;
  final List<IgcPoint> trackPoints;
  final List<IgcPoint> faiTrianglePoints;
  final ValueNotifier<int?> selectedTrackPointIndex;
  final double closingDistanceThreshold;
  final void Function(int?)? onTrackPointSelected;
  final Function(LatLng)? onMapTapped;
  final VoidCallback? onOpen3DView;

  const FlightTrackMap({
    super.key,
    required this.flight,
    required this.trackPoints,
    required this.faiTrianglePoints,
    required this.selectedTrackPointIndex,
    this.closingDistanceThreshold = 500.0,
    this.onTrackPointSelected,
    this.onMapTapped,
    this.onOpen3DView,
    super.height,
  });

  @override
  State<FlightTrackMap> createState() => _FlightTrackMapState();
}

class _FlightTrackMapState extends BaseMapState<FlightTrackMap> {
  static const double _mapPadding = 0.005;

  @override
  String get mapProviderKey => 'flight_track_2d_map_provider';

  @override
  String get legendExpandedKey => 'flight_track_2d_legend_expanded';

  @override
  String get mapContext => 'flight_track_2d';

  @override
  int get siteLimit => 30; // Smaller limit for performance with charts

  @override
  void initState() {
    super.initState();

    // Set initial center from track points
    if (widget.trackPoints.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        mapController.move(
          LatLng(widget.trackPoints.first.latitude, widget.trackPoints.first.longitude),
          13.0,
        );
      });
    }
  }

  @override
  void onMapReady() {
    super.onMapReady();
    _fitMapToBounds();
  }

  @override
  void onMapTap(TapPosition tapPosition, LatLng point) {
    // Call custom handler if provided
    widget.onMapTapped?.call(point);

    // Find and select closest track point
    if (widget.onTrackPointSelected != null && widget.trackPoints.isNotEmpty) {
      final closestIndex = _findClosestTrackPointByPosition(point);
      if (closestIndex != -1) {
        widget.onTrackPointSelected!(closestIndex);
      }
    }
  }

  int _findClosestTrackPointByPosition(LatLng position) {
    return MapCalculationUtils.findClosestTrackPoint(position, widget.trackPoints);
  }

  void _fitMapToBounds() {
    if (widget.trackPoints.isNotEmpty) {
      final bounds = _calculateBounds();
      LoggingService.action('FlightTrackMap', 'Fitting map to bounds', {
        'bounds': '${bounds.south.toStringAsFixed(4)},${bounds.west.toStringAsFixed(4)} - '
                  '${bounds.north.toStringAsFixed(4)},${bounds.east.toStringAsFixed(4)}'
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          mapController.fitCamera(CameraFit.bounds(bounds: bounds));
          setState(() {});
          loadSitesForBounds(bounds);
        }
      });
    }
  }

  LatLngBounds _calculateBounds() {
    return MapCalculationUtils.calculateBounds(widget.trackPoints, padding: _mapPadding);
  }

  @override
  List<Widget> buildAdditionalLayers() {
    return [
      // Colored track polylines
      PolylineLayer(
        polylines: [
          ..._buildColoredTrackLines(),
          ..._buildFaiTriangleLines(),
        ],
      ),

      // Closing distance circle for closed flights
      if (widget.flight.isClosed)
        CircleLayer(
          circles: _buildClosingDistanceCircle(),
        ),

      // Site markers using the new SiteMarkerLayer
      SiteMarkerLayer(
        sites: sites,
        showFlightCounts: true,
      ),

      // Flight endpoint markers (launch/landing)
      FlightEndpointMarkers(
        launchLatitude: widget.trackPoints.isNotEmpty ? widget.trackPoints.first.latitude : null,
        launchLongitude: widget.trackPoints.isNotEmpty ? widget.trackPoints.first.longitude : null,
        landingLatitude: widget.trackPoints.isNotEmpty ? widget.trackPoints.last.latitude : null,
        landingLongitude: widget.trackPoints.isNotEmpty ? widget.trackPoints.last.longitude : null,
        landingDescription: widget.flight.landingDescription,
      ),

      // Closing point marker
      if (widget.flight.isClosed && widget.flight.closingPointIndex != null)
        MarkerLayer(
          markers: _buildClosingPointMarker(),
        ),

      // Selected track point marker
      _buildTrackPointMarker(),

      // Triangle distance labels
      if (widget.flight.isClosed)
        MarkerLayer(
          markers: _buildTriangleDistanceMarkers(),
        ),
    ];
  }

  @override
  List<Widget> buildAdditionalLegendItems() {
    final items = <Widget>[];

    // Launch and landing markers
    items.addAll([
      const SizedBox(height: 4),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SiteMarkerUtils.buildLaunchMarkerIcon(
                  color: SiteMarkerUtils.launchColor,
                  size: 16,
                ),
                const Icon(
                  Icons.flight_takeoff,
                  color: Colors.white,
                  size: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Launch',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SiteMarkerUtils.buildLandingMarkerIcon(
                  color: SiteMarkerUtils.landingColor,
                  size: 16,
                ),
                const Icon(
                  Icons.flight_land,
                  color: Colors.white,
                  size: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Landing',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white),
          ),
        ],
      ),
    ]);

    // Closing point legend (only for closed flights)
    if (widget.flight.isClosed) {
      items.addAll([
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.purple,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.change_history,
                color: Colors.white,
                size: 8,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Close',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white),
            ),
          ],
        ),
      ]);
    }

    // Climb rate legend
    items.addAll([
      const SizedBox(height: 4),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(1.5))),
          const SizedBox(width: 8),
          const Text('Climb', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(1.5))),
          const SizedBox(width: 8),
          const Text('Sink (<1.5m/s)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(1.5))),
          const SizedBox(width: 8),
          const Text('Sink (>1.5m/s)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
        ],
      ),
    ]);

    return items;
  }

  @override
  List<Widget> buildAdditionalControls() {
    if (widget.onOpen3DView == null) return [];

    return [
      Container(
        decoration: BoxDecoration(
          color: const Color(0x80000000),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BaseMapState.standardElevatedShadow],
        ),
        child: AppTooltip(
          message: '3D Fly Through',
          child: InkWell(
            onTap: widget.onOpen3DView,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Icon(
                Icons.threed_rotation,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  // Track visualization methods
  List<Polyline> _buildColoredTrackLines() {
    if (widget.trackPoints.length < 2) return [];

    List<Polyline> lines = [];
    List<LatLng> currentSegment = [LatLng(widget.trackPoints[0].latitude, widget.trackPoints[0].longitude)];
    Color currentColor = Colors.blue;

    for (int i = 1; i < widget.trackPoints.length; i++) {
      final climbRate = MapCalculationUtils.calculateClimbRate(widget.trackPoints[i-1], widget.trackPoints[i]);
      final color = _getClimbRateColor(climbRate);

      if (color != currentColor && currentSegment.length > 1) {
        lines.add(Polyline(
          points: currentSegment,
          strokeWidth: 3.0,
          color: currentColor,
        ));
        currentSegment = [currentSegment.last];
        currentColor = color;
      }

      currentSegment.add(LatLng(widget.trackPoints[i].latitude, widget.trackPoints[i].longitude));
      currentColor = color;
    }

    if (currentSegment.length > 1) {
      lines.add(Polyline(
        points: currentSegment,
        strokeWidth: 3.0,
        color: currentColor,
      ));
    }

    return lines;
  }

  List<Polyline> _buildFaiTriangleLines() {
    if (!widget.flight.isClosed || widget.faiTrianglePoints.length != 3) return [];

    final p1 = LatLng(widget.faiTrianglePoints[0].latitude, widget.faiTrianglePoints[0].longitude);
    final p2 = LatLng(widget.faiTrianglePoints[1].latitude, widget.faiTrianglePoints[1].longitude);
    final p3 = LatLng(widget.faiTrianglePoints[2].latitude, widget.faiTrianglePoints[2].longitude);

    return [
      Polyline(
        points: [p1, p2],
        strokeWidth: 2.0,
        color: Colors.purple,
        pattern: StrokePattern.dashed(segments: const [5, 5]),
      ),
      Polyline(
        points: [p2, p3],
        strokeWidth: 2.0,
        color: Colors.purple,
        pattern: StrokePattern.dashed(segments: const [5, 5]),
      ),
      Polyline(
        points: [p3, p1],
        strokeWidth: 2.0,
        color: Colors.purple,
        pattern: StrokePattern.dashed(segments: const [5, 5]),
      ),
    ];
  }

  List<CircleMarker> _buildClosingDistanceCircle() {
    if (widget.trackPoints.isEmpty) return [];

    final launchPoint = widget.trackPoints.first;

    return [
      CircleMarker(
        point: LatLng(launchPoint.latitude, launchPoint.longitude),
        radius: widget.closingDistanceThreshold,
        useRadiusInMeter: true,
        color: Colors.transparent,
        borderColor: Colors.purple,
        borderStrokeWidth: 2.0,
      ),
    ];
  }

  List<Marker> _buildClosingPointMarker() {
    int closingIndex = widget.flight.closingPointIndex!;
    if (closingIndex < 0 || closingIndex >= widget.trackPoints.length) {
      return [];
    }

    return [
      Marker(
        point: LatLng(widget.trackPoints[closingIndex].latitude, widget.trackPoints[closingIndex].longitude),
        width: 24,
        height: 24,
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Colors.purple,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: const Icon(
            Icons.change_history,
            color: Colors.white,
            size: 14,
          ),
        ),
      ),
    ];
  }

  Widget _buildTrackPointMarker() {
    return ValueListenableBuilder<int?>(
      valueListenable: widget.selectedTrackPointIndex,
      builder: (context, selectedIndex, child) {
        if (selectedIndex == null || selectedIndex >= widget.trackPoints.length) {
          return const SizedBox.shrink();
        }

        final point = widget.trackPoints[selectedIndex];

        return MarkerLayer(
          markers: [
            Marker(
              point: LatLng(point.latitude, point.longitude),
              width: 12,
              height: 12,
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: SiteMarkerUtils.selectedPointColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Marker> _buildTriangleDistanceMarkers() {
    if (widget.faiTrianglePoints.length != 3) return [];

    final p1 = LatLng(widget.faiTrianglePoints[0].latitude, widget.faiTrianglePoints[0].longitude);
    final p2 = LatLng(widget.faiTrianglePoints[1].latitude, widget.faiTrianglePoints[1].longitude);
    final p3 = LatLng(widget.faiTrianglePoints[2].latitude, widget.faiTrianglePoints[2].longitude);

    final side1Distance = MapCalculationUtils.haversineDistanceKm(p1, p2);
    final side2Distance = MapCalculationUtils.haversineDistanceKm(p2, p3);
    final side3Distance = MapCalculationUtils.haversineDistanceKm(p3, p1);

    final midpoint1 = MapCalculationUtils.calculateMidpoint(p1, p2);
    final midpoint2 = MapCalculationUtils.calculateMidpoint(p2, p3);
    final midpoint3 = MapCalculationUtils.calculateMidpoint(p3, p1);

    return [
      _buildDistanceLabel(midpoint1, side1Distance),
      _buildDistanceLabel(midpoint2, side2Distance),
      _buildDistanceLabel(midpoint3, side3Distance),
    ];
  }

  Marker _buildDistanceLabel(LatLng point, double distanceKm) {
    return Marker(
      point: point,
      width: 60,
      height: 20,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(3),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Center(
          child: Text(
            '${distanceKm.toStringAsFixed(1)}km',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  // Helper methods
  Color _getClimbRateColor(double climbRate) {
    if (climbRate >= 0) return Colors.green;
    if (climbRate > -1.5) return Colors.blue;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return buildMap();
  }
}