# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Free Flight Log is a cross-platform application for logging paraglider, hang glider, and microlight flights. This repository contains:

- **Complete Flutter Application**: Fully functional MVP with flight logging capabilities
- **Planning Documents**: Original functional specification, technical design, and MVP build plan
- **Legacy Design Assets**: An old app design from December 2022 created in Appery.io (a visual app builder)
- **Working Implementation**: Flutter app with database, UI screens, and core functionality


📋 **Planning Documents** (for reference):

- Complete functional requirements (FUNCTIONAL_SPECIFICATION.md)
- Technical architecture using Flutter/Dart (TECHNICAL_DESIGN.md)

## Quick Development Commands

```bash
# Navigate to the Flutter app
cd ~/Projects/free_flight_log_app

# Install dependencies
flutter pub get

# Run on Linux desktop (recommended for development)
flutter run -d linux"

# Run on Android (device must be connected)
flutter run -d pixel"

# Run on emulator:
flutter run -d emulator-5554

# Get pixel screen shot
adb -s 192.168.86.250:45781 exec-out screencap -p > ~Projects/free_flight_log/screenshots/123456.png
```

For comprehensive development setup, build commands, testing, and troubleshooting, see [DEVELOPMENT.md](documentation/DEVELOPMENT.md).

## Architecture Overview

**Current Implementation:**

- **Pattern**: MVVM with Repository pattern ✅
- **State Management**: Provider (ready for implementation) 
- **Database**: SQLite via sqflite (mobile) + sqflite_common_ffi (desktop) ✅
- **UI Framework**: Flutter with Material Design 3 ✅

For detailed technical architecture, database schema, and implementation details, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Project History

For complete project history and detailed changelog, see [CHANGELOG.md](CHANGELOG.md).



## Calculations

- ALLWAYS use GPS for Altitude
- ALLWAYS use GPS for calculating Speed taking into account the time between readings.
- If available use pressure for climb rate, otherwise use GPS, taking into account the time between readings.

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

### Important Notes
- Timezone conversion happens exactly once after detection (not during B record parsing)
- Midnight crossing is handled by incrementing the date when time goes backwards
- All timestamps are validated to ensure chronological order
  
## Development Reminders

- After running flutter ask the user if they want claude to review the output, look for root causes and fix
- Prefer running app tests in flutter on the emulator
- Store documentation in the document directory
- Do not try to modularise cesium JS as ES6 Modules Don't Work in WebView
- Allways test app on emulator