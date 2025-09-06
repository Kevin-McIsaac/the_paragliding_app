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
      LoggingService.debug(_tag, 'Starting IGC file analysis');
      
      // Get all flights with their track paths
      final flights = await DatabaseService.instance.getAllFlightsRaw();
      final referencedFilenames = <String>{};
      
      LoggingService.debug(_tag, 'Retrieved ${flights.length} flight records from database');
      
      for (final flight in flights) {
        final trackPath = flight['track_log_path'] as String?;
        LoggingService.debug(_tag, 'Flight ${flight['id']}: track_log_path = "$trackPath"');
        
        if (trackPath != null && trackPath.isNotEmpty) {
          // Extract just the filename from the path (handles both absolute and relative paths)
          final filename = path.basename(trackPath);
          referencedFilenames.add(filename);
          LoggingService.debug(_tag, 'Referenced path: $trackPath -> filename: $filename');
        }
      }
      
      LoggingService.debug(_tag, 'Found ${flights.length} flights with ${referencedFilenames.length} unique filenames');
      
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
        LoggingService.debug(_tag, 'File: ${file.path} -> filename: $filename');
        
        if (referencedFilenames.contains(filename)) {
          referencedCount++;
          LoggingService.debug(_tag, 'MATCHED: $filename');
        } else {
          orphanedFiles.add(file.path);
          orphanedSize += size;
          LoggingService.debug(_tag, 'ORPHANED: $filename');
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
      
      LoggingService.info(_tag, 'Analysis complete: ${stats.totalIgcFiles} total files, '
          '${stats.referencedFiles} referenced, ${stats.orphanedFiles} orphaned '
          '(${stats.orphanedPercentage.toStringAsFixed(1)}%)');
      
      return stats;
    } catch (e) {
      LoggingService.error(_tag, 'Failed to analyze IGC files: $e');
      return null;
    }
  }

  /// Clean up orphaned IGC files
  static Future<Map<String, dynamic>> cleanupOrphanedFiles({bool dryRun = true}) async {
    try {
      LoggingService.debug(_tag, 'Starting IGC cleanup (dry run: $dryRun)');
      
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
              LoggingService.debug(_tag, 'Deleted orphaned file: $filePath (${_formatBytes(size)})');
            }
          } catch (e) {
            LoggingService.warning(_tag, 'Failed to delete file $filePath: $e');
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
      LoggingService.error(_tag, 'IGC cleanup failed: $e');
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
      LoggingService.error(_tag, 'Error finding IGC files: $e');
    }
    
    return igcFiles;
  }

  /// Get relative path for comparison with database
  static Future<String> _getRelativePath(File file) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final relativePath = path.relative(file.path, from: appDir.path);
      return relativePath;
    } catch (e) {
      LoggingService.warning(_tag, 'Failed to get relative path for ${file.path}: $e');
      return file.path;
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}