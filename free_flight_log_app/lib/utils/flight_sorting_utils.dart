import '../data/models/flight.dart';

/// Utility class for sorting flights with generic comparators
class FlightSortingUtils {
  /// Map of column names to value extractors that return Comparable values
  static final Map<String, Comparable Function(Flight)> _sortExtractors = {
    'launch_site': (Flight flight) => flight.launchSiteName ?? 'ZZZ',
    'datetime': (Flight flight) => _getFlightDateTime(flight),
    'duration': (Flight flight) => flight.effectiveDuration,
    'track_distance': (Flight flight) => flight.distance ?? 0,
    'distance': (Flight flight) => flight.straightDistance ?? 0,
    'altitude': (Flight flight) => flight.maxAltitude ?? 0,
  };

  /// Sorts a list of flights based on the specified column and direction
  static void sortFlights(List<Flight> flights, String column, bool ascending) {
    final extractor = _sortExtractors[column];
    if (extractor == null) {
      return; // Unknown column, no sorting
    }

    flights.sort((a, b) {
      final aValue = extractor(a);
      final bValue = extractor(b);
      final comparison = aValue.compareTo(bValue);
      return ascending ? comparison : -comparison;
    });
  }

  /// Creates a DateTime from flight date and launch time for sorting
  static DateTime _getFlightDateTime(Flight flight) {
    try {
      final timeParts = flight.effectiveLaunchTime.split(':');
      return DateTime(
        flight.date.year,
        flight.date.month,
        flight.date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
    } catch (e) {
      // Fallback to date only if time parsing fails
      return flight.date;
    }
  }

  /// Returns the list of available sort columns
  static List<String> get availableColumns => _sortExtractors.keys.toList();

  /// Checks if a column is sortable
  static bool isValidColumn(String column) => _sortExtractors.containsKey(column);
}