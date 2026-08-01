import 'package:flutter/material.dart';

/// Date range presets used by the statistics screen.
///
/// Pure function so it can be tested without pumping the screen - pass [now] to
/// pin the reference date.
DateTimeRange? dateRangeForPreset(String preset, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);

  switch (preset) {
    case 'all':
      return null;
    case 'this_year':
      return DateTimeRange(
        start: DateTime(reference.year, 1, 1),
        end: today,
      );
    case '12_months':
      return DateTimeRange(start: _daysBefore(today, 365), end: today);
    case '6_months':
      return DateTimeRange(start: _daysBefore(today, 183), end: today);
    case '3_months':
      return DateTimeRange(start: _daysBefore(today, 91), end: today);
    case '30_days':
      return DateTimeRange(start: _daysBefore(today, 30), end: today);
    default:
      return null;
  }
}

/// Subtract whole days and snap back to midnight.
///
/// Duration arithmetic on local time shifts by an hour across a DST boundary,
/// which would otherwise push the range start onto the previous day.
DateTime _daysBefore(DateTime day, int days) {
  final shifted = day.subtract(Duration(days: days));
  return DateTime(shifted.year, shifted.month, shifted.day);
}
