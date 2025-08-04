import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../data/models/paragliding_site.dart';

/// Service for interacting with ParaglidingEarth.com API
/// Provides real-time site lookups with caching and fallback support
class ParaglidingEarthApi {
  static ParaglidingEarthApi? _instance;
  static ParaglidingEarthApi get instance => _instance ??= ParaglidingEarthApi._();
  
  ParaglidingEarthApi._();

  static const String _baseUrl = 'https://www.paraglidingearth.com/api/geojson';
  static const Duration _timeout = Duration(seconds: 10);
  static const int _defaultLimit = 10;
  
  // In-memory cache for API responses (could be enhanced with persistent storage)
  final Map<String, _CachedResponse> _cache = {};
  static const Duration _cacheExpiry = Duration(hours: 24);

  /// Get sites around given coordinates
  /// Returns sites within [radiusKm] of the coordinates, ordered by distance
  Future<List<ParaglidingSite>> getSitesAroundCoordinates(
    double latitude,
    double longitude, {
    double radiusKm = 10.0,
    int limit = _defaultLimit,
    bool detailed = true,
  }) async {
    // Create cache key
    final cacheKey = '${latitude.toStringAsFixed(4)}_${longitude.toStringAsFixed(4)}_${radiusKm}_$limit';
    
    // Check cache first
    final cached = _getCachedResponse(cacheKey);
    if (cached != null) {
      return cached;
    }

    try {
      final url = Uri.parse('$_baseUrl/getAroundLatLngSites.php').replace(
        queryParameters: {
          'lat': latitude.toString(),
          'lng': longitude.toString(),
          'distance': radiusKm.toString(),
          'limit': limit.toString(),
          if (detailed) 'style': 'detailled',
        },
      );

      print('ParaglidingEarth API: Fetching sites around $latitude, $longitude (${radiusKm}km)');

      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final sites = _parseGeoJsonResponse(response.body);
        
        // Cache the response
        _cacheResponse(cacheKey, sites);
        
        print('ParaglidingEarth API: Found ${sites.length} sites');
        return sites;
      } else {
        print('ParaglidingEarth API: HTTP ${response.statusCode} - ${response.reasonPhrase}');
        return [];
      }
    } catch (e) {
      print('ParaglidingEarth API error: $e');
      return [];
    }
  }

  /// Find the nearest site to given coordinates
  /// Returns the closest site within [maxDistanceKm], or null if none found
  Future<ParaglidingSite?> findNearestSite(
    double latitude,
    double longitude, {
    double maxDistanceKm = 10.0,
    String? preferredType, // 'launch', 'landing', or null for any
  }) async {
    final sites = await getSitesAroundCoordinates(
      latitude,
      longitude,
      radiusKm: maxDistanceKm,
      limit: 5, // We only need the closest few
    );

    if (sites.isEmpty) return null;

    // Filter by type if specified
    final filteredSites = preferredType != null 
        ? sites.where((site) => 
            site.siteType == preferredType || 
            site.siteType == 'both'
          ).toList()
        : sites;

    if (filteredSites.isEmpty) return null;

    // Sites are already ordered by distance from the API
    final nearest = filteredSites.first;
    final distance = nearest.distanceTo(latitude, longitude);
    
    // Double-check distance constraint (API sometimes returns sites slightly outside radius)
    if (distance <= maxDistanceKm * 1000) { // Convert km to meters for comparison
      return nearest;
    }

    return null;
  }

  /// Get sites in a bounding box (useful for map displays)
  Future<List<ParaglidingSite>> getSitesInBounds(
    double north,
    double south,
    double east,
    double west, {
    int limit = 50,
    bool detailed = true,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/getBoundingBoxSites.php').replace(
        queryParameters: {
          'north': north.toString(),
          'south': south.toString(),
          'east': east.toString(),  
          'west': west.toString(),
          'limit': limit.toString(),
          if (detailed) 'style': 'detailled',
        },
      );

      print('ParaglidingEarth API: Fetching sites in bounds');

      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final sites = _parseGeoJsonResponse(response.body);
        print('ParaglidingEarth API: Found ${sites.length} sites in bounds');
        return sites;
      } else {
        print('ParaglidingEarth API: HTTP ${response.statusCode} - ${response.reasonPhrase}');
        return [];
      }
    } catch (e) {
      print('ParaglidingEarth API error: $e');
      return [];
    }
  }

  /// Test API connectivity
  Future<bool> testConnection() async {
    try {
      // Test with a well-known location (Chamonix, France)
      final sites = await getSitesAroundCoordinates(
        45.9237, 6.8694,
        radiusKm: 5.0,
        limit: 1,
      );
      return sites.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Check if we have internet connectivity
  Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('www.paraglidingearth.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Parse GeoJSON response from ParaglidingEarth API
  List<ParaglidingSite> _parseGeoJsonResponse(String jsonString) {
    final sites = <ParaglidingSite>[];
    
    try {
      final json = jsonDecode(jsonString);
      
      if (json['type'] == 'FeatureCollection' && json['features'] != null) {
        for (final feature in json['features']) {
          try {
            final site = _parseFeature(feature);
            if (site != null) {
              sites.add(site);
            }
          } catch (e) {
            print('Error parsing feature: $e');
            // Continue with other features
          }
        }
      }
    } catch (e) {
      print('Error parsing GeoJSON: $e');
    }
    
    return sites;
  }

  /// Parse a single GeoJSON feature into a ParaglidingSite
  ParaglidingSite? _parseFeature(Map<String, dynamic> feature) {
    final geometry = feature['geometry'];
    final properties = feature['properties'];
    
    if (geometry == null || properties == null) return null;
    
    final coordinates = geometry['coordinates'] as List?;
    if (coordinates == null || coordinates.length < 2) return null;
    
    final longitude = (coordinates[0] as num).toDouble();
    final latitude = (coordinates[1] as num).toDouble();
    final altitude = coordinates.length > 2 ? (coordinates[2] as num?)?.toDouble() : null;

    // Map ParaglidingEarth properties to our model
    final name = properties['name']?.toString() ?? 'Unknown Site';
    final description = properties['description']?.toString() ?? '';
    final country = properties['country']?.toString();
    final region = properties['region']?.toString();
    
    // Determine site type based on API data
    String siteType = 'launch'; // Default
    
    // ParaglidingEarth doesn't explicitly separate launch/landing, 
    // so we'll classify based on altitude and name patterns
    if (name.toLowerCase().contains('landing') || 
        name.toLowerCase().contains('atterrissage') ||
        name.toLowerCase().contains('landeplatz')) {
      siteType = 'landing';
    }

    // Estimate rating based on available data (ParaglidingEarth doesn't provide ratings)
    int rating = 3; // Default middle rating
    if (description.isNotEmpty) rating = 4; // Sites with descriptions are likely better documented
    
    // Estimate popularity (not available in API, so we'll use a default)
    double popularity = 50.0;

    return ParaglidingSite(
      name: name,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude?.toInt(), // Convert double to int for altitude
      description: description,
      windDirections: [], // Not provided by API
      siteType: siteType,
      rating: rating,
      country: country,
      region: region,
      popularity: popularity,
    );
  }

  /// Get cached response if valid
  List<ParaglidingSite>? _getCachedResponse(String key) {
    final cached = _cache[key];
    if (cached != null && DateTime.now().isBefore(cached.expiry)) {
      print('ParaglidingEarth API: Using cached response for $key');
      return cached.sites;
    }
    return null;
  }

  /// Cache a response
  void _cacheResponse(String key, List<ParaglidingSite> sites) {
    _cache[key] = _CachedResponse(
      sites: sites,
      expiry: DateTime.now().add(_cacheExpiry),
    );
    
    // Clean up old cache entries
    _cleanupCache();
  }

  /// Remove expired cache entries
  void _cleanupCache() {
    final now = DateTime.now();
    _cache.removeWhere((key, cached) => now.isAfter(cached.expiry));
  }

  /// Clear all cached data
  void clearCache() {
    _cache.clear();
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    final now = DateTime.now();
    final validEntries = _cache.values.where((cached) => now.isBefore(cached.expiry)).length;
    
    return {
      'total_entries': _cache.length,
      'valid_entries': validEntries,
      'expired_entries': _cache.length - validEntries,
    };
  }
}

/// Cached API response
class _CachedResponse {
  final List<ParaglidingSite> sites;
  final DateTime expiry;

  _CachedResponse({
    required this.sites,
    required this.expiry,
  });
}