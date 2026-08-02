# CLAUDE.md

## ⚡ Critical Rules (Read First)

- **NEVER use `print()` statements** - Use `LoggingService` instead
- **ALL flight data** must go through `FlightTrackLoader.loadFlightTrack()`
- **All track data is zero-based and trimmed** when received from FlightTrackLoader
- **ALWAYS Use free maps in development. Test on Linux desktop by default; emulator/device only for 3D**
- **ALWAYS Run `flutter analyze` and fix errors after complex, multi-file changes**

## 🚀 Essential Commands

### Linux Desktop Loop (default - no emulator needed)

```bash
# WORKING DIRECTORY: /home/kmcisaac/Projects/the_paragliding_app (repo root)
bin/dev_run.sh                # Run on Linux desktop, seeded from dev_data/igc
bin/dev_run.sh --reset        # Wipe dev database + documents first, then re-seed
bin/dev_run.sh --profile      # Profile build - real timings, no hot reload
bin/dev_run.sh -d chrome      # Same, on another device

bin/dev_reload.sh             # Hot reload  (SIGUSR1 via dev_data/flutter.pid)
bin/dev_reload.sh R           # Hot restart (SIGUSR2) - needed for main()/initState changes
```

Hot reload also works with the standard `r` / `R` keys if you started it in a
terminal; `bin/dev_reload.sh` is for when the app was started in the background.

- **Test data**: drop ~10 real `.igc` files into `dev_data/igc/` (gitignored - real coordinates).
  They import on first launch only; `--reset` starts over. Seeding is driven by
  `--dart-define=SEED_IGC_DIR=...` and handled by `lib/utils/dev_seed.dart` (never runs in release).
- **App state** (database + IGC copies) lives in `dev_data/app_documents/`, redirected
  there via `XDG_DOCUMENTS_DIR`. It persists across runs — the seeder only imports when
  the flights table is empty, so relaunching keeps your data. Use `--reset` to start clean.
- **Limitation**: `flutter_inappwebview` has no Linux implementation, so the 3D map screens
  show a "3D Map Not Available" placeholder. Use an Android device/emulator for 3D work.

### Android Loop (emulator/device - required for 3D)

The script lives at `bin/flutter_controller_enhanced` and is **not on `PATH`** - invoke it
by path. It takes the Flutter project directory from the shell's cwd, so it must be run
from `the_paragliding_app/` or it fails with `No pubspec.yaml file found`.

```bash
# WORKING DIRECTORY: /home/kmcisaac/Projects/the_paragliding_app/the_paragliding_app
../bin/flutter_controller_enhanced run # Start app with logging. ALWAYS run in background
../bin/flutter_controller_enhanced r    # Hot reload with readiness check (most used)
../bin/flutter_controller_enhanced R    # Hot restart with readiness check (for state issues)
../bin/flutter_controller_enhanced status     # Check app status with enhanced health info
../bin/flutter_controller_enhanced logs 50    # Recent logs (prefer over bash output)
../bin/flutter_controller_enhanced screenshot # Take screenshot (alias: ss)
../bin/flutter_controller_enhanced q    # Quit app
```

Defaults to `emulator-5554`; pass `-d <device>` for anything else. Its `screenshot`
command shells out to adb, so it only works on Android targets.

Debug builds install as `com.theparaglidingapp.debug` with the launcher name
"Paragliding App (debug)", so they sit alongside a Play Store install instead of
replacing it. Without that suffix the debug keystore clashes with the release
signature (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) and Flutter silently uninstalls the
production app, taking its flight database with it.

#### Wireless debugging (physical device)

```bash
# On the phone: Settings > System > Developer options > Wireless debugging
adb pair <ip>:<pairing-port> <6-digit-code>   # "Pair device with pairing code" dialog
adb connect <ip>:<connect-port>               # DIFFERENT port, on the main screen
adb devices -l                                # confirm, then use -d <id>
```

The pairing port and the connect port are different - mixing them up is the usual
failure. Pairing is permanent; re-run only `adb connect` in later sessions. A stale
pairing dialog leaves its port listening but dead, which surfaces as
`error: protocol fault (couldn't read status message)` - reopen the dialog for a fresh
port and code. `adb mdns services` returns nothing from a Crostini container (multicast
does not cross the NAT), so always use an explicit `IP:port`.

### Test & Quality Commands

