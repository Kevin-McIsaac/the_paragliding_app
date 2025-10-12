import 'backup_diagnostic_service.dart';
import 'igc_cleanup_service.dart';
import 'logging_service.dart';

/// Cache manager for backup diagnostics results
/// Provides intelligent caching to avoid expensive file operations
class BackupDiagnosticsCache {
  // IGC Stats caching
  static IGCBackupStats? _cachedIGCStats;
  static DateTime? _igcStatsTime;

  // Cleanup Stats caching
  static IGCCleanupStats? _cachedCleanupStats;
  static DateTime? _cleanupStatsTime;

  // Backup Status caching
  static Map<String, dynamic>? _cachedBackupStatus;
  static DateTime? _backupStatusTime;

  // Cache validity periods
  static const Duration _igcStatsCacheValidity = Duration(minutes: 10);
  static const Duration _cleanupStatsCacheValidity = Duration(minutes: 5);
  static const Duration _backupStatusCacheValidity = Duration(hours: 1);

  /// Get cached IGC backup stats if valid
  static IGCBackupStats? getCachedIGCStats() {
    if (_isIGCStatsCacheValid()) {
      _cacheHits['igc_stats'] = (_cacheHits['igc_stats'] ?? 0) + 1;
      final age = _igcStatsTime != null ? DateTime.now().difference(_igcStatsTime!) : null;
      LoggingService.structured('BACKUP_CACHE_HIT', {
        'type': 'igc_stats',
        'age_seconds': age?.inSeconds,
        'file_count': _cachedIGCStats?.fileCount,
      });
      return _cachedIGCStats;
    }
    _cacheMisses['igc_stats'] = (_cacheMisses['igc_stats'] ?? 0) + 1;
    final reason = _cachedIGCStats == null ? 'no_data' :
                   _igcStatsTime == null ? 'no_timestamp' : 'expired';
    final age = _igcStatsTime != null ? DateTime.now().difference(_igcStatsTime!) : null;
    LoggingService.structured('BACKUP_CACHE_MISS', {
      'type': 'igc_stats',
      'reason': reason,
      'age_seconds': age?.inSeconds,
      'validity_seconds': _igcStatsCacheValidity.inSeconds,
    });
    return null;
  }

  /// Cache IGC backup stats
  static void cacheIGCStats(IGCBackupStats? stats) {
    _cachedIGCStats = stats;
    _igcStatsTime = DateTime.now();

    LoggingService.structured('BACKUP_CACHE_IGC_STORED', {
      'file_count': stats?.fileCount ?? 0,
      'cache_valid_until': _igcStatsTime?.add(_igcStatsCacheValidity).toIso8601String(),
    });
  }

  /// Get cached cleanup stats if valid
  static IGCCleanupStats? getCachedCleanupStats() {
    if (_isCleanupStatsCacheValid()) {
      _cacheHits['cleanup_stats'] = (_cacheHits['cleanup_stats'] ?? 0) + 1;
      final age = _cleanupStatsTime != null ? DateTime.now().difference(_cleanupStatsTime!) : null;
      LoggingService.structured('BACKUP_CACHE_HIT', {
        'type': 'cleanup_stats',
        'age_seconds': age?.inSeconds,
        'total_files': _cachedCleanupStats?.totalIgcFiles,
        'orphaned_files': _cachedCleanupStats?.orphanedFiles,
      });
      return _cachedCleanupStats;
    }
    _cacheMisses['cleanup_stats'] = (_cacheMisses['cleanup_stats'] ?? 0) + 1;
    final reason = _cachedCleanupStats == null ? 'no_data' :
                   _cleanupStatsTime == null ? 'no_timestamp' : 'expired';
    final age = _cleanupStatsTime != null ? DateTime.now().difference(_cleanupStatsTime!) : null;
    LoggingService.structured('BACKUP_CACHE_MISS', {
      'type': 'cleanup_stats',
      'reason': reason,
      'age_seconds': age?.inSeconds,
      'validity_seconds': _cleanupStatsCacheValidity.inSeconds,
    });
    return null;
  }

  /// Cache cleanup stats
  static void cacheCleanupStats(IGCCleanupStats? stats) {
    _cachedCleanupStats = stats;
    _cleanupStatsTime = DateTime.now();

    LoggingService.structured('BACKUP_CACHE_CLEANUP_STORED', {
      'total_files': stats?.totalIgcFiles ?? 0,
      'orphaned_files': stats?.orphanedFiles ?? 0,
      'cache_valid_until': _cleanupStatsTime?.add(_cleanupStatsCacheValidity).toIso8601String(),
    });
  }

  /// Get cached backup status if valid
  static Map<String, dynamic>? getCachedBackupStatus() {
    if (_isBackupStatusCacheValid()) {
      _cacheHits['backup_status'] = (_cacheHits['backup_status'] ?? 0) + 1;
      final age = _backupStatusTime != null ? DateTime.now().difference(_backupStatusTime!) : null;
      LoggingService.structured('BACKUP_CACHE_HIT', {
        'type': 'backup_status',
        'age_seconds': age?.inSeconds,
        'backup_enabled': _cachedBackupStatus?['backupEnabled'],
      });
      return _cachedBackupStatus;
    }
    _cacheMisses['backup_status'] = (_cacheMisses['backup_status'] ?? 0) + 1;
    final reason = _cachedBackupStatus == null ? 'no_data' :
                   _backupStatusTime == null ? 'no_timestamp' : 'expired';
    final age = _backupStatusTime != null ? DateTime.now().difference(_backupStatusTime!) : null;
    LoggingService.structured('BACKUP_CACHE_MISS', {
      'type': 'backup_status',
      'reason': reason,
      'age_seconds': age?.inSeconds,
      'validity_seconds': _backupStatusCacheValidity.inSeconds,
    });
    return null;
  }

