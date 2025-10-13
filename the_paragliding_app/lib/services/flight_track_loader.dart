import 'dart:io';
import '../data/models/flight.dart';
import '../data/models/igc_file.dart';
import '../services/igc_parser.dart';
import '../services/database_service.dart';
import '../services/takeoff_landing_detector.dart';
import '../utils/preferences_helper.dart';
import '../services/logging_service.dart';

// Cache entry with file metadata for validation
class _CacheEntry {
  final IgcFile file;
  final DateTime fileModified;
  final int fileSize;
  
  _CacheEntry({
    required this.file,
    required this.fileModified,
    required this.fileSize,
  });
}

/// Centralized service for loading flight track data in a consistent format.
/// 
/// This service ensures ALL flight operations work with the same trimmed representation:
/// - IGC files are stored untrimmed (archival)
/// - All calculations use trimmed data (takeoff to landing)
/// - Eliminates index confusion between full track and flight track
/// 
/// Key principle: The stored IGC is archival; the working data is the flight
class FlightTrackLoader {
  static final DatabaseService _databaseService = DatabaseService.instance;
  static final IgcParser _parser = IgcParser();
  
  // LRU cache with proper access tracking
  static final Map<String, _CacheEntry> _igcCache = {};
  static final List<String> _accessOrder = []; // Track access order for LRU
  static const int _maxCacheSize = 10; // Limit cache to 10 files to prevent memory issues
  
