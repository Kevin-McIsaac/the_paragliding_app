# The Paragliding App — agent rules

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

**See the `testing` skill** for this repo's command reference, the `network`-tag schedule,
and the fixture/in-memory-DB isolation rules that keep the suite from flaking. The
environment export and the generic analyze/test discipline are in the global
**`flutter-dev`** skill; how to decide whether a result actually proves anything is
**`verification`**. Do not duplicate any of them here.

- `kill "$(cat dev_data/flutter.pid)"` to stop a running app.

## 🤖 Agent environment facts (read before running anything)

These cost real debugging time when learned by trial and error (2026-09-05,
WU PWS session - three failed app starts and one wrong-directory analyze run;
2026-09-12, wireless-adb session - the two `adb`s and the missing sudo):

1. **Read the relevant skill FIRST, before running its commands.**
   Project skills live in `.agents/skills/`, which DSH scans directly, so load them with
   the `skill` tool - `read` by path only if the catalog is missing one. Non-negotiable
   triggers:
   - about to run the app, reload, screenshot, drive the UI, or use adb
     → `run-app`
   - about to run `flutter test`, `flutter analyze`, or touch fixtures
     → `testing` (repo specifics) plus `flutter-dev` (the environment export)
   Do not reconstruct the commands from memory - the skills carry traps this
   file deliberately does not duplicate.

2. **Agent shells do not inherit the interactive environment.** `flutter` is not on PATH
   (it lives at `~/flutter/bin`), and the sandbox's read-only `$HOME` breaks Flutter's own
   config writes. The export, the writable-`$HOME` recipe for `flutter devices`, and the
   two-`adb` situation are in the **`flutter-dev`** global skill - do not reconstruct them
   from memory. **The export is needed whether or not the sandbox is off**: the PATH gap is
   a shell-environment issue, not a sandbox one (verified 2026-09-05: sandbox off with no
   export still fails with `setsid: failed to execute flutter`).

3. **An agent shell has no working `sudo` - system changes are the human's job.** `sudo`
   dies with `The "no new privileges" flag is set`, so nothing can be installed, removed or
   symlinked system-wide from an agent shell, not even with escalated file access. The
   ownership and read-only errors it reports are **sandbox artifacts, not your real
   filesystem** - see the **`machine-env`** global skill. Ask the human to run the command
   in their own terminal rather than escalating repeatedly, and verify the artifact
   afterwards (the adb symlink in item 2 was installed exactly that way).

4. **Working directory**: `flutter analyze` / `flutter test` run from
   `the_paragliding_app/`, not the repo root. `bin/dev_*.sh` run from the repo
   root. Getting this wrong can silently analyze/build the wrong tree (a
   root-level run once reported "39645 issues" from build artifacts).

## 📁 Key Files (Most Accessed)

| File | Purpose | Usage Frequency |
|------|---------|----------------|
| `lib/main.dart` | App entry point | Low |
| `lib/services/database_service.dart` | Main database layer | High |
| `lib/services/flight_track_loader.dart` | **Single source of truth** for flight data | High |
| `lib/services/logging_service.dart` | Structured logging | High |
| `lib/presentation/screens/flight_list_screen.dart` | Main flight list | High |
| `lib/presentation/screens/flight_detail_screen.dart` | Flight details | Medium |

Paths in this table and in Code Layout are relative to `the_paragliding_app/`.

## 📂 Code Layout

`lib/services/` (business logic - start here), `lib/presentation/screens/` and
`lib/presentation/widgets/{common,flight_*}`, `lib/data/models/` and
`lib/data/datasources/database_helper.dart` (schema & migrations).

## 🚨 Common Error Patterns & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| Tests fail with `TimeoutException` | A test file opens a file-backed database, or does needless DB lifecycle churn | Keep the test DB in-memory; don't add per-test `recreateDatabase()` (see #280) |
| Test reads its own fixture back empty | Fixture written to a fixed `/tmp` path | Use `TestHelpers.fixturePath('name.igc')` |
| Test hits the network | Live-API test not tagged | Tag it `network`; it is skipped by default |
| Hot reload fails | State corruption | Use `R` (hot restart) instead of `r` |
| App won't start | Already running | `kill "$(cat dev_data/flutter.pid)"`, then start again |
| Hot reload does nothing | App not actually running | `kill -0 "$(cat dev_data/flutter.pid)"` - no pid file means it exited |
| `Gtk-WARNING cannot open display: :0` | DSH hides the X11 socket - the machine is not headless | Use the Wayland socket (`sandbox-setup` skill), then escalate once |
| Build dies on `Read-only file system` in `/tmp` or `~/.local/share/kotlin` | DSH sandbox filesystem policy | Use the `flutter-dev` writable-HOME export, then escalate once (see the `sandbox-setup` skill) |

## Project Overview

The Paragliding App is a free, Android-first, cross-platform application for logging, reporting, and visualizing paraglider, hang glider, and microlight flights.

**Architecture**: MVVM with Repository pattern, Flutter + Material Design 3, SQLite database

**Scale**: Simple app with <10 screens, <5000 flights, <100 sites, <10 wings

**Documentation**: [Index](docs/README.md) | [Architecture](docs/TECHNICAL_DESIGN.md) | [Requirements](docs/FUNCTIONAL_SPECIFICATION.md)

## DSH integration

**DSH** is the current harness. It reads `AGENTS.md` and the project skills. See
[docs/DSH.md](docs/DSH.md) for skills, sandbox recovery, and CI. The retired Claude Code
review workflow is in `docs/archive/claude-code/`.

### Logs

`dev_data/flutter.log` is the app's output on desktop, and the only place build and compile
errors appear. It ends with an explicit marker when the session dies:

