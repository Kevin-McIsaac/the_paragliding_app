import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/database_reset_helper.dart';
import '../../services/site_matching_service.dart';
import '../../services/cesium_token_validator.dart';
import '../../utils/cache_utils.dart';
import '../../utils/preferences_helper.dart';
import '../../services/backup_diagnostic_service.dart';
import '../../services/igc_cleanup_service.dart';
import '../../services/backup_diagnostics_cache.dart';
import '../../services/igc_file_manager.dart';
import '../../services/logging_service.dart';
import '../../utils/card_expansion_manager.dart';
import '../widgets/common/app_expansion_card.dart';
import '../widgets/common/app_stat_row.dart';
import '../widgets/airspace_country_selector.dart';
import '../../services/airspace_geojson_service.dart';
import '../../services/airspace_country_service.dart';
import '../../services/pge_sites_download_service.dart';
import '../../services/pge_sites_database_service.dart';
import '../../services/pge_incremental_sync_service.dart';

class DataManagementScreen extends StatefulWidget {
  final bool expandPremiumMaps;
  final Future<void> Function()? onRefreshAllTabs;

  const DataManagementScreen({
    super.key,
    this.expandPremiumMaps = false,
    this.onRefreshAllTabs,
  });

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _dbStats;
  Map<String, dynamic>? _backupStatus;
  IGCBackupStats? _igcStats;
  IGCCleanupStats? _cleanupStats;
  bool _isLoading = true;
  bool _dataModified = false; // Track if any data was modified

  // PGE Sites state
  Map<String, dynamic>? _pgeSitesStats;
  PgeSitesDownloadProgress? _pgeSitesProgress;
  StreamSubscription<PgeSitesDownloadProgress>? _downloadProgressSubscription;

  // PGE Sites sync state
  bool _isSyncing = false;
  String? _lastSyncTime;

  // Card expansion state manager (persistent for this screen)
  late CardExpansionManager _expansionManager;

  // Cesium token state
  String? _cesiumToken;
  bool _isCesiumTokenValidated = false;
  bool _isValidatingCesium = false;

  // Airspace refresh key to force widget recreation
  int _airspaceRefreshKey = 0;

  // Scroll controller and keys for Premium Maps highlighting
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _premiumMapsKey = GlobalKey();
  late AnimationController _highlightController;
  late Animation<double> _highlightAnimation;

  // Helper method to format numbers with thousands separator
  String _formatNumber(int number) {
    final formatter = NumberFormat('#,###');
    return formatter.format(number);
  }


