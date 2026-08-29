# CLAUDE.md

## ⚡ Critical Rules (Read First)

- **NEVER use `print()` statements** - Use `LoggingService` instead
- **ALL flight data** must go through `FlightTrackLoader.loadFlightTrack()`
- **All track data is zero-based and trimmed** when received from FlightTrackLoader
- **ALWAYS Use free maps in development. Test on Linux desktop by default; emulator/device only for 3D**
- **ALWAYS Run `flutter analyze` and fix errors after complex, multi-file changes**

## 🚀 Running the app

**See the `run-app` skill** for the full command reference - Linux desktop and Android,
hot reload, screenshots, wireless adb, driving the UI. It is the single source of truth
for running the app - do not duplicate it here.

- **Debug builds** install as `com.theparaglidingapp.debug`, alongside any production
  install - never `pm clear`/uninstall the unsuffixed package, it holds the real flight
  log and exists nowhere else.
- **Test data**: drop real `.igc` files into `dev_data/igc/` (gitignored). App state
  (database + IGC copies) lives in `dev_data/app_documents/`, via `XDG_DOCUMENTS_DIR`,
  and persists across runs - use `bin/dev_run.sh --reset` to start clean.
- **Limitation**: no Linux implementation of `flutter_inappwebview`, so 3D map screens
  show a placeholder on desktop. Use an Android device/emulator for 3D work.

## ✅ Testing & quality

**See the `testing` skill** for the full command reference, the `network`-tag schedule,
and the fixture/in-memory-DB isolation rules that keep the suite from flaking. It is the
single source of truth - do not duplicate it here.

- `flutter analyze` after complex, multi-file changes.
- `flutter test` (plain - no concurrency flag needed locally). CI still uses
  `--concurrency=1`.
- `kill "$(cat dev_data/flutter.pid)"` to stop a running app.

## 📁 Key Files (Most Accessed)

| File | Purpose | Usage Frequency |
|------|---------|----------------|
| `lib/main.dart` | App entry point | Low |
| `lib/services/database_service.dart` | Main database layer | High |
| `lib/services/flight_track_loader.dart` | **Single source of truth** for flight data | High |
| `lib/services/logging_service.dart` | Claude-optimized logging | High |
| `lib/presentation/screens/flight_list_screen.dart` | Main flight list | High |
| `lib/presentation/screens/flight_detail_screen.dart` | Flight details | Medium |

## 📂 Code Layout

`lib/services/` (business logic - start here), `lib/presentation/screens/` and
`lib/presentation/widgets/{common,flight_*}`, `lib/data/models/` and
`lib/data/datasources/database_helper.dart` (schema & migrations).

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
| App won't start | Already running | `kill "$(cat dev_data/flutter.pid)"`, then start again |
| Hot reload does nothing | App not actually running | `kill -0 "$(cat dev_data/flutter.pid)"` - no pid file means it exited |
| `Gtk-WARNING cannot open display: :0` | Bash sandbox has no X11 display - the machine is not headless | Add `bin/dev_*.sh` to `sandbox.excludedCommands` (see the `sandbox-setup` skill) |
| Build dies on `Read-only file system` in `/tmp` or `~/.local/share/kotlin` | Bash sandbox filesystem policy | Add the path to `sandbox.filesystem.allowWrite` (see the `sandbox-setup` skill) |
| `Unable to create '.git/index.lock': File exists` | An index-writing git command was killed and left its lock | Check it is stale - `stat -c %y .git/index.lock` and `pgrep -a git` - then `rm -f .git/index.lock`. Never delete one while a git process is alive |

## Project Overview

The Paragliding App is a free, Android-first, cross-platform application for logging, reporting, and visualizing paraglider, hang glider, and microlight flights.

**Architecture**: MVVM with Repository pattern, Flutter + Material Design 3, SQLite database

**Scale**: Simple app with <10 screens, <5000 flights, <100 sites, <10 wings

**Documentation**: [Architecture](docs/TECHNICAL_DESIGN.md) | [Requirements](docs/FUNCTIONAL_SPECIFICATION.md)

## Claude Code Integration