```bash
flutter analyze                       # Check for errors (run after complex, mult-file change)
flutter test                          # Run all tests
flutter test test/specific_test.dart  # Run specific test
flutter test --tags network --run-skipped  # Live-API tests, skipped by default
flutter_controller_enhanced cleanup   # Clean up processes if stuck
flutter_controller_enhanced health    # Check process/pipe/readiness status
```

**Plain `flutter test` is fine locally.** It used to fail about 1 run in 3, so this file
told you to always pass `--concurrency=1`. Issue #280 fixed the underlying test problems;
measured over 16 consecutive runs on an 8-core dev box, parallel is now 0/16 failures and
the fastest of the three modes (mean 46s, vs 60s serial, vs 81s serial before the fix).

Keep the tests isolated, or this comes back:

- **Never write fixtures to a fixed path.** Use `TestHelpers.fixturePath('name.igc')`, which
  gives each test process its own directory. Fixed `/tmp` paths caused a real failure -
  two test files both wrote `/tmp/test_india.igc`, and one run read a fixture back empty
  (`Parsed 0 track points, pilot: Unknown`).
- **The test database is in-memory** (`TestHelpers.initializeDatabaseForTesting()` sets
  `DatabaseHelper.databasePathOverride`). Don't reintroduce a file-backed one, and don't
  add per-test `recreateDatabase()` unless a test actually writes - eight read-only tests
  were rebuilding the schema and re-seeding 249 country codes nine times per run.

**CI still passes `--concurrency=1`** (`.github/workflows/ci.yml`). That is deliberate and
not stale: parallel was only verified on an 8-core dev machine, and hosted runners have
far fewer cores. Re-measure there before changing it.

`concurrency:` cannot be set in `dart_test.yaml` - `flutter test` always passes its own
`-j` and overrides the file. It has to be on the command line.

## 📁 Key Files (Most Accessed)

| File | Purpose | Usage Frequency |
|------|---------|----------------|
| `lib/main.dart` | App entry point | Low |
| `lib/services/database_service.dart` | Main database layer | High |
| `lib/services/flight_track_loader.dart` | **Single source of truth** for flight data | High |
| `lib/services/logging_service.dart` | Claude-optimized logging | High |
| `lib/presentation/screens/flight_list_screen.dart` | Main flight list | High |
| `lib/presentation/screens/flight_detail_screen.dart` | Flight details | Medium |

## 📂 File Structure Quick Reference

```
lib/
├── services/                    # Core business logic (MOST IMPORTANT)
│   ├── database_service.dart    # All DB operations
│   ├── flight_track_loader.dart # Single source of truth for flight data
│   ├── logging_service.dart     # Claude-optimized logging
│   ├── igc_import_service.dart  # File import workflow
│   └── takeoff_landing_detector.dart
├── presentation/
│   ├── screens/                 # Full-screen UI components
│   │   ├── flight_list_screen.dart      # Main app screen
│   │   ├── flight_detail_screen.dart    # Flight details
│   │   ├── igc_import_screen.dart       # File import UI
│   │   └── data_management_screen.dart  # Settings/admin
│   └── widgets/
│       ├── common/              # Reusable widgets
│       │   ├── app_stat_card.dart       # Statistics display
│       │   ├── app_expansion_card.dart  # Collapsible content
│       │   ├── app_empty_state.dart     # Empty list states
│       │   └── app_error_state.dart     # Error displays
│       └── flight_*_widget.dart # Flight-specific components
├── data/
│   ├── models/                  # Data structures
│   │   ├── flight.dart          # Core flight model
│   │   ├── igc_file.dart        # Track data structure
│   │   └── site.dart / wing.dart # Supporting models
│   └── datasources/
│       └── database_helper.dart # SQLite schema & migrations
└── main.dart                    # App entry point
```

## 🚨 Common Error Patterns & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `print()` used | Direct print call | Use `LoggingService.info()` instead |
| Track data empty | Direct IGC parsing | Use `FlightTrackLoader.loadFlightTrack()` |
| State not updating | Widget not rebuilding | Check `setState()` calls |
| Database locked | Concurrent operations | Use `DatabaseService` methods |
| Tests fail with `TimeoutException` | A test file opens a file-backed database, or does needless DB lifecycle churn | Keep the test DB in-memory; don't add per-test `recreateDatabase()` (see #280) |
| Test reads its own fixture back empty | Fixture written to a fixed `/tmp` path | Use `TestHelpers.fixturePath('name.igc')` |
| Test hits the network | Live-API test not tagged | Tag it `network`; it is skipped by default |
| Hot reload fails | State corruption | Use `R` (hot restart) instead of `r` |
| App won't start | Process still running | Run `flutter_controller_enhanced cleanup` |
| Commands unresponsive | Pipe/readiness issues | Run `flutter_controller_enhanced health` |
| Race conditions | Commands sent too early | Commands now auto-wait for readiness |

