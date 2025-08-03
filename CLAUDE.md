# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Free Flight Log is a cross-platform application for logging paraglider, hang glider, and microlight flights. This repository contains:

- **Complete Flutter Application**: Fully functional MVP with flight logging capabilities
- **Planning Documents**: Original functional specification, technical design, and MVP build plan
- **Legacy Design Assets**: An old app design from December 2022 created in Appery.io (a visual app builder)
- **Working Implementation**: Flutter app with database, UI screens, and core functionality

## Project Status

**IMPLEMENTATION COMPLETE** - The MVP has been successfully built and is functional:

✅ **Completed Features:**
- Flight logging with comprehensive form validation
- SQLite database with full CRUD operations
- Cross-platform support (Linux, Android, iOS, macOS, Windows)
- Material Design 3 UI with proper theming
- Flight list with statistics display
- Repository pattern architecture implementation
- Database initialization for all platforms
- IGC file import with flight track visualization
- Climb rate calculations (instantaneous and 15-second averaged)
- Flight detail screens with comprehensive statistics
- OpenStreetMap integration for cross-platform track display
- Folder memory for IGC import workflow

📋 **Planning Documents** (for reference):
- Complete functional requirements (FUNCTIONAL_SPECIFICATION.md)
- Technical architecture using Flutter/Dart (TECHNICAL_DESIGN.md)
- Week-by-week MVP implementation plan (MVP_BUILD_PLAN.md)

## Getting Started with Development

### Quick Start (App Already Built)
```bash
# Navigate to the Flutter app
cd free_flight_log_app

# Install dependencies
flutter pub get

# Run on Linux desktop (recommended for development)
flutter run -d linux

# Run on Android (device must be connected)
flutter run -d android
```

### Development Environment Setup
See the comprehensive setup guide in [README.md](free_flight_log_app/README.md) for:
- Flutter SDK installation
- Platform-specific development tools
- Android Studio/SDK setup
- Build tool requirements (CMake, Ninja, etc.)

### Current Dependencies (implemented)
```yaml
dependencies:
  flutter: sdk
  sqflite: ^2.3.0                    # Local SQLite database
  sqflite_common_ffi: ^2.3.0         # SQLite for desktop platforms
  shared_preferences: ^2.2.0         # Settings storage
  provider: ^6.1.0                   # State management
  flutter_map: ^6.1.0                # Cross-platform map visualization with OpenStreetMap
  latlong2: ^0.9.1                   # Coordinate handling for flutter_map
  file_picker: ^6.0.0                # IGC file import (for future use)
  fl_chart: ^0.65.0                  # Charts for altitude/climb rate
  intl: ^0.18.0                      # Date/time formatting
```

## Architecture Overview (Implemented)

**Current Implementation:**
- **Pattern**: MVVM with Repository pattern ✅
- **State Management**: Provider (ready for implementation) 
- **Database**: SQLite via sqflite (mobile) + sqflite_common_ffi (desktop) ✅
- **UI Framework**: Flutter with Material Design 3 ✅

### Current Project Structure
```
lib/
├── data/
│   ├── models/              # ✅ Flight, Site, Wing models
│   ├── repositories/        # ✅ Data access layer (CRUD operations)
│   └── datasources/         # ✅ Database helper with initialization
├── presentation/
│   ├── screens/             # ✅ Flight list, Add flight form
│   ├── widgets/             # 📁 Ready for reusable components
│   └── providers/           # 📁 Ready for state management
├── services/                # 📁 Ready for import/export, location
└── main.dart               # ✅ App entry point with database init
```

### Implemented Features
- **Flight Model**: Complete data model with validation and climb rate fields
- **Database Helper**: SQLite initialization for all platforms with migration support
- **Flight Repository**: Full CRUD operations with statistics
- **Site Repository**: Location management with coordinate search
- **Wing Repository**: Equipment tracking with usage stats
- **Flight List Screen**: Material Design 3 UI with empty states
- **Add Flight Form**: Comprehensive form with validation
- **Flight Detail Screen**: Complete flight information with climb rate statistics
- **IGC Import Service**: Full IGC file parsing with climb rate calculations
- **IGC Import Screen**: File selection with folder memory and batch import
- **Flight Track Visualization**: OpenStreetMap (flutter_map) and canvas-based track display
- **Navigation**: Screen transitions with result callbacks

