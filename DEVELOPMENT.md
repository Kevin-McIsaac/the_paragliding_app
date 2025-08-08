# Development Guide

This document provides comprehensive development guidance for the Free Flight Log application, including setup, commands, testing, and troubleshooting.

## Getting Started with Development

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
  timezone: ^0.9.2                   # Timezone database and GPS-based timezone detection
```

## Development Commands

### Current Working Commands

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
# Note: Includes OSM compliance flag to suppress flutter_map warning
flutter build linux --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not."

# Build Android APK (debug)
flutter build apk --debug --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not."

# Build Android APK (release)
flutter build apk --release --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not."

# Build Android App Bundle for Play Store
flutter build appbundle --release --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not."
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
✅ **Database migration tested** from v1 to v3 schema (climb rates + timezone)
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

## Performance Goals

- Support 10,000+ flight records
- IGC parsing at >1000 points/second
- Smooth 30fps map animations
- <2 second flight list load time