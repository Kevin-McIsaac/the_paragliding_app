import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const _databaseName = "FlightLog.db";
  static const _databaseVersion = 1;

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
        landing_site_id INTEGER,
        max_altitude REAL,
        max_climb_rate REAL,
        max_sink_rate REAL,
        distance REAL,
        straight_distance REAL,
        wing_id INTEGER,
        notes TEXT,
        track_log_path TEXT,
        source TEXT CHECK(source IN ('manual', 'igc', 'parajournal')),
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (launch_site_id) REFERENCES sites (id),
        FOREIGN KEY (landing_site_id) REFERENCES sites (id),
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

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}