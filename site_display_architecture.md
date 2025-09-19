# Site Display Architecture - High Level Overview

## Three Map Views in Free Flight Log

### 1. **Nearby Sites Map** (`NearbySitesScreen` + `NearbySitesMapWidget`)
**Purpose:** Discover and explore flying sites near current location or search area

```
┌─────────────────────────────────────────────┐
│           NearbySitesScreen                  │
│  - Manages legend state (expanded/collapsed) │
│  - Handles search via SearchManager          │
│  - Controls map bounds and filters           │
└────────────┬────────────────────────────────┘
             │ passes sites + state
             ▼
┌─────────────────────────────────────────────┐
│         NearbySitesMapWidget                 │
│  - Renders map with sites                    │
│  - Shows MapLegendWidget                     │
│  - Handles airspace overlays                 │
└─────────────────────────────────────────────┘
```

### 2. **Flight Detail Map** (`FlightTrack2DWidget`)
**Purpose:** Show a specific flight's track with nearby sites for context

```
┌─────────────────────────────────────────────┐
│         FlightTrack2DWidget                  │
│  - Loads and displays flight track           │
│  - Shows launch/landing points               │
│  - Custom inline legend (not MapLegendWidget)│
│  - Sites loaded based on track bounds        │
└─────────────────────────────────────────────┘
```

### 3. **Site Editor Map** (`EditSiteScreen`)
**Purpose:** Edit site locations and merge duplicate sites

```
┌─────────────────────────────────────────────┐
│           EditSiteScreen                     │
│  - Drag & drop site markers                  │
│  - Merge duplicate sites                     │
│  - Shows MapLegendWidget                     │
│  - Special merge mode interactions           │
└─────────────────────────────────────────────┘
```

## Unified Site Loading System

All three maps now use the **SiteBoundsLoader** service for consistent site loading:

```
                    ┌──────────────────────┐
                    │  SiteBoundsLoader    │
                    │                      │
                    │ - Caching (5 min)    │
                    │ - Deduplication      │
                    │ - Flight counts      │
                    └──────┬───────────────┘
                           │
                ┌──────────┴──────────┐
                ▼                     ▼
     ┌──────────────────┐   ┌──────────────────┐
     │ DatabaseService   │   │ ParaglidingEarth │
     │                   │   │      API         │
     │ Local DB Sites    │   │ Online Sites     │
     │ (Flown sites)     │   │ (New sites)      │
     └───────────────────┘   └──────────────────┘
                │                     │
                └──────────┬──────────┘
                           ▼
                   ┌──────────────┐
                   │ UnifiedSite  │
                   │   Model      │
                   └──────────────┘
```

## Site Data Flow

### 1. **Bounds Change Trigger**
```
User pans/zooms map
    ↓
onCameraMove event
    ↓
Debounced (750ms)
    ↓
Calculate visible bounds
    ↓
Check if bounds significantly changed (>0.001° threshold)
```

### 2. **Site Loading Process**
```
loadSitesForBounds() called
    ↓
Check cache (5 min TTL)
    ↓ (cache miss)
Parallel fetch:
├─→ DatabaseService.getSitesInBounds()
│     - Returns local Site objects
│     - Includes flight counts
│
└─→ ParaglidingEarthApi.getSitesInBounds()
      - Returns ParaglidingSite objects
      - Limited to prevent overload (30-50 sites)
    ↓
Deduplication (300m radius)
    ↓
Create UnifiedSite objects
    ↓
Return SiteBoundsLoadResult
```

### 3. **Site Display**
```
UnifiedSite list
    ↓
Map to markers using SiteMarkerUtils
    ↓
Color coding:
- Blue: Flown sites (have flights)
- Green: New sites (no flights yet)
- Orange: Launch points
- Red: Landing points
    ↓
Size indicates importance/flight count
```

## Key Components

### Models
- **`Site`**: Local database site (has flights)
- **`ParaglidingSite`**: API site from Paragliding Earth
- **`UnifiedSite`**: Wrapper that can represent either type

### Services
- **`SiteBoundsLoader`**: Centralized site loading with caching
- **`DatabaseService`**: Local SQLite database access
- **`ParaglidingEarthApi`**: External API for worldwide sites

### UI Components
- **`MapLegendWidget`**: Reusable legend (Nearby Sites & Edit Site)
- **`SiteMarkerUtils`**: Consistent marker generation across all maps

## Legend State Management

### Nearby Sites & Edit Site Maps
```
SharedPreferences
    ↓
Screen State (_isLegendExpanded)
    ↓
MapLegendWidget props (isExpanded, onToggleExpanded)
    ↓
Widget renders based on external state
```

### Flight Detail Map
```
SharedPreferences
    ↓
FlightTrack2DWidget State (_isLegendExpanded)
    ↓
Custom inline legend implementation
```

## Site Categories

1. **Flown Sites** (Blue markers)
   - Sites from local database
   - Have associated flight records
   - Show flight count indicators

2. **New Sites** (Green markers)
   - Sites from Paragliding Earth API
   - No local flight records
   - Potential flying locations

3. **Launch/Landing** (Orange/Red markers)
   - Special markers on flight detail maps
   - Calculated from IGC track data
   - May or may not correspond to known sites

## Performance Optimizations

- **Debouncing**: 750ms delay before loading after map movement
- **Caching**: 5-minute cache for loaded site bounds
- **Limits**: API calls limited to 30-50 sites to prevent overload
- **Deduplication**: Sites within 300m merged to reduce clutter
- **Loading indicators**: Show after 500ms to prevent flashing

## State Persistence

- Map provider selection (OpenStreetMap, Satellite, etc.)
- Legend expanded/collapsed state
- Filter settings (altitude limits, ICAO classes)
- All stored in SharedPreferences and restored on app launch