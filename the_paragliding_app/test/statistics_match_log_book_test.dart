import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/services/database_service.dart';

import 'helpers/test_helpers.dart';

/// The invariant that was broken: Statistics and the Log Book must report the
/// same total for the same set of flights.
///
/// Deliberately goes through the production call paths rather than asserting on
/// SQL written here - `getYearlyStatistics()` is what statistics_screen.dart:109
/// calls, `getAllFlights()` is what flight_list_screen.dart:110 calls, and the
/// fold below is what flight_list_screen.dart:430 does with the result. A test
/// that recomputed the totals its own way would just be a third implementation
/// of the rule whose duplication caused the bug, and would pass even if both
/// screens were wrong.
void main() {
  setUpAll(TestHelpers.initializeDatabaseForTesting);

  final db = DatabaseService.instance;

  setUp(() async {
    final raw = await DatabaseHelper.instance.database;
    await raw.delete('flights');
  });

  Future<void> insertFlight({
    required String date,
    required int duration,
    String? takeoff,
    String? landing,
  }) async {
    final raw = await DatabaseHelper.instance.database;
    await raw.insert('flights', {
      'date': date,
      'launch_time': '10:00',
      'landing_time': '12:00',
      'duration': duration,
      'detected_takeoff_time': takeoff,
      'detected_landing_time': landing,
    });
  }

  /// Total hours as the Statistics screen computes it (statistics_screen.dart:142-145).
  Future<double> statisticsHours() async {
    final stats = await db.getYearlyStatistics();
    return stats.fold<double>(
        0.0, (sum, s) => sum + ((s['total_hours'] as num?)?.toDouble() ?? 0.0));
  }

  /// Total minutes as the Log Book computes it (flight_list_screen.dart:430).
  Future<int> logBookMinutes() async {
    final flights = await db.getAllFlights();
    return flights.fold<int>(0, (sum, f) => sum + f.duration);
  }

  test('totals agree when durations came from detection', () async {
    await insertFlight(
      date: '2026-01-15',
      duration: 95,
      takeoff: '2026-01-15T10:05:00.000',
      landing: '2026-01-15T11:40:00.000',
    );
    await insertFlight(
      date: '2026-02-20',
      duration: 90,
      takeoff: '2026-02-20T13:00:00.000',
      landing: '2026-02-20T14:30:00.000',
    );

    expect(await logBookMinutes(), 185);
    expect(await statisticsHours(), closeTo(185 / 60.0, 0.0001));
  });

  test('totals agree for manual flights with no detection data', () async {
    await insertFlight(date: '2026-03-01', duration: 42);

    expect(await logBookMinutes(), 42);
    expect(await statisticsHours(), closeTo(42 / 60.0, 0.0001));
  });

  test('totals agree across years and a mix of both kinds', () async {
    await insertFlight(
      date: '2025-06-10',
      duration: 75,
      takeoff: '2025-06-10T09:00:00.000',
      landing: '2025-06-10T10:15:00.000',
    );
    await insertFlight(date: '2026-03-01', duration: 42);
    await insertFlight(
      date: '2026-07-04',
      duration: 110,
      takeoff: '2026-07-04T11:00:00.000',
      landing: '2026-07-04T12:50:00.000',
    );

    final minutes = await logBookMinutes();
    expect(minutes, 75 + 42 + 110);
    expect(await statisticsHours(), closeTo(minutes / 60.0, 0.0001));
  });

  test('a database still holding pre-v3 durations is reconciled by the backfill',
      () async {
    // Exactly the broken state: the column holds the IGC header's figure while
    // detection says the flight was shorter.
    await insertFlight(
      date: '2026-01-15',
      duration: 120, // header
      takeoff: '2026-01-15T10:05:00.000',
      landing: '2026-01-15T11:40:00.000', // 95 detected
    );

    // Before the migration the two disagree - this is the bug, reproduced.
    expect(await logBookMinutes(), 120);

    await DatabaseHelper.instance
        .backfillDetectedDurations(await DatabaseHelper.instance.database);

    final minutes = await logBookMinutes();
    expect(minutes, 95);
    expect(await statisticsHours(), closeTo(minutes / 60.0, 0.0001));
  });
}