**Bash sandbox** (per-developer, not configured in this repo): if a sandboxed command
fails looking like a headless machine, a dead network, or a read-only filesystem, it
usually isn't - see the `sandbox-setup` skill for this project's `excludedCommands`,
`filesystem.allowWrite`, and `network.strictAllowlist` requirements.

### Log Files for Monitoring

- **Output**: `dev_data/flutter.log` (full app output, truncated on each run)
- **PID**: `dev_data/flutter.pid` (written once the app is up, removed on exit - so its
  presence *is* the readiness check)

Both are per-checkout, so worktrees do not fight over them.

`flutter.log` ends with an explicit marker when the session dies:

```
--- flutter exited 2026-08-04 10:52:42 - log ends here; the app may still be running on the device ---
```

Without it, a log that stopped because `flutter run` died is indistinguishable from one with
nothing to report — a dropped session was once read as "the app was never touched", and the
wrong conclusion drawn from it. **On a device the app usually keeps running after flutter
detaches**, so the marker means the log stopped, not the app. Switch to `bin/dev_logs.sh`
from there: logcat is written by the app itself and survives a dropped `flutter run`.

### Reading logs from a device

`bin/dev_logs.sh` reads logcat over adb — the only option for a Play Store install, where
there is no `flutter run` at all. There is no logcat on Linux desktop, so `flutter.log`
remains the only log there, and it is also the only place build and compile errors appear.

```bash
bin/dev_logs.sh --keys       # just the [API_KEYS_STATUS] line
bin/dev_logs.sh -g cesium    # search the whole buffer
bin/dev_logs.sh -f           # follow live
bin/dev_logs.sh --tee        # follow live, appending to dev_data/logcat.log
```

**The logcat ring buffer is too small to read after the fact, and it is not `adbd`'s fault.**
This file blamed `adbd` retrying a USB bind for years; measuring it on 2026-08-11 found the
real source is `android.hardware.thermal-service.pixel`, which logs one `I pixel-thermal:`
line per sensor per poll — 84.5 lines/s, 79% of the buffer, leaving **~30 seconds** of
retention in the 256 KiB default. The wrong attribution sent a debugging session looking at
USB and adb, so prefer the numbers over the story:

```bash
adb shell setprop persist.log.tag.pixel-thermal S        # survives reboot, needs no root
adb shell setprop persist.log.tag.libPixelUsbOverheat S  # the second-largest source
adb shell logcat -G 4M     # re-apply each boot - persist.logd.size is refused without root
```

Measured after: **9.5 lines/s and ~65 min** of retention. `trusty` looks like the biggest
flooder in a plain `logcat -d` histogram and is a red herring — it is in the **kernel**
buffer, a separate 256 KiB ring that costs the app's log nothing.

Even 65 minutes is still a ring, so for anything you intend to read later use
`bin/dev_logs.sh --tee`: it copies the filtered stream to a host file where nothing ages
out. It appends and brackets each run with a marker, for the same reason `flutter.log` has
an exit marker — a capture that died with the adb connection must not read as an app with
nothing to say. The phone also dozes when idle, which kills `flutter run` (and with it
`dev_input.sh`, though not the app); Developer options → **"Stay awake"** avoids it.

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

### Verifying work: check the artifact, not the status

Summaries in this project lie in both directions. Every one of these cost real time:

| what it reported | what was true |
|---|---|
| CI run conclusion `cancelled` | its Play upload step had **succeeded** - the build was published |
| the deleted `flutter_controller_enhanced` status → `RUNNING` / `Pipe Responsive` | `flutter run` had **already exited**; hot reloads went into a dead pipe and did nothing |
| that same script → `CRASHED` / `ERROR` | app running fine; the *tooling* had disconnected, or the log merely contained an `[E]` line |
| a passing test | passed identically against the **unfixed** code |
| a green signing assertion | had never once been observed failing |

So:

- **A failing run can still have shipped.** Check the step, not the run: a cancel that
  lands after approval stops later jobs while the publish already went through. This is how
  version code 13 was burned.
- **Prove a regression test fails without the fix.** Revert the fix, run it, watch it go red.
  A test that passes either way is worse than none - it reads as coverage.
