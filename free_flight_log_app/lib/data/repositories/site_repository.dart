import 'package:sqflite/sqflite.dart';
import '../datasources/database_helper.dart';
import '../models/site.dart';

class SiteRepository {
  final DatabaseHelper _databaseHelper;
  
  /// Constructor with dependency injection
  SiteRepository(this._databaseHelper);

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
      'SELECT COUNT(*) as count FROM flights WHERE launch_site_id = ?',
      [siteId],
    );
    return result.first['count'] == 0;
  }

  Future<Site> findOrCreateSite({
    required double latitude,
    required double longitude,
    double? altitude,
    required String name,
    String? country,
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
      country: country,
      customName: false,
    );
    
    final id = await insertSite(newSite);
    return Site(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      country: country,
      customName: false,
    );
  }


  /// Get all sites that have been used in flights (for personalized fallback)
  /// Returns sites ordered by usage frequency (most used first)
  Future<List<Site>> getSitesUsedInFlights() async {
    Database db = await _databaseHelper.database;
    
    // Query to get all launch sites used in flights, with usage count for ordering
    // Note: We only track launch sites now, not landing sites (which are stored as coordinates)
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT 
        sites.*,
        (
          SELECT COUNT(*) FROM flights 
          WHERE flights.launch_site_id = sites.id
        ) as usage_count
      FROM sites 
      WHERE sites.id IN (
        SELECT DISTINCT launch_site_id FROM flights WHERE launch_site_id IS NOT NULL
      )
      ORDER BY usage_count DESC, sites.name ASC
    ''');
    
    return List.generate(maps.length, (i) => Site.fromMap(maps[i]));
  }

  /// Get all sites that are missing country information
  Future<List<Site>> getSitesWithoutLocationInfo() async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'sites',
      where: 'country IS NULL AND name != ?',
      whereArgs: ['Unknown'],
      orderBy: 'name ASC',
    );
    return List.generate(maps.length, (i) => Site.fromMap(maps[i]));
  }

  /// Update country for an existing site
  Future<int> updateSiteLocationInfo(int siteId, String? country) async {
    Database db = await _databaseHelper.database;
    return await db.update(
      'sites',
      {
        'country': country,
      },
      where: 'id = ?',
      whereArgs: [siteId],
    );
  }

  /// Get all sites with their flight counts (including sites with 0 flights)
  Future<List<Site>> getSitesWithFlightCounts() async {
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT 
        sites.*,
        COALESCE(
          (SELECT COUNT(*) FROM flights WHERE flights.launch_site_id = sites.id), 
          0
        ) as flight_count
      FROM sites 
      ORDER BY sites.name ASC
    ''');
    
    return List.generate(maps.length, (i) => Site.fromMap(maps[i]));
  }
}