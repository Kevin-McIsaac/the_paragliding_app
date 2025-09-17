import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/database_reset_helper.dart';
import '../../services/site_matching_service.dart';
import '../../services/cesium_token_validator.dart';
import '../../utils/cache_utils.dart';
import '../../utils/preferences_helper.dart';
import '../../services/backup_diagnostic_service.dart';
import '../../services/igc_cleanup_service.dart';
import '../../services/logging_service.dart';
import '../../utils/card_expansion_manager.dart';
import '../widgets/common/app_expansion_card.dart';
import '../widgets/common/app_stat_row.dart';
import '../../services/airspace_geojson_service.dart';
import '../../services/airspace_metadata_cache.dart';
import '../../services/airspace_geometry_cache.dart';
import '../../services/airspace_disk_cache.dart';

class DataManagementScreen extends StatefulWidget {
  final bool expandPremiumMaps;
  
  const DataManagementScreen({super.key, this.expandPremiumMaps = false});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  Map<String, dynamic>? _dbStats;
  Map<String, dynamic>? _backupStatus;
  IGCBackupStats? _igcStats;
  IGCCleanupStats? _cleanupStats;
  bool _isLoading = true;
  bool _dataModified = false; // Track if any data was modified
  
  // Card expansion state manager (session-only for this screen)
  late CardExpansionManager _expansionManager;
  
  // Cesium token state
  String? _cesiumToken;
  bool _isCesiumTokenValidated = false;
  bool _isValidatingCesium = false;

  // Airspace cache state
  Map<String, dynamic>? _airspaceCacheStats;

