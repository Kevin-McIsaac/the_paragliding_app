import 'package:sqflite/sqflite.dart';
import '../datasources/database_helper.dart';
import '../../services/logging_service.dart';

/// Service for flight statistics and data aggregation operations
/// Handles all statistical calculations and reporting functionality
class FlightStatisticsService {
  final DatabaseHelper _databaseHelper;

  /// Constructor with dependency injection
  FlightStatisticsService(this._databaseHelper);

  /// Get overall flight statistics (total flights, hours, max altitude)
  Future<Map<String, dynamic>> getOverallStatistics() async {
    LoggingService.debug('FlightStatisticsService: Getting overall statistics');
    
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_flights,
        SUM(duration) as total_duration,
        MAX(max_altitude) as highest_altitude,
        AVG(duration) as average_duration,
        AVG(max_altitude) as average_altitude
      FROM flights
    ''');
    
    final row = result.first;
    final stats = {
      'totalFlights': row['total_flights'] ?? 0,
      'totalDuration': row['total_duration'] ?? 0,
      'highestAltitude': row['highest_altitude'] ?? 0.0,
      'averageDuration': row['average_duration'] ?? 0.0,
      'averageAltitude': row['average_altitude'] ?? 0.0,
    };
    
    LoggingService.info('FlightStatisticsService: Generated overall statistics for ${stats['totalFlights']} flights');
    return stats;
  }

  /// Get flight statistics grouped by year
  Future<List<Map<String, dynamic>>> getYearlyStatistics() async {
    LoggingService.debug('FlightStatisticsService: Getting yearly statistics');
    
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        CAST(strftime('%Y', date) AS INTEGER) as year,
        COUNT(*) as flight_count,
        SUM(duration) as total_minutes,
        MAX(max_altitude) as max_altitude,
        AVG(duration) as avg_duration,
        AVG(max_altitude) as avg_altitude
      FROM flights
      GROUP BY year
      ORDER BY year DESC
    ''');
    
    final yearlyStats = results.map((row) {
      final totalMinutes = (row['total_minutes'] as int?) ?? 0;
      return {
        'year': row['year'],
        'flight_count': row['flight_count'] ?? 0,
        'total_hours': totalMinutes / 60.0,
        'max_altitude': row['max_altitude'] ?? 0,
        'avg_duration': (row['avg_duration'] as double?) ?? 0.0,
        'avg_altitude': (row['avg_altitude'] as double?) ?? 0.0,
      };
    }).toList();
    
