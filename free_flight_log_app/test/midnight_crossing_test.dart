import 'package:flutter_test/flutter_test.dart';
import '../lib/data/models/igc_file.dart';

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
        timestamp: DateTime(2024, 1, 15, 23, 30, 0), // 23:30
        latitude: 45.0,
        longitude: 6.0,
        pressureAltitude: 1000,
        gpsAltitude: 1000,
        isValid: true,
      );
      
      final landingPoint = IgcPoint(
        timestamp: DateTime(2024, 1, 15, 1, 45, 0), // 01:45 (appears to be same day due to UTC conversion)
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
      
      // Without midnight correction: 01:45 - 23:30 = -21:45 = -1305 minutes
      // With midnight correction: -1305 + 1440 = 135 minutes (2 hours 15 minutes)
      expect(igcFile.duration, equals(135));
    });
    
    test('Edge case: exactly midnight crossing', () {
      // Launch just before midnight, land just after
      final launchPoint = IgcPoint(
        timestamp: DateTime(2024, 1, 15, 23, 59, 0), // 23:59
        latitude: 45.0,
        longitude: 6.0,
        pressureAltitude: 1000,
        gpsAltitude: 1000,
        isValid: true,
      );
      
      final landingPoint = IgcPoint(
        timestamp: DateTime(2024, 1, 15, 0, 1, 0), // 00:01 (appears same day due to parsing)
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
      
      // Without midnight correction: 00:01 - 23:59 = -23:58 = -1438 minutes
      // With midnight correction: -1438 + 1440 = 2 minutes
      expect(igcFile.duration, equals(2));
    });
  });
}