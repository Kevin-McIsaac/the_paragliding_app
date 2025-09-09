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
  
  /// Load flight track data in consistent trimmed format
  /// 
  /// Always returns track data from takeoff to landing (trimmed).
  /// If detection data is missing, runs detection and caches results.
  /// Falls back to full track only if detection completely fails.
  static Future<IgcFile> loadFlightTrack(Flight flight, {
    String logContext = 'FlightTrackLoader',
  }) async {
    LoggingService.debug('$logContext: Loading track for flight ${flight.id}');
    
    if (flight.trackLogPath == null) {
      throw Exception('Flight has no track log path');
    }
    
    // Parse full IGC file first
    final fullIgcFile = await _parser.parseFile(flight.trackLogPath!);
    
    if (fullIgcFile.trackPoints.isEmpty) {
      throw Exception('No track points found in IGC file');
    }
    
    // Check if we have detection data
    if (flight.hasDetectionData) {
      // Use existing detection data to trim
      LoggingService.debug('$logContext: Using existing detection data (takeoff: ${flight.takeoffIndex}, landing: ${flight.landingIndex})');
      
      final trimmedFile = fullIgcFile.copyWithTrimmedPoints(
        flight.takeoffIndex!,
        flight.landingIndex!
      );
      
      LoggingService.info('$logContext: Loaded ${trimmedFile.trackPoints.length}/${fullIgcFile.trackPoints.length} track points (trimmed: ${flight.hasDetectionData})');
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
          
          LoggingService.info('$logContext: Loaded ${trimmedFile.trackPoints.length}/${fullIgcFile.trackPoints.length} track points (trimmed after detection)');
          return trimmedFile;
        }
      } catch (e) {
        LoggingService.error('$logContext: Detection failed for flight ${flight.id}', e);
      }
    }
    
    // Fallback to full track (should be rare)
    LoggingService.warning('$logContext: Using full track for flight ${flight.id} - no detection data available');
    LoggingService.info('$logContext: Loaded ${fullIgcFile.trackPoints.length} track points (full track fallback)');
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
    
    LoggingService.debug('$logContext: Running detection with speed=${speedThreshold}km/h, climbRate=${climbRateThreshold}m/s');
    
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
        LoggingService.debug('$logContext: Cached detection results in database');
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
      final fullIgcFile = await _parser.parseFile(flight.trackLogPath!);
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
}

