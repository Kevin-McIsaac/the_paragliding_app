import 'package:sqflite/sqflite.dart';
import '../datasources/database_helper.dart';
import '../models/flight.dart';

class FlightRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  Future<int> insertFlight(Flight flight) async {
    Database db = await _databaseHelper.database;
    var map = flight.toMap();
    map.remove('id');
    map['updated_at'] = DateTime.now().toIso8601String();
    
    try {
      return await db.insert('flights', map);
    } catch (e) {
      if (e.toString().contains('max_climb_rate_5_sec') || 
          e.toString().contains('max_sink_rate_5_sec')) {
        print('Database migration needed. Attempting to recreate database...');
        
        // Remove the new fields and try again with legacy format
        map.remove('max_climb_rate_5_sec');
        map.remove('max_sink_rate_5_sec');
        
        try {
          return await db.insert('flights', map);
        } catch (e2) {
          // If that also fails, recreate the database
          await _databaseHelper.recreateDatabase();
          db = await _databaseHelper.database;
          
          // Restore the full map with new fields for the fresh database
          map = flight.toMap();
          map.remove('id');
          map['updated_at'] = DateTime.now().toIso8601String();
          
          return await db.insert('flights', map);
        }
      } else {
        rethrow;
      }
    }
  }

  Future<List<Flight>> getAllFlights() async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'flights',
      orderBy: 'date DESC, launch_time DESC',
    );
    return List.generate(maps.length, (i) => Flight.fromMap(maps[i]));
  }

  Future<Flight?> getFlight(int id) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'flights',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Flight.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateFlight(Flight flight) async {
    Database db = await _databaseHelper.database;
    var map = flight.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    return await db.update(
      'flights',
      map,
      where: 'id = ?',
      whereArgs: [flight.id],
    );
  }

  Future<int> deleteFlight(int id) async {
    Database db = await _databaseHelper.database;
    return await db.delete(
      'flights',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Flight>> getFlightsByDateRange(DateTime start, DateTime end) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'flights',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC, launch_time DESC',
    );
    return List.generate(maps.length, (i) => Flight.fromMap(maps[i]));
  }

  Future<List<Flight>> getFlightsBySite(int siteId) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'flights',
      where: 'launch_site_id = ? OR landing_site_id = ?',
      whereArgs: [siteId, siteId],
      orderBy: 'date DESC, launch_time DESC',
    );
    return List.generate(maps.length, (i) => Flight.fromMap(maps[i]));
  }

  Future<List<Flight>> getFlightsByWing(int wingId) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'flights',
      where: 'wing_id = ?',
      whereArgs: [wingId],
      orderBy: 'date DESC, launch_time DESC',
    );
    return List.generate(maps.length, (i) => Flight.fromMap(maps[i]));
  }

  /// Find flight by date and launch time to check for duplicates
  Future<Flight?> findFlightByDateTime(DateTime date, String launchTime) async {
    Database db = await _databaseHelper.database;
    
    // Format date as ISO string for database comparison
    final dateStr = date.toIso8601String().split('T')[0]; // Get just the date part
    
    List<Map<String, dynamic>> maps = await db.query(
      'flights',
      where: 'DATE(date) = ? AND launch_time = ?',
      whereArgs: [dateStr, launchTime],
      limit: 1,
    );
    
    if (maps.isNotEmpty) {
      return Flight.fromMap(maps.first);
    }
    return null;
  }

  Future<Map<String, dynamic>> getFlightStatistics() async {
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> countResult = await db.rawQuery(
      'SELECT COUNT(*) as total_flights FROM flights'
    );
    
    List<Map<String, dynamic>> durationResult = await db.rawQuery(
      'SELECT SUM(duration) as total_duration FROM flights'
    );
    
    List<Map<String, dynamic>> maxAltitudeResult = await db.rawQuery(
      'SELECT MAX(max_altitude) as highest_altitude FROM flights'
    );
    
    return {
      'totalFlights': countResult.first['total_flights'] ?? 0,
      'totalDuration': durationResult.first['total_duration'] ?? 0,
      'highestAltitude': maxAltitudeResult.first['highest_altitude'] ?? 0.0,
    };
  }
}