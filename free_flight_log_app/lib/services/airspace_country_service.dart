import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/logging_service.dart';
import '../services/airspace_metadata_cache.dart';
import '../services/airspace_geometry_cache.dart';
import '../services/airspace_disk_cache.dart';
import '../data/models/airspace_country_models.dart';

/// Service for managing country-based airspace data
class AirspaceCountryService {
  static AirspaceCountryService? _instance;
  static AirspaceCountryService get instance => _instance ??= AirspaceCountryService._();

  AirspaceCountryService._();

  // Google Storage configuration
  static const String _storageBaseUrl = 'https://storage.googleapis.com/29f98e10-a489-4c82-ae5e-489dbcd4912f';
  static const Duration _requestTimeout = Duration(minutes: 2); // Longer timeout for large files

  // Preferences keys
  static const String _selectedCountriesKey = 'airspace_selected_countries';
  static const String _countryMetadataKey = 'airspace_country_metadata';

  // Cache references
  final AirspaceMetadataCache _metadataCache = AirspaceMetadataCache.instance;
  final AirspaceGeometryCache _geometryCache = AirspaceGeometryCache.instance;
  final AirspaceDiskCache _diskCache = AirspaceDiskCache.instance;

  // Available countries with metadata
  static final Map<String, CountryInfo> availableCountries = {
    'AU': CountryInfo(code: 'AU', name: 'Australia', estimatedSizeMB: 13),
    'NZ': CountryInfo(code: 'NZ', name: 'New Zealand', estimatedSizeMB: 3),
    'US': CountryInfo(code: 'US', name: 'United States', estimatedSizeMB: 50),
    'CA': CountryInfo(code: 'CA', name: 'Canada', estimatedSizeMB: 25),
    'GB': CountryInfo(code: 'GB', name: 'United Kingdom', estimatedSizeMB: 8),
    'IE': CountryInfo(code: 'IE', name: 'Ireland', estimatedSizeMB: 2),
    'DE': CountryInfo(code: 'DE', name: 'Germany', estimatedSizeMB: 10),
    'FR': CountryInfo(code: 'FR', name: 'France', estimatedSizeMB: 12),
    'ES': CountryInfo(code: 'ES', name: 'Spain', estimatedSizeMB: 8),
    'IT': CountryInfo(code: 'IT', name: 'Italy', estimatedSizeMB: 7),
    'CH': CountryInfo(code: 'CH', name: 'Switzerland', estimatedSizeMB: 3),
    'AT': CountryInfo(code: 'AT', name: 'Austria', estimatedSizeMB: 3),
    'NL': CountryInfo(code: 'NL', name: 'Netherlands', estimatedSizeMB: 4),
    'BE': CountryInfo(code: 'BE', name: 'Belgium', estimatedSizeMB: 3),
    'SE': CountryInfo(code: 'SE', name: 'Sweden', estimatedSizeMB: 5),
    'NO': CountryInfo(code: 'NO', name: 'Norway', estimatedSizeMB: 6),
    'FI': CountryInfo(code: 'FI', name: 'Finland', estimatedSizeMB: 4),
    'DK': CountryInfo(code: 'DK', name: 'Denmark', estimatedSizeMB: 3),
    'PL': CountryInfo(code: 'PL', name: 'Poland', estimatedSizeMB: 6),
    'CZ': CountryInfo(code: 'CZ', name: 'Czech Republic', estimatedSizeMB: 3),
    'PT': CountryInfo(code: 'PT', name: 'Portugal', estimatedSizeMB: 4),
    'GR': CountryInfo(code: 'GR', name: 'Greece', estimatedSizeMB: 5),
    'ZA': CountryInfo(code: 'ZA', name: 'South Africa', estimatedSizeMB: 8),
    'JP': CountryInfo(code: 'JP', name: 'Japan', estimatedSizeMB: 10),
    'KR': CountryInfo(code: 'KR', name: 'South Korea', estimatedSizeMB: 5),
    'IN': CountryInfo(code: 'IN', name: 'India', estimatedSizeMB: 15),
    'BR': CountryInfo(code: 'BR', name: 'Brazil', estimatedSizeMB: 20),
    'AR': CountryInfo(code: 'AR', name: 'Argentina', estimatedSizeMB: 10),
    'CL': CountryInfo(code: 'CL', name: 'Chile', estimatedSizeMB: 8),
    'MX': CountryInfo(code: 'MX', name: 'Mexico', estimatedSizeMB: 12),
  };

  /// Get list of selected countries
  Future<List<String>> getSelectedCountries() async {
    final prefs = await SharedPreferences.getInstance();
    final countries = prefs.getStringList(_selectedCountriesKey) ?? [];

    LoggingService.info('Retrieved ${countries.length} selected countries: ${countries.join(", ")}');
    return countries;
  }

  /// Set selected countries
  Future<void> setSelectedCountries(List<String> countryCodes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedCountriesKey, countryCodes);