## Project Overview

The Paragliding App is a free, Android-first, cross-platform application for logging, reporting, and visualizing paraglider, hang glider, and microlight flights.

**Architecture**: MVVM with Repository pattern, Flutter + Material Design 3, SQLite database

**Scale**: Simple app with <10 screens, <5000 flights, <100 sites, <10 wings

**Documentation**: [Architecture](docs/TECHNICAL_DESIGN.md) | [Requirements](docs/FUNCTIONAL_SPECIFICATION.md)

## Claude Code Integration

### Log Files for Monitoring

- **Output**: `/tmp/flutter_controller/flutter_output.log` (full app output)
- **Status**: `/tmp/flutter_controller/flutter_status` (running/stopped)
- **PID**: `/tmp/flutter_controller/flutter.pid` (process tracking)
- **Screenshots**: `/tmp/flutter_controller/screenshots/` (also copied to `/tmp/`)

### Claude-Specific Patterns

```dart
// File navigation format for Claude
LoggingService.info('Error in flight loading'); // Outputs: at=flight_service.dart:142

// Structured data for Claude analysis  
LoggingService.structured('PERFORMANCE', {
  'operation': 'database_query',
  'duration_ms': 245,
  'rows_returned': 1500,
});

// Error reporting with context
try {
  await operation();
} catch (error, stackTrace) {
  LoggingService.error('Operation failed', error, stackTrace);
  // Claude can parse the structured error output
}
```

### Testing Integration  

```bash
# Run tests with Claude-readable output
flutter test --reporter=expanded          # Detailed test output
flutter test test/services/               # Test specific directory
flutter test test/flight_test.dart        # Single test file
flutter analyze --write=analyzer.log      # Save analysis to file

# Generate coverage for Claude analysis
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html/
```

## Development Principles

### Core Rules

- **Keep it Simple**: Choose simple, proven solutions over complex architectures
- **State Management**: Simple StatefulWidget with direct database access
- **Database**: Simple management - <10 tables, largest <5000 rows
- **Idiomatic**: Use idomatic language/tool-native approaches (Flutter, Cesium, JavaScript)
- **WebView Constraints**: No ES6 modules, single JS context
- **Error Recovery**: Add fallbacks for external services

### Testing & Performance

- Add Claude-readable logging for debugging and performance
- Run analyzer to check for errors after complex multi-file changes
- Measure performance before optimizing
- Default to emulator for testing

## ✅❌ Code Patterns & Anti-Patterns

### Logging (ALWAYS use LoggingService)

```dart
import 'package:the_paragliding_app/services/logging_service.dart';

// ✅ Correct logging patterns
LoggingService.info('General information');
LoggingService.error('Database error', error, stackTrace);
LoggingService.structured('IGC_IMPORT', {'file': 'flight.igc', 'points': 1091});
LoggingService.performance('Database Query', duration, 'flights loaded');

// ❌ NEVER use these
print('Debug message');              // Use LoggingService.info() instead
debugPrint('Flutter debug');         // Use LoggingService.debug() instead
developer.log('Developer log');      // Use LoggingService.info() instead
```

### Flight Data (Single Source of Truth)

```dart
// ✅ Always use FlightTrackLoader
final igcFile = await FlightTrackLoader.loadFlightTrack(flight);
final trackPoints = igcFile.trackPoints; // Already trimmed and zero-based
final distance = igcFile.calculateGroundTrackDistance();

// ❌ Never parse IGC files directly
final rawIgc = File(flight.igcFilePath).readAsStringSync(); // Wrong!
final parser = IgcParser(); // Don't use directly in UI
final customTrimmed = trackPoints.sublist(10, -10); // Wrong indexing!
```

### Database Operations

```dart
// ✅ Use DatabaseService methods
final flights = await DatabaseService.instance.getAllFlights();
await DatabaseService.instance.insertFlight(flight);

// ❌ Never use raw SQLite directly
final db = await openDatabase('path'); // Use DatabaseService instead
db.rawQuery('SELECT * FROM flights'); // Use typed methods instead
```

### Widget Creation Patterns

