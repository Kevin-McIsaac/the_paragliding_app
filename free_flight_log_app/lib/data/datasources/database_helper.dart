import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const _databaseName = "FlightLog.db";
  static const _databaseVersion = 4;

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
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

    await db.execute('CREATE INDEX idx_flights_date ON flights(date)');
    await db.execute('CREATE INDEX idx_flights_launch_site ON flights(launch_site_id)');
    await db.execute('CREATE INDEX idx_flights_wing ON flights(wing_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('Upgrading database from version $oldVersion to $newVersion');
    
    if (oldVersion < 2) {
      try {
        // Add 5-second average climb rate columns
        await db.execute('ALTER TABLE flights ADD COLUMN max_climb_rate_5_sec REAL');
        await db.execute('ALTER TABLE flights ADD COLUMN max_sink_rate_5_sec REAL');
        print('Successfully added new climb rate columns');
      } catch (e) {
        print('Error during migration: $e');
        // If migration fails, we might need to recreate the database
        throw e;
      }
    }
    
    if (oldVersion < 3) {
      try {
        // Add timezone column for proper timezone support
        await db.execute('ALTER TABLE flights ADD COLUMN timezone TEXT');
        print('Successfully added timezone column');
      } catch (e) {
        print('Error during timezone migration: $e');
        // If migration fails, we might need to recreate the database
        throw e;
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
        
        print('Successfully migrated to landing coordinates');
      } catch (e) {
        print('Error during landing coordinates migration: $e');
        throw e;
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

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}