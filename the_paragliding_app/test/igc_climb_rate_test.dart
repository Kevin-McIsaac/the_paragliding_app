import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/igc_file.dart';

void main() {
  group('IGC Climb Rate Averaging', () {
    /// 30 seconds at 1 Hz: 10 m/s climb, 5 m/s sink, 8 m/s climb, 12 m/s sink.
    /// The final sink is sustained for 10s, longer than half the averaging
    /// window, so it survives smoothing intact.
    IgcFile buildTestFlight() {
      final trackPoints = <IgcPoint>[];

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

      return IgcFile(
        date: DateTime(2024, 1, 1),
        pilot: 'Test Pilot',
        gliderType: 'Test Glider',
        gliderID: 'TEST',
        trackPoints: trackPoints,
        headers: {},
      );
    }

    test('produces a rate for every track point', () {
      final igcFile = buildTestFlight();

      expect(igcFile.calculateInstantaneousClimbRates(), hasLength(30));
      expect(igcFile.calculate15SecondClimbRates(), hasLength(30));
    });

    test('reports non-zero instantaneous and averaged extremes', () {
      final igcFile = buildTestFlight();

      final maxRates = igcFile.calculateClimbRates();
      final maxRates15Sec = igcFile.calculate15SecondMaxClimbRates();

      expect(maxRates['maxClimb'], greaterThan(0));
      expect(maxRates['maxSink'], greaterThan(0));
      expect(maxRates15Sec['maxClimb15Sec'], greaterThan(0));
      expect(maxRates15Sec['maxSink15Sec'], greaterThan(0));
    });

    test('15-second averages never exceed the instantaneous peaks', () {
      final igcFile = buildTestFlight();

      final maxRates = igcFile.calculateClimbRates();
      final maxRates15Sec = igcFile.calculate15SecondMaxClimbRates();

      expect(maxRates15Sec['maxClimb15Sec'],
          lessThanOrEqualTo(maxRates['maxClimb']!));
      expect(maxRates15Sec['maxSink15Sec'],
          lessThanOrEqualTo(maxRates['maxSink']!));
    });

    test('smooths short climb bursts', () {
      final igcFile = buildTestFlight();

      final maxRates = igcFile.calculateClimbRates();
      final maxRates15Sec = igcFile.calculate15SecondMaxClimbRates();

      // No climb segment lasts longer than 10s, so averaging over 15s must
      // pull the peak down
      expect(maxRates15Sec['maxClimb15Sec'], lessThan(maxRates['maxClimb']!));
    });
  });
}
