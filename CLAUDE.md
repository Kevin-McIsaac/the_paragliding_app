# CLAUDE.md

## Project Overview

Free Flight Log is a free, android first, cross-platform application for
logging, reporting, and visualising paraglider, hang glider, and microlight flights. This repository contains:

- **Complete Flutter Application**: Fully functional flight logbook capabilities
- **Planning Documents** (for reference):
  - [Functional requirements](documentation/FUNCTIONAL_SPECIFICATION.md)
  - [Technical architecture](documentation/TECHNICAL_DESIGN.md)

## Flutter Commands ( Recommended for Claude)

Use the enhanced controller with comprehensive logging and monitoring capabilities:

```bash
# Always run from current location. 
# Script location: /home/kmcisaac/flutter/bin/flutter_controller_enhanced.sh

# Start Flutter with full logging
flutter_controller_enhanced.sh run [device]

# Control commands (send to running Flutter)
flutter_controller_enhanced.sh r      # Hot reload
flutter_controller_enhanced.sh R      # Hot restart
flutter_controller_enhanced.sh q      # Quit

# Monitoring and debugging commands
flutter_controller_enhanced.sh status          # Check app status
flutter_controller_enhanced.sh logs [lines]    # Show recent logs. To optimise context window use this rather than bash shell output.
flutter_controller_enhanced.sh monitor         # Watch logs real-time
flutter_controller_enhanced.sh restart [device] # Force restart
flutter_controller_enhanced.sh cleanup         # Clean up processes
```

### Log Files for Claude Integration

The enhanced controller creates log files that Claude can read:
- **Output Log**: `/tmp/flutter_controller/flutter_output.log` - All Flutter output and app logs
- **Status File**: `/tmp/flutter_controller/flutter_status` - Current app status and timestamp
- **PID File**: `/tmp/flutter_controller/flutter.pid` - Process ID for monitoring

### Example Claude Usage

```bash
# Start Flutter in background
flutter_controller_enhanced.sh run

# Check status and logs
flutter_controller_enhanced.sh status
flutter_controller_enhanced.sh logs 50

# Send commands
flutter_controller_enhanced.sh r  # Hot reload
```

## Key Files Structure

### **Main Entry & Core**

- `lib/main.dart` - App entry point
- `lib/data/datasources/database_helper.dart` - Low-level database operations
- `lib/services/database_service.dart` - Main database service layer
- `assets/cesium/cesium.js` - Cesium 3D map integration

### **Screens** (main app screens)

- `lib/presentation/screens/flight_list_screen.dart` - Main flight list
- `lib/presentation/screens/flight_detail_screen.dart` - Individual flight details
- `lib/presentation/screens/add_flight_screen.dart` / `edit_flight_screen.dart` - Flight creation/editing
- `lib/presentation/screens/igc_import_screen.dart` - IGC file import
- `lib/presentation/screens/statistics_screen.dart` - Flight statistics
- `lib/presentation/screens/manage_sites_screen.dart` / `edit_site_screen.dart` - Site management
- `lib/presentation/screens/wing_management_screen.dart` / `edit_wing_screen.dart` - Wing management
- `lib/presentation/screens/preferences_screen.dart` - App settings
- `lib/presentation/screens/data_management_screen.dart` - Data management and backup settings
- `lib/presentation/screens/about_screen.dart` - App information and credits
- `lib/presentation/screens/flight_track_3d_fullscreen.dart` - 3D flight track fullscreen view
- `lib/presentation/screens/flight_track_3d_screen.dart` - 3D flight track display
- `lib/presentation/screens/cesium_settings_demo_screen.dart` - Cesium settings demonstration
- `lib/presentation/screens/splash_screen.dart` - App startup screen

### **Services** (core business logic)

- `lib/services/igc_parser.dart` - IGC file parsing
- `lib/services/igc_import_service.dart` - IGC import workflow
- `lib/services/paragliding_earth_api.dart` - External API integration
- `lib/services/site_matching_service.dart` / `site_merge_service.dart` - Site management logic
- `lib/services/timezone_service.dart` - Timezone handling
- `lib/services/logging_service.dart` - App logging
- `lib/services/backup_diagnostic_service.dart` - Backup diagnostics and file analysis
- `lib/services/cesium_token_validator.dart` - Cesium token validation and management
- `lib/services/claude_log_printer.dart` - Claude-optimized log formatting
- `lib/services/flight_track_loader.dart` - Central flight track loading and caching
- `lib/services/igc_cleanup_service.dart` - IGC file cleanup and orphan detection
- `lib/services/takeoff_landing_detector.dart` - Automatic flight phase detection