  /// Load flight track data in consistent trimmed format
  /// 
  /// **Single Source of Truth for Flight Data**
  /// 
  /// This method ensures ALL app code works with trimmed data (takeoff to landing).
  /// Returns an [IgcFile] with track points trimmed to the actual flight period.
  /// 
  /// **Data Flow:**
  /// 1. Load full IGC file from disk (with caching)
  /// 2. Apply trimming using stored detection indices 
  /// 3. Return zero-based trimmed track points
  /// 
  /// **Index Coordinates:**
  /// - Input: [flight] contains indices relative to full IGC file
  /// - Output: [IgcFile] with zero-based trimmed track points
  /// 
  /// **Fallback Behavior:**
  /// - If detection data missing: runs detection and caches results
  /// - If detection fails: returns full track (logged as warning)
  /// 
  /// **Performance:**
  /// - LRU cache prevents repeated file parsing
  /// - File modification detection invalidates stale cache entries
  /// 
  /// [flight] Flight record containing track log path and detection indices
  /// [logContext] Context string for logging (defaults to 'FlightTrackLoader')
  /// 
  /// Returns trimmed [IgcFile] with zero-based track points
  /// Throws [Exception] if flight has no track log path or file cannot be parsed
  static Future<IgcFile> loadFlightTrack(Flight flight, {
    String logContext = 'FlightTrackLoader',
  }) async {
    // Validate input
    if (flight.trackLogPath == null || flight.trackLogPath!.isEmpty) {
      throw ArgumentError('Flight has no track log path');
    }
    
    if (flight.id == null) {
      throw ArgumentError('Flight must have an ID for logging context');
    }
    
    final cacheKey = flight.trackLogPath!;
    final file = File(cacheKey);
    
    // Get current file stats for validation
    final fileStat = await file.stat();
    final fileModified = fileStat.modified;
    final fileSize = fileStat.size;
    
    // Check cache and validate
    final cachedEntry = _igcCache[cacheKey];
    IgcFile? fullIgcFile;
    
    if (cachedEntry != null && 
        cachedEntry.fileModified == fileModified && 
        cachedEntry.fileSize == fileSize) {
      // Cache hit with valid file
      fullIgcFile = cachedEntry.file;

      // Update LRU access order
      _accessOrder.remove(cacheKey);
      _accessOrder.add(cacheKey); // Move to end (most recent)

      LoggingService.debug('$logContext: Using cached IGC file for flight ${flight.id}');
      LoggingService.cache('IGC_FILE_CACHE', true,
        key: cacheKey,
        sizeBytes: fileSize);
    } else {
      // Cache miss or stale entry
      if (cachedEntry != null) {
        LoggingService.info('$logContext: File modified, invalidating cache for flight ${flight.id}');
        _igcCache.remove(cacheKey);
        _accessOrder.remove(cacheKey);
      } else {
        LoggingService.info('$logContext: Parsing IGC file from disk for flight ${flight.id}');
        LoggingService.cache('IGC_FILE_CACHE', false,
          key: cacheKey,
          sizeBytes: fileSize);
      }

      // Parse full IGC file
      final parseStart = DateTime.now();
      fullIgcFile = await _parser.parseFile(flight.trackLogPath!);
      final parseDuration = DateTime.now().difference(parseStart);

      LoggingService.performance('IGC_FILE_PARSE', parseDuration,
        'points: ${fullIgcFile.trackPoints.length}, size: ${fileSize ~/ 1024}KB');

      // Evict LRU entry if cache is full
      if (_igcCache.length >= _maxCacheSize && _accessOrder.isNotEmpty) {
        final lruKey = _accessOrder.removeAt(0); // Remove least recently used
        _igcCache.remove(lruKey);
        LoggingService.debug('$logContext: Cache full, evicted LRU entry: $lruKey');
      }
      
      // Add to cache
      _igcCache[cacheKey] = _CacheEntry(
        file: fullIgcFile,
        fileModified: fileModified,
        fileSize: fileSize,
      );
      _accessOrder.add(cacheKey);
      
      LoggingService.info('$logContext: Cached IGC file, cache size: ${_igcCache.length}');
    }
    
    if (fullIgcFile.trackPoints.isEmpty) {
      throw Exception('No track points found in IGC file');
    }
    
    // Log warning for large files that may impact performance
    if (fullIgcFile.trackPoints.length > 10000) {
      LoggingService.warning('$logContext: Large track file detected - ${fullIgcFile.trackPoints.length} points, may impact performance');
    }
    
    // Check if we have detection data
    if (flight.hasDetectionData) {
      // Validate detection indices before trimming
      final takeoffIndex = flight.takeoffIndex!;
      final landingIndex = flight.landingIndex!;
      final totalPoints = fullIgcFile.trackPoints.length;
      
      if (takeoffIndex < 0 || landingIndex >= totalPoints || takeoffIndex > landingIndex) {
        LoggingService.error('$logContext: Invalid detection indices for flight ${flight.id} - takeoff:$takeoffIndex, landing:$landingIndex, total:$totalPoints');
        throw ArgumentError('Invalid detection indices: takeoff=$takeoffIndex, landing=$landingIndex, total=$totalPoints');
      }
      
      final trimmedFile = fullIgcFile.copyWithTrimmedPoints(takeoffIndex, landingIndex);
      
      LoggingService.structured('TRACK_LOAD', {
        'flight_id': flight.id,
        'trimmed_points': trimmedFile.trackPoints.length,
        'total_points': totalPoints,
        'takeoff_idx': takeoffIndex,
        'landing_idx': landingIndex,
        'source': 'detection_data',
      });
      
      return trimmedFile;
    }
    
    // Missing detection data - run detection if this is an IGC flight
    if (flight.source == 'igc') {
      LoggingService.info('$logContext: No detection data found, running detection for flight ${flight.id}');
      
      try {
        final detectionResult = await _runDetectionAndCache(flight, fullIgcFile, logContext);
        
        if (detectionResult.isComplete) {
          // Validate fresh detection indices before trimming
          final takeoffIndex = detectionResult.takeoffIndex!;
          final landingIndex = detectionResult.landingIndex!;
          final totalPoints = fullIgcFile.trackPoints.length;
          
          if (takeoffIndex < 0 || landingIndex >= totalPoints || takeoffIndex > landingIndex) {
            LoggingService.error('$logContext: Invalid fresh detection indices for flight ${flight.id} - takeoff:$takeoffIndex, landing:$landingIndex, total:$totalPoints');
            throw ArgumentError('Invalid fresh detection indices: takeoff=$takeoffIndex, landing=$landingIndex, total=$totalPoints');
          }
          
          final trimmedFile = fullIgcFile.copyWithTrimmedPoints(takeoffIndex, landingIndex);
          
          LoggingService.structured('TRACK_LOAD', {
            'flight_id': flight.id,
            'trimmed_points': trimmedFile.trackPoints.length,
            'total_points': totalPoints,
            'takeoff_idx': takeoffIndex,
            'landing_idx': landingIndex,
            'source': 'fresh_detection',
          });
          
          return trimmedFile;
        }
      } catch (e) {
        LoggingService.warning('$logContext: Detection failed for flight ${flight.id}: $e - falling back to full track');
      }
    }
    
    // Fallback to full track (should be rare)
    LoggingService.warning('$logContext: Using full track for flight ${flight.id} - no detection data available');
    
    LoggingService.structured('TRACK_LOAD', {
      'flight_id': flight.id,
      'trimmed_points': fullIgcFile.trackPoints.length,
      'total_points': fullIgcFile.trackPoints.length,
      'takeoff_idx': null,
      'landing_idx': null,
      'source': 'fallback_full',
    });
    
    return fullIgcFile;
  }
  
