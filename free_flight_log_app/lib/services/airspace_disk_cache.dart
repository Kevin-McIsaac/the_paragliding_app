import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:latlong2/latlong.dart';
import '../services/logging_service.dart';
import '../data/models/airspace_cache_models.dart';

class AirspaceDiskCache {
  static const String _databaseName = 'airspace_cache.db';
  static const int _databaseVersion = 6; // Version 6: Expanded native columns for direct pipeline optimization

  static const String _geometryTable = 'airspace_geometries';
  static const String _metadataTable = 'tile_metadata'; // Keep for compatibility
  static const String _countryMetadataTable = 'country_metadata'; // New table
  static const String _countryMappingTable = 'country_airspace_mapping'; // New table
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

    // PRE-RELEASE ONLY: Force recreation for schema changes
    // Remove this after v1.0 release and implement proper migrations
    try {
      final existing = await openDatabase(path, readOnly: true);
      final currentVersion = await existing.getVersion();
      await existing.close();

      if (currentVersion != _databaseVersion) {
        LoggingService.info('Database version mismatch (current: $currentVersion, expected: $_databaseVersion). Deleting old database.');
        await deleteDatabase(path);
      }
    } catch (e) {
      // Database doesn't exist yet, which is fine
      LoggingService.info('No existing database found, will create new one');
    }

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

    // Tile metadata table (keep for compatibility)
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

    // Country metadata table (new for country-based storage)
    await db.execute('''
      CREATE TABLE $_countryMetadataTable (
        country_code TEXT PRIMARY KEY,
        airspace_count INTEGER NOT NULL,
        fetch_time INTEGER NOT NULL,
        etag TEXT,
        last_modified TEXT,
        version INTEGER DEFAULT 1,
        size_bytes INTEGER,
        last_accessed INTEGER
      )
    ''');

