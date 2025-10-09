import 'package:sqflite/sqflite.dart';
import '../data/datasources/database_helper.dart';
import '../data/models/flight.dart';
import '../data/models/site.dart';
import '../data/models/wing.dart';
import '../data/models/paragliding_site.dart';
import 'logging_service.dart';
import 'pge_sites_database_service.dart';

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
    
    Database db = await _databaseHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM flights');
    final count = result.first['count'] as int;
    
    return count;
  }

  /// Get a specific flight by ID
  Future<Flight?> getFlight(int id) async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.id = ?
    ''', [id]);
    
    if (maps.isNotEmpty) {
      return Flight.fromMap(maps.first);
    }
    
    return null;
  }

  /// Update an existing flight
  Future<int> updateFlight(Flight flight) async {
    
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

  /// Get flights for a site that have launch coordinates (for map display)
  Future<List<Flight>> getFlightsWithLaunchCoordinatesForSite(int siteId) async {
    LoggingService.debug('DatabaseService: Getting flights with launch coordinates for site $siteId');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.launch_site_id = ? 
        AND f.launch_latitude IS NOT NULL 
        AND f.launch_longitude IS NOT NULL
      ORDER BY f.date DESC, f.launch_time DESC
    ''', [siteId]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('DatabaseService: Found ${flights.length} flights with launch coordinates for site');
    
    return flights;
  }

  /// Get all flights with launch coordinates within given bounds (for map display)
  Future<List<Flight>> getAllLaunchesInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    LoggingService.debug('DatabaseService: Getting all launches in bounds N:$north S:$south E:$east W:$west');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.launch_latitude IS NOT NULL 
        AND f.launch_longitude IS NOT NULL
        AND f.launch_latitude BETWEEN ? AND ?
        AND f.launch_longitude BETWEEN ? AND ?
      ORDER BY f.date DESC, f.launch_time DESC
    ''', [south, north, west, east]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('DatabaseService: Found ${flights.length} launches in bounds');
    
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
      LoggingService.warning('DatabaseService: Found duplicate flight by filename: $filename (ID: ${flight.id})');
      return flight;
    }
    
    return null;
  }

  /// Find flight by date and launch time to check for duplicates during import
  Future<Flight?> findFlightByDateTime(DateTime date, String launchTime) async {
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
      LoggingService.warning('DatabaseService: Found duplicate flight on $dateStr at $launchTime (ID: ${duplicate.id})');
      return duplicate;
    }
    
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
  
  /// Helper method to build date filtering WHERE clause and arguments
  /// Returns a tuple of (whereClause, whereArgs)
  (String, List<dynamic>) _buildDateFilter(DateTime? startDate, DateTime? endDate, {String? tablePrefix}) {
    String whereClause = '';
    List<dynamic> whereArgs = [];
    
    if (startDate != null || endDate != null) {
      final prefix = tablePrefix != null ? '$tablePrefix.' : '';
      whereClause = 'WHERE ';
      
      if (startDate != null) {
        whereClause += '${prefix}date >= ?';
        whereArgs.add(startDate.toIso8601String().split('T')[0]);
      }
      
      if (endDate != null) {
        if (startDate != null) whereClause += ' AND ';
        whereClause += '${prefix}date <= ?';
        whereArgs.add(endDate.toIso8601String().split('T')[0]);
      }
    }
    
    return (whereClause, whereArgs);
  }
  
  /// Helper method to add date filtering to existing WHERE clause
  /// Returns updated (whereClause, whereArgs)
  (String, List<dynamic>) _addDateFilter(String existingWhereClause, List<dynamic> existingWhereArgs, 
      DateTime? startDate, DateTime? endDate, {String? tablePrefix}) {
    if (startDate == null && endDate == null) {
      return (existingWhereClause, existingWhereArgs);
    }
    
    final prefix = tablePrefix != null ? '$tablePrefix.' : '';
    String whereClause = existingWhereClause;
    List<dynamic> whereArgs = List.from(existingWhereArgs);
    
    if (startDate != null) {
      whereClause += ' AND ${prefix}date >= ?';
      whereArgs.add(startDate.toIso8601String().split('T')[0]);
    }
    
    if (endDate != null) {
      whereClause += ' AND ${prefix}date <= ?';
      whereArgs.add(endDate.toIso8601String().split('T')[0]);
    }
    
    return (whereClause, whereArgs);
  }
  
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
  Future<List<Map<String, dynamic>>> getYearlyStatistics({DateTime? startDate, DateTime? endDate}) async {
    final stopwatch = Stopwatch()..start();
    LoggingService.debug('DatabaseService: Getting yearly statistics');
    
    Database db = await _databaseHelper.database;
    
    final (whereClause, whereArgs) = _buildDateFilter(startDate, endDate);
    
    List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        CAST(strftime('%Y', date) AS INTEGER) as year,
        COUNT(*) as flight_count,
        SUM(duration) as total_minutes,
        MAX(max_altitude) as max_altitude,
        AVG(duration) as avg_duration,
        AVG(max_altitude) as avg_altitude
      FROM flights
      $whereClause
      GROUP BY year
      ORDER BY year DESC
    ''', whereArgs);
    
    stopwatch.stop();
    LoggingService.debug('DatabaseService: Yearly statistics query completed in ${stopwatch.elapsedMilliseconds}ms');
    
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

  /// Get statistics for wings grouped by manufacturer, model, and size
  Future<List<Map<String, dynamic>>> getWingStatistics({DateTime? startDate, DateTime? endDate}) async {
    final stopwatch = Stopwatch()..start();
    LoggingService.debug('DatabaseService: Getting wing statistics');
    
    Database db = await _databaseHelper.database;
    
    final (whereClause, whereArgs) = _addDateFilter('WHERE w.active = 1', [], startDate, endDate, tablePrefix: 'f');
    
    List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        CASE 
          WHEN w.manufacturer IS NOT NULL OR w.model IS NOT NULL THEN
            TRIM(
              COALESCE(w.manufacturer, '') || 
              CASE WHEN w.model IS NOT NULL THEN ' ' || w.model ELSE '' END
            )
          ELSE MIN(w.name)
        END as name,
        w.manufacturer,
        w.model,
        w.size,
        COUNT(DISTINCT w.id) as wing_count,
        COUNT(f.id) as flight_count,
        SUM(f.duration) as total_duration,
        MAX(f.max_altitude) as max_altitude,
        AVG(f.duration) as avg_duration
      FROM wings w
      LEFT JOIN flights f ON f.wing_id = w.id
      $whereClause
      GROUP BY w.manufacturer, w.model, w.size
      ORDER BY flight_count DESC
    ''', whereArgs);
    
    stopwatch.stop();
    LoggingService.debug('DatabaseService: Wing statistics query completed in ${stopwatch.elapsedMilliseconds}ms');
    
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
  Future<List<Map<String, dynamic>>> getSiteStatistics({DateTime? startDate, DateTime? endDate}) async {
    final stopwatch = Stopwatch()..start();
    LoggingService.debug('DatabaseService: Getting site statistics');
    
    Database db = await _databaseHelper.database;
    
    final (whereClause, whereArgs) = _buildDateFilter(startDate, endDate, tablePrefix: 'f');
    
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
      INNER JOIN flights f ON f.launch_site_id = s.id
      $whereClause
      GROUP BY s.id
      HAVING COUNT(f.id) > 0
      ORDER BY flight_count DESC
    ''', whereArgs);
    
    stopwatch.stop();
    LoggingService.debug('DatabaseService: Site statistics query completed in ${stopwatch.elapsedMilliseconds}ms');
    
    // Convert duration from minutes to hours
    final siteStats = results.map((row) {
      final totalMinutes = (row['total_duration'] as int?) ?? 0;
      return {
        ...row,
        'total_hours': totalMinutes / 60.0,
      };
    }).toList();
    
    LoggingService.debug('DatabaseService: Generated statistics for ${siteStats.length} sites with flights');
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

  /// Optimized method to get sites with flight counts in a single query
  /// Uses LEFT JOIN to avoid N+1 query problem
  Future<Map<Site, int>> getSitesInBoundsWithFlightCounts({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    Database db = await _databaseHelper.database;

    // Handle date line crossing
    String longitudeCondition;
    List<dynamic> whereArgs;

    if (west > east) {
      // Crosses date line
      longitudeCondition = '(s.longitude >= ? OR s.longitude <= ?)';
      whereArgs = [south, north, west, east];
    } else {
      // Normal case
      longitudeCondition = '(s.longitude >= ? AND s.longitude <= ?)';
      whereArgs = [south, north, west, east];
    }

    // Use raw query with LEFT JOINs to get sites, flight counts, and country names in one query
    final query = '''
      SELECT
        s.*,
        COALESCE(cc.name, s.country) as country_name,
        COUNT(f.id) as flight_count
      FROM sites s
      LEFT JOIN flights f ON s.id = f.launch_site_id
      LEFT JOIN country_codes cc ON UPPER(s.country) = cc.code
      WHERE s.latitude >= ? AND s.latitude <= ? AND $longitudeCondition
      GROUP BY s.id
      ORDER BY s.name ASC
    ''';

    final stopwatch = Stopwatch()..start();
    List<Map<String, dynamic>> results = await db.rawQuery(query, whereArgs);
    stopwatch.stop();

    final sitesWithCounts = <Site, int>{};
    for (final row in results) {
      // Extract site data (remove the flight_count and country_name fields)
      final siteMap = Map<String, dynamic>.from(row)
        ..remove('flight_count')
        ..remove('country_name');

      // Use country_name if available, otherwise use the original country code
      if (row['country_name'] != null) {
        siteMap['country'] = row['country_name'];
      }

      final site = Site.fromMap(siteMap);
      final flightCount = row['flight_count'] as int? ?? 0;
      sitesWithCounts[site] = flightCount;
    }

    LoggingService.performance(
      'Optimized sites query',
      Duration(milliseconds: stopwatch.elapsedMilliseconds),
      'Found ${sitesWithCounts.length} sites with flight counts in single query',
    );

    return sitesWithCounts;
  }

  /// Get local sites enriched with PGE data via FK JOIN
  /// Returns ParaglidingSite objects combining local and PGE data
  Future<List<ParaglidingSite>> getLocalSitesWithPgeDataInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    final stopwatch = Stopwatch()..start();
    Database db = await _databaseHelper.database;

    // Handle date line crossing
    String longitudeCondition;
    List<dynamic> whereArgs;
    if (west > east) {
      // Crosses date line
      longitudeCondition = '(s.longitude >= ? OR s.longitude <= ?)';
      whereArgs = [south, north, west, east];
    } else {
      // Normal case
      longitudeCondition = '(s.longitude >= ? AND s.longitude <= ?)';
      whereArgs = [south, north, west, east];
    }

    // JOIN query to get local sites with PGE data via FK
    // Note: pge_sites table only has basic fields, not description/rating/etc from API
    final results = await db.rawQuery('''
      SELECT
        s.*,
        COUNT(f.id) as flight_count,
        pge.name as pge_name,
        pge.wind_n, pge.wind_ne, pge.wind_e, pge.wind_se,
        pge.wind_s, pge.wind_sw, pge.wind_w, pge.wind_nw,
        pge.altitude as pge_altitude,
        pge.country as pge_country
      FROM sites s
      LEFT JOIN pge_sites pge ON s.pge_site_id = pge.id
      LEFT JOIN flights f ON f.launch_site_id = s.id
      WHERE s.latitude >= ? AND s.latitude <= ?
      AND $longitudeCondition
      GROUP BY s.id
    ''', whereArgs);

    // Convert results to ParaglidingSite objects
    final sites = <ParaglidingSite>[];
    for (final row in results) {
      // Build wind directions from PGE data
      final windDirections = <String>[];
      final windMap = {
        'N': row['wind_n'],
        'NE': row['wind_ne'],
        'E': row['wind_e'],
        'SE': row['wind_se'],
        'S': row['wind_s'],
        'SW': row['wind_sw'],
        'W': row['wind_w'],
        'NW': row['wind_nw'],
      };

      // Debug for Mt Bakewell
      if ((row['name'] as String).contains('Bakewell')) {
        LoggingService.debug('Mt Bakewell JOIN result:');
        LoggingService.debug('  - Site ID: ${row['id']}');
        LoggingService.debug('  - PGE Site ID: ${row['pge_site_id']}');
        LoggingService.debug('  - Wind data: $windMap');
      }

      windMap.forEach((direction, value) {
        if (value != null && (value as int) >= 1) {
          windDirections.add(direction);
        }
      });

      sites.add(ParaglidingSite(
        id: row['id'] as int?,
        name: row['name'] as String,
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        altitude: (row['altitude'] as num?)?.toInt() ?? (row['pge_altitude'] as num?)?.toInt(),
        country: (row['country'] ?? row['pge_country']) as String?,
        siteType: 'launch',  // Default since PGE DB doesn't have this
        windDirections: windDirections,
        description: null,  // Not available in local PGE DB
        rating: null,  // Not available in local PGE DB
        region: null,  // Not available in local PGE DB
        flightCount: row['flight_count'] as int? ?? 0,
        isFromLocalDb: true,
      ));
    }

    stopwatch.stop();
    LoggingService.performance(
      'Local sites with PGE JOIN',
      stopwatch.elapsed,
      'Found ${sites.length} sites'
    );

    return sites;
  }

  Future<Site?> getSite(int id) async {
    Database db = await _databaseHelper.database;

    // Use JOIN to get country name conversion
    final results = await db.rawQuery('''
      SELECT
        s.*,
        COALESCE(cc.name, s.country) as country_name
      FROM sites s
      LEFT JOIN country_codes cc ON UPPER(s.country) = cc.code
      WHERE s.id = ?
    ''', [id]);

    if (results.isNotEmpty) {
      final row = results.first;
      final siteMap = Map<String, dynamic>.from(row)
        ..remove('country_name');

      // Use country_name if available
      if (row['country_name'] != null) {
        siteMap['country'] = row['country_name'];
      }

      return Site.fromMap(siteMap);
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

  /// Bulk update multiple flights to assign them to a new site
  Future<void> bulkUpdateFlightSites(List<int> flightIds, int newSiteId) async {
    if (flightIds.isEmpty) return;
    
    Database db = await _databaseHelper.database;
    
    // Use a batch for efficiency
    final batch = db.batch();
    for (final flightId in flightIds) {
      batch.update(
        'flights',
        {'launch_site_id': newSiteId},
        where: 'id = ?',
        whereArgs: [flightId],
      );
    }
    
    await batch.commit();
    LoggingService.debug('DatabaseService: Bulk updated ${flightIds.length} flights to site $newSiteId');
  }

  /// Reassign all flights from one site to another
  /// Returns the number of flights updated
  Future<int> reassignFlights(int fromSiteId, int toSiteId) async {
    Database db = await _databaseHelper.database;
    LoggingService.info('DatabaseService: Reassigning flights from site $fromSiteId to site $toSiteId');
    
    // Update all flights that reference the old site
    final result = await db.update(
      'flights',
      {'launch_site_id': toSiteId},
      where: 'launch_site_id = ?',
      whereArgs: [fromSiteId],
    );
    
    LoggingService.info('DatabaseService: Reassigned $result flights');
    return result;
  }

  /// Count flights for a specific site
  Future<int> getFlightCountForSite(int siteId) async {
    Database db = await _databaseHelper.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM flights
      WHERE launch_site_id = ?
    ''', [siteId]);
    
    return result.first['count'] as int? ?? 0;
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
    int? pgeSiteId,
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
    // Use provided pgeSiteId or try to find a matching PGE site
    int? finalPgeSiteId = pgeSiteId;
    if (finalPgeSiteId == null) {
      try {
        final pgeSite = await PgeSitesDatabaseService.instance.findNearestSite(
          latitude: latitude,
          longitude: longitude,
          maxDistanceKm: 0.1, // 100m tolerance for automatic linking
        );
        finalPgeSiteId = pgeSite?.id;
      } catch (e) {
        LoggingService.debug('Failed to find matching PGE site: $e');
        // Continue without PGE link
      }
    }

    final newSite = Site(
      latitude: latitude,
      longitude: longitude,
      name: finalName,
      altitude: altitude,
      country: country,
      pgeSiteId: finalPgeSiteId,
    );

    final id = await insertSite(newSite);
    final createdSite = newSite.copyWith(id: id);

    if (finalPgeSiteId != null) {
      LoggingService.info('DatabaseService: Created site "$finalName" linked to PGE site ID: $finalPgeSiteId');
    }

    return createdSite;
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

  /// Link a local site with a PGE site using foreign key relationship
  /// This replaces the need for runtime coordinate-based matching
  Future<bool> linkSiteWithPgeSite(int localSiteId, int pgeSiteId) async {
    try {
      Database db = await _databaseHelper.database;

      final result = await db.update(
        'sites',
        {'pge_site_id': pgeSiteId},
        where: 'id = ?',
        whereArgs: [localSiteId],
      );

      if (result > 0) {
        LoggingService.info('DatabaseService: Linked site $localSiteId with PGE site $pgeSiteId');
        return true;
      } else {
        LoggingService.warning('DatabaseService: Failed to link site $localSiteId - site not found');
        return false;
      }
    } catch (e) {
      LoggingService.error('DatabaseService: Error linking site with PGE site', e);
      return false;
    }
  }

  /// Get sites with their linked PGE site information
  /// Uses JOIN to efficiently combine local and PGE site data
  Future<List<Map<String, dynamic>>> getSitesWithPgeInfo() async {
    Database db = await _databaseHelper.database;

    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT s.*,
             p.name as pge_name,
             p.wind_n, p.wind_ne, p.wind_e, p.wind_se,
             p.wind_s, p.wind_sw, p.wind_w, p.wind_nw,
             COUNT(f.id) as flight_count
      FROM sites s
      LEFT JOIN pge_sites p ON s.pge_site_id = p.id
      LEFT JOIN flights f ON f.launch_site_id = s.id
      GROUP BY s.id
      ORDER BY s.name ASC
    ''');

    return maps;
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

  // ========================================================================
  // WING ALIAS OPERATIONS
  // ========================================================================
  
  /// Add an alias for a wing
  Future<void> addWingAlias(int wingId, String aliasName) async {
    Database db = await _databaseHelper.database;
    await db.insert('wing_aliases', {
      'wing_id': wingId,
      'alias_name': aliasName.trim(),
    });
    LoggingService.debug('DatabaseService: Added alias "$aliasName" for wing $wingId');
  }
  
  /// Get all aliases for a wing
  Future<List<String>> getWingAliases(int wingId) async {
    Database db = await _databaseHelper.database;
    final results = await db.query(
      'wing_aliases',
      where: 'wing_id = ?',
      whereArgs: [wingId],
      orderBy: 'alias_name ASC',
    );
    return results.map((row) => row['alias_name'] as String).toList();
  }
  
  /// Remove an alias
  Future<void> removeWingAlias(int wingId, String aliasName) async {
    Database db = await _databaseHelper.database;
    await db.delete(
      'wing_aliases',
      where: 'wing_id = ? AND alias_name = ?',
      whereArgs: [wingId, aliasName],
    );
    LoggingService.debug('DatabaseService: Removed alias "$aliasName" from wing $wingId');
  }
  
  /// Find wing by name or alias
  Future<Wing?> findWingByNameOrAlias(String name) async {
    Database db = await _databaseHelper.database;
    final trimmedName = name.trim();
    
    // First check primary wing names
    var results = await db.query(
      'wings',
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [trimmedName],
      limit: 1,
    );
    
    if (results.isNotEmpty) {
      return Wing.fromMap(results.first);
    }
    
    // Then check aliases
    results = await db.rawQuery('''
      SELECT w.* FROM wings w
      JOIN wing_aliases wa ON w.id = wa.wing_id
      WHERE LOWER(wa.alias_name) = LOWER(?)
      LIMIT 1
    ''', [trimmedName]);
    
    if (results.isNotEmpty) {
      return Wing.fromMap(results.first);
    }
    
    return null;
  }
  
  /// Merge multiple wings into one primary wing
  Future<void> mergeWings(int primaryWingId, List<int> wingIdsToMerge) async {
    Database db = await _databaseHelper.database;
    
    // Start a transaction for data integrity
    await db.transaction((txn) async {
      // Get the wings being merged for alias creation
      final wingsToMerge = await txn.query(
        'wings',
        where: 'id IN (${wingIdsToMerge.map((_) => '?').join(',')})',
        whereArgs: wingIdsToMerge,
      );
      
      // Update all flights to use the primary wing
      for (int wingId in wingIdsToMerge) {
        await txn.update(
          'flights',
          {'wing_id': primaryWingId},
          where: 'wing_id = ?',
          whereArgs: [wingId],
        );
        
        // Copy any aliases from merged wing to primary wing
        final aliases = await txn.query(
          'wing_aliases',
          where: 'wing_id = ?',
          whereArgs: [wingId],
        );
        
        for (var alias in aliases) {
          try {
            await txn.insert('wing_aliases', {
              'wing_id': primaryWingId,
              'alias_name': alias['alias_name'],
            });
          } catch (e) {
            // Ignore duplicate alias errors
            LoggingService.debug('Skipping duplicate alias: ${alias['alias_name']}');
          }
        }
      }
      
      // Add the merged wing names as aliases for the primary wing
      for (var wing in wingsToMerge) {
        final wingName = wing['name'] as String;
        try {
          await txn.insert('wing_aliases', {
            'wing_id': primaryWingId,
            'alias_name': wingName,
          });
        } catch (e) {
          // Ignore if this name is already an alias
          LoggingService.debug('Skipping duplicate alias: $wingName');
        }
      }
      
      // Delete the merged wings
      for (int wingId in wingIdsToMerge) {
        await txn.delete(
          'wings',
          where: 'id = ?',
          whereArgs: [wingId],
        );
      }
    });
    
    LoggingService.info('DatabaseService: Merged ${wingIdsToMerge.length} wings into wing $primaryWingId');
  }
  
  /// Get statistics about wings that could be merged
  Future<Map<String, List<Wing>>> findPotentialDuplicateWings() async {
    final wings = await getAllWings();
    
    Map<String, List<Wing>> potentialDuplicates = {};
    
    for (var wing in wings) {
      // Extract potential base name (remove common variations)
      String baseName = wing.name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '') // Remove special chars
          .replaceAll(RegExp(r'\s+'), ' ') // Normalize spaces
          .trim();
      
      // Also try with manufacturer + model if available
      if (wing.manufacturer != null && wing.model != null) {
        String fullName = '${wing.manufacturer} ${wing.model}'
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        
        if (!potentialDuplicates.containsKey(fullName)) {
          potentialDuplicates[fullName] = [];
        }
        potentialDuplicates[fullName]!.add(wing);
      }
      
      // Group by base name
      if (!potentialDuplicates.containsKey(baseName)) {
        potentialDuplicates[baseName] = [];
      }
      potentialDuplicates[baseName]!.add(wing);
    }
    
    // Filter out groups with only one wing
    potentialDuplicates.removeWhere((key, value) => value.length <= 1);
    
    return potentialDuplicates;
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