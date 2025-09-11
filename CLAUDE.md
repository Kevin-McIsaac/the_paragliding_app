# CLAUDE.md

## Quick Start for Claude Code

### Essential Commands
```bash
# Always run from /home/kmcisaac/Projects/free_flight_log/free_flight_log_app
flutter_controller_enhanced.sh run        # Start app with logging
flutter_controller_enhanced.sh r          # Hot reload
flutter_controller_enhanced.sh status     # Check status
flutter_controller_enhanced.sh logs 50    # Recent logs (prefer over bash output)
flutter_controller_enhanced.sh screenshot # Take screenshot (alias: ss)
```

### Key Files (Most Accessed)
| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point |
| `lib/services/database_service.dart` | Main database layer |
| `lib/services/flight_track_loader.dart` | **Single source of truth** for flight data |
| `lib/services/logging_service.dart` | Claude-optimized logging |
| `lib/presentation/screens/flight_list_screen.dart` | Main flight list |
| `lib/presentation/screens/flight_detail_screen.dart` | Flight details |

### Critical Rules
- **NEVER use `print()` statements** - Use `LoggingService` instead
- **ALL flight data** must go through `FlightTrackLoader.loadFlightTrack()`
- **All track data is zero-based and trimmed** when received from FlightTrackLoader
- Use free maps in development
- Test on emulator by default

## Project Overview

Free Flight Log is a free, Android-first, cross-platform application for logging, reporting, and visualizing paraglider, hang glider, and microlight flights.

**Architecture**: MVVM with Repository pattern, Flutter + Material Design 3, SQLite database

**Scale**: Simple app with <10 screens, <5000 flights, <100 sites, <10 wings

**Documentation**: [Architecture](documentation/TECHNICAL_DESIGN.md) | [Requirements](documentation/FUNCTIONAL_SPECIFICATION.md)

## Flutter Development

### Enhanced Controller
```bash
# Script: /home/kmcisaac/flutter/bin/flutter_controller_enhanced.sh
flutter_controller_enhanced.sh run [device]     # Start with full logging
flutter_controller_enhanced.sh R                # Hot restart
flutter_controller_enhanced.sh q                # Quit
flutter_controller_enhanced.sh monitor          # Watch logs real-time
flutter_controller_enhanced.sh restart [device] # Force restart
flutter_controller_enhanced.sh cleanup          # Clean up processes
flutter_controller_enhanced.sh screenshot [name] [device] # Take screenshot
flutter_controller_enhanced.sh ss               # Screenshot (short alias)
```

### Log Files for Claude Integration
- **Output**: `/tmp/flutter_controller/flutter_output.log`
- **Status**: `/tmp/flutter_controller/flutter_status`
- **PID**: `/tmp/flutter_controller/flutter.pid`
- **Screenshots**: `/tmp/flutter_controller/screenshots/` (also copied to `/tmp/`)

## Code Structure

### Core Services
| Service | Function |
|---------|----------|
| `database_service.dart` | Main database operations |
| `flight_track_loader.dart` | **Single source of truth** for flight data with LRU cache |
| `igc_import_service.dart` | IGC file import workflow |
| `logging_service.dart` | Claude-optimized logging with filtering |
| `paragliding_earth_api.dart` | External API integration |
| `takeoff_landing_detector.dart` | Automatic flight phase detection |

### Main Screens
| Screen | Purpose |
|--------|---------|
| `flight_list_screen.dart` | Main flight list with `AppStatCard` and sorting |
| `flight_detail_screen.dart` | Individual flight with expansion cards |
| `igc_import_screen.dart` | IGC file import interface |
| `statistics_screen.dart` | Flight statistics and charts |
| `data_management_screen.dart` | Uses `AppExpansionCard.dataManagement()` pattern |
| `manage_sites_screen.dart` + `edit_site_screen.dart` | Site management |
| `wing_management_screen.dart` + `edit_wing_screen.dart` | Wing management |

### Widget Patterns
| Widget | Usage |
|--------|-------|
| `AppStatCard.flightList()` | Flight statistics display |
| `AppEmptyState.flights()` | Empty flight list state |
| `AppExpansionCard.dataManagement()` | Consistent expansion pattern |
| `AppLoadingSkeleton` | Loading placeholders |
| `AppErrorState` | Error displays with retry |

### Key Models
- `flight.dart` - Flight data with detection indices
- `igc_file.dart` - IGC file structure  
- `site.dart` / `paragliding_site.dart` - Site models
- `wing.dart` - Equipment model

