import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'logging_service.dart';

/// Centralized manager for IGC file discovery and caching
/// Eliminates redundant file system scans across multiple services
class IGCFileManager {
  static List<File>? _cachedFileList;
  static DateTime? _lastScan;
  static const Duration _cacheValidity = Duration(minutes: 5);

  /// Get all IGC files with caching
  static Future<List<File>> getIGCFiles({bool forceRefresh = false}) async {
    // Return cached results if valid and not forced refresh
    if (!forceRefresh && _isCacheValid()) {
      LoggingService.debug('IGCFileManager: Using cached file list (${_cachedFileList!.length} files)');
      return _cachedFileList!;
    }

    LoggingService.debug('IGCFileManager: Scanning for IGC files...');
    final stopwatch = Stopwatch()..start();

    try {
      _cachedFileList = await _scanForIGCFiles();
      _lastScan = DateTime.now();

      stopwatch.stop();
      LoggingService.structured('IGC_FILE_SCAN_COMPLETE', {
        'files_found': _cachedFileList!.length,
        'scan_time_ms': stopwatch.elapsedMilliseconds,
        'cached_until': _lastScan!.add(_cacheValidity).toIso8601String(),
      });

      return _cachedFileList!;
    } catch (e, stackTrace) {
      LoggingService.error('IGCFileManager: Failed to scan for IGC files', e, stackTrace);
      return _cachedFileList ?? [];
    }
  }

  /// Check if cache is still valid
  static bool _isCacheValid() {
    return _cachedFileList != null &&
           _lastScan != null &&
           DateTime.now().difference(_lastScan!) < _cacheValidity;
  }

  /// Clear the cache (useful after file operations)
  static void clearCache() {
    _cachedFileList = null;
    _lastScan = null;
    LoggingService.debug('IGCFileManager: Cache cleared');
  }

  /// Get cache statistics
  static Map<String, dynamic> getCacheStats() {
    return {
      'is_cached': _cachedFileList != null,
      'files_cached': _cachedFileList?.length ?? 0,
      'cache_age_seconds': _lastScan != null
          ? DateTime.now().difference(_lastScan!).inSeconds
          : null,
      'cache_valid': _isCacheValid(),
      'cache_expires_in_seconds': _lastScan != null
          ? _cacheValidity.inSeconds - DateTime.now().difference(_lastScan!).inSeconds
          : null,
    };
  }

  /// Private method to perform the actual file system scan
  static Future<List<File>> _scanForIGCFiles() async {
    final igcFiles = <File>[];

    try {
      final appDir = await getApplicationDocumentsDirectory();

      // Known IGC directories used by the app
      final igcDirectories = [
        'igc_tracks',        // Primary location
        'igc_files',         // Legacy location
        'imported_igc',      // Alternative location
        'flight_tracks',     // Alternative location
      ];

      // First check root documents directory
      final rootFiles = await _scanDirectory(appDir, recursive: false);
      igcFiles.addAll(rootFiles);

      int directoriesScanned = 1;

      // Then check each known IGC directory
      for (final dirName in igcDirectories) {
        final dir = Directory('${appDir.path}/$dirName');

        if (await dir.exists()) {
          final files = await _scanDirectory(dir, recursive: true);
          igcFiles.addAll(files);
          directoriesScanned++;
        }
      }

      LoggingService.structured('IGC_SCAN_DETAILS', {
        'directories_scanned': directoriesScanned,
        'total_files_found': igcFiles.length,
        'app_dir_files': rootFiles.length,
        'subdirectory_files': igcFiles.length - rootFiles.length,
      });

    } catch (e, stackTrace) {
      LoggingService.error('IGCFileManager: Error during file scan', e, stackTrace);
    }

    return igcFiles;
  }

  /// Scan a directory for IGC files
  static Future<List<File>> _scanDirectory(Directory directory, {bool recursive = false}) async {
    final igcFiles = <File>[];

    try {
      if (!await directory.exists()) {
        return igcFiles;
      }

      await for (final entity in directory.list(recursive: recursive)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.igc')) {
          igcFiles.add(entity);
        }
      }
    } catch (e) {
      LoggingService.warning('IGCFileManager: Failed to scan directory ${directory.path}: $e');
    }

    return igcFiles;
  }

  /// Get files in batches for processing
  static Future<List<List<File>>> getFilesInBatches({
    int batchSize = 10,
    bool forceRefresh = false,
  }) async {
    final allFiles = await getIGCFiles(forceRefresh: forceRefresh);
    final batches = <List<File>>[];

    for (int i = 0; i < allFiles.length; i += batchSize) {
      final end = (i + batchSize < allFiles.length) ? i + batchSize : allFiles.length;
      batches.add(allFiles.sublist(i, end));
    }

    LoggingService.debug('IGCFileManager: Created ${batches.length} batches of ~$batchSize files each');
    return batches;
  }
}