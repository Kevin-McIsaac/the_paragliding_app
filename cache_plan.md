# Optimize Airspace Tile Caching System

## Problem Analysis

1. **Duplication**: Large airspaces (e.g., Class A covering entire countries) are stored redundantly across multiple tiles
2. **Wasted Space**: Many tiles are empty (oceans, remote areas) but still consume cache slots
3. **Memory Constraints**: Limited to 200 tiles in memory (~2.5MB), no persistence

## Optimization Strategy

### Phase 1: Hierarchical Object Cache

- Create separate caches for airspace geometries and tile metadata
- **AirspaceGeometryCache**: Store unique airspace objects by ID (deduped)
- **AirspaceMetadataCache**: Store lightweight tile → airspace ID mappings
- Benefits: ~70% memory reduction by eliminating polygon duplication

### Phase 2: Disk Persistence Layer

- Add SQLite-based cache for persistent storage
- Direct disk operations with SQLite's built-in page caching
- Cache airspace data for 7-30 days (configurable)
- Benefits: Instant app startup, offline capability, simpler architecture

### Phase 3: Smart Compression

- Compress GeoJSON with gzip in cache (70-90% size reduction)
- Store empty tiles as simple flags instead of full GeoJSON
- Benefits: 5-10x more data in same memory footprint

### Phase 4: Performance Monitoring

- Add detailed metrics for cache efficiency
- Track duplication rates, empty tile percentage
- Implement automatic cache tuning based on usage patterns

## Implementation Plan

1. Create new cache model classes
2. Implement hierarchical caching with geometry/metadata separation
3. Integrate disk persistence layer
4. Add compression pipeline
5. Update AirspaceGeoJsonService to use new cache
6. Add performance logging and metrics
7. Test with real-world data patterns

## Expected Results

- **70% reduction** in memory usage from deduplication
- **5-10x** more effective cache capacity with compression
- **Instant** map loads for previously visited areas
- **Offline** capability for cached regions

---

## Phase 1: Hierarchical Object Cache - Detailed Design

### Simplified Architecture

The cache system uses SQLite directly without a separate memory tier:

- SQLite handles its own page caching efficiently (~2MB by default)
- No need for complex hot/cold cache synchronization
- Direct queries to SQLite are fast enough (5-20ms) for UI responsiveness

### Current Problem: Duplication Example

Consider a large Class A airspace like "FRANCE UIR" that spans from 5°W to 9°E and 42°N to 51°N:

- At zoom level 8, this covers approximately **40 tiles**
- The polygon data (potentially 1000+ coordinate pairs) is **duplicated 40 times**
- Memory usage: 40 tiles × ~50KB per copy = **2MB for one airspace**

### Proposed Solution: Separation of Concerns

#### AirspaceGeometryCache (SQLite Table)

**Purpose**: Store the actual airspace polygon data once in SQLite, indexed by unique ID

**Contents**:

```dart
class CachedAirspaceGeometry {
  final String id;           // Unique OpenAIP ID (e.g., "60c8f3b2a7c4e90007a5d8e1")
  final String name;          // "FRANCE UIR"
  final String type;          // "UIR", "CTR", "TMA", etc.
  final List<List<LatLng>> polygons;  // Actual coordinate data
  final Map<String, dynamic> properties;  // Altitude limits, ICAO class, etc.
  final DateTime fetchTime;   // When this was fetched from API
  final String geometryHash;  // Hash of coordinates for change detection
}
```

**Key characteristics**:

- Single instance per unique airspace
- Indexed by OpenAIP `_id` field
- Contains full polygon geometry
- Stored in SQLite with compression
- TTL-based expiration (7 days)

#### AirspaceMetadataCache (SQLite Table)

**Purpose**: Map tiles to airspace IDs without storing geometry in SQLite

**Contents**:

```dart
class TileMetadata {
  final String tileKey;       // "8_132_89" (zoom_x_y)
  final Set<String> airspaceIds;  // IDs of airspaces in this tile
  final DateTime fetchTime;   // When this tile was fetched
  final int airspaceCount;    // Number of airspaces (for density)
  final bool isEmpty;         // Quick flag for empty tiles
}
```

**Key characteristics**:

- Lightweight (~100 bytes per tile vs ~10KB+ currently)
- References geometry by ID only
- Can track tile statistics
- Enables quick empty tile detection

### How They Work Together

#### Fetch Flow

1. **Request viewport** → Calculate required tiles
2. **Query SQLite TileMetadata** → Get list of airspace IDs per tile
3. **Query SQLite GeometryCache** → Load actual polygons by ID
4. **Fetch missing data** → API call only for uncached geometries
5. **Store in SQLite** → Geometry in one table, tile mapping in another

#### Memory Savings Example

```text
Current approach (France UIR across 40 tiles):
- 40 tiles × 50KB = 2000KB

New approach:
- 1 geometry × 50KB = 50KB
- 40 tile metadata × 0.1KB = 4KB
- Total: 54KB (97% reduction!)
```

### Additional Benefits

#### 1. **Change Detection**

- Geometry hash allows detecting when airspace boundaries change
- Can update single airspace without invalidating all tiles

#### 2. **Prefetching**

- Can fetch adjacent tile metadata without loading full geometry
- Enables smooth map panning

#### 3. **Statistics**

- Track which airspaces are viewed most
- Identify high-density areas for optimization
- Monitor empty tile percentage

#### 4. **Partial Updates**

- Update individual airspaces when regulations change
- Refresh tile mappings without re-fetching all geometry

#### 5. **Automatic Cleanup**

- TTL-based expiration (7 days for geometries, 1 day for tiles)
- Periodic vacuum to reclaim disk space
- Optional manual cache clearing

### Implementation Considerations

#### ID Strategy

- Use OpenAIP `_id` field as primary key
- Fallback: Generate hash from `name + type + country` for items without ID
- Handle ID changes in API updates

#### Viewport Clipping

- Still clip geometries to viewport for rendering
- But source data comes from deduplicated cache
- Clipping happens at render time, not storage time

#### Cache Invalidation

- Tile metadata: 24 hours (current)
- Geometry: 7 days (less frequent changes)
- Manual refresh option for users

#### Database Access

- SQLite handles concurrent reads efficiently
- Single write connection to prevent conflicts
- Async queries to prevent UI blocking
- SQLite's built-in page cache handles frequently accessed data
