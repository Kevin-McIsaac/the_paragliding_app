import 'package:sqflite/sqflite.dart';
import '../data/datasources/database_helper.dart';
import '../data/models/flight.dart';
import '../data/models/site.dart';
import '../data/models/wing.dart';
import 'logging_service.dart';

/// Unified database service combining all database operations
/// Single source of truth for all data persistence and queries
class DatabaseService {
  // Singleton pattern
  static DatabaseService? _instance;
  static DatabaseService get instance {
    _instance ??= DatabaseService._internal();
    return _instance!;
  }
  
  DatabaseService._internal();
  
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  // ========================================================================
  // FLIGHT OPERATIONS
  // ========================================================================
  
  /// Insert a new flight into the database
  Future<int> insertFlight(Flight flight) async {
    LoggingService.debug('DatabaseService: Inserting new flight');
    
    Database db = await _databaseHelper.database;
    var map = flight.toMap();
    map.remove('id');
    map['updated_at'] = DateTime.now().toIso8601String();
    
    try {
      final result = await db.insert('flights', map);
      LoggingService.database('INSERT', 'Successfully inserted flight with ID $result');
      return result;
    } catch (e) {
      LoggingService.error('DatabaseService: Failed to insert flight', e);
      LoggingService.debug('DatabaseService: Flight data attempted: ${map.keys.join(', ')}');
      
      throw Exception(
        'Failed to insert flight. This may indicate a database schema issue. '
        'Please restart the app to trigger database migrations, or contact support if the problem persists. '
        'Error details: $e'
      );
    }
  }

  /// Get all flights ordered by date (most recent first) with launch site names
  Future<List<Flight>> getAllFlights() async {
    LoggingService.debug('DatabaseService: Getting all flights');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      ORDER BY f.date DESC, f.launch_time DESC
    ''');
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('DatabaseService: Retrieved ${flights.length} flights');
    
    return flights;
  }
  
  /// Get all flights as raw maps for isolate processing
  Future<List<Map<String, dynamic>>> getAllFlightsRaw() async {
    LoggingService.debug('DatabaseService: Getting all flights (raw)');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      ORDER BY f.date DESC, f.launch_time DESC
    ''');
    