### **Models** (data structures)

- `lib/data/models/flight.dart` - Flight data model
- `lib/data/models/site.dart` / `paragliding_site.dart` - Site models
- `lib/data/models/wing.dart` - Wing/equipment model
- `lib/data/models/igc_file.dart` - IGC file structure

### **Widgets** (reusable UI components)

- `lib/presentation/widgets/flight_track_2d_widget.dart` - 2D flight visualization
- `lib/presentation/widgets/flight_track_3d_widget.dart` - 3D flight visualization
- `lib/presentation/widgets/flight_statistics_widget.dart` - Statistics display
- `lib/utils/site_marker_utils.dart` - Site marker utilities

### **Common Widget Components** (shared UI elements)

- `lib/presentation/widgets/common/app_empty_state.dart` - Empty state displays with consistent styling
- `lib/presentation/widgets/common/app_error_state.dart` - Error state displays with retry functionality
- `lib/presentation/widgets/common/app_expansion_card.dart` - Reusable expansion cards with state management
- `lib/presentation/widgets/common/app_loading_skeleton.dart` - Loading skeleton placeholders
- `lib/presentation/widgets/common/app_stat_card.dart` - Statistics card displays with consistent theming
- `lib/presentation/widgets/common/app_stat_row.dart` - Statistics row displays for data presentation

### **Theme System**

- `lib/presentation/theme/app_card_theme.dart` - Centralized card theming and styling consistency

## UI Cards and Key Functionality Locations

### **Flight List Screen** (`lib/presentation/screens/flight_list_screen.dart`)
- **Statistics Cards**: Uses `AppStatCard.flightList()` and `AppStatCardGroup.flightList()` - Shows flight count and total time (top of screen)
- **Empty State**: Uses `AppEmptyState.flights()` - When no flights are present
- **Loading State**: Uses skeleton loading for better UX
- **Flight Items**: Individual flight entries in ListView with sorting capabilities via `FlightSortingUtils`

### **Flight Detail Screen** (`lib/presentation/screens/flight_detail_screen.dart`)
- **Flight Details Card**: Main expandable card with overview, sites, and equipment info
- **Flight Statistics Card**: Expandable card with performance statistics (if track log exists)
- **Flight Track Card**: Expandable card with 2D/3D visualization (if track log exists)
- **Notes Card**: `_buildNotesCard()` - Flight notes and comments

### **Statistics Screen** (`lib/presentation/screens/statistics_screen.dart`)
- **Multiple Statistics Cards**: Three main cards showing various flight statistics and charts

### **Wing Management Screen** (`lib/presentation/screens/wing_management_screen.dart`)
- **Wing Cards**: `_buildWingCard()` - Individual wing information cards
- **Active Wings Section**: Cards for currently active wings
- **Inactive Wings Section**: Grayed-out cards for inactive wings

### **Sites Management Screen** (`lib/presentation/screens/manage_sites_screen.dart`)
- **Site Cards**: Individual site information cards with ListTile layout

### **Preferences Screen** (`lib/presentation/screens/preferences_screen.dart`)
- **Settings Sections**: `_buildSection()` - Expandable cards for different preference categories

### **Data Management Screen** (`lib/presentation/screens/data_management_screen.dart`)
- **Uses `AppExpansionCard.dataManagement()` Pattern**: All cards follow consistent expansion pattern with state management
- **Map Cache Statistics Card**: Expandable card showing cache info with `CardExpansionManager`
- **Android Backup Status Card**: Expandable card for backup management using `BackupDiagnosticService`
- **IGC File Cleanup Card**: Expandable card for file management using `IgcCleanupService`
- **ParaglidingEarth API Card**: Expandable card for API integration
- **Free Premium Maps Card**: Expandable card for map provider settings
- **Database Management Card**: Expandable card for database operations

### **IGC Import Screen** (`lib/presentation/screens/igc_import_screen.dart`)
- **File Selection Card**: Upload and file picker interface
- **Import Progress Card**: Shows import status and progress
- **Error Display Card**: Red-themed card for import errors
- **Import Results Card**: Summary of imported flights

