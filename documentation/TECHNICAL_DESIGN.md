# The Paragliding App - Technical Design Document

## 1. Introduction

### 1.1 Purpose
This document outlines the technical architecture, technology stack, and implementation strategy for the The Paragliding App mobile application based on the functional requirements.

### 1.2 Goals

- Minimize development and operational costs
- Enable easy deployment to Google Play Store
- Ensure local-only operation on Android devices
- Provide maintainable and scalable architecture
- Leverage Google technologies where beneficial

## 2. Technology Stack

### 2.1 Core Framework

**Flutter** (Google's UI Framework)

- **Version**: Latest stable (3.x)
- **Language**: Dart
- **Rationale**:
  - Native Android performance
  - Google's official framework
  - Rich ecosystem of packages
  - Excellent documentation and community
  - Built-in Material Design support

### 2.2 Local Data Storage

#### Primary Database

**SQLite** via `sqflite` package

- Embedded database, zero runtime cost
- Handles complex queries for statistics
- Proven reliability for 10,000+ records
- ACID compliance for data integrity

#### Configuration Storage

**SharedPreferences**

- Lightweight key-value storage
- Perfect for user settings
- Native Android integration

#### File Storage

**Path Provider** + Device File System

- Store IGC track logs
- Cache generated exports
- Temporary file handling

### 2.3 Mapping Solutions

#### Primary: OpenStreetMap via flutter_map (Implemented)

```yaml
dependencies:
  flutter_map: ^8.2.1         # Cross-platform map visualization
  latlong2: ^0.9.1            # Coordinate handling
```
- **Pros**: No API costs, unlimited usage, open source, excellent tile caching
- **2D Maps**: Site visualization, launch/landing markers, flight boundaries
- **Cache Duration**: 12-month HTTP cache headers for optimal performance
- **Cost**: $0 forever - no quotas or limits

#### Secondary: Cesium 3D Globe (Implemented)

```yaml
dependencies:
  flutter_inappwebview: ^6.1.5  # WebView integration
```
- **Pros**: Professional 3D flight visualization, terrain rendering, flight replay
- **3D Visualization**: Flight tracks, altitude profiles, terrain interaction
- **Optimizations**: Development mode with free providers, performance caching
- **Cost**: Free tier sufficient for typical use (optimized quota usage)

### 2.4 Key Dependencies

```yaml
name: the_paragliding_app
description: "A mobile app for logging paraglider, hang glider, and microlight flights"

dependencies:
  flutter:
    sdk: flutter
    
  # Core dependencies for The Paragliding App
  cupertino_icons: ^1.0.8     # iOS-style icons
  async: ^2.11.0              # Async utilities including CancelableOperation
  
  # Data Storage
  sqflite: ^2.4.2             # Local SQLite database - platform architecture updates
  sqflite_common_ffi: ^2.3.6  # SQLite for desktop platforms - latest stable version
  shared_preferences: ^2.5.3  # Settings storage - new async APIs
  
  # Mapping Solutions - OpenStreetMap instead of Google Maps
  flutter_map: ^8.2.1         # Cross-platform map visualization with OpenStreetMap
  latlong2: ^0.9.1            # Coordinate handling for flutter_map
  
  # File Handling
  file_picker: ^10.3.1        # IGC file import - minor improvements
  receive_sharing_intent: ^1.8.1  # Handle IGC files shared from other apps
  
  # Data Processing & IGC Parsing
  xml: ^6.5.0                 # XML/KML parsing for paragliding sites
  intl: ^0.20.2               # Date/time formatting
  timezone: ^0.10.1           # Timezone database and lookup
  crypto: ^3.0.5              # SHA256 hashing for cache keys
  
  # Visualization & Charts
  fl_chart: ^1.0.0           # Charts for altitude/climb rate
  
  # 3D Visualization - Cesium Integration
  flutter_inappwebview: ^6.1.5  # WebView for 3D Cesium integration with CORS bypass
  
  # Network & Connectivity
  connectivity_plus: ^6.1.5   # Network connectivity detection - WASM support & fixes
  url_launcher: ^6.3.2        # Open external URLs for OSM links
  http: ^1.2.2                # HTTP client - pinned from "any" to stable
  
  # State Management
  provider: any               # State management (flexible version)
  
  # Utilities
  path: ^1.8.0                # Database path utilities
  path_provider: ^2.1.5       # App directory paths - bug fixes & stability
  logger: ^2.6.1              # Structured logging framework

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  flutter_lints: ^6.0.0      # Latest lint rules
```

## 3. Architecture Design

### 3.1 Application Architecture Pattern

**MVVM with Repository Pattern**

```
┌─────────────────┐
│   UI Layer      │  ← Flutter Widgets
├─────────────────┤
│   ViewModels    │  ← Business Logic (Provider)
├─────────────────┤
│   Repositories  │  ← Data Access Abstraction
├─────────────────┤
│   Data Sources  │  ← SQLite, Files, Preferences
└─────────────────┘
```

### 3.2 Project Structure

```

lib/
├── main.dart
├── app.dart
├── core/
│   ├── constants/
│   ├── themes/
│   └── utils/
├── data/
│   ├── models/
│   │   ├── flight.dart
│   │   ├── site.dart
│   │   ├── wing.dart
│   │   └── settings.dart
│   ├── repositories/
│   │   ├── flight_repository.dart
│   │   ├── site_repository.dart
│   │   └── settings_repository.dart
│   └── datasources/
│       ├── local/
│       │   ├── database_helper.dart
│       │   └── preferences_helper.dart
│       └── parsers/
│           ├── igc_parser.dart
│           └── csv_parser.dart
├── domain/
│   ├── entities/
│   └── usecases/
├── presentation/
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── flight_list_screen.dart
│   │   ├── add_flight_screen.dart
│   │   ├── edit_flight_screen.dart
│   │   ├── flight_detail_screen.dart
│   │   ├── flight_track_3d_screen.dart
│   │   ├── igc_import_screen.dart
│   │   ├── statistics_screen.dart
│   │   ├── edit_site_screen.dart
│   │   ├── manage_sites_screen.dart
│   │   ├── wing_management_screen.dart
│   │   ├── edit_wing_screen.dart
│   │   ├── database_settings_screen.dart
│   │   └── about_screen.dart
│   ├── widgets/
│   │   ├── cesium_3d_map_inappwebview.dart
│   │   ├── flight_track_3d_widget.dart
│   │   └── common/
│   └── providers/
│       └── (using Provider pattern with ChangeNotifier)
└── services/
    ├── export_service.dart
    ├── import_service.dart
    └── location_service.dart
```

### 3.3 Database Schema

```sql
-- Flights table
CREATE TABLE flights (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  launch_time TEXT NOT NULL,
  landing_time TEXT NOT NULL,
  duration INTEGER NOT NULL,
  launch_site_id INTEGER,
  landing_site_id INTEGER,
  max_altitude REAL,
  max_climb_rate REAL,
  max_sink_rate REAL,
  distance REAL,
  wing_id INTEGER,
  notes TEXT,
  track_log_path TEXT,
  source TEXT CHECK(source IN ('manual', 'igc', 'parajournal')),
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (launch_site_id) REFERENCES sites (id),
  FOREIGN KEY (landing_site_id) REFERENCES sites (id),
  FOREIGN KEY (wing_id) REFERENCES wings (id)
);

-- Sites table
CREATE TABLE sites (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  altitude REAL,
  custom_name INTEGER DEFAULT 0,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Wings table
CREATE TABLE wings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  manufacturer TEXT,
  model TEXT,
  size TEXT,
  color TEXT,
  purchase_date TEXT,
  active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_flights_date ON flights(date);
CREATE INDEX idx_flights_launch_site ON flights(launch_site_id);
CREATE INDEX idx_flights_wing ON flights(wing_id);
```

### 4.3 Performance Optimizations

1. **Database**
   - Use indexes on frequently queried fields
   - Implement pagination for large datasets
   - Cache computed statistics

2. **UI & Maps**
  
   - Advanced map tile caching (12-month HTTP headers)
   - Flutter ImageCache (100MB, 1000 tiles)
   - Cesium 3D memory caching (300 tiles runtime)
   - Debounced search/filter operations

3. **IGC Processing**
   - Stream-based parsing for large files
   - Background isolate for heavy computations
   - Progressive loading for track visualization

4. **3D Visualization (Cesium Integration)**
   - WebView-based Cesium 3D globe
   - Performance monitoring and metrics
   - Automatic quality scaling (Performance/Quality/Ultra modes)
   - Free provider fallback system (OpenStreetMap, Stamen Terrain)
   - Development mode quota optimization
   - JavaScript-Flutter bridge for performance data

## 5. Testing Strategy

### 5.1 Unit Tests

```dart
// Example: IGC Parser Test
test('parses IGC header correctly', () {
  final parser = IgcParser();
  final result = parser.parseHeader('HFDTE2501231');
  expect(result.date, DateTime(2023, 01, 25));
});
```

### 5.2 Widget Tests

```dart
// Example: Flight Entry Form Test
testWidgets('validates landing after launch', (tester) async {
  await tester.pumpWidget(FlightEntryForm());
  // Test implementation
});
```

### 5.3 Integration Tests

- Database operations
- File import/export
- Map rendering
- Performance benchmarks

## 6. Build & Deployment

### 6.1 Build Configuration

```bash
# Development
flutter run

# Release build for Play Store
flutter build appbundle --release

# APK for direct installation
flutter build apk --release
```

### 6.2 Play Store Preparation

1. **App Signing**

   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. **Build Configuration** (`android/key.properties`)

   ```
   storePassword=<password>
   keyPassword=<password>
   keyAlias=upload
   storeFile=../upload-keystore.jks
   ```

3. **Permissions** (`android/app/src/main/AndroidManifest.xml`)

   ```xml
   <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
   ```

## 7. Map Caching Implementation

### 7.1 Multi-Layer Caching Strategy

**2D Maps (flutter_map + OpenStreetMap)**
- **HTTP Headers**: `Cache-Control: max-age=31536000` (12 months)
- **Flutter ImageCache**: 100MB, 1000 tiles (LRU eviction)
- **Benefits**: 95% bandwidth reduction, instant loading for visited areas

**3D Maps (Cesium + WebView)**
- **HTML Assets**: `max-age=31536000, immutable` (12 months)
- **WebView Cache**: 20MB persistent HTTP cache
- **Runtime Cache**: 300 tiles in memory during session
- **Performance**: 312ms initialization, 85% cache hit rate

### 7.2 Cache Verification & Management

**Monitoring**:
```dart
// Cache statistics in Database Settings
CacheUtils.getCurrentCacheCount()  // Returns tile count
CacheUtils.getCurrentCacheSize()   // Returns size in bytes
CacheUtils.formatBytes(size)       // Human-readable format (KB/MB/GB)
```

**Manual Management**:
- Clear cache option in Database Settings screen
- Automatic cache eviction when limits reached
- Cache persists across app restarts for 12 months

## 8. Maintenance Plan

### 8.1 Update Schedule

- **Monthly**: Security patches
- **Quarterly**: Dependency updates
- **Bi-annually**: Flutter SDK updates

### 8.2 Monitoring

- Crash reporting via Flutter's built-in tools
- User feedback via Play Store reviews
- Performance monitoring in Play Console

### 8.3 Version Control

```bash
# Branching strategy
main          # Production releases
develop       # Development branch
feature/*     # Feature branches
release/*     # Release candidates
hotfix/*      # Emergency fixes
```

## 9. Cost Analysis

### 9.1 Development Costs

- **One-time**: Developer time only
- **Tools**: All development tools are free

### 9.2 Operational Costs

- **Hosting**: $0 (local app only)
- **Database**: $0 (SQLite)
- **2D Maps**: $0 (OpenStreetMap - no quotas, unlimited usage)
- **3D Maps**: $0 (Cesium free providers in development mode)
- **Map Caching**: $0 (12-month browser cache, 95% bandwidth savings)
- **Play Store**: $25 one-time developer fee

### 9.3 Total Cost of Ownership

- **Year 1**: $25 (Play Store fee)
- **Ongoing**: $0/year

## 10. Security Considerations

### 10.1 Data Protection

- All data stored locally on device
- No network transmission of personal data
- Optional app-level PIN/biometric lock

### 10.2 File Handling

- Validate all imported files
- Sanitize file paths
- Handle malformed data gracefully

## 11. Migration Strategy

### 11.1 From Existing App

1. Export data from old app
2. Import via CSV/IGC functions
3. Verify data integrity
4. Archive old app

### 11.2 Future Platform Support

- Architecture supports iOS with minimal changes
- Web version possible with Flutter Web
- Desktop support via Flutter Desktop

## Appendices

### A. Development Environment Setup

```bash
# Install Flutter
git clone https://github.com/flutter/flutter.git
export PATH="$PATH:`pwd`/flutter/bin"

# Verify installation
flutter doctor

# Create project
flutter create the_paragliding_app --org com.theparaglidingapp

# Run on device
flutter run
```

### B. Useful Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Material Design Guidelines](https://material.io/design)
- [IGC File Format Spec](http://www.fai.org/igc-documents)
- [SQLite Best Practices](https://www.sqlite.org/bestpractice.html)