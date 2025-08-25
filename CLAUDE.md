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

```

### Running Flutter in Background

When asked to run Flutter app ALLWAYS use background execution:

```bash

# Run in background (won't timeout)
# Prefer emulator 
flutter run -d [device]

# Get logs from currently running Flutter app
flutter logs -d [device]

# Clear logs before capturing new ones
flutter logs -c -d [device]

# Take screenshot from running app
flutter screenshot -o screenshots/$(date +%Y%m%d_%H%M%S).png -d [device]
```

For comprehensive development setup, build commands, testing, and troubleshooting, see [DEVELOPMENT.md](documentation/DEVELOPMENT.md).

## Architecture Overview

**Current Implementation:**

- **Pattern**: MVVM with Repository pattern ✅
- **State Management**: Provider (ready for implementation) 
- **Database**: SQLite via sqflite (mobile) + sqflite_common_ffi (desktop) ✅
- **UI Framework**: Flutter with Material Design 3 ✅
- **Simple App**: THis is a simple app with a few screen and typically less than 5,000 flights, 100 sites and 10 wings. Do not over complicate the implementation

For detailed technical architecture, database schema, and implementation details, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Project History

For complete project history and detailed changelog, see [CHANGELOG.md](CHANGELOG.md).

## Calculations

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

### Important Notes

- Timezone conversion happens exactly once after detection (not during B record parsing)
- Midnight crossing is handled by incrementing the date when time goes backwards
- All timestamps are validated to ensure chronological order
  
## Core Principles

- **Simplicity First**: This is a straightforward flight logging app. Choose simple, proven solutions over complex architectures
- **Incremental Testing**: Always test changes on emulator before proposing major refactors
- **Performance Measurement**: Measure before optimizing. Add monitoring first, then make informed decisions
- **Platform Constraints**: WebView has limitations (no ES6 modules, single JS context). Work within them, don't fight them

## External Dependencies

- **Map Services**: Assume quotas exist. Default to free providers (OpenStreetMap) during development
- **GPS/Sensors**: Primary data source. All calculations derive from GPS timestamps and coordinates
- **File Storage**: IGC files are immutable once imported. Parse once, store results

## Code Modification Guidelines

- **KISS**: Keep it simple. This is a small mobile app, don't over complicate or optimse.
- **Readability**: Keep the code simple and readable.
- **Error Recovery**: Add fallbacks for external services (maps, network)
- **State Management**: Keep state simple - this app has <10 screens
- **Idomatic**: Look for solutions that are idomatic to the language/tool, e.g., Flutter, Cesium and Java script, especially efficient data handling.

## Common Pitfalls

- JavaScript in WebView runs in a single global scope
- Flutter background execution prevents timeouts
- Emulator GPU limitations affect 3D rendering
- Cache durations affect offline functionality

## Development Reminders

- All ways test app on emulator
- Store documentation in the document directory
- Do not try to modularise cesium JS as ES6 Modules Don't Work in WebView
- When implementing functionality in Cesium look for the simplest, idomatic Cesium native and JavaScript approach
- 