# Database Development

## The app is published — schema changes need real migrations

A user's flight log exists nowhere else; clearing it is unrecoverable. There is no
"clear data and re-create" path for anyone who has installed the app.

`database_helper.dart` is at `databaseVersion = 5`, with real `_onUpgrade` branches for
versions 2, 3, 4 and 5. Every future schema change adds another.

> This file previously described a "pre-release, no migrations" strategy and told readers
> to clear app data on a schema change. That was written before release and was wrong by
> the time it was read — following it would destroy a user's flight log. If you find that
> advice repeated anywhere else, it is stale.

## Schema change process

1. Bump `databaseVersion` in `database_helper.dart`
2. Add an `if (oldVersion < N)` branch to `_onUpgrade`, following the existing ones
   (see :435, :451, :463, :503 for the current four)
3. **Log how many rows a data migration changed.** A migration that rewrites user data
   silently cannot be audited afterwards — see `backfillDetectedDurations`
4. Test the upgrade path, not just the fresh-install path. `test/duration_backfill_test.dart`
   is the pattern: annotate the migration `@visibleForTesting` and drive it directly, rather
   than duplicating its SQL in the test where the two can drift apart
5. Verify a fresh install still works — `_onCreate` and `_onUpgrade` must converge on the
   same schema

A good way to exercise a migration for real: copy an older `dev_data/app_documents`
database into a worktree and launch there, then check `[DB:MIGRATE]` in the log.

## Clearing data (development only)

Fine on a dev machine, never appropriate as a user-facing fix.

- **Linux desktop**: `bin/dev_run.sh --reset`
- **Android**: Settings → Apps → **Paragliding App (debug)** → Storage → Clear Data.
  Pick the "(debug)" entry — a production install may sit next to it under "The
  Paragliding App", and clearing that one destroys real flight data.

## Tables

`flights`, `sites`, `wings`, `wing_aliases`, `country_codes`. Track points are not a
table — IGC files are stored on disk and read through `FlightTrackLoader`.

## Architecture

- **Pattern**: MVVM with Repository pattern
- **Database**: SQLite via sqflite (mobile) + sqflite_common_ffi (desktop)
- **Scale**: <10 tables, largest table <5000 rows
- **Access**: Simple StatefulWidget with direct database access

## Key services

- `database_helper.dart` — schema, migrations, low-level operations
- `database_service.dart` — main service layer with business logic
