import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../data/models/paragliding_site.dart';
import '../services/logging_service.dart';

/// Service for interacting with ParaglidingEarth.com API
/// Provides real-time site lookups with caching and fallback support
class ParaglidingEarthApi {
  static ParaglidingEarthApi? _instance;
  static ParaglidingEarthApi get instance => _instance ??= ParaglidingEarthApi._();
  
  ParaglidingEarthApi._();

  static const String _baseUrl = 'https://www.paraglidingearth.com/api/geojson';
  static const Duration _timeout = Duration(seconds: 10);
  static const int _defaultLimit = 10;
  
  // Persistent HTTP client for connection pooling
  static http.Client? _httpClient;
  static int _requestCount = 0;
  static const int _maxRequestsPerClient = 50; // Increased to reduce recreation overhead
  static DateTime? _clientCreatedAt;

  static http.Client get httpClient {
    if (_httpClient == null || _requestCount >= _maxRequestsPerClient) {
      // Close old client if exists
      if (_httpClient != null) {
        final clientAge = _clientCreatedAt != null
            ? DateTime.now().difference(_clientCreatedAt!).inSeconds
            : 0;
        LoggingService.info('ParaglidingEarthApi: Recreating HTTP client after $_requestCount requests (age: ${clientAge}s)');
        _httpClient!.close();
      }
      _httpClient = http.Client();
      _clientCreatedAt = DateTime.now();
      _requestCount = 0;
      LoggingService.info('[HTTP_CLIENT_CREATED] New client created for connection pooling');
    }
    return _httpClient!;
  }
  
  // Simple in-memory caching for site details and search results
  final Map<String, Map<String, dynamic>?> _siteDetailsCache = {};
  final Map<String, DateTime> _siteDetailsCacheExpiry = {};
  final Map<String, List<ParaglidingSite>> _searchResultsCache = {};
  final Map<String, DateTime> _searchResultsCacheExpiry = {};
  static const Duration _cacheTimeout = Duration(minutes: 15);
  static const int _maxCacheEntries = 50; // Prevent unlimited growth
  
  // Offline status tracking
  static bool _isOfflineMode = false;
  static DateTime? _lastSuccessfulRequest;
  static int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 3;

  // Simple cache management methods
  void _cleanupCache() {
    final now = DateTime.now();
    
    // Clean expired site details cache
    final expiredSiteKeys = _siteDetailsCacheExpiry.entries
        .where((entry) => entry.value.isBefore(now))
        .map((entry) => entry.key)
        .toList();
    for (final key in expiredSiteKeys) {
      _siteDetailsCache.remove(key);
      _siteDetailsCacheExpiry.remove(key);
    }
    
    // Clean expired search results cache  
    final expiredSearchKeys = _searchResultsCacheExpiry.entries
        .where((entry) => entry.value.isBefore(now))
        .map((entry) => entry.key)
        .toList();
    for (final key in expiredSearchKeys) {
      _searchResultsCache.remove(key);
      _searchResultsCacheExpiry.remove(key);
    }
    
    // If still too many entries, remove oldest ones
    if (_siteDetailsCache.length > _maxCacheEntries) {
      final sortedEntries = _siteDetailsCacheExpiry.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final keysToRemove = sortedEntries.take(_siteDetailsCache.length - _maxCacheEntries);
      for (final entry in keysToRemove) {
        _siteDetailsCache.remove(entry.key);
        _siteDetailsCacheExpiry.remove(entry.key);
      }
    }
    
    if (_searchResultsCache.length > _maxCacheEntries) {
      final sortedEntries = _searchResultsCacheExpiry.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final keysToRemove = sortedEntries.take(_searchResultsCache.length - _maxCacheEntries);
      for (final entry in keysToRemove) {
        _searchResultsCache.remove(entry.key);
        _searchResultsCacheExpiry.remove(entry.key);
      }
    }
  }

