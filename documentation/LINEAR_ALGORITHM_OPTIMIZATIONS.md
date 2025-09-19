# Linear O(n²) Algorithm Optimization Opportunities

Based on our performance analysis, here are concrete optimizations for the Linear algorithm that could provide significant speedups:

## 1. Early Exit Optimizations

### Current Code Pattern
```dart
for (int j = 0; j < i; j++) {
  final lowerAirspace = visibleAirspaces[j];
  totalComparisons++;

  // Skip if bounding boxes don't overlap
  if (!_boundingBoxesOverlap(currentBounds, lowerAirspace.bounds)) {
    skippedDueToBounds++;
    continue;
  }

  // Check altitude
  if (lowerAltitude < currentAltitude) {
    clippingPolygons.add(lowerAirspace.data.points);
  }
}
```

### Optimization 1: Pre-sort by Altitude
```dart
// Sort once at the beginning by altitude
visibleAirspaces.sort((a, b) =>
  a.data.airspaceData.getLowerAltitudeInFeet()
    .compareTo(b.data.airspaceData.getLowerAltitudeInFeet()));

// Now we can break early when altitude is too high
for (int j = 0; j < i; j++) {
  final lowerAltitude = visibleAirspaces[j].data.airspaceData.getLowerAltitudeInFeet();
  final currentAltitude = airspaceData.getLowerAltitudeInFeet();

  // Can stop checking - all remaining are at same or higher altitude
  if (lowerAltitude >= currentAltitude) break;

  if (!_boundingBoxesOverlap(currentBounds, visibleAirspaces[j].bounds)) continue;

  clippingPolygons.add(visibleAirspaces[j].data.points);
}
```
**Expected Improvement**: 20-30% fewer comparisons

## 2. Bounding Box Check Optimizations

### Current Implementation
```dart
bool _boundingBoxesOverlap(fm.LatLngBounds bounds1, fm.LatLngBounds bounds2) {
  return !(bounds1.south > bounds2.north ||
      bounds1.north < bounds2.south ||
      bounds1.west > bounds2.east ||
      bounds1.east < bounds2.west);
}
```

### Optimization 2A: Inline and Simplify
```dart
// Inline the check to avoid function call overhead
// Use early exit on first condition failure
if (currentBounds.south > lowerBounds.north) continue;
if (currentBounds.north < lowerBounds.south) continue;
if (currentBounds.west > lowerBounds.east) continue;
if (currentBounds.east < lowerBounds.west) continue;

// Boxes overlap - proceed with clipping
```
**Expected Improvement**: 5-10% from avoiding function calls

### Optimization 2B: Integer Coordinates
```dart
// Pre-convert to integers (scaled by 1e7)
class IntBounds {
  final int south, north, west, east;
}

// Integer comparisons are faster than floating point
if (currentIntBounds.south > lowerIntBounds.north) continue;
```
**Expected Improvement**: 10-15% from integer math

## 3. Memory Layout Optimizations

### Current: Array of Structures (AoS)
```dart
List<({fm.Polygon polygon, AirspacePolygonData data, fm.LatLngBounds bounds})> visibleAirspaces;
```

### Optimization 3: Structure of Arrays (SoA)
```dart
// Better cache locality - all bounds together
class AirspaceArrays {
  final List<fm.LatLngBounds> bounds;
  final List<int> altitudes;
  final List<AirspacePolygonData> data;
  final List<fm.Polygon> polygons;
}

// Bounds checks access only the bounds array - better cache usage
for (int j = 0; j < i; j++) {
  if (!boundsOverlap(boundsArray[i], boundsArray[j])) continue;
  if (altitudesArray[j] >= altitudesArray[i]) break;
  // ...
}
```
**Expected Improvement**: 15-25% from better cache utilization

## 4. Parallel Processing

### Optimization 4: Parallel Outer Loop
```dart
import 'dart:isolate';

// Process independent polygons in parallel
final results = await Future.wait(
  visibleAirspaces.asMap().entries.map((entry) async {
    final i = entry.key;
    final current = entry.value;

    // Each polygon can be clipped independently
    return Isolate.run(() => _clipSinglePolygon(
      current,
      visibleAirspaces.sublist(0, i), // Only lower polygons
    ));
  })
);
```
**Expected Improvement**: 2-4x on multi-core systems

## 5. Spatial Hashing (Hybrid Approach)

### Optimization 5: Grid-based Pre-filtering
```dart
// Divide space into grid cells
class SpatialGrid {
  static const int gridSize = 100; // 100x100 grid
  final Map<int, List<int>> grid = {};

  int getCell(double lat, double lng) {
    final x = ((lng + 180) * gridSize / 360).floor();
    final y = ((lat + 90) * gridSize / 180).floor();
    return y * gridSize + x;
  }

  List<int> getCandidates(fm.LatLngBounds bounds) {
    // Get all polygons in cells that bounds touches
    final candidates = <int>{};
    for (var cell in getTouchedCells(bounds)) {
      candidates.addAll(grid[cell] ?? []);
    }
    return candidates.toList();
  }
}

// Use grid to reduce comparisons
final candidates = spatialGrid.getCandidates(currentBounds);
for (int j in candidates) {
  if (j >= i) continue; // Only check lower polygons
  // ... rest of comparison
}
```
**Expected Improvement**: 30-50% fewer comparisons for dense areas

## 6. SIMD Optimizations