```dart
// ✅ Follow existing widget patterns
AppStatCard.flightList(
  title: 'Total Flights',
  value: '42',
  icon: Icons.flight,
);

AppExpansionCard.dataManagement(
  title: 'Export Data',
  children: [exportButtons],
);

AppEmptyState.flights(
  message: 'No flights logged yet',
  actionButton: AddFlightButton(),
);

// ❌ Don't create custom cards when standard ones exist
Card(child: ListTile(...)); // Use AppStatCard instead
ExpansionTile(...);         // Use AppExpansionCard instead
```

### State Management

```dart
// ✅ Simple StatefulWidget pattern (project standard)
class FlightListScreen extends StatefulWidget {
  @override
  _FlightListScreenState createState() => _FlightListScreenState();
}

class _FlightListScreenState extends State<FlightListScreen> {
  List<Flight> _flights = [];
  
  @override
  void initState() {
    super.initState();
    _loadFlights();
  }
  
  Future<void> _loadFlights() async {
    final flights = await DatabaseService.instance.getAllFlights();
    setState(() => _flights = flights);
  }
}

// ❌ Don't use complex state management
// Avoid Provider, Bloc, Riverpod - this project uses simple StatefulWidget
```

### Log Format (Claude-optimized)

```
[I][+1.2s] App startup completed | at=splash_screen.dart:32
[D][+5.1s] [IGC_IMPORT] file=flight.igc | points=1091 | at=igc_import_service.dart:85
[P][+2.1s] Database Query | 156ms | flights loaded | at=database_service.dart:245
```


### Data Flow

```
IGC File (Full/Archival) → Detection → Store Full Indices → Load Trimmed → App Uses Zero-Based
```

**Key Services**: `FlightTrackLoader` (single source), `TakeoffLandingDetector`, `IgcParser`, `IgcImportService`

## 📊 Performance Guidelines & Thresholds

### Database Performance

| Operation | Target Time | Alert Threshold | Notes |
|-----------|-------------|-----------------|-------|
| Load all flights | <200ms | >500ms | ~5000 flights max |
| Single flight query | <50ms | >100ms | By ID or simple filter |
| IGC file loading | <1s | >3s | Includes parsing + trimming |
| Database startup | <300ms | >1s | App launch impact |

### UI Performance

| Component | Target | Alert | Notes |
|-----------|--------|-------|-------|
| Hot reload | <2s | >5s | Code changes |
| Screen navigation | <300ms | >1s | Between screens |
| List scrolling | 60fps | <30fps | Flight list with 1000+ items |
| Widget rebuilds | Minimal | Excessive | Use `const` constructors |

### Memory Guidelines

- **IGC File Cache**: Max 10 files in `FlightTrackLoader` LRU cache
- **Database Connections**: Use single instance via `DatabaseService`
- **Widget State**: Clear heavy objects in `dispose()`
- **Image Memory**: Lazy load screenshots, compress if >1MB

### Optimization Tips

```dart
// ✅ Efficient list building
ListView.builder(
  itemCount: flights.length,
  itemBuilder: (context, index) => FlightListItem(flights[index]),
);

// ✅ Const constructors for static widgets
const AppStatCard.flightList(title: 'Static Title');

// ✅ Dispose heavy resources
@override
void dispose() {
  _controller?.dispose();
  _subscription?.cancel();
  super.dispose();
}

// ❌ Performance anti-patterns
ListView(children: flights.map((f) => Widget(f)).toList()); // Builds all at once
setState(() {}); // In build() method - causes infinite rebuilds
```

## 🔍 Quick Reference Tables

### Database Tables (Core Schema)

| Table | Primary Key | Key Columns | Purpose |
|-------|-------------|-------------|---------|
| `flights` | `id` | `date`, `site_id`, `wing_id` | Flight records |
| `sites` | `id` | `name`, `latitude`, `longitude` | Launch/landing sites |
| `wings` | `id` | `manufacturer`, `model` | Equipment |
| `igc_files` | `flight_id` | `filename`, `track_points` | Track data |

### Common File Operations

| Task | File/Service | Method | Notes |
|------|-------------|--------|-------|
| Load flight data | `FlightTrackLoader` | `loadFlightTrack(flight)` | Single source of truth |
| Database query | `DatabaseService` | `getAllFlights()`, `getFlight(id)` | Typed methods |
| Import IGC | `IgcImportService` | `importIgcFile(path)` | Full workflow |
| Logging | `LoggingService` | `info()`, `error()`, `structured()` | Claude-optimized |

### Widget Quick Reference

