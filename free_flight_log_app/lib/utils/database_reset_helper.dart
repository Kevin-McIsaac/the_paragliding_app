import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../data/datasources/database_helper.dart';
import '../services/logging_service.dart';
import '../services/igc_import_service.dart';

/// Helper class for resetting/clearing database data
/// Can be called from within the Flutter app
class DatabaseResetHelper {
  static final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  /// Reset the entire database - removes all data and recreates tables
  static Future<Map<String, dynamic>> resetDatabase() async {
    try {
      LoggingService.info('DatabaseResetHelper: Resetting database...');
      
      // Get current database info before reset
      final db = await _databaseHelper.database;
      final path = db.path;
      
      final flightCount = await _getTableCount('flights');
      final siteCount = await _getTableCount('sites');
      final wingCount = await _getTableCount('wings');
      
      LoggingService.info('DatabaseResetHelper: Removing $flightCount flights, $siteCount sites, $wingCount wings');
      
      // Close the database connection
      await db.close();
      
      // Delete the database file
      final dbFile = File(path);
      if (await dbFile.exists()) {
        await dbFile.delete();
        LoggingService.info('DatabaseResetHelper: Database file deleted');
      }
      
      // Recreate the database (this will run the onCreate method)
      LoggingService.info('DatabaseResetHelper: Recreating database with fresh schema...');
      await _databaseHelper.recreateDatabase();
      await _databaseHelper.database;
      
      // Verify the new database is empty
      final newFlightCount = await _getTableCount('flights');
      final newSiteCount = await _getTableCount('sites');
      final newWingCount = await _getTableCount('wings');
      
      LoggingService.info('DatabaseResetHelper: Database reset complete!');
      LoggingService.info('DatabaseResetHelper: New database: $newFlightCount flights, $newSiteCount sites, $newWingCount wings');
      
      return {
        'success': true,
        'message': 'Database reset successfully',
        'before': {
          'flights': flightCount,
          'sites': siteCount,
          'wings': wingCount,
          'total': flightCount + siteCount + wingCount,
        },
        'after': {
          'flights': newFlightCount,
          'sites': newSiteCount,
          'wings': newWingCount,
          'total': newFlightCount + newSiteCount + newWingCount,
        },
      };
      
    } catch (e) {
      LoggingService.error('DatabaseResetHelper: Error resetting database', e);
      return {
        'success': false,
        'message': 'Error resetting database: $e',
      };
    }
  }

  /// Recreate database from existing IGC files
  /// This will reset the database and reimport all IGC files found on device
  static Future<Map<String, dynamic>> recreateDatabaseFromIGCFiles({
    Function(String, int, int)? onProgress,
  }) async {
    try {
      LoggingService.info('DatabaseResetHelper: Recreating database from IGC files...');
      
      // First, find all IGC files before we reset the database
      final igcFiles = await _findAllIGCFiles();
      final totalFiles = igcFiles.length;
      
      LoggingService.info('DatabaseResetHelper: Found $totalFiles IGC files to process');
      
      if (totalFiles == 0) {
        return {
          'success': false,
          'message': 'No IGC files found to recreate database from',
          'found': 0,
          'imported': 0,
          'failed': 0,
          'errors': <String>[],
        };
      }
      
      // Reset the database first
      final resetResult = await resetDatabase();
      if (!resetResult['success']) {
        return {
          'success': false,
          'message': 'Failed to reset database: ${resetResult['message']}',
          'found': totalFiles,
          'imported': 0,
          'failed': 0,
          'errors': [resetResult['message']],
        };
      }
      
      LoggingService.info('DatabaseResetHelper: Database reset complete, now importing IGC files...');
      
      // Import each IGC file
      final importService = IgcImportService.instance;
      int imported = 0;
      int failed = 0;
      final errors = <String>[];
      
      for (int i = 0; i < igcFiles.length; i++) {
        final file = igcFiles[i];
        final filename = file.path.split('/').last;
        
        // Call progress callback if provided
        onProgress?.call(filename, i + 1, totalFiles);
        
        try {
          LoggingService.debug('DatabaseResetHelper: Importing ${i + 1}/$totalFiles: $filename');
          
          await importService.importIgcFileWithoutCopy(file.path);
          imported++;
          
          LoggingService.debug('DatabaseResetHelper: Successfully imported $filename');
          
        } catch (e) {
          failed++;
          final errorMsg = '$filename: $e';
          errors.add(errorMsg);
          LoggingService.warning('DatabaseResetHelper: Failed to import $filename: $e');
        }
      }
      
      LoggingService.info('DatabaseResetHelper: Import complete - $imported successful, $failed failed');
      
      return {
        'success': true,
        'message': 'Database recreated successfully! Imported $imported flights from $totalFiles IGC files' + 
                  (failed > 0 ? '. $failed files failed to import.' : '.'),
        'found': totalFiles,
        'imported': imported,
        'failed': failed,
        'errors': errors,
      };
      
    } catch (e) {
      LoggingService.error('DatabaseResetHelper: Error recreating database from IGC files', e);
      return {
        'success': false,
        'message': 'Error recreating database from IGC files: $e',
        'found': 0,
        'imported': 0,
        'failed': 0,
        'errors': [e.toString()],
      };
    }
  }