### **Edit Wing Screen** (`lib/presentation/screens/edit_wing_screen.dart`)
- **Basic Information Card**: Wing details (manufacturer, model, size, etc.)
- **Purchase Information Card**: Purchase date, price, seller details
- **Status and Notes Card**: Active status and additional notes

### **About Screen** (`lib/presentation/screens/about_screen.dart`)
- **App Info Card**: Version, description, and app details
- **Contact Information Card**: Developer contact and OSM compliance info

### **Utils/Helpers** (utility functions)

- `lib/utils/date_time_utils.dart` - Date/time utilities
- `lib/utils/ui_utils.dart` - UI helper functions
- `lib/utils/file_sharing_handler.dart` - File sharing logic
- `lib/utils/build_info.dart` - Build information and version utilities
- `lib/utils/card_expansion_manager.dart` - Card expansion state management across screens
- `lib/utils/flight_sorting_utils.dart` - Flight list sorting utilities with multiple criteria
- `lib/utils/import_error_helper.dart` - Import error handling and user-friendly messaging
- `lib/utils/performance_monitor.dart` - Performance monitoring and metrics collection
- `lib/utils/cache_utils.dart` - Caching utilities for performance optimization

## Core Principles

- **Keep it Simple**: This is a simple app with a few screen and typically less than 5,000 flights, 100 sites and 10 wings. Choose simple, proven solutions over complex architectures
- **State Management**: Keep state simple - this app has <10 screens
- **Database**: Keep database managment simple, this app has < 10 tables, and the largest table will have < 5000 rows
- **Idomatic**: Look for solutions that are idomatic to the language/tool, e.g., Flutter, Cesium and Javascript, especially large data handling code.
- **WebView Constraints**: WebView has limitations (no ES6 modules, single JS context). Work within them.
- **Error Recovery**: Add fallbacks for external services (maps, network)
- **Performance Measurement**: Measure performance before optimizing. Add monitoring to debug logs, then make informed decisions from app testing.
- **App Testing**: Test app changes by:
  - Adding logging that helps with understanding app usage, performance and diagnoing errors.
  - Runing the app in the bash tool on the emulator and telling the user what to do.
  - When requested by the user, reviewing the logs in the bash shell output for:
    - errors,
    - ways to improve efficency and performance,
    - improve map image quality while reducing cost.

## Current Implementation

- **Pattern**: MVVM with Repository pattern ✅
- **State Management**: Simple StatefulWidget with direct database access ✅
- **Database**: SQLite via sqflite (mobile) + sqflite_common_ffi (desktop) ✅
- **UI Framework**: Flutter with Material Design 3 ✅

For detailed technical architecture, database schema, and implementation details, see [ARCHITECTURE.md](documentation/ARCHITECTURE.md).

## Development guideline

- Keep code simple to read and understand, this is a small app for a mobile device.
- Use separation of concerns and DRY
- Use free maps in development
- Run the analyzer to check for errors
- Add Claude readable logging for debugging erros and performance.
- Default to the emulator for testing
- Test after implementing or updating a feature.
- Follow the current implementation patterns.

## Logging Best Practices - Claude Code Optimized

Use the centralized `LoggingService` for all application logging. **Never use `print()` statements** - they should be replaced with appropriate LoggingService calls.

The logging system is **optimized for Claude Code integration** with:
- **ClaudeLogPrinter**: Single-line format `[D][+10.5s] message | at=file.dart:123` for easy parsing
- **Smart filtering**: Routine operations filtered to reduce log noise by 60-70%
- **Duplicate detection**: Prevents redundant logs from repeated operations
- **File navigation**: Every log includes `at=file.dart:line` for instant code navigation
- **Workflow tracking**: Correlation IDs trace related operations across components

### Usage Patterns

#### Basic Logging
```dart
import 'package:free_flight_log/services/logging_service.dart';

// General logging - automatic filtering applied
LoggingService.debug('Debug information');
LoggingService.info('General information');  
LoggingService.warning('Warning message');
LoggingService.error('Error occurred', error, stackTrace);
```