    LoggingService.debug('DatabaseService: Retrieved ${maps.length} flight records');
    return maps;
  }
  
  /// Get total number of flights
  Future<int> getFlightCount() async {
    LoggingService.debug('DatabaseService: Getting flight count');
    
    Database db = await _databaseHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM flights');
    final count = result.first['count'] as int;
    
    LoggingService.debug('DatabaseService: Total flights: $count');
    return count;
  }

  /// Get a specific flight by ID
  Future<Flight?> getFlight(int id) async {
    LoggingService.debug('DatabaseService: Getting flight $id');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.id = ?
    ''', [id]);
    
    if (maps.isNotEmpty) {
      LoggingService.debug('DatabaseService: Found flight $id');
      return Flight.fromMap(maps.first);
    }
    
    LoggingService.debug('DatabaseService: Flight $id not found');
    return null;
  }

  /// Update an existing flight
  Future<int> updateFlight(Flight flight) async {
    LoggingService.debug('DatabaseService: Updating flight ${flight.id}');
    
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
    LoggingService.debug('DatabaseService: Deleting flight $id');
    
    Database db = await _databaseHelper.database;
    final result = await db.delete(
      'flights',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    LoggingService.database('DELETE', 'Deleted flight $id');
    return result;
  }

  // ========================================================================
  // FLIGHT QUERY OPERATIONS
  // ========================================================================
  
  /// Get flights within a date range
  Future<List<Flight>> getFlightsByDateRange(DateTime start, DateTime end) async {
    LoggingService.debug('DatabaseService: Getting flights by date range');
    
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
    LoggingService.debug('DatabaseService: Found ${flights.length} flights in date range');
    
    return flights;
  }

  /// Get all flights from a specific launch site
  Future<List<Flight>> getFlightsBySite(int siteId) async {
    LoggingService.debug('DatabaseService: Getting flights by site $siteId');
    
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
    LoggingService.debug('DatabaseService: Found ${flights.length} flights for site');
    
    return flights;
  }

  /// Get all flights with a specific wing
  Future<List<Flight>> getFlightsByWing(int wingId) async {
    LoggingService.debug('DatabaseService: Getting flights by wing $wingId');
    
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
    LoggingService.debug('DatabaseService: Found ${flights.length} flights for wing');
    
    return flights;
  }

  /// Find a flight by original filename (used for fast duplicate detection)
  Future<Flight?> findFlightByFilename(String filename) async {
    LoggingService.debug('DatabaseService: Checking for duplicate by filename: $filename');
    
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
      LoggingService.debug('DatabaseService: Found duplicate by filename - Flight ID: ${flight.id}');
      return flight;
    }
    
    LoggingService.debug('DatabaseService: No duplicate found for filename: $filename');
    return null;
  }

  /// Find flight by date and launch time to check for duplicates during import
  Future<Flight?> findFlightByDateTime(DateTime date, String launchTime) async {
    LoggingService.debug('DatabaseService: Checking for duplicate flight on ${date.toIso8601String()} at $launchTime');
    
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
      LoggingService.debug('DatabaseService: Found duplicate flight with ID ${duplicate.id}');
      return duplicate;
    }
    
    LoggingService.debug('DatabaseService: No duplicate flight found');
    return null;
  }

  /// Search flights by text query (searches notes, site names, etc.)
  Future<List<Flight>> searchFlights(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }
    
    LoggingService.debug('DatabaseService: Searching flights with query: $query');
    
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
    LoggingService.debug('DatabaseService: Found ${flights.length} flights matching search');
    
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

  // ========================================================================
  // FLIGHT STATISTICS OPERATIONS
  // ========================================================================
  
  /// Get overall flight statistics (total flights, hours, max altitude)
  Future<Map<String, dynamic>> getOverallStatistics() async {
    LoggingService.debug('DatabaseService: Getting overall statistics');
    
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
    
    LoggingService.info('DatabaseService: Generated overall statistics for ${stats['totalFlights']} flights');
    return stats;
  }

  /// Get flight statistics grouped by year
  Future<List<Map<String, dynamic>>> getYearlyStatistics() async {
    LoggingService.debug('DatabaseService: Getting yearly statistics');
    
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
    
    LoggingService.info('DatabaseService: Generated statistics for ${yearlyStats.length} years');
    return yearlyStats;
  }

  /// Get flight hours grouped by year (simplified version for charts)
  Future<Map<int, double>> getFlightHoursByYear() async {
    LoggingService.debug('DatabaseService: Getting flight hours by year');
    
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
      final minutes = (row['total_minutes'] as int?) ?? 0;
      hoursByYear[year] = minutes / 60.0;
    }
    
    LoggingService.debug('DatabaseService: Retrieved flight hours for ${hoursByYear.length} years');
    return hoursByYear;
  }

  /// Get statistics for wings
  Future<List<Map<String, dynamic>>> getWingStatistics() async {
    LoggingService.debug('DatabaseService: Getting wing statistics');
    
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        w.id,
        w.name,
        w.manufacturer,
        COUNT(f.id) as flight_count,
        SUM(f.duration) as total_duration,
        MAX(f.max_altitude) as max_altitude,
        AVG(f.duration) as avg_duration
      FROM wings w
      LEFT JOIN flights f ON f.wing_id = w.id
      WHERE w.active = 1
      GROUP BY w.id
      ORDER BY flight_count DESC
    ''');
    
    // Convert duration from minutes to hours
    final wingStats = results.map((row) {
      final totalMinutes = (row['total_duration'] as int?) ?? 0;
      return {
        ...row,
        'total_hours': totalMinutes / 60.0,
      };
    }).toList();
    
    LoggingService.debug('DatabaseService: Generated statistics for ${wingStats.length} wings');
    return wingStats;
  }

  /// Get statistics for sites
  Future<List<Map<String, dynamic>>> getSiteStatistics() async {
    LoggingService.debug('DatabaseService: Getting site statistics');
    
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        s.id,
        s.name,
        s.country,
        COUNT(f.id) as flight_count,
        SUM(f.duration) as total_duration,
        MAX(f.max_altitude) as max_altitude,
        AVG(f.duration) as avg_duration
      FROM sites s
      LEFT JOIN flights f ON f.launch_site_id = s.id
      GROUP BY s.id
      ORDER BY flight_count DESC
    ''');
    
    // Convert duration from minutes to hours
    final siteStats = results.map((row) {
      final totalMinutes = (row['total_duration'] as int?) ?? 0;
      return {
        ...row,
        'total_hours': totalMinutes / 60.0,
      };
    }).toList();
    
    LoggingService.debug('DatabaseService: Generated statistics for ${siteStats.length} sites');
    return siteStats;
  }

  // ========================================================================
  // SITE OPERATIONS
  // ========================================================================
  
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
    String? name,
    double? altitude,
    String? country,
  }) async {
    // Check if site exists at these coordinates
    Site? existingSite = await findSiteByCoordinates(latitude, longitude);
    if (existingSite != null) {
      return existingSite;
    }
    
    // If name is "Unknown", make it unique
    String finalName = name ?? 'Site at ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    if (finalName == 'Unknown') {
      // Count existing Unknown sites
      Database db = await _databaseHelper.database;
      final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM sites WHERE name LIKE 'Unknown%'"
      );
      final count = result.first['count'] as int;
      finalName = 'Unknown ${count + 1}';
      LoggingService.info('DatabaseService: Creating unique site name: "$finalName"');
    }
    
    // Create new site
    final newSite = Site(
      latitude: latitude,
      longitude: longitude,
      name: finalName,
      altitude: altitude,
      country: country,
    );
    
    final id = await insertSite(newSite);
    return newSite.copyWith(id: id);
  }

  Future<List<Site>> getSitesWithFlightCounts() async {
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT s.*, COUNT(f.id) as flight_count
      FROM sites s
      LEFT JOIN flights f ON f.launch_site_id = s.id
      GROUP BY s.id
      ORDER BY s.name ASC
    ''');
    
    return maps.map((map) {
      final site = Site.fromMap(map);
      // Add flight count as a transient property (not persisted)
      return site;
    }).toList();
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
      WHERE EXISTS (
        SELECT 1 FROM flights WHERE flights.launch_site_id = sites.id
      )
      ORDER BY usage_count DESC, sites.name ASC
    ''');
    
    return List.generate(maps.length, (i) => Site.fromMap(maps[i]));
  }

  // ========================================================================
  // WING OPERATIONS
  // ========================================================================
  
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

  Future<Map<String, dynamic>> getWingStatisticsById(int wingId) async {
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

  Future<Wing> findOrCreateWing({
    required String manufacturer,
    required String model,
    String? size,
    String? color,
    bool active = true,
  }) async {
    // Check if wing exists
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query(
      'wings',
      where: 'manufacturer = ? AND name = ? AND size = ?',
      whereArgs: [manufacturer, model, size ?? ''],
    );
    
    if (maps.isNotEmpty) {
      return Wing.fromMap(maps.first);
    }
    
    // Create new wing
    final newWing = Wing(
      manufacturer: manufacturer,
      name: model,
      size: size ?? '',
      color: color ?? '',
      active: active,
    );
    
    final id = await insertWing(newWing);
    return newWing.copyWith(id: id);
  }
}