  /// Get sites around given coordinates
  /// Returns sites within [radiusKm] of the coordinates, ordered by distance
  Future<List<ParaglidingSite>> getSitesAroundCoordinates(
    double latitude,
    double longitude, {
    double radiusKm = 0.5, // 500m default - typical launch site search radius
    int limit = _defaultLimit,
    bool detailed = false, // Default to basic data for faster loading
  }) async {
    
    // Check if we're in offline mode
    if (_isOfflineMode) {
      LoggingService.warning('ParaglidingEarthApi: No data available in offline mode');
      return [];
    }

    // Retry logic with exponential backoff
    int retries = 0;
    Duration delay = Duration(seconds: 1);
    
    while (retries < 3) {
      try {
        if (retries > 0) {
          LoggingService.info('ParaglidingEarthApi: Retry attempt ${retries + 1} after ${delay.inSeconds}s');
          await Future.delayed(delay);
        }
        
        final url = Uri.parse('$_baseUrl/getAroundLatLngSites.php').replace(
          queryParameters: {
            'lat': latitude.toString(),
            'lng': longitude.toString(),
            'distance': radiusKm.toString(),
            'limit': limit.toString(),
            if (detailed) 'style': 'detailled',
          },
        );

        LoggingService.info('ParaglidingEarthApi: Fetching sites around $latitude, $longitude (${radiusKm}km)');

        final response = await httpClient.get(url).timeout(_timeout);
        _requestCount++; // Increment request counter
        
        if (response.statusCode == 200) {
          final sites = _parseGeoJsonResponse(response.body);
          
          // Mark successful request
          _markRequestSuccess();
          
          LoggingService.info('ParaglidingEarthApi: Found ${sites.length} sites');
          return sites;
        } else {
          LoggingService.warning('ParaglidingEarthApi: HTTP ${response.statusCode} - ${response.reasonPhrase}');
          _markRequestFailure();
          return [];
        }
      } on SocketException catch (e) {
        retries++;
        
        // Enhanced error logging
        if (e.message.contains('Failed host lookup')) {
          LoggingService.error('ParaglidingEarthApi: DNS lookup failed for paraglidingearth.com', e);
          LoggingService.info('ParaglidingEarthApi: This may indicate rate limiting or network issues');
        } else {
          LoggingService.error('ParaglidingEarthApi: Network error', e);
        }
        
        if (retries >= 3) {
          LoggingService.error('ParaglidingEarthApi: Failed after 3 attempts', e);
          _markRequestFailure();
          
          return [];
        }
        
        delay = Duration(seconds: delay.inSeconds * 2); // Exponential backoff
      } on TimeoutException catch (e) {
        retries++;
        LoggingService.error('ParaglidingEarthApi: Request timeout after ${_timeout.inSeconds}s', e);
        
        if (retries >= 3) {
          return [];
        }
        
        delay = Duration(seconds: delay.inSeconds * 2);
      } catch (e) {
        LoggingService.error('ParaglidingEarthApi: Unexpected error', e);
        return [];
      }
    }
    
    return [];
  }

