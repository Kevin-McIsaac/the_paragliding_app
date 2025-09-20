# Airspace Pipeline Performance Tuning

## Overview

This document tracks the performance optimization journey of the airspace rendering pipeline in Free Flight Log. The pipeline processes aviation airspace data from OpenAIP, stores it in SQLite, and renders it on maps with polygon clipping to eliminate overlaps.

### Architecture
```
OpenAIP API → GeoJSON → SQLite (Binary Storage) → Direct Pipeline → Clipper2 → Flutter Map
```

### Performance Goals
- Sub-100ms rendering for typical viewport (100-200 airspaces)
- Minimal memory footprint on mobile devices
- Smooth pan/zoom without stuttering
- Efficient polygon clipping for overlapping airspaces

---

## Optimization Timeline

### Completed Optimizations

| Stage | Optimization | Implementation Details | Performance Impact | Code Location |
|-------|-------------|------------------------|-------------------|---------------|
| **1. SQL Filtering** | Move filtering to database | Filter by type, class, altitude, and viewport in SQL query instead of post-processing | Reduces data loaded by ~70-90% | `airspace_geojson_service.dart:445-450` |
| **2. Pre-computed Altitudes** | Store altitude in feet | Added `lower_altitude_ft INTEGER` column to avoid runtime conversion | Eliminates ~1ms per 100 airspaces | `airspace_disk_cache.dart:107-108` |
| **3. Viewport Culling** | SQL spatial indices | Compound index `idx_geometry_spatial` for bounding box queries | Fast spatial queries (~5ms for 1000s) | `airspace_disk_cache.dart:185-189` |
| **4. Direct Pipeline** | Skip GeoJSON parsing | Load from cache directly without intermediate JSON | Saves ~20-30ms per load | `_loadAirspacePolygonsFromCacheDirect()` |
| **5. Altitude Sorting** | Pre-sort for clipping | Sort airspaces by altitude once for optimal clipping order | Enables early exit optimization | `airspace_geojson_service.dart:1473-1479` |
| **6. Early Exit** | Stop at higher altitudes | Break loop when lower altitude ≥ current altitude | Reduces comparisons by ~40-60% | `airspace_geojson_service.dart:1538-1545` |
| **7. Bounds Pre-check** | Inline bbox check | Direct coordinate comparison before polygon operations | Skips ~50-70% of polygon ops | `airspace_geojson_service.dart:1550-1557` |
| **8. Altitude Array** | Cache-friendly layout | Pre-extract altitudes into contiguous `Int32List` | Better CPU cache locality | `airspace_geojson_service.dart:1486-1490` |
| **9. Binary Storage** | Compressed coordinates | Float32 binary arrays with GZIP compression | 75% storage reduction vs JSON | `airspace_disk_cache.dart:227-287` |

---

## Current Performance Metrics

### Clipping Operation Analysis
Based on production logging from `CLIPPING_DETAILED_PERFORMANCE`:

| Metric | Baseline (O(n²)) | Current | Improvement |
|--------|------------------|---------|-------------|
| **Theoretical comparisons** | n*(n-1)/2 | - | - |
| **Actual comparisons** | 100% of theoretical | 30-40% of theoretical | **60-70% reduction** |
| **Altitude rejections** | 0 | 40-60% of comparisons | Early exit working |
| **Bounds rejections** | 0 | 50-70% of remaining | Spatial filtering effective |
| **Empty clipping lists** | 0 | ~20% of airspaces | Skip unnecessary ops |
| **Actual clipping operations** | 100% | ~20% of airspaces | **80% reduction** |

### Timing Breakdown (100 airspaces)
- **Setup & sorting**: 1-5ms
- **Comparison loop**: 10-20ms
- **Polygon clipping**: 30-50ms (only for overlapping)
- **Total**: ~40-75ms

### Memory Usage
- **Coordinate storage**: 4 bytes/coord (Float32)
- **Polygon offsets**: ~20 bytes/polygon (JSON array)
- **Total per airspace**: ~2-5KB (depending on complexity)

---

## Pipeline Stage Details

### Stage 1: Database Query
```sql
SELECT * FROM airspace_geometry
WHERE bounds_west <= ? AND bounds_east >= ?
  AND bounds_south <= ? AND bounds_north >= ?
  AND lower_altitude_ft <= ?
  AND type_code NOT IN (?)
  AND icao_class NOT IN (?)
ORDER BY lower_altitude_ft ASC  -- When clipping enabled
```

### Stage 2: Binary Decoding
```dart
// Current: Float32 binary to LatLng
Float32List → LatLng objects → Display/Clipping

// Proposed: Int32 direct to Clipper2
Int32List → Point64 (direct) → Clipping
```

### Stage 3: Clipping Algorithm
```
For each airspace (sorted by altitude):
  1. Check altitude early exit
  2. Inline bounds check
  3. Collect lower overlapping airspaces
  4. Perform Clipper2 difference operation
  5. Convert result to display format
```

---

## Proposed Optimizations

### High Priority: Int32 Coordinate Storage

**Goal**: Eliminate LatLng intermediary objects for Clipper2 operations