#### Structured Logging (Preferred for Complex Operations)
```dart
// Use structured logging for data that Claude needs to analyze
LoggingService.structured('IGC_IMPORT', {
  'file': 'flight.igc',
  'points': 1091,
  'duration_min': 94,
  'trimmed': true,
});

// Operation summaries with key metrics
LoggingService.summary('TRIANGLE_CALC', {
  'valid': true,
  'distance_km': 25.3,
  'time_ms': 150,
  'points_sampled': 200,
});

// User actions with context
LoggingService.action('FlightDetail', 'reprocess_flight', {
  'flight_id': 2,
  'reason': 'user_requested',
});

// Performance metrics with thresholds
LoggingService.performance('Database Query', duration, 'flights loaded');
```

#### Workflow Tracking
```dart
// Track multi-step operations with correlation IDs
final opId = LoggingService.startOperation('IGC_IMPORT');
// ... perform import steps
LoggingService.endOperation('IGC_IMPORT', results: {
  'flights_created': 1,
  'errors': 0,
  'duration_ms': 2500,
});
```

#### Legacy Context Logging
```dart
// Specialized logging with context (maintained for compatibility)
LoggingService.database('INSERT', 'Added new flight record');
LoggingService.igc('PARSE', 'Processing IGC file: filename.igc');
LoggingService.ui('FlightList', 'User tapped add flight button');
```

### Output Format Examples
```
[I][+1.2s] App startup completed | at=splash_screen.dart:32
[D][+5.1s] [IGC_IMPORT] file=flight.igc | points=1091 | duration_min=94 | at=igc_import_service.dart:85
[I][+8.5s] [WORKFLOW:IGC_IMPORT] completed | id=igc_import_001 | flights_created=1 | at=logging_service.dart:150
```

### Key Benefits

- **Claude Code Integration**: Optimized format for AI code analysis and navigation
- **Reduced Volume**: 60-70% log size reduction through smart filtering
- **Enhanced Navigation**: File:line references enable instant code location
- **Correlation Tracking**: Related operations linked via correlation IDs  
- **Performance Monitoring**: Built-in timing and performance thresholds
- **Duplicate Prevention**: Smart detection prevents redundant log entries
- **Production Ready**: Automatic verbosity adjustment for release builds

### Guidelines

1. **Prefer structured logging** for complex operations that Claude needs to analyze
2. **Use workflow tracking** for multi-step processes like imports or calculations  
3. **Never use `print()`** - LoggingService provides filtering and formatting
4. **Include context data** in structured logs (IDs, metrics, file names)
5. **Trust the filtering** - routine operations are automatically suppressed
6. **Use descriptive messages** - logs should be self-explanatory without code context

The logging system automatically handles:
- ✅ File:line location extraction
- ✅ Relative timestamp formatting  
- ✅ Routine operation filtering
- ✅ Duplicate detection
- ✅ Correlation ID management
- ✅ Performance threshold monitoring

## Key Calculations

- ALL WAYS use GPS for Altitude
- ALL WAYS use GPS for calculating Speed taking into account the time between readings.
- If available use pressure for climb rate, otherwise use GPS, taking into account the time between readings.
- Calculate both intantanious and 15s trailing average climb rates.

## Timestamp Handling

### IGC File Processing

- **B Records**: IGC B records contain UTC time (HHMMSS format) according to IGC specification
- **Timezone Detection**: Timezone is automatically detected from GPS coordinates of the first track point
- **Midnight Crossing**: The parser detects when a flight crosses midnight by checking if timestamps go backwards (e.g., 23:59 → 00:01) and automatically increments the date
- **Conversion Flow**:
  1. Parse B records as UTC timestamps
  2. Detect timezone from GPS coordinates
  3. Convert all timestamps from UTC to local time in bulk
  4. Validate timestamps are in chronological order

### Display

- **Local Time**: All timestamps are displayed in the local timezone of the launch location
- **Database Storage**: Stores date (ISO8601), launch/landing times (HH:MM strings), and timezone offset
- **Cesium 3D**: Receives ISO8601 timestamps with timezone offset (e.g., "2025-07-11T11:03:56.000+02:00")
- **Flutter UI**: Displays times in HH:MM format with optional timezone indicator

## Database Development

### Pre-Release Schema Strategy

- **No Database Migrations**: Since the app is pre-release, we use a simplified approach
- **Schema Changes**: Any database schema changes require clearing app data during development
- **Clean v1.0**: The current schema in `database_helper.dart` represents the v1.0 release baseline
- **Future Migrations**: Post-release migrations will start from v2 with the current schema as the baseline