  @override
  void initState() {
    super.initState();
    LoggingService.action('DataManagement', 'screen_opened', {
      'expand_premium_maps': widget.expandPremiumMaps,
    });
    
    // Initialize expansion manager
    _expansionManager = CardExpansionManagers.createDataManagementManager();
    
    // Set initial Premium Maps expansion state based on parameter
    if (widget.expandPremiumMaps) {
      _expansionManager.setState('premium_maps', true);
    }
    
    _loadDatabaseStats();
    _loadBackupDiagnostics();
    _loadCesiumToken();
    _loadAirspaceCacheStats();
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

  Future<void> _loadBackupDiagnostics() async {
    LoggingService.action('DataManagement', 'load_backup_diagnostics');
    final stopwatch = Stopwatch()..start();
    
    try {
      final backupStatus = await BackupDiagnosticService.getBackupStatus();
      final igcStats = await BackupDiagnosticService.calculateIGCCompressionStats();
      final cleanupStats = await IGCCleanupService.analyzeIGCFiles();
      
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
      });
      
      setState(() {
        _backupStatus = backupStatus;
        _igcStats = igcStats;
        _cleanupStats = cleanupStats;
      });
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
      '• All sites\n' 
      '• All wings\n'
      '• All IGC track files\n\n'
      'This is a complete data wipe and cannot be undone.\n\n'
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
      final result = await DatabaseResetHelper.deleteAllFlightData();
      
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
        
        // Refresh all statistics after deletion
        await _loadDatabaseStats();
        await _loadBackupDiagnostics(); // This includes IGC analysis
        
        // Force refresh of cleanup stats to show cleared state
        setState(() {
          _cleanupStats = null; // Clear to show loading state
        });
        final newCleanupStats = await IGCCleanupService.analyzeIGCFiles();
        setState(() {
          _cleanupStats = newCleanupStats;
        });
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
        
        // Refresh all statistics after recreation
        await _loadDatabaseStats();
        await _loadBackupDiagnostics(); // This includes IGC analysis
        
        // Force refresh of cleanup stats to show updated state
        setState(() {
          _cleanupStats = null; // Clear to show loading state
        });
        final newCleanupStats = await IGCCleanupService.analyzeIGCFiles();
        setState(() {
          _cleanupStats = newCleanupStats;
        });
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


  Future<void> _loadAirspaceCacheStats() async {
    try {
      final stats = await AirspaceGeoJsonService.instance.getCacheStatistics();
      if (mounted) {
        setState(() {
          _airspaceCacheStats = stats;
        });
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to load airspace cache stats', e, stackTrace);
    }
  }

  Future<void> _clearAirspaceCache() async {
    final confirmed = await _showConfirmationDialog(
      'Clear Airspace Cache',
      'This will clear all cached airspace data. The cache will be rebuilt as you view different areas on the map.\n\nThis action cannot be undone.',
    );

    if (!confirmed) return;

    _showLoadingDialog('Clearing airspace cache...');
    try {
      // Clear all cache layers through the service
      await AirspaceGeoJsonService.instance.clearCache();

      if (mounted) Navigator.of(context).pop(); // Close loading

      await _loadAirspaceCacheStats(); // Reload stats

      _showSuccessDialog(
        'Cache Cleared',
        'Airspace cache has been cleared successfully. Please navigate back to the map to reload airspaces.',
      );
    } catch (e, stackTrace) {
      if (mounted) Navigator.of(context).pop(); // Close loading
      LoggingService.error('Failed to clear airspace cache', e, stackTrace);
      _showErrorDialog('Error', 'Failed to clear airspace cache: $e');
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

  Future<void> _analyzeIGCFiles() async {
    LoggingService.action('DataManagement', 'analyze_igc_files');
    final stopwatch = Stopwatch()..start();
    
    _showLoadingDialog('Analyzing IGC files...');
    try {
      final cleanupStats = await IGCCleanupService.analyzeIGCFiles();
      
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
        
        // Refresh the analysis
        await _analyzeIGCFiles();
        
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
              padding: const EdgeInsets.only(top: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

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

                  // Airspace Cache (New Hierarchical Cache)
                  AppExpansionCard.dataManagement(
                    icon: Icons.layers,
                    title: 'Airspace Cache',
                    subtitle: _airspaceCacheStats != null
                        ? '${_airspaceCacheStats!['summary']['total_unique_airspaces']} airspaces • ${_airspaceCacheStats!['summary']['database_size_mb'] ?? '0.00'}MB database'
                        : 'Loading...',
                    expansionKey: 'airspace_cache',
                    expansionManager: _expansionManager,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expansionManager.setState('airspace_cache', expanded);
                      });
                      if (expanded) {
                        _loadAirspaceCacheStats(); // Refresh when expanded
                      }
                    },
                    children: [
                      if (_airspaceCacheStats != null) ...[
                        AppStatRowGroup.dataManagement(
                          rows: [
                            AppStatRow.dataManagement(
                              label: 'Database Size',
                              value: '${_airspaceCacheStats!['summary']['database_size_mb'] ?? '0.00'}MB / 100MB',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Unique Airspaces',
                              value: _airspaceCacheStats!['summary']['total_unique_airspaces'].toString(),
                            ),
                            AppStatRow.dataManagement(
                              label: 'Cached Tiles',
                              value: _airspaceCacheStats!['summary']['total_tiles_cached'].toString(),
                            ),
                            AppStatRow.dataManagement(
                              label: 'Empty Tiles',
                              value: _airspaceCacheStats!['summary']['empty_tiles'].toString(),
                            ),
                            AppStatRow.dataManagement(
                              label: 'Compression Ratio',
                              value: '${(_airspaceCacheStats!['summary']['compression_ratio'] as String).substring(0, 4)}x',
                            ),
                            AppStatRow.dataManagement(
                              label: 'Cache Hit Rate',
                              value: '${(double.parse(_airspaceCacheStats!['summary']['cache_hit_rate']) * 100).toStringAsFixed(1)}%',
                            ),
                          ],
                          padding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: (((_airspaceCacheStats!['summary']['total_unique_airspaces'] as int?) ?? 0) > 0 ||
                                    ((_airspaceCacheStats!['summary']['total_cached_tiles'] as int?) ?? 0) > 0)
                                ? _clearAirspaceCache
                                : null,
                            icon: const Icon(Icons.cleaning_services),
                            label: const Text('Clear Airspace Cache'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                            ),
                          ),
                        ),
                      ] else
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
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
                  
                  // Free Premium Maps
                  AppExpansionCard.dataManagement(
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
                  
                  const SizedBox(height: 24),
                  
                  // Database Management
                  AppExpansionCard.dataManagement(
                    icon: Icons.storage,
                    title: 'Database Management',
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
                                '• Completely removes ALL data (database + IGC files)\n'
                                '• Use when starting completely fresh or freeing storage space\n'
                                '• Deletes everything - database records AND IGC files\n'
                                '• Warning: This is irreversible - all flight data will be lost\n\n'
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
                ],
              ),
            ),
      ),
    );
  }

}