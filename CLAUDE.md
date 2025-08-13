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
cd ~/Projects/free_flight_log_app

# Install dependencies
flutter pub get

# Run on Linux desktop (recommended for development)
flutter run -d linux --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not."

# Run on Android (device must be connected)
flutter run -d pixel --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not."

# Run on emulator:
flutter run -d emulator-5554 --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not."

# Get pixel screen shot
adb -s 192.168.86.250:45781 exec-out screencap -p > /mnt/chromeos/MyFiles/Downloads/pixel_screenshot.png
```

For comprehensive development setup, build commands, testing, and troubleshooting, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Architecture Overview

**Current Implementation:**

- **Pattern**: MVVM with Repository pattern ✅
- **State Management**: Provider (ready for implementation) 
- **Database**: SQLite via sqflite (mobile) + sqflite_common_ffi (desktop) ✅
- **UI Framework**: Flutter with Material Design 3 ✅

For detailed technical architecture, database schema, and implementation details, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Project History

For complete project history and detailed changelog, see [CHANGELOG.md](CHANGELOG.md).

## Development Reminders

- After running flutter review the output and fix
- Prefer running app test in flutter on the pixel
- The Bash tool doesn't support shell redirection operators like 2>&1 or pipes but it does capture stdout and stderr.
- store documentation in the document directory

## Calculations

- ALLWAYS use GPS for Altitude
- ALLWAYS use GPS for calculating Speed taking into account the time between readings.
- If available use pressure for climb rate, otherwise use GPS, taking into account the time between readings.
  
- Do not try to modularise cesium JS as ES6 Modules Don't Work in WebView