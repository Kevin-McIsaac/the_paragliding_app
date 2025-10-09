import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/igc_file.dart';

void main() {
  group('IGC Midnight Crossing Tests', () {
    test('Normal flight duration calculation', () {
      // Create track points for a normal flight (same day)
      final launchPoint = IgcPoint(
        timestamp: DateTime(2024, 1, 15, 14, 30, 0), // 14:30
        latitude: 45.0,
        longitude: 6.0,
        pressureAltitude: 1000,
        gpsAltitude: 1000,
        isValid: true,
      );
      
      final landingPoint = IgcPoint(
        timestamp: DateTime(2024, 1, 15, 16, 45, 0), // 16:45 (same day)
        latitude: 45.1,
        longitude: 6.1,
        pressureAltitude: 800,
        gpsAltitude: 800,
        isValid: true,
      );
      
      final igcFile = IgcFile(
        date: DateTime(2024, 1, 15),
        pilot: 'Test Pilot',
        gliderType: 'Test Glider',
        gliderID: 'TEST123',
        trackPoints: [launchPoint, landingPoint],
        headers: {},
        timezone: '+01:00',
      );
      
      // Expected duration: 2 hours 15 minutes = 135 minutes
      expect(igcFile.duration, equals(135));
    });
    
    test('Midnight crossing flight duration calculation', () {
      // Create track points for a flight crossing midnight
      final launchPoint = IgcPoint(
        timestamp: DateTime(2024, 1, 15, 23, 30, 0), // 23:30 on Jan 15
        latitude: 45.0,
        longitude: 6.0,
        pressureAltitude: 1000,
        gpsAltitude: 1000,
        isValid: true,
      );
      
      final landingPoint = IgcPoint(
        timestamp: DateTime(2024, 1, 16, 1, 45, 0), // 01:45 on Jan 16 (next day)
        latitude: 45.1,
        longitude: 6.1,
        pressureAltitude: 800,
        gpsAltitude: 800,
        isValid: true,
      );
      
      final igcFile = IgcFile(
        date: DateTime(2024, 1, 15),
        pilot: 'Test Pilot',
        gliderType: 'Test Glider',
        gliderID: 'TEST123',
        trackPoints: [launchPoint, landingPoint],
        headers: {},
        timezone: '+01:00',
      );
      
      // Correct calculation: Jan 16 01:45 - Jan 15 23:30 = 2 hours 15 minutes = 135 minutes
      expect(igcFile.duration, equals(135));
    });
    
    test('Edge case: exactly midnight crossing', () {
      // Launch just before midnight, land just after
      final launchPoint = IgcPoint(
        timestamp: DateTime(2024, 1, 15, 23, 59, 0), // 23:59 on Jan 15
        latitude: 45.0,
        longitude: 6.0,
        pressureAltitude: 1000,
        gpsAltitude: 1000,
        isValid: true,
      );
      
      final landingPoint = IgcPoint(
        timestamp: DateTime(2024, 1, 16, 0, 1, 0), // 00:01 on Jan 16 (next day)
        latitude: 45.1,
        longitude: 6.1,
        pressureAltitude: 800,
        gpsAltitude: 800,
        isValid: true,
      );
      
      final igcFile = IgcFile(
        date: DateTime(2024, 1, 15),
        pilot: 'Test Pilot',
        gliderType: 'Test Glider',
        gliderID: 'TEST123',
        trackPoints: [launchPoint, landingPoint],
        headers: {},
        timezone: '+01:00',
      );
      
      // Correct calculation: Jan 16 00:01 - Jan 15 23:59 = 2 minutes
      expect(igcFile.duration, equals(2));
    });
  });
}