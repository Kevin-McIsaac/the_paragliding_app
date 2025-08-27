import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log_app/services/igc_parser.dart';

void main() {
  test('IGC Parser performance without isolates', () async {
    final parser = IgcParser();
    const testFile = 'test_data/sample_flight.igc';
    
    // Warm up
    await parser.parseFile(testFile);
    
    // Benchmark 10 runs
    final stopwatch = Stopwatch()..start();
    for (int i = 0; i < 10; i++) {
      final result = await parser.parseFile(testFile);
      expect(result.trackPoints.isNotEmpty, true);
    }
    stopwatch.stop();
    
    final averageMs = stopwatch.elapsedMilliseconds / 10;
    debugPrint('Average parse time: ${averageMs.toStringAsFixed(2)}ms');
    debugPrint('Total time for 10 parses: ${stopwatch.elapsedMilliseconds}ms');
    
    // Should be under 50ms for small files (no isolate overhead)
    expect(averageMs, lessThan(50));
  });
}