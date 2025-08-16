import 'package:sqflite/sqflite.dart';
import '../datasources/database_helper.dart';
import '../models/flight.dart';
import '../../services/logging_service.dart';

/// Service for complex flight queries and filtering operations
/// Handles all query-related operations that don't involve basic CRUD
class FlightQueryService {
  // Singleton pattern
  static FlightQueryService? _instance;
  static FlightQueryService get instance {
    _instance ??= FlightQueryService._internal();
    return _instance!;
  }
  
  FlightQueryService._internal();
  
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  /// Get flights within a date range
  Future<List<Flight>> getFlightsByDateRange(DateTime start, DateTime end) async {
    LoggingService.debug('FlightQueryService: Getting flights by date range');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.date >= ? AND f.date <= ?
      ORDER BY f.date DESC, f.launch_time DESC
    ''', [start.toIso8601String(), end.toIso8601String()]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('FlightQueryService: Found ${flights.length} flights in date range');
    
    return flights;
  }

  /// Get all flights from a specific launch site
  Future<List<Flight>> getFlightsBySite(int siteId) async {
    LoggingService.debug('FlightQueryService: Getting flights by site $siteId');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.launch_site_id = ?
      ORDER BY f.date DESC, f.launch_time DESC
    ''', [siteId]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('FlightQueryService: Found ${flights.length} flights for site');
    
    return flights;
  }

  /// Get all flights with a specific wing
  Future<List<Flight>> getFlightsByWing(int wingId) async {
    LoggingService.debug('FlightQueryService: Getting flights by wing $wingId');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.wing_id = ?
      ORDER BY f.date DESC, f.launch_time DESC
    ''', [wingId]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('FlightQueryService: Found ${flights.length} flights for wing');
    
    return flights;
  }

  /// Find a flight by original filename (used for fast duplicate detection)
  Future<Flight?> findFlightByFilename(String filename) async {
    LoggingService.debug('FlightQueryService: Checking for duplicate by filename: $filename');
    
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.original_filename = ?
      LIMIT 1
    ''', [filename]);
    
    if (maps.isNotEmpty) {
      final flight = Flight.fromMap(maps.first);
      LoggingService.debug('FlightQueryService: Found duplicate by filename - Flight ID: ${flight.id}');
      return flight;
    }
    
    LoggingService.debug('FlightQueryService: No duplicate found for filename: $filename');
    return null;
  }

  /// Find flight by date and launch time to check for duplicates during import
  Future<Flight?> findFlightByDateTime(DateTime date, String launchTime) async {
    LoggingService.debug('FlightQueryService: Checking for duplicate flight on ${date.toIso8601String()} at $launchTime');
    
    Database db = await _databaseHelper.database;
    
    // Format date as ISO string for database comparison
    final dateStr = date.toIso8601String().split('T')[0]; // Get just the date part
    
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE DATE(f.date) = ? AND f.launch_time = ?
      LIMIT 1
    ''', [dateStr, launchTime]);
    
    if (maps.isNotEmpty) {
      final duplicate = Flight.fromMap(maps.first);
      LoggingService.debug('FlightQueryService: Found duplicate flight with ID ${duplicate.id}');
      return duplicate;
    }
    
    LoggingService.debug('FlightQueryService: No duplicate flight found');
    return null;
  }

  /// Search flights by text query (searches notes, site names, etc.)
  Future<List<Flight>> searchFlights(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }
    
    LoggingService.debug('FlightQueryService: Searching flights with query: $query');
    
    Database db = await _databaseHelper.database;
    final searchTerm = '%${query.toLowerCase()}%';
    
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE LOWER(f.notes) LIKE ? 
         OR LOWER(ls.name) LIKE ?
      ORDER BY f.date DESC, f.launch_time DESC
    ''', [searchTerm, searchTerm]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('FlightQueryService: Found ${flights.length} flights matching search');
    
    return flights;
  }


  /// Get total count of flights
  Future<int> getTotalFlightCount() async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM flights'
    );
    return result.first['count'] as int;
  }
}