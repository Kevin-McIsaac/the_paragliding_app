import '../data/models/paragliding_site.dart';

/// Shared constants and utilities for flyability forecast tables
class FlyabilityConstants {
  // Table display constants
  static const double cellSize = 36.0;
  static const double siteColumnWidth = 120.0;
  static const double headerHeight = 36.0;

  // Time range constants
  static const int startHour = 7;  // 7am
  static const int endHour = 19;   // 7pm
  static const int hoursToShow = 13; // 7am to 7pm inclusive

  // Peak hours for daily summary (10am-4pm)
  static const int peakStartIndex = 3;  // 10am is index 3 (7am + 3 hours)
  static const int peakEndIndex = 9;    // 4pm is index 9 (7am + 9 hours)
}

/// Generate a unique key for a site based on its coordinates
///
/// Uses 4 decimal places for precision (±11m accuracy)
String generateSiteKey(ParaglidingSite site) {
  return '${site.latitude.toStringAsFixed(4)}_${site.longitude.toStringAsFixed(4)}';
}

/// Get a date for a given day index (0-6 for next 7 days)
DateTime getDay(int dayIndex) {
  return DateTime.now().add(Duration(days: dayIndex));
}
