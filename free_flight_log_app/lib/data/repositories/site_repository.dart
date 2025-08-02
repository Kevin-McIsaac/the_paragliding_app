import 'package:sqflite/sqflite.dart';
import '../datasources/database_helper.dart';
import '../models/site.dart';

class SiteRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  Future<int> insertSite(Site site) async {
    Database db = await _databaseHelper.database;
    var map = site.toMap();
    map.remove('id');
    return await db.insert('sites', map);
  }

  Future<List<Site>> getAllSites() async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'sites',
      orderBy: 'name ASC',
    );
    return List.generate(maps.length, (i) => Site.fromMap(maps[i]));
  }

  Future<Site?> getSite(int id) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'sites',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Site.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateSite(Site site) async {
    Database db = await _databaseHelper.database;
    return await db.update(
      'sites',
      site.toMap(),
      where: 'id = ?',
      whereArgs: [site.id],
    );
  }

  Future<int> deleteSite(int id) async {
    Database db = await _databaseHelper.database;
    return await db.delete(
      'sites',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Site?> findSiteByCoordinates(double latitude, double longitude, {double tolerance = 0.01}) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'sites',
      where: 'ABS(latitude - ?) < ? AND ABS(longitude - ?) < ?',
      whereArgs: [latitude, tolerance, longitude, tolerance],
    );
    if (maps.isNotEmpty) {
      return Site.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Site>> searchSites(String query) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'sites',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
    );
    return List.generate(maps.length, (i) => Site.fromMap(maps[i]));
  }

  Future<bool> canDeleteSite(int siteId) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM flights WHERE launch_site_id = ? OR landing_site_id = ?',
      [siteId, siteId],
    );
    return result.first['count'] == 0;
  }
}