| UI Pattern | Widget | Usage |
|------------|--------|--------|
| Statistics display | `AppStatCard.flightList()` | Flight counts, totals |
| Empty states | `AppEmptyState.flights()` | No data scenarios |
| Expandable content | `AppExpansionCard.dataManagement()` | Settings panels |
| Loading states | `AppLoadingSkeleton` | Data fetching |
| Error display | `AppErrorState` | Error handling with retry |

## Database Development

**The app is published, so schema and data changes need real migrations.** This section
used to say "no migrations, clear app data" - that was written pre-release and is now
wrong: a user's flight log exists nowhere else, and clearing it is unrecoverable.

### Schema Change Process

1. Bump `databaseVersion` in `database_helper.dart`
2. Add an `if (oldVersion < N)` branch to `_onUpgrade`, following the existing ones
3. **Log how many rows a data migration changed.** A migration that rewrites user data
   silently cannot be audited afterwards - see `backfillDetectedDurations`
4. Test the upgrade path, not just the fresh-install path. `test/duration_backfill_test.dart`
   is the pattern: annotate the migration `@visibleForTesting` and drive it directly, rather
   than duplicating its SQL in the test where the two can drift apart
5. Verify a fresh install still works - `_onCreate` and `_onUpgrade` must converge on the
   same schema

### Clearing data (development only)

Clearing app data is fine on a dev machine and never appropriate as a user-facing fix.
On Linux desktop use `bin/dev_run.sh --reset`. On Android: Settings → Apps →
**Paragliding App (debug)** → Storage → Clear Data. Pick the "(debug)" entry - a production
install may sit next to it under "The Paragliding App", and clearing that one destroys real
flight data.

## Key Calculations & Data

### Flight Calculations

- **Altitude**: Always use GPS
- **Speed**: GPS with time between readings
- **Climb Rate**: Pressure if available, otherwise GPS with time deltas
- **Calculate**: Both instantaneous and 15s trailing average climb rates

### Timestamp Handling

- **IGC**: UTC time (HHMMSS) → Detect timezone from GPS → Convert to local
- **Display**: Local timezone of launch location
- **Database**: ISO8601 date + HH:MM times + timezone offset
- **Cesium**: ISO8601 with timezone (e.g., "2025-07-11T11:03:56.000+02:00")

### External Dependencies

- **Maps**: Assume quotas exist, default to free providers (OpenStreetMap)
- **GPS**: Primary data source for all calculations
- **IGC Files**: Immutable once imported, parse once and store results

## 🌐 OpenAIP API Integration

### Overview

The Paragliding App integrates with OpenAIP Core API for aviation data overlays including airspaces, airports, navigation aids, and reporting points.

### API Endpoints & Authentication

```
Base URL: https://api.core.openaip.net/api
Authentication: API key as query parameter (?apiKey=xxx)
```

**Working Endpoints:**

- `/api/airspaces` - Controlled airspace polygons (CTR, TMA, CTA, danger areas, etc.)
- `/api/airports` - Airport point data with details and frequencies
- `/api/navaids` - Navigation aids (VOR, NDB, DME, waypoints)
- `/api/reporting-points` - VFR reporting points with altitude restrictions

### Request Format

```http
GET /api/{endpoint}?bbox=west,south,east,north&limit=500&apiKey={key}
Headers:
  Accept: application/json
  User-Agent: TheParaglidingApp/1.0
```

### Response Format

All endpoints return GeoJSON FeatureCollection with:

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "_id": "unique_identifier",
      "geometry": { "type": "Point|Polygon", "coordinates": [...] },
      "properties": { endpoint-specific data }
    }
  ]
}
```

### Code Integration

**Service Architecture:**

- `AirspaceGeoJsonService` - Handles airspace polygons and styling
- `AviationDataService` - Handles airports, navaids, reporting points
- `AirspaceOverlayManager` - Coordinates all aviation data layers
- `OpenAipService` - Manages API keys and layer preferences

**Key Implementation Points:**

```dart
// ✅ Correct authentication (URL parameter, not headers)
final url = 'https://api.core.openaip.net/api/airports'
    '?bbox=$west,$south,$east,$north&limit=500&apiKey=$apiKey';

// ✅ Standard headers (same as working airspace service)
final headers = {
  'Accept': 'application/json',
  'User-Agent': 'TheParaglidingApp/1.0',
};

