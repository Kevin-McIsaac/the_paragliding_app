import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../services/logging_service.dart';
import '../services/airspace_geojson_service.dart' show ClipperData;
import '../data/models/airspace_cache_models.dart';

class AirspaceDiskCache {
  static const String _databaseName = 'airspace_cache.db';
  static const int _databaseVersion = 7; // Version 7: Removed redundant indexes and tile table

  static const String _geometryTable = 'airspace_geometries';
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

    // Ensure the directory exists
    try {
      await documentsDirectory.create(recursive: true);
    } catch (e) {
      LoggingService.error('Failed to create documents directory', e, null);
    }

    // PRE-RELEASE ONLY: Force recreation for schema changes
    // Remove this after v1.0 release and implement proper migrations
    try {
      final file = File(path);
      if (await file.exists()) {
        // Only try to open existing database file
        final existing = await openDatabase(path, readOnly: true);
        final currentVersion = await existing.getVersion();
        await existing.close();

        if (currentVersion != _databaseVersion) {
          LoggingService.info('Database version mismatch (current: $currentVersion, expected: $_databaseVersion). Deleting old database.');
          await deleteDatabase(path);
        }
      } else {
        LoggingService.info('Database file does not exist, will create new one');
      }
    } catch (e) {
      // Database doesn't exist or cannot be opened, which is fine for initial creation
      LoggingService.info('Cannot access existing database (${e.toString()}), will create new one');
    }