### Optimization 6: Vector Operations
```dart
import 'dart:typed_data';

// Use SIMD for bounding box checks (if Dart adds SIMD support)
class SimdBounds {
  final Float32x4 bounds; // [south, north, west, east]

  bool overlaps(SimdBounds other) {
    // Single SIMD comparison
    final result = bounds.lessThan(other.bounds);
    // Check all conditions in parallel
    return !result.flagX && !result.flagY && !result.flagZ && !result.flagW;
  }
}
```
**Expected Improvement**: 2-3x for bounds checks (future)

## 7. Clipping Operation Optimizations

### Current: Clip Against All Lower Polygons
```dart
final clippedResults = _subtractPolygonsFromSubject(
  subjectPoints: currentPoints,
  clippingPolygons: clippingPolygons, // All lower polygons
);
```

### Optimization 7: Incremental Clipping with Early Exit
```dart
List<List<LatLng>> clippedResults = [currentPoints];

for (final clipPoly in clippingPolygons) {
  final newResults = <List<LatLng>>[];

  for (final subject in clippedResults) {
    // Quick check if clipping is needed
    if (!_polygonsOverlap(subject, clipPoly)) {
      newResults.add(subject);
      continue;
    }

    // Perform actual clipping
    final clipped = _clipSingleAgainstSingle(subject, clipPoly);
    newResults.addAll(clipped);
  }

  clippedResults = newResults;

  // Early exit if completely clipped
  if (clippedResults.isEmpty) break;
}
```
**Expected Improvement**: 20-40% for heavily overlapped areas

## 8. Altitude-based Optimizations

### Optimization 8: Skip Altitude Bands
```dart
// Group by altitude bands (e.g., every 500ft)
const int bandSize = 500;
final Map<int, List<int>> altitudeBands = {};

for (int i = 0; i < visibleAirspaces.length; i++) {
  final band = altitudes[i] ~/ bandSize;
  altitudeBands.putIfAbsent(band, () => []).add(i);
}

// Only check polygons in lower bands
for (int j = 0; j < i; j++) {
  final currentBand = altitudes[i] ~/ bandSize;
  final checkBand = altitudes[j] ~/ bandSize;

  // Skip entire bands that are too high
  if (checkBand >= currentBand) continue;

  // Rest of checking...
}
```
**Expected Improvement**: 15-25% for layered airspace

## Implementation Priority

### Phase 1: Quick Wins (1-2 days)
1. **Pre-sort by altitude** - Easy, immediate benefit
2. **Inline bounding box checks** - Simple code change
3. **Early exit conditions** - Add break statements

### Phase 2: Structural Changes (3-5 days)
4. **Structure of Arrays** - Requires refactoring
5. **Integer coordinates** - Conversion layer needed
6. **Incremental clipping** - Algorithm change

### Phase 3: Advanced (1-2 weeks)
7. **Spatial hashing** - New data structure
8. **Parallel processing** - Isolate implementation
9. **SIMD** - Wait for Dart support

## Expected Combined Performance

Implementing Phase 1 + 2 optimizations:
- **Perth**: 193ms → ~120ms (38% improvement)
- **Continental AU**: 334ms → ~200ms (40% improvement)
- **France**: 942ms → ~550ms (42% improvement)

With all optimizations (including parallel):
- Could achieve 4-6x speedup
- Continental AU: 334ms → ~60-80ms
- France: 942ms → ~150-200ms

## Code Example: Optimized Linear Algorithm

```dart
class OptimizedLinearClipper {
  // Pre-computed integer bounds for fast comparison
  final List<IntBounds> _intBounds = [];
  final List<int> _altitudes = [];
  final SpatialGrid _grid = SpatialGrid();

  List<fm.Polygon> clipAirspaces(
    List<({fm.Polygon polygon, AirspacePolygonData data})> polygonsWithAltitude,
  ) {
    // Phase 1: Pre-process and sort
    _preprocessPolygons(polygonsWithAltitude);

    // Phase 2: Parallel clipping
    return _parallelClip(polygonsWithAltitude);
  }

  void _preprocessPolygons(polygons) {
    // Sort by altitude (lowest first)
    polygons.sort((a, b) =>
      a.data.airspaceData.getLowerAltitudeInFeet()
        .compareTo(b.data.airspaceData.getLowerAltitudeInFeet()));

    // Pre-compute integer bounds and build spatial index
    for (final poly in polygons) {
      _intBounds.add(IntBounds.fromLatLng(poly.bounds));
      _altitudes.add(poly.data.airspaceData.getLowerAltitudeInFeet());
      _grid.add(poly);
    }
  }

  List<fm.Polygon> _parallelClip(polygons) {
    // Process in parallel chunks
    final numCores = Platform.numberOfProcessors;
    final chunkSize = (polygons.length / numCores).ceil();

    final futures = <Future<List<fm.Polygon>>>[];

    for (int i = 0; i < polygons.length; i += chunkSize) {
      final end = min(i + chunkSize, polygons.length);
      futures.add(
        Isolate.run(() => _clipChunk(polygons.sublist(i, end), i))
      );
    }

    return (await Future.wait(futures)).expand((x) => x).toList();
  }
}
```

## Conclusion

The Linear O(n²) algorithm, already the fastest, has significant optimization potential:

1. **Quick wins** (Phase 1) can deliver 20-30% improvement with minimal changes
2. **Structural optimizations** (Phase 2) can add another 20-30%
3. **Advanced techniques** (Phase 3) could achieve 4-6x total speedup

The optimized Linear algorithm would be unbeatable for airspace clipping, combining:
- Simple, maintainable code
- Predictable performance
- Excellent scaling characteristics
- Hardware-friendly access patterns

These optimizations maintain Linear's key advantage - sequential memory access - while reducing unnecessary work through smarter filtering and parallel execution.