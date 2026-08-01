import 'dart:async';
import 'logging_service.dart';
import 'pge_sites_database_service.dart';
import 'pge_sites_download_service.dart';
import 'pge_incremental_sync_service.dart';
import '../utils/preferences_helper.dart';

/// Service responsible for initializing app data on first launch
/// Handles background download of PGE sites database
class AppInitializationService {
  static final AppInitializationService instance = AppInitializationService._();
  AppInitializationService._();

  bool _isInitialized = false;
  Future<void>? _initialization;
  Future<void>? _tableCreation;

  /// Create the PGE tables if they are missing - cheap DDL, safe to await at
  /// startup. Keeps queries from failing with "no such table: pge_sites"
  /// before the (deferred) data import has run.
  Future<void> ensureTables() {
    return _tableCreation ??= PgeSitesDatabaseService.instance.initializeTables();
  }

  /// Download and import the PGE sites database, then sync.
  ///
  /// Deferred until something actually needs the data (the Sites map) - the
  /// import is ~11k rows and used to block app startup. Concurrent callers
  /// share one run and await the same future.
  Future<void> initializeInBackground() {
    if (_isInitialized) {
      return Future.value();
    }
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      LoggingService.info('AppInitializationService: Starting background initialization');

      // Check if this is first launch or if PGE sites need download
      await _checkAndDownloadPgeSites();

      // Check if PGE sites need incremental sync (daily auto-sync)
      await _checkAndSyncPgeSites();

      _isInitialized = true;
      LoggingService.info('AppInitializationService: Background initialization complete');
    } catch (e) {
      LoggingService.error('AppInitializationService: Background initialization failed', e);
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

      if (!hasData) {
        LoggingService.info('AppInitializationService: Empty PGE database detected, auto-importing bundled data');

        // On first launch or if database is empty, automatically import bundled CSV data
        // Wait for import to complete so database is ready before sync runs
        await _downloadAndImportPgeSites();
      } else {
        LoggingService.info('AppInitializationService: PGE sites already available');
      }
    } catch (e) {
      LoggingService.error('AppInitializationService: Error checking PGE sites', e);
      // Non-fatal - app can work without PGE sites
    }
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
  /// Syncs on every app load to ensure data is up to date
  Future<void> _checkAndSyncPgeSites() async {
    try {
      // Check if data exists first
      final hasData = await PgeSitesDatabaseService.instance.isDataAvailable();

      if (!hasData) {
        LoggingService.info('AppInitializationService: No PGE sites data, skipping sync');
        return;
      }

      // Always sync on app load to ensure data is up to date
      LoggingService.info('AppInitializationService: Performing PGE database sync on app load');

      // Perform sync in background without blocking
      _syncPgeSitesAsync();
    } catch (e) {
      LoggingService.error('AppInitializationService: Error checking sync status', e);
      // Non-fatal - sync can be triggered manually
    }
  }

  /// Sync PGE sites asynchronously in background
  Future<void> _syncPgeSitesAsync() async {
    try {
      LoggingService.info('AppInitializationService: Starting background PGE sites sync');

      final result = await PgeIncrementalSyncService.instance.syncModifiedSites();

      if (result.success) {
        // Save last sync time
        final now = DateTime.now().toIso8601String();
        await PreferencesHelper.setString('pge_last_sync_time', now);

        LoggingService.structured('PGE_AUTO_SYNC_COMPLETED', {
          'sites_added': result.sitesAdded,
          'sites_modified': result.sitesModified,
          'total_processed': result.totalProcessed,
          'duration_ms': result.duration.inMilliseconds,
        });

        if (result.totalProcessed > 0) {
          LoggingService.info('AppInitializationService: Background sync completed - ${result.totalProcessed} sites updated');
        } else {
          LoggingService.info('AppInitializationService: Background sync completed - no updates');
        }
      } else {
        LoggingService.warning('AppInitializationService: Background sync failed: ${result.errorMessage}');
      }
    } catch (e) {
      LoggingService.error('AppInitializationService: Error syncing PGE sites in background', e);
      // Non-fatal - user can manually sync later
    }
  }

  /// Get initialization status
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _initialization != null && !_isInitialized;
}