- **Assert against the underlying state, not the service reporting it.** Query `sqlite_master`
  rather than asking the service whether its tables exist.
- **Drive production code paths.** Recomputing an expected value in the test proves the test
  agrees with itself. `test/statistics_match_log_book_test.dart` calls the same
  `getYearlyStatistics()` / `getAllFlights()` the two screens call - that is what would have
  caught the duration bug.
- **A guard that has only been seen passing is unverified.** Both release assertions in
  `build.yml` were deliberately made to fail once, on a throwaway branch, to prove they work.

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

**The app is published, so schema and data changes need real migrations.** A user's flight
log exists nowhere else; clearing it is unrecoverable.

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

## 🌐 OpenAIP Integration

**See the `openaip` skill** for endpoints, auth, request/response format, and
troubleshooting - it is the single source of truth; do not duplicate it here.

One rule worth keeping inline because it costs real debugging time otherwise:
**airspace overlays are a bulk per-country download and need no API key; airports,
navaids and reporting points come from the authenticated API.** When airspace breaks,
check the bucket, not the key.

## 🚀 Development Workflow (Claude-Optimized)

### Worktrees

**See the `worktree` skill** for creating, bootstrapping (`bin/setup_worktree.sh`), and
merging/cleaning up a worktree - it is the single source of truth; do not duplicate it
here.

Two facts worth keeping top-of-mind: worktrees live in `.claude/worktrees/` (gitignored),
branched from `origin/main`; and after a squash merge, cleanup uses `git branch -D` (not
`-d`) - the branch's own commits are never ancestors of `main` even though the content
landed, so `-d` refuses it as a false negative.

### Standard Development Process

1. **Start**: `bin/dev_run.sh --background` (add `-d "<device>"` for a phone)
2. **Code**: Follow existing patterns, use `LoggingService` for debugging
3. **Test**: `bin/dev_reload.sh` for hot reload
4. **Debug**: `tail -n 50 dev_data/flutter.log` + screenshots
5. **Quality**: `flutter analyze` before committing
6. **Commit**: Only when user explicitly requests

### Releasing

**See the `release` skill** (`.claude/skills/release/`) for cutting a release: choosing the
version numbers, writing the user-facing notes, tagging, and checking the run actually
published. It is the single source of truth for the sequence, and defers to
`GOOGLE_PLAY_DEPLOYMENT.md` for the reference detail (CI structure, secrets, signing,
troubleshooting). Do not duplicate either one here.

### Common Task Patterns

| Task | Commands | Notes |
|------|----------|-------|
| Fix hot reload issues | `kill "$(cat dev_data/flutter.pid)"` → start again | No pid file means it already exited |
| Debug UI (desktop) | `bin/dev_screenshot.sh` → Read the PNG; `bin/dev_input.sh` to tap/scroll | Both go via the VM service, not the compositor - no screenshot or input tool works under Crostini |
| Debug UI (Android) | `adb exec-out screencap -p > dev_data/screenshot.png` → analyze | Unlock the phone first |
| Performance check | `grep "\[P\]" dev_data/flutter.log` | Performance logs |
| Schema change | Clear data → restart → reimport | Dev workflow |

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
- use adb screenshots on emulator; on Linux desktop use `bin/dev_screenshot.sh` (see the
  `run-app` skill - Wayland capture tools cannot work in this container)
- Call sites in local DB "Flown Sites" and sites from PGE API "New Sites"
- always start the app with `bin/dev_run.sh --background`
- **Driving the app's UI yourself is allowed** (adb since 2026-08-08, Linux desktop since
  2026-08-10; both were previously forbidden). Navigate to the screen you need and verify
  the change yourself rather than asking the user to tap through it — a UI fix nobody
  looked at is unverified. `bin/dev_input.sh` on desktop, `adb shell input` on a phone.
  See "Driving the UI" in the `run-app` skill for the commands, the coordinate rules and
  what to check afterwards.
- Filters in Map FIlter, e.g, checkboxes, should have immediate effect in the map
- When proposing a solution, look for the simple, idomatic solution suitable for a mobile app
