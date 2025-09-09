import 'dart:async';
import '../data/models/flight.dart';
import '../data/models/igc_file.dart';
import '../services/flight_track_loader.dart';
import '../services/database_service.dart';
import '../utils/preferences_helper.dart';
import '../services/logging_service.dart';

/// Result of a single flight recalculation
class FlightRecalculationResult {
  final int flightId;
  final bool success;
  final String? error;
  final double? oldTriangleDistance;
  final double? newTriangleDistance;
  final bool wasClosedBefore;
  final bool isClosedNow;

  const FlightRecalculationResult({
    required this.flightId,
    required this.success,
    this.error,
    this.oldTriangleDistance,
    this.newTriangleDistance,
    required this.wasClosedBefore,
    required this.isClosedNow,
  });
}

/// Result of the batch recalculation process
class BatchRecalculationResult {
  final int totalFlights;
  final int processedFlights;
  final int successfulFlights;
  final int failedFlights;
  final int changedFlights;
  final List<FlightRecalculationResult> details;

  const BatchRecalculationResult({
    required this.totalFlights,
    required this.processedFlights,
    required this.successfulFlights,
    required this.failedFlights,
    required this.changedFlights,
    required this.details,
  });
}

/// Progress callback for UI updates
/// Parameters: currentIndex, totalFlights, currentFlightDescription
typedef ProgressCallback = void Function(int current, int total, String description);

/// Service to handle batch recalculation of all flight triangles
/// when triangle calculation preferences change
class BatchTriangleRecalculationService {
  static final DatabaseService _databaseService = DatabaseService.instance;
  
  /// Cancellation token to allow stopping the process
  static bool _isCancelled = false;
  
  /// Cancel the current batch recalculation
  static void cancel() {
    _isCancelled = true;
  }
  
  /// Recalculate triangles for all flights with track logs
  static Future<BatchRecalculationResult> recalculateAllFlights({
    ProgressCallback? onProgress,
    String logContext = 'BatchTriangleRecalculation',
  }) async {
    _isCancelled = false;
    
    LoggingService.info('$logContext: Starting batch triangle recalculation');
    
    // Get all flights with track logs
    final allFlights = await _databaseService.getAllFlights();
    final flightsWithTracks = allFlights.where((f) => f.trackLogPath != null).toList();
    
    LoggingService.info('$logContext: Found ${flightsWithTracks.length} flights with track logs');
    
    // Get current preferences
    final triangleSamplingInterval = await PreferencesHelper.getTriangleSamplingInterval();
    final closingDistance = await PreferencesHelper.getTriangleClosingDistance();
    
    LoggingService.info('$logContext: Using preferences - sampling: ${triangleSamplingInterval}s, closing: ${closingDistance}m');
    
    final results = <FlightRecalculationResult>[];
    int successCount = 0;
    int failCount = 0;
    int changeCount = 0;
    
    for (int i = 0; i < flightsWithTracks.length; i++) {
      if (_isCancelled) {
        LoggingService.info('$logContext: Batch recalculation cancelled by user');
        break;
      }
      
      final flight = flightsWithTracks[i];
      
      // Report progress
      onProgress?.call(
        i + 1,
        flightsWithTracks.length,
        'Processing flight ${flight.id} from ${flight.date}',
      );
      
      // Process this flight
      final result = await _recalculateSingleFlight(
        flight,
        triangleSamplingInterval: triangleSamplingInterval,
        closingDistance: closingDistance,
        logContext: logContext,
      );
      
      results.add(result);
      
      if (result.success) {
        successCount++;
        if (result.wasClosedBefore != result.isClosedNow ||
            result.oldTriangleDistance != result.newTriangleDistance) {
          changeCount++;
        }
      } else {
        failCount++;
      }
      
      // Small delay to prevent UI freezing
      await Future.delayed(const Duration(milliseconds: 10));
    }
    
    final processedCount = _isCancelled ? results.length : flightsWithTracks.length;
    
    LoggingService.info('$logContext: Batch recalculation complete. '
        'Processed: $processedCount, Success: $successCount, Failed: $failCount, Changed: $changeCount');
    
    return BatchRecalculationResult(
      totalFlights: flightsWithTracks.length,
      processedFlights: processedCount,
      successfulFlights: successCount,
      failedFlights: failCount,
      changedFlights: changeCount,
      details: results,
    );
  }
  