// ✅ Individual caching per data type
final airports = await AviationDataService.instance.fetchAirports(bounds);
```

### Visual Representation

- **Airspaces**: Semi-transparent polygons with type-specific colors
- **Airports**: Circular markers with airplane icons, sized by category
- **Navaids**: Symbol markers (⬡ VOR, ● NDB, ◇ DME, ◉ Waypoints)
- **Reporting Points**: Triangle markers with altitude restriction tooltips

### Troubleshooting

| Issue | Cause | Solution |
|-------|--------|----------|
| 401 Auth Failed | Invalid API key | Check OpenAIP account, verify key |
| 404 Not Found | Wrong endpoint | Use full names: `/airports` not `/apt` |
| No data returned | Geographic bounds | Try different location/zoom level |
| Headers auth failure | Wrong auth method | Use query parameter, not headers |

### Logging Integration

All API calls generate structured logs:

```
[AIRPORTS_API_REQUEST] url=*** | bounds=*** | has_api_key=true
[AIRPORTS_API_SUCCESS] airports_count=15 | cache_key=***
```

## 🚀 Development Workflow (Claude-Optimized)

### Worktrees

Do feature and bugfix work in a git worktree, one per task, branched from `origin/main`.
They live in `.claude/worktrees/` (gitignored) and are removed once the work merges.

A fresh worktree has none of the gitignored files. After creating one, from
`the_paragliding_app/`:

```bash
MAIN=/home/kmcisaac/Projects/the_paragliding_app/the_paragliding_app
cp "$MAIN/env.json" env.json                              # API keys
cp "$MAIN/android/key.properties" android/key.properties  # release signing
flutter pub get
```

Neither omission fails loudly, and the signing one is dangerous:

- **`env.json` missing** — everything builds and runs, but FFVL weather, OpenAIP overlays
  and Cesium 3D are silently unconfigured. `bin/dev_run.sh` and
  `bin/flutter_controller_enhanced` warn; a bare `flutter run` does not. Confirm with the
  `[API_KEYS_STATUS]` line at startup.
- **`android/key.properties` missing** — `flutter build appbundle --release` **succeeds**
  and signs with the *debug* key. `android/app/build.gradle.kts` falls back deliberately
  and only `println`s a warning, which is invisible in normal build output. Play rejects
  the upload. Always verify before uploading:

  ```bash
  keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep -E "Owner:|SHA256:"
  ```

  Expect `Owner: CN=Kevin McIsaac, ...`. `CN=Android Debug` means the fallback fired.
  The fingerprint must match `upload-cert-new.pem`:
  `openssl x509 -in ../upload-cert-new.pem -noout -fingerprint -sha256`

Also absent: `.dart_tool/`, `build/`, and `dev_data/` — re-seed `dev_data/igc` only if the
task needs the app to actually run.

### Standard Development Process

1. **Start**: `flutter_controller_enhanced run` from correct directory
2. **Code**: Follow existing patterns, use `LoggingService` for debugging
3. **Test**: `flutter_controller_enhanced r` for hot reload
4. **Debug**: `flutter_controller_enhanced logs 50` + screenshots
5. **Quality**: `flutter analyze` before committing
6. **Commit**: Only when user explicitly requests

### Common Task Patterns

| Task | Commands | Notes |
|------|----------|-------|
| Fix hot reload issues | `health` → `cleanup` → `restart` | Enhanced diagnostics first |
| Debug UI | `screenshot` → analyze | Visual debugging |
| Performance check | `logs 50` → filter `[P]` | Performance logs |
| Schema change | Clear data → restart → reimport | Dev workflow |
| Troubleshoot unresponsive commands | `health` → `status` | Check all health indicators |
| Force readiness wait | `wait-ready 30` | Before critical operations |

### File Navigation for Claude

Use format `file_path:line_number` in logs:

- `flight_service.dart:142` - Easy navigation
- `database_service.dart:67` - Clickable in IDE
- `logging_service.dart:28` - Jump to source

---

📚 **Detailed Documentation**:

- [IGC Data Trimming](docs/IGC_TRIMMING.md) - Track data processing
- [Database Schema](docs/DATABASE.md) - Complete table definitions
- [Timestamp Processing](docs/TIMESTAMPS.md) - UTC/local conversion
- at the end of complex set of changes use flutter analyze to find errors
- use adb screenshots on emulator
- Call sites in local DB "Flown Sites" and sites from PGE API "New Sites"
- Call sites in local DB "Flown Sites" and sites from PGE API "New Sites"
- always run flutter_controller_enhanced in background
- DOnt try to contol the app
- don't try to controll app with adb
- Filters in Map FIlter, e.g, checkboxes, should have immediate effect in the map
- When proposing a solution, look for the simple, idomatic solution suitable for a mobile app