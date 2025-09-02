# CLAUDE.md

## Project Overview

Free Flight Log is a free, android first, cross-platform application for
logging, reporting, and visualising paraglider, hang glider, and microlight flights.
This repository contains:

- **Complete Flutter Application**: Fully functional flight logbook capabilities
- **Planning Documents** (for reference):
  - [Functional requirements](documentation/FUNCTIONAL_SPECIFICATION.md)
  - [Technical architecture](documentation/TECHNICAL_DESIGN.md)

## Flutter commands

```bash
# Allways run the app using flutter_controller.sh in background

# Run app
flutter_controller.sh run 

# Hot reload
flutter_controller.sh r

# Hot restart
flutter_controller.sh R

# Quit app
flutter_controller.sh q
```

## Key Files

- IGC parser: `lib/services/igc_parser.dart`
- Cesium 3D: `assets/cesium/cesium.js`  
- Database: `lib/data/datasources/local/database_helper.dart`
- Screens: `lib/presentation/screens/`

## Core Principles

- **Keep it Simple**: This is a simple app with a few screen and typically less than 5,000 flights, 100 sites and 10 wings. Choose simple, proven solutions over complex architectures
- **State Management**: Keep state simple - this app has <10 screens
- **Database**: Keep database managment simple, this app has < 10 tables, and the largest table will have < 5000 rows
- **Idomatic**: Look for solutions that are idomatic to the language/tool, e.g., Flutter, Cesium and Javascript, especially large data handling.
- **WebView Constraints**: WebView has limitations (no ES6 modules, single JS context). Work within them.
- **Error Recovery**: Add fallbacks for external services (maps, network)
- **Performance Measurement**: Measure performance before optimizing. Add monitoring to debug logs, then make informed decisions from app testing.
- **App Testing**: Test app changes by:
  - Adding logging that helps with understanding app usage, performance and diagnoing errors.
  - Runing the app in the bash tool on the emulator and telling the user what to do.
  - When requested by the user reviewing the logs in the bash shell output for:
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

## Development Reminders

- Store documentation in the document directory
- Do not try to modularise cesium JS as ES6 Modules Don't Work in WebView
- When implementing functionality in Cesium look for the simplest, idomatic Cesium native and JavaScript approach

## External Dependencies

- **Map Services**: Assume quotas exist. Default to free providers (OpenStreetMap) during development
- **GPS/Sensors**: Primary data source. All calculations derive from GPS timestamps and coordinates
- **File Storage**: IGC files are immutable once imported. Parse once, store results
