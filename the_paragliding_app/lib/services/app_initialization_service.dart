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

  bool _isInitializing = false;
  bool _isInitialized = false;

  /// Check and perform necessary initialization tasks
  /// This runs in background and doesn't block the app
  Future<void> initializeInBackground() async {
    if (_isInitializing || _isInitialized) {
      return; // Already initializing or done
    }

    _isInitializing = true;

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
    } finally {
      _isInitializing = false;
    }
  }

  /// Check if PGE sites need to be downloaded and do it in background
  Future<void> _checkAndDownloadPgeSites() async {
    try {
      // Check if user has already manually downloaded PGE sites
      final hasDownloadedBefore = await PreferencesHelper.hasPgeSitesBeenDownloaded();

      // Initialize PGE sites tables
      await PgeSitesDatabaseService.instance.initializeTables();

      // Check if data exists
      final hasData = await PgeSitesDatabaseService.instance.isDataAvailable();

      if (!hasData && !hasDownloadedBefore) {
        LoggingService.info('AppInitializationService: First launch detected, downloading PGE sites in background');

        // Start download in background
        // We don't await this - let it run async
        _downloadPgeSitesAsync();
      } else if (hasData) {
        LoggingService.info('AppInitializationService: PGE sites already available');
      } else {
        LoggingService.info('AppInitializationService: PGE sites not downloaded, user can download manually');
      }
    } catch (e) {
      LoggingService.error('AppInitializationService: Error checking PGE sites', e);
      // Non-fatal - app can work without PGE sites
    }
  }

  /// Download PGE sites asynchronously without blocking
  Future<void> _downloadPgeSitesAsync() async {
    try {
      LoggingService.info('AppInitializationService: Starting background PGE sites download');

      // Download the sites data
      final downloadSuccess = await PgeSitesDownloadService.instance.downloadSitesData();

      if (downloadSuccess) {
        // Import the downloaded data
        final importSuccess = await PgeSitesDatabaseService.instance.importSitesData();

        if (importSuccess) {
          // Mark as downloaded
          await PreferencesHelper.setPgeSitesDownloaded(true);
          LoggingService.info('AppInitializationService: PGE sites downloaded and imported successfully in background');
        } else {
          LoggingService.warning('AppInitializationService: PGE sites downloaded but import failed');
        }
      } else {
        LoggingService.warning('AppInitializationService: PGE sites download failed in background');
      }
    } catch (e) {
      LoggingService.error('AppInitializationService: Error downloading PGE sites in background', e);
      // Non-fatal - user can manually download later
    }
  }

  /// Check if PGE sites need incremental sync and perform it in background
  /// Runs daily auto-sync if last sync was more than 24 hours ago
  Future<void> _checkAndSyncPgeSites() async {
    try {
      // Check if data exists first
      final hasData = await PgeSitesDatabaseService.instance.isDataAvailable();

      if (!hasData) {
        LoggingService.info('AppInitializationService: No PGE sites data, skipping sync');
        return;
      }

      // Check last sync time
      final lastSyncTimestamp = await PreferencesHelper.getString('pge_last_sync_time');

      bool shouldSync = false;
      if (lastSyncTimestamp == null || lastSyncTimestamp.isEmpty) {
        // Never synced before
        shouldSync = true;
        LoggingService.info('AppInitializationService: No previous sync, performing first sync');
      } else {
        try {
          final lastSync = DateTime.parse(lastSyncTimestamp);
          final age = DateTime.now().difference(lastSync);

          if (age.inHours >= 24) {
            shouldSync = true;
            LoggingService.info('AppInitializationService: Last sync was ${age.inHours} hours ago, performing sync');
          } else {
            LoggingService.info('AppInitializationService: Last sync was ${age.inHours} hours ago, skipping sync');
          }
        } catch (e) {
          LoggingService.warning('AppInitializationService: Failed to parse last sync time, performing sync');
          shouldSync = true;
        }
      }

      if (shouldSync) {
        // Perform sync in background without blocking
        _syncPgeSitesAsync();
      }
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
  bool get isInitializing => _isInitializing;
}