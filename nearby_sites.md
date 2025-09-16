# Nearby Sites Display - Rendering Process Overview

## Key Steps in Rendering the Display

The nearby sites feature implements a sophisticated bounds-based loading pattern that dynamically fetches and displays paragliding sites and airspace data based on the current map view.

### 1. Initial Load & Setup (`NearbySitesScreen.initState`)

- Load user preferences (map provider, legend state)
- Load filter settings (excluded ICAO classes)
- Get initial map center using fallback hierarchy:
  - Current user location
  - Last known location from previous session
  - Default fallback (Perth, Australia)
- Initialize empty site lists and search manager

### 2. Map Widget Initialization (`NearbySitesMapWidget.initState`)

- Load airspace enabled/disabled status from preferences
- Schedule post-frame callback to load airspace layers
  - Ensures MapController is ready before attempting to fetch data
- Initialize zoom level tracking

### 3. Bounds-Based Site Loading

Triggered by map movements (`_onMapEvent`):

- **Debouncing**: 750ms delay to avoid excessive API calls
- **Threshold check**: Minimum 0.001° change required
- **Parallel data fetching**:
  - **Local sites** from SQLite database (`DatabaseService.getSitesInBounds`)
  - **API sites** from ParaglidingEarth (`ParaglidingEarthApi.getSitesInBounds`)
- **Data merging**:
  - Match API sites with local sites to determine flight status
  - Create unified site list with flight tracking
  - Handle sites that exist only locally or only in API
- Update displayed sites through search/filter state

### 4. Airspace Loading (`_loadAirspaceLayers`)

Triggered by map movements or filter changes:

- Check if airspace is enabled in user preferences
- Get current map bounds and zoom level
- **API Request** (`AirspaceGeoJsonService.fetchAirspaceGeoJson`):
  - OpenAIP Core API endpoint: `/api/airspaces`
  - Geographic filtering via bbox parameter
  - API key authentication as query parameter
  - Returns GeoJSON FeatureCollection
- **Data Processing**:
  - Filter by user preferences (type/class exclusions)
  - Filter by altitude (max altitude setting)
  - Optional polygon clipping to reduce complexity
  - Convert to Flutter Map polygons with type-specific styling
- Cache results for performance

### 5. Rendering Layers (`NearbySitesMapWidget.build`)

Map layers rendered in order (bottom to top):

1. **Tile Layer** - Base map tiles (OpenStreetMap/Satellite/Terrain)
2. **Airspace Polygons** - Semi-transparent colored overlays
   - Color-coded by airspace type
   - Opacity indicates restriction level
3. **Site Markers** - Clustered markers for paragliding sites:
   - Green markers: Sites with logged flights
   - Orange markers: New/unvisited sites
   - Clustering at lower zoom levels for performance
4. **User Location** - Blue dot with accuracy circle
5. **Controls & Overlays**:
   - Search bar with autocomplete dropdown
   - Filter FAB with active filters indicator
   - Expandable legend showing marker meanings
   - Loading indicators for dynamic content
   - Hover/tap tooltips for airspace information

### 6. User Interaction Processing

- **Site selection** → Display detailed dialog with tabbed information
- **Airspace hover** → Show tooltip with airspace details and restrictions
- **Search interaction**:
  - API query to ParaglidingEarth
  - Pin selected result
  - Smooth jump to location
- **Filter changes** → Selective reload of affected layers
- **Map movement** → Trigger bounds-based loading cycle

### 7. Performance Optimizations

- **Debouncing**:
  - Map movements: 750ms
  - Hover events: 200ms
  - Search queries: 500ms
- **Caching**:
  - Airspace data by bounds key
  - Site data by geographic bounds
  - Search results for session
- **Lazy Loading**:
  - Only fetch data for visible map area
  - Progressive loading as user pans/zooms
- **Clustering**:
  - Sites grouped at zoom levels < 10
  - Dynamic cluster radius based on zoom
- **Polygon Simplification**:
  - Optional Clipper2 library usage
  - Reduces complex airspace boundaries
  - Maintains visual accuracy while improving performance

## Data Flow Architecture

```
User Action (pan/zoom/filter)
    ↓
Debounce Timer (750ms)
    ↓
Bounds Calculation
    ↓
Parallel Fetch:
├── Site Data
│   ├── Local DB Query
│   └── ParaglidingEarth API
└── Airspace Data
    └── OpenAIP API
    ↓
Data Processing:
├── Merge & Filter Sites
├── Apply Airspace Filters
└── Generate Map Layers
    ↓
Render Update
```

## Key Components

### Services

- `DatabaseService` - Local SQLite operations
- `ParaglidingEarthApi` - External site data API
- `AirspaceGeoJsonService` - OpenAIP airspace fetching
- `OpenAipService` - User preferences and API key management
- `LocationService` - GPS and location fallback hierarchy

### Widgets

- `NearbySitesScreen` - Main screen container and state management
- `NearbySitesMapWidget` - Map rendering and interaction handling
- `MapFilterDialog` - Filter configuration UI
- `AirspaceTooltipWidget` - Contextual airspace information

### Managers

- `NearbySitesSearchManager` - Search state and autocomplete
- `AirspaceOverlayManager` - Airspace layer coordination

## Critical Design Decisions

1. **Bounds-based Loading**: Rather than loading all data upfront, the app dynamically fetches only what's visible, balancing responsiveness with API efficiency.

2. **Parallel Data Sources**: Sites come from both local database (flown sites) and external API (all sites), merged intelligently to show flight history.

3. **Progressive Enhancement**: Core functionality works without API keys, with additional features (airspace, detailed info) enabled when configured.

4. **Smart Caching**: Geographic bounds are used as cache keys, preventing redundant API calls for previously viewed areas.

5. **User-Centric Defaults**: Location fallback hierarchy ensures the map always shows a relevant area, even without GPS permission.
