import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import '../../services/logging_service.dart';
import '../../utils/startup_performance_tracker.dart';

class DatabaseHelper {
  static const _databaseName = "FlightLog.db";
  static const _databaseVersion = 8;

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

    // Create optimized indexes for query performance
    await _createIndexes(db);
  }
  
  /// Create database indexes for optimal query performance
  Future<void> _createIndexes(Database db) async {
    LoggingService.database('INDEX', 'Creating database indexes for performance optimization');
    final perfTracker = StartupPerformanceTracker();
    final indexWatch = perfTracker.startMeasurement('Create All Indexes');
    
    try {
      // Basic indexes for foreign key relationships
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_launch_site ON flights(launch_site_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_wing ON flights(wing_id)');
      
      // Composite index for most common query pattern: ORDER BY date DESC, launch_time DESC
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_date_time ON flights(date DESC, launch_time DESC)');
      
      // Index for fast filename duplicate detection
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_original_filename ON flights(original_filename)');
      
      // Index for date range queries (statistics, filtering)
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_date ON flights(date)');
      
      // Index for created/updated timestamp queries
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_created ON flights(created_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_updated ON flights(updated_at)');
      
      // Statistics query optimization indexes
      await db.execute("CREATE INDEX IF NOT EXISTS idx_flights_year ON flights(strftime('%Y', date))");
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_duration ON flights(duration)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_altitude ON flights(max_altitude)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_distance ON flights(distance)');
      
      // Sites table indexes
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_country ON sites(country)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_name ON sites(name)');
      
      // Wings table indexes  
      await db.execute('CREATE INDEX IF NOT EXISTS idx_wings_active ON wings(active)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_wings_manufacturer ON wings(manufacturer)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_wings_name ON wings(name)');
      
      // Duplicate detection optimization (IGC import)
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_duplicate_check ON flights(date, launch_time)');
      
      LoggingService.database('INDEX', 'Successfully created all database indexes');
      perfTracker.completeMeasurement('Create All Indexes', indexWatch);
    } catch (e) {
      LoggingService.error('DatabaseHelper: Failed to create indexes', e);
      perfTracker.completeMeasurement('Create All Indexes', indexWatch);
      rethrow;
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    LoggingService.database('UPGRADE', 'Upgrading database from version $oldVersion to $newVersion');
    
    if (oldVersion < 2) {
      try {
        // Add 5-second average climb rate columns
        await db.execute('ALTER TABLE flights ADD COLUMN max_climb_rate_5_sec REAL');
        await db.execute('ALTER TABLE flights ADD COLUMN max_sink_rate_5_sec REAL');
        LoggingService.database('MIGRATION', 'Successfully added new climb rate columns');
      } catch (e) {
        LoggingService.database('MIGRATION', 'Error during migration', e);
        // If migration fails, we might need to recreate the database
        rethrow;
      }
    }
    
    if (oldVersion < 3) {
      try {
        // Add timezone column for proper timezone support
        await db.execute('ALTER TABLE flights ADD COLUMN timezone TEXT');
        LoggingService.database('MIGRATION', 'Successfully added timezone column');
      } catch (e) {
        LoggingService.database('MIGRATION', 'Error during timezone migration', e);
        // If migration fails, we might need to recreate the database
        rethrow;
      }
    }
    
    if (oldVersion < 4) {
      try {
        // Add landing coordinate columns and migrate existing landing site data
        await db.execute('ALTER TABLE flights ADD COLUMN landing_latitude REAL');
        await db.execute('ALTER TABLE flights ADD COLUMN landing_longitude REAL');
        await db.execute('ALTER TABLE flights ADD COLUMN landing_altitude REAL');
        await db.execute('ALTER TABLE flights ADD COLUMN landing_description TEXT');
        
        // Migrate existing landing site data to coordinates
        await db.execute('''
          UPDATE flights 
          SET landing_latitude = (SELECT latitude FROM sites WHERE sites.id = flights.landing_site_id),
              landing_longitude = (SELECT longitude FROM sites WHERE sites.id = flights.landing_site_id),
              landing_altitude = (SELECT altitude FROM sites WHERE sites.id = flights.landing_site_id),
              landing_description = (SELECT name FROM sites WHERE sites.id = flights.landing_site_id)
          WHERE landing_site_id IS NOT NULL
        ''');
        
        // Remove landing_site_id column (SQLite doesn't support DROP COLUMN directly)
        // We'll leave it for now to avoid complex table recreation
        // It will be ignored in the new model
        
        LoggingService.database('MIGRATION', 'Successfully migrated to landing coordinates');
      } catch (e) {
        LoggingService.database('MIGRATION', 'Error during landing coordinates migration', e);
        rethrow;
      }
    }
    
    if (oldVersion < 5) {
      try {
        // Add country and state columns to sites table
        await db.execute('ALTER TABLE sites ADD COLUMN country TEXT');
        await db.execute('ALTER TABLE sites ADD COLUMN state TEXT');
        
        LoggingService.database('MIGRATION', 'Successfully added country and state columns to sites table');
      } catch (e) {
        LoggingService.database('MIGRATION', 'Error during country/state migration', e);
        rethrow;
      }
    }
    
    if (oldVersion < 6) {
      try {
        // Remove state column as ParaglidingEarth API doesn't provide region data
        // SQLite doesn't support DROP COLUMN, so we'll recreate the table
        await db.execute('''
          CREATE TABLE sites_new (
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
        
        // Copy data from old table (excluding state column)
        await db.execute('''
          INSERT INTO sites_new (id, name, latitude, longitude, altitude, country, custom_name, created_at)
          SELECT id, name, latitude, longitude, altitude, country, custom_name, created_at FROM sites
        ''');
        
        // Drop old table and rename new table
        await db.execute('DROP TABLE sites');
        await db.execute('ALTER TABLE sites_new RENAME TO sites');
        
        LoggingService.database('MIGRATION', 'Successfully removed state column from sites table');
      } catch (e) {
        LoggingService.database('MIGRATION', 'Error during state column removal', e);
        rethrow;
      }
    }
    
    if (oldVersion < 7) {
      try {
        // Create optimized indexes for better query performance
        await _createIndexes(db);
        LoggingService.database('MIGRATION', 'Successfully created performance indexes');
      } catch (e) {
        LoggingService.database('MIGRATION', 'Error during index creation', e);
        rethrow;
      }
    }
    
    if (oldVersion < 8) {
      try {
        // Add original_filename column for better duplicate detection and traceability
        await db.execute('ALTER TABLE flights ADD COLUMN original_filename TEXT');
        
        // Create index for fast filename-based duplicate detection
        await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_original_filename ON flights(original_filename)');
        
        LoggingService.database('MIGRATION', 'Successfully added original_filename column and index');
      } catch (e) {
        LoggingService.database('MIGRATION', 'Error during original_filename migration', e);
        rethrow;
      }
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