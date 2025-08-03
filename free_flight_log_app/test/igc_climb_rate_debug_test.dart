import 'package:flutter_test/flutter_test.dart';
import '../lib/data/models/igc_file.dart';

void main() {
  group('IGC Climb Rate Debug Tests', () {
    test('Debug 15-second climb rate with realistic IGC data', () {
      // Create realistic IGC data with 1-second intervals
      final trackPoints = <IgcPoint>[];
      
      // Add 30 seconds of flight data with varying climb rates
      for (int i = 0; i < 30; i++) {
        int altitude;
        if (i < 5) {
          altitude = 1000 + (i * 10); // Climbing at 10 m/s
        } else if (i < 10) {
          altitude = 1050 - ((i - 5) * 5); // Sinking at 5 m/s
        } else if (i < 20) {
          altitude = 1025 + ((i - 10) * 8); // Climbing at 8 m/s
        } else {
          altitude = 1105 - ((i - 20) * 12); // Fast sink at 12 m/s
        }
        
        trackPoints.add(IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, i),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: altitude,
          gpsAltitude: altitude,
          isValid: true,
        ));
      }

      final igcFile = IgcFile(
        date: DateTime(2024, 1, 1),
        pilot: 'Test Pilot',
        gliderType: 'Test Glider',
        gliderID: 'TEST',
        trackPoints: trackPoints,
        headers: {},
      );

      // Calculate both types of climb rates
      final instantRates = igcFile.calculateInstantaneousClimbRates();
      final fifteenSecRates = igcFile.calculate15SecondClimbRates();
      final maxRates = igcFile.calculateClimbRates();
      final maxRates15Sec = igcFile.calculate15SecondMaxClimbRates();

      print('=== IGC Climb Rate Debug ===');
      print('Track points: ${trackPoints.length}');
      print('Instantaneous rates: ${instantRates.length}');
      print('15-second rates: ${fifteenSecRates.length}');
      print('');
      
      print('Sample altitudes:');
      for (int i = 0; i < 10 && i < trackPoints.length; i++) {
        print('Point $i: ${trackPoints[i].gpsAltitude}m at ${trackPoints[i].timestamp}');
      }
      print('');
      
      print('Sample instantaneous rates (first 10):');
      for (int i = 0; i < 10 && i < instantRates.length; i++) {
        print('Point $i: ${instantRates[i].toStringAsFixed(2)} m/s');
      }
      print('');
      
      print('Sample 15-second rates (first 10):');
      for (int i = 0; i < 10 && i < fifteenSecRates.length; i++) {
        print('Point $i: ${fifteenSecRates[i].toStringAsFixed(2)} m/s');
      }
      print('');
      
      print('Max instantaneous climb: ${maxRates['maxClimb']?.toStringAsFixed(2)} m/s');
      print('Max instantaneous sink: ${maxRates['maxSink']?.toStringAsFixed(2)} m/s');
      print('Max 15-second climb: ${maxRates15Sec['maxClimb15Sec']?.toStringAsFixed(2)} m/s');
      print('Max 15-second sink: ${maxRates15Sec['maxSink15Sec']?.toStringAsFixed(2)} m/s');

      // Verify that we have non-zero values
      expect(maxRates['maxClimb'], greaterThan(0));
      expect(maxRates['maxSink'], greaterThan(0));
      expect(maxRates15Sec['maxClimb15Sec'], greaterThan(0));
      expect(maxRates15Sec['maxSink15Sec'], greaterThan(0));
      
      // The 15-second rates should be somewhat different from instantaneous
      expect(maxRates15Sec['maxClimb15Sec'], isNot(equals(maxRates['maxClimb'])));
      expect(maxRates15Sec['maxSink15Sec'], isNot(equals(maxRates['maxSink'])));
    });
  });
}