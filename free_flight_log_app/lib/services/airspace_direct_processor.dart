import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'airspace_geojson_service.dart';
import '../data/models/airspace_enums.dart';

/// Optimized airspace polygon for direct pipeline processing
/// Keeps data in binary format until final rendering for maximum efficiency
class DirectAirspacePolygon {
  final Uint8List coordinatesBinary;
  final List<int> polygonOffsets;
  final int lowerAltitudeFt;
  final int typeCode;
  final int? icaoClass;
  final fm.LatLngBounds bounds;
  final AirspaceStyle style;
  final AirspaceData airspaceData;

  // Lazy-loaded points
  List<LatLng>? _cachedPoints;

  DirectAirspacePolygon({
    required this.coordinatesBinary,
    required this.polygonOffsets,
    required this.lowerAltitudeFt,
    required this.typeCode,
    this.icaoClass,
    required this.bounds,
    required this.style,
    required this.airspaceData,
  });

  /// Get points, decoding from binary only when needed
  List<LatLng> get points {
    _cachedPoints ??= _decodeBinary();
    return _cachedPoints!;
  }

  /// Decode binary coordinates to LatLng points
  List<LatLng> _decodeBinary() {
    // Ensure alignment for Float32List
    final alignedBytes = Uint8List.fromList(coordinatesBinary);
    final floatArray = Float32List.view(
      alignedBytes.buffer,
      0,
      alignedBytes.length ~/ 4,
    );

    final points = <LatLng>[];

    // For now, just decode the first polygon (handle multi-polygon later)
    if (polygonOffsets.isNotEmpty) {
      final startIdx = polygonOffsets[0] * 2;
      final endIdx = polygonOffsets.length > 1
          ? polygonOffsets[1] * 2
          : floatArray.length;

      for (int i = startIdx; i < endIdx; i += 2) {
        points.add(LatLng(
          floatArray[i + 1], // latitude
          floatArray[i],     // longitude
        ));
      }
    }

    return points;
  }

  /// Create from database row with pre-computed altitude
  factory DirectAirspacePolygon.fromDatabaseRow(Map<String, dynamic> row) {
    // Extract bounds
    final bounds = fm.LatLngBounds(
      LatLng(row['bounds_south'] as double, row['bounds_west'] as double),
      LatLng(row['bounds_north'] as double, row['bounds_east'] as double),
    );

    // Build airspace data from native columns
    final airspaceData = AirspaceData(
      name: row['name'] as String,
      type: AirspaceType.fromCode(row['type_code'] as int),
      icaoClass: row['icao_class'] != null
          ? IcaoClass.fromCode(row['icao_class'] as int)
          : null,
      upperLimit: row['upper_value'] != null ? {
        'value': row['upper_value'],
        'unit': row['upper_unit'],
        'reference': row['upper_reference'],
      } : null,
      lowerLimit: row['lower_value'] != null ? {
        'value': row['lower_value'],
        'unit': row['lower_unit'],
        'reference': row['lower_reference'],
      } : null,
      country: row['country'] as String?,
    );

    // Get style once
    final style = AirspaceGeoJsonService.instance.getStyleForAirspace(airspaceData);

    return DirectAirspacePolygon(
      coordinatesBinary: row['coordinates_binary'] as Uint8List,
      polygonOffsets: (row['polygon_offsets'] as List).cast<int>(),
      lowerAltitudeFt: row['lower_altitude_ft'] as int? ?? 999999,
      typeCode: row['type_code'] as int,
      icaoClass: row['icao_class'] as int?,
      bounds: bounds,
      style: style,
      airspaceData: airspaceData,
    );
  }

  /// Convert to Flutter Map polygon for rendering
  fm.Polygon toFlutterMapPolygon() {
    return fm.Polygon(
      points: points,
      borderStrokeWidth: style.borderWidth,
      borderColor: style.borderColor,
      color: style.fillColor,
    );
  }
}

/// Direct processing pipeline for airspace polygons
class AirspaceDirectProcessor {
  /// Process raw database results directly to clipped Flutter Map polygons
  /// This bypasses all intermediate conversions for maximum efficiency
  static Future<List<fm.Polygon>> processDirect({
    required List<Map<String, dynamic>> databaseResults,
    required bool enableClipping,
  }) async {
    if (databaseResults.isEmpty) {
      return [];
    }

    // Convert to direct polygons (already sorted by altitude from SQL)
    final directPolygons = databaseResults
        .map((row) => DirectAirspacePolygon.fromDatabaseRow(row))
        .toList();

    if (!enableClipping) {
      // No clipping needed, just convert to Flutter Map polygons
      return directPolygons.map((dp) => dp.toFlutterMapPolygon()).toList();
    }

    // Apply optimized linear clipping
    return _applyOptimizedClipping(directPolygons);
  }

  /// Apply optimized linear clipping with pre-sorted altitude data
  static List<fm.Polygon> _applyOptimizedClipping(
    List<DirectAirspacePolygon> polygons,
  ) {
    final clippedPolygons = <fm.Polygon>[];
    final clippingMasks = <DirectAirspacePolygon>[];

    // Process from lowest to highest altitude (already sorted)
    for (final polygon in polygons) {
      // Check if this polygon needs clipping
      bool needsClipping = false;

      for (final mask in clippingMasks) {
        // Early exit: all remaining masks are at higher altitude
        if (mask.lowerAltitudeFt >= polygon.lowerAltitudeFt) {
          break;
        }

        // Check bounds overlap
        if (_boundsOverlap(polygon.bounds, mask.bounds)) {
          needsClipping = true;
          break;
        }
      }

      if (!needsClipping) {
        // No clipping needed, add directly
        clippedPolygons.add(polygon.toFlutterMapPolygon());
      } else {
        // TODO: Implement actual polygon clipping here
        // For now, just add the polygon (will implement full clipping later)
        clippedPolygons.add(polygon.toFlutterMapPolygon());
      }

      // Add to clipping masks for next iteration
      clippingMasks.add(polygon);
    }

    return clippedPolygons;
  }

  /// Check if two bounds overlap
  static bool _boundsOverlap(fm.LatLngBounds a, fm.LatLngBounds b) {
    return !(a.east < b.west ||
             a.west > b.east ||
             a.north < b.south ||
             a.south > b.north);
  }
}