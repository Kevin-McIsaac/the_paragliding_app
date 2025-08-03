import 'package:flutter_test/flutter_test.dart';
import '../lib/data/models/igc_file.dart';

void main() {
  group('Climb Rate Calculations', () {
    test('Test instantaneous climb rate calculation', () {
      // Create test track points with altitude changes
      final trackPoints = [
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 0),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1000,
          gpsAltitude: 1000,
          isValid: true,
        ),
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 10), // 10 seconds later
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1050, // 50m higher
          gpsAltitude: 1050,
          isValid: true,
        ),
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 20), // 10 seconds later
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1030, // 20m lower
          gpsAltitude: 1030,
          isValid: true,
        ),
      ];

      final igcFile = IgcFile(
        date: DateTime(2024, 1, 1),
        pilot: 'Test Pilot',
        gliderType: 'Test Glider',
        gliderID: 'TEST',
        trackPoints: trackPoints,
        headers: {},
      );

      // Test instantaneous climb rates
      final instantRates = igcFile.calculateInstantaneousClimbRates();
      
      expect(instantRates.length, equals(3));
      expect(instantRates[0], equals(0.0)); // First point has no previous point
      expect(instantRates[1], equals(5.0)); // 50m in 10s = 5 m/s climb
      expect(instantRates[2], equals(-2.0)); // -20m in 10s = -2 m/s sink
    });

    test('Test 15-second average climb rate calculation', () {
      // Create test track points every 3 seconds over 30 seconds
      final trackPoints = [
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 0),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1000,
          gpsAltitude: 1000,
          isValid: true,
        ),
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 3),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1010,
          gpsAltitude: 1010,
          isValid: true,
        ),
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 6),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1020,
          gpsAltitude: 1020,
          isValid: true,
        ),
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 9),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1030,
          gpsAltitude: 1030,
          isValid: true,
        ),
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 12),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1040,
          gpsAltitude: 1040,
          isValid: true,
        ),
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 15),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1050,
          gpsAltitude: 1050,
          isValid: true,
        ),
      ];

      final igcFile = IgcFile(
        date: DateTime(2024, 1, 1),
        pilot: 'Test Pilot',
        gliderType: 'Test Glider',
        gliderID: 'TEST',
        trackPoints: trackPoints,
        headers: {},
      );

      // Test 15-second average climb rates
      final fifteenSecRates = igcFile.calculate15SecondClimbRates();
      
      expect(fifteenSecRates.length, equals(6));
      
      // Middle points should have consistent climb rate
      // (50m altitude gain over 15 seconds = ~3.33 m/s average)
      for (int i = 1; i < 5; i++) {
        expect(fifteenSecRates[i], closeTo(3.33, 1.0)); // Allow tolerance for 15-sec window
      }
    });

    test('Test get climb rate at specific index', () {
      final trackPoints = [
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 0),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1000,
          gpsAltitude: 1000,
          isValid: true,
        ),
        IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, 10),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1100, // 100m higher
          gpsAltitude: 1100,
          isValid: true,
        ),
      ];

      final igcFile = IgcFile(
        date: DateTime(2024, 1, 1),
        pilot: 'Test Pilot',
        gliderType: 'Test Glider',
        gliderID: 'TEST',
        trackPoints: trackPoints,
        headers: {},
      );

      // Test individual point access
      expect(igcFile.getInstantaneousClimbRateAt(0), equals(0.0));
      expect(igcFile.getInstantaneousClimbRateAt(1), equals(10.0)); // 100m in 10s = 10 m/s
      expect(igcFile.getInstantaneousClimbRateAt(5), equals(0.0)); // Out of bounds
      
      expect(igcFile.get15SecondClimbRateAt(0), greaterThanOrEqualTo(0.0));
      expect(igcFile.get15SecondClimbRateAt(1), greaterThanOrEqualTo(0.0));
      expect(igcFile.get15SecondClimbRateAt(5), equals(0.0)); // Out of bounds
    });

    test('Test 15-second maximum climb rate calculation', () {
      // Create more track points to ensure 15-second window works properly
      final trackPoints = <IgcPoint>[];
      for (int i = 0; i <= 10; i++) {
        trackPoints.add(IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, i * 2), // Every 2 seconds
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1000 + (i * 10), // Steady climb of 5 m/s (10m every 2s)
          gpsAltitude: 1000 + (i * 10),
          isValid: true,
        ));
      }
      
      // Add some sink points
      for (int i = 11; i <= 15; i++) {
        trackPoints.add(IgcPoint(
          timestamp: DateTime(2024, 1, 1, 10, 0, i * 2),
          latitude: 45.0,
          longitude: 6.0,
          pressureAltitude: 1100 - ((i - 10) * 20), // Sink of 10 m/s
          gpsAltitude: 1100 - ((i - 10) * 20),
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

      final maxRates15Sec = igcFile.calculate15SecondMaxClimbRates();
      expect(maxRates15Sec['maxClimb15Sec'], greaterThan(0));
      expect(maxRates15Sec['maxSink15Sec'], greaterThan(0));
    });

    test('Test with empty track points', () {
      final igcFile = IgcFile(
        date: DateTime(2024, 1, 1),
        pilot: 'Test Pilot',
        gliderType: 'Test Glider',
        gliderID: 'TEST',
        trackPoints: [],
        headers: {},
      );

      expect(igcFile.calculateInstantaneousClimbRates(), isEmpty);
      expect(igcFile.calculate15SecondClimbRates(), isEmpty);
      expect(igcFile.getInstantaneousClimbRateAt(0), equals(0.0));
      expect(igcFile.get15SecondClimbRateAt(0), equals(0.0));
      
      final maxRates15Sec = igcFile.calculate15SecondMaxClimbRates();
      expect(maxRates15Sec['maxClimb15Sec'], equals(0.0));
      expect(maxRates15Sec['maxSink15Sec'], equals(0.0));
    });
  });
}