import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/services/takeoff_landing_detector.dart';

/// `DetectionResult.detectedDurationMinutes` is what IgcImportService stores in
/// the `duration` column at import (`detectedDurationMinutes ?? igcData.duration`),
/// so it decides every flight time the app shows and every total it sums. It had
/// no coverage before - it was unused until this change adopted it.
void main() {
  DetectionResult result({
    int? takeoffIndex,
    int? landingIndex,
    DateTime? takeoffTime,
    DateTime? landingTime,
  }) =>
      DetectionResult(
        takeoffIndex: takeoffIndex,
        landingIndex: landingIndex,
        takeoffTime: takeoffTime,
        landingTime: landingTime,
        message: 'test',
      );

  test('returns takeoff to landing when detection is complete', () {
    final r = result(
      takeoffIndex: 10,
      landingIndex: 900,
      takeoffTime: DateTime(2026, 1, 15, 10, 5),
      landingTime: DateTime(2026, 1, 15, 11, 40),
    );

    expect(r.detectedDurationMinutes, 95);
  });

  test('returns null when detection is incomplete, so import keeps the header value', () {
    expect(result().detectedDurationMinutes, isNull);
    expect(
      result(takeoffIndex: 10, takeoffTime: DateTime(2026, 1, 15, 10, 5))
          .detectedDurationMinutes,
      isNull,
      reason: 'takeoff without landing is not a duration',
    );
  });

  test('truncates toward zero, matching Duration.inMinutes', () {
    // Documents the behaviour rather than endorsing it: the SQL backfill rounds,
    // so a freshly imported flight and a migrated one can differ by a minute on
    // the same track. Worth knowing before trusting an exact match between them.
    final r = result(
      takeoffIndex: 0,
      landingIndex: 1,
      takeoffTime: DateTime(2026, 1, 15, 10, 0, 0),
      landingTime: DateTime(2026, 1, 15, 10, 59, 30),
    );

    expect(r.detectedDurationMinutes, 59);
  });
}
