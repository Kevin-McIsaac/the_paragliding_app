import '../services/logging_service.dart';
import '../services/airspace_disk_cache.dart';
import '../services/airspace_geometry_cache.dart';
import '../data/models/airspace_cache_models.dart';

/// Manages tile-to-airspace ID mappings
class AirspaceMetadataCache {
  static AirspaceMetadataCache? _instance;
  final AirspaceDiskCache _diskCache = AirspaceDiskCache.instance;
  final AirspaceGeometryCache _geometryCache = AirspaceGeometryCache.instance;

  // In-memory cache for tile metadata (keeping for backward compatibility)
  final Map<String, TileMetadata> _memoryCache = {};
  final List<String> _accessOrder = [];
  static const int _maxMemoryCacheSize = 20000; // Keep metadata for 20000 tiles

  // In-memory cache for country metadata
  final Map<String, Set<String>> _countryAirspaceCache = {};
  final List<String> _countryAccessOrder = [];
  static const int _maxCountryCacheSize = 30; // Cache up to 30 countries

  // Statistics tracking
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _emptyTileCount = 0;
  final Map<String, DateTime> _pendingFetches = {};

  AirspaceMetadataCache._internal();

  static AirspaceMetadataCache get instance {
    _instance ??= AirspaceMetadataCache._internal();
    return _instance!;
  }

  /// Generate tile key from zoom, x, y coordinates
  String generateTileKey(int zoom, int x, int y) {
    return '${zoom}_${x}_$y';
  }

  /// Parse tile key into components
  Map<String, int>? parseTileKey(String tileKey) {
    final parts = tileKey.split('_');
    if (parts.length != 3) return null;

    try {
      return {
        'zoom': int.parse(parts[0]),
        'x': int.parse(parts[1]),
        'y': int.parse(parts[2]),
      };
    } catch (e) {
      return null;
    }
  }

  /// Store tile metadata with airspace IDs
  Future<void> putTileMetadata({
    required String tileKey,
    required List<Map<String, dynamic>> features,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Extract airspace IDs and store geometries
      final airspaceIds = <String>{};

      for (final feature in features) {
        try {
          final id = _geometryCache.generateAirspaceId(feature);
          airspaceIds.add(id);

          // Store geometry (will handle deduplication)
          await _geometryCache.putGeometry(feature);
        } catch (e, stack) {
          LoggingService.error('Failed to process feature for tile $tileKey', e, stack);
        }
      }

      // Create tile metadata
      final metadata = TileMetadata(
        tileKey: tileKey,
        airspaceIds: airspaceIds,
        fetchTime: DateTime.now(),
        airspaceCount: airspaceIds.length,
        isEmpty: airspaceIds.isEmpty,
        statistics: _generateTileStatistics(features),
      );

      // Track empty tiles
      if (metadata.isEmpty) {
        _emptyTileCount++;
      }

      // Store to disk
      await _diskCache.putTileMetadata(metadata);

      // Update memory cache
      _updateMemoryCache(tileKey, metadata);

      LoggingService.performance(
        'Stored tile metadata',
        stopwatch.elapsed,
        'tile=$tileKey, airspaces=${airspaceIds.length}, empty=${metadata.isEmpty}',
      );
    } catch (e, stack) {
      LoggingService.error('Failed to store tile metadata', e, stack);
    }
  }

  /// Mark a tile as empty
  Future<void> markTileEmpty(String tileKey) async {
    final metadata = TileMetadata.empty(tileKey);

    // Store to disk
    await _diskCache.putTileMetadata(metadata);

    // Update memory cache
    _updateMemoryCache(tileKey, metadata);
    _emptyTileCount++;
  }