    // Country to airspace mapping table
    await db.execute('''
      CREATE TABLE $_countryMappingTable (
        country_code TEXT NOT NULL,
        airspace_id TEXT NOT NULL,
        PRIMARY KEY (country_code, airspace_id),
        FOREIGN KEY (country_code) REFERENCES $_countryMetadataTable(country_code) ON DELETE CASCADE,
        FOREIGN KEY (airspace_id) REFERENCES $_geometryTable(id) ON DELETE CASCADE
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

    // Create optimized spatial indices for bounding box queries
    // Using compound index for efficient spatial queries without R-tree
    await db.execute('CREATE INDEX idx_geometry_spatial ON $_geometryTable(bounds_west, bounds_east, bounds_south, bounds_north)');
    await db.execute('CREATE INDEX idx_geometry_bounds_west ON $_geometryTable(bounds_west)');
    await db.execute('CREATE INDEX idx_geometry_bounds_east ON $_geometryTable(bounds_east)');
    await db.execute('CREATE INDEX idx_geometry_bounds_south ON $_geometryTable(bounds_south)');
    await db.execute('CREATE INDEX idx_geometry_bounds_north ON $_geometryTable(bounds_north)');

    // Create optimized indices for direct pipeline
    // Filtering indices
    await db.execute('CREATE INDEX idx_geometry_lower_altitude ON $_geometryTable(lower_altitude_ft)');
    await db.execute('CREATE INDEX idx_geometry_type_code ON $_geometryTable(type_code)');
    await db.execute('CREATE INDEX idx_geometry_icao_class ON $_geometryTable(icao_class)');
    await db.execute('CREATE INDEX idx_geometry_country ON $_geometryTable(country)');
    await db.execute('CREATE INDEX idx_geometry_fetch_time ON $_geometryTable(fetch_time)');

    // Compound index for common filter pattern
    await db.execute('CREATE INDEX idx_geometry_filter_combined ON $_geometryTable(lower_altitude_ft, type_code, icao_class)');

    // Optimized compound index for spatial + altitude queries (most common pattern)
    // This covers the typical query: bounds check + altitude filter + sorting
    await db.execute('CREATE INDEX idx_geometry_spatial_altitude ON $_geometryTable(lower_altitude_ft, bounds_west, bounds_east, bounds_south, bounds_north)');

    // Metadata indices
    await db.execute('CREATE INDEX idx_metadata_fetch_time ON $_metadataTable(fetch_time)');
    await db.execute('CREATE INDEX idx_metadata_empty ON $_metadataTable(is_empty)');
    // New indices for country-based queries
    await db.execute('CREATE INDEX idx_country_mapping_country ON $_countryMappingTable(country_code)');
    await db.execute('CREATE INDEX idx_country_mapping_airspace ON $_countryMappingTable(airspace_id)');
    await db.execute('CREATE INDEX idx_country_metadata_fetch ON $_countryMetadataTable(fetch_time)');
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

  // Binary encoding utilities for coordinates
  /// Encodes polygon coordinates as Int32 arrays for direct Clipper2 compatibility
  /// Returns the coordinate data and polygon offsets as binary blobs
  (Uint8List, Uint8List) _encodeCoordinatesInt32(List<List<LatLng>> polygons) {
    final stopwatch = Stopwatch()..start();

    // Calculate total size needed
    int totalPoints = 0;
    int invalidPoints = 0;
    for (final polygon in polygons) {
      for (final point in polygon) {
        // Validate point before encoding
        if (point.latitude.isNaN || point.longitude.isNaN ||
            point.latitude.abs() > 90 || point.longitude.abs() > 180) {
          LoggingService.error(
            'Invalid point during encoding: lat=${point.latitude}, lng=${point.longitude}',
            null,
            null,
          );
          invalidPoints++;
        }
      }
      totalPoints += polygon.length;
    }

    if (invalidPoints > 0) {
      LoggingService.error(
        'Found $invalidPoints invalid points during encoding',
        null,
        null,
      );
    }

    // Allocate Int32 arrays
    final coordArray = Int32List(totalPoints * 2);
    final offsetArray = Int32List(polygons.length);

    // Single pass encoding with pre-scaled integers for Clipper2
    int coordIndex = 0;
    for (int i = 0; i < polygons.length; i++) {
      offsetArray[i] = coordIndex ~/ 2; // Store point index

      final polygon = polygons[i];
      for (final point in polygon) {
        // Scale to Int32 with precision factor 10^7 (1.11cm precision)
        coordArray[coordIndex++] = (point.longitude * 10000000).round();
        coordArray[coordIndex++] = (point.latitude * 10000000).round();
      }
    }

    // Convert to bytes
    final coordBytes = coordArray.buffer.asUint8List();
    final offsetBytes = offsetArray.buffer.asUint8List();

    // Only log if encoding takes significant time (>5ms)
    if (stopwatch.elapsedMilliseconds > 5) {
      LoggingService.performance(
        '[ENCODE_INT32_SLOW]',
        stopwatch.elapsed,
        'polygons=${polygons.length}, points=$totalPoints, coordBytes=${coordBytes.length}, offsetBytes=${offsetBytes.length}',
      );
    }

    return (coordBytes, offsetBytes);
  }

  // Keep old Float32 version for compatibility during migration
  (Uint8List, List<int>) _encodeCoordinatesBinary(List<List<LatLng>> polygons) {
    final (coordBytes, offsetBytes) = _encodeCoordinatesInt32(polygons);
    // Convert offset bytes back to list for compatibility
    final offsets = Int32List.view(offsetBytes.buffer).toList();
    return (coordBytes, offsets);
  }

  /// Decodes Int32 coordinate and offset arrays back to polygon coordinates
  List<List<LatLng>> _decodeCoordinatesInt32(Uint8List coordBlob, Uint8List offsetBlob) {
    final stopwatch = Stopwatch()..start();

    // Validate input
    if (coordBlob.length % 4 != 0 || offsetBlob.length % 4 != 0) {
      LoggingService.error(
        'Invalid binary data: coord bytes ${coordBlob.length} or offset bytes ${offsetBlob.length} not divisible by 4',
        null,
        null,
      );
      return [];
    }

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

    final polygons = <List<LatLng>>[];

    for (int i = 0; i < offsets.length; i++) {
      final startIdx = offsets[i] * 2; // Convert point index to coord index
      final endIdx = (i + 1 < offsets.length)
          ? offsets[i + 1] * 2
          : coords.length;

      // Validate indices
      if (startIdx < 0 || endIdx > coords.length || startIdx > endIdx) {
        LoggingService.error(
          'Invalid polygon indices: start=$startIdx, end=$endIdx, array length=${coords.length}',
          null,
          null,
        );
        continue;
      }

      final polygon = <LatLng>[];
      for (int j = startIdx; j < endIdx; j += 2) {
        // Decode from Int32 with scale factor 10^7
        polygon.add(LatLng(
          coords[j + 1] / 10000000.0,  // latitude
          coords[j] / 10000000.0,       // longitude
        ));
      }

      if (polygon.isNotEmpty) {
        polygons.add(polygon);
      }
    }

    // Only log if decoding takes significant time (>5ms)
    if (stopwatch.elapsedMilliseconds > 5) {
      LoggingService.performance(
        '[DECODE_INT32_SLOW]',
        stopwatch.elapsed,
        'polygons=${polygons.length}, coordBytes=${coordBlob.length}, offsetBytes=${offsetBlob.length}',
      );
    }

    return polygons;
  }

  // Keep old Float32 version for compatibility during migration
  List<List<LatLng>> _decodeCoordinatesBinary(Uint8List bytes, List<int> polygonOffsets) {
    // Convert List<int> offsets to Uint8List for new method
    final offsetArray = Int32List.fromList(polygonOffsets);
    final offsetBytes = offsetArray.buffer.asUint8List();

    return _decodeCoordinatesInt32(bytes, offsetBytes);
  }

  // Legacy Float32 decode method (to be removed after migration)
  List<List<LatLng>> _decodeCoordinatesFloat32(Uint8List bytes, List<int> polygonOffsets) {
    final stopwatch = Stopwatch()..start();

    // Validate input
    if (bytes.length % 4 != 0) {
      LoggingService.error(
        'Invalid binary data: byte length ${bytes.length} not divisible by 4',
        null,
        null,
      );
      return [];
    }

    // CRITICAL FIX: Copy to aligned buffer to avoid alignment issues
    // SQLite returns BLOBs as views at arbitrary offsets that may not be 4-byte aligned
    // Float32List requires 4-byte alignment, so we copy to a new aligned buffer
    final alignedBytes = Uint8List.fromList(bytes);
    final floatArray = Float32List.view(
      alignedBytes.buffer,
      0,  // New buffer starts at offset 0 (guaranteed aligned)
      alignedBytes.length ~/ 4,  // Number of floats (4 bytes per float)
    );

    final polygons = <List<LatLng>>[];

    for (int i = 0; i < polygonOffsets.length; i++) {
      final startIdx = polygonOffsets[i] * 2; // Convert point index to float index
      final endIdx = (i + 1 < polygonOffsets.length)
          ? polygonOffsets[i + 1] * 2
          : floatArray.length;

      // Validate indices
      if (startIdx < 0 || startIdx > floatArray.length || endIdx > floatArray.length) {
        LoggingService.error(
          'Invalid polygon indices: start=$startIdx, end=$endIdx, array=${floatArray.length}',
          null,
          null,
        );
        continue;
      }

      final polygon = <LatLng>[];
      for (int j = startIdx; j < endIdx; j += 2) {
        final lat = floatArray[j + 1];
        final lng = floatArray[j];

        // Validate coordinates
        if (lat.isNaN || lng.isNaN || lat.abs() > 90 || lng.abs() > 180) {
          LoggingService.error(
            'Invalid coordinates: lat=$lat, lng=$lng at index $j',
            null,
            null,
          );
          continue;
        }

        polygon.add(LatLng(lat, lng));
      }

      if (polygon.isNotEmpty) {
        polygons.add(polygon);
      }
    }

    // Only log slow decode operations (>5ms)
    if (stopwatch.elapsedMilliseconds > 5) {
      final totalPoints = polygons.fold(0, (sum, p) => sum + p.length);
      LoggingService.performance(
        '[BINARY_DECODE_SLOW]',
        stopwatch.elapsed,
        'polygons=${polygons.length}, points=$totalPoints',
      );
    }

    return polygons;
  }

  /// Optimized binary decoding with reduced allocations (for batch operations)
  List<List<LatLng>> _decodeCoordinatesBinaryOptimized(Uint8List bytes, List<int> polygonOffsets) {
    // Validate input
    if (bytes.length % 4 != 0) return [];

    // Reuse aligned buffer approach but optimize for batch operations
    final alignedBytes = Uint8List.fromList(bytes);
    final floatArray = Float32List.view(alignedBytes.buffer, 0, alignedBytes.length ~/ 4);

    // Build polygons list with efficient allocation
    final polygons = <List<LatLng>>[];

    for (int i = 0; i < polygonOffsets.length; i++) {
      final startIdx = polygonOffsets[i] * 2;
      final endIdx = (i + 1 < polygonOffsets.length)
          ? polygonOffsets[i + 1] * 2
          : floatArray.length;

      // Validate indices with quick bounds check
      if (startIdx < 0 || endIdx > floatArray.length) continue;

      final polygon = <LatLng>[];

      for (int j = startIdx; j < endIdx; j += 2) {
        final lng = floatArray[j];
        final lat = floatArray[j + 1];

        // Quick coordinate validation (avoid expensive isNaN checks)
        if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
          polygon.add(LatLng(lat, lng));
        }
      }

      if (polygon.isNotEmpty) {
        polygons.add(polygon);
      }
    }

    return polygons;
  }

  /// Calculate bounds from polygons
  Map<String, double> _calculateBounds(List<List<LatLng>> polygons) {
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    for (final polygon in polygons) {
      for (final point in polygon) {
        minLat = math.min(minLat, point.latitude);
        maxLat = math.max(maxLat, point.latitude);
        minLng = math.min(minLng, point.longitude);
        maxLng = math.max(maxLng, point.longitude);
      }
    }

    return {
      'west': minLng,
      'south': minLat,
      'east': maxLng,
      'north': maxLat,
    };
  }

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
      // Encode coordinates as Int32 binary with binary offsets
      final (coordinatesBinary, offsetsBinary) = _encodeCoordinatesInt32(geometry.polygons);

      // Calculate bounds for spatial queries
      final bounds = _calculateBounds(geometry.polygons);

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

      // Count coordinates
      int coordinateCount = 0;
      for (final polygon in geometry.polygons) {
        coordinateCount += polygon.length;
      }

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
          'polygon_count': geometry.polygons.length,
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

      LoggingService.info(
        '[BATCH_ID_CHECK] Checked ${ids.length} IDs, found ${existingIds.length} existing in ${stopwatch.elapsedMilliseconds}ms'
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
        // Encode coordinates as Int32 binary with binary offsets
        final (coordinatesBinary, offsetsBinary) = _encodeCoordinatesInt32(geometry.polygons);

        // Calculate bounds for spatial queries
        final bounds = _calculateBounds(geometry.polygons);

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

        // Count coordinates
        int coordinateCount = 0;
        for (final polygon in geometry.polygons) {
          coordinateCount += polygon.length;
        }

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
            'polygon_count': geometry.polygons.length,
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

      final polygons = _decodeCoordinatesInt32(coordinatesBinary, offsetsBinary);

      // Reconstruct geometry from native columns
      final geometry = CachedAirspaceGeometry(
        id: row['id'] as String,
        name: row['name'] as String,
        typeCode: row['type_code'] as int,
        polygons: polygons,
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

          final polygons = _decodeCoordinatesBinaryOptimized(coordinatesBinary, polygonOffsets);

          final geometry = CachedAirspaceGeometry(
            id: row['id'] as String,
            name: row['name'] as String,
            typeCode: row['type_code'] as int,
            polygons: polygons,
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
    List<String>? countryCodes,
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

      // Build the query based on country filter
      String query;
      if (countryCodes != null && countryCodes.isNotEmpty) {
        query = '''
          SELECT DISTINCT g.*
          FROM $_geometryTable g
          JOIN $_countryMappingTable cm ON g.id = cm.airspace_id
          WHERE ${conditions.join(' AND ')}
            AND cm.country_code IN (${countryCodes.map((_) => '?').join(',')})
        ''';
        args.addAll(countryCodes);
      } else {
        query = '''
          SELECT * FROM $_geometryTable
          WHERE ${conditions.join(' AND ')}
        ''';
      }

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

          final polygons = _decodeCoordinatesInt32(coordinatesBinary, offsetsBinary);

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
            polygons: polygons,
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
          SUM(LENGTH(coordinates_binary)) as compressed,
          SUM(coordinate_count * 8) as uncompressed
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

  // Country-based methods

  /// Store country metadata
  Future<void> putCountryMetadata({
    required String countryCode,
    required int airspaceCount,
    String? etag,
    String? lastModified,
    int? sizeBytes,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      _countryMetadataTable,
      {
        'country_code': countryCode,
        'airspace_count': airspaceCount,
        'fetch_time': now,
        'etag': etag,
        'last_modified': lastModified,
        'version': 1,
        'size_bytes': sizeBytes,
        'last_accessed': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Store country to airspace mappings
  Future<void> putCountryMappings({
    required String countryCode,
    required List<String> airspaceIds,
  }) async {
    final db = await database;

    // Delete existing mappings for this country
    await db.delete(
      _countryMappingTable,
      where: 'country_code = ?',
      whereArgs: [countryCode],
    );

    // Insert new mappings in batch (use IGNORE to handle duplicates)
    final batch = db.batch();
    for (final airspaceId in airspaceIds) {
      batch.insert(
        _countryMappingTable,
        {
          'country_code': countryCode,
          'airspace_id': airspaceId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get airspace IDs for a country
  Future<List<String>> getCountryAirspaceIds(String countryCode) async {
    final db = await database;

    final results = await db.query(
      _countryMappingTable,
      columns: ['airspace_id'],
      where: 'country_code = ?',
      whereArgs: [countryCode],
    );

    return results.map((row) => row['airspace_id'] as String).toList();
  }

  /// Get airspace IDs for multiple countries
  Future<Set<String>> getAirspaceIdsForCountries(List<String> countryCodes) async {
    if (countryCodes.isEmpty) return {};

    final db = await database;
    final placeholders = List.filled(countryCodes.length, '?').join(',');

    final results = await db.rawQuery('''
      SELECT DISTINCT airspace_id
      FROM $_countryMappingTable
      WHERE country_code IN ($placeholders)
    ''', countryCodes);

    return results.map((row) => row['airspace_id'] as String).toSet();
  }

  /// Delete country data
  Future<void> deleteCountryData(String countryCode) async {
    final db = await database;

    // Delete country metadata (cascades to mappings)
    await db.delete(
      _countryMetadataTable,
      where: 'country_code = ?',
      whereArgs: [countryCode],
    );

    // Clean up orphaned geometries
    await cleanOrphanedGeometries();
  }

  /// Clean up geometries not referenced by any country
  Future<void> cleanOrphanedGeometries() async {
    final db = await database;

    await db.execute('''
      DELETE FROM $_geometryTable
      WHERE id NOT IN (
        SELECT DISTINCT airspace_id
        FROM $_countryMappingTable
      )
    ''');
  }

  /// Get list of cached countries
  Future<List<String>> getCachedCountries() async {
    final db = await database;

    final results = await db.query(
      _countryMetadataTable,
      columns: ['country_code'],
      orderBy: 'country_code',
    );

    return results.map((row) => row['country_code'] as String).toList();
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