    LoggingService.info('Updated selected countries: ${countryCodes.join(", ")}');
  }

  /// Get metadata for all countries from database
  Future<Map<String, CountryMetadata>> getCountryMetadata() async {
    try {
      final countryDetails = await _diskCache.getCountryDetails();
      final Map<String, CountryMetadata> metadata = {};

      for (final details in countryDetails) {
        final countryCode = details['country_code'] as String;
        final airspaceCount = details['airspace_count'] as int? ?? 0;
        final fetchTime = details['fetch_time'] as int?;
        final sizeBytes = details['size_bytes'] as int?;

        metadata[countryCode] = CountryMetadata(
          countryCode: countryCode,
          airspaceCount: airspaceCount,
          downloadTime: fetchTime != null
              ? DateTime.fromMillisecondsSinceEpoch(fetchTime)
              : DateTime.now(),
          etag: null, // Not stored in database
          lastModified: null, // Not stored in database
          version: 1,
        );
      }

      return metadata;
    } catch (e, stack) {
      LoggingService.error('Failed to get country metadata from database', e, stack);
      return {};
    }
  }


  /// Download country airspace data
  Future<DownloadResult> downloadCountryData(
    String countryCode, {
    void Function(double progress)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggingService.info('Starting download for country: $countryCode');

      // Build URL for country GeoJSON
      final url = '$_storageBaseUrl/${countryCode.toLowerCase()}_asp.geojson';

      LoggingService.structured('COUNTRY_DOWNLOAD_START', {
        'country': countryCode,
        'url': url,
      });

      // Make HTTP request with timeout
      final request = http.Request('GET', Uri.parse(url));
      final streamedResponse = await request.send().timeout(_requestTimeout);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Failed to download country data: HTTP ${streamedResponse.statusCode}');
      }

      // Get content length for progress tracking
      final contentLength = streamedResponse.contentLength ?? 0;
      final bytes = <int>[];
      var downloadedBytes = 0;

      // Download with progress tracking
      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;

        if (contentLength > 0 && onProgress != null) {
          final progress = downloadedBytes / contentLength;
          onProgress(progress);
        }
      }

      // Parse GeoJSON
      final jsonString = utf8.decode(bytes);
      final geoJson = json.decode(jsonString);

      if (geoJson['type'] != 'FeatureCollection') {
        throw Exception('Invalid GeoJSON format');
      }

      final features = geoJson['features'] as List<dynamic>;

      LoggingService.structured('COUNTRY_DOWNLOAD_COMPLETE', {
        'country': countryCode,
        'features_count': features.length,
        'size_bytes': bytes.length,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });

      // Get etag and last-modified from response headers
      final etag = streamedResponse.headers['etag'];
      final lastModified = streamedResponse.headers['last-modified'];

      // Store in cache
      await _storeCountryData(countryCode, features, etag, lastModified);

      stopwatch.stop();

      return DownloadResult(
        success: true,
        countryCode: countryCode,
        airspaceCount: features.length,
        sizeMB: bytes.length / 1024 / 1024,
        durationMs: stopwatch.elapsedMilliseconds,
      );

    } catch (e, stack) {
      LoggingService.error('Failed to download country $countryCode', e, stack);

      return DownloadResult(
        success: false,
        countryCode: countryCode,
        error: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Store country data in cache
  Future<void> _storeCountryData(
    String countryCode,
    List<dynamic> features,
    String? etag,
    String? lastModified,
  ) async {
    final stopwatch = Stopwatch()..start();

    LoggingService.structured('COUNTRY_STORE_START', {
      'country': countryCode,
      'features': features.length,
    });

    // Store all features for this country
    await _metadataCache.putCountryAirspaces(
      countryCode: countryCode,
      features: features.cast<Map<String, dynamic>>(),
    );

    // Country metadata is automatically stored by _metadataCache.putCountryAirspaces()

    stopwatch.stop();

    LoggingService.structured('COUNTRY_STORE_COMPLETE', {
      'country': countryCode,
      'duration_ms': stopwatch.elapsedMilliseconds,
    });
  }

  /// Check if country data needs updating
  Future<bool> checkForUpdate(String countryCode) async {
    try {
      final metadata = await getCountryMetadata();
      final currentData = metadata[countryCode];

      if (currentData == null) {
        return true; // No data, needs download
      }

      // Check age (update if > 30 days old)
      final age = DateTime.now().difference(currentData.downloadTime);
      return age.inDays > 30;

    } catch (e) {
      LoggingService.error('Failed to check for update for $countryCode', e);
      return false; // On error, assume up to date
    }
  }

  /// Delete country data
  Future<void> deleteCountryData(String countryCode) async {
    LoggingService.info('Deleting country data for $countryCode');

    // Remove from cache (also removes from database)
    await _metadataCache.deleteCountryData(countryCode);

    // Remove from selected countries
    final selected = await getSelectedCountries();
    selected.remove(countryCode);
    await setSelectedCountries(selected);

    LoggingService.info('Successfully deleted country data for $countryCode');
  }

  /// Get total storage used by airspace data
  Future<double> getTotalStorageMB() async {
    final stats = await _metadataCache.getStatistics();
    return stats.totalMemoryBytes / 1024 / 1024;
  }

  /// Clear all country data
  Future<void> clearAllData() async {
    LoggingService.info('Clearing all country airspace data');

    await _metadataCache.clearAllCache();
    await _geometryCache.clearAllCache();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedCountriesKey);

    LoggingService.info('Successfully cleared all country airspace data');
  }
}