  /// Batch process multiple tiles to avoid redundant geometry retrievals
  Future<void> putMultipleTilesMetadata(Map<String, List<Map<String, dynamic>>> tilesFeatures) async {
    final stopwatch = Stopwatch()..start();

    // Step 1: Collect all unique features across all tiles
    final Map<String, Map<String, dynamic>> uniqueFeatures = {};
    final Map<String, Set<String>> tileAirspaceIds = {};

    for (final entry in tilesFeatures.entries) {
      final tileKey = entry.key;
      final features = entry.value;
      final airspaceIds = <String>{};

      for (final feature in features) {
        try {
          final id = _geometryCache.generateAirspaceId(feature);
          airspaceIds.add(id);

          // Only add if not already collected
          if (!uniqueFeatures.containsKey(id)) {
            uniqueFeatures[id] = feature;
          }
        } catch (e, stack) {
          LoggingService.error('Failed to process feature for tile $tileKey', e, stack);
        }
      }

      tileAirspaceIds[tileKey] = airspaceIds;
    }

    // Step 2: Store all unique geometries in batch (avoids redundant checks)
    if (uniqueFeatures.isNotEmpty) {
      await _geometryCache.putGeometryBatch(uniqueFeatures.values.toList());
    }

    // Step 3: Store tile metadata for each tile
    for (final entry in tileAirspaceIds.entries) {
      final tileKey = entry.key;
      final airspaceIds = entry.value;

      final metadata = TileMetadata(
        tileKey: tileKey,
        airspaceIds: airspaceIds,
        fetchTime: DateTime.now(),
        airspaceCount: airspaceIds.length,
        isEmpty: airspaceIds.isEmpty,
      );

      if (metadata.isEmpty) {
        _emptyTileCount++;
      }

      // Store to disk
      await _diskCache.putTileMetadata(metadata);

      // Update memory cache
      _updateMemoryCache(tileKey, metadata);
    }

    LoggingService.info(
      '[BATCH_TILE_PROCESSING] Processed ${tilesFeatures.length} tiles with ${uniqueFeatures.length} unique features in ${stopwatch.elapsedMilliseconds}ms'
    );
  }

  /// Get tile metadata
  Future<TileMetadata?> getTileMetadata(String tileKey) async {
    // Check if fetch is already pending
    if (_pendingFetches.containsKey(tileKey)) {
      final pendingTime = _pendingFetches[tileKey]!;
      if (DateTime.now().difference(pendingTime).inSeconds < 5) {
        return null;
      }
    }

    // Check memory cache first
    if (_memoryCache.containsKey(tileKey)) {
      _cacheHits++;
      _updateAccessOrder(tileKey);
      final metadata = _memoryCache[tileKey]!;

      if (!metadata.isExpired) {
        return metadata;
      }
    }

    // Check disk cache
    _cacheMisses++;
    final metadata = await _diskCache.getTileMetadata(tileKey);

    if (metadata != null) {
      _updateMemoryCache(tileKey, metadata);

      if (!metadata.isExpired) {
        return metadata;
      }
    }
    return null;
  }

  /// Get airspaces for a tile
  Future<List<CachedAirspaceGeometry>> getAirspacesForTile(String tileKey) async {
    final metadata = await getTileMetadata(tileKey);

    if (metadata == null || metadata.isEmpty) {
      return [];
    }

    // Fetch geometries for all airspace IDs
    return await _geometryCache.getGeometries(metadata.airspaceIds);
  }

  /// Get airspaces for multiple tiles
  Future<List<CachedAirspaceGeometry>> getAirspacesForTiles(List<String> tileKeys) async {
    if (tileKeys.isEmpty) return [];

    final stopwatch = Stopwatch()..start();
    final allAirspaceIds = <String>{};
    var emptyTiles = 0;
    var cachedTiles = 0;
    var memoryHits = 0;
    var diskHits = 0;

    // Step 1: Check memory cache for tiles (fastest)
    final tilesToCheckOnDisk = <String>[];
    for (final tileKey in tileKeys) {
      final cachedMetadata = _memoryCache[tileKey];
      if (cachedMetadata != null && !cachedMetadata.isExpired) {
        _cacheHits++;
        memoryHits++;
        _updateAccessOrder(tileKey);
        cachedTiles++;

        if (cachedMetadata.isEmpty) {
          emptyTiles++;
        } else {
          allAirspaceIds.addAll(cachedMetadata.airspaceIds);
        }
      } else {
        tilesToCheckOnDisk.add(tileKey);
      }
    }

    // Step 2: Batch fetch remaining tiles from disk (single query)
    if (tilesToCheckOnDisk.isNotEmpty) {
      final diskStopwatch = Stopwatch()..start();
      final diskMetadata = await _diskCache.getTileMetadataBatch(tilesToCheckOnDisk);
      diskStopwatch.stop();

      diskHits = diskMetadata.length;
      _cacheMisses += tilesToCheckOnDisk.length - diskHits;

      // Process disk results
      for (final tileKey in tilesToCheckOnDisk) {
        final metadata = diskMetadata[tileKey];

        if (metadata != null && !metadata.isExpired) {
          // Update memory cache
          _updateMemoryCache(tileKey, metadata);
          cachedTiles++;

          if (metadata.isEmpty) {
            emptyTiles++;
          } else {
            allAirspaceIds.addAll(metadata.airspaceIds);
          }
        }
      }

      // Log disk fetch performance if slow
      if (diskStopwatch.elapsedMilliseconds > 20) {
        LoggingService.performance(
          '[BATCH_TILE_METADATA_FETCH]',
          diskStopwatch.elapsed,
          'requested=${tilesToCheckOnDisk.length}, found=$diskHits',
        );
      }
    }

    // Step 3: Fetch all unique geometries
    final geometries = await _geometryCache.getGeometries(allAirspaceIds);

    LoggingService.performance(
      'Retrieved airspaces for tiles',
      stopwatch.elapsed,
      'tiles=${tileKeys.length}, cached=$cachedTiles, empty=$emptyTiles, unique_airspaces=${allAirspaceIds.length}, memory_hits=$memoryHits, disk_hits=$diskHits',
    );

    return geometries;
  }

