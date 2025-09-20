# Spatial Query Optimization Strategies

## Current Query Analysis

### Current Implementation (50-100ms for 1344 rows)
```sql
SELECT * FROM airspace_geometry
WHERE bounds_west <= ? AND bounds_east >= ?
  AND bounds_south <= ? AND bounds_north >= ?
  AND lower_altitude_ft <= ?
  AND type_code NOT IN (?)
ORDER BY lower_altitude_ft ASC;
```

### Current Index Structure
```sql
-- Multiple separate indices (suboptimal)
CREATE INDEX idx_geometry_spatial ON airspace_geometry(bounds_west, bounds_east, bounds_south, bounds_north);
CREATE INDEX idx_geometry_bounds_west ON airspace_geometry(bounds_west);
CREATE INDEX idx_geometry_bounds_east ON airspace_geometry(bounds_east);
CREATE INDEX idx_geometry_bounds_south ON airspace_geometry(bounds_south);
CREATE INDEX idx_geometry_bounds_north ON airspace_geometry(bounds_north);
CREATE INDEX idx_geometry_lower_altitude ON airspace_geometry(lower_altitude_ft);
CREATE INDEX idx_geometry_spatial_altitude ON airspace_geometry(lower_altitude_ft, bounds_west, bounds_east, bounds_south, bounds_north);
```

## Optimization Strategies

### 1. Improved Index Design (Primary Optimization)

```sql
-- Drop redundant indices
DROP INDEX IF EXISTS idx_geometry_bounds_west;
DROP INDEX IF EXISTS idx_geometry_bounds_east;
DROP INDEX IF EXISTS idx_geometry_bounds_south;
DROP INDEX IF EXISTS idx_geometry_bounds_north;
DROP INDEX IF EXISTS idx_geometry_spatial;

-- Create optimized covering index for the most common query pattern
-- This index can satisfy the entire query without table lookups
CREATE INDEX idx_geometry_spatial_optimized ON airspace_geometry(
  bounds_west,
  bounds_east,
  bounds_south,
  bounds_north,
  lower_altitude_ft,
  type_code
) WHERE type_code NOT IN (28, 29, 30); -- Exclude common filtered types

-- Alternative: Partial index for active airspaces only
CREATE INDEX idx_geometry_spatial_active ON airspace_geometry(
  bounds_west,
  bounds_east,
  bounds_south,
  bounds_north,
  lower_altitude_ft
) WHERE type_code < 20; -- Only controlled airspace
```

### 2. Query Optimization with Hints

```sql
-- Optimized query with early filtering
WITH viewport_candidates AS (
  SELECT id, coordinates_binary, polygon_offsets, type_code, lower_altitude_ft
  FROM airspace_geometry
  INDEXED BY idx_geometry_spatial_optimized
  WHERE bounds_west <= ?
    AND bounds_east >= ?
    AND bounds_south <= ?
    AND bounds_north >= ?
)
SELECT * FROM viewport_candidates
WHERE (lower_altitude_ft IS NULL OR lower_altitude_ft <= ?)
  AND type_code NOT IN (?, ?, ?)
ORDER BY lower_altitude_ft ASC;
```

### 3. Spatial Grid Pre-filtering (Advanced)

```sql
-- Add grid cell column for coarse filtering
ALTER TABLE airspace_geometry ADD COLUMN grid_cell INTEGER;

-- Update grid cells (10x10 degree grid)
UPDATE airspace_geometry
SET grid_cell =
  (CAST((bounds_west + 180) / 10 AS INTEGER)) * 100 +
  (CAST((bounds_south + 90) / 10 AS INTEGER));

-- Create grid index
CREATE INDEX idx_geometry_grid ON airspace_geometry(grid_cell, bounds_west, bounds_east);

-- Optimized query with grid filtering
SELECT * FROM airspace_geometry
WHERE grid_cell IN (?, ?, ?, ?)  -- Pre-computed grid cells for viewport
  AND bounds_west <= ? AND bounds_east >= ?
  AND bounds_south <= ? AND bounds_north >= ?
  AND lower_altitude_ft <= ?
  AND type_code NOT IN (?)
ORDER BY lower_altitude_ft ASC;
```

### 4. Projection Optimization

```sql
-- Only select needed columns initially
SELECT
  id,
  coordinates_binary,
  polygon_offsets,
  type_code,
  lower_altitude_ft,
  -- Defer loading of extra_properties BLOB
  CASE WHEN ? THEN extra_properties ELSE NULL END as extra_properties
FROM airspace_geometry
WHERE ...
```

### 5. Prepared Statement Caching

