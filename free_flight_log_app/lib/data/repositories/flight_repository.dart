import 'package:sqflite/sqflite.dart';
import '../datasources/database_helper.dart';
import '../models/flight.dart';
import '../../services/logging_service.dart';

/// Repository for basic Flight CRUD operations
/// Handles only data persistence operations, not business logic or complex queries
class FlightRepository {
  final DatabaseHelper _databaseHelper;
  
  /// Constructor with dependency injection
  FlightRepository(this._databaseHelper);

  /// Insert a new flight into the database
  Future<int> insertFlight(Flight flight) async {
    LoggingService.debug('FlightRepository: Inserting new flight');
    
    Database db = await _databaseHelper.database;
    var map = flight.toMap();
    map.remove('id');
    map['updated_at'] = DateTime.now().toIso8601String();
    
    try {
      final result = await db.insert('flights', map);
      LoggingService.database('INSERT', 'Successfully inserted flight with ID $result');
      return result;
    } catch (e) {
      LoggingService.error('FlightRepository: Failed to insert flight', e);
      LoggingService.debug('FlightRepository: Flight data attempted: ${map.keys.join(', ')}');
      
      throw Exception(
        'Failed to insert flight. This may indicate a database schema issue. '
        'Please restart the app to trigger database migrations, or contact support if the problem persists. '
        'Error details: $e'
      );
    }
  }

  /// Get all flights ordered by date (most recent first) with launch site names
  Future<List<Flight>> getAllFlights() async {
    LoggingService.debug('FlightRepository: Getting all flights');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      ORDER BY f.date DESC, f.launch_time DESC
    ''');
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('FlightRepository: Retrieved ${flights.length} flights');
    
    return flights;
  }
  
  /// Get all flights as raw maps for isolate processing
  Future<List<Map<String, dynamic>>> getAllFlightsRaw() async {
    LoggingService.debug('FlightRepository: Getting all flights (raw)');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      ORDER BY f.date DESC, f.launch_time DESC
    ''');
    
    LoggingService.debug('FlightRepository: Retrieved ${maps.length} flight records');
    return maps;
  }
  
  /// Get paginated flights for better performance
  Future<List<Flight>> getFlightsPaginated(int offset, int limit) async {
    LoggingService.debug('FlightRepository: Getting flights (offset: $offset, limit: $limit)');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      ORDER BY f.date DESC, f.launch_time DESC
      LIMIT ? OFFSET ?
    ''', [limit, offset]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('FlightRepository: Retrieved ${flights.length} flights');
    
    return flights;
  }

  /// Get a specific flight by ID
  Future<Flight?> getFlight(int id) async {
    LoggingService.debug('FlightRepository: Getting flight $id');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.id = ?
    ''', [id]);
    
    if (maps.isNotEmpty) {
      LoggingService.debug('FlightRepository: Found flight $id');
      return Flight.fromMap(maps.first);
    }
    
    LoggingService.debug('FlightRepository: Flight $id not found');
    return null;
  }

  /// Update an existing flight
  Future<int> updateFlight(Flight flight) async {
    LoggingService.debug('FlightRepository: Updating flight ${flight.id}');
    
    Database db = await _databaseHelper.database;
    var map = flight.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    
    final result = await db.update(
      'flights',
      map,
      where: 'id = ?',
      whereArgs: [flight.id],
    );
    
    LoggingService.database('UPDATE', 'Updated flight ${flight.id}');
    return result;
  }

  /// Delete a flight by ID
  Future<int> deleteFlight(int id) async {
    LoggingService.debug('FlightRepository: Deleting flight $id');
    
    Database db = await _databaseHelper.database;
    final result = await db.delete(
      'flights',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    LoggingService.database('DELETE', 'Deleted flight $id');
    return result;
  }

}