  /// Check if tiles need fetching - optimized batch version
  Future<List<String>> getTilesToFetch(List<String> tileKeys) async {
    if (tileKeys.isEmpty) return [];

    final tilesToFetch = <String>[];
    final tilesToCheck = <String>[];

    // Step 1: Check memory cache first (very fast)
    for (final tileKey in tileKeys) {
      // Check if fetch is already pending
      if (_pendingFetches.containsKey(tileKey)) {
        final pendingTime = _pendingFetches[tileKey]!;
        if (DateTime.now().difference(pendingTime).inSeconds < 5) {
          continue; // Skip this tile, fetch is already pending
        }
      }

      // Check memory cache
      final cachedMetadata = _memoryCache[tileKey];
      if (cachedMetadata != null && !cachedMetadata.isExpired) {
        _cacheHits++;
        _updateAccessOrder(tileKey);
        continue; // This tile is cached and valid
      }

      // Need to check disk cache for this tile
      tilesToCheck.add(tileKey);
    }

    // Step 2: Batch check disk cache for remaining tiles
    if (tilesToCheck.isNotEmpty) {
      _cacheMisses += tilesToCheck.length;

      // Batch retrieve from disk
      final diskMetadata = await _diskCache.getTileMetadataBatch(tilesToCheck);

      for (final tileKey in tilesToCheck) {
        final metadata = diskMetadata[tileKey];

        if (metadata != null && !metadata.isExpired) {
          // Update memory cache
          _updateMemoryCache(tileKey, metadata);
        } else {
          // Need to fetch from API
          tilesToFetch.add(tileKey);
          _pendingFetches[tileKey] = DateTime.now();
        }
      }
    }

    return tilesToFetch;
  }

  /// Clear pending fetch marker
  void clearPendingFetch(String tileKey) {
    _pendingFetches.remove(tileKey);
  }

  /// Generate statistics for a tile
  Map<String, dynamic> _generateTileStatistics(List<Map<String, dynamic>> features) {
    final typeCount = <String, int>{};
    var totalPoints = 0;

    for (final feature in features) {
      final properties = feature['properties'] ?? {};
      final type = properties['type'] ?? 'Unknown';
      typeCount[type] = (typeCount[type] ?? 0) + 1;

      // Count geometry points
      final geometry = feature['geometry'] ?? {};
      final coordinates = geometry['coordinates'];
      if (coordinates is List) {
        totalPoints += _countCoordinates(coordinates);
      }
    }

    return {
      'types': typeCount,
      'totalPoints': totalPoints,
      'avgPointsPerAirspace': features.isNotEmpty
          ? (totalPoints / features.length).round()
          : 0,
    };
  }

  /// Count coordinates in nested arrays
  int _countCoordinates(List coordinates) {
    var count = 0;

    void countRecursive(dynamic item) {
      if (item is List) {
        if (item.isNotEmpty && item[0] is num) {
          count++;
        } else {
          for (final subItem in item) {
            countRecursive(subItem);
          }
        }
      }
    }

    countRecursive(coordinates);
    return count;
  }