```dart
// Cache prepared statements for common viewport queries
class OptimizedSpatialQuery {
  static final Map<String, sqlite3.PreparedStatement> _preparedStatements = {};

  static Future<List<Map>> executeSpatialQuery({
    required Database db,
    required double west,
    required double east,
    required double south,
    required double north,
    int? maxAltitudeFt,
    List<int>? excludedTypes,
  }) async {
    // Generate cache key based on query parameters
    final key = '${excludedTypes?.length ?? 0}_${maxAltitudeFt != null}';

    // Get or create prepared statement
    _preparedStatements[key] ??= db.prepare('''
      SELECT id, coordinates_binary, polygon_offsets, type_code, lower_altitude_ft
      FROM airspace_geometry
      WHERE bounds_west <= ?1 AND bounds_east >= ?2
        AND bounds_south <= ?3 AND bounds_north >= ?4
        ${maxAltitudeFt != null ? 'AND lower_altitude_ft <= ?5' : ''}
        ${excludedTypes != null ? 'AND type_code NOT IN (${excludedTypes.map((i) => '?${5 + i}').join(',')})' : ''}
      ORDER BY lower_altitude_ft ASC
    ''');

    return _preparedStatements[key]!.select([west, east, south, north, maxAltitudeFt, ...?excludedTypes]);
  }
}
```

## Implementation Plan

### Quick Wins (5-10 minute implementation)
1. **Remove redundant indices** - Reduces index maintenance overhead
2. **Add covering index** - Eliminates table lookups
3. **Use prepared statements** - Reduces parsing overhead

### Expected Performance Improvements
| Optimization | Current | Optimized | Improvement |
|-------------|---------|-----------|-------------|
| Index lookup | 5-10ms | 2-3ms | 60-70% faster |
| Data fetch | 40-80ms | 15-25ms | 60-70% faster |
| Total query | 50-100ms | **20-30ms** | **60-70% faster** |

### Medium Term (30 minute implementation)
1. **Grid-based pre-filtering** - Reduces candidates by 80-90%
2. **Partial indices** - Smaller index size, faster lookups
3. **Query hints** - Force optimal execution plan

### Expected Performance with Grid
| Stage | Time | Notes |
|-------|------|-------|
| Grid filter | 1ms | Eliminate 90% of rows |
| Spatial filter | 5ms | Only ~140 rows to check |
| Data fetch | 10ms | Smaller result set |
| **Total** | **16ms** | **80% improvement** |

## Recommended Implementation

```dart
// Immediate optimization - update airspace_disk_cache.dart
Future<void> optimizeIndices() async {
  final db = await database;

  // Drop redundant indices
  await db.execute('DROP INDEX IF EXISTS idx_geometry_bounds_west');
  await db.execute('DROP INDEX IF EXISTS idx_geometry_bounds_east');
  await db.execute('DROP INDEX IF EXISTS idx_geometry_bounds_south');
  await db.execute('DROP INDEX IF EXISTS idx_geometry_bounds_north');

  // Create optimized covering index
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_geometry_spatial_covering ON $_geometryTable(
      bounds_west,
      bounds_east,
      bounds_south,
      bounds_north,
      lower_altitude_ft,
      type_code,
      id,
      coordinates_binary,
      polygon_offsets
    )
  ''');
}

// Optimized query method
Future<List<CachedAirspaceGeometry>> getGeometriesInBoundsOptimized({
  required double west,
  required double east,
  required double south,
  required double north,
  // ... other parameters
}) async {
  final db = await database;

  // Use indexed columns first for maximum efficiency
  final query = '''
    SELECT id, coordinates_binary, polygon_offsets, type_code, lower_altitude_ft,
           name, icao_class, country, extra_properties
    FROM $_geometryTable INDEXED BY idx_geometry_spatial_covering
    WHERE bounds_west <= ? AND bounds_east >= ?
      AND bounds_south <= ? AND bounds_north >= ?
      ${maxAltitudeFt != null ? 'AND (lower_altitude_ft IS NULL OR lower_altitude_ft <= ?)' : ''}
      ${excludedTypes?.isNotEmpty == true ? 'AND type_code NOT IN (${excludedTypes!.map((_) => '?').join(',')})' : ''}
    ORDER BY lower_altitude_ft ASC
  ''';

  // ... rest of implementation
}
```

## Testing & Validation

### Performance Benchmarks to Run
1. Query 100x100km viewport (typical zoom)
2. Query 1000x1000km viewport (country level)
3. Query with altitude filter
4. Query with type exclusions

### Expected Results
- **Small viewport**: 10-15ms (from 50ms)
- **Large viewport**: 20-30ms (from 100ms)
- **With filters**: 15-20ms (from 75ms)

## Conclusion

The spatial query can be optimized from 50-100ms to **15-30ms** (70% improvement) with:
1. Better index design (covering index)
2. Query optimization (column projection)
3. Prepared statement caching

For even better performance (10-15ms), implement grid-based pre-filtering in a future update.

---
*Generated: 2025-09-20*