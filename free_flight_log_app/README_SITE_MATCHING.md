# Paragliding Site Matching Feature

This document describes the paragliding site name lookup feature that automatically identifies launch and landing sites from GPS coordinates.

## Overview

Instead of generic coordinate-based names like "Launch 47.377°N 8.542°E", the app now displays proper paragliding site names like "Interlaken - Beatenberg" when importing IGC files.

## Implementation

### 1. **ParaglidingSite Model** (`lib/data/models/paragliding_site.dart`)
- Complete data model for paragliding sites
- Includes name, coordinates, altitude, wind directions, rating, country
- Distance calculation methods using Haversine formula
- JSON serialization for loading from assets

### 2. **KML Parser** (`lib/services/kml_parser.dart`)  
- Parses KML files from Paraglidingearth.com
- Extracts site information including ratings and wind directions
- Filters to most popular sites based on popularity score
- Handles various KML formats and extended data

### 3. **Site Matching Service** (`lib/services/site_matching_service.dart`)
- Loads popular paragliding sites from JSON asset file
- Fast coordinate-based site matching (500m for launches, 1km for landings)
- Search functionality by name, country, region
- Fallback to coordinate formatting when no match found

### 4. **IGC Import Integration** (`lib/services/igc_import_service.dart`)
- Automatically queries site matching during IGC import
- Uses proper site names instead of generic coordinates
- Maintains existing fallback behavior for unknown locations

### 5. **Development Tool** (`tools/site_data_processor.dart`)
- Downloads KML files from Paraglidingearth.com
- Processes and filters to top 1000 most popular sites worldwide
- Generates JSON asset file for the app
- Provides statistics and site analysis

## Usage

### Automatic Site Detection
When importing IGC files, the app automatically:
1. Extracts launch/landing coordinates from the track
2. Searches for nearby paragliding sites within tolerance
3. Uses the site name if found, otherwise falls back to coordinates

### Manual Site Lookup
The `SiteMatchingService` provides methods for:
```dart
// Find nearest launch site
final site = SiteMatchingService.instance.findNearestLaunchSite(lat, lon);

// Search by name
final results = SiteMatchingService.instance.searchByName("Interlaken");

// Get site name suggestion
final name = SiteMatchingService.instance.getSiteNameSuggestion(lat, lon);
```

## Data Source

### Paraglidingearth.com
- **Coverage**: 16,000+ sites worldwide
- **Data Quality**: Community-verified with ratings and descriptions
- **Format**: KML files by region (Europe, North America, etc.)
- **Update Frequency**: Sites can be updated by running the development tool

### Curated Database
- **Size**: Top 1000 most popular sites (~500KB JSON file)
- **Criteria**: Based on ratings, popularity scores, and geographic distribution
- **Storage**: Local asset file for offline operation
- **Performance**: Fast in-memory lookup, no API calls needed

## Site Matching Logic

### Launch Sites
- **Search Radius**: 500 meters (precise matching)
- **Priority**: Sites marked as 'launch' or 'both'
- **Fallback**: Generic "Launch [coordinates]" if no match

### Landing Sites  
- **Search Radius**: 1000 meters (more flexible)
- **Priority**: Sites marked as 'landing' or 'both'
- **Fallback**: Generic "Landing [coordinates]" if no match

### Popularity Scoring
Sites are ranked by:
- User ratings (1-5 stars)
- Description detail level
- Available metadata (wind directions, altitude)
- Community usage indicators

## Development Workflow

### Updating Site Database
```bash
# Download latest KML files and generate asset
cd free_flight_log_app
dart run tools/site_data_processor.dart --download

# Copy generated file to assets
cp popular_paragliding_sites.json assets/
```

### Adding Custom Sites
Sites can be added manually to the JSON file or by modifying the processor to include additional sources.

## Example Results

**Before (Generic Coordinates):**
- Launch 46.695°N 7.987°E
- Landing 46.677°N 7.864°E

**After (Site Names):**
- Interlaken - Beatenberg
- Interlaken Landing Field

## Benefits

1. **Better UX**: Meaningful site names instead of coordinates
2. **Local Knowledge**: Leverages community-verified site database  
3. **Offline**: No internet required after initial app install
4. **Performance**: Fast local lookup vs API calls
5. **Accuracy**: Paragliding-specific sites vs generic geocoding
6. **Comprehensive**: Global coverage with 1000+ popular sites

## Future Enhancements

- Add site descriptions and wind information to flight details
- Implement site ratings display
- Add "nearby sites" feature for flight planning
- Include landing field recommendations based on wind conditions
- Expand database to include more regional sites