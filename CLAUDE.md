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
- Timezone support for IGC imports with proper time display
- Track distance column in flight list for comprehensive flight analysis
- Midnight crossing flight duration handling

📋 **Planning Documents** (for reference):
- Complete functional requirements (FUNCTIONAL_SPECIFICATION.md)
- Technical architecture using Flutter/Dart (TECHNICAL_DESIGN.md)
- Week-by-week MVP implementation plan (MVP_BUILD_PLAN.md)

## Quick Development Commands

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

For comprehensive development setup, build commands, testing, and troubleshooting, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Architecture Overview

**Current Implementation:**
- **Pattern**: MVVM with Repository pattern ✅
- **State Management**: Provider (ready for implementation) 
- **Database**: SQLite via sqflite (mobile) + sqflite_common_ffi (desktop) ✅
- **UI Framework**: Flutter with Material Design 3 ✅

For detailed technical architecture, database schema, and implementation details, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Development Status

### ✅ MVP Features (COMPLETED)
1. ✅ Manual flight entry form with validation
2. ✅ Flight list display with statistics
3. ✅ Basic CRUD operations (Create, Read, Update, Delete)
4. ✅ Simple statistics (total flights/hours/max altitude)
5. ✅ Local SQLite persistence with cross-platform support
6. ✅ IGC file import and parsing with climb rate calculations
7. ✅ OpenStreetMap integration for cross-platform track visualization
8. ✅ Flight detail view with inline editing capability and comprehensive statistics
9. ✅ Wing/equipment management with automatic creation from IGC data
10. ✅ Database migrations for schema updates

### 🚀 Next Features (Post-MVP)
1. 📋 Altitude and climb rate charts (fl_chart ready)
2. 📋 Site recognition via reverse geocoding
3. 📋 Export functionality (CSV, KML)
4. 📋 Provider state management implementation
5. 📋 Advanced flight analysis and statistics
6. 📋 Flight comparison and trend analysis

## Important Notes

- This is a **local-only** app - no cloud services or user authentication
- All data stored on device in SQLite database
- Cross-platform support: Linux ✅, Android ✅, iOS ✅, macOS ✅, Windows ✅
- Material Design 3 UI with proper theming
- Full IGC import and flight track visualization capability
- Comprehensive climb rate analysis with 15-second averaging
- Database migration support for schema updates
- Remembers last IGC import folder for improved workflow
- Timezone-aware time display for international flight logging
- Automatic midnight crossing duration correction
- Track distance analysis with sortable flight list columns

## Project History

For complete project history and detailed changelog, see [CHANGELOG.md](CHANGELOG.md).