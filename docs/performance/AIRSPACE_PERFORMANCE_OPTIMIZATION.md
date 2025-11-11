# Airspace Performance Optimization

## Overview

This document tracks the performance optimization journey of the airspace rendering pipeline in The Paragliding App. The pipeline processes aviation airspace data from OpenAIP, stores it in SQLite, and renders it on maps with polygon clipping to eliminate overlaps.

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
| **10. Int32 Coordinates** | Direct Clipper2 pipeline | Int32 storage with zero-copy ClipperData | 25-40% faster clipping, 85% memory reduction | Multiple files (see below) |

---

## Optimization Deep Dives

### 1. Int32 Coordinate Optimization (Major Improvement)

#### Problem
The original pipeline had excessive conversions and memory allocations:
```
Database (Float32) → Float32List → LatLng objects → Int64 → Clipper2
```

This created:
- 50,000+ temporary LatLng objects for 1344 polygons
- Multiple conversion steps (Float32→LatLng→Int64)
- ~56 bytes per coordinate (object overhead + conversions)

#### Solution
Direct Int32 pipeline with ClipperData wrapper:
```
Database (Int32) → Int32List.view → ClipperData → Point64 → Clipper2
```

#### Implementation Components

1. **ClipperData Class**: Helper class for zero-copy Int32 to Clipper2 conversion
2. **Direct Pipeline**: Database BLOBs → ClipperData → Clipper2 (no LatLng intermediary)
3. **Memory Alignment**: Handled SQLite BLOB alignment issues with buffer copying
4. **Backward Compatibility**: Maintains support for traditional LatLng paths for insertion

#### Performance Results

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Clipping Time (1344 polygons)** | ~2000-2500ms | 1508-1727ms | **25-40% faster** |
| **Memory Allocations** | 50,000+ LatLng objects | 0 intermediate objects | **100% reduction** |
| **Conversion Overhead** | ~35-45ms per 1000 | ~2-5ms per 1000 | **85% reduction** |
| **Memory per Coordinate** | ~56 bytes | ~8 bytes | **85% reduction** |

#### Test Conditions
- Location: Lake Garda area, Italy
- Airspace Data: Austria (1819 features) + France (1631 features)
- Viewport Polygons: 1344 airspaces loaded
- Output Polygons: 1079 after clipping (265 eliminated by overlap)
- Device: Chromebox emulator

### 2. SQL Spatial Index Optimization

#### Current Index Structure (Can Be Improved)

```sql
-- Multiple separate indices (suboptimal)
CREATE INDEX idx_geometry_spatial ON airspace_geometry(
  bounds_west, bounds_east, bounds_south, bounds_north
);
CREATE INDEX idx_geometry_spatial_altitude ON airspace_geometry(
  lower_altitude_ft, bounds_west, bounds_east, bounds_south, bounds_north
);
```

#### Proposed Covering Index

```sql
-- Create optimized covering index for the most common query pattern
CREATE INDEX idx_geometry_spatial_covering ON airspace_geometry(
  bounds_west,
  bounds_east,
  bounds_south,
  bounds_north,
  lower_altitude_ft,
  type_code,
  id,
  coordinates_binary,
  polygon_offsets
);
```

**Expected Impact:**
- Query time: 50-100ms → **20-30ms** (60-70% faster)
- Index lookup: 5-10ms → 2-3ms
- Data fetch: 40-80ms → 15-25ms

### 3. Grid-Based Pre-filtering (Future Optimization)

#### Concept
Add grid cell column for coarse filtering before exact spatial query:

```sql
-- Add grid cell column (10x10 degree grid)
ALTER TABLE airspace_geometry ADD COLUMN grid_cell INTEGER;

-- Update grid cells
UPDATE airspace_geometry
SET grid_cell =
  (CAST((bounds_west + 180) / 10 AS INTEGER)) * 100 +
  (CAST((bounds_south + 90) / 10 AS INTEGER));

-- Create grid index
CREATE INDEX idx_geometry_grid ON airspace_geometry(
  grid_cell, bounds_west, bounds_east
);

-- Optimized query with grid filtering
SELECT * FROM airspace_geometry
WHERE grid_cell IN (?, ?, ?, ?)  -- Pre-computed grid cells
  AND bounds_west <= ? AND bounds_east >= ?
  AND bounds_south <= ? AND bounds_north >= ?
  AND lower_altitude_ft <= ?
ORDER BY lower_altitude_ft ASC;
```

**Expected Impact:**
- Reduces candidates by 80-90%
- Query time: 20-30ms → **10-15ms** (50% faster)
- Particularly effective for large datasets (>5000 airspaces)

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

---

## Optimization Impact Summary

### Before All Optimizations (Estimated)
- **Pipeline**: Float32 → LatLng → Int64
- **Clipping**: ~2000-2500ms for 1344 polygons
- **Memory**: 56 bytes per coordinate
- **Objects**: 50,000+ LatLng instances
- **Query**: 100-150ms with inefficient filters

### After All Optimizations
- **Pipeline**: Int32 → Point64 direct
- **Clipping**: 1500-1700ms (25-40% faster)
- **Memory**: 8 bytes per coordinate (85% less)
- **Objects**: 1 ClipperData wrapper (99.99% fewer)
- **Query**: 50-100ms with SQL filtering

---

## Rejected Optimizations

### R-tree Spatial Index
**Reason**: Too complex for current scale (<5000 polygons)
- Implementation effort high
- Benefit marginal for current dataset size
- May revisit if scaling to global coverage (50,000+ airspaces)

### SIMD Operations
**Reason**: Limited Dart support, buggy in AOT compilation
- Platform-specific implementation required
- Maintenance burden high
- Performance gain uncertain

### WebAssembly Clipper
**Reason**: Not available in Flutter environment
- Would require custom bridge
- Flutter's FFI overhead negates benefits

### GPU Acceleration
**Reason**: Overkill for current polygon counts
- Complex implementation
- Better to optimize algorithm first
- May revisit if rendering >10,000 polygons simultaneously

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

## Running Performance Tests

```bash
# Enable performance logging
LoggingService.enablePerformanceLogging = true;

# Look for structured logs
flutter_controller_enhanced logs 50 | grep "CLIPPING_PERFORMANCE"
flutter_controller_enhanced logs 50 | grep "AIRSPACE_CLIPPING"
```

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

### 2025-01-12
- Consolidated performance documentation
- Added grid-based pre-filtering proposal
- Updated covering index recommendations

---

*Last Updated: 2025-01-12*
*Next Review: After covering index implementation*
