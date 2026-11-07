import 'package:flutter_test/flutter_test.dart';

import 'package:the_paragliding_app/utils/performance_monitor.dart';

/// The same-named operation slot is shared, so overlapping operations (two
/// site searches in flight at once) produce an end with no matching start.
/// That is expected and must not warn or fabricate a duration.
void main() {
  setUp(PerformanceMonitor.reset);

  test('an end without a start is counted, not reported as a failure', () {
    PerformanceMonitor.endOperation('Missing');

    expect(PerformanceMonitor.unmatchedEndsForTest, 1);
  });

  test('a matched start and end leaves no unmatched count', () {
    PerformanceMonitor.startOperation('Matched');
    PerformanceMonitor.endOperation('Matched');

    expect(PerformanceMonitor.unmatchedEndsForTest, 0);
  });

  test('reset clears the unmatched count', () {
    PerformanceMonitor.endOperation('Missing');

    PerformanceMonitor.reset();

    expect(PerformanceMonitor.unmatchedEndsForTest, 0);
  });
}