  /// Find the nearest site to given coordinates
  /// Returns the closest site within [maxDistanceKm], or null if none found
  Future<ParaglidingSite?> findNearestSite(
    double latitude,
    double longitude, {
    double maxDistanceKm = 0.5, // 500m default - typical launch site search radius
    String? preferredType, // 'launch' or null for any (landing sites not typically used)
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
    final stopwatch = Stopwatch()..start();
    final timingBreakdown = <String, int>{};

    try {
      // Track URL creation time
      final urlStart = stopwatch.elapsedMilliseconds;
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
      timingBreakdown['url_creation_ms'] = stopwatch.elapsedMilliseconds - urlStart;

      LoggingService.info('ParaglidingEarthApi: Fetching sites in bounds');

      // Check if this is the first request (cold start)
      final isFirstRequest = _requestCount == 0;
      if (isFirstRequest) {
        LoggingService.info('[COLD_START] First API request - expecting longer response time');
      }

      // Track DNS resolution separately for first request
      if (isFirstRequest) {
        final dnsStart = stopwatch.elapsedMilliseconds;
        try {
          await InternetAddress.lookup('www.paraglidingearth.com');
          timingBreakdown['dns_lookup_ms'] = stopwatch.elapsedMilliseconds - dnsStart;
          LoggingService.info('[DNS_TIMING] DNS lookup took ${timingBreakdown['dns_lookup_ms']}ms');
        } catch (e) {
          LoggingService.error('[DNS_ERROR] Failed to resolve paraglidingearth.com', e);
        }
      }

      // Track HTTP request time
      final httpStart = stopwatch.elapsedMilliseconds;
      final response = await httpClient.get(url).timeout(_timeout);
      timingBreakdown['http_request_ms'] = stopwatch.elapsedMilliseconds - httpStart;

      _requestCount++; // Increment request counter

      if (response.statusCode == 200) {
        // Track parsing time
        final parseStart = stopwatch.elapsedMilliseconds;
        final sites = _parseGeoJsonResponse(response.body);
        timingBreakdown['parse_response_ms'] = stopwatch.elapsedMilliseconds - parseStart;
        stopwatch.stop();

        // Log detailed timing breakdown
        LoggingService.structured('API_TIMING_BREAKDOWN', {
          'is_cold_start': isFirstRequest,
          'request_number': _requestCount,
          'total_ms': stopwatch.elapsedMilliseconds,
          ...timingBreakdown,
          'sites_count': sites.length,
          'response_size_bytes': response.body.length,
        });

        LoggingService.performance(
          'Paragliding Earth API',
          Duration(milliseconds: stopwatch.elapsedMilliseconds),
          'sites=${sites.length}, bounds=$west,$south,$east,$north, cold_start=$isFirstRequest'
        );

        LoggingService.info('ParaglidingEarthApi: Found ${sites.length} sites in bounds');
        return sites;
      } else {
        stopwatch.stop();
        LoggingService.performance(
          'Paragliding Earth API (Failed)',
          Duration(milliseconds: stopwatch.elapsedMilliseconds),
          'status=${response.statusCode}'
        );

        LoggingService.warning('ParaglidingEarthApi: HTTP ${response.statusCode} - ${response.reasonPhrase}');
        return [];
      }
    } catch (e) {
      stopwatch.stop();

      LoggingService.performance(
        'Paragliding Earth API (Error)',
        Duration(milliseconds: stopwatch.elapsedMilliseconds),
        'error=true'
      );

      LoggingService.error('ParaglidingEarthApi: API error', e);
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
            LoggingService.error('ParaglidingEarthApi: Error parsing feature', e);
            // Continue with other features
          }
        }
      }
    } catch (e) {
      LoggingService.error('ParaglidingEarthApi: Error parsing GeoJSON', e);
    }
    
    // Filter to only show launch sites (exclude landing sites)
    final launchSites = sites.where((site) => site.siteType == 'launch').toList();
    return launchSites;
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

    // Map ParaglidingEarth properties to our model (basic fields only)
    final name = properties['name']?.toString() ?? 'Unknown Site';
    final description = properties['description']?.toString() ?? '';
    
    // ParaglidingEarth API uses 'countryCode' field (e.g., "at", "ch", "fr")
    final countryCode = properties['countryCode']?.toString();
    final country = countryCode != null ? _countryCodeToName(countryCode) : null;
    
    // ParaglidingEarth API doesn't provide region/state information
    final region = null;
    
    // Parse wind directions from flags (0=no, 1=good, 2=excellent) for basic info
    final windDirections = <String>[];
    final windMap = {
      'N': properties['N']?.toString(),
      'NE': properties['NE']?.toString(),
      'E': properties['E']?.toString(),
      'SE': properties['SE']?.toString(),
      'S': properties['S']?.toString(),
      'SW': properties['SW']?.toString(),
      'W': properties['W']?.toString(),
      'NW': properties['NW']?.toString(),
    };
    
    windMap.forEach((direction, value) {
      if (value == '1' || value == '2') {
        windDirections.add(direction);
      }
    });
    
    // Determine site type based on API data
    String siteType = 'launch'; // Default to launch
    
    // ParaglidingEarth doesn't explicitly separate launch/landing, 
    // but we can detect landing sites from name patterns
    if (name.toLowerCase().contains('landing') || 
        name.toLowerCase().contains('atterrissage') ||
        name.toLowerCase().contains('landeplatz')) {
      siteType = 'landing';
    }

    // API doesn't provide rating data
    
    // Estimate popularity (not available in API)
    double popularity = 50.0;

    return ParaglidingSite(
      name: name,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude?.toInt(), // Convert double to int for altitude
      description: description,
      windDirections: windDirections,
      siteType: siteType,
      rating: null,
      country: country,
      region: region,
      popularity: popularity,
    );
  }

  /// Get detailed information for a specific site
  /// Returns detailed site data for display in dialog
  Future<Map<String, dynamic>?> getSiteDetails(double latitude, double longitude, {int? siteId}) async {
    
    // Check cache first
    final cacheKey = '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
    final now = DateTime.now();
    
    if (_siteDetailsCache.containsKey(cacheKey) && 
        _siteDetailsCacheExpiry.containsKey(cacheKey) &&
        _siteDetailsCacheExpiry[cacheKey]!.isAfter(now)) {
      LoggingService.info('ParaglidingEarthApi: Using cached site details');
      return _siteDetailsCache[cacheKey];
    }
    
    // Clean up expired cache entries occasionally
    if (_siteDetailsCache.length > 10) {
      _cleanupCache();
    }
    
    try {
      // Use the bounding box API which works reliably for all sites
      // Create a small bounding box (±0.001 degrees ≈ 100 meters) around the site
      // Larger epsilon prevents precision issues with coordinate storage
      final epsilon = 0.001; // ~100 meter box
      final url = Uri.parse('https://www.paraglidingearth.com/api/getBoundingBoxSites.php').replace(
        queryParameters: {
          'north': (latitude + epsilon).toString(),
          'south': (latitude - epsilon).toString(),
          'east': (longitude + epsilon).toString(),
          'west': (longitude - epsilon).toString(),
          'style': 'detailled', // Get detailed data
        },
      );

      LoggingService.info('ParaglidingEarthApi: Fetching detailed data for site at $latitude, $longitude (siteId: $siteId)');
      LoggingService.info('ParaglidingEarthApi: Request URL: $url');

      final response = await httpClient.get(url).timeout(_timeout);
      _requestCount++;

      if (response.statusCode == 200) {
        // Parse XML response
        final document = XmlDocument.parse(response.body);
        final takeoffElements = document.findAllElements('takeoff').toList();

        LoggingService.info('ParaglidingEarthApi: Found ${takeoffElements.length} site(s) in bounding box');

        // If we have a site ID, try to find the matching site
        XmlElement? takeoffElement;
        if (siteId != null && takeoffElements.length > 1) {
          // Multiple sites found - look for the one with matching ID
          for (final element in takeoffElements) {
            final idElement = element.findElements('id').firstOrNull;
            if (idElement != null && idElement.innerText.trim() == siteId.toString()) {
              takeoffElement = element;
              LoggingService.info('ParaglidingEarthApi: Matched site by ID: $siteId');
              break;
            }
          }
        }

        // If no ID match or only one result, use the first one
        if (takeoffElement == null && takeoffElements.isNotEmpty) {
          takeoffElement = takeoffElements.first;
          if (takeoffElements.length > 1) {
            LoggingService.warning('ParaglidingEarthApi: Multiple sites found but using first one (no ID match)');
          }
        }

        if (takeoffElement != null) {
          final Map<String, dynamic> properties = {};
          
          // Extract all child elements
          for (final element in takeoffElement.children.whereType<XmlElement>()) {
            final text = element.innerText.trim();
            if (text.isNotEmpty) {
              properties[element.name.local] = text;
            }
          }
          
          // Also extract orientations
          final orientationsElement = takeoffElement.findElements('orientations').firstOrNull;
          if (orientationsElement != null) {
            final Map<String, dynamic> orientations = {};
            for (final element in orientationsElement.children.whereType<XmlElement>()) {
              orientations[element.name.local] = element.innerText;
            }
            properties['orientations'] = orientations;
          }

          // Extract landing information (landing is a sibling of takeoff in the XML structure)
          final landingElement = document.findAllElements('landing').firstOrNull;
          if (landingElement != null) {
            final Map<String, dynamic> landing = {};
            for (final element in landingElement.children.whereType<XmlElement>()) {
              final text = element.innerText.trim();
              if (text.isNotEmpty) {
                landing[element.name.local] = text;
              }
            }
            properties['landing'] = landing;

            // Also flatten landing info for easy access
            if (landing['landing_altitude'] != null) {
              properties['landing_altitude'] = landing['landing_altitude'];
            }
            if (landing['landing_description'] != null) {
              properties['landing_description'] = landing['landing_description'];
            }
            if (landing['landing_lat'] != null) {
              properties['landing_lat'] = landing['landing_lat'];
            }
            if (landing['landing_lng'] != null) {
              properties['landing_lng'] = landing['landing_lng'];
            }
          }
          
          LoggingService.info('ParaglidingEarthApi: Found detailed data for site');
          LoggingService.info('ParaglidingEarthApi: Parsed fields: ${properties.keys.toList()}');
          
          // Store in cache for future use
          _siteDetailsCache[cacheKey] = properties;
          _siteDetailsCacheExpiry[cacheKey] = now.add(_cacheTimeout);
          
          return properties;
        }
        
        LoggingService.warning('ParaglidingEarthApi: No detailed data found for site');
        return null;
      } else {
        LoggingService.warning('ParaglidingEarthApi: HTTP ${response.statusCode} for site details');
        return null;
      }
    } catch (e) {
      LoggingService.error('ParaglidingEarthApi: Error getting site details', e);
      return null;
    }
  }

  /// Convert ISO country code to full country name
  String _countryCodeToName(String countryCode) {
    // Map of common ISO 3166-1 alpha-2 country codes to full names
    // Focus on European countries where paragliding is popular
    final countryMap = <String, String>{
      'ad': 'Andorra',
      'at': 'Austria', 
      'be': 'Belgium',
      'bg': 'Bulgaria',
      'ch': 'Switzerland',
      'cz': 'Czech Republic',
      'de': 'Germany',
      'dk': 'Denmark',
      'es': 'Spain',
      'fi': 'Finland',
      'fr': 'France',
      'gb': 'United Kingdom',
      'gr': 'Greece',
      'hr': 'Croatia',
      'hu': 'Hungary',
      'ie': 'Ireland',
      'is': 'Iceland',
      'it': 'Italy',
      'li': 'Liechtenstein',
      'lu': 'Luxembourg',
      'mc': 'Monaco',
      'mt': 'Malta',
      'nl': 'Netherlands',
      'no': 'Norway',
      'pl': 'Poland',
      'pt': 'Portugal',
      'ro': 'Romania',
      'se': 'Sweden',
      'si': 'Slovenia',
      'sk': 'Slovakia',
      'sm': 'San Marino',
      'va': 'Vatican City',
      
      // Other popular paragliding countries
      'us': 'United States',
      'ca': 'Canada',
      'mx': 'Mexico',
      'br': 'Brazil',
      'ar': 'Argentina',
      'cl': 'Chile',
      'co': 'Colombia',
      'pe': 'Peru',
      'au': 'Australia',
      'nz': 'New Zealand',
      'za': 'South Africa',
      'ma': 'Morocco',
      'tn': 'Tunisia',
      'eg': 'Egypt',
      'tr': 'Turkey',
      'il': 'Israel',
      'jo': 'Jordan',
      'lb': 'Lebanon',
      'in': 'India',
      'np': 'Nepal',
      'pk': 'Pakistan',
      'cn': 'China',
      'jp': 'Japan',
      'kr': 'South Korea',
      'th': 'Thailand',
      'vn': 'Vietnam',
      'id': 'Indonesia',
      'my': 'Malaysia',
      'ph': 'Philippines',
    };
    
    final lowerCode = countryCode.toLowerCase();
    return countryMap[lowerCode] ?? countryCode.toUpperCase(); // Fallback to uppercase code
  }

  /// Mark successful API request
  static void _markRequestSuccess() {
    _consecutiveFailures = 0;
    _lastSuccessfulRequest = DateTime.now();
    if (_isOfflineMode) {
      _isOfflineMode = false;
      LoggingService.info('ParaglidingEarthApi: Back online after successful request');
    }
  }
  
  /// Mark failed API request and check if we should enter offline mode
  static void _markRequestFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _maxConsecutiveFailures && !_isOfflineMode) {
      _isOfflineMode = true;
      LoggingService.warning('ParaglidingEarthApi: Entering offline mode after $_consecutiveFailures consecutive failures');
    }
  }
  
  /// Check if API is currently in offline mode
  static bool get isOfflineMode => _isOfflineMode;
  
  /// Get offline status information
  static Map<String, dynamic> getOfflineStatus() {
    return {
      'is_offline_mode': _isOfflineMode,
      'consecutive_failures': _consecutiveFailures,
      'last_successful_request': _lastSuccessfulRequest?.toIso8601String(),
      'time_since_last_success_hours': _lastSuccessfulRequest != null 
          ? DateTime.now().difference(_lastSuccessfulRequest!).inHours 
          : null,
    };
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'total_entries': 0,
      'valid_entries': 0,
      'expired_entries': 0,
      ...getOfflineStatus(),
    };
  }
  
  /// Search sites by name using PGE search API
  Future<List<ParaglidingSite>> searchSitesByName(String query) async {
    if (query.isEmpty || query.length < 2) return [];
    
    
    // Check cache first
    final cacheKey = query.toLowerCase().trim();
    final now = DateTime.now();
    
    if (_searchResultsCache.containsKey(cacheKey) && 
        _searchResultsCacheExpiry.containsKey(cacheKey) &&
        _searchResultsCacheExpiry[cacheKey]!.isAfter(now)) {
      LoggingService.info('ParaglidingEarthApi: Using cached search results for: $query');
      return _searchResultsCache[cacheKey]!;
    }
    
    // Clean up expired cache entries occasionally
    if (_searchResultsCache.length > 10) {
      _cleanupCache();
    }
    
    LoggingService.info('ParaglidingEarthApi: Searching sites by name: $query');
    
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = Uri.parse('https://paraglidingearth.com/assets/ajax/searchSitesJSON.php?name=$encodedQuery');
      
      final response = await httpClient.get(url).timeout(_timeout);
      _requestCount++;
      
      if (response.statusCode == 200) {
        final List<ParaglidingSite> sites = [];
        final json = jsonDecode(response.body);
        
        if (json['features'] != null && json['features'] is List) {
          for (final feature in json['features']) {
            try {
              final site = _parseSearchResult(feature);
              if (site != null) {
                sites.add(site);
              }
            } catch (e) {
              LoggingService.error('ParaglidingEarthApi: Error parsing search result', e);
            }
          }
        }
        
        LoggingService.info('ParaglidingEarthApi: Found ${sites.length} sites for query: $query');
        _markRequestSuccess();
        
        // Store in cache for future use
        _searchResultsCache[cacheKey] = sites;
        _searchResultsCacheExpiry[cacheKey] = now.add(_cacheTimeout);
        
        
        return sites;
      } else {
        LoggingService.warning('ParaglidingEarthApi: Search HTTP ${response.statusCode} - ${response.reasonPhrase}');
        _markRequestFailure();
        
        
        return [];
      }
    } catch (e) {
      LoggingService.error('ParaglidingEarthApi: Search API error for query: $query', e);
      _markRequestFailure();
      
      
      return [];
    }
  }

  /// Parse search result from PGE search API
  ParaglidingSite? _parseSearchResult(Map<String, dynamic> feature) {
    try {
      final id = feature['id']?.toString();
      final name = feature['name']?.toString() ?? 'Unknown Site';
      final countryCode = feature['countryCode']?.toString();
      final latitude = (feature['lat'] as num?)?.toDouble();
      final longitude = (feature['lng'] as num?)?.toDouble();
      
      if (latitude == null || longitude == null) return null;
      
      final country = countryCode != null ? _countryCodeToName(countryCode) : null;
      
      return ParaglidingSite(
        id: id != null ? int.tryParse(id) : null,
        name: name,
        latitude: latitude,
        longitude: longitude,
        altitude: null,
        description: '',
        windDirections: [],
        siteType: 'launch', // Default for search results
        rating: null,
        country: country,
        region: null,
        popularity: null,
      );
    } catch (e) {
      LoggingService.error('ParaglidingEarthApi: Error parsing search result', e);
      return null;
    }
  }

  /// Clean up resources - call this after batch operations or when app suspends
  static void cleanup() {
    _httpClient?.close();
    _httpClient = null;
    _requestCount = 0;
    LoggingService.info('ParaglidingEarthApi: HTTP client cleaned up');
  }
}

/// Cached API response
