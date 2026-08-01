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

/// Subtract whole calendar days.
///
/// Calendar arithmetic rather than Duration arithmetic: a Duration is a fixed
/// number of hours, so crossing a spring-forward boundary backwards lands on
/// 23:00 of the *previous* day - snapping that to midnight keeps the wrong day.
/// DateTime normalises out-of-range day values, so the offset never enters the
/// calculation at all.
DateTime _daysBefore(DateTime day, int days) {
  return DateTime(day.year, day.month, day.day - days);
}
