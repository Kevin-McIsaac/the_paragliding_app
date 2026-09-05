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

## 🤖 Agent environment facts (read before running anything)

These cost real debugging time when learned by trial and error (2026-09-05,
WU PWS session - three failed app starts and one wrong-directory analyze run):

1. **Read the relevant skill FIRST, by path, before running its commands.**
   `.claude/skills/` files are not auto-loaded. Non-negotiable triggers:
   - about to run the app, reload, screenshot, drive the UI, or use adb
     → read `.claude/skills/run-app/SKILL.md`
   - about to run `flutter test`, `flutter analyze`, or touch fixtures
     → read `.claude/skills/testing/SKILL.md`
   Do not reconstruct the commands from memory - the skills carry traps this
   file deliberately does not duplicate.

2. **Agent shells do not inherit the interactive environment.**
   `flutter` is NOT on PATH (it lives at `~/flutter/bin`), and the sandbox
   makes `~/.config` read-only (flutter tools die with
   `FileSystemException: ... /home/<user>/.config/flutter`). For plain
   analyze/test runs:
   ```bash
   export PATH="$HOME/flutter/bin:$PATH" \
          XDG_CONFIG_HOME=/tmp/flutter-config XDG_DATA_HOME=/tmp/flutter-data
   ```
   For `bin/dev_*.sh` and `adb`, do NOT do this piecemeal - the run-app skill
   requires those with the sandbox off entirely, which fixes PATH and config
   in one move.

3. **Working directory**: `flutter analyze` / `flutter test` run from
   `the_paragliding_app/`, not the repo root. `bin/dev_*.sh` run from the repo
   root. Getting this wrong can silently analyze/build the wrong tree (a
   root-level run once reported "39645 issues" from build artifacts).

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
| `could not lock config file .git/config: File exists` | Bash sandbox binds `/dev/null` over `.git/config.lock`. **The operation itself succeeded** - only the config write failed, so it exits 1 after working | Don't retry. Verify with `git ls-remote`/`git worktree list`, and prefer `git push origin HEAD` over `-u` (see the `sandbox-setup` skill) |

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
for analysing a log against the performance thresholds use the `flutter-log-analyzer` agent.

**Agent definitions in `.claude/agents/` are not auto-loaded in DSH.** To use
`flutter-log-analyzer`, read `.claude/agents/flutter-log-analyzer.md` and either follow it
inline (fine for small logs) or pass its content to a subagent (better when the log is
large and you don't want it eating this session's context). The same applies to the
`.claude/skills/` files: DSH does not register them as skills, so `read` them by path
when their topic comes up.

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
- Measure performance before optimizing; the thresholds live in the
  `flutter-log-analyzer` agent

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

## Conventions

`LoggingService` for all output (never `print`/`debugPrint`/`developer.log`),
`FlightTrackLoader` for all flight data, `DatabaseService` for all queries (never raw
`openDatabase`/`rawQuery`), and simple `StatefulWidget` state — no Provider, Bloc or
Riverpod. Follow the surrounding code for shape; the reusable widgets are in
`lib/presentation/widgets/common/` (`AppStatCard`, `AppExpansionCard`, `AppEmptyState`,
`AppErrorState`, `AppLoadingSkeleton`) — use them rather than raw `Card`/`ExpansionTile`.

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
| Schema change | Bump `databaseVersion`, add an `_onUpgrade` branch, test the upgrade path | Real migration - see docs/DATABASE.md. Never "clear data": the app is published |

### File Navigation for Claude

Use format `file_path:line_number` in logs:

- `flight_service.dart:142` - Easy navigation
- `database_service.dart:67` - Clickable in IDE
- `logging_service.dart:28` - Jump to source

### Naming & UI conventions

- Sites in the local DB are **"Flown Sites"**; sites from the PGE API are **"New Sites"**.
- Map filter controls (checkboxes and the like) take effect on the map immediately.

---

📚 **Detailed Documentation**:

- [IGC Data Trimming](docs/IGC_TRIMMING.md) - Track data processing
- [Database](docs/DATABASE.md) - Schema, migrations, clearing dev data
- [Timestamp Processing](docs/TIMESTAMPS.md) - UTC/local conversion
- [Architecture](docs/TECHNICAL_DESIGN.md) | [Requirements](docs/FUNCTIONAL_SPECIFICATION.md)
