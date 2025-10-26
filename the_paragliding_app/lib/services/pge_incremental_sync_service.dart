import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../services/logging_service.dart';
import '../data/datasources/database_helper.dart';

/// Result of a PGE sites synchronization operation
class SyncResult {
  final int sitesAdded;
  final int sitesModified;
  final int totalProcessed;
  final DateTime? lastEditDate;
  final Duration duration;
  final String? errorMessage;

  const SyncResult({
    required this.sitesAdded,
    required this.sitesModified,
    required this.totalProcessed,
    this.lastEditDate,
    required this.duration,
    this.errorMessage,
  });

  bool get success => errorMessage == null;

  @override
  String toString() {
    if (!success) return 'Sync failed: $errorMessage';
    return 'Sync completed: $totalProcessed sites ($sitesAdded new, $sitesModified updated) in ${duration.inSeconds}s';
  }
}

/// Service for incrementally syncing PGE sites database
class PgeIncrementalSyncService {
  static final PgeIncrementalSyncService instance = PgeIncrementalSyncService._();
  PgeIncrementalSyncService._();

  /// Base URL for PGE API
  static const String _baseUrl = 'http://www.paraglidingearth.com/api/geojson/getModifiedSites.php';

  /// HTTP client for API requests
  static http.Client? _httpClient;
  static http.Client get httpClient {
    if (_httpClient == null) {
      _httpClient = http.Client();
      LoggingService.info('[PGE_SYNC] HTTP client created for sync operations');
    }
    return _httpClient!;
  }

  /// Sync modified sites from PGE API to local database
  ///
  /// Simple approach:
  /// 1. Find most recent last_edit in local DB
  /// 2. Fetch sites modified after that date from API (basic data only)
  /// 3. Upsert into local DB
  Future<SyncResult> syncModifiedSites() async {
    final startTime = DateTime.now();

    try {
      LoggingService.info('[PGE_SYNC] Starting incremental sync');

      // Step 1: Get most recent last_edit from local DB
      final maxLastEdit = await _getMaxLastEdit();
      LoggingService.info('[PGE_SYNC] Most recent local site: $maxLastEdit');

      // Step 2: Fetch modified sites from API (basic data only)
      final modifiedSites = await _fetchModifiedSites(maxLastEdit);
      LoggingService.info('[PGE_SYNC] Fetched ${modifiedSites.length} modified sites from API');

      if (modifiedSites.isEmpty) {
        final duration = DateTime.now().difference(startTime);
        LoggingService.info('[PGE_SYNC] No new sites to sync');
        final parsedMaxEdit = maxLastEdit != null ? DateTime.tryParse(maxLastEdit) : null;
        return SyncResult(
          sitesAdded: 0,
          sitesModified: 0,
          totalProcessed: 0,
          lastEditDate: parsedMaxEdit,
          duration: duration,
        );
      }

      // Step 3: Upsert into local DB
      final result = await _upsertSites(modifiedSites);

      final duration = DateTime.now().difference(startTime);

      LoggingService.structured('PGE_SYNC_COMPLETED', {
        'sites_added': result.sitesAdded,
        'sites_modified': result.sitesModified,
        'total_processed': modifiedSites.length,
        'duration_ms': duration.inMilliseconds,
      });

      return SyncResult(
        sitesAdded: result.sitesAdded,
        sitesModified: result.sitesModified,
        totalProcessed: modifiedSites.length,
        lastEditDate: result.lastEditDate,
        duration: duration,
      );

    } catch (error, stackTrace) {
      final duration = DateTime.now().difference(startTime);
      LoggingService.error('[PGE_SYNC] Sync failed', error, stackTrace);

      return SyncResult(
        sitesAdded: 0,
        sitesModified: 0,
        totalProcessed: 0,
        duration: duration,
        errorMessage: error.toString(),
      );
    }
  }

  /// Get the most recent last_edit date from local database
  Future<String?> _getMaxLastEdit() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.rawQuery(
        'SELECT MAX(last_edit) as max_date FROM pge_sites WHERE last_edit IS NOT NULL'
      );

      if (result.isNotEmpty && result.first['max_date'] != null) {
        return result.first['max_date'] as String;
      }