  /// Run takeoff/landing detection and cache results in database
  static Future<DetectionResult> _runDetectionAndCache(
    Flight flight,
    IgcFile fullIgcFile,
    String logContext,
  ) async {
    // Get detection thresholds from preferences
    final speedThreshold = await PreferencesHelper.getDetectionSpeedThreshold();
    final climbRateThreshold = await PreferencesHelper.getDetectionClimbRateThreshold();
    
    // Perform detection
    final detectionResult = TakeoffLandingDetector.detectTakeoffLanding(
      fullIgcFile,
      speedThresholdKmh: speedThreshold,
      climbRateThresholdMs: climbRateThreshold,
    );
    
    LoggingService.info('$logContext: Detection result - ${detectionResult.message}');
    
    // Cache detection results in database if successful
    if (detectionResult.isComplete) {
      try {
        final updatedFlight = flight.copyWith(
          takeoffIndex: detectionResult.takeoffIndex,
          landingIndex: detectionResult.landingIndex,
          detectedTakeoffTime: detectionResult.takeoffTime,
          detectedLandingTime: detectionResult.landingTime,
        );
        
        await _databaseService.updateFlight(updatedFlight);
      } catch (e) {
        LoggingService.error('$logContext: Failed to cache detection results', e);
        // Don't throw - detection worked, just caching failed
      }
    }
    
    return detectionResult;
  }
  
  /// Check if a flight can provide trimmed data
  /// 
  /// Returns true if flight has detection data or can run detection
  static bool canProvideTrimmedData(Flight flight) {
    if (flight.hasDetectionData) {
      return true;
    }
    
    return flight.source == 'igc' && flight.trackLogPath != null;
  }
  
  /// Get track loading info for debugging
  static Future<String> getTrackLoadingInfo(Flight flight) async {
    if (flight.trackLogPath == null) {
      return 'No track log path';
    }
    
    try {
      // Use cached version if available and valid
      final cacheKey = flight.trackLogPath!;
      final cachedEntry = _igcCache[cacheKey];
      IgcFile? fullIgcFile;
      
      if (cachedEntry != null) {
        final file = File(cacheKey);
        final fileStat = await file.stat();
        if (cachedEntry.fileModified == fileStat.modified && 
            cachedEntry.fileSize == fileStat.size) {
          fullIgcFile = cachedEntry.file;
        }
      }
      
      fullIgcFile ??= await _parser.parseFile(flight.trackLogPath!);
      
      final totalPoints = fullIgcFile.trackPoints.length;
      
      if (flight.hasDetectionData) {
        final trimmedPoints = flight.landingIndex! - flight.takeoffIndex! + 1;
        final percentage = (trimmedPoints / totalPoints * 100).toStringAsFixed(1);
        return 'Trimmed: $trimmedPoints/$totalPoints points ($percentage% of track)';
      } else {
        return 'Full track: $totalPoints points (no detection data)';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }
  
  /// Clear the IGC file cache
  /// Call this when memory is low or app goes to background
  static void clearCache() {
    final cacheSize = _igcCache.length;
    _igcCache.clear();
    _accessOrder.clear();
    if (cacheSize > 0) {
      LoggingService.info('FlightTrackLoader: Cleared IGC cache, removed $cacheSize entries');
    }
  }
  
  /// Get current cache statistics
  static Map<String, dynamic> getCacheStats() {
    return {
      'entries': _igcCache.length,
      'maxSize': _maxCacheSize,
      'files': _igcCache.keys.toList(),
      'lruOrder': List<String>.from(_accessOrder),
    };
  }
  
  /// Invalidate a specific cache entry (e.g., when file is updated)
  static void invalidateCacheEntry(String filePath) {
    if (_igcCache.containsKey(filePath)) {
      _igcCache.remove(filePath);
      _accessOrder.remove(filePath);
      LoggingService.info('FlightTrackLoader: Invalidated cache entry for $filePath');
    }
  }
}

