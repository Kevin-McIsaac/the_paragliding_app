import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';

import 'helpers/test_helpers.dart';

/// Covers the v2 -> v3 migration, which rewrites `duration` in place on real
/// user data. Before v3 the column held the IGC header's figure while the UI
/// displayed a separately computed takeoff-to-landing value, so every total
/// disagreed with the rows it summarised.
void main() {
  setUpAll(TestHelpers.initializeDatabaseForTesting);

  Future<int> insertFlight({
    required int duration,
    String? takeoff,
    String? landing,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('flights', {
      'date': '2026-01-15',
      'launch_time': '10:00',
      'landing_time': '12:00',
      'duration': duration,
      'detected_takeoff_time': takeoff,
      'detected_landing_time': landing,
    });
  }

  Future<int> durationOf(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows =
        await db.query('flights', columns: ['duration'], where: 'id = ?', whereArgs: [id]);
    return rows.single['duration'] as int;
  }

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('flights');
  });

  test('rewrites duration as detected takeoff to landing', () async {
    // Header says 120 minutes; the detected flight is 95.
    final id = await insertFlight(
      duration: 120,
      takeoff: '2026-01-15T10:05:00.000',
      landing: '2026-01-15T11:40:00.000',
    );

    await DatabaseHelper.instance
        .backfillDetectedDurations(await DatabaseHelper.instance.database);

    expect(await durationOf(id), 95);
  });

  test('leaves manual flights alone', () async {
    // No detection data - a hand-entered flight whose duration is the only
    // record of how long it was. The migration must not touch it.
    final id = await insertFlight(duration: 42);

    await DatabaseHelper.instance
        .backfillDetectedDurations(await DatabaseHelper.instance.database);

    expect(await durationOf(id), 42);
  });

  test('is safe to run twice', () async {
    final id = await insertFlight(
      duration: 120,
      takeoff: '2026-01-15T10:05:00.000',
      landing: '2026-01-15T11:40:00.000',
    );
    final db = await DatabaseHelper.instance.database;

    await DatabaseHelper.instance.backfillDetectedDurations(db);
    await DatabaseHelper.instance.backfillDetectedDurations(db);

    expect(await durationOf(id), 95);
  });

  test('rounds to the nearest minute rather than truncating', () async {
    // 59.5 minutes. Truncation would store 59 and quietly lose time across a
    // whole log book.
    final id = await insertFlight(
      duration: 0,
      takeoff: '2026-01-15T10:00:00.000',
      landing: '2026-01-15T10:59:30.000',
    );

    await DatabaseHelper.instance
        .backfillDetectedDurations(await DatabaseHelper.instance.database);

    expect(await durationOf(id), 60);
  });

  test('leaves rows alone where landing is not after takeoff', () async {
    // Should be unreachable - TakeoffLandingDetector rejects takeoff at or after
    // landing - but the migration rewrites user data, so it must not turn a bad
    // row into a negative duration.
    final inverted = await insertFlight(
      duration: 60,
      takeoff: '2026-01-15T12:00:00.000',
      landing: '2026-01-15T11:00:00.000',
    );
    final equal = await insertFlight(
      duration: 30,
      takeoff: '2026-01-15T12:00:00.000',
      landing: '2026-01-15T12:00:00.000',
    );

    await DatabaseHelper.instance
        .backfillDetectedDurations(await DatabaseHelper.instance.database);

    expect(await durationOf(inverted), 60, reason: 'must not become -60');
    expect(await durationOf(equal), 30);
  });

  test('totals match the sum of the rows - the invariant that was broken',
      () async {
    await insertFlight(
      duration: 120,
      takeoff: '2026-01-15T10:05:00.000',
      landing: '2026-01-15T11:40:00.000', // 95
    );
    await insertFlight(
      duration: 200,
      takeoff: '2026-01-15T13:00:00.000',
      landing: '2026-01-15T14:30:00.000', // 90
    );
    await insertFlight(duration: 42); // manual, unchanged

    final db = await DatabaseHelper.instance.database;
    await DatabaseHelper.instance.backfillDetectedDurations(db);

    // What the aggregates sum in SQL...
    final total = (await db.rawQuery('SELECT SUM(duration) AS t FROM flights'))
        .single['t'] as int;
    // ...must equal what the list would fold over in Dart.
    final rows = await db.query('flights', columns: ['duration']);
    final folded =
        rows.fold<int>(0, (sum, r) => sum + (r['duration'] as int));

    expect(total, folded);
    expect(total, 95 + 90 + 42);
  });
}
