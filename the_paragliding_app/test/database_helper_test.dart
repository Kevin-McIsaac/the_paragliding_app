import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'helpers/test_helpers.dart';

void main() {
  group('DatabaseHelper', () {
    late DatabaseHelper databaseHelper;

    setUpAll(() {
      // Initialize database factory for testing
      TestHelpers.initializeDatabaseForTesting();
    });

    setUp(() {
      databaseHelper = DatabaseHelper.instance;
    });

    test('should create database with correct schema', () async {
      // Get the database instance
      final db = await databaseHelper.database;
      
      // Verify database version
      final version = await db.getVersion();
      expect(version, equals(1));
      
      // Verify all tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
      );
      final tableNames = tables.map((table) => table['name'] as String).toList();
      
      expect(tableNames, containsAll(['flights', 'sites', 'wings', 'wing_aliases']));
    });

    test('should validate database schema successfully', () async {
      // Validate schema
      final isValid = await databaseHelper.validateDatabaseSchema();
      
      expect(isValid, isTrue);
    });

    test('should have all required flights table columns', () async {
      final db = await databaseHelper.database;
      
      // Get flights table column info
      final columns = await db.rawQuery("PRAGMA table_info(flights)");
      final columnNames = columns.map((col) => col['name'] as String).toSet();
      
      // Expected columns from schema
      const expectedColumns = {
        'id', 'date', 'launch_time', 'landing_time', 'duration',
        'launch_site_id', 'launch_latitude', 'launch_longitude', 'launch_altitude',
        'landing_latitude', 'landing_longitude', 'landing_altitude', 'landing_description',
        'max_altitude', 'max_climb_rate', 'max_sink_rate', 'max_climb_rate_5_sec', 'max_sink_rate_5_sec',
        'distance', 'straight_distance', 'fai_triangle_distance', 'fai_triangle_points',
        'wing_id', 'notes', 'track_log_path', 'original_filename', 'source',
        'timezone', 'created_at', 'updated_at',
        'max_ground_speed', 'avg_ground_speed', 'thermal_count', 'avg_thermal_strength',
        'total_time_in_thermals', 'best_thermal', 'best_ld', 'avg_ld', 'longest_glide',
        'climb_percentage', 'gps_fix_quality', 'recording_interval',
        'takeoff_index', 'landing_index', 'detected_takeoff_time', 'detected_landing_time',
        'closing_point_index', 'closing_distance'
      };
      
      expect(columnNames.containsAll(expectedColumns), isTrue,
        reason: 'Missing columns: ${expectedColumns.difference(columnNames)}');
    });

    test('should have all required sites table columns', () async {
      final db = await databaseHelper.database;
      
      // Get sites table column info
      final columns = await db.rawQuery("PRAGMA table_info(sites)");
      final columnNames = columns.map((col) => col['name'] as String).toSet();
      
      const expectedColumns = {
        'id', 'name', 'latitude', 'longitude', 'altitude', 'country', 'custom_name', 'created_at'
      };
      
      expect(columnNames.containsAll(expectedColumns), isTrue,
        reason: 'Missing columns: ${expectedColumns.difference(columnNames)}');
    });

    test('should have all required wings table columns', () async {
      final db = await databaseHelper.database;
      
      // Get wings table column info
      final columns = await db.rawQuery("PRAGMA table_info(wings)");
      final columnNames = columns.map((col) => col['name'] as String).toSet();
      
      const expectedColumns = {
        'id', 'name', 'manufacturer', 'model', 'size', 'color', 
        'purchase_date', 'active', 'notes', 'created_at'
      };
      
      expect(columnNames.containsAll(expectedColumns), isTrue,
        reason: 'Missing columns: ${expectedColumns.difference(columnNames)}');
    });

    test('should have all required wing_aliases table columns', () async {
      final db = await databaseHelper.database;
      
      // Get wing_aliases table column info
      final columns = await db.rawQuery("PRAGMA table_info(wing_aliases)");
      final columnNames = columns.map((col) => col['name'] as String).toSet();
      
      const expectedColumns = {
        'id', 'wing_id', 'alias_name', 'created_at'
      };
      
      expect(columnNames.containsAll(expectedColumns), isTrue,
        reason: 'Missing columns: ${expectedColumns.difference(columnNames)}');
    });

    test('should have all required indexes', () async {
      final db = await databaseHelper.database;
      
      // Get index information
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
      );
      final indexNames = indexes.map((index) => index['name'] as String).toSet();
      
      const expectedIndexes = {
        'idx_flights_launch_site',
        'idx_flights_wing',
        'idx_flights_date_time',
        'idx_wing_aliases_wing_id',
        'idx_wing_aliases_alias_name'
      };
      
      expect(indexNames.containsAll(expectedIndexes), isTrue,
        reason: 'Missing indexes: ${expectedIndexes.difference(indexNames)}');
    });

    test('should have proper foreign key constraints', () async {
      final db = await databaseHelper.database;
      
      // Get foreign key information for flights table
      final flightsForeignKeys = await db.rawQuery("PRAGMA foreign_key_list(flights)");
      
      expect(flightsForeignKeys.length, equals(2));
      
      // Check launch_site_id foreign key
      final siteFk = flightsForeignKeys.firstWhere(
        (fk) => fk['from'] == 'launch_site_id'
      );
      expect(siteFk['table'], equals('sites'));
      expect(siteFk['to'], equals('id'));
      
      // Check wing_id foreign key
      final wingFk = flightsForeignKeys.firstWhere(
        (fk) => fk['from'] == 'wing_id'
      );
      expect(wingFk['table'], equals('wings'));
      expect(wingFk['to'], equals('id'));
      
      // Get foreign key information for wing_aliases table
      final aliasesForeignKeys = await db.rawQuery("PRAGMA foreign_key_list(wing_aliases)");
      
      expect(aliasesForeignKeys.length, equals(1));
      
      final aliasWingFk = aliasesForeignKeys.first;
      expect(aliasWingFk['from'], equals('wing_id'));
      expect(aliasWingFk['table'], equals('wings'));
      expect(aliasWingFk['to'], equals('id'));
    });
    
    tearDown(() async {
      // Clean up database for next test
      await databaseHelper.recreateDatabase();
    });
  });
}