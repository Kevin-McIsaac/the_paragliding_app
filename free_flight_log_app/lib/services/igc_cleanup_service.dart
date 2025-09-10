import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'logging_service.dart';
import 'database_service.dart';

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
  static const String _tag = 'IGCCleanupService';

  /// Analyze IGC files and identify orphans
  static Future<IGCCleanupStats?> analyzeIGCFiles() async {
    try {
      LoggingService.debug('Starting IGC file analysis');
      
      // Get all flights with their track paths
      final flights = await DatabaseService.instance.getAllFlightsRaw();
      final referencedFilenames = <String>{};
      
      LoggingService.structured('IGC_ANALYSIS_START', {
        'flight_records': flights.length,
      });
      
      for (final flight in flights) {
        final trackPath = flight['track_log_path'] as String?;
        
        if (trackPath != null && trackPath.isNotEmpty) {
          // Extract just the filename from the path (handles both absolute and relative paths)
          final filename = path.basename(trackPath);
          referencedFilenames.add(filename);
        }
      }
      
      // Find all IGC files
      final allIgcFiles = await _findAllIGCFiles();
      final orphanedFiles = <String>[];
      int totalSize = 0;
      int orphanedSize = 0;
      int referencedCount = 0;
      
      for (final file in allIgcFiles) {
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
      }
      
      final stats = IGCCleanupStats(
        totalIgcFiles: allIgcFiles.length,
        referencedFiles: referencedCount,
        orphanedFiles: orphanedFiles.length,
        totalSizeBytes: totalSize,
        orphanedSizeBytes: orphanedSize,
        orphanedFilePaths: orphanedFiles,
      );
      
      LoggingService.structured('IGC_ANALYSIS_COMPLETE', {
        'total_files': stats.totalIgcFiles,
        'referenced_files': stats.referencedFiles, 
        'orphaned_files': stats.orphanedFiles,
        'orphaned_percentage': stats.orphanedPercentage.toStringAsFixed(1),
        'total_size_mb': (stats.totalSizeBytes / 1024 / 1024).toStringAsFixed(1),
        'orphaned_size_mb': (stats.orphanedSizeBytes / 1024 / 1024).toStringAsFixed(1),
      });
      
      return stats;
    } catch (e) {
      LoggingService.error('Failed to analyze IGC files: $e');
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

  /// Find all IGC files in app directories
  static Future<List<File>> _findAllIGCFiles() async {
    final List<File> igcFiles = [];
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      
      // IGC file locations used by this app
      final igcDirectories = [
        'igc_tracks',        // Primary location
        'igc_files',         // Legacy location
        'imported_igc',      // Alternative location
        'flight_tracks',     // Alternative location
      ];
      
      // Check root documents directory
      final rootFiles = await appDir
          .list()
          .where((entity) => entity is File && 
                 entity.path.toLowerCase().endsWith('.igc'))
          .cast<File>()
          .toList();
      igcFiles.addAll(rootFiles);
      
      // Check subdirectories
      for (final dirName in igcDirectories) {
        final dir = Directory('${appDir.path}/$dirName');
        
        if (await dir.exists()) {
          final files = await dir
              .list()
              .where((entity) => entity is File && 
                     entity.path.toLowerCase().endsWith('.igc'))
              .cast<File>()
              .toList();
          igcFiles.addAll(files);
        }
      }
      
    } catch (e) {
      LoggingService.error('Error finding IGC files: $e');
    }
    
    return igcFiles;
  }

  /// Get relative path for comparison with database

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}