import '../data/models/igc_file.dart';
import 'logging_service.dart';

/// Service for detecting takeoff and landing points in flight tracks
/// Based on configurable ground speed and climb rate thresholds
class TakeoffLandingDetector {
  /// Default detection thresholds
  static const double defaultSpeedThresholdKmh = 9.0;
  static const double defaultClimbRateThresholdMs = 0.2;
  
  /// Detect takeoff and landing points in an IGC file
  /// 
  /// Takeoff: First point (scanning forward) where 5s ground speed > threshold AND 
  ///          absolute 5s climb rate > threshold
  /// Landing: Last point (scanning backward) meeting the same criteria
  static DetectionResult detectTakeoffLanding(
    IgcFile igcData, {
    double speedThresholdKmh = defaultSpeedThresholdKmh,
    double climbRateThresholdMs = defaultClimbRateThresholdMs,
  }) {
    final trackPoints = igcData.trackPoints;
    
    if (trackPoints.length < 10) {
      LoggingService.warning('TakeoffLandingDetector: Insufficient track points (${trackPoints.length}) for detection');
      return DetectionResult(
        takeoffIndex: null,
        landingIndex: null,
        takeoffTime: null,
        landingTime: null,
        message: 'Insufficient track points for detection',
      );
    }
    
    LoggingService.info('TakeoffLandingDetector: Starting detection with speed=${speedThresholdKmh}km/h, climb=${climbRateThresholdMs}m/s');
    
    // Detect takeoff (scan forward from start)
    int? takeoffIndex;
    for (int i = 1; i < trackPoints.length; i++) {
      final point = trackPoints[i];
      
      if (_meetsCriteria(point, speedThresholdKmh, climbRateThresholdMs)) {
        takeoffIndex = i;
        LoggingService.debug('TakeoffLandingDetector: Takeoff detected at index $i (${point.timestamp})');
        break;
      }
    }
    
    // Detect landing (scan backward from end)
    int? landingIndex;
    for (int i = trackPoints.length - 2; i >= 0; i--) {
      final point = trackPoints[i];
      
      if (_meetsCriteria(point, speedThresholdKmh, climbRateThresholdMs)) {
        landingIndex = i;
        LoggingService.debug('TakeoffLandingDetector: Landing detected at index $i (${point.timestamp})');
        break;
      }
    }
    
    // Validation: takeoff must come before landing
    if (takeoffIndex != null && landingIndex != null && takeoffIndex >= landingIndex) {
      LoggingService.warning('TakeoffLandingDetector: Invalid detection - takeoff ($takeoffIndex) >= landing ($landingIndex)');
      return DetectionResult(
        takeoffIndex: null,
        landingIndex: null,
        takeoffTime: null,
        landingTime: null,
        message: 'Invalid detection: takeoff point after landing point',
      );
    }
    
    final takeoffTime = takeoffIndex != null ? trackPoints[takeoffIndex].timestamp : null;
    final landingTime = landingIndex != null ? trackPoints[landingIndex].timestamp : null;
    
    // Log results
    if (takeoffIndex != null && landingIndex != null) {
      final originalDuration = trackPoints.last.timestamp.difference(trackPoints.first.timestamp).inMinutes;
      final detectedDuration = landingTime!.difference(takeoffTime!).inMinutes;
      LoggingService.info('TakeoffLandingDetector: Detection successful - trimmed ${originalDuration - detectedDuration} minutes');
    } else if (takeoffIndex == null && landingIndex == null) {
      LoggingService.warning('TakeoffLandingDetector: No takeoff or landing detected');
    } else {
      LoggingService.warning('TakeoffLandingDetector: Partial detection - takeoff=${takeoffIndex != null}, landing=${landingIndex != null}');
    }
    
    return DetectionResult(
      takeoffIndex: takeoffIndex,
      landingIndex: landingIndex,
      takeoffTime: takeoffTime,
      landingTime: landingTime,
      message: _buildResultMessage(takeoffIndex, landingIndex),
    );
  }
  
  /// Check if a track point meets the takeoff/landing criteria
  static bool _meetsCriteria(IgcPoint point, double speedThresholdKmh, double climbRateThresholdMs) {
    // Get 5-second average values
    final groundSpeed = point.groundSpeed; // Already calculated as 5s average in IgcPoint
    final climbRate5s = point.climbRate5s; // 5-second average climb rate
    
    // Check thresholds
    final speedOk = groundSpeed > speedThresholdKmh;
    final climbRateOk = climbRate5s.abs() > climbRateThresholdMs;
    
    return speedOk && climbRateOk;
  }
  
  /// Build a human-readable result message
  static String _buildResultMessage(int? takeoffIndex, int? landingIndex) {
    if (takeoffIndex != null && landingIndex != null) {
      return 'Takeoff and landing detected successfully';
    } else if (takeoffIndex != null) {
      return 'Takeoff detected, landing not found';
    } else if (landingIndex != null) {
      return 'Landing detected, takeoff not found';
    } else {
      return 'No takeoff or landing detected';
    }
  }
}

/// Result of takeoff/landing detection
class DetectionResult {
  /// Index of takeoff point in track points array (null if not detected)
  final int? takeoffIndex;
  
  /// Index of landing point in track points array (null if not detected)
  final int? landingIndex;
  
  /// Timestamp of detected takeoff (null if not detected)
  final DateTime? takeoffTime;
  
  /// Timestamp of detected landing (null if not detected)
  final DateTime? landingTime;
  
  /// Human-readable message about the detection result
  final String message;
  
  DetectionResult({
    required this.takeoffIndex,
    required this.landingIndex,
    required this.takeoffTime,
    required this.landingTime,
    required this.message,
  });
  
  /// Whether both takeoff and landing were successfully detected
  bool get isComplete => takeoffIndex != null && landingIndex != null;
  
  /// Whether any detection was made
  bool get hasDetection => takeoffIndex != null || landingIndex != null;
  
  /// Get the detected flight duration in minutes (null if incomplete detection)
  int? get detectedDurationMinutes {
    if (!isComplete) return null;
    return landingTime!.difference(takeoffTime!).inMinutes;
  }
  
  @override
  String toString() {
    return 'DetectionResult(takeoff: $takeoffIndex, landing: $landingIndex, message: $message)';
  }
}