  @override
  void initState() {
    super.initState();
    LoggingService.action('DataManagement', 'screen_opened', {
      'expand_premium_maps': widget.expandPremiumMaps,
    });

    // Initialize animation controller for highlighting
    _highlightController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _highlightAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _highlightController, curve: Curves.easeInOut),
    );

    // Initialize expansion manager
    _expansionManager = CardExpansionManagers.createDataManagementManager();

    // Load saved expansion states
    _loadCardExpansionStates();

    // Set initial Premium Maps expansion state based on parameter
    if (widget.expandPremiumMaps) {
      _expansionManager.setState('premium_maps', true);

      // Schedule scroll and highlight after build completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToPremiumMaps();
      });
    }

    _loadDatabaseStats();
    _loadBackupDiagnostics();
    _loadCesiumToken();
    _loadPgeSitesStats();
    _listenToDownloadProgress();
  }

  @override
  void dispose() {
    _downloadProgressSubscription?.cancel();
    _scrollController.dispose();
    _highlightController.dispose();
    // Save expansion states if the manager supports it
    super.dispose();
  }

  Future<void> _loadCardExpansionStates() async {
    await _expansionManager.loadStates();
    setState(() {
      // Update UI with loaded expansion states
    });
  }

  void _scrollToPremiumMaps() {
    try {
      final context = _premiumMapsKey.currentContext;
      if (context != null) {
        // Use Scrollable.ensureVisible for smooth scrolling
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          alignment: 0.2, // Position card 20% from top of screen
        );

        // Start highlight animation after a short delay
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _highlightController.repeat(reverse: true);
            // Stop highlighting after 3 cycles
            Future.delayed(const Duration(milliseconds: 6000), () {
              if (mounted) {
                _highlightController.stop();
                _highlightController.reset();
              }
            });
          }
        });

        LoggingService.action('DataManagement', 'scroll_to_premium_maps');
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to scroll to Premium Maps card', e, stackTrace);
    }
  }

  Future<void> _loadDatabaseStats() async {
    setState(() => _isLoading = true);
    
    LoggingService.action('DataManagement', 'load_database_stats');
    final stopwatch = Stopwatch()..start();
    
    final stats = await DatabaseResetHelper.getDatabaseStats();
    
    LoggingService.performance('Load database stats', stopwatch.elapsed, 'database statistics loaded');
    LoggingService.structured('DB_STATS_LOADED', {
      'flights': stats['flights'] ?? 0,
      'sites': stats['sites'] ?? 0,
      'wings': stats['wings'] ?? 0,
      'total_records': stats['total_records'] ?? 0,
      'size_kb': stats['size_kb'] ?? 0,
      'duration_ms': stopwatch.elapsedMilliseconds,
    });
    
    setState(() {
      _dbStats = stats;
      _isLoading = false;
    });
  }

  Future<void> _loadBackupDiagnostics({bool forceRefresh = false}) async {
    LoggingService.action('DataManagement', 'load_backup_diagnostics');
    final stopwatch = Stopwatch()..start();

    try {
      // Load backup status immediately (fast)
      final backupStatus = await BackupDiagnosticService.getBackupStatus();

      // Update UI with backup status immediately
      if (mounted) {
        setState(() {
          _backupStatus = backupStatus;
        });
      }

      // Load IGC stats and cleanup stats in parallel (slower operations)
      final results = await Future.wait([
        BackupDiagnosticService.calculateIGCCompressionStats(forceRefresh: forceRefresh),
        IGCCleanupService.analyzeIGCFiles(forceRefresh: forceRefresh),
      ]);

      final igcStats = results[0] as IGCBackupStats?;
      final cleanupStats = results[1] as IGCCleanupStats?;

      LoggingService.performance('Load backup diagnostics', stopwatch.elapsed, 'backup diagnostics loaded');
      LoggingService.structured('BACKUP_DIAGNOSTICS_LOADED', {
        'backup_enabled': backupStatus['backupEnabled'] ?? false,
        'backup_type': backupStatus['backupType'] ?? 'unknown',
        'igc_files': igcStats?.fileCount ?? 0,
        'original_size_mb': igcStats != null ? (igcStats.originalSizeBytes / 1024 / 1024).toStringAsFixed(1) : '0.0',
        'compressed_size_mb': igcStats != null ? (igcStats.compressedSizeBytes / 1024 / 1024).toStringAsFixed(1) : '0.0',
        'compression_ratio': igcStats?.compressionRatio ?? 0.0,
        'orphaned_files': cleanupStats?.orphanedFiles ?? 0,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'used_cache': !forceRefresh,
      });

      // Update UI with complete data
      if (mounted) {
        setState(() {
          _igcStats = igcStats;
          _cleanupStats = cleanupStats;
        });
      }

    } catch (e, stackTrace) {
      LoggingService.structured('BACKUP_DIAGNOSTICS_ERROR', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      LoggingService.error('DataManagementScreen: Error loading backup diagnostics', e, stackTrace);
    }
  }

  Future<void> _loadCesiumToken() async {
    LoggingService.action('DataManagement', 'load_cesium_token');
    
    try {
      final token = await PreferencesHelper.getCesiumUserToken();
      final validated = await PreferencesHelper.getCesiumTokenValidated() ?? false;
      
      LoggingService.structured('CESIUM_TOKEN_STATUS', {
        'has_token': token != null,
        'is_validated': validated,
        'token_length': token?.length ?? 0,
      });
      
      if (mounted) {
        setState(() {
          _cesiumToken = token;
          _isCesiumTokenValidated = validated;
        });
      }
    } catch (e, stackTrace) {
      LoggingService.structured('CESIUM_TOKEN_LOAD_ERROR', {
        'error': e.toString(),
      });
      LoggingService.error('DataManagementScreen: Error loading Cesium token', e, stackTrace);
    }
  }

  Future<void> _loadPgeSitesStats() async {
    LoggingService.action('DataManagement', 'load_pge_sites_stats');

    try {
      // Initialize tables if needed
      await PgeSitesDatabaseService.instance.initializeTables();

      // Get database statistics
      final stats = await PgeSitesDatabaseService.instance.getDatabaseStats();

      // Get download status
      final downloadStatus = await PgeSitesDownloadService.instance.getDownloadStatus();

      // Format last downloaded date
      String lastDownloaded = 'Never';
      if (downloadStatus['downloaded_at'] != null) {
        final downloadDate = DateTime.parse(downloadStatus['downloaded_at']);
        final age = DateTime.now().difference(downloadDate);
        if (age.inDays > 0) {
          lastDownloaded = '${age.inDays} days ago';
        } else if (age.inHours > 0) {
          lastDownloaded = '${age.inHours} hours ago';
        } else {
          lastDownloaded = 'Recently';
        }
      }

      final combinedStats = {
        ...stats,
        'database_size_mb': ((stats['database_size_bytes'] ?? 0) / 1024 / 1024).toStringAsFixed(1),
        'last_downloaded': lastDownloaded,
        'source_file_size_mb': ((downloadStatus['file_size_bytes'] ?? 0) / 1024 / 1024).toStringAsFixed(1),
        'status': stats['sites_count'] > 0 ? 'Active' : 'Not downloaded',
        'is_outdated': downloadStatus['is_outdated'] ?? false,
      };

      LoggingService.structured('PGE_SITES_STATS_LOADED', {
        'sites_count': stats['sites_count'],
        'database_size_mb': combinedStats['database_size_mb'],
        'last_downloaded': lastDownloaded,
        'is_outdated': downloadStatus['is_outdated'],
      });

      // Load last sync time
      final lastSyncTimestamp = await PreferencesHelper.getString('pge_last_sync_time');
      String lastSync = 'Never';
      if (lastSyncTimestamp != null && lastSyncTimestamp.isNotEmpty) {
        try {
          final syncDate = DateTime.parse(lastSyncTimestamp);
          final age = DateTime.now().difference(syncDate);
          if (age.inDays > 0) {
            lastSync = '${age.inDays} days ago';
          } else if (age.inHours > 0) {
            lastSync = '${age.inHours} hours ago';
          } else if (age.inMinutes > 0) {
            lastSync = '${age.inMinutes} minutes ago';
          } else {
            lastSync = 'Just now';
          }
        } catch (e) {
          LoggingService.warning('[PGE_SYNC] Failed to parse last sync time: $e');
        }
      }

      if (mounted) {
        setState(() {
          _pgeSitesStats = combinedStats;
          _lastSyncTime = lastSync;
        });
      }
    } catch (e, stackTrace) {
      LoggingService.error('DataManagementScreen: Error loading PGE sites stats', e, stackTrace);
      setState(() {
        _pgeSitesStats = {
          'sites_count': 0,
          'database_size_mb': '0.0',
          'last_downloaded': 'Error',
          'status': 'Error',
        };
      });
    }
  }

  void _listenToDownloadProgress() {
    _downloadProgressSubscription = PgeSitesDownloadService.instance.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _pgeSitesProgress = progress;
        });
      }
    });
  }

  Future<void> _downloadPgeSites() async {
    LoggingService.action('DataManagement', 'download_pge_sites');

    try {
      // First delete any corrupted local file to ensure fresh download
      final deleted = await PgeSitesDownloadService.instance.deleteLocalFile();
      if (deleted) {
        LoggingService.info('DataManagementScreen: Deleted existing local PGE sites file');
      }

      // Download the data
      final downloadSuccess = await PgeSitesDownloadService.instance.downloadSitesData(
        forceRedownload: true, // Always force since we may have deleted the file
      );

      if (!downloadSuccess) {
        _showErrorDialog('Download Failed', 'Failed to download PGE sites data. Please try again.');
        return;
      }

      // Import into database
      _showLoadingDialog('Importing sites into database...');

      final importSuccess = await PgeSitesDatabaseService.instance.importSitesData();

      if (mounted) Navigator.of(context).pop(); // Close loading dialog

      if (importSuccess) {
        setState(() {
          _dataModified = true; // Mark as modified to trigger parent refresh
        });

        // Refresh all tabs BEFORE showing dialog so Sites screen has fresh data
        if (widget.onRefreshAllTabs != null) {
          await widget.onRefreshAllTabs!();
        }

        _showSuccessDialog(
          'Sites Downloaded',
          'Successfully downloaded and imported worldwide paragliding sites.'
        );

        // Reload statistics
        await _loadPgeSitesStats();
      } else {
        _showErrorDialog('Import Failed', 'Failed to import sites into database.');
      }

    } catch (e, stackTrace) {
      if (mounted) Navigator.of(context).pop(); // Close any open dialog
      LoggingService.error('DataManagementScreen: Failed to download PGE sites', e, stackTrace);
      _showErrorDialog('Error', 'Failed to download sites: $e');
    }
  }

  Future<void> _syncPgeSites() async {
    LoggingService.action('DataManagement', 'sync_pge_sites');

    setState(() {
      _isSyncing = true;
    });

    try {
      // Perform incremental sync
      final result = await PgeIncrementalSyncService.instance.syncModifiedSites();

      // Save last sync time
      final now = DateTime.now().toIso8601String();
      await PreferencesHelper.setString('pge_last_sync_time', now);

      if (mounted) {
        setState(() {
          _isSyncing = false;
          _dataModified = result.totalProcessed > 0; // Mark as modified if sites were updated
        });

        if (result.success) {
          // Show success message
          final message = result.totalProcessed > 0
              ? '${result.sitesAdded + result.sitesModified} sites updated (${result.sitesAdded} new, ${result.sitesModified} modified)'
              : 'No updates found. Database is up to date.';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );

          // Refresh all tabs if sites were updated
          if (result.totalProcessed > 0 && widget.onRefreshAllTabs != null) {
            await widget.onRefreshAllTabs!();
          }

          // Reload statistics
          await _loadPgeSitesStats();
        } else {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync failed: ${result.errorMessage}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      LoggingService.error('DataManagementScreen: Failed to sync PGE sites', e, stackTrace);

      if (mounted) {
        setState(() {
          _isSyncing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }


  Future<void> _testCesiumToken() async {
    if (_cesiumToken == null) return;
    
    LoggingService.action('DataManagement', 'test_cesium_token', {'token_length': _cesiumToken!.length});
    final stopwatch = Stopwatch()..start();
    
    setState(() {
      _isValidatingCesium = true;
    });

    try {
      final isValid = await CesiumTokenValidator.validateToken(_cesiumToken!);
      
      LoggingService.performance('Test Cesium token', stopwatch.elapsed, 'token validation completed');
      LoggingService.structured('CESIUM_TOKEN_TEST', {
        'is_valid': isValid,
        'token_length': _cesiumToken!.length,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      if (mounted) {
        final message = isValid 
          ? 'Token is valid and working correctly.'
          : 'Token validation failed. It may be expired or have insufficient permissions.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isValid ? Colors.green : Colors.red,
            duration: Duration(seconds: isValid ? 2 : 4),
          ),
        );
        
        if (isValid) {
          await PreferencesHelper.setCesiumTokenValidated(true);
          setState(() {
            _isCesiumTokenValidated = true;
          });
        }
      }
    } catch (e, stackTrace) {
      LoggingService.structured('CESIUM_TOKEN_TEST_ERROR', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      LoggingService.error('DataManagementScreen: Error testing Cesium token', e, stackTrace);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error testing connection. Check your internet connection.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isValidatingCesium = false;
        });
      }
    }
  }

  Future<void> _launchCesiumSignup() async {
    const url = 'https://ion.cesium.com/signup/';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        LoggingService.action('DataManagement', 'launch_cesium_signup', {'url': url});
      }
    } catch (e, stackTrace) {
      LoggingService.structured('URL_LAUNCH_ERROR', {
        'url': url,
        'error': e.toString(),
      });
      LoggingService.error('DataManagementScreen: Failed to launch signup URL', e, stackTrace);
    }
  }

  Future<void> _launchCesiumTokens() async {
    const url = 'https://ion.cesium.com/tokens';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        LoggingService.action('DataManagement', 'launch_cesium_tokens', {'url': url});
      }
    } catch (e, stackTrace) {
      LoggingService.structured('URL_LAUNCH_ERROR', {
        'url': url,
        'error': e.toString(),
      });
      LoggingService.error('DataManagementScreen: Failed to launch tokens URL', e, stackTrace);
    }
  }

  void _showTokenDialog() {
    final controller = TextEditingController(text: _cesiumToken ?? '');
    final formKey = GlobalKey<FormState>();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Cesium Ion Token'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Paste your Cesium Ion access token below:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Access Token',
                    hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a token';
                    }
                    if (value.trim().length < 10) {
                      return 'Token appears to be too short';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _isValidatingCesium ? null : () async {
                if (formKey.currentState?.validate() ?? false) {
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  Navigator.of(context).pop();
                  final token = controller.text.trim();
                  
                  // Save token and validate it immediately
                  await PreferencesHelper.setCesiumUserToken(token);
                  setState(() {
                    _cesiumToken = token;
                    _isCesiumTokenValidated = false;
                    _isValidatingCesium = true;
                  });
                  
                  // Automatically validate the token
                  try {
                    final isValid = await CesiumTokenValidator.validateToken(token);
                    
                    if (mounted) {
                      if (isValid) {
                        await PreferencesHelper.setCesiumTokenValidated(true);
                        setState(() {
                          _isCesiumTokenValidated = true;
                        });
                        
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(
                            content: Text('✓ Token validated! Premium maps are now available.'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      } else {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(
                            content: Text('Invalid token. Please check and try again.'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 4),
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('Error validating token. Please check your internet connection.'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() {
                        _isValidatingCesium = false;
                      });
                    }
                  }
                }
              },
              child: _isValidatingCesium 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Validate & Save'),
            ),
          ],
        );
      },
    );
  }

  void _showRemoveConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Token?'),
        content: const Text(
          'This will remove your Cesium Ion token and disable access to premium maps. '
          'You can add it back anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _removeToken();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _removeToken() {
    LoggingService.action('DataManagement', 'remove_cesium_token', {
      'had_token': _cesiumToken != null,
      'was_validated': _isCesiumTokenValidated,
    });
    
    setState(() {
      _cesiumToken = null;
      _isCesiumTokenValidated = false;
    });
    PreferencesHelper.removeCesiumUserToken();
    
    LoggingService.structured('CESIUM_TOKEN_REMOVED', {
      'success': true,
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cesium Ion token removed'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteAllFlightData() async {
    // Show confirmation dialog
    final confirmed = await _showConfirmationDialog(
      'Delete All Flight Data',
      'This will permanently delete ALL flight data including:\n\n'
      '• All flight records\n'
      '• All flown sites\n'
      '• All wings\n'
      '• All IGC track files\n\n'
      'PGE sites database will be preserved.\n\n'
      'This action cannot be undone.\n\n'
      'Are you sure you want to continue?',
    );

    if (!confirmed) {
      LoggingService.action('DataManagement', 'delete_all_data_cancelled');
      return;
    }

    LoggingService.action('DataManagement', 'delete_all_data_confirmed');
    final stopwatch = Stopwatch()..start();

    // Show loading
    _showLoadingDialog('Deleting all flight data...');

    try {
      // Use deleteFlightDataOnly to preserve PGE sites database
      final result = await DatabaseResetHelper.deleteFlightDataOnly();
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (result['success']) {
        LoggingService.performance('Delete all flight data', stopwatch.elapsed, 'deletion completed successfully');
        LoggingService.summary('DELETE_ALL_DATA', {
          'success': true,
          'message': result['message'],
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        
        setState(() {
          _dataModified = true; // Mark data as modified
        });
        _showSuccessDialog('All Flight Data Deleted', result['message']);
        
        // Clear all caches after data deletion
        BackupDiagnosticsCache.clearAll();
        IGCFileManager.clearCache();

        // Refresh all statistics after deletion with forced refresh
        await _loadDatabaseStats();
        await _loadBackupDiagnostics(forceRefresh: true);
      } else {
        LoggingService.structured('DELETE_ALL_DATA_FAILED', {
          'success': false,
          'error': result['message'],
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        _showErrorDialog('Deletion Failed', result['message']);
      }
    } catch (e, stackTrace) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      LoggingService.structured('DELETE_ALL_DATA_ERROR', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      LoggingService.error('DataManagementScreen: Failed to delete all flight data', e, stackTrace);
      _showErrorDialog('Error', 'Failed to delete all flight data: $e');
    }
  }

  Future<void> _recreateDatabaseFromIGC() async {
    // Show confirmation dialog
    final confirmed = await _showConfirmationDialog(
      'Recreate Database from IGC Files',
      'This will reset the database and reimport all IGC files found on device.\n\n'
      'This process may take several minutes depending on the number of IGC files.\n\n'
      'The database will be completely rebuilt from your IGC files. '
      'This is useful for data recovery or fixing corruption issues.\n\n'
      'Are you sure you want to continue?',
      confirmButtonText: 'Recreate Database',
    );

    if (!confirmed) {
      LoggingService.action('DataManagement', 'recreate_db_cancelled');
      return;
    }

    LoggingService.action('DataManagement', 'recreate_db_confirmed');
    final stopwatch = Stopwatch()..start();

    // Show progress dialog initially
    _showProgressDialog('Finding IGC files...', '', 0, 0);

    try {
      String currentFile = '';
      int processedFiles = 0;
      
      final result = await DatabaseResetHelper.recreateDatabaseFromIGCFiles(
        onProgress: (filename, current, totalFiles) {
          currentFile = filename;
          processedFiles = current;
          
          // Update progress dialog
          if (mounted) {
            Navigator.of(context).pop(); // Close current dialog
            _showProgressDialog('Recreating database from IGC files...', currentFile, current, totalFiles);
          }
        },
      );
      
      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      if (result['success']) {
        final imported = result['imported'] ?? 0;
        final failed = result['failed'] ?? 0;
        final errors = result['errors'] as List<String>? ?? [];
        
        LoggingService.performance('Recreate database from IGC', stopwatch.elapsed, 'database recreation completed');
        LoggingService.summary('RECREATE_DATABASE', {
          'success': true,
          'files_processed': processedFiles,
          'flights_imported': imported,
          'failures': failed,
          'error_count': errors.length,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        
        setState(() {
          _dataModified = true; // Mark data as modified
        });
        
        String message = result['message'] ?? 'Database recreated successfully!';
        
        if (failed > 0 && errors.isNotEmpty) {
          // Show errors in dialog for failed imports
          final errorDetails = errors.take(5).join('\n'); // Show first 5 errors
          final moreErrors = errors.length > 5 ? '\n... and ${errors.length - 5} more errors' : '';
          message += '\n\nFailed imports:\n$errorDetails$moreErrors';
        }
        
        _showSuccessDialog('Database Recreation Complete', message);
        
        // Clear relevant caches after database recreation
        BackupDiagnosticsCache.clearIGCCaches();
        IGCFileManager.clearCache();

        // Refresh all statistics after recreation with forced refresh
        await _loadDatabaseStats();
        await _loadBackupDiagnostics(forceRefresh: true);
      } else {
        LoggingService.structured('RECREATE_DATABASE_FAILED', {
          'success': false,
          'error': result['message'],
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        _showErrorDialog('Recreation Failed', result['message']);
      }
    } catch (e, stackTrace) {
      // Close progress dialog
      if (mounted) Navigator.of(context).pop();
      
      LoggingService.structured('RECREATE_DATABASE_ERROR', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      LoggingService.error('DataManagementScreen: Failed to recreate database from IGC files', e, stackTrace);
      _showErrorDialog('Error', 'Failed to recreate database from IGC files: $e');
    }
  }


  Future<void> _clearMapCache() async {
    final initialTiles = CacheUtils.getCurrentCacheCount();
    final initialSize = CacheUtils.getCurrentCacheSize();
    
    final confirmed = await _showConfirmationDialog(
      'Clear Map Cache',
      'This will clear all cached map tiles.\n\n'
      'Maps will need to re-download tiles when viewed.',
    );

    if (!confirmed) {
      LoggingService.action('DataManagement', 'clear_map_cache_cancelled');
      return;
    }

    LoggingService.action('DataManagement', 'clear_map_cache_confirmed', {
      'initial_tiles': initialTiles,
      'initial_size_bytes': initialSize,
    });
    final stopwatch = Stopwatch()..start();

    CacheUtils.clearMapCache();

    // Give the system a moment to update cache stats
    await Future.delayed(const Duration(milliseconds: 100));
    
    final finalTiles = CacheUtils.getCurrentCacheCount();
    final finalSize = CacheUtils.getCurrentCacheSize();
    final freedBytes = initialSize - finalSize;
    
    LoggingService.performance('Clear map cache', stopwatch.elapsed, 'cache clearing completed');
    LoggingService.summary('CLEAR_MAP_CACHE', {
      'tiles_cleared': initialTiles - finalTiles,
      'bytes_freed': freedBytes,
      'initial_tiles': initialTiles,
      'final_tiles': finalTiles,
      'duration_ms': stopwatch.elapsedMilliseconds,
    });
    
    if (mounted) {
      setState(() {}); // Refresh display
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Map cache cleared successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<bool> _showConfirmationDialog(String title, String message, {String? confirmButtonText}) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(confirmButtonText ?? 'Delete All Data'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showProgressDialog(String title, String currentFile, int current, int total) {
    String progressText = total > 0 ? 'Processing file $current of $total' : 'Preparing...';
    String fileText = currentFile.isNotEmpty ? 'Current: $currentFile' : '';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Expanded(child: Text(progressText)),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: total > 0 ? current / total : null,
              ),
              const SizedBox(height: 8),
              Text(
                '${(total > 0 ? (current / total * 100).toStringAsFixed(1) : '0')}% complete',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (fileText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                fileText,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _testApiConnection() async {
    LoggingService.action('DataManagement', 'test_paragliding_earth_api');
    final stopwatch = Stopwatch()..start();
    
    // Show loading
    _showLoadingDialog('Testing ParaglidingEarth API connection...');

    try {
      final siteService = SiteMatchingService.instance;
      final isConnected = await siteService.testApiConnection();
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      LoggingService.performance('Test ParaglidingEarth API', stopwatch.elapsed, 'API connection test completed');
      LoggingService.structured('API_CONNECTION_TEST', {
        'is_connected': isConnected,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      // Show result
      if (mounted) {
        if (isConnected) {
          _showSuccessDialog(
            'API Connection Test',
            'Successfully connected to ParaglidingEarth.com API!\n\n'
            'Real-time site lookups are working.',
          );
        } else {
          _showErrorDialog(
            'API Connection Test',  
            'Failed to connect to ParaglidingEarth.com API.\n\n'
            'The app will use the local database as fallback.',
          );
        }
      }
    } catch (e, stackTrace) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      LoggingService.structured('API_CONNECTION_TEST_ERROR', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      LoggingService.error('DataManagementScreen: Error testing API connection', e, stackTrace);
      
      // Show error
      if (mounted) {
        _showErrorDialog('API Test Error', 'Error testing API connection: $e');
      }
    }
  }



  /// Handle airspace data changes from AirspaceCountrySelector.
  ///
  /// This is called when airspace data is downloaded or deleted,
  /// increments the refresh key to force the FutureBuilder to re-fetch statistics,
  /// and marks data as modified so the parent screen can refresh when this screen closes.
  void _handleAirspaceDataChanged() {
    if (mounted) {
      setState(() {
        _airspaceRefreshKey++;
        _dataModified = true; // Mark as modified to trigger parent refresh
      });
    }
  }

  Future<void> _clearAirspaceCache() async {
    final confirmed = await _showConfirmationDialog(
      'Clear Airspace Database',
      'This will clear all downloaded airspace data. You will need to re-download country data when viewing the map.\n\nThis action cannot be undone.',
    );

    if (!confirmed) return;

    _showLoadingDialog('Clearing airspace database...');
    try {
      // Clear all airspace data including country metadata and preferences
      await AirspaceCountryService.instance.clearAllData();

      if (mounted) {
        Navigator.of(context).pop(); // Close loading
      }

      // Refresh UI to show updated stats and force country selector refresh
      _handleAirspaceDataChanged();

      _showSuccessDialog(
        'Database Cleared',
        'Airspace database has been cleared successfully. Please navigate back to the map to re-download airspace data.',
      );
    } catch (e, stackTrace) {
      if (mounted) Navigator.of(context).pop(); // Close loading
      LoggingService.error('Failed to clear airspace database', e, stackTrace);
      _showErrorDialog('Error', 'Failed to clear airspace database: $e');
    }
  }

  Future<void> _showBackupDiagnostics() async {
    _showLoadingDialog('Loading backup diagnostics...');

    try {
      final dbEstimate = await BackupDiagnosticService.getDatabaseBackupEstimate();
      
      if (mounted) Navigator.of(context).pop(); // Close loading
      
      final StringBuffer message = StringBuffer();
      message.writeln('ANDROID BACKUP STATUS\n');
      
      if (_backupStatus?['success'] == true) {
        message.writeln('✓ Backup: ${_backupStatus!['backupEnabled'] ? 'Enabled' : 'Disabled'}');
        message.writeln('✓ Custom Agent: ${_backupStatus!['hasCustomAgent'] ? 'Yes' : 'No'}');
        message.writeln('✓ Backup Rules: ${_backupStatus!['hasBackupRules'] ? 'Yes' : 'No'}');
        message.writeln('✓ Type: ${_backupStatus!['backupType']}');
        message.writeln('✓ Limit: ${_backupStatus!['maxBackupSize']}\n');
      }
      
      message.writeln('DATABASE BACKUP\n');
      if (dbEstimate['success'] == true) {
        message.writeln('Database Size: ${dbEstimate['formattedSize']}');
        message.writeln('Backup Usage: ${dbEstimate['backupLimitPercent'].toStringAsFixed(1)}%\n');
      }
      
      message.writeln('IGC FILES BACKUP\n');
      if (_igcStats != null) {
        message.writeln('Files: ${_igcStats!.fileCount}');
        message.writeln('Original Size: ${_igcStats!.formattedOriginalSize}');
        message.writeln('Compressed: ${_igcStats!.formattedCompressedSize}');
        message.writeln('Compression: ${_igcStats!.compressionRatio.toStringAsFixed(1)}x');
        message.writeln('Backup Usage: ${_igcStats!.backupLimitUsagePercent.toStringAsFixed(1)}%');
        message.writeln('Flight Capacity: ~${_igcStats!.estimatedFlightCapacity} flights');
      }
      
      _showInfoDialog('Backup Diagnostics', message.toString());
      
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog('Diagnostics Error', 'Failed to load diagnostics: $e');
    }
  }

  Future<void> _analyzeIGCFiles({bool forceRefresh = false}) async {
    LoggingService.action('DataManagement', 'analyze_igc_files', {
      'force_refresh': forceRefresh,
    });
    final stopwatch = Stopwatch()..start();

    _showLoadingDialog('Analyzing IGC files...');
    try {
      final cleanupStats = await IGCCleanupService.analyzeIGCFiles(forceRefresh: forceRefresh);
      
      if (mounted) Navigator.of(context).pop(); // Close loading
      
      LoggingService.performance('Analyze IGC files', stopwatch.elapsed, 'IGC file analysis completed');
      
      setState(() {
        _cleanupStats = cleanupStats;
      });
      
      if (cleanupStats != null) {
        LoggingService.summary('IGC_ANALYSIS', {
          'total_files': cleanupStats.totalIgcFiles,
          'referenced_files': cleanupStats.referencedFiles,
          'orphaned_files': cleanupStats.orphanedFiles,
          'total_size_bytes': cleanupStats.totalSizeBytes,
          'orphaned_size_bytes': cleanupStats.orphanedSizeBytes,
          'orphaned_percentage': cleanupStats.orphanedPercentage,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        
        _showSuccessDialog(
          'IGC File Analysis',
          'Analysis completed!\n\n'
          'Total IGC Files: ${cleanupStats.totalIgcFiles}\n'
          'Referenced by Flights: ${cleanupStats.referencedFiles}\n'
          'Orphaned Files: ${cleanupStats.orphanedFiles}\n'
          'Total Size: ${cleanupStats.formattedTotalSize}\n'
          'Orphaned Size: ${cleanupStats.formattedOrphanedSize}\n'
          'Orphaned Percentage: ${cleanupStats.orphanedPercentage.toStringAsFixed(1)}%'
        );
      } else {
        LoggingService.structured('IGC_ANALYSIS_FAILED', {
          'error': 'null result',
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        _showErrorDialog('Analysis Failed', 'Failed to analyze IGC files.');
      }
      
    } catch (e, stackTrace) {
      if (mounted) Navigator.of(context).pop(); // Close loading
      
      LoggingService.structured('IGC_ANALYSIS_ERROR', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      LoggingService.error('DataManagementScreen: Failed to analyze IGC files', e, stackTrace);
      _showErrorDialog('Error', 'Failed to analyze IGC files: $e');
    }
  }

  Future<void> _cleanupOrphanedFiles() async {
    if (_cleanupStats == null || _cleanupStats!.orphanedFiles == 0) {
      LoggingService.action('DataManagement', 'cleanup_orphaned_files_none_found');
      _showInfoDialog('No Cleanup Needed', 'No orphaned IGC files found.');
      return;
    }
    
    final confirmed = await _showConfirmationDialog(
      'Clean Orphaned IGC Files',
      'This will permanently delete ${_cleanupStats!.orphanedFiles} orphaned IGC files '
      '(${_cleanupStats!.formattedOrphanedSize}).\n\n'
      'These files are not referenced by any flight records and can be safely removed.\n\n'
      'This action cannot be undone.',
    );
    
    if (!confirmed) {
      LoggingService.action('DataManagement', 'cleanup_orphaned_files_cancelled');
      return;
    }
    
    LoggingService.action('DataManagement', 'cleanup_orphaned_files_confirmed', {
      'orphaned_count': _cleanupStats!.orphanedFiles,
      'orphaned_size_bytes': _cleanupStats!.orphanedSizeBytes,
    });
    final stopwatch = Stopwatch()..start();
    
    _showLoadingDialog('Cleaning up orphaned IGC files...');
    try {
      final result = await IGCCleanupService.cleanupOrphanedFiles(dryRun: false);
      
      if (mounted) Navigator.of(context).pop(); // Close loading
      
      if (result['success'] == true) {
        final filesDeleted = result['filesDeleted'] ?? 0;
        final sizeFreed = result['formattedSizeFreed'] ?? '0B';
        final bytesFreed = result['bytesFreed'] ?? 0;
        final errors = result['errors'] as List<String>? ?? [];
        
        LoggingService.performance('Cleanup orphaned IGC files', stopwatch.elapsed, 'cleanup completed successfully');
        LoggingService.summary('IGC_CLEANUP', {
          'files_deleted': filesDeleted,
          'bytes_freed': bytesFreed,
          'errors': errors.length,
          'success': true,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        
        setState(() {
          _dataModified = true;
        });

        // Refresh the analysis with forced refresh to bypass cache
        await _analyzeIGCFiles(forceRefresh: true);

        String message = 'Cleanup completed successfully!\n\n'
            'Files deleted: $filesDeleted\n'
            'Space freed: $sizeFreed';
        
        if (errors.isNotEmpty) {
          message += '\n\nWarnings:\n${errors.take(3).join('\n')}';
          if (errors.length > 3) {
            message += '\n... and ${errors.length - 3} more';
          }
        }
        
        _showSuccessDialog('Cleanup Complete', message);
      } else {
        LoggingService.structured('IGC_CLEANUP_FAILED', {
          'success': false,
          'error': result['error'] ?? 'Unknown error',
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
        _showErrorDialog('Cleanup Failed', result['error'] ?? 'Unknown error');
      }
      
    } catch (e, stackTrace) {
      if (mounted) Navigator.of(context).pop(); // Close loading
      
      LoggingService.structured('IGC_CLEANUP_ERROR', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      LoggingService.error('DataManagementScreen: Failed to cleanup IGC files', e, stackTrace);
      _showErrorDialog('Error', 'Failed to cleanup IGC files: $e');
    }
  }



  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent automatic pop so we can handle it ourselves
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        // Only handle the pop if it was prevented (didPop = false)
        if (!didPop) {
          // Now we can safely pop with our data
          Navigator.of(context).pop(_dataModified);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Data Management'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_dataModified),
          ),
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Airspace Database (Local copy of OpenAIP data)
                  FutureBuilder<Map<String, dynamic>>(
                    key: ValueKey(_airspaceRefreshKey),
                    future: AirspaceGeoJsonService.instance.getCacheStatistics(),
                    builder: (context, snapshot) {
                      final airspaceCacheStats = snapshot.data;
                      return AppExpansionCard.dataManagement(
                        icon: Icons.layers,
                        title: 'Airspace Database',
                        subtitle: airspaceCacheStats != null
                            ? '${airspaceCacheStats['summary']['country_count'] ?? 0} countries • ${airspaceCacheStats['summary']['total_unique_airspaces']} airspaces • ${airspaceCacheStats['summary']['database_size_mb'] ?? '0.00'}MB'
                            : 'Loading...',
                        expansionKey: 'airspace_cache',
                        expansionManager: _expansionManager,
                        onExpansionChanged: (expanded) {
                          setState(() {
                            _expansionManager.setState('airspace_cache', expanded);
                          });
                        },
                        children: [
                          // Country Selection
                          const Text(
                            'Select countries to display controlled airspace on maps.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 350,
                            child: AirspaceCountrySelector(
                              key: ValueKey(_airspaceRefreshKey),
                              onDataChanged: _handleAirspaceDataChanged,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _clearAirspaceCache,
                              icon: const Icon(Icons.cleaning_services),
                              label: const Text('Clear All Airspace Data'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Android Backup Status
                  AppExpansionCard.dataManagement(
                    icon: Icons.backup,
                    title: 'Android Backup',
                    subtitle: _backupStatus?['success'] == true
                        ? '${_backupStatus!['backupEnabled'] ? '✓ Enabled' : '✗ Disabled'} • ${_igcStats?.fileCount ?? 0} IGC files'
                        : 'Loading...',
                    expansionKey: 'backup_status',
                    expansionManager: _expansionManager,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expansionManager.setState('backup_status', expanded);
                      });
                    },
                    children: [
                      const Text(
                        'Flight data, including the raw IGC files, is automatically backed up to the cloud and can be restored when the app is installed on another device.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      if (_backupStatus?['success'] == true) ...[
                        AppStatRowGroup.dataManagement(
                          rows: [
                            AppStatRow.dataManagement(
                              label: 'Status',
                              value: _backupStatus!['backupEnabled'] ? '✓ Enabled' : '✗ Disabled',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Type',
                              value: '${_backupStatus!['backupType'] ?? 'Unknown'}',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Limit',
                              value: '${_backupStatus!['maxBackupSize'] ?? 'Unknown'}',
                            ),
                          ],
                          padding: EdgeInsets.zero,
                        ),
                      ],
                      if (_igcStats != null) ...[
                        const SizedBox(height: 8),
                        AppStatRowGroup.dataManagement(
                          rows: [
                            AppStatRow.dataManagement(
                              label: 'IGC Files',
                              value: '${_igcStats!.fileCount}',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Original Size',
                              value: _igcStats!.formattedOriginalSize,
                            ),
                            AppStatRow.dataManagement(
                              label: 'Compressed',
                              value: _igcStats!.formattedCompressedSize,
                            ),
                            AppStatRow.dataManagement(
                              label: 'Compression',
                              value: '${_igcStats!.compressionRatio.toStringAsFixed(1)}x',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Backup Usage',
                              value: '${_igcStats!.backupLimitUsagePercent.toStringAsFixed(1)}%',
                            ),
                          ],
                          padding: EdgeInsets.zero,
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _showBackupDiagnostics,
                          icon: const Icon(Icons.info),
                          label: const Text('Full Diagnostics'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Database Management
                  AppExpansionCard.dataManagement(
                    icon: Icons.storage,
                    title: 'Flight DB',
                    subtitle: _dbStats != null
                        ? '${_dbStats!['flights'] ?? 0} flights • ${_dbStats!['sites'] ?? 0} sites • ${_dbStats!['wings'] ?? 0} wings'
                        : 'Loading...',
                    expansionKey: 'database_stats',
                    expansionManager: _expansionManager,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expansionManager.setState('database_stats', expanded);
                      });
                    },
                    children: [
                      const Text(
                        'The the core Flight Track database. Can be deleted, or recreated from the raw IGC file but any manual changes will be lost.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      if (_dbStats != null) ...[
                        AppStatRowGroup.dataManagement(
                          rows: [
                            AppStatRow.dataManagement(
                              label: 'Version',
                              value: '${_dbStats!['version'] ?? 'Unknown'}',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Flights',
                              value: '${_dbStats!['flights'] ?? 0}',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Sites',
                              value: '${_dbStats!['sites'] ?? 0}',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Wings',
                              value: '${_dbStats!['wings'] ?? 0}',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Total Records',
                              value: '${_dbStats!['total_records'] ?? 0}',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Database Size',
                              value: '${_dbStats!['size_kb'] ?? '0'}KB',
                            ),
                          ],
                          padding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Path: ${_dbStats!['path'] ?? 'Unknown'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),

                        const SizedBox(height: 24),

                        // Recreate Information Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.blue.withValues(alpha: 0.1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.info, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Text(
                                    'Recreate from IGC Files',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '• Resets the database and reimports all IGC files found on device\n'
                                '• Use when database is corrupted but IGC files are intact\n'
                                '• Rebuilds complete database from your existing track files\n'
                                '• Preserves all IGC files, only rebuilds database records',
                                style: TextStyle(color: Colors.blue[700]),
                              ),
                              const SizedBox(height: 16),

                              // Recreate from IGC Files button
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _recreateDatabaseFromIGC,
                                  icon: const Icon(Icons.restore),
                                  label: const Text('Recreate from IGC Files'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Danger Zone
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.red.withValues(alpha: 0.1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.warning, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text(
                                    'Danger Zone',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Delete All Flight Data\n\n'
                                '• Removes all flight records and IGC files\n'
                                '• Deletes all flown sites and wings\n'
                                '• Preserves PGE sites database\n'
                                '• Use when starting fresh or freeing storage space\n'
                                '• Warning: This is irreversible - flight data will be lost\n\n'
                                'This action cannot be undone.',
                                style: TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: (_dbStats?['total_records'] ?? 0) > 0 ? _deleteAllFlightData : null,
                                  icon: const Icon(Icons.delete_forever),
                                  label: const Text('Delete All Flight Data'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Free Premium Maps with visual highlighting
                  AnimatedBuilder(
                    key: _premiumMapsKey,
                    animation: _highlightAnimation,
                    builder: (context, child) {
                      final highlightValue = _highlightAnimation.value;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: highlightValue > 0
                              ? [
                                  BoxShadow(
                                    color: Colors.blue.withValues(alpha: 0.3 * highlightValue),
                                    blurRadius: 12 * highlightValue,
                                    spreadRadius: 4 * highlightValue,
                                  ),
                                ]
                              : null,
                        ),
                        child: child,
                      );
                    },
                    child: AppExpansionCard.dataManagement(
                      icon: Icons.map,
                      title: 'Free Premium Maps',
                      subtitle: _cesiumToken != null
                          ? (_isCesiumTokenValidated ? 'Active' : 'Not validated')
                          : 'No token configured',
                      expansionKey: 'premium_maps',
                      expansionManager: _expansionManager,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          _expansionManager.setState('premium_maps', expanded);
                        });
                      },
                      children: [
                      const Text(
                        'To unlock free access to premium Bing Maps you need to provide your own Cesium ION access token. '
                        'Registering with Cesium is free, quick and easy.',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Status: ${_cesiumToken != null ? (_isCesiumTokenValidated ? "Active" : "Not validated") : "No token configured"}',
                        style: TextStyle(
                          color: _cesiumToken != null
                            ? (_isCesiumTokenValidated ? Colors.green : Colors.orange)
                            : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_cesiumToken != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Token: ${CesiumTokenValidator.maskToken(_cesiumToken!)}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        _cesiumToken != null && _isCesiumTokenValidated
                          ? 'You now have access to the Premium maps.'
                          : 'To access premium Bing maps for free follow these 4 steps:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _cesiumToken != null && _isCesiumTokenValidated ? Colors.green : null,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 4-step instructions when no token
                      if (_cesiumToken == null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('1. ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            Expanded(
                              child: GestureDetector(
                                onTap: _launchCesiumSignup,
                                child: const Text(
                                  'Create a free account with Cesium ION.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Colors.blue,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('2. ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            Expanded(
                              child: GestureDetector(
                                onTap: _launchCesiumTokens,
                                child: const Text(
                                  'Navigate to Access Tokens',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Colors.blue,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('3. ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            Expanded(
                              child: Text(
                                'Copy the Default Token',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('4. ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            Expanded(
                              child: GestureDetector(
                                onTap: _showTokenDialog,
                                child: const Text(
                                  'Add your token to this app',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Colors.blue,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ] else
                        const SizedBox(height: 16),
                      // Token management buttons
                      if (_cesiumToken != null)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _isValidatingCesium ? null : _testCesiumToken,
                              icon: _isValidatingCesium
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi_protected_setup),
                              label: const Text('Test Connection'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _showRemoveConfirmDialog,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove Token'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  ),

                  const SizedBox(height: 24),

                  // IGC File Cleanup
                  AppExpansionCard.dataManagement(
                    icon: Icons.cleaning_services,
                    title: 'IGC File Cleanup',
                    subtitle: _cleanupStats != null
                        ? '${_cleanupStats!.totalIgcFiles} (${_cleanupStats!.formattedTotalSize}) • ${_cleanupStats!.orphanedFiles} orphaned'
                        : 'Analyzing files...',
                    expansionKey: 'igc_cleanup',
                    expansionManager: _expansionManager,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expansionManager.setState('igc_cleanup', expanded);
                      });
                    },
                    children: [
                      const Text(
                        'The raw IGC files are retained on your device. IGC files no longer linked to any Flight DB record can be safely removed to free up storage space',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      if (_cleanupStats != null) ...[
                        AppStatRowGroup.dataManagement(
                          rows: [
                            AppStatRow.dataManagement(
                              label: 'Total IGC Files',
                              value: '${_cleanupStats!.totalIgcFiles}',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Referenced by Flights',
                              value: '${_cleanupStats!.referencedFiles}',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Orphaned Files',
                              value: '${_cleanupStats!.orphanedFiles}',
                            ),
                            if (_cleanupStats!.orphanedFiles > 0) ...[
                              AppStatRow.dataManagement(
                                label: 'Total Size',
                                value: _cleanupStats!.formattedTotalSize,
                              ),
                              AppStatRow.dataManagement(
                                label: 'Orphaned Size',
                                value: _cleanupStats!.formattedOrphanedSize,
                              ),
                              AppStatRow.dataManagement(
                                label: 'Orphaned %',
                                value: '${_cleanupStats!.orphanedPercentage.toStringAsFixed(1)}%',
                              ),
                            ],
                          ],
                          padding: EdgeInsets.zero,
                        ),
                      ] else ...[
                        const Text('Analyzing IGC files...'),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _analyzeIGCFiles,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh Analysis'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_cleanupStats?.orphanedFiles ?? 0) > 0 ? _cleanupOrphanedFiles : null,
                              icon: const Icon(Icons.cleaning_services),
                              label: const Text('Clean Orphaned'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Map Cache Statistics
                  AppExpansionCard.dataManagement(
                    icon: Icons.map,
                    title: 'Map Tile Cache',
                    subtitle: '${CacheUtils.getCurrentCacheCount()} tiles • ${CacheUtils.formatBytes(CacheUtils.getCurrentCacheSize())}',
                    expansionKey: 'map_cache',
                    expansionManager: _expansionManager,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expansionManager.setState('map_cache', expanded);
                      });
                    },
                    children: [
                      const Text(
                        'Map tiles are cached when first used to improve map performance. Clear the Map Cache to free up storage space.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      AppStatRowGroup.dataManagement(
                        rows: [
                          AppStatRow.dataManagement(
                            label: 'Cached Tiles',
                            value: CacheUtils.getCurrentCacheCount().toString(),
                          ),
                          AppStatRow.dataManagement(
                            label: 'Cache Size',
                            value: CacheUtils.formatBytes(CacheUtils.getCurrentCacheSize()),
                          ),
                        ],
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: CacheUtils.getCurrentCacheCount() > 0 ? _clearMapCache : null,
                          icon: const Icon(Icons.cleaning_services),
                          label: const Text('Clear Map Cache'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ParaglidingEarth API
                  AppExpansionCard.dataManagement(
                    icon: Icons.cloud_sync,
                    title: 'ParaglidingEarth API',
                    subtitle: 'Lookup site details, eg., name, latitude/longitude, country',
                    expansionKey: 'api_test',
                    expansionManager: _expansionManager,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expansionManager.setState('api_test', expanded);
                      });
                    },
                    children: [
                      const Text(
                        'Test the connection to ParaglidingEarth.com API to lookup site details like name, latitude/longitude, and country.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _testApiConnection,
                          icon: const Icon(Icons.cloud_sync),
                          label: const Text('Test ParaglidingEarth API'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // PGE Sites Database
                  AppExpansionCard.dataManagement(
                    icon: Icons.public,
                    title: 'PGE Sites Database',
                    subtitle: _pgeSitesStats != null
                        ? '${_formatNumber(_pgeSitesStats!['sites_count'] ?? 0)} sites • ${_pgeSitesStats!['database_size_mb'] ?? '0.0'}MB • ${_pgeSitesStats!['status'] ?? 'Unknown'}'
                        : 'Loading...',
                    expansionKey: 'pge_sites_db',
                    expansionManager: _expansionManager,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expansionManager.setState('pge_sites_db', expanded);
                      });
                    },
                    children: [
                      const Text(
                        'The location of every PGE site is stored locally to improve site map performance.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      if (_pgeSitesStats != null) ...[
                        AppStatRowGroup.dataManagement(
                          rows: [
                            AppStatRow.dataManagement(
                              label: 'Total Sites',
                              value: _formatNumber(_pgeSitesStats!['sites_count'] ?? 0),
                            ),
                            AppStatRow.dataManagement(
                              label: 'Database Size',
                              value: '${_pgeSitesStats!['database_size_mb'] ?? '0.0'}MB',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Last Downloaded',
                              value: _pgeSitesStats!['last_downloaded'] ?? 'Never',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Source Size',
                              value: '${_pgeSitesStats!['source_file_size_mb'] ?? '0.0'}MB',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Last Synced',
                              value: _lastSyncTime ?? 'Never',
                            ),
                            if (_pgeSitesProgress != null && _pgeSitesProgress!.status == PgeSitesDownloadStatus.downloading)
                              AppStatRow.dataManagement(
                                label: 'Download Progress',
                                value: '${(_pgeSitesProgress!.progress * 100).toStringAsFixed(1)}%',
                              ),
                          ],
                          padding: EdgeInsets.zero,
                        ),
                      ] else ...[
                        const Text('Loading sites database information...'),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],

                      if (_pgeSitesProgress != null && _pgeSitesProgress!.status == PgeSitesDownloadStatus.downloading) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: _pgeSitesProgress!.progress,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Downloading: ${(_pgeSitesProgress!.downloadedBytes / 1024).toStringAsFixed(0)}KB / ${(_pgeSitesProgress!.totalBytes / 1024).toStringAsFixed(0)}KB',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],

                      const SizedBox(height: 16),
                      const Text(
                        'Download worldwide paragliding sites from ParaglidingEarth for offline use. '
                        'This enables fast site lookups without internet connectivity.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_pgeSitesProgress?.status == PgeSitesDownloadStatus.downloading || _isSyncing)
                                  ? null
                                  : _syncPgeSites,
                              icon: _isSyncing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.sync),
                              label: Text(_isSyncing ? 'Syncing...' : 'Sync Updates'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_pgeSitesProgress?.status == PgeSitesDownloadStatus.downloading || _isSyncing)
                                  ? null
                                  : _downloadPgeSites,
                              icon: const Icon(Icons.download),
                              label: Text(
                                (_pgeSitesStats?['sites_count'] ?? 0) > 0
                                  ? 'Re-download All'
                                  : 'Download Sites'
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
      ),
    );
  }

}