      return null;
    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SYNC] Failed to get max last_edit', error, stackTrace);
      return null;
    }
  }

  /// Fetch modified sites from PGE API
  ///
  /// Uses date parameter in YYYYMMDD format (no dashes)
  /// Returns basic site data (not detailed)
  Future<List<Map<String, dynamic>>> _fetchModifiedSites(String? lastEdit) async {
    try {
      // Convert YYYY-MM-DD to YYYYMMDD format for API
      String dateParam;
      if (lastEdit != null && lastEdit.isNotEmpty) {
        dateParam = lastEdit.replaceAll('-', '');
        LoggingService.info('[PGE_SYNC] Requesting sites modified after: $lastEdit ($dateParam)');
      } else {
        // If no local data, get sites from 30 days ago
        final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
        dateParam = '${thirtyDaysAgo.year}${thirtyDaysAgo.month.toString().padLeft(2, '0')}${thirtyDaysAgo.day.toString().padLeft(2, '0')}';
        LoggingService.info('[PGE_SYNC] No local data, requesting sites from last 30 days');
      }

      final url = '$_baseUrl?date=$dateParam';
      LoggingService.structured('PGE_SYNC_API_REQUEST', {
        'url': url,
        'date_param': dateParam,
      });

      final response = await httpClient.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'TheParaglidingApp/1.0',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('PGE API returned status ${response.statusCode}');
      }

      final jsonData = json.decode(response.body);

      if (jsonData is! Map || jsonData['type'] != 'FeatureCollection') {
        throw Exception('Invalid GeoJSON response from PGE API');
      }

      final features = jsonData['features'] as List? ?? [];
      final sites = <Map<String, dynamic>>[];

      for (final feature in features) {
        try {
          final properties = feature['properties'] as Map<String, dynamic>;
          final geometry = feature['geometry'] as Map<String, dynamic>;
          final coordinates = geometry['coordinates'] as List;

          // Parse site data matching our DB schema
          sites.add({
            'id': properties['pge_site_id'] ?? 0,
            'name': properties['name'] ?? '',
            'longitude': coordinates[0] as double? ?? 0.0,
            'latitude': coordinates[1] as double? ?? 0.0,
            'altitude': _parseAltitude(properties['takeoff_altitude']),
            'country': properties['countryCode'] ?? '',
            'wind_n': _parseWindRating(properties['N']),
            'wind_ne': _parseWindRating(properties['NE']),
            'wind_e': _parseWindRating(properties['E']),
            'wind_se': _parseWindRating(properties['SE']),
            'wind_s': _parseWindRating(properties['S']),
            'wind_sw': _parseWindRating(properties['SW']),
            'wind_w': _parseWindRating(properties['W']),
            'wind_nw': _parseWindRating(properties['NW']),
            'last_edit': properties['last_edit'] ?? '',
          });
        } catch (e) {
          LoggingService.warning('[PGE_SYNC] Failed to parse feature: $e');
          continue;
        }
      }

      LoggingService.structured('PGE_SYNC_API_SUCCESS', {
        'sites_fetched': sites.length,
        'response_size': response.body.length,
      });

      return sites;

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SYNC] Failed to fetch modified sites', error, stackTrace);
      rethrow;
    }
  }

  /// Parse altitude value handling empty strings and null
  int? _parseAltitude(dynamic value) {
    if (value == null || value == '') return null;
    if (value is int) return value;
    if (value is double) return value.floor();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed;
    }
    return null;
  }

  /// Parse wind rating handling empty strings and null
  int _parseWindRating(dynamic value) {
    if (value == null || value == '') return 0;
    if (value is int) return value;
    if (value is double) return value.floor();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed ?? 0;
    }
    return 0;
  }

  /// Upsert sites into local database
  ///
  /// Uses INSERT OR REPLACE to update existing sites or add new ones
  /// Returns count of new vs modified sites
  Future<({int sitesAdded, int sitesModified, DateTime? lastEditDate})> _upsertSites(
    List<Map<String, dynamic>> sites,
  ) async {
    if (sites.isEmpty) {
      return (sitesAdded: 0, sitesModified: 0, lastEditDate: null);
    }

    try {
      final db = await DatabaseHelper.instance.database;
      int sitesAdded = 0;
      int sitesModified = 0;
      String? maxLastEdit;

      await db.transaction((txn) async {
        for (final site in sites) {
          // Check if site already exists
          final existing = await txn.query(
            'pge_sites',
            where: 'id = ?',
            whereArgs: [site['id']],
            limit: 1,
          );

          final isNewSite = existing.isEmpty;

          // Insert or replace site
          await txn.insert(
            'pge_sites',
            {
              'id': site['id'],
              'name': site['name'] ?? '',
              'longitude': site['longitude'],
              'latitude': site['latitude'],
              'altitude': site['altitude'],
              'country': site['country'] ?? '',
              'wind_n': site['wind_n'],
              'wind_ne': site['wind_ne'],
              'wind_e': site['wind_e'],
              'wind_se': site['wind_se'],
              'wind_s': site['wind_s'],
              'wind_sw': site['wind_sw'],
              'wind_w': site['wind_w'],
              'wind_nw': site['wind_nw'],
              'last_edit': site['last_edit'] ?? '',
              // Preserve is_favorite if it exists
              'is_favorite': existing.isNotEmpty ? existing.first['is_favorite'] : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          if (isNewSite) {
            sitesAdded++;
          } else {
            sitesModified++;
          }

          // Track most recent last_edit
          final lastEdit = site['last_edit'] as String?;
          if (lastEdit != null && lastEdit.isNotEmpty) {
            if (maxLastEdit == null || lastEdit.compareTo(maxLastEdit!) > 0) {
              maxLastEdit = lastEdit;
            }
          }
        }
      });

      LoggingService.structured('PGE_SYNC_UPSERT_COMPLETED', {
        'sites_added': sitesAdded,
        'sites_modified': sitesModified,
        'max_last_edit': maxLastEdit,
      });

      // Parse last edit date - use local variable for null safety
      final lastEditStr = maxLastEdit;
      DateTime? parsedDate;
      if (lastEditStr != null && lastEditStr.isNotEmpty) {
        parsedDate = DateTime.tryParse(lastEditStr);
      }

      return (
        sitesAdded: sitesAdded,
        sitesModified: sitesModified,
        lastEditDate: parsedDate,
      );

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SYNC] Failed to upsert sites', error, stackTrace);
      rethrow;
    }
  }

  /// Clean up resources
  void dispose() {
    _httpClient?.close();
    _httpClient = null;
  }
}