## Development Status

### ✅ MVP Features (COMPLETED)
1. ✅ Manual flight entry form with validation
2. ✅ Flight list display with statistics
3. ✅ Basic CRUD operations (Create, Read, Update, Delete)
4. ✅ Simple statistics (total flights/hours/max altitude)
5. ✅ Local SQLite persistence with cross-platform support
6. ✅ IGC file import and parsing with climb rate calculations
7. ✅ OpenStreetMap integration for cross-platform track visualization
8. ✅ Flight detail view with edit capability and comprehensive statistics
9. ✅ Wing/equipment management with automatic creation from IGC data
10. ✅ Database migrations for schema updates

### 🚀 Next Features (Post-MVP)
1. 📋 Altitude and climb rate charts (fl_chart ready)
2. 📋 Site recognition via reverse geocoding
3. 📋 Export functionality (CSV, KML)
4. 📋 Provider state management implementation
5. 📋 Advanced flight analysis and statistics
6. 📋 Flight comparison and trend analysis

## Key Technical Considerations

### IGC File Format
- International Gliding Commission standard for flight tracks
- Contains GPS coordinates, altitude, timestamps
- Parser extracts launch/landing sites, max altitude, climb rates
- Supports both pressure and GPS altitude data
- Calculates instantaneous and 15-second averaged climb rates
- Stores complete track data for visualization

### Database Schema
Three main tables with current implementation:
- `flights`: Core flight records with comprehensive statistics including climb rates
- `sites`: Launch/landing locations with custom names and coordinates
- `wings`: Equipment tracking with automatic creation from IGC data
- Database version 2 with migration support for climb rate fields

### Climb Rate Calculations
- **Instantaneous rates**: Point-to-point climb/sink calculations
- **15-second averaged rates**: Smoothed rates using ±7.5 second window
- **Pressure altitude priority**: Uses barometric altitude when available for accuracy
- **GPS fallback**: Falls back to GPS altitude when pressure data unavailable
- **Thermal analysis**: 15-second window filters GPS noise for realistic thermal readings

### Performance Goals
- Support 10,000+ flight records
- IGC parsing at >1000 points/second
- Smooth 30fps map animations
- <2 second flight list load time

## Development Commands

### Current Working Commands

```bash
# Navigate to app directory
cd free_flight_log_app

# Install/update dependencies
flutter pub get

# Run on Linux desktop (recommended for development)
flutter run -d linux

# Run on Android device (must be connected with USB debugging)
flutter run -d android

# Check available devices
flutter devices

# Hot reload during development (press 'r' in terminal)
# Hot restart (press 'R' in terminal)
```

### Build Commands
```bash
# Clean build cache
flutter clean

# Build Linux desktop app
flutter build linux

# Build Android APK (debug)
flutter build apk --debug

# Build Android APK (release)
flutter build apk --release

# Build Android App Bundle for Play Store
flutter build appbundle --release
```

### Development Tools
```bash
# Analyze code for issues
flutter analyze

# Run tests (when implemented)
flutter test

# Format code
dart format .

# Check Flutter installation
flutter doctor

# Update Flutter
flutter upgrade
```

## Testing Approach

### Current Testing Status
✅ **Manual testing completed** with flight entry and display  
✅ **CRUD operations verified** with database persistence  
✅ **Form validation tested** with edge cases  
✅ **Cross-platform verified** on Linux desktop  
✅ **IGC import tested** with real flight data
✅ **Climb rate calculations tested** with unit tests for 15-second averaging
✅ **Database migration tested** from v1 to v2 schema
✅ **Flight track visualization tested** on OpenStreetMap (flutter_map)

### Recommended Testing
1. Test flight entry with various time combinations
2. Verify database persistence across app restarts
3. Test form validation edge cases (e.g., landing before launch)
4. Performance testing with multiple flight entries
5. Cross-platform testing (Linux, Android, iOS)
6. IGC import with various file formats and sizes
7. Climb rate accuracy with real flight instrument data

## Known Issues and Troubleshooting

### Common Issues
1. **"Database factory not initialized" Error**
   - Fixed in main.dart with sqflite_common_ffi initialization
   - Rebuild app if error persists: `flutter clean && flutter build linux`

