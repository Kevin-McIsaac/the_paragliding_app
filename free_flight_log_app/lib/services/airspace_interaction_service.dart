import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/map_calculation_utils.dart';
import 'airspace_identification_service.dart';
import 'airspace_geojson_service.dart';
import 'logging_service.dart';

/// Service for managing airspace interaction state and rendering on maps
/// Extracts airspace-specific logic from BaseMapWidget for better separation of concerns
class AirspaceInteractionService {
  static final instance = AirspaceInteractionService._();
  AirspaceInteractionService._();

  // Current interaction state
  final _state = ValueNotifier<AirspaceInteractionState?>(null);
  ValueListenable<AirspaceInteractionState?> get state => _state;

  /// Dispose of resources
  /// Note: As a singleton, this is rarely called, but available for cleanup if needed
  void dispose() {
    _state.dispose();
  }

  /// Handle map tap to identify and highlight airspaces
  void handleMapTap({
    required LatLng point,
    required Offset tapPosition,
    required List<Widget> airspaceLayers,
    required String context,
  }) {
    try {
      LoggingService.info('$context: Identifying airspace at ${point.latitude}, ${point.longitude}');

      // Identify airspace at tap point
      final identificationService = AirspaceIdentificationService.instance;
      final airspaces = identificationService.identifyAirspacesAtPoint(point);

      LoggingService.info('$context: Found ${airspaces.length} airspaces at tap location');

      if (airspaces.isNotEmpty) {
        LoggingService.info('$context: Showing airspace popup for ${airspaces.first.name}');

        // Find all clipped polygons that contain the tap point and their centroids
        final result = _findClippedPolygonsWithCentroids(point, airspaces, airspaceLayers);

        _state.value = AirspaceInteractionState(
          airspaces: airspaces,
          tapPosition: tapPosition,
          highlightedPolygons: result.$1,
          labels: result.$2,
        );
      } else {
        LoggingService.info('$context: No airspace found at tap location, clearing popup');
        clearInteraction();
      }
    } catch (e) {
      LoggingService.error('$context: Error identifying airspace', e);
      clearInteraction();
    }
  }

  /// Clear current airspace interaction
  void clearInteraction() {
    _state.value = null;
  }

  /// Find clipped polygons that contain the tap point with their centroids
  (List<Polygon>, List<AirspaceLabel>) _findClippedPolygonsWithCentroids(
    LatLng point,
    List<AirspaceData> airspaces,
    List<Widget> airspaceLayers,
  ) {
    final highlightedPolygons = <Polygon>[];
    final individualLabels = <MapEntry<AirspaceData, LatLng>>[];
    int airspaceIndex = 0;

    // Search through the rendered airspace layers for all polygons containing the tap point
    for (final layer in airspaceLayers) {
      if (layer is PolygonLayer) {
        for (final polygon in layer.polygons) {
          // Check if this polygon contains the tap point
          if (MapCalculationUtils.pointInPolygon(point, polygon.points)) {
            // Create highlighted version with double opacity
            final originalColor = polygon.color ?? Colors.blue.withValues(alpha: 0.2);
            final highlightedPolygon = Polygon(
              points: polygon.points,
              borderStrokeWidth: polygon.borderStrokeWidth * 1.5,
              borderColor: polygon.borderColor,
              color: originalColor.withValues(
                alpha: ((originalColor.a * 255.0).round() * 2).clamp(0, 255) / 255.0,
              ),
            );
            highlightedPolygons.add(highlightedPolygon);

            // Calculate centroid and associate with airspace
            final centroid = MapCalculationUtils.calculateCentroid(polygon.points);
            if (airspaceIndex < airspaces.length) {
              individualLabels.add(MapEntry(airspaces[airspaceIndex], centroid));
              airspaceIndex++;
            }
          }
        }
      }
    }

    // Group nearby labels to prevent overlap
    final groupedLabels = _groupNearbyLabels(individualLabels);

    LoggingService.info('Found ${highlightedPolygons.length} polygons, grouped into ${groupedLabels.length} labels');
    return (highlightedPolygons, groupedLabels);
  }

  /// Group nearby labels to prevent overlap
  List<AirspaceLabel> _groupNearbyLabels(List<MapEntry<AirspaceData, LatLng>> individualLabels) {
    if (individualLabels.isEmpty) return [];

    const double groupingThresholdMeters = 1000.0;
    final groupedIndices = <int>{};
    final result = <AirspaceLabel>[];

    for (int i = 0; i < individualLabels.length; i++) {
      if (groupedIndices.contains(i)) continue;

      final currentLabel = individualLabels[i];
      final group = <AirspaceData>[currentLabel.key];
      final positions = <LatLng>[currentLabel.value];
      groupedIndices.add(i);

      // Find all other labels within threshold distance
      for (int j = i + 1; j < individualLabels.length; j++) {
        if (groupedIndices.contains(j)) continue;

        final otherLabel = individualLabels[j];
        final distance = MapCalculationUtils.haversineDistance(
          currentLabel.value,
          otherLabel.value,
        );

        if (distance <= groupingThresholdMeters) {
          group.add(otherLabel.key);
          positions.add(otherLabel.value);
          groupedIndices.add(j);
        }
      }

      // Calculate average position for the group
      final groupPosition = MapCalculationUtils.calculateCentroid(positions);
      result.add(AirspaceLabel(airspaces: group, position: groupPosition));
    }

    return result;
  }

  /// Build airspace label widget for single or grouped airspaces
  static Widget buildAirspaceLabel(List<AirspaceData> airspaces) {
    if (airspaces.isEmpty) return const SizedBox.shrink();

    // For a single airspace, show full details
    if (airspaces.length == 1) {
      final airspace = airspaces.first;
      final lower = airspace.lowerAltitude;
      final upper = airspace.upperAltitude;
      String altitudeRange;

      if (lower == upper || upper.isEmpty) {
        altitudeRange = lower;
      } else if (lower.isEmpty) {
        altitudeRange = upper;
      } else {
        altitudeRange = '$lower-$upper';
      }

      return IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              airspace.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
                  Shadow(color: Colors.black, blurRadius: 4, offset: Offset(-1, -1)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${airspace.type.abbreviation}, ${airspace.icaoClass.displayName}, $altitudeRange',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1, 1)),
                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(-1, -1)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    // For grouped airspaces, show combined info
    final firstAirspace = airspaces.first;
    final typeClasses = airspaces
        .map((a) => '${a.type.abbreviation}/${a.icaoClass.displayName}')
        .toSet()
        .join(', ');

    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            airspaces.length == 2 ? firstAirspace.name : 'Multiple Airspaces',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
                Shadow(color: Colors.black, blurRadius: 4, offset: Offset(-1, -1)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            typeClasses,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1, 1)),
                Shadow(color: Colors.black, blurRadius: 3, offset: Offset(-1, -1)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// State for airspace interaction
class AirspaceInteractionState {
  final List<AirspaceData> airspaces;
  final Offset tapPosition;
  final List<Polygon> highlightedPolygons;
  final List<AirspaceLabel> labels;

  const AirspaceInteractionState({
    required this.airspaces,
    required this.tapPosition,
    this.highlightedPolygons = const [],
    this.labels = const [],
  });
}

/// Airspace label with position
class AirspaceLabel {
  final List<AirspaceData> airspaces;
  final LatLng position;

  const AirspaceLabel({
    required this.airspaces,
    required this.position,
  });
}