  /// Update memory cache with LRU eviction
  void _updateMemoryCache(String tileKey, TileMetadata metadata) {
    // Remove from current position if exists
    _accessOrder.remove(tileKey);

    // Add to front
    _accessOrder.insert(0, tileKey);
    _memoryCache[tileKey] = metadata;

    // Evict if over limit
    while (_accessOrder.length > _maxMemoryCacheSize) {
      final evictKey = _accessOrder.removeLast();
      _memoryCache.remove(evictKey);
    }
  }

  /// Update access order for LRU
  void _updateAccessOrder(String tileKey) {
    _accessOrder.remove(tileKey);
    _accessOrder.insert(0, tileKey);
  }

  // Country-based methods

  /// Store airspaces for a country
  Future<void> putCountryAirspaces({
    required String countryCode,
    required List<Map<String, dynamic>> features,
  }) async {
    final stopwatch = Stopwatch()..start();

    LoggingService.structured('COUNTRY_CACHE_STORE', {
      'country': countryCode,
      'features': features.length,
    });

    try {
      // Extract airspace IDs
      final airspaceIds = <String>[];

      for (final feature in features) {
        try {
          final id = _geometryCache.generateAirspaceId(feature);
          airspaceIds.add(id);
        } catch (e, stack) {
          LoggingService.error('Failed to generate ID for feature in country $countryCode', e, stack);
        }
      }

      // Store all geometries in batch - much faster than individual inserts
      await _geometryCache.putGeometryBatch(features);

      // Store country metadata
      await _diskCache.putCountryMetadata(
        countryCode: countryCode,
        airspaceCount: airspaceIds.length,
        sizeBytes: null, // Will be calculated later
      );

      // Store country to airspace mappings
      await _diskCache.putCountryMappings(
        countryCode: countryCode,
        airspaceIds: airspaceIds,
      );

      // Update memory cache
      _updateCountryCache(countryCode, airspaceIds.toSet());

      stopwatch.stop();
      LoggingService.performance(
        'Stored country airspaces',
        stopwatch.elapsed,
        'country=$countryCode, airspaces=${airspaceIds.length}',
      );
    } catch (e, stack) {
      LoggingService.error('Failed to store country airspaces', e, stack);
    }
  }

  /// Get airspaces for selected countries
  Future<List<CachedAirspaceGeometry>> getAirspacesForCountries(List<String> countryCodes) async {
    if (countryCodes.isEmpty) {
      return [];
    }

    final stopwatch = Stopwatch()..start();

    // Get all airspace IDs for the selected countries
    final airspaceIds = await _diskCache.getAirspaceIdsForCountries(countryCodes);

    // Fetch all geometries using batch operation
    final geometries = await _geometryCache.getGeometries(airspaceIds.toSet());

    stopwatch.stop();
    LoggingService.performance(
      'Retrieved country airspaces',
      stopwatch.elapsed,
      'countries=${countryCodes.length}, airspaces=${geometries.length}',
    );

    return geometries;
  }

  /// Get airspaces for viewport using optimized spatial query with filtering
  /// All filtering is performed at the database level for optimal performance
  Future<List<CachedAirspaceGeometry>> getAirspacesForViewport({
    required List<String> countryCodes,
    required double west,
    required double south,
    required double east,
    required double north,
    Set<int>? excludedTypes,
    Set<int>? excludedClasses,
    double? maxAltitudeFt,
    bool orderByAltitude = false,
    bool useClipperData = false,  // Pass through flag for ClipperData mode
  }) async {
    if (countryCodes.isEmpty) {
      return [];
    }

    final stopwatch = Stopwatch()..start();

    // Use the enhanced spatial query with SQL-level filtering
    final viewportGeometries = await _diskCache.getGeometriesInBounds(
      west: west,
      south: south,
      east: east,
      north: north,
      countryCodes: countryCodes,
      excludedTypes: excludedTypes,
      excludedClasses: excludedClasses,
      maxAltitudeFt: maxAltitudeFt,
      orderByAltitude: orderByAltitude,
      useClipperData: useClipperData,  // Forward the flag to disk cache
    );

    stopwatch.stop();

    // Log the new optimized performance
    LoggingService.performance(
      '[SPATIAL_VIEWPORT_QUERY]',
      stopwatch.elapsed,
      'countries=${countryCodes.length}, viewport_geometries=${viewportGeometries.length}',
    );

    // Update country cache for loaded geometries
    for (final countryCode in countryCodes) {
      final countryIds = viewportGeometries
          .map((g) => g.id)
          .toSet();
      if (countryIds.isNotEmpty) {
        _updateCountryCache(countryCode, countryIds);
      }
    }

    return viewportGeometries;
  }

