import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import '../../services/logging_service.dart';

class DatabaseHelper {
  static const _databaseName = "FlightLog.db";
  static const _databaseVersion = 1; // v1.0 Release Schema - Start migrations from v2

  // Singleton pattern
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async => _database ??= await _initDatabase();

  /// Initialize database with v1.0 schema
  ///
  /// PRE-RELEASE STRATEGY: No migrations needed since app hasn't been released.
  /// All schema changes during development require clearing app data.
  ///
  /// POST-RELEASE STRATEGY: Start migrations from v2 when app is released.
  /// This ensures a clean baseline for production users.
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    LoggingService.database('INIT', 'Opening database at: $path');

    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );

    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE flights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        launch_time TEXT NOT NULL,
        landing_time TEXT NOT NULL,
        duration INTEGER NOT NULL,
        launch_site_id INTEGER,
        launch_latitude REAL,
        launch_longitude REAL,
        launch_altitude REAL,
        landing_latitude REAL,
        landing_longitude REAL,
        landing_altitude REAL,
        landing_description TEXT,
        max_altitude REAL,
        max_climb_rate REAL,
        max_sink_rate REAL,
        max_climb_rate_5_sec REAL,
        max_sink_rate_5_sec REAL,
        distance REAL,
        straight_distance REAL,
        fai_triangle_distance REAL,
        fai_triangle_points TEXT,
        wing_id INTEGER,
        notes TEXT,
        track_log_path TEXT,
        original_filename TEXT,
        source TEXT CHECK(source IN ('manual', 'igc', 'parajournal')),
        timezone TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        max_ground_speed REAL,
        avg_ground_speed REAL,
        thermal_count INTEGER,
        avg_thermal_strength REAL,
        total_time_in_thermals INTEGER,
        best_thermal REAL,
        avg_ld REAL,
        longest_glide REAL,
        climb_percentage REAL,
        gps_fix_quality REAL,
        recording_interval REAL,
        takeoff_index INTEGER,
        landing_index INTEGER,
        detected_takeoff_time TEXT,
        detected_landing_time TEXT,
        closing_point_index INTEGER,
        closing_distance REAL,
        FOREIGN KEY (launch_site_id) REFERENCES sites (id),
        FOREIGN KEY (wing_id) REFERENCES wings (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE sites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        country TEXT,
        custom_name INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE wings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        manufacturer TEXT,
        model TEXT,
        size TEXT,
        color TEXT,
        purchase_date TEXT,
        active INTEGER DEFAULT 1,
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE wing_aliases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wing_id INTEGER NOT NULL,
        alias_name TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (wing_id) REFERENCES wings (id) ON DELETE CASCADE,
        UNIQUE(alias_name)
      )
    ''');

    // Create optimized indexes for query performance
    await _createIndexes(db);
  }
  
  /// Create database indexes for optimal query performance
  Future<void> _createIndexes(Database db) async {
    LoggingService.database('INDEX', 'Creating essential indexes');
    
    try {
      // Essential indexes for <5000 records
      
      // 1. Foreign key index for launch site joins (used in almost every query)
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_launch_site ON flights(launch_site_id)');
      
      // 2. Foreign key index for wing joins
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_wing ON flights(wing_id)');
      
      // 3. Composite index for most common query pattern: ORDER BY date DESC, launch_time DESC
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_date_time ON flights(date DESC, launch_time DESC)');
      
      // 4. Index for wing aliases lookup
      await db.execute('CREATE INDEX IF NOT EXISTS idx_wing_aliases_wing_id ON wing_aliases(wing_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_wing_aliases_alias_name ON wing_aliases(alias_name)');

      // 5. Spatial indexes for sites table to optimize bounding box queries
      // These are critical for getSitesInBounds() performance
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_latitude ON sites(latitude)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_longitude ON sites(longitude)');
      // Composite index for the most common spatial query pattern
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_lat_lon ON sites(latitude, longitude)');

      // 6. Index for site name searches
      // Used in searchSitesByName() for autocomplete and site search features
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_name ON sites(name)');

      LoggingService.database('INDEX', 'Successfully created essential indexes');
    } catch (e) {
      LoggingService.error('DatabaseHelper: Failed to create indexes', e);
      rethrow;
    }
  }

  /// Force recreation of the database (use when migration fails)
  Future<void> recreateDatabase() async {
    final path = join(await getDatabasesPath(), _databaseName);
    
    // Close existing connection
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    
    // Delete the database file
    await deleteDatabase(path);
    
    // Recreate the database
    _database = await _initDatabase();
  }

  /// Validate database schema to ensure all expected columns exist
  /// This provides an additional safety net beyond migrations
  Future<bool> validateDatabaseSchema() async {
    try {
      final db = await database;
      
      // Check flights table has all expected columns
      final flightColumns = await db.rawQuery("PRAGMA table_info(flights)");
      final expectedFlightColumns = {
        'id', 'date', 'launch_time', 'landing_time', 'duration',
        'launch_site_id', 'launch_latitude', 'launch_longitude', 'launch_altitude',
        'landing_latitude', 'landing_longitude', 'landing_altitude', 'landing_description',
        'max_altitude', 'max_climb_rate', 'max_sink_rate', 'max_climb_rate_5_sec', 'max_sink_rate_5_sec',
        'distance', 'straight_distance', 'fai_triangle_distance', 'fai_triangle_points',
        'wing_id', 'notes', 'track_log_path', 'original_filename', 'source',
        'timezone', 'created_at', 'updated_at',
        'max_ground_speed', 'avg_ground_speed', 'thermal_count', 'avg_thermal_strength',
        'total_time_in_thermals', 'best_thermal', 'avg_ld', 'longest_glide',
        'climb_percentage', 'gps_fix_quality', 'recording_interval',
        'takeoff_index', 'landing_index', 'detected_takeoff_time', 'detected_landing_time',
        'closing_point_index', 'closing_distance'
      };
      
      final actualFlightColumns = flightColumns.map((col) => col['name'] as String).toSet();
      final missingFlightColumns = expectedFlightColumns.difference(actualFlightColumns);
      
      if (missingFlightColumns.isNotEmpty) {
        LoggingService.error('DatabaseHelper: Missing flight columns: ${missingFlightColumns.join(', ')}');
        return false;
      }
      
      // Check sites table has all expected columns  
      final siteColumns = await db.rawQuery("PRAGMA table_info(sites)");
      final expectedSiteColumns = {
        'id', 'name', 'latitude', 'longitude', 'altitude', 'country', 'custom_name', 'created_at'
      };
      
      final actualSiteColumns = siteColumns.map((col) => col['name'] as String).toSet();
      final missingSiteColumns = expectedSiteColumns.difference(actualSiteColumns);
      
      if (missingSiteColumns.isNotEmpty) {
        LoggingService.error('DatabaseHelper: Missing site columns: ${missingSiteColumns.join(', ')}');
        return false;
      }
      
      // Check wings table has all expected columns
      final wingColumns = await db.rawQuery("PRAGMA table_info(wings)");
      final expectedWingColumns = {
        'id', 'name', 'manufacturer', 'model', 'size', 'color', 'purchase_date', 'active', 'notes', 'created_at'
      };
      
      final actualWingColumns = wingColumns.map((col) => col['name'] as String).toSet();
      final missingWingColumns = expectedWingColumns.difference(actualWingColumns);
      
      if (missingWingColumns.isNotEmpty) {
        LoggingService.error('DatabaseHelper: Missing wing columns: ${missingWingColumns.join(', ')}');
        return false;
      }
      
      // Check wing_aliases table has all expected columns
      final wingAliasColumns = await db.rawQuery("PRAGMA table_info(wing_aliases)");
      final expectedWingAliasColumns = {
        'id', 'wing_id', 'alias_name', 'created_at'
      };
      
      final actualWingAliasColumns = wingAliasColumns.map((col) => col['name'] as String).toSet();
      final missingWingAliasColumns = expectedWingAliasColumns.difference(actualWingAliasColumns);
      
      if (missingWingAliasColumns.isNotEmpty) {
        LoggingService.error('DatabaseHelper: Missing wing_aliases columns: ${missingWingAliasColumns.join(', ')}');
        return false;
      }
      
      // Check database version
      final version = await db.getVersion();
      if (version != _databaseVersion) {
        LoggingService.error('DatabaseHelper: Database version mismatch. Expected: $_databaseVersion, Actual: $version');
        return false;
      }
      
      LoggingService.info('DatabaseHelper: Database schema validation successful (v$version)');
      return true;
    } catch (e) {
      LoggingService.error('DatabaseHelper: Schema validation failed', e);
      return false;
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}