    LoggingService.info('FlightStatisticsService: Generated statistics for ${yearlyStats.length} years');
    return yearlyStats;
  }

  /// Get flight hours grouped by year (simplified version for charts)
  Future<Map<int, double>> getFlightHoursByYear() async {
    LoggingService.debug('FlightStatisticsService: Getting flight hours by year');
    
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        CAST(strftime('%Y', date) AS INTEGER) as year,
        SUM(duration) as total_minutes
      FROM flights
      GROUP BY year
      ORDER BY year DESC
    ''');
    
    Map<int, double> hoursByYear = {};
    for (final row in results) {
      final year = row['year'] as int;
      final totalMinutes = (row['total_minutes'] as int?) ?? 0;
      hoursByYear[year] = totalMinutes / 60.0; // Convert to hours
    }
    
    LoggingService.debug('FlightStatisticsService: Generated hours data for ${hoursByYear.length} years');
    return hoursByYear;
  }

  /// Get statistics grouped by wing type (manufacturer + model)
  Future<List<Map<String, dynamic>>> getWingStatistics() async {
    LoggingService.debug('FlightStatisticsService: Getting wing statistics');
    
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        CASE 
          WHEN w.manufacturer IS NOT NULL AND w.manufacturer != '' 
               AND w.model IS NOT NULL AND w.model != ''
          THEN w.manufacturer || ' ' || w.model
          ELSE COALESCE(w.name, 'Unknown')
        END as wing_name,
        COUNT(f.id) as flight_count,
        SUM(f.duration) as total_minutes,
        MAX(f.max_altitude) as max_altitude,
        AVG(f.duration) as avg_duration,
        AVG(f.max_altitude) as avg_altitude,
        COUNT(DISTINCT w.id) as wing_count
      FROM wings w
      LEFT JOIN flights f ON f.wing_id = w.id
      WHERE f.id IS NOT NULL
      GROUP BY wing_name
      ORDER BY total_minutes DESC
    ''');
    
    final wingStats = results.map((row) {
      final displayName = row['wing_name'] as String? ?? 'Unknown';
      final totalMinutes = (row['total_minutes'] as int?) ?? 0;
      final wingCount = (row['wing_count'] as int?) ?? 1;
      
      return {
        'name': displayName,
        'flight_count': row['flight_count'] ?? 0,
        'total_hours': totalMinutes / 60.0,
        'max_altitude': row['max_altitude'] ?? 0,
        'avg_duration': (row['avg_duration'] as double?) ?? 0.0,
        'avg_altitude': (row['avg_altitude'] as double?) ?? 0.0,
        'wing_count': wingCount, // Number of individual wings of this type
      };
    }).toList();
    
    LoggingService.info('FlightStatisticsService: Generated statistics for ${wingStats.length} wing types');
    return wingStats;
  }

  /// Get statistics grouped by launch site
  Future<List<Map<String, dynamic>>> getSiteStatistics() async {
    LoggingService.debug('FlightStatisticsService: Getting site statistics');
    
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        s.name as site_name,
        s.country as country,
        COUNT(f.id) as flight_count,
        SUM(f.duration) as total_minutes,
        MAX(f.max_altitude) as max_altitude,
        AVG(f.duration) as avg_duration,
        AVG(f.max_altitude) as avg_altitude
      FROM sites s
      LEFT JOIN flights f ON f.launch_site_id = s.id
      WHERE f.id IS NOT NULL
      GROUP BY s.id, s.name, s.country
      ORDER BY 
        CASE WHEN s.country IS NULL THEN 1 ELSE 0 END,
        s.country ASC,
        s.name ASC
    ''');
    
    final siteStats = results.map((row) {
      final totalMinutes = (row['total_minutes'] as int?) ?? 0;
      return {
        'site_name': row['site_name'] ?? 'Unknown',
        'country': row['country'] ?? 'Unknown Country',
        'flight_count': row['flight_count'] ?? 0,
        'total_hours': totalMinutes / 60.0,
        'max_altitude': row['max_altitude'] ?? 0,
        'avg_duration': (row['avg_duration'] as double?) ?? 0.0,
        'avg_altitude': (row['avg_altitude'] as double?) ?? 0.0,
      };
    }).toList();
    
    LoggingService.info('FlightStatisticsService: Generated statistics for ${siteStats.length} sites');
    return siteStats;
  }

  /// Get monthly statistics for a specific year
  Future<List<Map<String, dynamic>>> getMonthlyStatistics(int year) async {
    LoggingService.debug('FlightStatisticsService: Getting monthly statistics for $year');
    
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        CAST(strftime('%m', date) AS INTEGER) as month,
        COUNT(*) as flight_count,
        SUM(duration) as total_minutes,
        MAX(max_altitude) as max_altitude,
        AVG(duration) as avg_duration
      FROM flights
      WHERE CAST(strftime('%Y', date) AS INTEGER) = ?
      GROUP BY month
      ORDER BY month
    ''', [year]);
    
    final monthlyStats = results.map((row) {
      final totalMinutes = (row['total_minutes'] as int?) ?? 0;
      return {
        'month': row['month'],
        'flight_count': row['flight_count'] ?? 0,
        'total_hours': totalMinutes / 60.0,
        'max_altitude': row['max_altitude'] ?? 0,
        'avg_duration': (row['avg_duration'] as double?) ?? 0.0,
      };
    }).toList();
    
    LoggingService.debug('FlightStatisticsService: Generated monthly statistics for ${monthlyStats.length} months');
    return monthlyStats;
  }

  /// Get personal records and achievements
  Future<Map<String, dynamic>> getPersonalRecords() async {
    LoggingService.debug('FlightStatisticsService: Getting personal records');
    
    Database db = await _databaseHelper.database;
    
    // Get various records in parallel
    final futures = await Future.wait([
      // Longest flight by duration
      db.rawQuery('''
        SELECT f.*, s.name as site_name, s.country
        FROM flights f
        LEFT JOIN sites s ON f.launch_site_id = s.id
        ORDER BY f.duration DESC
        LIMIT 1
      '''),
      
      // Highest altitude flight
      db.rawQuery('''
        SELECT f.*, s.name as site_name, s.country
        FROM flights f
        LEFT JOIN sites s ON f.launch_site_id = s.id
        ORDER BY f.max_altitude DESC
        LIMIT 1
      '''),
      
      // Longest distance flight
      db.rawQuery('''
        SELECT f.*, s.name as site_name, s.country
        FROM flights f
        LEFT JOIN sites s ON f.launch_site_id = s.id
        WHERE f.distance IS NOT NULL
        ORDER BY f.distance DESC
        LIMIT 1
      '''),
    ]);
    
    final records = {
      'longest_duration': futures[0].isNotEmpty ? futures[0].first : null,
      'highest_altitude': futures[1].isNotEmpty ? futures[1].first : null,
      'longest_distance': futures[2].isNotEmpty ? futures[2].first : null,
    };
    
    LoggingService.info('FlightStatisticsService: Generated personal records');
    return records;
  }
}