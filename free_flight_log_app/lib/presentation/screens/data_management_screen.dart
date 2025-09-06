import 'package:flutter/material.dart';
import '../../utils/database_reset_helper.dart';
import '../../services/site_matching_service.dart';
import '../../services/cesium_token_validator.dart';
import '../../utils/cache_utils.dart';
import '../../utils/preferences_helper.dart';
import '../../services/backup_diagnostic_service.dart';
import '../../services/igc_cleanup_service.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

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
  
  // Expansion state for collapsible cards - all start collapsed
  bool _dbStatsExpanded = false;
  bool _backupExpanded = false;
  bool _mapCacheExpanded = false;
  bool _cleanupExpanded = false;
  bool _apiTestExpanded = false;
  bool _actionsExpanded = false;
  
  // Cesium token state
  String? _cesiumToken;
  bool _isCesiumTokenValidated = false;
  bool _isValidatingCesium = false;

  @override
  void initState() {
    super.initState();
    _loadDatabaseStats();
    _loadBackupDiagnostics();
    _loadCesiumToken();
  }

  Future<void> _loadDatabaseStats() async {
    setState(() => _isLoading = true);
    final stats = await DatabaseResetHelper.getDatabaseStats();
    setState(() {
      _dbStats = stats;
      _isLoading = false;
    });
  }

  Future<void> _loadBackupDiagnostics() async {
    try {
      final backupStatus = await BackupDiagnosticService.getBackupStatus();
      final igcStats = await BackupDiagnosticService.calculateIGCCompressionStats();
      final cleanupStats = await IGCCleanupService.analyzeIGCFiles();
      
      setState(() {
        _backupStatus = backupStatus;
        _igcStats = igcStats;
        _cleanupStats = cleanupStats;
      });
    } catch (e) {
      print('Error loading backup diagnostics: $e');
    }
  }

  Future<void> _loadCesiumToken() async {
    try {
      final token = await PreferencesHelper.getCesiumUserToken();
      final validated = await PreferencesHelper.getCesiumTokenValidated() ?? false;
      
      if (mounted) {
        setState(() {
          _cesiumToken = token;
          _isCesiumTokenValidated = validated;
        });
      }
    } catch (e) {
      print('Error loading Cesium token: $e');
    }
  }

  Future<void> _testCesiumToken() async {
    if (_cesiumToken == null) return;
    
    setState(() {
      _isValidatingCesium = true;
    });

    try {
      final isValid = await CesiumTokenValidator.validateToken(_cesiumToken!);
      
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
    } catch (e) {
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

    if (!confirmed) return;

    // Show loading
    _showLoadingDialog('Deleting all flight data...');

    try {
      final result = await DatabaseResetHelper.deleteAllFlightData();
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (result['success']) {
        setState(() {
          _dataModified = true; // Mark data as modified
        });
        _showSuccessDialog('All Flight Data Deleted', result['message']);
        await _loadDatabaseStats(); // Refresh stats
      } else {
        _showErrorDialog('Deletion Failed', result['message']);
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
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

    if (!confirmed) return;

    // Show progress dialog initially
    _showProgressDialog('Finding IGC files...', '', 0, 0);

    try {
      String currentFile = '';
      int processed = 0;
      int total = 0;
      
      final result = await DatabaseResetHelper.recreateDatabaseFromIGCFiles(
        onProgress: (filename, current, totalFiles) {
          currentFile = filename;
          processed = current;
          total = totalFiles;
          
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
        setState(() {
          _dataModified = true; // Mark data as modified
        });
        
        final found = result['found'] ?? 0;
        final imported = result['imported'] ?? 0;
        final failed = result['failed'] ?? 0;
        final errors = result['errors'] as List<String>? ?? [];
        
        String message = result['message'] ?? 'Database recreated successfully!';
        
        if (failed > 0 && errors.isNotEmpty) {
          // Show errors in dialog for failed imports
          final errorDetails = errors.take(5).join('\n'); // Show first 5 errors
          final moreErrors = errors.length > 5 ? '\n... and ${errors.length - 5} more errors' : '';
          message += '\n\nFailed imports:\n$errorDetails$moreErrors';
        }
        
        _showSuccessDialog('Database Recreation Complete', message);
        await _loadDatabaseStats(); // Refresh stats
      } else {
        _showErrorDialog('Recreation Failed', result['message']);
      }
    } catch (e) {
      // Close progress dialog
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog('Error', 'Failed to recreate database from IGC files: $e');
    }
  }

  Future<void> _clearFlights() async {
    final confirmed = await _showConfirmationDialog(
      'Clear All Flights',
      'This will permanently delete all flight records.\n\n'
      'Sites and wings will be preserved.\n\n'
      'This action cannot be undone.',
    );

    if (!confirmed) return;

    _showLoadingDialog('Clearing flights...');

    try {
      final result = await DatabaseResetHelper.clearAllFlights();
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (result['success']) {
        setState(() {
          _dataModified = true; // Mark data as modified
        });
        _showSuccessDialog('Flights Cleared', result['message']);
        await _loadDatabaseStats(); // Refresh stats
      } else {
        _showErrorDialog('Clear Failed', result['message']);
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog('Error', 'Failed to clear flights: $e');
    }
  }

  Future<void> _clearMapCache() async {
    final confirmed = await _showConfirmationDialog(
      'Clear Map Cache',
      'This will clear all cached map tiles.\n\n'
      'Maps will need to re-download tiles when viewed.',
    );

    if (!confirmed) return;

    CacheUtils.clearMapCache();

    // Give the system a moment to update cache stats
    await Future.delayed(const Duration(milliseconds: 100));
    
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
    // Show loading
    _showLoadingDialog('Testing ParaglidingEarth API connection...');

    try {
      final siteService = SiteMatchingService.instance;
      final isConnected = await siteService.testApiConnection();
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
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
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      // Show error
      if (mounted) {
        _showErrorDialog('API Test Error', 'Error testing API connection: $e');
      }
    }
  }

  Future<void> _testIGCCompression() async {
    _showLoadingDialog('Testing IGC compression...');

    try {
      final result = await BackupDiagnosticService.testCompressionIntegrity();
      
      if (mounted) Navigator.of(context).pop(); // Close loading
      
      if (result['success'] == true) {
        final filename = result['filename'] ?? 'Unknown';
        final originalSize = result['originalSize'] ?? 0;
        final compressedSize = result['compressedSize'] ?? 0;
        final ratio = result['compressionRatio'] ?? 0.0;
        final dataIntact = result['dataIntact'] ?? false;
        
        _showSuccessDialog(
          'IGC Compression Test',
          'Test completed successfully!\n\n'
          'File: $filename\n'
          'Original: ${_formatBytes(originalSize)}\n'
          'Compressed: ${_formatBytes(compressedSize)}\n'
          'Ratio: ${ratio.toStringAsFixed(1)}x compression\n'
          'Data integrity: ${dataIntact ? '✓ Perfect' : '✗ Failed'}'
        );
      } else {
        _showErrorDialog('Compression Test Failed', result['error'] ?? 'Unknown error');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog('Test Error', 'Failed to test compression: $e');
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
    _showLoadingDialog('Analyzing IGC files...');
    try {
      final cleanupStats = await IGCCleanupService.analyzeIGCFiles();
      
      if (mounted) Navigator.of(context).pop(); // Close loading
      
      setState(() {
        _cleanupStats = cleanupStats;
      });
      
      if (cleanupStats != null) {
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
        _showErrorDialog('Analysis Failed', 'Failed to analyze IGC files.');
      }
      
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // Close loading
      _showErrorDialog('Error', 'Failed to analyze IGC files: $e');
    }
  }

  Future<void> _cleanupOrphanedFiles() async {
    if (_cleanupStats == null || _cleanupStats!.orphanedFiles == 0) {
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
    
    if (!confirmed) return;
    
    _showLoadingDialog('Cleaning up orphaned IGC files...');
    try {
      final result = await IGCCleanupService.cleanupOrphanedFiles(dryRun: false);
      
      if (mounted) Navigator.of(context).pop(); // Close loading
      
      if (result['success'] == true) {
        final filesDeleted = result['filesDeleted'] ?? 0;
        final sizeFreed = result['formattedSizeFreed'] ?? '0B';
        final errors = result['errors'] as List<String>? ?? [];
        
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
        _showErrorDialog('Cleanup Failed', result['error'] ?? 'Unknown error');
      }
      
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // Close loading
      _showErrorDialog('Error', 'Failed to cleanup IGC files: $e');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
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
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.map),
                      title: const Text('Map Tile Cache'),
                      subtitle: Text('${CacheUtils.getCurrentCacheCount()} tiles • ${CacheUtils.formatBytes(CacheUtils.getCurrentCacheSize())}'),
                      initiallyExpanded: _mapCacheExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          _mapCacheExpanded = expanded;
                        });
                      },
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatRow('Cached Tiles', CacheUtils.getCurrentCacheCount().toString()),
                              _buildStatRow('Cache Size', CacheUtils.formatBytes(CacheUtils.getCurrentCacheSize())),
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
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),

                  // Android Backup Status
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.backup),
                      title: const Text('Android Backup'),
                      subtitle: _backupStatus?['success'] == true 
                        ? Text('${_backupStatus!['backupEnabled'] ? '✓ Enabled' : '✗ Disabled'} • ${_igcStats?.fileCount ?? 0} IGC files')
                        : const Text('Loading...'),
                      initiallyExpanded: _backupExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          _backupExpanded = expanded;
                        });
                      },
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_backupStatus?['success'] == true) ...[
                            _buildStatRow(
                              'Status', 
                              '${_backupStatus!['backupEnabled'] ? '✓ Enabled' : '✗ Disabled'}',
                            ),
                            _buildStatRow('Type', '${_backupStatus!['backupType'] ?? 'Unknown'}'),
                            _buildStatRow('Limit', '${_backupStatus!['maxBackupSize'] ?? 'Unknown'}'),
                              ],
                              if (_igcStats != null) ...[
                            const SizedBox(height: 8),
                            _buildStatRow('IGC Files', '${_igcStats!.fileCount}'),
                            _buildStatRow('Original Size', _igcStats!.formattedOriginalSize),
                            _buildStatRow('Compressed', _igcStats!.formattedCompressedSize),
                            _buildStatRow(
                              'Compression', 
                              '${_igcStats!.compressionRatio.toStringAsFixed(1)}x'
                            ),
                            _buildStatRow(
                              'Backup Usage', 
                              '${_igcStats!.backupLimitUsagePercent.toStringAsFixed(1)}%'
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
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  // IGC File Cleanup
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.cleaning_services),
                      title: const Text('IGC File Cleanup'),
                      subtitle: _cleanupStats != null 
                        ? Text('${_cleanupStats!.totalIgcFiles} total • ${_cleanupStats!.orphanedFiles} orphaned')
                        : const Text('Analyzing files...'),
                      initiallyExpanded: _cleanupExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          _cleanupExpanded = expanded;
                        });
                      },
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_cleanupStats != null) ...[
                                _buildStatRow('Total IGC Files', '${_cleanupStats!.totalIgcFiles}'),
                                _buildStatRow('Referenced by Flights', '${_cleanupStats!.referencedFiles}'),
                                _buildStatRow('Orphaned Files', '${_cleanupStats!.orphanedFiles}'),
                                if (_cleanupStats!.orphanedFiles > 0) ...[
                                  _buildStatRow('Total Size', _cleanupStats!.formattedTotalSize),
                                  _buildStatRow('Orphaned Size', _cleanupStats!.formattedOrphanedSize),
                                  _buildStatRow('Orphaned %', '${_cleanupStats!.orphanedPercentage.toStringAsFixed(1)}%'),
                                ],
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
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // PGE API Test
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.cloud_sync),
                      title: const Text('APIs'),
                      subtitle: const Text('Manage external API connections'),
                      initiallyExpanded: _apiTestExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          _apiTestExpanded = expanded;
                        });
                      },
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ParaglidingEarth API Section
                              const Text(
                                'ParaglidingEarth API',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Test the connection to ParaglidingEarth.com API for site data synchronization.',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
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
                              
                              const SizedBox(height: 24),
                              const Divider(),
                              const SizedBox(height: 16),
                              
                              // Cesium Token Section
                              const Text(
                                'Cesium Ion Access Token',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
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
                                  ? 'Premium Bing maps are available for use.'
                                  : 'Configure your Cesium Ion token to access premium maps.',
                                style: TextStyle(
                                  color: _cesiumToken != null && _isCesiumTokenValidated 
                                    ? Colors.green 
                                    : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_cesiumToken != null)
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _isValidatingCesium ? null : _testCesiumToken,
                                    icon: _isValidatingCesium 
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.wifi_protected_setup),
                                    label: const Text('Test Cesium Token'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                    ),
                                  ),
                                )
                              else
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pushNamed(context, '/preferences');
                                    },
                                    icon: const Icon(Icons.settings),
                                    label: const Text('Configure in Preferences'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Database Management
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.storage),
                      title: const Text('Database Management'),
                      subtitle: _dbStats != null 
                        ? Text('${_dbStats!['flights'] ?? 0} flights • ${_dbStats!['sites'] ?? 0} sites • ${_dbStats!['wings'] ?? 0} wings')
                        : const Text('Loading...'),
                      initiallyExpanded: _dbStatsExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          _dbStatsExpanded = expanded;
                        });
                      },
                      children: [
                        if (_dbStats != null) 
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStatRow('Version', '${_dbStats!['version'] ?? 'Unknown'}'),
                                _buildStatRow('Flights', '${_dbStats!['flights'] ?? 0}'),
                                _buildStatRow('Sites', '${_dbStats!['sites'] ?? 0}'),
                                _buildStatRow('Wings', '${_dbStats!['wings'] ?? 0}'),
                                _buildStatRow('Total Records', '${_dbStats!['total_records'] ?? 0}'),
                                _buildStatRow('Database Size', '${_dbStats!['size_kb'] ?? '0'}KB'),
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
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}