import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../utils/database_migration_helper.dart';

/// Simple script to fix database migration issues
/// Run this if you're getting column not found errors
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize sqflite for desktop platforms
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  print('=== Database Migration Fix Tool ===');
  print('');
  
  try {
    print('Checking database schema...');
    await DatabaseMigrationHelper.checkAndFixDatabase();
    print('');
    print('✅ Database schema check completed!');
    
  } catch (e) {
    print('');
    print('❌ Error during database fix: $e');
    print('');
    print('If the error persists, you may need to recreate the database.');
    print('WARNING: This will delete all existing flight data!');
    print('');
    print('To recreate the database, run:');
    print('await DatabaseMigrationHelper.recreateDatabase();');
  }
}