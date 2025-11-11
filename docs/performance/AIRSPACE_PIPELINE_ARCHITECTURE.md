# Airspace Pipeline Architecture

## Overview

The airspace rendering pipeline processes aviation airspace data from OpenAIP, stores it efficiently in SQLite, and renders it on maps with polygon clipping to eliminate overlaps.

### Pipeline Stages

```
INGESTION → DATABASE → QUERY → CLIPPING → RENDERING
   16s        3.5s      50ms     1.5s       60fps
```

## Stage 1: INGESTION (16-20 seconds)

### Download from OpenAIP API
```
OpenAIP API (GeoJSON)
├── Australia: 1819 features, 12.9MB → 16.1s
└── France: 1631 features, 5.3MB → 7.5s
```

**Performance:**
- Download Speed: ~800KB/s average
- Total Time: 16-20s for country data
- Parsing: ~1-2s for GeoJSON decode

### Processing & Conversion
```
GeoJSON Features
→ Extract properties (type, altitude, class)
→ Convert coordinates to LatLng
→ Encode as Int32 with 10^7 precision
→ Create binary BLOBs
```

**Performance:**
- Processing: ~1ms per feature
- Int32 Encoding: ~0.5ms per polygon
- Total: ~2-3s for 1800 features

## Stage 2: DATABASE STORAGE (3.5 seconds)

### Binary Encoding

**Current Format: Int32 Binary Arrays**
```
LatLng Coordinates
→ Int32 arrays (10^7 precision = 1.11cm accuracy)
→ Polygon offsets as Int32List
→ GZIP compression (optional, 75% reduction)
```

### Database Schema

```sql
CREATE TABLE airspace_geometry (
  id TEXT PRIMARY KEY,
  coordinates_binary BLOB,      -- Int32 array
  polygon_offsets BLOB,         -- Int32 offsets
  bounds_west REAL,             -- Spatial index
  bounds_east REAL,
  bounds_south REAL,
  bounds_north REAL,
  lower_altitude_ft INTEGER,    -- Pre-computed for performance
  upper_altitude_ft INTEGER,
  type_code INTEGER,            -- Airspace type
  icao_class TEXT,
  name TEXT,
  country TEXT,
  extra_properties BLOB         -- Additional metadata
);

-- Spatial index for bounding box queries
CREATE INDEX idx_geometry_spatial ON airspace_geometry(
  bounds_west, bounds_east, bounds_south, bounds_north
);

-- Altitude + spatial composite index
CREATE INDEX idx_geometry_spatial_altitude ON airspace_geometry(
  lower_altitude_ft, bounds_west, bounds_east, bounds_south, bounds_north
);
```

### Batch Insert Performance
```
Batch Insert (1800 geometries)
├── Prepare statements: 10ms
├── Binary encoding: 500ms
├── SQLite writes: 3000ms
└── Index updates: 100ms
Total: ~3.5s
```

**Per-geometry metrics:**
- Binary size: 2-5KB average
- Insert time: ~2ms per geometry
- Index overhead: ~0.05ms

## Stage 3: QUERY & RETRIEVAL (50-100ms)

### Spatial Query

```sql
SELECT * FROM airspace_geometry
WHERE bounds_west <= ? AND bounds_east >= ?
  AND bounds_south <= ? AND bounds_north >= ?
  AND lower_altitude_ft <= ?
  AND type_code NOT IN (?)
ORDER BY lower_altitude_ft ASC;
```

**Performance:**
- Index lookup: 5-10ms
- Data fetch: 40-80ms for 1344 rows
- Total: 50-100ms typical

### ClipperData Creation (Optimized Int32 Path)

```
SQLite BLOB
→ Aligned buffer copy (1ms)
→ Int32List.view (zero-copy)
→ ClipperData wrapper (single object)
```

**Performance:**
- Buffer alignment: 1-2ms total
- View creation: <1ms
- Memory: 8 bytes per coordinate

## Stage 4: CLIPPING (1.5-1.7 seconds for 1344 polygons)

### Direct Clipper2 Pipeline

```
ClipperData (Int32)
→ Direct Point64 creation (on-demand)
→ Clipper2.Difference operations
→ Result polygons (clipped)
```

