# Free Flight Log - Technical Design Document

## 1. Introduction

### 1.1 Purpose
This document outlines the technical architecture, technology stack, and implementation strategy for the Free Flight Log mobile application based on the functional requirements.

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

#### Google Maps (Recommended for features)

```yaml
dependencies:
  google_maps_flutter: ^2.5.0
```
- **Pros**: Best features, smooth performance, familiar UX
- **Free Tier**: 28,000 map loads/month
- **Cost**: $0 for typical personal use

### 2.4 Key Dependencies

```yaml
name: free_flight_log
description: Flight logging for paragliding, hang gliding, and microlights

dependencies:
  flutter:
    sdk: flutter
  
  # UI Components
  material_design_icons_flutter: ^7.0.0
  
  # Data Storage
  sqflite: ^2.3.0
  shared_preferences: ^2.2.0
  path_provider: ^2.1.0
  
  # File Handling
  file_picker: ^6.0.0
  share_plus: ^7.2.0
  permission_handler: ^11.0.0
  
  # Maps (choose one)
  google_maps_flutter: ^2.5.0  # Option A
  
  # Data Processing
  xml: ^6.4.0      # IGC parsing
  csv: ^5.0.0      # CSV import/export
  intl: ^0.18.0    # Internationalization
  
  # Visualization
  fl_chart: ^0.65.0
  
  # Location Services
  geolocator: ^10.1.0
  geocoding: ^2.1.0
  
  # State Management
  provider: ^6.1.0
  
  # Utilities
  path: ^1.8.0
  collection: ^1.17.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  test: ^1.24.0
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
│   │   ├── flight_log/
│   │   ├── flight_details/
│   │   ├── statistics/
│   │   ├── sites/
│   │   ├── wings/
│   │   └── settings/
│   ├── widgets/
│   │   ├── common/
│   │   ├── charts/
│   │   └── maps/
│   └── providers/
│       ├── flight_provider.dart
│       ├── statistics_provider.dart
│       └── settings_provider.dart
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

## 4. Implementation Strategy

### 4.1 Development Phases

#### Phase 1: Foundation (Week 1-2)

- Project setup and architecture
- Database implementation
- Basic flight model and repository
- Manual flight entry screen
- Flight list display

#### Phase 2: Core Features (Week 3-4)

- IGC parser implementation
- File import functionality
- Flight details screen
- Basic statistics
- Site management

#### Phase 3: Visualization (Week 5-6)

- Map integration
- Altitude/climb rate charts
- Flight replay animation
- Export functionality

#### Phase 4: Polish (Week 7-8)

- Settings implementation
- UI/UX refinement
- Performance optimization
- Testing and bug fixes

### 4.2 State Management Strategy

Using **Provider** for simplicity:

```dart
// Example: Flight List Provider
class FlightProvider extends ChangeNotifier {
  final FlightRepository _repository;
  List<Flight> _flights = [];
  bool _isLoading = false;
  
  List<Flight> get flights => _flights;
  bool get isLoading => _isLoading;
  
  Future<void> loadFlights() async {
    _isLoading = true;
    notifyListeners();
    
    _flights = await _repository.getAllFlights();
    
    _isLoading = false;
    notifyListeners();
  }
}
```

### 4.3 Performance Optimizations

1. **Database**
   - Use indexes on frequently queried fields
   - Implement pagination for large datasets
   - Cache computed statistics

2. **UI**
   - Lazy loading for flight list
   - Image caching for maps
   - Debounced search/filter operations

3. **IGC Processing**
   - Stream-based parsing for large files
   - Background isolate for heavy computations
   - Progressive loading for track visualization

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

## 7. Maintenance Plan

### 7.1 Update Schedule

- **Monthly**: Security patches
- **Quarterly**: Dependency updates
- **Bi-annually**: Flutter SDK updates

### 7.2 Monitoring

- Crash reporting via Flutter's built-in tools
- User feedback via Play Store reviews
- Performance monitoring in Play Console

### 7.3 Version Control

```bash
# Branching strategy
main          # Production releases
develop       # Development branch
feature/*     # Feature branches
release/*     # Release candidates
hotfix/*      # Emergency fixes
```

## 8. Cost Analysis

### 8.1 Development Costs

- **One-time**: Developer time only
- **Tools**: All development tools are free

### 8.2 Operational Costs

- **Hosting**: $0 (local app only)
- **Database**: $0 (SQLite)
- **Maps**: $0 (under free tier or OpenStreetMap)
- **Play Store**: $25 one-time developer fee

### 8.3 Total Cost of Ownership

- **Year 1**: $25 (Play Store fee)
- **Ongoing**: $0/year

## 9. Security Considerations

### 9.1 Data Protection

- All data stored locally on device
- No network transmission of personal data
- Optional app-level PIN/biometric lock

### 9.2 File Handling

- Validate all imported files
- Sanitize file paths
- Handle malformed data gracefully

## 10. Migration Strategy

### 10.1 From Existing App

1. Export data from old app
2. Import via CSV/IGC functions
3. Verify data integrity
4. Archive old app

### 10.2 Future Platform Support

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
flutter create free_flight_log --org com.example

# Run on device
flutter run
```

### B. Useful Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Material Design Guidelines](https://material.io/design)
- [IGC File Format Spec](http://www.fai.org/igc-documents)
- [SQLite Best Practices](https://www.sqlite.org/bestpractice.html)