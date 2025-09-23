import '../services/logging_service.dart';
import '../services/airspace_disk_cache.dart';
import '../services/airspace_geometry_cache.dart';
import '../data/models/airspace_cache_models.dart';

/// Manages country-based airspace metadata and viewport queries
class AirspaceMetadataCache {
  static AirspaceMetadataCache? _instance;
  final AirspaceDiskCache _diskCache = AirspaceDiskCache.instance;
  final AirspaceGeometryCache _geometryCache = AirspaceGeometryCache.instance;

  // In-memory cache for country metadata
  final Map<String, Set<String>> _countryAirspaceCache = {};
  final List<String> _countryAccessOrder = [];
  static const int _maxCountryCacheSize = 30; // Cache up to 30 countries

  // Statistics tracking
  int _cacheHits = 0;
  int _cacheMisses = 0;

  AirspaceMetadataCache._internal();

  static AirspaceMetadataCache get instance {
    _instance ??= AirspaceMetadataCache._internal();
    return _instance!;
  }

  /// Store airspaces for a country
  Future<void> putCountryAirspaces({
    required String countryCode,
    required List<Map<String, dynamic>> features,
  }) async {

    LoggingService.debug('Caching ${features.length} features for country $countryCode');

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

      // Update memory cache for UI purposes
      _updateCountryCache(countryCode, airspaceIds.toSet());

      LoggingService.info('Stored $countryCode airspaces: ${airspaceIds.length} geometries');
    } catch (e, stack) {
      LoggingService.error('Failed to store country airspaces', e, stack);
    }
  }


  /// Get airspaces for viewport using optimized spatial query with filtering
  /// All filtering is performed at the database level for optimal performance
  Future<List<CachedAirspaceGeometry>> getAirspacesForViewport({
    required double west,
    required double south,
    required double east,
    required double north,
    Set<int>? excludedTypes,
    Set<int>? excludedClasses,
    double? maxAltitudeFt,
    bool orderByAltitude = false,
  }) async {


    // Use the enhanced spatial query with SQL-level filtering
    final viewportGeometries = await _diskCache.getGeometriesInBounds(
      west: west,
      south: south,
      east: east,
      north: north,
      excludedTypes: excludedTypes,
      excludedClasses: excludedClasses,
      maxAltitudeFt: maxAltitudeFt,
      orderByAltitude: orderByAltitude,
    );

    LoggingService.debug('Viewport query found ${viewportGeometries.length} geometries');

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

  /// Delete country data (simplified - clears all airspace data)
  Future<void> deleteCountryData(String countryCode) async {
    LoggingService.info('Clearing airspace data for: $countryCode');

    // Remove from memory cache
    _countryAirspaceCache.remove(countryCode);
    _countryAccessOrder.remove(countryCode);

    // Since we no longer track by country, clear all cache data
    await clearAllCache();

    LoggingService.info('Successfully cleared airspace data');
  }

  /// Get cache statistics
  Future<CacheStatistics> getStatistics() async {
    final diskStats = await _diskCache.getStatistics();
    final geometryStats = await _geometryCache.getStatistics();

    return CacheStatistics(
      totalGeometries: geometryStats.totalGeometries,
      totalTiles: 0,  // Tiles are deprecated
      emptyTiles: 0,  // Tiles are deprecated
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
    _countryAirspaceCache.clear();
    _countryAccessOrder.clear();
    _cacheHits = 0;
    _cacheMisses = 0;
    LoggingService.info('Cleared country metadata memory cache');
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
  }

  /// Get performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    final geometryMetrics = _geometryCache.getPerformanceMetrics();

    return {
      'tileCache': {
        'memoryHits': _cacheHits,
        'memoryMisses': _cacheMisses,
        'hitRate': (_cacheHits + _cacheMisses) > 0
            ? '${(_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(1)}%'
            : '0.0%',
        'countryCacheSize': _countryAirspaceCache.length,
      },
      'geometryCache': geometryMetrics,
    };
  }
}