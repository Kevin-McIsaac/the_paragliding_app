import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/utils/dev_seed.dart';

/// DevSeed imports only the most recent flights so a full IGC archive does not
/// take minutes to seed. The selection is pure - no disk, no database.
void main() {
  group('DevSeed.mostRecentPaths', () {
    test('keeps the newest files, still oldest-first', () {
      final paths = [
        '/igc/160124_Kevin McIsaac_01.igc',
        '/igc/260712_KMc_01.igc',
        '/igc/230501_KMc_01.igc',
        '/igc/260711_KMc_01.igc',
      ];

      expect(DevSeed.mostRecentPaths(paths, 2), [
        '/igc/260711_KMc_01.igc',
        '/igc/260712_KMc_01.igc',
      ]);
    });

    test('returns everything when there are fewer files than the limit', () {
      final paths = ['/igc/230501_KMc_01.igc', '/igc/160124_KMc_01.igc'];

      expect(DevSeed.mostRecentPaths(paths, 8), [
        '/igc/160124_KMc_01.igc',
        '/igc/230501_KMc_01.igc',
      ]);
    });

    test('returns everything when the count equals the limit', () {
      final paths = ['/igc/230501_KMc_01.igc', '/igc/160124_KMc_01.igc'];

      expect(DevSeed.mostRecentPaths(paths, 2).length, 2);
    });

    test('a non-positive limit means no cap', () {
      final paths = List.generate(20, (i) => '/igc/2607${i.toString().padLeft(2, '0')}_KMc_01.igc');

      expect(DevSeed.mostRecentPaths(paths, 0).length, 20);
    });

    test('picks the July 2026 tail out of a decade of flights', () {
      final paths = <String>[
        for (var year = 16; year <= 25; year++) '/igc/${year}0501_Kevin McIsaac_01.igc',
        '/igc/260705_KMc_01.igc',
        '/igc/260709_KMc_01.igc',
        '/igc/260709_KMc_02.igc',
        '/igc/260712_KMc_01.igc',
      ];

      final selected = DevSeed.mostRecentPaths(paths, 8);

      expect(selected.length, 8);
      expect(selected.where((p) => p.contains('/2607')).length, 4);
      expect(selected.last, '/igc/260712_KMc_01.igc');
    });

    test('does not mutate the caller\'s list', () {
      final paths = ['/igc/260712_KMc_01.igc', '/igc/160124_KMc_01.igc'];

      DevSeed.mostRecentPaths(paths, 1);

      expect(paths.first, '/igc/260712_KMc_01.igc');
    });
  });
}
