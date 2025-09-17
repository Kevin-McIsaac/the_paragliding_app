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

  Database? _database;
  static AirspaceDiskCache? _instance;

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
      LoggingService.debug('Could not set PRAGMA options: $e');
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
          'type': geometry.type,
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

      LoggingService.performance(
        'Stored airspace geometry',
        stopwatch.elapsed,
        'id=${geometry.id}, compressed=${compressed.length}, ratio=${(1 - compressed.length / uncompressedSize).toStringAsFixed(2)}',
      );
    } catch (e, stack) {
      LoggingService.error('Failed to store geometry', e, stack);
      rethrow;
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
        LoggingService.debug('Cache miss for geometry: $id');
        return null;
      }

      final row = results.first;
      final compressed = row['compressed_data'] as Uint8List;
      final json = _decompress(compressed);
      final geometry = CachedAirspaceGeometry.fromJson(jsonDecode(json));

      // Update access statistics
      await db.update(
        _geometryTable,
        {
          'access_count': (row['access_count'] as int? ?? 0) + 1,
          'last_accessed': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      LoggingService.performance(
        'Retrieved airspace geometry',
        stopwatch.elapsed,
        'id=$id, size=${compressed.length}',
      );

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

      // Batch update access statistics
      if (geometries.isNotEmpty) {
        final batch = db.batch();
        for (final id in ids) {
          batch.rawUpdate(
            'UPDATE $_geometryTable SET access_count = access_count + 1, last_accessed = ? WHERE id = ?',
            [DateTime.now().millisecondsSinceEpoch, id],
          );
        }
        await batch.commit(noResult: true);
      }

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

      LoggingService.debug('Stored tile metadata: ${metadata.tileKey}, airspaces=${metadata.airspaceCount}');
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

      // Update access statistics
      await db.update(
        _metadataTable,
        {
          'access_count': (row['access_count'] as int? ?? 0) + 1,
          'last_accessed': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'tile_key = ?',
        whereArgs: [tileKey],
      );

      return metadata;
    } catch (e, stack) {
      LoggingService.error('Failed to retrieve tile metadata', e, stack);
      return null;
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

      return CacheStatistics(
        totalGeometries: totalGeometries,
        totalTiles: totalTiles,
        emptyTiles: emptyTiles,
        duplicatedAirspaces: 0, // Will be calculated by the service
        totalMemoryBytes: uncompressedBytes,
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

  // Clear all cache
  Future<void> clearCache() async {
    final db = await database;

    try {
      await db.delete(_geometryTable);
      await db.delete(_metadataTable);
      await db.delete(_statisticsTable);
      await db.execute('VACUUM');

      LoggingService.info('Cleared all airspace cache');
    } catch (e, stack) {
      LoggingService.error('Failed to clear cache', e, stack);
    }
  }

  // Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}