import '../data/models/flight.dart';
import '../data/models/igc_file.dart';
import '../services/flight_track_loader.dart';
import '../services/database_service.dart';
import '../utils/preferences_helper.dart';
import '../services/logging_service.dart';

class TriangleRecalculationResult {
  final Flight updatedFlight;
  final List<IgcPoint>? trianglePoints;
  final bool recalculationPerformed;

  const TriangleRecalculationResult({
    required this.updatedFlight,
    this.trianglePoints,
    required this.recalculationPerformed,
  });
}

class TriangleRecalculationService {
  static final DatabaseService _databaseService = DatabaseService.instance;

  /// Check if triangle recalculation is needed and perform it if necessary
  /// Returns updated flight data and triangle points for display
  static Future<TriangleRecalculationResult> checkAndRecalculate(
    Flight flight, {
    String logContext = 'TriangleRecalculation',
  }) async {
    // Get current triangle calculation version
    final currentVersion = await PreferencesHelper.getTriangleCalcVersion();
    
    LoggingService.info('$logContext: Checking triangle recalculation for flight ${flight.id} - currentVersion: $currentVersion, flightVersion: ${flight.triangleCalcVersion}');
    
    // Check if recalculation is needed
    if (flight.needsTriangleRecalculation(currentVersion) && 
        flight.trackLogPath != null) {
      
      try {
        LoggingService.info('$logContext: Recalculating triangle for flight ${flight.id}');
        
        // Load trimmed flight track data (consistent with import)
        final igcFile = await FlightTrackLoader.loadFlightTrack(flight, logContext: logContext);
        
        // Get current preferences
        final triangleSamplingInterval = await PreferencesHelper.getTriangleSamplingInterval();
        final closingDistance = await PreferencesHelper.getTriangleClosingDistance();
        
        // Recalculate closing point with new closing distance preference
        // Note: Now calculated on trimmed data, same as import
        int? newClosingPointIndex = igcFile.getClosingPointIndex(maxDistanceMeters: closingDistance);
        double? actualClosingDistance;
        
        if (newClosingPointIndex != null) {
          final launchPoint = igcFile.trackPoints.first;
          final closingPoint = igcFile.trackPoints[newClosingPointIndex];
          actualClosingDistance = igcFile.calculateSimpleDistance(launchPoint, closingPoint);
        }
        
        // Calculate triangle on trimmed data if closing point exists
        Map<String, dynamic> faiTriangle;
        List<IgcPoint>? trianglePoints;
        
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
          } else {
            // Extract triangle points for display
            final rawTrianglePoints = faiTriangle['trianglePoints'] as List<dynamic>?;
            if (rawTrianglePoints != null && rawTrianglePoints.length == 3) {
              trianglePoints = rawTrianglePoints.cast<IgcPoint>();
            }
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
          triangleCalcVersion: currentVersion,
        );
        
        // Save to database
        await _databaseService.updateFlight(updatedFlight);
        
        LoggingService.info('$logContext: Triangle recalculated: ${faiTriangle['triangleDistance']} km, Closed: ${newClosingPointIndex != null}');
        
        return TriangleRecalculationResult(
          updatedFlight: updatedFlight,
          trianglePoints: trianglePoints,
          recalculationPerformed: true,
        );
        
      } catch (e) {
        LoggingService.error('$logContext: Error recalculating triangle', e);
        rethrow;
      }
    } else {
      // No recalculation needed, but might need to extract triangle points for display
      List<IgcPoint>? trianglePoints;
      
      // Try to use pre-calculated triangle points from database
      final storedTrianglePoints = flight.getParsedTrianglePoints();
      if (storedTrianglePoints != null && storedTrianglePoints.length == 3) {
        LoggingService.debug('$logContext: Using stored triangle points (fast)');
        // Convert stored coordinate maps to IgcPoint objects
        trianglePoints = storedTrianglePoints.map((point) => IgcPoint(
          latitude: point['lat']!,
          longitude: point['lng']!,
          gpsAltitude: point['alt']!.toInt(),
          pressureAltitude: 0,
          timestamp: DateTime.now(), // Timestamp not needed for triangle display
          isValid: true, // Stored points are assumed valid
        )).toList();
      } else if (flight.isClosed && flight.trackLogPath != null) {
        // Fallback: calculate from IGC file if no stored points (should be rare)
        LoggingService.debug('$logContext: No stored triangle points, calculating from IGC file (slow)');
        try {
          final igcFile = await FlightTrackLoader.loadFlightTrack(flight, logContext: logContext);
          final triangleSamplingInterval = await PreferencesHelper.getTriangleSamplingInterval();
          final closingDistance = await PreferencesHelper.getTriangleClosingDistance();
          final faiTriangle = igcFile.calculateFaiTriangle(
            samplingIntervalSeconds: triangleSamplingInterval, 
            closingDistanceMeters: closingDistance
          );
          final rawTrianglePoints = faiTriangle['trianglePoints'] as List<dynamic>?;
          
          if (rawTrianglePoints != null && rawTrianglePoints.length == 3) {
            trianglePoints = rawTrianglePoints.cast<IgcPoint>();
          }
        } catch (e) {
          LoggingService.error('$logContext: Failed to calculate triangle from IGC', e);
        }
      }
      
      return TriangleRecalculationResult(
        updatedFlight: flight,
        trianglePoints: trianglePoints,
        recalculationPerformed: false,
      );
    }
  }
}