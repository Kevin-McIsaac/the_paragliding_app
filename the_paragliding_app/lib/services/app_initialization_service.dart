import 'dart:async';
import 'package:sqflite/sqflite.dart' show Database;
import '../data/datasources/database_helper.dart';
import 'logging_service.dart';
import 'pge_sites_database_service.dart';
import 'pge_sites_download_service.dart';
import '../utils/preferences_helper.dart';

/// Service responsible for initializing app data on first launch
/// Handles background download of PGE sites database
class AppInitializationService {
  static final AppInitializationService instance = AppInitializationService._();
  AppInitializationService._();

  /// Whether deferred background initialization may run.
  ///
  /// Reached transitively from `SiteMatchingService.initialize()`/`reload()`, so
  /// any test touching site matching triggered all of it. Neither half belongs
  /// in a test run:
  ///
  /// - the bundled-CSV import loads an asset through `rootBundle`, which cannot
  ///   work without a Flutter binding - it fails with "Binding has not yet been
  ///   initialized" after burning about a minute, long enough to push unrelated
  ///   test files past the 30s default timeout
  /// - the incremental sync is a live HTTP call to paraglidingearth.com
  ///
  /// Tests turn this off in `flutter_test_config.dart` and seed `pge_sites`
  /// directly where they need it. Production never changes it.
  static bool backgroundInitEnabled = true;

  // Both memos below record a fact about the *contents* of a database, so they
  // are keyed on the connection they were established against rather than a
  // bare bool. DatabaseHelper.recreateDatabase() deletes the file and opens a
  // new Database, which drops pge_sites and pge_sites_metadata - those are
  // created by PgeSitesDatabaseService.initializeTables(), not by _onCreate. A
  // memo that outlives its database reports success against tables that no
  // longer exist. Comparing identity makes both self-heal on next use.
  Database? _initializedFor;
  Database? _tablesCreatedFor;
  Future<void>? _initialization;
  Future<void>? _tableCreation;

  /// Create the PGE tables if they are missing - cheap DDL, safe to await at
  /// startup. Keeps queries from failing with "no such table: pge_sites"
  /// before the (deferred) data import has run.
  ///
  /// Failures clear the memo, the same way [_initialize] does. Caching a
  /// rejected future here would make main.dart's "Retry" button dead: it calls
  /// straight back into this method and would keep getting the original
  /// failure, leaving a force-quit as the only way out.
  Future<void> ensureTables() async {
    final db = await DatabaseHelper.instance.database;
    if (identical(_tablesCreatedFor, db)) return;
    return _tableCreation ??= _createTables(db);
  }

  Future<void> _createTables(Database db) async {
    try {
      await PgeSitesDatabaseService.instance.initializeTables();
      _tablesCreatedFor = db;
    } catch (e) {
      LoggingService.error('AppInitializationService: Table creation failed', e);
      rethrow;
    } finally {
      // Cleared either way: on success the connection identity is now the memo,
      // and on failure the next caller must be free to retry.
      _tableCreation = null;
    }
  }

  /// Download and import the PGE sites database, then sync.
  ///
  /// Deferred until something actually needs the data (the Sites map) - the
  /// import is ~11k rows and used to block app startup. Concurrent callers
  /// share one run and await the same future.
  Future<void> initializeInBackground() async {
    if (!backgroundInitEnabled) {
      return;
    }
    final db = await DatabaseHelper.instance.database;
    // Keyed on the connection, not a bool: after a recreate the tables are empty
    // again, and a bool would report the import as already done.
    if (identical(_initializedFor, db)) {
      return;
    }
    return _initialization ??= _initialize(db);
  }

  /// [db] is the connection this run is populating. If the database is recreated
  /// while this is in flight the stamp below is stale, which is not reachable
  /// today - both recreate and background init are user-initiated and
  /// sequential - and is not worth guarding against.
  Future<void> _initialize(Database db) async {
    try {
      LoggingService.info('AppInitializationService: Starting background initialization');

      // Check if this is first launch or if PGE sites need download
      await _checkAndDownloadPgeSites();

      // Check if PGE sites need incremental sync (daily auto-sync)

      _initializedFor = db;
      LoggingService.info('AppInitializationService: Background initialization complete');
    } catch (e) {
      LoggingService.error('AppInitializationService: Background initialization failed', e);
    } finally {
      _initialization = null; // Allow a retry on the next request
    }
  }

