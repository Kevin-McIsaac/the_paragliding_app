---
name: testing
description: Run and write tests for this Flutter app, and diagnose CI/analyze failures. Use when asked to run tests, fix a failing or flaky test, add test coverage, run flutter analyze, write a fixture, or work out why CI is red. Covers flutter test/analyze commands, the network-tagged live-API tests and their weekly schedule, and the two test-isolation rules (fixture paths, in-memory DB) that keep the suite from flaking.
---

# Testing and quality

## Commands

```bash
flutter analyze                              # run after complex, multi-file changes
flutter test                                 # all tests
flutter test test/specific_test.dart         # one file
flutter test --tags network --run-skipped    # live-API tests, skipped by default
```

Run these from `the_paragliding_app/` (the app subdirectory), not the repo root.

## Plain `flutter test` is fine locally

It used to fail about 1 run in 3, so this file used to say to always pass
`--concurrency=1`. Issue #280 fixed the underlying test problems; measured over 16
consecutive runs on an 8-core dev box, parallel is now 0/16 failures and the fastest of
the three modes (mean 46s, vs 60s serial, vs 81s serial before the fix).

**CI still passes `--concurrency=1`** (`.github/workflows/ci.yml`). That is deliberate
and not stale: parallel was only verified on an 8-core dev machine, and hosted runners
have far fewer cores. Re-measure there before changing it. `concurrency:` cannot be set
in `dart_test.yaml` - `flutter test` always passes its own `-j` and overrides the file,
so it has to be on the command line.

If a green local run doesn't match a red CI run (or vice versa), that gap - not the test
itself - is usually the thing to chase first.

## Keep tests isolated, or the flakiness comes back

- **Never write fixtures to a fixed path.** Use `TestHelpers.fixturePath('name.igc')`,
  which gives each test process its own directory. Fixed `/tmp` paths caused a real
  failure - two test files both wrote `/tmp/test_india.igc`, and one run read a fixture
  back empty (`Parsed 0 track points, pilot: Unknown`).
- **The test database is in-memory** (`TestHelpers.initializeDatabaseForTesting()` sets
  `DatabaseHelper.databasePathOverride`). Don't reintroduce a file-backed one, and don't
  add per-test `recreateDatabase()` unless a test actually writes - eight read-only tests
  were rebuilding the schema and re-seeding 249 country codes nine times per run.

## The `network` tests

They run weekly in CI, on their own schedule (`.github/workflows/network.yml`,
Tuesdays), not on pushes or pull requests. They are the only checks on things that move
without anyone touching this repository - the bundled catalogue falling behind what the
producer publishes, the OpenAIP export bucket being locked down, a launch changing its
name, altitude, wind or guide under the baseline that pins them. A red run there means
the world moved, not that your branch is broken; the log is kept as an artifact, and a
timeout or 5xx just wants re-running. Run it on demand from the Actions tab before
cutting a release.

## Writing tests

- Drive production code paths rather than recomputing an expected value inline - a test
  that agrees only with itself isn't coverage. `test/statistics_match_log_book_test.dart`
  is the pattern: it calls the same `getYearlyStatistics()` / `getAllFlights()` the
  screens call.
- Prove a regression test fails without the fix: revert the fix, run it, watch it go red.
  A test that passes either way is worse than none.
- For a schema migration, drive the migration function directly (`@visibleForTesting`)
  rather than duplicating its SQL in the test, where the two can drift apart - see
  `test/duration_backfill_test.dart`.