**Performance Breakdown:**
```
1344 Input Polygons
├── Setup & sorting: 5ms
├── Altitude filtering: 10ms (40% rejected)
├── Bounds checking: 15ms (50% rejected)
├── Actual clipping: 1420ms (20% of pairs)
├── Result conversion: 50ms
└── Total: 1500-1700ms
```

### Clipping Algorithm

```
For each airspace (sorted by altitude):
  1. Check altitude early exit
  2. Inline bounds check
  3. Collect lower overlapping airspaces
  4. Perform Clipper2 difference operation
  5. Convert result to display format
```

### Optimizations Applied

1. **Altitude early exit**: Skip 40-60% comparisons
2. **Bounds pre-check**: Skip 50-70% of remainder
3. **Empty clip lists**: Skip 20% of airspaces
4. **Direct Int32 path**: Eliminate conversions

**Result:**
- Input: 1344 polygons
- Output: 1079 polygons (265 eliminated)
- Time: 1.5-1.7 seconds

## Stage 5: RENDERING (60fps maintained)

### Display Conversion

```
Clipped Polygons (ClipperData)
→ Convert to LatLng (only for display)
→ Flutter Map Polygons
→ GPU tessellation
```

**Performance:**
- LatLng conversion: 20-30ms
- Widget creation: 10-15ms
- GPU upload: 5-10ms
- Frame time: 16ms (60fps)

### Rendering Pipeline

```
Flutter Map Widget
├── Polygon layer (1079 polygons)
├── Stroke & fill styles
├── GPU tessellation
└── Rasterization
```

**Metrics:**
- Polygons rendered: 1079
- Draw calls: ~100-200
- Frame budget: 16ms
- Actual frame time: 10-14ms

## Data Flow Diagrams

### Complete Pipeline Timing

| Stage | Operation | Time | Notes |
|-------|-----------|------|-------|
| **INGESTION** | | | |
| | Download | 16s | Country data from API |
| | Parse GeoJSON | 2s | Decode & validate |
| | Process features | 2s | Extract properties |
| **DATABASE** | | | |
| | Encode binary | 0.5s | Int32 conversion |
| | Batch insert | 3s | 1800 geometries |
| | Index update | 0.1s | Spatial indices |
| **QUERY** | | | |
| | SQL query | 50ms | Spatial + altitude filter |
| | Load binary | 40ms | 1344 geometries |
| | Create ClipperData | 2ms | Zero-copy views |
| **CLIPPING** | | | |
| | Setup | 5ms | Sorting & prep |
| | Filter checks | 25ms | Altitude + bounds |
| | Clipper2 ops | 1420ms | Actual clipping |
| | Convert results | 50ms | Output format |
| **RENDERING** | | | |
| | To LatLng | 25ms | Display format |
| | Create widgets | 12ms | Flutter polygons |
| | GPU render | 14ms | Per frame |

### Total End-to-End Times

**Initial Data Load (One-time)**
```
Download + Process + Store = 16s + 4s + 3.5s = 23.5s
```

**Runtime Performance (Per Frame)**
```
Query + Clip + Render = 92ms + 1500ms + 51ms = 1643ms
```

**Pan/Zoom Update**
```
Query + Clip + Render = 92ms + 1500ms + 51ms = 1643ms
(Cached geometry, no download needed)
```

## Memory Usage

### Storage
- Database: ~10MB for 3450 airspaces
- Binary format: 75% smaller than JSON
- Indices: ~1MB overhead

### Runtime
- ClipperData: 8 bytes per coordinate
- Display polygons: ~32 bytes per point
- Peak memory: ~50MB for 1344 active polygons

## Code Locations

- **Main service**: `lib/services/airspace_geojson_service.dart`
- **Cache layer**: `lib/services/airspace_disk_cache.dart`
- **Clipping logic**: `_applyPolygonClipping()` at line 1429
- **Direct pipeline**: `_loadAirspacePolygonsFromCacheDirect()` at line 1736
- **ClipperData class**: `lib/data/models/clipper_data.dart`

---

*Last Updated: 2025-01-12*
*Architecture: Int32 binary storage with direct Clipper2 pipeline*