```
--- flutter exited 2026-08-04 10:52:42 - log ends here; the app may still be running on the device ---
```

Without it, a log that stopped because `flutter run` died is indistinguishable from one with
nothing to report — a dropped session was once read as "the app was never touched", and the
wrong conclusion drawn from it. **On a device the app usually keeps running after flutter
detaches**, so the marker means the log stopped, not the app.

For device logs (`bin/dev_logs.sh`, logcat ring-buffer tuning) see the `run-app` skill, and
for analysing a log against the performance thresholds load the `flutter-log-analyzer`
skill.

This marker is the local instance of the global **`verification`** rule: the presence of the
marker is evidence, and a log that merely stops is not.

**The `flutter-log-analyzer` skill contains its agent definition in `agent.md`.** Load the
skill and follow it. Pass the agent file and the log path to a subagent when the log is
large. Project skills live in `.agents/skills/`, so load them with the `skill` tool.

### Logging patterns

```dart
// File navigation format
LoggingService.info('Error in flight loading'); // Outputs: at=flight_service.dart:142

// Structured data for analysis
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
  // The structured error output is easy to parse.
}
```

Use `file_path:line_number` in logs. The values are clickable in the IDE.

## Development Principles

### Core Rules

- **Keep it Simple**: Choose simple, proven solutions over complex architectures.
- **Idiomatic**: Use idiomatic Flutter, Cesium, and JavaScript patterns.
- **WebView Constraints**: No ES6 modules, single JS context.
- **Error Recovery**: Add fallbacks for external services.

### Testing & Performance

- Add structured logging for debugging and performance
- Measure performance before optimizing; the thresholds live in the
  `flutter-log-analyzer` agent

## Conventions

`LoggingService` for all output (never `print`/`debugPrint`/`developer.log`),
`FlightTrackLoader` for all flight data, `DatabaseService` for all queries (never raw
`openDatabase`/`rawQuery`), and simple `StatefulWidget` state — no Provider, Bloc or
Riverpod. Follow the surrounding code for shape; the reusable widgets are in
`lib/presentation/widgets/common/` (`AppStatCard`, `AppExpansionCard`, `AppEmptyState`,
`AppErrorState`, `AppLoadingSkeleton`) — use them rather than raw `Card`/`ExpansionTile`.

### Log format

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

## Database

**The app is published, so schema and data changes need real migrations.** A user's flight
log exists nowhere else; clearing it is unrecoverable. `databaseVersion` is 5, with real
`_onUpgrade` branches for 2–5.

See [docs/DATABASE.md](docs/DATABASE.md) for the schema-change process and the
development-only ways to clear data.

## Key Calculations & Data

### Flight Calculations

- **Altitude**: Always use GPS
- **Speed**: GPS with time between readings
- **Climb Rate**: Pressure if available, otherwise GPS with time deltas
- **Calculate**: Both instantaneous and 15s trailing average climb rates

Timestamp handling (UTC → GPS-derived timezone → local, and the Cesium/database formats)
is in [docs/TIMESTAMPS.md](docs/TIMESTAMPS.md).

### External Dependencies

- **Maps**: Assume quotas exist, default to free providers (OpenStreetMap)
- **GPS**: Primary data source for all calculations
- **IGC Files**: Immutable once imported, parse once and store results

## 🌐 OpenAIP Integration

**See the `openaip` skill** for the data paths, the tile layer, and troubleshooting - it
is the single source of truth; do not duplicate it here.

One rule worth keeping inline because it costs real debugging time otherwise:
**airspace polygons are a keyless bulk per-country download; the API key is for the map
tile layer only.** When airspace breaks, check the bucket, not the key.

## 🚀 Development workflow

### Worktrees

**See the `git-worktree` global skill** for the portable mechanics (create from
`origin/main`, bootstrap, merge, `-D` cleanup, proving a merge landed) and the **`worktree`
project skill** for this repo's `bin/setup_worktree.sh`, the gitignored-file traps and the
DSH shared-checkout rule. Do not duplicate either here.

Worktrees live in `.claude/worktrees/` (gitignored), branched from `origin/main`.

Under DSH, nothing blocks a background job or subagent from moving HEAD in the shared
checkout. Run ref-moving git commands in a worktree.

### Standard Development Process

Follow the `run-app` loop: start, code, hot reload, read the log, then run
`flutter analyze`.

### Releasing

**See the `release` skill** for cutting a release: choosing the version numbers, writing the
user-facing notes, tagging, and checking the run actually published. It is the single source
of truth for the sequence, and defers to `GOOGLE_PLAY_DEPLOYMENT.md` for the reference detail
(CI structure, secrets, signing, troubleshooting). The generic `gh` merge and CI-verification
commands are in **`gh-pr`**, and whether a result proves anything is **`verification`**. Do
not duplicate any of them here.

### Common task patterns

The `run-app` skill owns hot reload, screenshots, input, and device logs. The
`flutter-log-analyzer` skill owns log performance checks. See
[docs/DATABASE.md](docs/DATABASE.md) for a schema change.

### Naming & UI conventions

- Sites in the local DB are **"Flown Sites"**; sites from the PGE API are **"New Sites"**.
- Map filter controls (checkboxes and the like) take effect on the map immediately.

---

📚 **Detailed Documentation**:

- [IGC Data Trimming](docs/IGC_TRIMMING.md) - Track data processing
- [Database](docs/DATABASE.md) - Schema, migrations, clearing dev data
- [Timestamp Processing](docs/TIMESTAMPS.md) - UTC/local conversion
- [Architecture](docs/TECHNICAL_DESIGN.md) | [Requirements](docs/FUNCTIONAL_SPECIFICATION.md)
