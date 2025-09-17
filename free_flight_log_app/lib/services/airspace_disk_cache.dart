import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../services/logging_service.dart';
import '../data/models/airspace_cache_models.dart';

class AirspaceDiskCache {
  static const String _databaseName = 'airspace_cache.db';
  static const int _databaseVersion = 1;

  static const String _geometryTable = 'airspace_geometries';
  static const String _metadataTable = 'tile_metadata';
  static const String _statisticsTable = 'cache_statistics';

  // Size limits
  static const int maxDatabaseSizeMB = 100; // Maximum database size in MB
  static const int cleanupBatchSize = 50; // Number of entries to delete per cleanup

  Database? _database;
  static AirspaceDiskCache? _instance;
  String? _databasePath;

  AirspaceDiskCache._internal();

  static AirspaceDiskCache get instance {
    _instance ??= AirspaceDiskCache._internal();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    _databasePath = path;

    LoggingService.info('Initializing airspace cache database at: $path');

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onOpen: _onOpen,
    );
  }

  Future<void> _onOpen(Database db) async {
    // Configure database after opening
    try {
      // Use rawQuery for PRAGMA commands on Android
      await db.rawQuery('PRAGMA page_size = 4096');
      await db.rawQuery('PRAGMA cache_size = -2000'); // 2MB cache
      await db.rawQuery('PRAGMA journal_mode = WAL');
      await db.rawQuery('PRAGMA synchronous = NORMAL');
    } catch (e) {
      // If PRAGMA commands fail, continue anyway - they're optimizations
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    LoggingService.info('Creating airspace cache tables');

    // Geometry table with compressed data
    await db.execute('''
      CREATE TABLE $_geometryTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        compressed_data BLOB NOT NULL,
        properties TEXT,
        fetch_time INTEGER NOT NULL,
        geometry_hash TEXT NOT NULL,
        compressed_size INTEGER,
        uncompressed_size INTEGER,
        access_count INTEGER DEFAULT 0,
        last_accessed INTEGER
      )
    ''');

    // Tile metadata table
    await db.execute('''
      CREATE TABLE $_metadataTable (
        tile_key TEXT PRIMARY KEY,
        airspace_ids TEXT NOT NULL,
        fetch_time INTEGER NOT NULL,
        airspace_count INTEGER NOT NULL,
        is_empty INTEGER NOT NULL,
        statistics TEXT,
        access_count INTEGER DEFAULT 0,
        last_accessed INTEGER
      )
    ''');

    // Statistics table
    await db.execute('''
      CREATE TABLE $_statisticsTable (
        id INTEGER PRIMARY KEY,
        stats_json TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    // Create indices for performance
    await db.execute('CREATE INDEX idx_geometry_type ON $_geometryTable(type)');
    await db.execute('CREATE INDEX idx_geometry_fetch_time ON $_geometryTable(fetch_time)');
    await db.execute('CREATE INDEX idx_metadata_fetch_time ON $_metadataTable(fetch_time)');
    await db.execute('CREATE INDEX idx_metadata_empty ON $_metadataTable(is_empty)');
  }

  // Compression utilities
  Uint8List _compress(String data) {
    final bytes = utf8.encode(data);
    return gzip.encode(bytes) as Uint8List;
  }

  String _decompress(Uint8List compressed) {
    final bytes = gzip.decode(compressed);
    return utf8.decode(bytes);
  }

  // Geometry cache operations
  Future<void> putGeometry(CachedAirspaceGeometry geometry) async {
    // Check database size before inserting
    await _enforceSizeLimit();

    final db = await database;
    final stopwatch = Stopwatch()..start();

    try {
      final json = jsonEncode(geometry.toJson());
      final compressed = _compress(json);
      final uncompressedSize = utf8.encode(json).length;

      await db.insert(
        _geometryTable,
        {
          'id': geometry.id,
          'name': geometry.name,
          'type': geometry.typeCode.toString(),  // Store typeCode as string for DB
          'compressed_data': compressed,
          'properties': jsonEncode(geometry.properties),
          'fetch_time': geometry.fetchTime.millisecondsSinceEpoch,
          'geometry_hash': geometry.geometryHash,
          'compressed_size': compressed.length,
          'uncompressed_size': uncompressedSize,
          'last_accessed': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Only log slow operations
      if (stopwatch.elapsedMilliseconds > 50) {
        LoggingService.performance(
          'Stored airspace geometry',
          stopwatch.elapsed,
          'id=${geometry.id}, compressed=${compressed.length}, ratio=${(1 - compressed.length / uncompressedSize).toStringAsFixed(2)}',
        );
      }
    } catch (e, stack) {
      LoggingService.error('Failed to store geometry', e, stack);
      rethrow;
    }
  }

  /// Check which IDs already exist in the cache (batch operation)
  Future<Set<String>> getExistingIds(List<String> ids) async {
    if (ids.isEmpty) return {};

    final db = await database;
    final stopwatch = Stopwatch()..start();

    try {
      // Build placeholders for SQL IN clause
      final placeholders = ids.map((_) => '?').join(',');

      final results = await db.query(
        _geometryTable,
        columns: ['id'],
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );

      final existingIds = results.map((row) => row['id'] as String).toSet();

      LoggingService.info(
        '[BATCH_ID_CHECK] Checked ${ids.length} IDs, found ${existingIds.length} existing in ${stopwatch.elapsedMilliseconds}ms'
      );

      return existingIds;
    } catch (e, stack) {
      LoggingService.error('Failed to check existing IDs', e, stack);
      return {};
    }
  }

  Future<CachedAirspaceGeometry?> getGeometry(String id) async {
    final db = await database;
    final stopwatch = Stopwatch()..start();

    try {
      final results = await db.query(
        _geometryTable,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (results.isEmpty) {
        return null;
      }

      final row = results.first;
      final compressed = row['compressed_data'] as Uint8List;
      final json = _decompress(compressed);
      final geometry = CachedAirspaceGeometry.fromJson(jsonDecode(json));

      // REMOVED: Real-time access tracking to improve performance
      // Access tracking is now deferred to batch operations

      // Only log slow operations
      if (stopwatch.elapsedMilliseconds > 50) {
        LoggingService.performance(
          'Retrieved airspace geometry',
          stopwatch.elapsed,
          'id=$id, size=${compressed.length}',
        );
      }

      return geometry;
    } catch (e, stack) {
      LoggingService.error('Failed to retrieve geometry', e, stack);
      return null;
    }
  }

  Future<List<CachedAirspaceGeometry>> getGeometries(Set<String> ids) async {
    if (ids.isEmpty) return [];

    final db = await database;
    final stopwatch = Stopwatch()..start();
    final geometries = <CachedAirspaceGeometry>[];

    try {
      final placeholders = ids.map((_) => '?').join(',');
      final results = await db.query(
        _geometryTable,
        where: 'id IN ($placeholders)',
        whereArgs: ids.toList(),
      );

      for (final row in results) {
        try {
          final compressed = row['compressed_data'] as Uint8List;
          final json = _decompress(compressed);
          geometries.add(CachedAirspaceGeometry.fromJson(jsonDecode(json)));
        } catch (e) {
          LoggingService.error('Failed to parse geometry: ${row['id']}', e, null);
        }
      }

      // REMOVED: Batch access statistics update for performance
      // Access tracking is now deferred or eliminated

      // Always log batch operations
      LoggingService.performance(
        'Retrieved multiple geometries',
        stopwatch.elapsed,
        'requested=${ids.length}, found=${geometries.length}',
      );

      return geometries;
    } catch (e, stack) {
      LoggingService.error('Failed to retrieve geometries', e, stack);
      return [];
    }
  }

  // Tile metadata operations
  Future<void> putTileMetadata(TileMetadata metadata) async {
    final db = await database;

    try {
      await db.insert(
        _metadataTable,
        {
          'tile_key': metadata.tileKey,
          'airspace_ids': jsonEncode(metadata.airspaceIds.toList()),
          'fetch_time': metadata.fetchTime.millisecondsSinceEpoch,
          'airspace_count': metadata.airspaceCount,
          'is_empty': metadata.isEmpty ? 1 : 0,
          'statistics': metadata.statistics != null
              ? jsonEncode(metadata.statistics)
              : null,
          'last_accessed': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, stack) {
      LoggingService.error('Failed to store tile metadata', e, stack);
    }
  }

  Future<TileMetadata?> getTileMetadata(String tileKey) async {
    final db = await database;

    try {
      final results = await db.query(
        _metadataTable,
        where: 'tile_key = ?',
        whereArgs: [tileKey],
        limit: 1,
      );

      if (results.isEmpty) return null;

      final row = results.first;
      final metadata = TileMetadata(
        tileKey: row['tile_key'] as String,
        airspaceIds: Set<String>.from(
          jsonDecode(row['airspace_ids'] as String) as List,
        ),
        fetchTime: DateTime.fromMillisecondsSinceEpoch(
          row['fetch_time'] as int,
        ),
        airspaceCount: row['airspace_count'] as int,
        isEmpty: (row['is_empty'] as int) == 1,
        statistics: row['statistics'] != null
            ? jsonDecode(row['statistics'] as String)
            : null,
      );

      // REMOVED: Real-time access tracking to improve performance
      // Access tracking is now deferred to batch operations
      // The last_accessed field is still used for cleanup based on fetch_time

      return metadata;
    } catch (e, stack) {
      LoggingService.error('Failed to retrieve tile metadata', e, stack);
      return null;
    }
  }

  /// Batch retrieve multiple tile metadata in a single query
  Future<Map<String, TileMetadata>> getTileMetadataBatch(List<String> tileKeys) async {
    if (tileKeys.isEmpty) return {};

    final db = await database;
    final stopwatch = Stopwatch()..start();
    final metadataMap = <String, TileMetadata>{};

    try {
      // Create placeholders for IN clause
      final placeholders = tileKeys.map((_) => '?').join(',');

      final results = await db.query(
        _metadataTable,
        where: 'tile_key IN ($placeholders)',
        whereArgs: tileKeys,
      );

      for (final row in results) {
        try {
          final metadata = TileMetadata(
            tileKey: row['tile_key'] as String,
            airspaceIds: Set<String>.from(
              jsonDecode(row['airspace_ids'] as String) as List,
            ),
            fetchTime: DateTime.fromMillisecondsSinceEpoch(
              row['fetch_time'] as int,
            ),
            airspaceCount: row['airspace_count'] as int,
            isEmpty: (row['is_empty'] as int) == 1,
            statistics: row['statistics'] != null
                ? jsonDecode(row['statistics'] as String)
                : null,
          );
          metadataMap[metadata.tileKey] = metadata;
        } catch (e) {
          LoggingService.error('Failed to parse tile metadata: ${row['tile_key']}', e, null);
        }
      }

      // Log only if slow
      if (stopwatch.elapsedMilliseconds > 50) {
        LoggingService.performance(
          'Batch retrieved tile metadata',
          stopwatch.elapsed,
          'requested=${tileKeys.length}, found=${metadataMap.length}',
        );
      }

      return metadataMap;
    } catch (e, stack) {
      LoggingService.error('Failed to batch retrieve tile metadata', e, stack);
      return {};
    }
  }

  // Cache maintenance
  Future<void> cleanExpiredData() async {
    final db = await database;
    final stopwatch = Stopwatch()..start();

    try {
      // Clean expired geometries (7 days)
      final geometryExpiry = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;

      final deletedGeometries = await db.delete(
        _geometryTable,
        where: 'fetch_time < ?',
        whereArgs: [geometryExpiry],
      );

      // Clean expired metadata (24 hours)
      final metadataExpiry = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;

      final deletedMetadata = await db.delete(
        _metadataTable,
        where: 'fetch_time < ?',
        whereArgs: [metadataExpiry],
      );

      // Vacuum database to reclaim space
      if (deletedGeometries > 0 || deletedMetadata > 0) {
        await db.execute('VACUUM');
      }

      LoggingService.performance(
        'Cleaned expired cache',
        stopwatch.elapsed,
        'geometries=$deletedGeometries, metadata=$deletedMetadata',
      );
    } catch (e, stack) {
      LoggingService.error('Failed to clean cache', e, stack);
    }
  }

  // Statistics
  Future<CacheStatistics> getStatistics() async {
    final db = await database;

    try {
      // Get geometry statistics
      final geometryStats = await db.rawQuery('''
        SELECT
          COUNT(*) as count,
          SUM(compressed_size) as compressed,
          SUM(uncompressed_size) as uncompressed
        FROM $_geometryTable
      ''');

      // Get metadata statistics
      final metadataStats = await db.rawQuery('''
        SELECT
          COUNT(*) as count,
          SUM(is_empty) as empty_count
        FROM $_metadataTable
      ''');

      final geoRow = geometryStats.first;
      final metaRow = metadataStats.first;

      final totalGeometries = geoRow['count'] as int? ?? 0;
      final compressedBytes = geoRow['compressed'] as int? ?? 0;
      final uncompressedBytes = geoRow['uncompressed'] as int? ?? 0;
      final totalTiles = metaRow['count'] as int? ?? 0;
      final emptyTiles = metaRow['empty_count'] as int? ?? 0;

      // Get database file size
      final dbSize = await getDatabaseSize();

      return CacheStatistics(
        totalGeometries: totalGeometries,
        totalTiles: totalTiles,
        emptyTiles: emptyTiles,
        duplicatedAirspaces: 0, // Will be calculated by the service
        totalMemoryBytes: dbSize, // Use actual database size
        compressedBytes: compressedBytes,
        averageCompressionRatio: totalGeometries > 0
            ? 1.0 - (compressedBytes / uncompressedBytes)
            : 0,
        cacheHitRate: 0, // Will be calculated by the service
        lastUpdated: DateTime.now(),
      );
    } catch (e, stack) {
      LoggingService.error('Failed to get statistics', e, stack);
      return CacheStatistics.empty();
    }
  }

  // Get statistics as a simple map (for compatibility)
  Future<Map<String, dynamic>> getStatisticsMap() async {
    final db = await database;

    try {
      // Get geometry statistics
      final geometryStats = await db.rawQuery('''
        SELECT
          COUNT(*) as count,
          SUM(compressed_size) as compressed,
          SUM(uncompressed_size) as uncompressed
        FROM $_geometryTable
      ''');

      final geoRow = geometryStats.first;
      final dbSize = await getDatabaseSize();

      return {
        'geometry_count': geoRow['count'] as int? ?? 0,
        'total_compressed_size': geoRow['compressed'] as int? ?? 0,
        'total_uncompressed_size': geoRow['uncompressed'] as int? ?? 0,
        'database_size_bytes': dbSize,
        'database_size_mb': (dbSize / (1024 * 1024)).toStringAsFixed(2),
        'max_size_mb': maxDatabaseSizeMB,
        'avg_compression_ratio': (geoRow['count'] as int? ?? 0) > 0
            ? 1.0 - ((geoRow['compressed'] as int? ?? 0) / (geoRow['uncompressed'] as int? ?? 1))
            : 0,
      };
    } catch (e, stack) {
      LoggingService.error('Failed to get statistics map', e, stack);
      return {};
    }
  }

  // Get current database size in bytes
  Future<int> getDatabaseSize() async {
    final path = _databasePath ?? join((await getApplicationDocumentsDirectory()).path, _databaseName);
    final dbFile = File(path);
    if (await dbFile.exists()) {
      return await dbFile.length();
    }
    return 0;
  }

  // Check and enforce database size limit
  Future<void> _enforceSizeLimit() async {
    final currentSize = await getDatabaseSize();
    final maxSizeBytes = maxDatabaseSizeMB * 1024 * 1024;

    if (currentSize >= maxSizeBytes) { // Trigger cleanup at 100% of limit
      LoggingService.info('Database size ${(currentSize / (1024 * 1024)).toStringAsFixed(1)}MB reached limit, performing cleanup');
      await _performSizeCleanup();
    }
  }

  // Perform cleanup to reduce database size to 80% of max
  Future<void> _performSizeCleanup() async {
    final db = await database;
    final maxSizeBytes = maxDatabaseSizeMB * 1024 * 1024;
    final targetSize = maxSizeBytes * 0.8; // Target 80% of max size

    try {
      var currentSize = await getDatabaseSize();
      LoggingService.info('Starting cleanup: current ${(currentSize / (1024 * 1024)).toStringAsFixed(1)}MB, target ${(targetSize / (1024 * 1024)).toStringAsFixed(1)}MB');

      // Keep deleting batches until we reach 80% of max size
      while (currentSize > targetSize) {
        // Delete oldest geometry entries based on last_accessed
        await db.execute('''
          DELETE FROM $_geometryTable
          WHERE id IN (
            SELECT id FROM $_geometryTable
            ORDER BY last_accessed ASC
            LIMIT $cleanupBatchSize
          )
        ''');

        // Delete oldest tile metadata
        await db.execute('''
          DELETE FROM $_metadataTable
          WHERE id IN (
            SELECT id FROM $_metadataTable
            ORDER BY fetch_time ASC
            LIMIT $cleanupBatchSize
          )
        ''');

        currentSize = await getDatabaseSize();
      }

      // Vacuum to reclaim space
      await db.execute('VACUUM');

      final newSize = await getDatabaseSize();
      LoggingService.info('Cleanup complete, new size: ${(newSize / (1024 * 1024)).toStringAsFixed(1)}MB');
    } catch (e, stack) {
      LoggingService.error('Failed to perform size cleanup', e, stack);
    }
  }

  // Clear all cache
  Future<void> clearCache() async {
    try {
      LoggingService.info('Starting airspace disk cache clear');

      // Close the database if it's open
      if (_database != null) {
        await _database!.close();
        _database = null;
        LoggingService.info('Closed airspace database');
      }

      // Delete the database file
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = join(documentsDirectory.path, _databaseName);
      final file = File(path);

      if (await file.exists()) {
        await file.delete();
        LoggingService.info('Deleted airspace database file at: $path');
      }

      _databasePath = null;
      // The database will be recreated on next access
      LoggingService.info('Cleared airspace disk cache completely');
    } catch (e, stack) {
      LoggingService.error('Failed to clear disk cache', e, stack);
    }
  }

  // Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}