  /// Find all IGC files in app directories
  static Future<List<File>> _findAllIGCFiles() async {
    final List<File> igcFiles = [];
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      
      // IGC file locations used by this app
      final igcDirectories = [
        'igc_tracks',        // Primary location
        'igc_files',         // Legacy location
        'imported_igc',      // Alternative location
        'flight_tracks',     // Alternative location
      ];
      
      // Check root documents directory
      final rootFiles = await appDir
          .list()
          .where((entity) => entity is File && 
                 entity.path.toLowerCase().endsWith('.igc'))
          .cast<File>()
          .toList();
      igcFiles.addAll(rootFiles);
      
      // Check subdirectories
      for (final dirName in igcDirectories) {
        final dir = Directory('${appDir.path}/$dirName');
        
        if (await dir.exists()) {
          final files = await dir
              .list()
              .where((entity) => entity is File && 
                     entity.path.toLowerCase().endsWith('.igc'))
              .cast<File>()
              .toList();
          igcFiles.addAll(files);
        }
      }
      
    } catch (e) {
      LoggingService.error('DatabaseResetHelper: Error finding IGC files', e);
    }
    
    return igcFiles;
  }
  
  /// Clear all flight data (keep sites and wings)
  static Future<Map<String, dynamic>> clearAllFlights() async {
    try {
      LoggingService.info('DatabaseResetHelper: Clearing all flights...');
      
      final db = await _databaseHelper.database;
      final flightCount = await _getTableCount('flights');
      
      if (flightCount == 0) {
        return {
          'success': true,
          'message': 'No flights to delete',
          'deleted': 0,
        };
      }
      
      // Delete all flights
      final deletedCount = await db.delete('flights');
      
      LoggingService.info('DatabaseResetHelper: Cleared $deletedCount flights');
      
      return {
        'success': true,
        'message': 'Cleared $deletedCount flights',
        'deleted': deletedCount,
      };
      
    } catch (e) {
      LoggingService.error('DatabaseResetHelper: Error clearing flights', e);
      return {
        'success': false,
        'message': 'Error clearing flights: $e',
      };
    }
  }
  
  /// Clear all site data (may fail if referenced by flights)
  static Future<Map<String, dynamic>> clearAllSites() async {
    try {
      LoggingService.info('DatabaseResetHelper: Clearing all sites...');
      
      final db = await _databaseHelper.database;
      final siteCount = await _getTableCount('sites');
      
      if (siteCount == 0) {
        return {
          'success': true,
          'message': 'No sites to delete',
          'deleted': 0,
        };
      }
      
      try {
        final deletedCount = await db.delete('sites');
        LoggingService.info('DatabaseResetHelper: Cleared $deletedCount sites');
        
        return {
          'success': true,
          'message': 'Cleared $deletedCount sites',
          'deleted': deletedCount,
        };
      } catch (e) {
        return {
          'success': false,
          'message': 'Cannot delete sites - they are referenced by existing flights. Delete flights first.',
        };
      }
      
    } catch (e) {
      LoggingService.error('DatabaseResetHelper: Error clearing sites', e);
      return {
        'success': false,
        'message': 'Error clearing sites: $e',
      };
    }
  }
  
  /// Clear all wing data (may fail if referenced by flights)
  static Future<Map<String, dynamic>> clearAllWings() async {
    try {
      LoggingService.info('DatabaseResetHelper: Clearing all wings...');
      
      final db = await _databaseHelper.database;
      final wingCount = await _getTableCount('wings');
      
      if (wingCount == 0) {
        return {
          'success': true,
          'message': 'No wings to delete',
          'deleted': 0,
        };
      }
      
      try {
        final deletedCount = await db.delete('wings');
        LoggingService.info('DatabaseResetHelper: Cleared $deletedCount wings');
        
        return {
          'success': true,
          'message': 'Cleared $deletedCount wings',
          'deleted': deletedCount,
        };
      } catch (e) {
        return {
          'success': false,
          'message': 'Cannot delete wings - they are referenced by existing flights. Delete flights first.',
        };
      }
      
    } catch (e) {
      LoggingService.error('DatabaseResetHelper: Error clearing wings', e);
      return {
        'success': false,
        'message': 'Error clearing wings: $e',
      };
    }
  }
  
  /// Get database statistics
  static Future<Map<String, dynamic>> getDatabaseStats() async {
    try {
      final db = await _databaseHelper.database;
      
      final flightCount = await _getTableCount('flights');
      final siteCount = await _getTableCount('sites');
      final wingCount = await _getTableCount('wings');
      
      // Get database file size
      final dbFile = File(db.path);
      int sizeBytes = 0;
      if (await dbFile.exists()) {
        sizeBytes = await dbFile.length();
      }
      
      return {
        'path': db.path,
        'version': await _getDatabaseVersion(db),
        'flights': flightCount,
        'sites': siteCount,
        'wings': wingCount,
        'total_records': flightCount + siteCount + wingCount,
        'size_bytes': sizeBytes,
        'size_kb': (sizeBytes / 1024).toStringAsFixed(1),
      };
      
    } catch (e) {
      return {
        'error': 'Error getting database stats: $e',
      };
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
  
  /// Initialize a fresh database (call this after reset if needed)
  static Future<void> initializeFreshDatabase() async {
    try {
      LoggingService.info('DatabaseResetHelper: Initializing fresh database...');
      
      // This will ensure the database is created with the latest schema
      final db = await _databaseHelper.database;
      final version = await _getDatabaseVersion(db);
      
      LoggingService.info('DatabaseResetHelper: Database initialized with version $version');
      
    } catch (e) {
      LoggingService.error('DatabaseResetHelper: Error initializing database', e);
      rethrow;
    }
  }

  /// Get the actual database version from the database
  static Future<int> _getDatabaseVersion(Database db) async {
    try {
      final result = await db.rawQuery('PRAGMA user_version');
      return result.first['user_version'] as int;
    } catch (e) {
      LoggingService.error('DatabaseResetHelper: Error getting database version', e);
      return 0;
    }
  }
}