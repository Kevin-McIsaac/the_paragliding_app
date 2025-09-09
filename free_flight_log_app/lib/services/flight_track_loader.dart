import '../data/models/flight.dart';
import '../data/models/igc_file.dart';
import '../services/igc_parser.dart';
import '../services/database_service.dart';
import '../services/takeoff_landing_detector.dart';
import '../utils/preferences_helper.dart';
import '../services/logging_service.dart';

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
  
  // Simple memory cache for parsed IGC files
  static final Map<String, IgcFile> _igcCache = {};
  static const int _maxCacheSize = 10; // Limit cache to 10 files to prevent memory issues
  
  /// Load flight track data in consistent trimmed format
  /// 
  /// Always returns track data from takeoff to landing (trimmed).
  /// If detection data is missing, runs detection and caches results.
  /// Falls back to full track only if detection completely fails.
  static Future<IgcFile> loadFlightTrack(Flight flight, {
    String logContext = 'FlightTrackLoader',
  }) async {
    if (flight.trackLogPath == null) {
      throw Exception('Flight has no track log path');
    }
    
    // Check cache first
    final cacheKey = flight.trackLogPath!;
    IgcFile? fullIgcFile = _igcCache[cacheKey];
    
    if (fullIgcFile == null) {
      LoggingService.info('$logContext: Parsing IGC file from disk for flight ${flight.id}');
      
      // Parse full IGC file
      fullIgcFile = await _parser.parseFile(flight.trackLogPath!);
      
      // Add to cache with size limit
      if (_igcCache.length >= _maxCacheSize) {
        // Remove oldest entry (first in map)
        final oldestKey = _igcCache.keys.first;
        _igcCache.remove(oldestKey);
        LoggingService.debug('$logContext: Cache full, removed oldest entry: $oldestKey');
      }
      _igcCache[cacheKey] = fullIgcFile;
      LoggingService.info('$logContext: Cached IGC file, cache size: ${_igcCache.length}');
    } else {
      LoggingService.debug('$logContext: Using cached IGC file for flight ${flight.id}');
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
      final trimmedFile = fullIgcFile.copyWithTrimmedPoints(
        flight.takeoffIndex!,
        flight.landingIndex!
      );
      
      LoggingService.info('$logContext: Loaded ${trimmedFile.trackPoints.length}/${fullIgcFile.trackPoints.length} track points (trimmed: true)');
      return trimmedFile;
    }
    
    // Missing detection data - run detection if this is an IGC flight
    if (flight.source == 'igc') {
      LoggingService.info('$logContext: No detection data found, running detection for flight ${flight.id}');
      
      try {
        final detectionResult = await _runDetectionAndCache(flight, fullIgcFile, logContext);
        
        if (detectionResult.isComplete) {
          final trimmedFile = fullIgcFile.copyWithTrimmedPoints(
            detectionResult.takeoffIndex!,
            detectionResult.landingIndex!
          );
          
          LoggingService.info('$logContext: Loaded ${trimmedFile.trackPoints.length}/${fullIgcFile.trackPoints.length} track points (trimmed: true)');
          return trimmedFile;
        }
      } catch (e) {
        LoggingService.warning('$logContext: Detection failed for flight ${flight.id}: $e - falling back to full track');
      }
    }
    
    // Fallback to full track (should be rare)
    LoggingService.warning('$logContext: Using full track for flight ${flight.id} - no detection data available');
    LoggingService.info('$logContext: Loaded ${fullIgcFile.trackPoints.length}/${fullIgcFile.trackPoints.length} track points (trimmed: false)');
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
      // Use cached version if available
      final cacheKey = flight.trackLogPath!;
      IgcFile? fullIgcFile = _igcCache[cacheKey];
      
      if (fullIgcFile == null) {
        fullIgcFile = await _parser.parseFile(flight.trackLogPath!);
      }
      
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
    };
  }
}