  /// Update country cache with LRU eviction
  void _updateCountryCache(String countryCode, Set<String> airspaceIds) {
    // Remove from current position if exists
    _countryAccessOrder.remove(countryCode);

    // Add to front
    _countryAccessOrder.insert(0, countryCode);
    _countryAirspaceCache[countryCode] = airspaceIds;

    // Evict if over limit
    while (_countryAccessOrder.length > _maxCountryCacheSize) {
      final evictKey = _countryAccessOrder.removeLast();
      _countryAirspaceCache.remove(evictKey);
    }
  }

  /// Delete country data
  Future<void> deleteCountryData(String countryCode) async {
    LoggingService.info('Deleting country data from cache: $countryCode');

    // Remove from memory cache
    _countryAirspaceCache.remove(countryCode);
    _countryAccessOrder.remove(countryCode);

    // Remove from disk cache
    await _diskCache.deleteCountryData(countryCode);

    LoggingService.info('Successfully deleted country data: $countryCode');
  }

  /// Get cache statistics
  Future<CacheStatistics> getStatistics() async {
    final diskStats = await _diskCache.getStatistics();
    final geometryStats = await _geometryCache.getStatistics();  // Now async

    return CacheStatistics(
      totalGeometries: geometryStats.totalGeometries,
      totalTiles: _memoryCache.length,
      emptyTiles: _emptyTileCount,
      duplicatedAirspaces: geometryStats.duplicatedAirspaces,
      totalMemoryBytes: diskStats.totalMemoryBytes,
      compressedBytes: diskStats.compressedBytes,
      averageCompressionRatio: diskStats.averageCompressionRatio,
      cacheHitRate: (_cacheHits + _cacheMisses) > 0
          ? _cacheHits / (_cacheHits + _cacheMisses)
          : 0.0,
      lastUpdated: DateTime.now(),
    );
  }

  /// Clear memory cache
  void clearMemoryCache() {
    _memoryCache.clear();
    _accessOrder.clear();
    _pendingFetches.clear();
    _cacheHits = 0;
    _cacheMisses = 0;
    _emptyTileCount = 0;
    LoggingService.info('Cleared tile metadata memory cache');
  }

  /// Clear all cache (memory and disk)
  Future<void> clearAllCache() async {
    clearMemoryCache();
    await _diskCache.clearCache();
    LoggingService.info('Cleared all airspace cache');
  }

  /// Clean expired data
  Future<void> cleanExpiredData() async {
    await _diskCache.cleanExpiredData();
    await _geometryCache.cleanExpiredData();

    // Remove expired items from memory cache
    final expiredKeys = <String>[];

    for (final entry in _memoryCache.entries) {
      if (entry.value.isExpired) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _memoryCache.remove(key);
      _accessOrder.remove(key);
    }

    if (expiredKeys.isNotEmpty) {
      LoggingService.info('Removed ${expiredKeys.length} expired tiles from memory cache');
    }
  }

  /// Get performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    final geometryMetrics = _geometryCache.getPerformanceMetrics();

    return {
      'tileCache': {
        'memoryHits': _cacheHits,
        'memoryMisses': _cacheMisses,
        'hitRate': (_cacheHits + _cacheMisses) > 0
            ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(1)
            : '0.0',
        'memoryCacheSize': _memoryCache.length,
        'emptyTiles': _emptyTileCount,
        'pendingFetches': _pendingFetches.length,
      },
      'geometryCache': geometryMetrics,
    };
  }

  /// Prefetch adjacent tiles
  Future<void> prefetchAdjacentTiles(String tileKey, {int radius = 1}) async {
    final components = parseTileKey(tileKey);
    if (components == null) return;

    final zoom = components['zoom']!;
    final x = components['x']!;
    final y = components['y']!;

    final tilesToPrefetch = <String>[];

    // Generate adjacent tile keys
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        if (dx == 0 && dy == 0) continue; // Skip current tile

        final adjacentKey = generateTileKey(zoom, x + dx, y + dy);
        final metadata = _memoryCache[adjacentKey];

        // Only prefetch if not already cached or expired
        if (metadata == null || metadata.isExpired) {
          tilesToPrefetch.add(adjacentKey);
        }
      }
    }

    if (tilesToPrefetch.isNotEmpty) {
      // Note: Actual fetching would be done by the service layer
    }
  }
}