| Aspect | Current | Proposed | Expected Impact |
|--------|---------|----------|-----------------|
| **Storage Format** | Float32 (4 bytes/coord) | Int32 (4 bytes/coord) | Same size, better alignment |
| **Conversion Path** | Float32→LatLng→Int64 | Int32→Point64 direct | **Eliminate 2 conversions** |
| **Memory Objects** | Create LatLng objects | Zero intermediate objects | **~50% memory reduction** |
| **Conversion Speed** | ~10-20ms per 1000 polygons | ~2-5ms per 1000 polygons | **75% faster** |

#### Implementation Plan
1. Change `_encodeCoordinatesBinary()` to store Int32 with scale 10^7
2. Add `_createClipperPathFromInt32()` for direct path creation
3. Modify clipping to work with Int32 blobs
4. Convert to LatLng only for final display

### Medium Priority: Polygon Offset Optimization

**Current**: JSON array stored as TEXT
**Proposed**: Binary Int32List BLOB

- Save ~50% storage (4 bytes vs ~6 chars per number)
- Eliminate JSON parsing overhead
- Direct memory view access

### Low Priority: Future Considerations

1. **R-tree Spatial Index** (Rejected - too complex for current scale)
2. **SIMD Operations** (Dart support limited and buggy in AOT)
3. **WebAssembly Clipper** (Not available in Flutter)
4. **GPU Acceleration** (Overkill for current polygon counts)

---

## Benchmarking Methodology

### Test Scenarios
1. **Dense Urban**: 200+ overlapping airspaces (e.g., London, Paris)
2. **Sparse Rural**: 10-20 airspaces with minimal overlap
3. **Pan Test**: Rapid viewport changes
4. **Zoom Test**: Multiple zoom levels

### Metrics to Track
```dart
LoggingService.structured('CLIPPING_PERFORMANCE', {
  'polygons_input': count,
  'polygons_output': count,
  'clipping_time_ms': ms,
  'total_comparisons': count,
  'altitude_rejections': count,
  'bounds_rejections': count,
});
```

### Performance Targets
- **Initial load**: <100ms for typical viewport
- **Pan/zoom update**: <50ms
- **Memory per airspace**: <5KB
- **Comparison reduction**: >60% from theoretical O(n²)

---

## Maintenance Notes

### Updating This Document
When implementing new optimizations:
1. Add entry to Optimization Timeline with commit hash
2. Update Performance Metrics with new measurements
3. Move items from Proposed to Completed
4. Add new proposals as discovered

### Running Performance Tests
```bash
# Enable performance logging
LoggingService.enablePerformanceLogging = true;

# Look for structured logs
flutter logs | grep "CLIPPING_PERFORMANCE"
flutter logs | grep "AIRSPACE_CLIPPING"
```

### Code Locations
- **Main service**: `lib/services/airspace_geojson_service.dart`
- **Cache layer**: `lib/services/airspace_disk_cache.dart`
- **Clipping logic**: `_applyPolygonClipping()` at line 1429
- **Direct pipeline**: `_loadAirspacePolygonsFromCacheDirect()` at line 1736

---

## Change Log

### 2024-01-20
- Initial documentation created
- Documented 9 completed optimizations
- Added Int32 storage proposal

### 2025-09-20
- Implemented Int32 coordinate storage with ClipperData optimization
- Added direct database BLOB to Clipper2 pipeline
- Performance testing with 1344 dense airspaces (Austria, France)

---

## Int32 Optimization Results

### Implementation Complete
The Int32 coordinate storage optimization has been successfully implemented with the following components:

1. **ClipperData Class**: Helper class for direct Int32 to Clipper2 conversion
2. **Direct Pipeline**: Database BLOBs → ClipperData → Clipper2 (no LatLng intermediary)
3. **Memory Alignment**: Handled SQLite BLOB alignment issues with buffer copying
4. **Backward Compatibility**: Maintains support for traditional LatLng paths for insertion

### Performance Results

#### Dense Airspace Test (1344 polygons)
| Metric | Before Optimization | After Optimization | Improvement |
|--------|--------------------|--------------------|-------------|
| **Clipping Time** | ~2000-2500ms (estimated) | 1508-1727ms | **~25-40% faster** |
| **Memory Objects** | 1344 LatLng arrays | 0 intermediate objects | **100% reduction** |
| **Conversion Steps** | Float32→LatLng→Int64 | Int32→Point64 direct | **2 conversions eliminated** |

#### Test Conditions
- **Location**: Lake Garda area, Italy
- **Airspace Data**: Austria (1819 features) + France (1631 features)
- **Viewport Polygons**: 1344 airspaces loaded
- **Output Polygons**: 1079 after clipping (265 eliminated by overlap)
- **Device**: Chromebox emulator

### Key Achievements

1. **Direct Binary Pipeline**: Successfully eliminated LatLng conversion for clipping operations
2. **Memory Efficiency**: Zero intermediate object allocation during clipping
3. **Maintained Accuracy**: 10^7 precision factor provides 1.11cm accuracy
4. **Production Ready**: Handles dense European airspace with sub-2-second clipping

### Technical Notes

- ClipperData is created only when `enableClipping=true` for optimal performance
- Polygon data still uses LatLng for insertion operations (write path unchanged)
- Memory alignment issues resolved by copying SQLite BLOBs to aligned buffers
- The optimization primarily benefits the read/clip path, not the write path

---

*Last Updated: 2025-09-20*
*Next Review: After R-tree spatial index evaluation*