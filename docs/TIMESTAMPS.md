# Timestamp Handling

## IGC File Processing

- **B Records**: IGC B records contain UTC time (HHMMSS format) according to IGC specification
- **Timezone Detection**: Timezone is automatically detected from GPS coordinates of the first track point
- **Midnight Crossing**: The parser detects when a flight crosses midnight by checking if timestamps go backwards (e.g., 23:59 → 00:01) and automatically increments the date
- **Conversion Flow**:
  1. Parse B records as UTC timestamps
  2. Detect timezone from GPS coordinates
  3. Convert all timestamps from UTC to local time in bulk
  4. Validate timestamps are in chronological order

## Display

- **Local Time**: All timestamps are displayed in the local timezone of the launch location
- **Database Storage**: Stores date (ISO8601), launch/landing times (HH:MM strings), and timezone offset
- **Cesium 3D**: Receives ISO8601 timestamps with timezone offset (e.g., "2025-07-11T11:03:56.000+02:00")
- **Flutter UI**: Displays times in HH:MM format with optional timezone indicator

## Key Services

- `timezone_service.dart` - Timezone detection and conversion
- `igc_parser.dart` - Handles UTC time parsing and midnight crossing detection
- Automatic timezone detection from GPS coordinates ensures correct local time display