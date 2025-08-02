import 'package:sqflite/sqflite.dart';
import '../datasources/database_helper.dart';
import '../models/wing.dart';

class WingRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  Future<int> insertWing(Wing wing) async {
    Database db = await _databaseHelper.database;
    var map = wing.toMap();
    map.remove('id');
    return await db.insert('wings', map);
  }

  Future<List<Wing>> getAllWings() async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'wings',
      orderBy: 'active DESC, name ASC',
    );
    return List.generate(maps.length, (i) => Wing.fromMap(maps[i]));
  }

  Future<List<Wing>> getActiveWings() async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'wings',
      where: 'active = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );
    return List.generate(maps.length, (i) => Wing.fromMap(maps[i]));
  }

  Future<Wing?> getWing(int id) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'wings',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Wing.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateWing(Wing wing) async {
    Database db = await _databaseHelper.database;
    return await db.update(
      'wings',
      wing.toMap(),
      where: 'id = ?',
      whereArgs: [wing.id],
    );
  }

  Future<int> deleteWing(int id) async {
    Database db = await _databaseHelper.database;
    return await db.delete(
      'wings',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deactivateWing(int id) async {
    Database db = await _databaseHelper.database;
    return await db.update(
      'wings',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> canDeleteWing(int wingId) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM flights WHERE wing_id = ?',
      [wingId],
    );
    return result.first['count'] == 0;
  }

  Future<Map<String, dynamic>> getWingStatistics(int wingId) async {
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> countResult = await db.rawQuery(
      'SELECT COUNT(*) as total_flights FROM flights WHERE wing_id = ?',
      [wingId],
    );
    
    List<Map<String, dynamic>> durationResult = await db.rawQuery(
      'SELECT SUM(duration) as total_duration FROM flights WHERE wing_id = ?',
      [wingId],
    );
    
    return {
      'totalFlights': countResult.first['total_flights'] ?? 0,
      'totalDuration': durationResult.first['total_duration'] ?? 0,
    };
  }
}