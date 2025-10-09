import 'dart:async';
import 'logging_service.dart';
import 'pge_sites_database_service.dart';
import 'pge_sites_download_service.dart';
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

  /// Get initialization status
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
}