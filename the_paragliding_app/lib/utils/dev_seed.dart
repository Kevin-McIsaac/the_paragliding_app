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
class DevSeed {
  static const _seedDir = String.fromEnvironment('SEED_IGC_DIR');

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

    final files = await directory
        .list()
        .where((entity) =>
            entity is File && entity.path.toLowerCase().endsWith('.igc'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) {
      LoggingService.warning('DevSeed: no IGC files found in $_seedDir');
      return;
    }

    final stopwatch = Stopwatch()..start();
    int imported = 0;
    int failed = 0;

    for (final file in files) {
      onProgress?.call(imported + failed, files.length);
      try {
        await IgcImportService.instance.importIgcFile(file.path);
        imported++;
      } catch (e) {
        failed++;
        LoggingService.warning('DevSeed: failed to import ${file.path}', e);
      }
    }

    LoggingService.structured('DEV_SEED', {
      'directory': _seedDir,
      'found': files.length,
      'imported': imported,
      'failed': failed,
      'duration_ms': stopwatch.elapsedMilliseconds,
    });
  }
}
