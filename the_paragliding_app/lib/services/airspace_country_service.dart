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

  // OpenAIP's public daily export bucket.
  //
  // This is NOT the old Google Cloud Storage bucket
  // (storage.googleapis.com/29f98e10-...), and must not be "corrected" back to
  // it. OpenAIP switched that bucket to Requester Pays around 2026-07-23, so
  // every anonymous request now fails with HTTP 400 UserProjectMissing and no
  // country can be downloaded. It was deliberate - they were being billed
  // four-figure egress costs - and announced in openAIP/openaip#468. The
  // replacement S3 endpoint below is the sanctioned bulk channel (#469), rate
  // limited to 20 req/s. Downloading a whole country is one request against
  // that budget; fetching per-viewport instead would be the very usage pattern
  // that got the last bucket locked down.
  //
  // The endpoint returns `content-encoding: utf-8`, which is a charset, not an
  // encoding. It is wrong but harmless here: dart:io only auto-uncompresses
  // gzip, so an unknown value is passed through untouched. Verified against
  // this exact code path. Tools that trust the header - `curl --compressed` -
  // do fail on it, which is worth knowing when reproducing by hand.
  static const String _storageBaseUrl = 'https://storage.openaip.net/openaip-system-exports';
  static const Duration _requestTimeout = Duration(minutes: 2); // Longer timeout for large files

  // Preferences keys
  static const String _selectedCountriesKey = 'airspace_selected_countries';

  /// Where the ETag / Last-Modified / download time for one country are kept.
  static String _fetchInfoKey(String countryCode) =>
      'airspace_fetch_info_${countryCode.toUpperCase()}';

  /// URL of the daily airspace export for [countryCode], e.g. `au_asp.geojson`.
  ///
  /// Public so a test can assert the app points at a URL that actually serves
  /// data. That is the only thing that would have caught this file's last
  /// outage: the code was correct, the host was not.
  static String countryDataUrl(String countryCode) =>
      '$_storageBaseUrl/${countryCode.toLowerCase()}_asp.geojson';

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

    // Only log when countries list changes, not on every call
    return countries;
  }

  /// Set selected countries
  Future<void> setSelectedCountries(List<String> countryCodes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedCountriesKey, countryCodes);

    LoggingService.info('Updated selected countries: ${countryCodes.join(", ")}');
  }

  /// Get metadata for all countries with real database statistics
  Future<Map<String, CountryMetadata>> getCountryMetadata() async {
    try {
      // Get currently selected countries from preferences
      final selectedCountries = await getSelectedCountries();

      // Query real statistics for each country
      final metadata = <String, CountryMetadata>{};
      for (final countryCode in selectedCountries) {
        final stats = await _diskCache.getCountryStatistics(countryCode);

        // Only include countries that actually have data
        if (stats['has_data'] == true) {
          final fetchInfo = await _getFetchInfo(countryCode);

          metadata[countryCode] = CountryMetadata(
            countryCode: countryCode,
            airspaceCount: stats['airspace_count'] ?? 0,
            // Falls back to "now" only for data downloaded before the fetch
            // info was recorded. That reads as freshly downloaded, which is the
            // safe direction: it delays an update rather than discarding data.
            downloadTime: fetchInfo.downloadedAt ?? DateTime.now(),
            etag: fetchInfo.etag,
            lastModified: fetchInfo.lastModified,
            version: 1,
          );
        }
      }

      return metadata;
    } catch (e, stack) {
      LoggingService.error('Failed to get country metadata', e, stack);
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
      final url = countryDataUrl(countryCode);

      LoggingService.structured('COUNTRY_DOWNLOAD_START', {
        'country': countryCode,
        'url': url,
      });

      // Make HTTP request with timeout
      final request = http.Request('GET', Uri.parse(url));
      final streamedResponse = await request.send().timeout(_requestTimeout);

      if (streamedResponse.statusCode != 200) {
        // Read the body before throwing. When the old bucket switched to
        // Requester Pays this threw a bare "HTTP 400", while the server was
        // spelling out exactly what was wrong in a body nobody looked at:
        //   <Error><Code>UserProjectMissing</Code>...
        // That cost far more to diagnose than it should have.
        var detail = '';
        try {
          final body = await streamedResponse.stream.bytesToString();
          detail = body.trim().replaceAll(RegExp(r'\s+'), ' ');
          if (detail.length > 300) detail = '${detail.substring(0, 300)}...';
        } catch (_) {
          // Body unreadable - the status code is still worth reporting.
        }

        LoggingService.structured('COUNTRY_DOWNLOAD_FAILED', {
          'country': countryCode,
          'status': streamedResponse.statusCode,
          'url': url,
          'body': detail,
        });

        throw Exception(
          'Failed to download country data: HTTP ${streamedResponse.statusCode}'
          '${detail.isEmpty ? '' : ' - $detail'}',
        );
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

      final countryName = availableCountries[countryCode]?.name ?? countryCode;
      final sizeMB = bytes.length / (1024 * 1024);
      final durationSec = stopwatch.elapsedMilliseconds / 1000;

      LoggingService.info(
        'Downloaded $countryName: ${features.length} airspaces (${sizeMB.toStringAsFixed(1)} MB) in ${durationSec.toStringAsFixed(1)}s'
      );

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

    LoggingService.debug('Storing ${features.length} features for country $countryCode');

    // Store all features for this country
    await _metadataCache.putCountryAirspaces(
      countryCode: countryCode,
      features: features.cast<Map<String, dynamic>>(),
    );

    // Country metadata is automatically stored by _metadataCache.putCountryAirspaces(),
    // but not the HTTP validators - so record them here. They used to be passed
    // in and dropped on the floor, which left checkForUpdate() with nothing to
    // compare and getCountryMetadata() reporting etag/lastModified as null.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _fetchInfoKey(countryCode),
      jsonEncode({
        'etag': etag,
        'lastModified': lastModified,
        'downloadedAt': DateTime.now().toIso8601String(),
      }),
    );

    stopwatch.stop();

    LoggingService.debug('Completed storing country $countryCode in ${stopwatch.elapsedMilliseconds}ms');
  }

  /// Check if country data needs updating.
  ///
  /// Asks the server with a HEAD request and compares HTTP validators instead
  /// of guessing from age. The exports are rebuilt daily but the airspace in
  /// them changes rarely, so an age rule gets it wrong in both directions: it
  /// re-downloads ~13 MB that is already current, or sits on stale safety data
  /// for a month. A HEAD is a few hundred bytes.
  Future<bool> checkForUpdate(String countryCode) async {
    try {
      final metadata = await getCountryMetadata();
      final currentData = metadata[countryCode];

      if (currentData == null) {
        return true; // No data, needs download
      }

      final stored = await _getFetchInfo(countryCode);
      final ageInDays =
          DateTime.now().difference(currentData.downloadTime).inDays;

      // Data downloaded before validators were recorded has nothing to compare.
      if (stored.etag == null && stored.lastModified == null) {
        return ageInDays > 30;
      }

      final response = await http
          .head(Uri.parse(countryDataUrl(countryCode)))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        LoggingService.structured('COUNTRY_UPDATE_CHECK_FAILED', {
          'country': countryCode,
          'status': response.statusCode,
        });
        // Can't tell. Say no rather than pushing a large download that may be
        // pointless - the user can still re-download by hand.
        return false;
      }

      final remoteEtag = response.headers['etag'];
      final remoteLastModified = response.headers['last-modified'];

      final bool changed;
      if (remoteEtag != null && stored.etag != null) {
        changed = remoteEtag != stored.etag;
      } else if (remoteLastModified != null && stored.lastModified != null) {
        changed = remoteLastModified != stored.lastModified;
      } else {
        changed = ageInDays > 30; // No comparable validator - fall back to age
      }

      LoggingService.structured('COUNTRY_UPDATE_CHECK', {
        'country': countryCode,
        'update_available': changed,
        'age_days': ageInDays,
      });

      return changed;
    } catch (e) {
      LoggingService.error('Failed to check for update for $countryCode', e);
      return false; // On error, assume up to date
    }
  }

  /// Read the stored ETag / Last-Modified / download time for a country.
  Future<_FetchInfo> _getFetchInfo(String countryCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_fetchInfoKey(countryCode));
      if (raw == null) return const _FetchInfo();

      final map = jsonDecode(raw) as Map<String, dynamic>;
      return _FetchInfo(
        etag: map['etag'] as String?,
        lastModified: map['lastModified'] as String?,
        downloadedAt: DateTime.tryParse(map['downloadedAt'] as String? ?? ''),
      );
    } catch (e) {
      LoggingService.error('Failed to read fetch info for $countryCode', e);
      return const _FetchInfo();
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

    // And the stored validators, so a re-download is not told it is current.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fetchInfoKey(countryCode));

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
    // Drop the stored validators too, or a later re-download would compare
    // against an ETag whose data is gone and report "up to date".
    for (final code in availableCountries.keys) {
      await prefs.remove(_fetchInfoKey(code));
    }
    await prefs.remove(_selectedCountriesKey);

    LoggingService.info('Successfully cleared all country airspace data');
  }
}

/// Stored HTTP validators for one country's export file, used to answer
/// "has this changed?" with a HEAD request instead of a 13 MB download.
class _FetchInfo {
  final String? etag;
  final String? lastModified;
  final DateTime? downloadedAt;

  const _FetchInfo({this.etag, this.lastModified, this.downloadedAt});
}