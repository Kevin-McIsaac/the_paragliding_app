import 'package:intl/intl.dart';

/// Utility class for date and time formatting operations
class DateTimeUtils {
  /// Formats a duration in minutes to "Xh Ym" format
  /// 
  /// Examples:
  /// - 90 minutes -> "1h 30m"
  /// - 45 minutes -> "0h 45m"
  /// - 0 minutes -> "0h 0m"
  static String formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }

  /// Formats a duration in minutes to compact format (omits hours if 0)
  /// 
  /// Examples:
  /// - 90 minutes -> "1h 30m"
  /// - 45 minutes -> "45m"
  /// - 0 minutes -> "0m"
  static String formatDurationCompact(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  /// Formats decimal hours to "Xh Ym" format (used in statistics)
  /// 
  /// Examples:
  /// - 1.5 hours -> "1h 30m"
  /// - 0.75 hours -> "0h 45m"
  /// - 2.25 hours -> "2h 15m"
  static String formatHours(double hours) {
    final wholeHours = hours.floor();
    final minutes = ((hours - wholeHours) * 60).round();
    return '${wholeHours}h ${minutes}m';
  }

  /// Formats a time string with timezone information
  /// 
  /// Used for displaying flight times with proper timezone context
  static String formatTimeWithTimezone(String timeString, String? timezone) {
    if (timezone != null && timezone.isNotEmpty) {
      return '$timeString $timezone';
    }
    return timeString;
  }

  /// Parses a time string (HH:MM) and returns hour and minute components
  /// 
  /// Returns a Map with 'hour' and 'minute' keys, or null if invalid format
  static Map<String, int>? parseTimeString(String timeString) {
    try {
      final parts = timeString.split(':');
      if (parts.length != 2) return null;
      
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        return null;
      }
      
      return {'hour': hour, 'minute': minute};
    } catch (e) {
      return null;
    }
  }

  /// Calculates duration between two time strings in minutes
  /// 
  /// Handles midnight crossing (e.g., 23:30 to 01:15 = 105 minutes)
  /// Returns null if either time string is invalid
  static int? calculateDurationMinutes(String startTime, String endTime) {
    final start = parseTimeString(startTime);
    final end = parseTimeString(endTime);
    
    if (start == null || end == null) return null;
    
    final startMinutes = start['hour']! * 60 + start['minute']!;
    final endMinutes = end['hour']! * 60 + end['minute']!;
    
    // Handle midnight crossing
    if (endMinutes >= startMinutes) {
      return endMinutes - startMinutes;
    } else {
      // Next day crossing: add 24 hours to end time
      return (endMinutes + 24 * 60) - startMinutes;
    }
  }
  
  /// Formats a date to a short string format (MMM d)
  /// 
  /// Examples:
  /// - January 15, 2024 -> "Jan 15"
  /// - December 31, 2023 -> "Dec 31"
  static String formatDateShort(DateTime date) {
    return DateFormat('MMM d').format(date);
  }
}