  /// Check if PGE sites need to be downloaded and do it in background
  Future<void> _checkAndDownloadPgeSites() async {
    try {
      // Tables may already exist from ensureTables() at startup
      await ensureTables();

      // Check if data exists
      final hasData = await PgeSitesDatabaseService.instance.isDataAvailable();
      // Having *a* catalogue is not the same as having the current one. This
      // only checked for emptiness, so an upgrade that shipped a new
      // catalogue never imported it: existing users kept whatever they first
      // installed, and would never have seen the sites this release adds.
      final catalogChanged =
          hasData && await PgeSitesDownloadService.instance.bundledCatalogDiffersFromLocal();

      if (!hasData || catalogChanged) {
        LoggingService.info(
          catalogChanged
              ? 'AppInitializationService: Bundled catalogue changed, re-importing'
              : 'AppInitializationService: Empty PGE database detected, auto-importing bundled data',
        );

        // Wait for import to complete so the database is ready before use
        await _downloadAndImportPgeSites();
      } else if (await _publishedCatalogIsNewer()) {
        // The bundled copy is only ever as new as the release. Launches added
        // since then reach the pilot from here, without waiting for a Play
        // update - the whole reason the catalogue is published separately.
        LoggingService.info(
            'AppInitializationService: Newer catalogue published, refreshing');
        if (await PgeSitesDownloadService.instance.downloadFromRemote()) {
          await PgeSitesDatabaseService.instance.importSitesData();
        }
      } else {
        LoggingService.info('AppInitializationService: PGE sites already available');
      }
    } catch (e) {
      LoggingService.error('AppInitializationService: Error checking PGE sites', e);
      // Non-fatal - app can work without PGE sites
    }
  }

  /// Whether to ask the server for a newer catalogue, and its answer.
  ///
  /// Throttled to [PgeSitesConfig.maxAge] since the last check, not the last
  /// download: the pipeline runs weekly and usually changes nothing, so an
  /// unthrottled check would be a HEAD request on every cold start for an
  /// answer that is almost always "no". A launch site often has no signal, so
  /// this must never be on anything the pilot waits for - it is not: the whole
  /// method runs on the deferred path, and every failure is swallowed.
  Future<bool> _publishedCatalogIsNewer() async {
    final lastChecked = await PreferencesHelper.getCatalogCheckedDate();
    if (lastChecked != null &&
        DateTime.now().difference(lastChecked) < PgeSitesConfig.maxAge) {
      return false;
    }
    return PgeSitesDownloadService.instance.checkForUpdate();
  }

  /// Download and import PGE sites from bundled CSV in background
  Future<void> _downloadAndImportPgeSites() async {
    try {
      LoggingService.info('AppInitializationService: Starting auto-import of bundled PGE sites data');

      // Download (copy from assets) the bundled CSV data
      final downloadSuccess = await PgeSitesDownloadService.instance.downloadSitesData();

      if (downloadSuccess) {
        LoggingService.info('AppInitializationService: Bundled CSV copied, starting database import');

        // Import the data into database
        final importSuccess = await PgeSitesDatabaseService.instance.importSitesData();

        if (importSuccess) {
          // Mark as downloaded
          await PreferencesHelper.setPgeSitesDownloaded(true);
          LoggingService.info('AppInitializationService: Auto-import completed successfully - PGE sites database initialized');
        } else {
          LoggingService.warning('AppInitializationService: CSV copied but database import failed');
        }
      } else {
        LoggingService.warning('AppInitializationService: Failed to copy bundled CSV data');
      }
    } catch (e) {
      LoggingService.error('AppInitializationService: Error during auto-import of PGE sites', e);
      // Non-fatal - user can manually download later from Data Management screen
    }
  }

  /// Check if PGE sites need incremental sync and perform it in background


  // isInitialized / isInitializing getters removed: nothing read them, and both
  // reported on a bool that could not distinguish "imported" from "imported into
  // a database that has since been deleted".
}