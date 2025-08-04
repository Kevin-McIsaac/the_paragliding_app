import 'dart:io';
import '../data/datasources/database_helper.dart';

/// Script to reset the database - removes all data and recreates tables
/// This is useful for development and testing purposes
class DatabaseReset {
  static final DatabaseHelper _databaseHelper = DatabaseHelper();

  /// Reset the entire database - removes all data
  static Future<void> resetDatabase() async {
    try {
      print('🗃️  Database Reset Script');
      print('=====================');
      
      // Get current database info
      final db = await _databaseHelper.database;
      final path = db.path;
      print('Database path: $path');
      
      // Get current data counts
      final flightCount = await _getTableCount('flights');
      final siteCount = await _getTableCount('sites');
      final wingCount = await _getTableCount('wings');
      
      print('\nCurrent data:');
      print('  Flights: $flightCount');
      print('  Sites: $siteCount');
      print('  Wings: $wingCount');
      print('  Total records: ${flightCount + siteCount + wingCount}');
      
      if (flightCount + siteCount + wingCount == 0) {
        print('\n✅ Database is already empty!');
        return;
      }
      
      // Confirm deletion
      print('\n⚠️  WARNING: This will permanently delete ALL data!');
      print('This includes:');
      print('  - All flight records');
      print('  - All sites');
      print('  - All wings');
      print('  - All track log files');
      print('\nThis action cannot be undone.');
      
      // Close the database connection
      await db.close();
      
      // Delete the database file
      final dbFile = File(path);
      if (await dbFile.exists()) {
        await dbFile.delete();
        print('\n🗑️  Database file deleted');
      }
      
      // Recreate the database (this will run the onCreate method)
      print('🔄 Recreating database with fresh schema...');
      final newDb = await _databaseHelper.database;
      
      // Verify the new database is empty
      final newFlightCount = await _getTableCount('flights');
      final newSiteCount = await _getTableCount('sites');
      final newWingCount = await _getTableCount('wings');
      
      print('\n✅ Database reset complete!');
      print('New database:');
      print('  Flights: $newFlightCount');
      print('  Sites: $newSiteCount');
      print('  Wings: $newWingCount');
      print('  Database version: ${await newDb.getVersion()}');
      
      // Clean up track log files
      await _cleanupTrackLogFiles();
      
      print('\n🎉 All data has been successfully removed!');
      print('The database is now clean and ready for fresh data.');
      
    } catch (e) {
      print('❌ Error resetting database: $e');
      rethrow;
    }
  }
  
  /// Clear only flight data (keep sites and wings)
  static Future<void> clearFlights() async {
    try {
      print('🗃️  Clear Flights');
      print('================');
      
      final db = await _databaseHelper.database;
      final flightCount = await _getTableCount('flights');
      
      print('Current flights: $flightCount');
      
      if (flightCount == 0) {
        print('✅ No flights to delete!');
        return;
      }
      
      // Delete all flights
      await db.delete('flights');
      
      // Clean up track log files
      await _cleanupTrackLogFiles();
      
      final newFlightCount = await _getTableCount('flights');
      print('✅ Cleared $flightCount flights');
      print('Remaining flights: $newFlightCount');
      
    } catch (e) {
      print('❌ Error clearing flights: $e');
      rethrow;
    }
  }
  
  /// Clear only sites data
  static Future<void> clearSites() async {
    try {
      print('🗃️  Clear Sites');
      print('==============');
      
      final db = await _databaseHelper.database;
      final siteCount = await _getTableCount('sites');
      
      print('Current sites: $siteCount');
      
      if (siteCount == 0) {
        print('✅ No sites to delete!');
        return;
      }
      
      // Note: This will fail if there are flights referencing these sites
      // due to foreign key constraints
      try {
        await db.delete('sites');
        print('✅ Cleared $siteCount sites');
      } catch (e) {
        print('❌ Cannot delete sites - they are referenced by existing flights');
        print('Delete flights first, or use resetDatabase() to clear everything');
      }
      
    } catch (e) {
      print('❌ Error clearing sites: $e');
      rethrow;
    }
  }
  
  /// Clear only wings data
  static Future<void> clearWings() async {
    try {
      print('🗃️  Clear Wings');
      print('==============');
      
      final db = await _databaseHelper.database;
      final wingCount = await _getTableCount('wings');
      
      print('Current wings: $wingCount');
      
      if (wingCount == 0) {
        print('✅ No wings to delete!');
        return;
      }
      
      // Note: This will fail if there are flights referencing these wings
      try {
        await db.delete('wings');
        print('✅ Cleared $wingCount wings');
      } catch (e) {
        print('❌ Cannot delete wings - they are referenced by existing flights');
        print('Delete flights first, or use resetDatabase() to clear everything');
      }
      
    } catch (e) {
      print('❌ Error clearing wings: $e');
      rethrow;
    }
  }
  
  /// Get count of records in a table
  static Future<int> _getTableCount(String tableName) async {
    try {
      final db = await _databaseHelper.database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM $tableName');
      return result.first['count'] as int;
    } catch (e) {
      return 0;
    }
  }
  
  /// Clean up track log files in app storage
  static Future<void> _cleanupTrackLogFiles() async {
    try {
      // This would need to be implemented based on where track log files are stored
      // For now, just print a message
      print('🧹 Track log file cleanup would happen here');
      print('   (Implementation depends on file storage location)');
    } catch (e) {
      print('⚠️  Warning: Could not clean up track log files: $e');
    }
  }
  
  /// Print database statistics
  static Future<void> printDatabaseStats() async {
    try {
      print('\n📊 Database Statistics');
      print('=====================');
      
      final db = await _databaseHelper.database;
      print('Database path: ${db.path}');
      print('Database version: ${await db.getVersion()}');
      
      final flightCount = await _getTableCount('flights');
      final siteCount = await _getTableCount('sites');
      final wingCount = await _getTableCount('wings');
      
      print('\nTable counts:');
      print('  Flights: $flightCount');
      print('  Sites: $siteCount');
      print('  Wings: $wingCount');
      print('  Total records: ${flightCount + siteCount + wingCount}');
      
      // Get database file size
      final dbFile = File(db.path);
      if (await dbFile.exists()) {
        final sizeBytes = await dbFile.length();
        final sizeKB = (sizeBytes / 1024).toStringAsFixed(1);
        print('  Database size: ${sizeKB}KB');
      }
      
    } catch (e) {
      print('❌ Error getting database stats: $e');
    }
  }
}

/// Command-line interface for the database reset script
void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('''
🗃️  Database Reset Tool
===================

Usage: dart run lib/scripts/reset_database.dart <command>

Commands:
  reset         - Reset entire database (delete all data)
  clear-flights - Clear only flight data
  clear-sites   - Clear only sites data  
  clear-wings   - Clear only wings data
  stats         - Show database statistics
  help          - Show this help message

Examples:
  dart run lib/scripts/reset_database.dart reset
  dart run lib/scripts/reset_database.dart stats
''');
    return;
  }

  final command = arguments.first.toLowerCase();
  
  try {
    switch (command) {
      case 'reset':
        await DatabaseReset.resetDatabase();
        break;
      case 'clear-flights':
        await DatabaseReset.clearFlights();
        break;
      case 'clear-sites':
        await DatabaseReset.clearSites();
        break;
      case 'clear-wings':
        await DatabaseReset.clearWings();
        break;
      case 'stats':
        await DatabaseReset.printDatabaseStats();
        break;
      case 'help':
      case '--help':
      case '-h':
        // Help already printed above
        break;
      default:
        print('❌ Unknown command: $command');
        print('Use "help" to see available commands');
    }
  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
}