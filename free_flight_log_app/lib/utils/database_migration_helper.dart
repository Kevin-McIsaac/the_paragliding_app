import 'package:sqflite/sqflite.dart';
import '../data/datasources/database_helper.dart';

/// Utility class to help with database migration issues
class DatabaseMigrationHelper {
  static final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  /// Check if the database has the new climb rate columns
  static Future<bool> hasNewClimbRateColumns() async {
    try {
      final db = await _databaseHelper.database;
      
      // Try to query with the new columns
      await db.rawQuery('''
        SELECT max_climb_rate_5_sec, max_sink_rate_5_sec 
        FROM flights 
        LIMIT 1
      ''');
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Manually add the new columns if they don't exist
  static Future<void> addMissingColumns() async {
    try {
      final db = await _databaseHelper.database;
      
      // Check if columns exist first
      final hasColumns = await hasNewClimbRateColumns();
      if (hasColumns) {
        print('Columns already exist');
        return;
      }

      print('Adding missing climb rate columns...');
      
      await db.execute('ALTER TABLE flights ADD COLUMN max_climb_rate_5_sec REAL');
      await db.execute('ALTER TABLE flights ADD COLUMN max_sink_rate_5_sec REAL');
      
      print('Successfully added missing columns');
    } catch (e) {
      print('Error adding columns: $e');
      throw e;
    }
  }

  /// Force recreate the database (WARNING: This will delete all data!)
  static Future<void> recreateDatabase() async {
    print('WARNING: Recreating database - all data will be lost!');
    await _databaseHelper.recreateDatabase();
    print('Database recreated successfully');
  }

  /// Check database schema and attempt to fix any issues
  static Future<void> checkAndFixDatabase() async {
    try {
      final hasColumns = await hasNewClimbRateColumns();
      
      if (!hasColumns) {
        print('Missing climb rate columns. Attempting to add them...');
        await addMissingColumns();
      } else {
        print('Database schema is up to date');
      }
    } catch (e) {
      print('Schema check failed: $e');
      print('Consider running recreateDatabase() if you can afford to lose data');
    }
  }
}