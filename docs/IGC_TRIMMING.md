# IGC Data Trimming Architecture

## Core Principle: Single Source of Truth for Flight Data

**The fundamental rule: ALL app code must work with trimmed data (takeoff to landing). Untrimmed data exists only in the source IGC file for archival purposes.**

## Data Flow Architecture

```
IGC File (Full/Archival) → Detection → Store Full Indices → Load Trimmed → App Uses Zero-Based
```

1. **IGC File Storage**: Store complete, unmodified IGC files for archival
2. **Detection**: Automatically detect takeoff/landing points using speed and climb rate thresholds
3. **Database Storage**: Store detection indices relative to **full IGC file** coordinates
4. **Runtime Loading**: `FlightTrackLoader` provides trimmed data with zero-based indices to all app code
5. **App Operations**: All calculations, visualizations, and analysis work on trimmed data only

## Implementation

### FlightTrackLoader (Single Source of Truth)
- **Location**: `lib/services/flight_track_loader.dart`
- **Purpose**: Centralized service ensuring all flight operations use consistent trimmed data
- **Key Method**: `FlightTrackLoader.loadFlightTrack(flight)` - returns `IgcFile` with trimmed track points
- **Caching**: LRU cache for parsed IGC files to optimize performance
- **Fallback**: Returns full track only if detection completely fails

### Index Coordinate Systems
- **Database Indices**: Always stored relative to full IGC file (e.g., `takeoffIndex: 150`, `landingIndex: 1200`)
- **App Runtime Indices**: Always zero-based relative to trimmed data (e.g., closing point at index 45 in a 200-point trimmed track)
- **Conversion**: When storing indices calculated on trimmed data, convert to full coordinates: `trimmedIndex + takeoffIndex`

### Detection Data Storage
Flight model stores detection results:
```dart
class Flight {
  int? takeoffIndex;    // Index in full IGC file
  int? landingIndex;    // Index in full IGC file  
  DateTime? detectedTakeoffTime;
  DateTime? detectedLandingTime;
  bool get hasDetectionData => takeoffIndex != null && landingIndex != null;
}
```

## Best Practices

### For App Code
- **Always use `FlightTrackLoader.loadFlightTrack()`** to get flight data
- **Never parse IGC files directly** in UI or business logic
- **Assume all track data is zero-based and trimmed** when received from FlightTrackLoader
- **Trust the single source of truth** - don't implement custom trimming logic

### For New Features
- **Start with FlightTrackLoader**: Get trimmed data first
- **No index adjustments needed**: Work with zero-based indices directly
- **Store full coordinates**: If storing indices to database, convert from trimmed to full coordinates

### Deprecated Patterns
- ❌ **Direct IGC parsing in widgets**: Use FlightTrackLoader instead
- ❌ **Manual index adjustments**: FlightTrackLoader handles trimming automatically  
- ❌ **Custom trimming logic**: Central service eliminates need for scattered trimming code
- ❌ **Mixed coordinate systems**: All app code works with zero-based trimmed indices

## Key Services

- **`FlightTrackLoader`**: Single source of truth for flight track data
- **`TakeoffLandingDetector`**: Automatic detection using configurable thresholds
- **`IgcParser`**: Low-level IGC file parsing (used by FlightTrackLoader)
- **`IgcImportService`**: Creates flights with detection data during import

## Example Usage

```dart
// ✅ Correct: Use FlightTrackLoader
final igcFile = await FlightTrackLoader.loadFlightTrack(flight);
// igcFile.trackPoints is already trimmed and zero-based

// ✅ Correct: Calculate on trimmed data
final distance = igcFile.calculateGroundTrackDistance(); 
final triangleData = igcFile.calculateFaiTriangle();

// ✅ Correct: Store index relative to full IGC file
if (closingPointIndex != null && flight.hasDetectionData) {
  final fullCoordinateIndex = closingPointIndex + flight.takeoffIndex!;
  // Store fullCoordinateIndex to database
}
```

This architecture ensures:
- **Consistency**: All app features work with the same trimmed representation
- **Performance**: LRU caching prevents repeated parsing
- **Simplicity**: No index confusion or coordinate system mixing
- **Archival**: Original IGC files preserved for compliance and re-processing