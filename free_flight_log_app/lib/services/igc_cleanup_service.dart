import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'logging_service.dart';
import 'database_service.dart';
import 'igc_file_manager.dart';
import 'backup_diagnostics_cache.dart';

class IGCCleanupStats {
  final int totalIgcFiles;
  final int referencedFiles;
  final int orphanedFiles;
  final int totalSizeBytes;
  final int orphanedSizeBytes;
  final List<String> orphanedFilePaths;

  IGCCleanupStats({
    required this.totalIgcFiles,
    required this.referencedFiles,
    required this.orphanedFiles,
    required this.totalSizeBytes,
    required this.orphanedSizeBytes,
    required this.orphanedFilePaths,
  });

  String get formattedTotalSize => _formatBytes(totalSizeBytes);
  String get formattedOrphanedSize => _formatBytes(orphanedSizeBytes);
  
  double get orphanedPercentage => totalIgcFiles > 0 
      ? (orphanedFiles / totalIgcFiles) * 100 
      : 0.0;

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class IGCCleanupService {

  /// Analyze IGC files and identify orphans with caching
  static Future<IGCCleanupStats?> analyzeIGCFiles({bool forceRefresh = false}) async {
    // Check cache first unless forced refresh
    if (!forceRefresh) {
      final cached = BackupDiagnosticsCache.getCachedCleanupStats();
      if (cached != null) {
        return cached;
      }
    }

    try {
      LoggingService.debug('Starting IGC file analysis');
      final overallStopwatch = Stopwatch()..start();

      // Get all flights with their track paths
      final flightsStopwatch = Stopwatch()..start();
      final flights = await DatabaseService.instance.getAllFlightsRaw();
      final referencedFilenames = <String>{};
      flightsStopwatch.stop();

      LoggingService.structured('IGC_ANALYSIS_START', {
        'flight_records': flights.length,
        'flights_query_ms': flightsStopwatch.elapsedMilliseconds,
      });

      // Extract referenced filenames
      final extractionStopwatch = Stopwatch()..start();
      for (final flight in flights) {
        final trackPath = flight['track_log_path'] as String?;

        if (trackPath != null && trackPath.isNotEmpty) {
          // Extract just the filename from the path (handles both absolute and relative paths)
          final filename = path.basename(trackPath);
          referencedFilenames.add(filename);
        }
      }
      extractionStopwatch.stop();

      // Use centralized file manager (with its own caching)
      final filesStopwatch = Stopwatch()..start();
      final allIgcFiles = await IGCFileManager.getIGCFiles(forceRefresh: forceRefresh);
      filesStopwatch.stop();

      // Analyze files in batches to avoid blocking
      const batchSize = 20;
      final orphanedFiles = <String>[];
      int totalSize = 0;
      int orphanedSize = 0;
      int referencedCount = 0;

      final analysisStopwatch = Stopwatch()..start();

      for (int i = 0; i < allIgcFiles.length; i += batchSize) {
        final end = (i + batchSize < allIgcFiles.length) ? i + batchSize : allIgcFiles.length;
        final batch = allIgcFiles.sublist(i, end);

        for (final file in batch) {
          try {
            final size = await file.length();
            totalSize += size;

            // Extract filename for comparison
            final filename = path.basename(file.path);

            if (referencedFilenames.contains(filename)) {
              referencedCount++;
            } else {
              orphanedFiles.add(file.path);
              orphanedSize += size;
            }
          } catch (e) {
            LoggingService.warning('Failed to analyze IGC file ${file.path}: $e');
          }
        }

        // Yield control periodically
        if (i % (batchSize * 3) == 0) {
          await Future.delayed(Duration.zero);
        }
      }
      analysisStopwatch.stop();

      final stats = IGCCleanupStats(
        totalIgcFiles: allIgcFiles.length,
        referencedFiles: referencedCount,
        orphanedFiles: orphanedFiles.length,
        totalSizeBytes: totalSize,
        orphanedSizeBytes: orphanedSize,
        orphanedFilePaths: orphanedFiles,
      );

      overallStopwatch.stop();

      LoggingService.structured('IGC_ANALYSIS_COMPLETE', {
        'total_files': stats.totalIgcFiles,
        'referenced_files': stats.referencedFiles,
        'orphaned_files': stats.orphanedFiles,
        'orphaned_percentage': stats.orphanedPercentage.toStringAsFixed(1),
        'total_size_mb': (stats.totalSizeBytes / 1024 / 1024).toStringAsFixed(1),
        'orphaned_size_mb': (stats.orphanedSizeBytes / 1024 / 1024).toStringAsFixed(1),
        'total_time_ms': overallStopwatch.elapsedMilliseconds,
        'flights_query_ms': flightsStopwatch.elapsedMilliseconds,
        'extraction_ms': extractionStopwatch.elapsedMilliseconds,
        'files_scan_ms': filesStopwatch.elapsedMilliseconds,
        'analysis_ms': analysisStopwatch.elapsedMilliseconds,
        'batched_processing': true,
      });

      // Cache the result
      BackupDiagnosticsCache.cacheCleanupStats(stats);
      return stats;

    } catch (e, stackTrace) {
      LoggingService.error('Failed to analyze IGC files', e, stackTrace);

      // Cache null result to avoid immediate retry
      BackupDiagnosticsCache.cacheCleanupStats(null);
      return null;
    }
  }

  /// Clean up orphaned IGC files
  static Future<Map<String, dynamic>> cleanupOrphanedFiles({bool dryRun = true}) async {
    try {
      LoggingService.action('IGCCleanup', 'start_cleanup', {'dry_run': dryRun});
      
      final stats = await analyzeIGCFiles();
      if (stats == null) {
        return {
          'success': false,
          'error': 'Failed to analyze IGC files',
        };
      }
      
      if (stats.orphanedFiles == 0) {
        return {
          'success': true,
          'filesDeleted': 0,
          'sizeFreed': 0,
          'message': 'No orphaned files found',
        };
      }
      
      int deletedCount = 0;
      int freedSize = 0;
      final errors = <String>[];
      
      if (!dryRun) {
        for (final filePath in stats.orphanedFilePaths) {
          try {
            final file = File(filePath);
            if (await file.exists()) {
              final size = await file.length();
              await file.delete();
              deletedCount++;
              freedSize += size;
              // Individual file deletion logged only for actual deletions (not dry run)
              if (deletedCount % 10 == 0 || deletedCount == stats.orphanedFiles) {
                LoggingService.debug('Deleted orphaned files: $deletedCount/${stats.orphanedFiles}');
              }
            }
          } catch (e) {
            LoggingService.warning('Failed to delete IGC file: $e');
            errors.add('$filePath: $e');
          }
        }
      }
      
      return {
        'success': true,
        'dryRun': dryRun,
        'filesDeleted': dryRun ? stats.orphanedFiles : deletedCount,
        'sizeFreed': dryRun ? stats.orphanedSizeBytes : freedSize,
        'formattedSizeFreed': dryRun ? stats.formattedOrphanedSize : _formatBytes(freedSize),
        'errors': errors,
      };
      
    } catch (e) {
      LoggingService.error('IGC cleanup failed: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Removed old _findAllIGCFiles method - now using IGCFileManager

  /// Get relative path for comparison with database

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}