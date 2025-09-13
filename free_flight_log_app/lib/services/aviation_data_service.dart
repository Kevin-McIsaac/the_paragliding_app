import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart' as fm;

import '../data/models/airport.dart';
import '../data/models/navaid.dart';
import '../data/models/reporting_point.dart';
import '../services/logging_service.dart';
import '../services/openaip_service.dart';

/// Service for fetching different types of aviation data from OpenAIP Core API
class AviationDataService {
  static AviationDataService? _instance;
  static AviationDataService get instance => _instance ??= AviationDataService._();

  AviationDataService._();

  final OpenAipService _openAipService = OpenAipService.instance;

  // OpenAIP Core API configuration
  static const String _coreApiBase = 'https://api.core.openaip.net/api';
  static const int _defaultLimit = 500;
  static const Duration _requestTimeout = Duration(seconds: 30);

  // Cache for preventing duplicate requests
  final Map<String, List<Airport>> _airportCache = {};
  final Map<String, List<Navaid>> _navaidCache = {};
  final Map<String, List<ReportingPoint>> _reportingPointCache = {};

  /// Generate cache key from bounding box
  String _generateCacheKey(fm.LatLngBounds bounds) {
    return '${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)},'
           '${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}';
  }

  /// Build API URL with bounding box and optional API key
  String _buildApiUrl(String endpoint, fm.LatLngBounds bounds, {String? apiKey}) {
    var url = '$_coreApiBase/$endpoint'
        '?bbox=${bounds.west},${bounds.south},${bounds.east},${bounds.north}'
        '&limit=$_defaultLimit';

    if (apiKey != null && apiKey.isNotEmpty) {
      url += '&apiKey=$apiKey';
    }

    return url;
  }

  /// Fetch airports from OpenAIP Core API
  Future<List<Airport>> fetchAirports(fm.LatLngBounds bounds) async {
    final cacheKey = _generateCacheKey(bounds);

    // Check cache first
    if (_airportCache.containsKey(cacheKey)) {
      LoggingService.structured('AIRPORTS_CACHE_HIT', {
        'cache_key': cacheKey,
        'cached_count': _airportCache[cacheKey]!.length,
      });
      return _airportCache[cacheKey]!;
    }

    final apiKey = await _openAipService.getApiKey();
    final url = _buildApiUrl('airports', bounds, apiKey: apiKey);

    LoggingService.structured('AIRPORTS_API_REQUEST', {
      'url': url.replaceAll(RegExp(r'apiKey=[^&]*'), 'apiKey=***'),
      'bounds': '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
    });

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List? ?? [];

        final airports = features
            .map((feature) => Airport.fromJson(feature as Map<String, dynamic>))
            .toList();

        // Cache the results
        _airportCache[cacheKey] = airports;

        LoggingService.structured('AIRPORTS_API_SUCCESS', {
          'airports_count': airports.length,
          'cache_key': cacheKey,
        });

        return airports;
      } else {
        LoggingService.error('Airport API request failed',
          'Status: ${response.statusCode}, Body: ${response.body}');
        return [];
      }
    } catch (error, stackTrace) {
      LoggingService.error('Airport API request error', error, stackTrace);
      return [];
    }
  }

  /// Fetch navigation aids from OpenAIP Core API
  Future<List<Navaid>> fetchNavaids(fm.LatLngBounds bounds) async {
    final cacheKey = _generateCacheKey(bounds);

    // Check cache first
    if (_navaidCache.containsKey(cacheKey)) {
      LoggingService.structured('NAVAIDS_CACHE_HIT', {
        'cache_key': cacheKey,
        'cached_count': _navaidCache[cacheKey]!.length,
      });
      return _navaidCache[cacheKey]!;
    }

    final apiKey = await _openAipService.getApiKey();
    final url = _buildApiUrl('navaids', bounds, apiKey: apiKey);

    LoggingService.structured('NAVAIDS_API_REQUEST', {
      'url': url.replaceAll(RegExp(r'apiKey=[^&]*'), 'apiKey=***'),
      'bounds': '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
    });

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List? ?? [];

        final navaids = features
            .map((feature) => Navaid.fromJson(feature as Map<String, dynamic>))
            .toList();

        // Cache the results
        _navaidCache[cacheKey] = navaids;

        LoggingService.structured('NAVAIDS_API_SUCCESS', {
          'navaids_count': navaids.length,
          'cache_key': cacheKey,
        });

        return navaids;
      } else {
        LoggingService.error('Navaids API request failed',
          'Status: ${response.statusCode}, Body: ${response.body}');
        return [];
      }
    } catch (error, stackTrace) {
      LoggingService.error('Navaids API request error', error, stackTrace);
      return [];
    }
  }

  /// Fetch reporting points from OpenAIP Core API
  Future<List<ReportingPoint>> fetchReportingPoints(fm.LatLngBounds bounds) async {
    final cacheKey = _generateCacheKey(bounds);

    // Check cache first
    if (_reportingPointCache.containsKey(cacheKey)) {
      LoggingService.structured('REPORTING_POINTS_CACHE_HIT', {
        'cache_key': cacheKey,
        'cached_count': _reportingPointCache[cacheKey]!.length,
      });
      return _reportingPointCache[cacheKey]!;
    }

    final apiKey = await _openAipService.getApiKey();
    final url = _buildApiUrl('reporting-points', bounds, apiKey: apiKey);

    LoggingService.structured('REPORTING_POINTS_API_REQUEST', {
      'url': url.replaceAll(RegExp(r'apiKey=[^&]*'), 'apiKey=***'),
      'bounds': '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
    });

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List? ?? [];

        final reportingPoints = features
            .map((feature) => ReportingPoint.fromJson(feature as Map<String, dynamic>))
            .toList();

        // Cache the results
        _reportingPointCache[cacheKey] = reportingPoints;

        LoggingService.structured('REPORTING_POINTS_API_SUCCESS', {
          'reporting_points_count': reportingPoints.length,
          'cache_key': cacheKey,
        });

        return reportingPoints;
      } else {
        LoggingService.error('Reporting Points API request failed',
          'Status: ${response.statusCode}, Body: ${response.body}');
        return [];
      }
    } catch (error, stackTrace) {
      LoggingService.error('Reporting Points API request error', error, stackTrace);
      return [];
    }
  }

  /// Clear all caches (useful when API key changes or for memory management)
  void clearCaches() {
    _airportCache.clear();
    _navaidCache.clear();
    _reportingPointCache.clear();
    LoggingService.info('Aviation data caches cleared');
  }

  /// Get cache statistics for debugging
  Map<String, int> getCacheStats() {
    return {
      'airports': _airportCache.length,
      'navaids': _navaidCache.length,
      'reporting_points': _reportingPointCache.length,
    };
  }
}