# Local Sites Database Schema Design

## New Table: `pge_sites`

```sql
CREATE TABLE pge_sites (
  id INTEGER PRIMARY KEY,                    -- PGE site ID
  name TEXT NOT NULL,                        -- Site name
  latitude REAL NOT NULL,                    -- Coordinates
  longitude REAL NOT NULL,
  altitude INTEGER,                          -- Takeoff altitude in meters
  country_code TEXT,                         -- ISO country code (au, fr, etc.)
  country TEXT,                              -- Full country name
  place TEXT,                                -- Site description/type
  takeoff_description TEXT,                  -- Detailed takeoff info

  -- Wind direction ratings (0=no good, 1=good, 2=excellent)
  wind_n INTEGER DEFAULT 0,
  wind_ne INTEGER DEFAULT 0,
  wind_e INTEGER DEFAULT 0,
  wind_se INTEGER DEFAULT 0,
  wind_s INTEGER DEFAULT 0,
  wind_sw INTEGER DEFAULT 0,
  wind_w INTEGER DEFAULT 0,
  wind_nw INTEGER DEFAULT 0,

  -- Site capabilities (0=no, 1=yes)
  paragliding INTEGER DEFAULT 0,
  hanggliding INTEGER DEFAULT 0,
  thermals INTEGER DEFAULT 0,
  soaring INTEGER DEFAULT 0,
  winch INTEGER DEFAULT 0,
  xc INTEGER DEFAULT 0,
  flatland INTEGER DEFAULT 0,

  -- Landing coordinates (if different from takeoff)
  landing_lat REAL,
  landing_lng REAL,

  -- Parking coordinates
  takeoff_parking_lat REAL,
  takeoff_parking_lng REAL,
  landing_parking_lat REAL,
  landing_parking_lng REAL,

  -- PGE metadata
  pge_link TEXT,                             -- Link to PGE site page
  last_edit TEXT,                            -- Last modified on PGE
  ffvl_site_id INTEGER DEFAULT 0,           -- FFVL cross-reference

  -- Local metadata
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Spatial indexes for fast geographic queries
CREATE INDEX idx_pge_sites_spatial ON pge_sites(latitude, longitude);
CREATE INDEX idx_pge_sites_country ON pge_sites(country_code);
CREATE INDEX idx_pge_sites_capabilities ON pge_sites(paragliding, hanggliding);
CREATE INDEX idx_pge_sites_wind ON pge_sites(wind_n, wind_ne, wind_e, wind_se, wind_s, wind_sw, wind_w, wind_nw);

-- Metadata table for download tracking
CREATE TABLE pge_sites_metadata (
  id INTEGER PRIMARY KEY,
  download_url TEXT NOT NULL,                -- Google Drive URL
  downloaded_at TEXT,                        -- Last download timestamp
  file_size_bytes INTEGER,                   -- Compressed file size
  sites_count INTEGER,                       -- Number of sites imported
  index_size_bytes INTEGER,                  -- Database index size
  version TEXT,                              -- Data version/hash
  status TEXT DEFAULT 'pending'             -- pending, downloading, completed, error
);
```

## Query Performance Optimization

### Bounding Box Query (Primary Use Case)
```sql
-- Fast spatial query for map bounds
SELECT * FROM pge_sites
WHERE latitude BETWEEN ? AND ?
  AND longitude BETWEEN ? AND ?
  AND paragliding = 1
LIMIT 100;
```

### Wind Direction Filtering
```sql
-- Sites suitable for specific wind directions
SELECT * FROM pge_sites
WHERE latitude BETWEEN ? AND ?
  AND longitude BETWEEN ? AND ?
  AND (wind_w >= 1 OR wind_sw >= 1)  -- Good westerly conditions
LIMIT 50;
```

### Site Search by Name
```sql
-- Text search with spatial proximity
SELECT *,
       (ABS(latitude - ?) + ABS(longitude - ?)) as distance_score
FROM pge_sites
WHERE name LIKE '%' || ? || '%'
  AND paragliding = 1
ORDER BY distance_score
LIMIT 20;
```

## Storage Estimates

- **11,438 sites** × ~500 bytes/site = **~5.7MB** uncompressed
- **Spatial indexes**: ~1-2MB additional
- **Total database size**: ~8MB (vs 7.8MB JSON download)
- **Query performance**: Sub-millisecond for bounding box queries

## Migration Strategy

1. **Phase 1**: Add new tables alongside existing schema
2. **Phase 2**: Implement download service and populate data
3. **Phase 3**: Modify services to use local data
4. **Phase 4**: Keep API for detailed site information only

## Constants for Configuration

```dart
class PgeSitesConfig {
  // Download URL - easily changeable
  static const String downloadUrl = 'https://drive.google.com/file/d/1cfCns9cihiJqLJZbiDJGOy1qeLZIW_h7/view?usp=drive_link';

  // Cache settings
  static const Duration maxAge = Duration(days: 30);
  static const int maxSitesPerQuery = 100;
  static const double spatialTolerance = 0.001; // ~100m for matching
}
```