### Developer Workflow

When pulling code changes that modify the database schema:
1. Clear app data: Settings → Apps → Free Flight Log → Storage → Clear Data
2. Or use the emulator wipe: `flutter_controller.sh clean` (if available)
3. Hot restart the app to recreate the database with the new schema
4. Re-import any test data as needed

### Benefits

- **Simplified codebase**: No complex migration logic during development
- **Clean baseline**: Start v1.0 with optimized schema
- **Fewer bugs**: No migration-related errors during development
- **Performance**: Faster app startup without migration checks

## Development Reminders

- Store documentation in the document directory
- Do not try to modularise cesium JS as ES6 Modules Don't Work in WebView
- When implementing functionality in Cesium look for the simplest, idomatic Cesium native and JavaScript approach

## IGC Data Trimming Architecture

### Core Principle: Single Source of Truth for Flight Data

**The fundamental rule: ALL app code must work with trimmed data (takeoff to landing). Untrimmed data exists only in the source IGC file for archival purposes.**

### Data Flow Architecture

```
IGC File (Full/Archival) → Detection → Store Full Indices → Load Trimmed → App Uses Zero-Based
```

1. **IGC File Storage**: Store complete, unmodified IGC files for archival
2. **Detection**: Automatically detect takeoff/landing points using speed and climb rate thresholds
3. **Database Storage**: Store detection indices relative to **full IGC file** coordinates
4. **Runtime Loading**: `FlightTrackLoader` provides trimmed data with zero-based indices to all app code
5. **App Operations**: All calculations, visualizations, and analysis work on trimmed data only

### Implementation

#### FlightTrackLoader (Single Source of Truth)
- **Location**: `lib/services/flight_track_loader.dart`
- **Purpose**: Centralized service ensuring all flight operations use consistent trimmed data
- **Key Method**: `FlightTrackLoader.loadFlightTrack(flight)` - returns `IgcFile` with trimmed track points
- **Caching**: LRU cache for parsed IGC files to optimize performance
- **Fallback**: Returns full track only if detection completely fails

#### Index Coordinate Systems
- **Database Indices**: Always stored relative to full IGC file (e.g., `takeoffIndex: 150`, `landingIndex: 1200`)
- **App Runtime Indices**: Always zero-based relative to trimmed data (e.g., closing point at index 45 in a 200-point trimmed track)
- **Conversion**: When storing indices calculated on trimmed data, convert to full coordinates: `trimmedIndex + takeoffIndex`

#### Detection Data Storage
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

### Best Practices

#### For App Code
- **Always use `FlightTrackLoader.loadFlightTrack()`** to get flight data
- **Never parse IGC files directly** in UI or business logic
- **Assume all track data is zero-based and trimmed** when received from FlightTrackLoader
- **Trust the single source of truth** - don't implement custom trimming logic

#### For New Features
- **Start with FlightTrackLoader**: Get trimmed data first
- **No index adjustments needed**: Work with zero-based indices directly
- **Store full coordinates**: If storing indices to database, convert from trimmed to full coordinates

#### Deprecated Patterns
- ❌ **Direct IGC parsing in widgets**: Use FlightTrackLoader instead
- ❌ **Manual index adjustments**: FlightTrackLoader handles trimming automatically  
- ❌ **Custom trimming logic**: Central service eliminates need for scattered trimming code
- ❌ **Mixed coordinate systems**: All app code works with zero-based trimmed indices

### Key Services

- **`FlightTrackLoader`**: Single source of truth for flight track data
- **`TakeoffLandingDetector`**: Automatic detection using configurable thresholds
- **`IgcParser`**: Low-level IGC file parsing (used by FlightTrackLoader)
- **`IgcImportService`**: Creates flights with detection data during import

### Example Usage

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

## External Dependencies

- **Map Services**: Assume quotas exist. Default to free providers (OpenStreetMap) during development
- **GPS/Sensors**: Primary data source. All calculations derive from GPS timestamps and coordinates
- **File Storage**: IGC files are immutable once imported. Parse once, store results
- don't cd when using flutter controller
- when doing a hot reload, check if the bash process is still running. If not start again
- use adb screenshot
