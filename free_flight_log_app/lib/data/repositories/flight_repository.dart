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
    return await db.insert('flights', map);
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