  /// Recalculate triangle for a single flight
  static Future<FlightRecalculationResult> _recalculateSingleFlight(
    Flight flight, {
    required int triangleSamplingInterval,
    required double closingDistance,
    required String logContext,
  }) async {
    try {
      // Store original values for comparison
      final wasClosedBefore = flight.isClosed;
      final oldTriangleDistance = flight.faiTriangleDistance;
      
      // Load trimmed flight track data
      final igcFile = await FlightTrackLoader.loadFlightTrack(
        flight,
        logContext: '$logContext:Flight${flight.id}',
      );
      
      // Recalculate closing point with new closing distance preference
      int? newClosingPointIndex = igcFile.getClosingPointIndex(maxDistanceMeters: closingDistance);
      double? actualClosingDistance;
      
      if (newClosingPointIndex != null) {
        final launchPoint = igcFile.trackPoints.first;
        final closingPoint = igcFile.trackPoints[newClosingPointIndex];
        actualClosingDistance = igcFile.calculateSimpleDistance(launchPoint, closingPoint);
      }
      
      // Calculate triangle on trimmed data if closing point exists
      Map<String, dynamic> faiTriangle;
      
      if (newClosingPointIndex != null) {
        final trimmedIgcFile = igcFile.copyWithTrimmedPoints(0, newClosingPointIndex);
        faiTriangle = trimmedIgcFile.calculateFaiTriangle(
          samplingIntervalSeconds: triangleSamplingInterval,
          closingDistanceMeters: closingDistance,
        );
        
        // Check if triangle validation failed
        if (faiTriangle['trianglePoints'] != null && 
            (faiTriangle['trianglePoints'] as List).isEmpty) {
          // Triangle invalid - mark flight as open
          newClosingPointIndex = null;
          actualClosingDistance = null;
          faiTriangle = {'trianglePoints': null, 'triangleDistance': 0.0};
        }
      } else {
        faiTriangle = {'trianglePoints': null, 'triangleDistance': 0.0};
      }
      
      // Convert triangle points to JSON for storage
      String? faiTrianglePointsJson;
      if (faiTriangle['trianglePoints'] != null && 
          (faiTriangle['trianglePoints'] as List).isNotEmpty) {
        final trianglePointsList = faiTriangle['trianglePoints'] as List<dynamic>;
        faiTrianglePointsJson = Flight.encodeTrianglePointsToJson(trianglePointsList);
      }
      
      // Create updated flight with new closing point and triangle data
      final updatedFlight = flight.copyWith(
        closingPointIndex: newClosingPointIndex,
        closingDistance: actualClosingDistance,
        faiTriangleDistance: faiTriangle['triangleDistance'],
        faiTrianglePoints: faiTrianglePointsJson,
      );
      
      // Save to database
      await _databaseService.updateFlight(updatedFlight);
      
      final isClosedNow = newClosingPointIndex != null;
      
      LoggingService.debug('$logContext: Flight ${flight.id} - '
          'Was closed: $wasClosedBefore, Is closed: $isClosedNow, '
          'Old triangle: ${oldTriangleDistance?.toStringAsFixed(1) ?? "N/A"}km, '
          'New triangle: ${faiTriangle['triangleDistance']?.toStringAsFixed(1) ?? "N/A"}km');
      
      return FlightRecalculationResult(
        flightId: flight.id!,
        success: true,
        oldTriangleDistance: oldTriangleDistance,
        newTriangleDistance: faiTriangle['triangleDistance'],
        wasClosedBefore: wasClosedBefore,
        isClosedNow: isClosedNow,
      );
      
    } catch (e) {
      LoggingService.error('$logContext: Error recalculating flight ${flight.id}', e);
      
      return FlightRecalculationResult(
        flightId: flight.id!,
        success: false,
        error: e.toString(),
        wasClosedBefore: flight.isClosed,
        isClosedNow: flight.isClosed,
      );
    }
  }
}