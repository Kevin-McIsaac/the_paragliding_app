import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import '../../services/logging_service.dart';
import '../../utils/startup_performance_tracker.dart';

class DatabaseHelper {
  static const _databaseName = "FlightLog.db";
  static const _databaseVersion = 10; // Added wing aliases support

  // Singleton pattern
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    final perfTracker = StartupPerformanceTracker();
    
    final pathWatch = perfTracker.startMeasurement('Get Database Path');
    String path = join(await getDatabasesPath(), _databaseName);
    perfTracker.completeMeasurement('Get Database Path', pathWatch);
    
    LoggingService.database('INIT', 'Opening database at: $path');
    
    final openWatch = perfTracker.startMeasurement('Open Database');
    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        final createWatch = perfTracker.startMeasurement('Create Database Schema');
        await _onCreate(db, version);
        perfTracker.completeMeasurement('Create Database Schema', createWatch);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        final upgradeWatch = perfTracker.startMeasurement('Upgrade Database');
        await _onUpgrade(db, oldVersion, newVersion);
        perfTracker.completeMeasurement('Upgrade Database', upgradeWatch);
      },
    );
    perfTracker.completeMeasurement('Open Database', openWatch);
    
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
        wing_id INTEGER,
        notes TEXT,
        track_log_path TEXT,
        original_filename TEXT,
        source TEXT CHECK(source IN ('manual', 'igc', 'parajournal')),
        timezone TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
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
    LoggingService.database('INDEX', 'Creating ONLY essential indexes (reduced from 18 to 3)');
    final perfTracker = StartupPerformanceTracker();
    final indexWatch = perfTracker.startMeasurement('Create Essential Indexes');
    
    try {
      // ONLY 3 ESSENTIAL INDEXES for <5000 records
      // Removed 14 unnecessary indexes that were adding overhead with minimal benefit
      
      // 1. Foreign key index for launch site joins (used in almost every query)
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_launch_site ON flights(launch_site_id)');
      
      // 2. Foreign key index for wing joins
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_wing ON flights(wing_id)');
      
      // 3. Composite index for most common query pattern: ORDER BY date DESC, launch_time DESC
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_date_time ON flights(date DESC, launch_time DESC)');
      
      // 4. Index for wing aliases lookup
      await db.execute('CREATE INDEX IF NOT EXISTS idx_wing_aliases_wing_id ON wing_aliases(wing_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_wing_aliases_alias_name ON wing_aliases(alias_name)');
      
      LoggingService.database('INDEX', 'Successfully created essential indexes');
      perfTracker.completeMeasurement('Create Essential Indexes', indexWatch);
    } catch (e) {
      LoggingService.error('DatabaseHelper: Failed to create indexes', e);
      perfTracker.completeMeasurement('Create Essential Indexes', indexWatch);
      rethrow;
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    LoggingService.database('UPGRADE', 'Upgrading database from version $oldVersion to $newVersion');
    
    // SIMPLIFIED MIGRATION for v9: Just optimize indexes
    // All previous migrations (v1-8) stay applied, we're just removing unnecessary indexes
    if (oldVersion < 9) {
      try {
        LoggingService.database('MIGRATION', 'Optimizing database - reducing indexes from 18 to 3');
        
        // Drop all unnecessary indexes (data remains intact)
        final indexesToDrop = [
          'idx_flights_original_filename',
          'idx_flights_date',
          'idx_flights_created',
          'idx_flights_updated',
          'idx_flights_year',
          'idx_flights_duration',
          'idx_flights_altitude',
          'idx_flights_distance',
          'idx_sites_country',
          'idx_sites_name',
          'idx_wings_active',
          'idx_wings_manufacturer',
          'idx_wings_name',
          'idx_flights_duplicate_check',
        ];
        
        for (final index in indexesToDrop) {
          try {
            await db.execute('DROP INDEX IF EXISTS $index');
          } catch (e) {
            // Ignore if index doesn't exist
          }
        }
        
        // Ensure only essential indexes exist
        await _createIndexes(db);
        
        LoggingService.database('MIGRATION', 'Successfully optimized database - reduced to 3 essential indexes');
      } catch (e) {
        LoggingService.error('DatabaseHelper: Index optimization failed', e);
        // Non-critical - app can continue with existing indexes
      }
    }
    
    // Migration for v10: Add wing aliases support
    if (oldVersion < 10) {
      try {
        LoggingService.database('MIGRATION', 'Adding wing aliases support');
        
        // Create wing_aliases table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS wing_aliases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            wing_id INTEGER NOT NULL,
            alias_name TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (wing_id) REFERENCES wings (id) ON DELETE CASCADE,
            UNIQUE(alias_name)
          )
        ''');
        
        // Create indexes for wing aliases
        await db.execute('CREATE INDEX IF NOT EXISTS idx_wing_aliases_wing_id ON wing_aliases(wing_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_wing_aliases_alias_name ON wing_aliases(alias_name)');
        
        LoggingService.database('MIGRATION', 'Successfully added wing aliases support');
      } catch (e) {
        LoggingService.error('DatabaseHelper: Failed to add wing aliases', e);
        rethrow; // This is important for data integrity
      }
    }
    
    LoggingService.database('UPGRADE', 'Database upgrade complete');
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
        'launch_site_id', 'landing_latitude', 'landing_longitude', 'landing_altitude', 'landing_description',
        'max_altitude', 'max_climb_rate', 'max_sink_rate', 'max_climb_rate_5_sec', 'max_sink_rate_5_sec',
        'distance', 'straight_distance', 'wing_id', 'notes', 'created_at', 'updated_at', 'timezone'
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