## Development Principles

### Core Rules
- **Keep it Simple**: Choose simple, proven solutions over complex architectures
- **State Management**: Simple StatefulWidget with direct database access
- **Database**: Simple management - <10 tables, largest <5000 rows
- **Idiomatic**: Use language/tool-native approaches (Flutter, Cesium, JavaScript)
- **WebView Constraints**: No ES6 modules, single JS context
- **Error Recovery**: Add fallbacks for external services

### Testing & Performance
- Add Claude-readable logging for debugging and performance
- Run analyzer to check for errors
- Test after implementing features
- Measure performance before optimizing
- Default to emulator for testing

## Logging (Claude Code Optimized)

### Essential Patterns
```dart
import 'package:free_flight_log/services/logging_service.dart';

// Basic logging (auto-filtered)
LoggingService.info('General information');
LoggingService.error('Error occurred', error, stackTrace);

// Structured logging for Claude analysis
LoggingService.structured('IGC_IMPORT', {
  'file': 'flight.igc', 'points': 1091, 'duration_min': 94
});

// Performance tracking
LoggingService.performance('Database Query', duration, 'flights loaded');

// Workflow tracking
final opId = LoggingService.startOperation('IGC_IMPORT');
LoggingService.endOperation('IGC_IMPORT', results: {'flights_created': 1});
```

### Format
```
[I][+1.2s] App startup completed | at=splash_screen.dart:32
[D][+5.1s] [IGC_IMPORT] file=flight.igc | points=1091 | at=igc_import_service.dart:85
```

**Benefits**: 60-70% log reduction, file:line navigation, correlation tracking

## Flight Data Architecture

### Single Source of Truth Pattern
```dart
// ✅ Always use FlightTrackLoader
final igcFile = await FlightTrackLoader.loadFlightTrack(flight);
// igcFile.trackPoints is trimmed and zero-based

// ✅ All calculations on trimmed data
final distance = igcFile.calculateGroundTrackDistance();
final triangleData = igcFile.calculateFaiTriangle();

// ❌ Never parse IGC files directly in UI
// ❌ Never implement custom trimming logic
```

### Data Flow
```
IGC File (Full/Archival) → Detection → Store Full Indices → Load Trimmed → App Uses Zero-Based
```

**Key Services**: `FlightTrackLoader` (single source), `TakeoffLandingDetector`, `IgcParser`, `IgcImportService`

## Database Development

### Pre-Release Strategy
- **No Migrations**: Clear app data for schema changes during development
- **v1.0 Baseline**: Current schema in `database_helper.dart`
- **Developer Workflow**: Clear data → Hot restart → Re-import test data

### Schema Change Process
1. Clear app data: Settings → Apps → Free Flight Log → Storage → Clear Data
2. Hot restart app to recreate database
3. Re-import test data

## Key Calculations & Data

### Flight Calculations
- **Altitude**: Always use GPS
- **Speed**: GPS with time between readings
- **Climb Rate**: Pressure if available, otherwise GPS with time deltas
- **Calculate**: Both instantaneous and 15s trailing average climb rates

### Timestamp Handling
- **IGC**: UTC time (HHMMSS) → Detect timezone from GPS → Convert to local
- **Display**: Local timezone of launch location
- **Database**: ISO8601 date + HH:MM times + timezone offset
- **Cesium**: ISO8601 with timezone (e.g., "2025-07-11T11:03:56.000+02:00")

### External Dependencies
- **Maps**: Assume quotas exist, default to free providers (OpenStreetMap)
- **GPS**: Primary data source for all calculations
- **IGC Files**: Immutable once imported, parse once and store results

## Common Tasks

### Hot Reload Issues
- Check if bash process still running, restart if needed
- Use `flutter_controller_enhanced.sh logs` instead of bash output

### Testing
- Use `flutter_controller_enhanced.sh screenshot` for debugging
- Don't use `cd` with flutter controller
- Add logging for performance analysis

### Development Workflow
1. Follow current implementation patterns
2. Use separation of concerns and DRY
3. Add structured logging for Claude analysis
4. Test on emulator after changes

---

📚 **Detailed Documentation**: 
- [IGC Data Trimming](docs/IGC_TRIMMING.md)
- [Database Schema](docs/DATABASE.md) 
- [Timestamp Processing](docs/TIMESTAMPS.md)