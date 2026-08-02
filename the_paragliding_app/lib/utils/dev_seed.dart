import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../services/igc_import_service.dart';
import '../services/logging_service.dart';

/// Seeds the flight log from a directory of IGC files during development.
///
/// Enabled with `--dart-define=SEED_IGC_DIR=/path/to/igc` (see bin/dev_run.sh).
/// Never runs in release builds, and skips when the log already has flights, so
/// it is safe to leave enabled across restarts.
///
/// Only the most recent [_seedLimit] flights are imported - a real IGC archive
/// runs to hundreds of files and importing all of them takes minutes, while a
/// handful exercises every screen. Raise it with
/// `--dart-define=SEED_IGC_LIMIT=20`, or set it to 0 to import the lot.
class DevSeed {
  static const _seedDir = String.fromEnvironment('SEED_IGC_DIR');
  static const _seedLimit = int.fromEnvironment('SEED_IGC_LIMIT', defaultValue: 8);

  /// The newest [limit] of [paths], returned oldest-first so imports still run
  /// in chronological order.
  ///
  /// IGC files are named `YYMMDD_<pilot>_NN.igc`, so sorting by name is sorting
  /// by flight date and the newest flights are the tail of the sorted list.
  @visibleForTesting
  static List<String> mostRecentPaths(List<String> paths, int limit) {
    final sorted = [...paths]..sort();
    if (limit <= 0 || sorted.length <= limit) return sorted;
    return sorted.sublist(sorted.length - limit);
  }

  /// Whether seeding is switched on for this build - lets the caller show a
  /// status before the first import starts
  static bool get isConfigured => !kReleaseMode && _seedDir.isNotEmpty;

  /// [onProgress] is called with (completed, total) before each import so the
  /// caller can show progress - seeding a real log takes several seconds.
  static Future<void> maybeSeed({
    void Function(int done, int total)? onProgress,
  }) async {
    if (kReleaseMode || _seedDir.isEmpty) return;

    final directory = Directory(_seedDir);
    if (!directory.existsSync()) {
      LoggingService.warning('DevSeed: seed directory not found: $_seedDir');
      return;
    }

    final existingFlights = await DatabaseService.instance.getFlightCount();
    if (existingFlights > 0) {
      LoggingService.debug('DevSeed: skipped, $existingFlights flights already in database');
      return;
    }

    final found = await directory
        .list()
        .where((entity) =>
            entity is File && entity.path.toLowerCase().endsWith('.igc'))
        .map((entity) => entity.path)
        .toList();

    if (found.isEmpty) {
      LoggingService.warning('DevSeed: no IGC files found in $_seedDir');
      return;
    }

    final paths = mostRecentPaths(found, _seedLimit);

    final stopwatch = Stopwatch()..start();
    int imported = 0;
    int failed = 0;

    for (final path in paths) {
      onProgress?.call(imported + failed, paths.length);
      try {
        await IgcImportService.instance.importIgcFile(path);
        imported++;
      } catch (e) {
        failed++;
        LoggingService.warning('DevSeed: failed to import $path', e);
      }
    }

    LoggingService.structured('DEV_SEED', {
      'directory': _seedDir,
      'found': found.length,
      'limit': _seedLimit,
      'seeded': paths.length,
      'imported': imported,
      'failed': failed,
      'duration_ms': stopwatch.elapsedMilliseconds,
    });
  }
}
