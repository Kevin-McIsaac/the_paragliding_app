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

  Future<Site> findOrCreateSite({
    required double latitude,
    required double longitude,
    double? altitude,
    required String name,
    double tolerance = 0.01,
  }) async {
    // First try to find existing site
    Site? existingSite = await findSiteByCoordinates(latitude, longitude, tolerance: tolerance);
    
    if (existingSite != null) {
      return existingSite;
    }
    
    // Create new site
    final newSite = Site(
      name: name,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      customName: false,
    );
    
    final id = await insertSite(newSite);
    return Site(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      customName: false,
    );
  }

  /// Clean up site names that have redundant "Launch" or "Landing" prefixes
  /// This method removes prefixes from coordinate-based site names
  Future<int> cleanupSiteNamePrefixes() async {
    Database db = await _databaseHelper.database;
    
    // Find sites with "Launch " or "Landing " prefix followed by coordinates
    final sitesToUpdate = await db.rawQuery('''
      SELECT id, name FROM sites 
      WHERE (name LIKE 'Launch %°%' OR name LIKE 'Landing %°%')
      AND custom_name = 0
    ''');
    
    int updatedCount = 0;
    
    for (final siteData in sitesToUpdate) {
      final id = siteData['id'] as int;
      final currentName = siteData['name'] as String;
      
      String newName = currentName;
      if (currentName.startsWith('Launch ')) {
        newName = currentName.substring(7); // Remove "Launch " prefix
      } else if (currentName.startsWith('Landing ')) {
        newName = currentName.substring(8); // Remove "Landing " prefix
      }
      
      if (newName != currentName) {
        await db.update(
          'sites',
          {'name': newName},
          where: 'id = ?',
          whereArgs: [id],
        );
        updatedCount++;
      }
    }
    
    return updatedCount;
  }
}