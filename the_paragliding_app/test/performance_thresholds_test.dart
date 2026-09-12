import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/services/logging_service.dart';

/// The threshold map has to name the operations that are actually logged.
///
/// It held ten names and exactly one of them - `'Load flights'` - was ever passed
/// to `LoggingService.performance`. On the live run of 2026-09-12 that left a
/// 1761ms database startup and an 11306ms first map load unremarked, and the
/// warning path unreachable for 50 of the codebase's 51 operations: the guard
/// existed, the names never matched it.
void main() {
  group('every logged operation has a threshold', () {
    test('no call site uses an operation without one', () {
      final names = <String>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final match
            in RegExp(r"performance\(\s*'([^']*)'").allMatches(source)) {
          names.add(match.group(1)!);
        }
      }
      // Guard the guard: a moved directory would otherwise make this pass by
      // finding nothing at all.
      expect(
        names.length,
        greaterThan(30),
        reason: 'the scan must actually find the performance() call sites',
      );

      final missing = [
        for (final name in names)
          if (LoggingService.thresholdForTest(name) == null) name,
      ];
      expect(
        missing,
        isEmpty,
        reason: 'these operations could never warn, whatever they cost',
      );
    });

    test('names assembled at the call site resolve by prefix', () {
      expect(LoggingService.thresholdForTest('BOM WA parsing'), isNotNull);
      expect(LoggingService.thresholdForTest('CESIUM map_ready'), isNotNull);
      expect(LoggingService.thresholdForTest('PgeSitesQuery_Bounds'), isNotNull);
      expect(LoggingService.thresholdForTest('PgeSitesQuery_Search'), isNotNull);
    });
  });

  group('the thresholds the live run breached now fire', () {
    test('a slow database startup warns', () {
      expect(
        LoggingService.thresholdSeverityForTest('Startup: database', 1761),
        'WARNING',
      );
    });

    test('a slow first map load is critical', () {
      expect(
        LoggingService.thresholdSeverityForTest(
            'Load Nearby Sites Data', 11306),
        'CRITICAL',
      );
    });

    test('a bounds query above its target warns', () {
      expect(
        LoggingService.thresholdSeverityForTest('PgeSitesQuery_Bounds', 254),
        'WARNING',
      );
    });

    test('an operation inside its threshold says nothing', () {
      expect(
        LoggingService.thresholdSeverityForTest('Startup: database', 400),
        isNull,
      );
      expect(
        LoggingService.thresholdSeverityForTest('Station deduplication', 4),
        isNull,
      );
    });
  });
}