2. **File Picker Warnings**
   - Informational warnings about plugin implementations
   - Safe to ignore - don't affect app functionality

3. **App Screen Disappears**
   - Run built binary directly: `./build/linux/x64/release/bundle/free_flight_log_app`
   - Or use: `flutter run -d linux` after ensuring clean build

4. **Android Device Not Detected**
   - Enable USB debugging in Developer Options
   - Use `adb devices` to verify connection
   - Use `flutter devices` to check Flutter detection

## Important Notes

- This is a **local-only** app - no cloud services or user authentication
- All data stored on device in SQLite database
- Cross-platform support: Linux ✅, Android ✅, iOS ✅, macOS ✅, Windows ✅
- Material Design 3 UI with proper theming
- Full IGC import and flight track visualization capability
- Comprehensive climb rate analysis with 15-second averaging
- Database migration support for schema updates
- Remembers last IGC import folder for improved workflow

## Recent Updates

### August 2025 - IGC Import Enhancements & Flight Track Visualization
- **HFDTE Parsing Correction**: Fixed IGC date parsing from incorrect YYMMDD to correct DDMMYY format
- **Date Accuracy**: Ensures flight dates are parsed correctly from IGC file headers
- **Duplicate Detection**: Added comprehensive duplicate flight detection during IGC import
- **User Choice Options**: Implemented Skip/Skip All/Replace/Replace All options for duplicate handling
- **Enhanced Results**: Detailed import results showing imported, replaced, skipped, and failed files
- **Straight Line Visualization**: Added straight-line distance overlay on both OpenStreetMap and Canvas flight track views
- **Distance Labels**: Straight distance displayed directly on the visualization line (marker for Maps, text overlay for Canvas)
- **Enhanced Statistics**: Shows track distance and straight distance (removed efficiency calculation)
- **Interactive Controls**: Toggle visibility of straight line via popup menu in both map and canvas views
- **Consistent Experience**: Both map and canvas views now offer identical functionality and visual design
- **Parser Update**: Updated `IgcParser._parseDate()` method with correct format interpretation

### August 2025 - Cross-Platform Map Migration
- **OpenStreetMap Migration**: Migrated from Google Maps to flutter_map with OpenStreetMap for full cross-platform compatibility
- **Linux Desktop Support**: Flight track visualization now works natively on Linux desktop without dependencies
- **Maintained Functionality**: All existing map features preserved including straight-line distance visualization
- **Enhanced Compatibility**: Single codebase now supports maps on all platforms (Linux, Android, iOS, macOS, Windows)

### December 2024 - Enhanced Climb Rate Analysis
- **15-Second Averaging**: Upgraded from 5-second to 15-second climb rate calculations for more stable readings
- **Dual Rate Display**: Shows both instantaneous and 15-second averaged climb/sink rates
- **Database Migration**: Added support for new climb rate fields with automatic migration
- **UI Improvements**: Enhanced flight statistics display with consolidated climb rate information
- **Test Coverage**: Added comprehensive unit tests for climb rate calculations
- **Folder Memory**: IGC import now remembers last used folder for improved workflow

### Key Files Updated
- `lib/services/igc_parser.dart`: Fixed HFDTE date format parsing (DDMMYY)
- `lib/data/models/import_result.dart`: New models for tracking import results (NEW)
- `lib/data/repositories/flight_repository.dart`: Added duplicate detection method
- `lib/presentation/widgets/duplicate_flight_dialog.dart`: User choice dialog for duplicates (NEW)
- `lib/services/igc_import_service.dart`: Enhanced IGC processing with duplicate handling
- `lib/presentation/screens/igc_import_screen.dart`: Updated UI for duplicate handling
- `lib/presentation/screens/flight_track_screen.dart`: Added straight line visualization and enhanced statistics
- `lib/presentation/screens/flight_track_canvas_screen.dart`: Added matching straight line visualization for canvas view
- `lib/data/models/igc_file.dart`: Core climb rate calculation algorithms
- `lib/data/models/flight.dart`: Added 15-second climb rate fields
- `lib/data/datasources/database_helper.dart`: Database migration support
- `lib/presentation/screens/flight_detail_screen.dart`: Enhanced statistics display
- Test files: Updated for 15-second calculations