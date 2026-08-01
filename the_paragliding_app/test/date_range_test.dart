import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/utils/date_range_utils.dart';

void main() {
  group('dateRangeForPreset', () {
    test('returns null for all time', () {
      expect(dateRangeForPreset('all', now: DateTime(2024, 3, 15)), isNull);
    });

    test('returns null for an unknown preset', () {
      expect(dateRangeForPreset('nonsense', now: DateTime(2024, 3, 15)), isNull);
    });

    test('ends at midnight on the reference day', () {
      final range = dateRangeForPreset('30_days', now: DateTime(2024, 3, 15, 17, 42));

      expect(range!.end, DateTime(2024, 3, 15));
    });

    test('this_year starts on January 1st', () {
      final range = dateRangeForPreset('this_year', now: DateTime(2024, 7, 15));

      expect(range!.start, DateTime(2024, 1, 1));
      expect(range.end, DateTime(2024, 7, 15));
    });

    test('presets span their documented number of days', () {
      final now = DateTime(2024, 3, 15);

      expect(dateRangeForPreset('30_days', now: now)!.start, DateTime(2024, 2, 14));
      expect(dateRangeForPreset('3_months', now: now)!.start, DateTime(2023, 12, 15));
      expect(dateRangeForPreset('6_months', now: now)!.start, DateTime(2023, 9, 14));
      expect(dateRangeForPreset('12_months', now: now)!.start, DateTime(2023, 3, 16));
    });

    test('handles month-end reference dates', () {
      final range = dateRangeForPreset('3_months', now: DateTime(2024, 1, 31));

      // 91 days before January 31st 2024
      expect(range!.start, DateTime(2023, 11, 1));
    });

    test('handles a leap day reference date', () {
      final range = dateRangeForPreset('12_months', now: DateTime(2024, 2, 29));

      // 365 days before February 29th 2024 - 2023 has no leap day
      expect(range!.start, DateTime(2023, 3, 1));
    });

    test('start is always midnight', () {
      for (final preset in ['30_days', '3_months', '6_months', '12_months']) {
        final start = dateRangeForPreset(preset, now: DateTime(2024, 3, 15, 9, 30))!.start;

        expect(start.hour, 0, reason: preset);
        expect(start.minute, 0, reason: preset);
      }
    });
  });
}