    try {
      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onOpen: _onOpen,
      );
    } catch (e, stackTrace) {
      LoggingService.error('Failed to initialize airspace cache database', e, stackTrace);

      // Try to delete any corrupted database file and retry once
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          LoggingService.info('Deleted corrupted database file, retrying creation');
        }

        return await openDatabase(
          path,
          version: _databaseVersion,
          onCreate: _onCreate,
          onOpen: _onOpen,
        );
      } catch (retryError, retryStackTrace) {
        LoggingService.error('Failed to create airspace cache database after retry', retryError, retryStackTrace);
        rethrow;
      }
    }
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

    // Geometry table - Version 6 with expanded native columns for direct pipeline
    await db.execute('''
      CREATE TABLE $_geometryTable (
        -- Core identifiers
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type_code INTEGER NOT NULL,

        -- Spatial data (binary for efficiency)
        coordinates_binary BLOB NOT NULL,  -- Int32 array (scaled by 10^7)
        polygon_offsets BLOB NOT NULL,     -- Int32 array of point indices
        bounds_west REAL NOT NULL,
        bounds_south REAL NOT NULL,
        bounds_east REAL NOT NULL,
        bounds_north REAL NOT NULL,

        -- Computed altitude fields (for fast filtering and sorting)
        lower_altitude_ft INTEGER,         -- Lower limit in feet (computed)
        upper_altitude_ft INTEGER,         -- Upper limit in feet (computed)

        -- Raw altitude components
        lower_value REAL,                  -- Raw lower value
        lower_unit INTEGER,                -- Unit code (1=ft, 2=m, 6=FL)
        lower_reference INTEGER,           -- Reference code (0=GND, 1=AMSL, 2=AGL)
        upper_value REAL,                  -- Raw upper value
        upper_unit INTEGER,                -- Unit code
        upper_reference INTEGER,           -- Reference code

        -- Classification fields
        icao_class INTEGER,                -- ICAO class code (extracted)
        activity INTEGER,                  -- Activity bitmask
        country TEXT,                      -- Country code

        -- Metadata
        fetch_time INTEGER NOT NULL,
        geometry_hash TEXT NOT NULL,
        coordinate_count INTEGER NOT NULL,
        polygon_count INTEGER NOT NULL,
        last_accessed INTEGER,

        -- Minimal JSON for rarely-used fields
        extra_properties TEXT              -- Remaining properties not extracted
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

    // Create spatial index for bounding box queries (most critical for performance)
    await db.execute('CREATE INDEX idx_geometry_spatial ON $_geometryTable(bounds_west, bounds_east, bounds_south, bounds_north)');

  }

  // Compression utilities

  /// Extract binary data directly from ClipperData
  (Uint8List, Uint8List) _extractBinaryFromClipperData(ClipperData clipperData) {
    // ClipperData already stores Int32 coordinates - just convert to bytes
    final coordBytes = clipperData.coords.buffer.asUint8List();
    final offsetBytes = clipperData.offsets.buffer.asUint8List();
    return (coordBytes, offsetBytes);
  }

  /// Calculate bounds from ClipperData
  Map<String, double> _calculateBoundsFromClipperData(ClipperData clipperData) {
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    // Iterate through coordinates (they're stored as lng,lat pairs in Int32)
    for (int i = 0; i < clipperData.coords.length; i += 2) {
      final lng = clipperData.coords[i] / 10000000.0;  // Convert back to degrees
      final lat = clipperData.coords[i + 1] / 10000000.0;

      minLat = lat < minLat ? lat : minLat;
      maxLat = lat > maxLat ? lat : maxLat;
      minLng = lng < minLng ? lng : minLng;
      maxLng = lng > maxLng ? lng : maxLng;
    }

    return {
      'west': minLng,
      'south': minLat,
      'east': maxLng,
      'north': maxLat,
    };
  }

  // Binary encoding utilities for coordinates
  /// Encodes polygon coordinates as Int32 arrays for direct Clipper2 compatibility


  /// Create ClipperData directly from database BLOBs without LatLng conversion
  ClipperData _createClipperData(Uint8List coordBlob, Uint8List offsetBlob) {
    // CRITICAL: Copy to aligned buffer to avoid alignment issues
    // SQLite returns BLOBs as views at arbitrary offsets that may not be 4-byte aligned
    final alignedCoords = Uint8List.fromList(coordBlob);
    final alignedOffsets = Uint8List.fromList(offsetBlob);

    final coords = Int32List.view(
      alignedCoords.buffer,
      0,
      alignedCoords.length ~/ 4,
    );
    final offsets = Int32List.view(
      alignedOffsets.buffer,
      0,
      alignedOffsets.length ~/ 4,
    );

    return ClipperData(coords, offsets);
  }


  // REMOVED: Legacy Float32 decode methods - now always use Int32


  /// Compute altitude in feet from raw value, unit, and reference
  /// Returns 999999 for unknown altitudes (will sort to end)
  int _computeAltitudeInFeet(dynamic value, int? unit, int? reference) {
    // Handle special ground values or reference code 0 (GND)
    if (reference == 0 || (value is String && value.toLowerCase() == 'gnd')) {
      return 0;
    }

    // Handle numeric values with OpenAIP unit codes
    if (value is num) {
      // OpenAIP unit codes: 1=ft, 2=m, 6=FL
      if (unit == 6) {
        // Flight Level: FL090 = 9,000 feet
        return (value * 100).round();
      } else if (unit == 1) {
        // Feet (AMSL or AGL - treat both as feet for sorting)
        return value.round();
      } else if (unit == 2) {
        // Meters - convert to feet
        return (value * 3.28084).round();
      }
    }

    // Unknown altitude
    return 999999;
  }

  // Geometry cache operations - Version 2 with binary storage
  Future<void> putGeometry(CachedAirspaceGeometry geometry) async {
    // Check database size before inserting
    await _enforceSizeLimit();

    final db = await database;
    final stopwatch = Stopwatch()..start();

    // Removed verbose per-geometry logging - logged in batch operations instead

    try {
      // Extract binary data directly from ClipperData
      final (coordinatesBinary, offsetsBinary) = _extractBinaryFromClipperData(geometry.clipperData);

      // Calculate bounds for spatial queries
      final bounds = _calculateBoundsFromClipperData(geometry.clipperData);

      // Extract altitude limits (complex objects)
      final lowerLimit = geometry.properties['lowerLimit'] as Map<String, dynamic>?;
      final upperLimit = geometry.properties['upperLimit'] as Map<String, dynamic>?;

      // Extract altitude components
      final lowerValue = lowerLimit?['value'];
      final lowerUnit = lowerLimit?['unit'] as int?;
      final lowerReference = lowerLimit?['reference'] as int?;
      final upperValue = upperLimit?['value'];
      final upperUnit = upperLimit?['unit'] as int?;
      final upperReference = upperLimit?['reference'] as int?;

      // Compute altitude in feet for fast filtering
      final lowerAltitudeFt = lowerLimit != null
          ? _computeAltitudeInFeet(lowerValue, lowerUnit, lowerReference)
          : null;
      final upperAltitudeFt = upperLimit != null
          ? _computeAltitudeInFeet(upperValue, upperUnit, upperReference)
          : null;

      // Extract classification fields
      final icaoClass = (geometry.properties['class'] ?? geometry.properties['icaoClass']) as int?;
      final activity = geometry.properties['activity'] as int?;
      final country = geometry.properties['country'] as String?;

      // Create a copy of properties without the extracted fields for extra_properties
      final extraProperties = Map<String, dynamic>.from(geometry.properties);
      extraProperties.remove('lowerLimit');
      extraProperties.remove('upperLimit');
      extraProperties.remove('class');
      extraProperties.remove('icaoClass');
      extraProperties.remove('activity');
      extraProperties.remove('country');

      // Count coordinates from ClipperData
      final coordinateCount = geometry.clipperData.coords.length ~/ 2;

      await db.insert(
        _geometryTable,
        {
          // Core identifiers
          'id': geometry.id,
          'name': geometry.name,
          'type_code': geometry.typeCode,

          // Spatial data
          'coordinates_binary': coordinatesBinary,
          'polygon_offsets': offsetsBinary,
          'bounds_west': bounds['west'],
          'bounds_south': bounds['south'],
          'bounds_east': bounds['east'],
          'bounds_north': bounds['north'],

          // Computed altitude fields
          'lower_altitude_ft': lowerAltitudeFt,
          'upper_altitude_ft': upperAltitudeFt,

          // Raw altitude components
          'lower_value': lowerValue is num ? lowerValue.toDouble() : null,
          'lower_unit': lowerUnit,
          'lower_reference': lowerReference,
          'upper_value': upperValue is num ? upperValue.toDouble() : null,
          'upper_unit': upperUnit,
          'upper_reference': upperReference,

          // Classification fields
          'icao_class': icaoClass,
          'activity': activity,
          'country': country,

          // Metadata
          'fetch_time': geometry.fetchTime.millisecondsSinceEpoch,
          'geometry_hash': geometry.geometryHash,
          'coordinate_count': coordinateCount,
          'polygon_count': geometry.clipperData.offsets.length,
          'last_accessed': DateTime.now().millisecondsSinceEpoch,

          // Minimal JSON for remaining properties
          'extra_properties': extraProperties.isNotEmpty ? jsonEncode(extraProperties) : null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Only log slow storage operations (>10ms)
      if (stopwatch.elapsedMilliseconds > 10) {
        LoggingService.performance(
          '[PUT_GEOMETRY_SLOW]',
          stopwatch.elapsed,
          'id=${geometry.id}, name=${geometry.name}, binary_size=${coordinatesBinary.length}',
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

      LoggingService.debug(
        'Batch ID check: ${ids.length} IDs, ${existingIds.length} existing (${stopwatch.elapsedMilliseconds}ms)'
      );

      return existingIds;
    } catch (e, stack) {
      LoggingService.error('Failed to check existing IDs', e, stack);
      return {};
    }
  }

  /// Batch insert multiple geometries in a single transaction
  Future<void> putGeometryBatch(List<CachedAirspaceGeometry> geometries) async {
    if (geometries.isEmpty) return;

    final db = await database;
    final stopwatch = Stopwatch()..start();

    try {
      // Use a batch for maximum performance
      final batch = db.batch();

      for (final geometry in geometries) {
        // Extract binary data directly from ClipperData
        final (coordinatesBinary, offsetsBinary) = _extractBinaryFromClipperData(geometry.clipperData);

        // Calculate bounds for spatial queries
        final bounds = _calculateBoundsFromClipperData(geometry.clipperData);

        // Extract altitude limits (complex objects)
        final lowerLimit = geometry.properties['lowerLimit'] as Map<String, dynamic>?;
        final upperLimit = geometry.properties['upperLimit'] as Map<String, dynamic>?;

        // Extract altitude components
        final lowerValue = lowerLimit?['value'];
        final lowerUnit = lowerLimit?['unit'] as int?;
        final lowerReference = lowerLimit?['reference'] as int?;
        final upperValue = upperLimit?['value'];
        final upperUnit = upperLimit?['unit'] as int?;
        final upperReference = upperLimit?['reference'] as int?;

        // Compute altitude in feet for fast filtering
        final lowerAltitudeFt = lowerLimit != null
            ? _computeAltitudeInFeet(lowerValue, lowerUnit, lowerReference)
            : null;
        final upperAltitudeFt = upperLimit != null
            ? _computeAltitudeInFeet(upperValue, upperUnit, upperReference)
            : null;

        // Extract classification fields
        final icaoClass = (geometry.properties['class'] ?? geometry.properties['icaoClass']) as int?;
        final activity = geometry.properties['activity'] as int?;
        final country = geometry.properties['country'] as String?;

        // Create a copy of properties without the extracted fields for extra_properties
        final extraProperties = Map<String, dynamic>.from(geometry.properties);
        extraProperties.remove('lowerLimit');
        extraProperties.remove('upperLimit');
        extraProperties.remove('class');
        extraProperties.remove('icaoClass');
        extraProperties.remove('activity');
        extraProperties.remove('country');

        // Count coordinates from ClipperData
        final coordinateCount = geometry.clipperData.coords.length ~/ 2;

        batch.insert(
          _geometryTable,
          {
            // Core identifiers
            'id': geometry.id,
            'name': geometry.name,
            'type_code': geometry.typeCode,

            // Spatial data
            'coordinates_binary': coordinatesBinary,
            'polygon_offsets': offsetsBinary,
            'bounds_west': bounds['west'],
            'bounds_south': bounds['south'],
            'bounds_east': bounds['east'],
            'bounds_north': bounds['north'],

            // Computed altitude fields
            'lower_altitude_ft': lowerAltitudeFt,
            'upper_altitude_ft': upperAltitudeFt,

            // Raw altitude components
            'lower_value': lowerValue is num ? lowerValue.toDouble() : null,
            'lower_unit': lowerUnit,
            'lower_reference': lowerReference,
            'upper_value': upperValue is num ? upperValue.toDouble() : null,
            'upper_unit': upperUnit,
            'upper_reference': upperReference,

            // Classification fields
            'icao_class': icaoClass,
            'activity': activity,
            'country': country,

            // Metadata
            'fetch_time': geometry.fetchTime.millisecondsSinceEpoch,
            'geometry_hash': geometry.geometryHash,
            'coordinate_count': coordinateCount,
            'polygon_count': geometry.clipperData.offsets.length,
            'last_accessed': DateTime.now().millisecondsSinceEpoch,

            // Minimal JSON for remaining properties
            'extra_properties': extraProperties.isNotEmpty ? jsonEncode(extraProperties) : null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Commit all inserts at once with noResult for better performance
      await batch.commit(noResult: true);

      stopwatch.stop();
      LoggingService.performance(
        '[BATCH_GEOMETRY_INSERT]',
        stopwatch.elapsed,
        'count=${geometries.length}',
      );
    } catch (e, stack) {
      LoggingService.error('Failed to batch insert geometries', e, stack);
      rethrow;
    }
  }

  Future<CachedAirspaceGeometry?> getGeometry(String id) async {
    final db = await database;
    final stopwatch = Stopwatch()..start();

    // Removed verbose per-geometry logging - logged in batch operations instead

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

      // Decode Int32 coordinates and offsets
      final coordinatesBinary = row['coordinates_binary'] as Uint8List;
      final offsetsBinary = row['polygon_offsets'] as Uint8List;

      // Removed verbose per-geometry decode logging

      // Always use ClipperData for optimal performance
      final clipperData = _createClipperData(coordinatesBinary, offsetsBinary);

      // Reconstruct geometry from native columns
      final geometry = CachedAirspaceGeometry(
        id: row['id'] as String,
        name: row['name'] as String,
        typeCode: row['type_code'] as int,
        clipperData: clipperData,
        properties: jsonDecode(row['properties'] as String) as Map<String, dynamic>,
        fetchTime: DateTime.fromMillisecondsSinceEpoch(row['fetch_time'] as int),
        geometryHash: row['geometry_hash'] as String,
        compressedSize: coordinatesBinary.length,
        uncompressedSize: (row['coordinate_count'] as int) * 8, // 2 floats * 4 bytes
      );

      // Only log very slow retrieval operations (>50ms) to reduce noise
      if (stopwatch.elapsedMilliseconds > 50) {
        LoggingService.performance(
          '[GET_GEOMETRY_SLOW]',
          stopwatch.elapsed,
          'id=$id, name=${geometry.name}',
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
    final decodeStopwatch = Stopwatch();

    try {
      final placeholders = ids.map((_) => '?').join(',');
      final results = await db.query(
        _geometryTable,
        where: 'id IN ($placeholders)',
        whereArgs: ids.toList(),
      );

      // Track decoding time separately
      decodeStopwatch.start();

      // Optimize by avoiding repeated JSON parsing of polygonOffsets
      final decodedGeometries = <CachedAirspaceGeometry>[];
      for (final row in results) {
        try {
          final coordinatesBinary = row['coordinates_binary'] as Uint8List;
          final polygonOffsetsJson = row['polygon_offsets'] as String;
          final propertiesJson = row['properties'] as String;

          // Decode polygonOffsets once per row (avoid repeated JSON parsing)
          List<int> polygonOffsets;
          Map<String, dynamic> properties;
          try {
            polygonOffsets = (jsonDecode(polygonOffsetsJson) as List).cast<int>();
            properties = jsonDecode(propertiesJson) as Map<String, dynamic>;
          } catch (jsonError) {
            LoggingService.error('Failed to parse JSON for geometry: ${row['id']}', jsonError, null);
            continue;
          }

          // Convert List<int> offsets to Uint8List for Int32 decode
          final offsetArray = Int32List.fromList(polygonOffsets);
          final offsetBytes = offsetArray.buffer.asUint8List();

          // Always use ClipperData for optimal performance
          final clipperData = _createClipperData(coordinatesBinary, offsetBytes);

          final geometry = CachedAirspaceGeometry(
            id: row['id'] as String,
            name: row['name'] as String,
            typeCode: row['type_code'] as int,
            clipperData: clipperData,
            properties: properties,
            fetchTime: DateTime.fromMillisecondsSinceEpoch(row['fetch_time'] as int),
            geometryHash: row['geometry_hash'] as String,
            compressedSize: coordinatesBinary.length,
            uncompressedSize: (row['coordinate_count'] as int) * 8,
            lowerAltitudeFt: row['lower_altitude_ft'] as int?,
          );

          decodedGeometries.add(geometry);
        } catch (e) {
          LoggingService.error('Failed to parse geometry: ${row['id']}', e, null);
        }
      }

      geometries.addAll(decodedGeometries);

      decodeStopwatch.stop();

      // Performance logging with detailed breakdown
      LoggingService.performance(
        '[BATCH_GEOMETRY_FETCH]',
        stopwatch.elapsed,
        'requested=${ids.length}, found=${geometries.length}, db_query=${stopwatch.elapsedMilliseconds - decodeStopwatch.elapsedMilliseconds}ms, decode=${decodeStopwatch.elapsedMilliseconds}ms',
      );

      return geometries;
    } catch (e, stack) {
      LoggingService.error('Failed to retrieve geometries', e, stack);
      return [];
    }
  }

  /// Get geometries within spatial bounds with direct SQL filtering
  /// This method performs all filtering at the database level for optimal performance
  Future<List<CachedAirspaceGeometry>> getGeometriesInBounds({
    required double west,
    required double south,
    required double east,
    required double north,
    int? typeCode,
    Set<int>? excludedTypes,
    Set<int>? excludedClasses,
    double? maxAltitudeFt,
    bool orderByAltitude = false,
  }) async {
    final db = await database;
    final stopwatch = Stopwatch()..start();
    final queryStopwatch = Stopwatch();
    final decodeStopwatch = Stopwatch();

    try {
      // Build the spatial query using indexed bounds columns
      queryStopwatch.start();

      final conditions = <String>[];
      final args = <dynamic>[];

      // Spatial bounds conditions - uses indexed columns for fast filtering
      conditions.add('bounds_west <= ?');
      args.add(east);
      conditions.add('bounds_east >= ?');
      args.add(west);
      conditions.add('bounds_south <= ?');
      args.add(north);
      conditions.add('bounds_north >= ?');
      args.add(south);

      // Type filtering
      if (typeCode != null) {
        conditions.add('type_code = ?');
        args.add(typeCode);
      } else if (excludedTypes != null && excludedTypes.isNotEmpty) {
        conditions.add('type_code NOT IN (${excludedTypes.map((_) => '?').join(',')})');
        args.addAll(excludedTypes);
      }

      // ICAO class filtering
      if (excludedClasses != null && excludedClasses.isNotEmpty) {
        conditions.add('(icao_class IS NULL OR icao_class NOT IN (${excludedClasses.map((_) => '?').join(',')}))');
        args.addAll(excludedClasses);
      }

      // Altitude filtering
      if (maxAltitudeFt != null) {
        conditions.add('(lower_altitude_ft IS NULL OR lower_altitude_ft <= ?)');
        args.add(maxAltitudeFt);
      }

      // Build the optimized spatial query without JOIN
      var query = '''
        SELECT * FROM $_geometryTable
        WHERE ${conditions.join(' AND ')}
      ''';

      // Add ORDER BY clause for clipping optimization
      if (orderByAltitude) {
        query += ' ORDER BY lower_altitude_ft ASC NULLS LAST';
      }

      final results = await db.rawQuery(query, args);
      queryStopwatch.stop();

      LoggingService.info('[SPATIAL_INDEX_QUERY] Found ${results.length} geometries in bounds | query_ms=${queryStopwatch.elapsedMilliseconds}');

      if (results.isEmpty) {
        return [];
      }

      // Decode geometries
      decodeStopwatch.start();
      final geometries = <CachedAirspaceGeometry>[];

      for (final row in results) {
        try {
          final coordinatesBinary = row['coordinates_binary'] as Uint8List;
          final offsetsBinary = row['polygon_offsets'] as Uint8List;

          // Always use ClipperData for optimal performance
          final clipperData = _createClipperData(coordinatesBinary, offsetsBinary);

          // Reconstruct properties from native columns
          final properties = <String, dynamic>{};

          // Add altitude limits if present
          if (row['lower_value'] != null) {
            properties['lowerLimit'] = {
              'value': row['lower_value'],
              'unit': row['lower_unit'],
              'reference': row['lower_reference'],
            };
          }
          if (row['upper_value'] != null) {
            properties['upperLimit'] = {
              'value': row['upper_value'],
              'unit': row['upper_unit'],
              'reference': row['upper_reference'],
            };
          }

          // Add classification fields
          if (row['icao_class'] != null) {
            properties['icaoClass'] = row['icao_class'];
          }
          if (row['activity'] != null) {
            properties['activity'] = row['activity'];
          }
          if (row['country'] != null) {
            properties['country'] = row['country'];
          }

          // Add any extra properties if present
          if (row['extra_properties'] != null) {
            final extraProps = jsonDecode(row['extra_properties'] as String) as Map<String, dynamic>;
            properties.addAll(extraProps);
          }

          final geometry = CachedAirspaceGeometry(
            id: row['id'] as String,
            name: row['name'] as String,
            typeCode: row['type_code'] as int,
            clipperData: clipperData,
            properties: properties,
            fetchTime: DateTime.fromMillisecondsSinceEpoch(row['fetch_time'] as int),
            geometryHash: row['geometry_hash'] as String,
            compressedSize: coordinatesBinary.length,
            uncompressedSize: (row['coordinate_count'] as int) * 8,
            lowerAltitudeFt: row['lower_altitude_ft'] as int?,
          );

          geometries.add(geometry);
        } catch (e) {
          LoggingService.error('Failed to parse geometry: ${row['id']}', e, null);
        }
      }

      decodeStopwatch.stop();

      // Log performance metrics
      LoggingService.performance(
        '[SPATIAL_QUERY_COMPLETE]',
        stopwatch.elapsed,
        'query_results=${results.length}, returned=${geometries.length}, '
        'query_ms=${queryStopwatch.elapsedMilliseconds}, decode_ms=${decodeStopwatch.elapsedMilliseconds}',
      );

      return geometries;
    } catch (e, stack) {
      LoggingService.error('Failed to query geometries in bounds', e, stack);
      return [];
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

      // Vacuum database to reclaim space
      if (deletedGeometries > 0) {
        await db.execute('VACUUM');
      }

      LoggingService.performance(
        'Cleaned expired cache',
        stopwatch.elapsed,
        'geometries=$deletedGeometries',
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
          SUM(LENGTH(coordinates_binary)) as compressed,
          SUM(coordinate_count * 8) as uncompressed
        FROM $_geometryTable
      ''');

      final geoRow = geometryStats.first;

      final totalGeometries = geoRow['count'] as int? ?? 0;
      final compressedBytes = geoRow['compressed'] as int? ?? 0;
      final uncompressedBytes = geoRow['uncompressed'] as int? ?? 0;

      // Get database file size
      final dbSize = await getDatabaseSize();

      return CacheStatistics(
        totalGeometries: totalGeometries,
        totalTiles: 0,
        emptyTiles: 0,
        duplicatedAirspaces: 0, // Will be calculated by the service
        totalMemoryBytes: dbSize, // Use actual database size
        compressedBytes: compressedBytes,
        averageCompressionRatio: totalGeometries > 0 && uncompressedBytes > 0
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

  /// Get the total number of geometries in the cache
  Future<int> getGeometryCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM $_geometryTable');
    return result.first['count'] as int;
  }

  // Get statistics as a simple map (for compatibility)
  Future<Map<String, dynamic>> getStatisticsMap() async {
    final db = await database;

    try {
      // Get geometry statistics
      final geometryStats = await db.rawQuery('''
        SELECT
          COUNT(*) as count,
          SUM(LENGTH(coordinates_binary)) as compressed,
          SUM(coordinate_count * 8) as uncompressed
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
        'database_version': _databaseVersion,
        'avg_compression_ratio': (geoRow['count'] as int? ?? 0) > 0 && (geoRow['uncompressed'] as int? ?? 0) > 0
            ? 1.0 - ((geoRow['compressed'] as int? ?? 0) / (geoRow['uncompressed'] as int? ?? 1))
            : 0,
      };
    } catch (e, stack) {
      LoggingService.error('Failed to get statistics map', e, stack);
      return {};
    }
  }

  // Get database version
  Future<int> getDatabaseVersion() async {
    try {
      final db = await database;
      return await db.getVersion();
    } catch (e) {
      LoggingService.error('Failed to get database version', e, null);
      return _databaseVersion; // Return expected version as fallback
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
      } else {
        LoggingService.info('No airspace database file found at: $path');
      }

      // Also try to delete any journal files
      final walFile = File('$path-wal');
      final shmFile = File('$path-shm');
      if (await walFile.exists()) {
        await walFile.delete();
        LoggingService.info('Deleted WAL file');
      }
      if (await shmFile.exists()) {
        await shmFile.delete();
        LoggingService.info('Deleted SHM file');
      }

      _databasePath = null;
      // The database will be recreated on next access
      LoggingService.info('Cleared airspace disk cache completely');

      // Verify deletion
      if (!await file.exists() && !await walFile.exists() && !await shmFile.exists()) {
        LoggingService.info('[CACHE_CLEAR_VERIFIED] All database files successfully deleted');
      } else {
        LoggingService.error('Some database files may still exist after clear', null, null);
      }
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