  /// Cache backup status
  static void cacheBackupStatus(Map<String, dynamic>? status) {
    _cachedBackupStatus = status;
    _backupStatusTime = DateTime.now();

    LoggingService.structured('BACKUP_CACHE_STATUS_STORED', {
      'backup_enabled': status?['backupEnabled'] ?? false,
      'cache_valid_until': _backupStatusTime?.add(_backupStatusCacheValidity).toIso8601String(),
    });
  }

  /// Check if IGC stats cache is valid
  static bool _isIGCStatsCacheValid() {
    return _cachedIGCStats != null &&
           _igcStatsTime != null &&
           DateTime.now().difference(_igcStatsTime!) < _igcStatsCacheValidity;
  }

  /// Check if cleanup stats cache is valid
  static bool _isCleanupStatsCacheValid() {
    return _cachedCleanupStats != null &&
           _cleanupStatsTime != null &&
           DateTime.now().difference(_cleanupStatsTime!) < _cleanupStatsCacheValidity;
  }

  /// Check if backup status cache is valid
  static bool _isBackupStatusCacheValid() {
    return _cachedBackupStatus != null &&
           _backupStatusTime != null &&
           DateTime.now().difference(_backupStatusTime!) < _backupStatusCacheValidity;
  }

  /// Clear all cached data (useful after data modifications)
  static void clearAll() {
    _cachedIGCStats = null;
    _igcStatsTime = null;
    _cachedCleanupStats = null;
    _cleanupStatsTime = null;
    _cachedBackupStatus = null;
    _backupStatusTime = null;

    LoggingService.debug('BackupDiagnosticsCache: All caches cleared');
  }

  /// Clear only IGC-related caches (after file operations)
  static void clearIGCCaches() {
    _cachedIGCStats = null;
    _igcStatsTime = null;
    _cachedCleanupStats = null;
    _cleanupStatsTime = null;

    LoggingService.debug('BackupDiagnosticsCache: IGC caches cleared');
  }

  /// Get comprehensive cache status for debugging
  static Map<String, dynamic> getCacheStatus() {
    return {
      'igc_stats': {
        'cached': _cachedIGCStats != null,
        'valid': _isIGCStatsCacheValid(),
        'age_seconds': _igcStatsTime != null
            ? DateTime.now().difference(_igcStatsTime!).inSeconds
            : null,
        'expires_in_seconds': _igcStatsTime != null && _isIGCStatsCacheValid()
            ? _igcStatsCacheValidity.inSeconds - DateTime.now().difference(_igcStatsTime!).inSeconds
            : null,
        'file_count': _cachedIGCStats?.fileCount,
      },
      'cleanup_stats': {
        'cached': _cachedCleanupStats != null,
        'valid': _isCleanupStatsCacheValid(),
        'age_seconds': _cleanupStatsTime != null
            ? DateTime.now().difference(_cleanupStatsTime!).inSeconds
            : null,
        'expires_in_seconds': _cleanupStatsTime != null && _isCleanupStatsCacheValid()
            ? _cleanupStatsCacheValidity.inSeconds - DateTime.now().difference(_cleanupStatsTime!).inSeconds
            : null,
        'total_files': _cachedCleanupStats?.totalIgcFiles,
        'orphaned_files': _cachedCleanupStats?.orphanedFiles,
      },
      'backup_status': {
        'cached': _cachedBackupStatus != null,
        'valid': _isBackupStatusCacheValid(),
        'age_seconds': _backupStatusTime != null
            ? DateTime.now().difference(_backupStatusTime!).inSeconds
            : null,
        'expires_in_seconds': _backupStatusTime != null && _isBackupStatusCacheValid()
            ? _backupStatusCacheValidity.inSeconds - DateTime.now().difference(_backupStatusTime!).inSeconds
            : null,
        'backup_enabled': _cachedBackupStatus?['backupEnabled'],
      },
    };
  }

  /// Check if any cache data is available (for immediate display)
  static bool hasAnyCachedData() {
    return _cachedIGCStats != null ||
           _cachedCleanupStats != null ||
           _cachedBackupStatus != null;
  }

  /// Get cache hit rate for performance monitoring
  static final Map<String, int> _cacheHits = {'igc_stats': 0, 'cleanup_stats': 0, 'backup_status': 0};
  static final Map<String, int> _cacheMisses = {'igc_stats': 0, 'cleanup_stats': 0, 'backup_status': 0};

  /// Get cache performance statistics
  static Map<String, dynamic> getCachePerformance() {
    final Map<String, double> hitRates = {};

    for (final type in _cacheHits.keys) {
      final hits = _cacheHits[type] ?? 0;
      final misses = _cacheMisses[type] ?? 0;
      final total = hits + misses;
      hitRates[type] = total > 0 ? (hits / total * 100) : 0.0;
    }

    return {
      'cache_hits': Map.from(_cacheHits),
      'cache_misses': Map.from(_cacheMisses),
      'hit_rates_percent': hitRates,
    };
  }
}