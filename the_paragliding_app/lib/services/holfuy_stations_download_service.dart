import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/holfuy_station_catalogue.dart';
import '../utils/http_freshness.dart' as freshness;
import '../utils/map_constants.dart';
import 'logging_service.dart';

/// Where the published Holfuy station file lives and how often it is checked.
class HolfuyStationsConfig {
  /// The copy bundled with the build, so Holfuy pins exist with no signal.
  static const String assetPath = 'assets/data/holfuy_stations.json';

  /// The published file, from the federation pipeline that generates it.
  ///
  /// `main` rather than a release asset, like the site catalogue: that branch
  /// only moves when a human merges the pipeline's PR, so what the app follows
  /// is a catalogue someone reviewed, and rolling back a bad one is a revert.
  static const String catalogUrl =
      'https://raw.githubusercontent.com/Kevin-McIsaac/'
      'paragliding_site_federation/main/app/holfuy_stations.json';

  static const Duration downloadTimeout = Duration(seconds: 30);
}

/// Keeps the app's copy of the Holfuy station catalogue current.
///
/// Positions only, and the file changes only when someone re-runs the manual
/// catalogue build, so this is deliberately the cheapest possible refresher: a
/// HEAD on a 7-day cadence, a download only when the validators say the file
/// moved, and the bundled asset as the fallback for every failure. Nothing here
/// talks to Holfuy - readings are the provider's on-demand business.
class HolfuyStationsDownloadService {
  static final HolfuyStationsDownloadService instance =
      HolfuyStationsDownloadService._();
  HolfuyStationsDownloadService._();

  static const String _etagKey = 'holfuy_stations_etag';
  static const String _lastModifiedKey = 'holfuy_stations_last_modified';
  static const String _downloadedAtKey = 'holfuy_stations_downloaded_at';
  static const String _checkedAtKey = 'holfuy_stations_checked_at';

  http.Client? _httpClient;
  http.Client get _client => _httpClient ??= http.Client();

  @visibleForTesting
  set httpClientForTest(http.Client client) => _httpClient = client;

  /// Directory the downloaded copy is written under. Tests point this at a
  /// throwaway directory so they never touch the real app documents.
  @visibleForTesting
  String? directoryOverrideForTest;

  /// Loader for the bundled copy, so a test can serve a fixture instead of
  /// reaching into the asset bundle.
  @visibleForTesting
  Future<String> Function()? bundledLoaderForTest;

  // --- reads -----------------------------------------------------------------

  /// The catalogue as currently known. Never touches the network.
  Future<HolfuyStationCatalogue> loadCatalogue() async {
    return HolfuyStationCatalogue.parse(await loadJson());
  }

  /// The published file's text: the downloaded copy if one is on disk, else the
  /// bundled asset.
  Future<String> loadJson() async {
    final local = await _localFileOrNull();
    if (local != null) {
      try {
        return await local.readAsString();
      } catch (error) {
        LoggingService.error(
            'Holfuy station file on disk was unreadable; using bundled copy',
            error);
      }
    }
    return _loadBundled();
  }

  Future<String> _loadBundled() async {
    final loader = bundledLoaderForTest;
    if (loader != null) return loader();
    return rootBundle.loadString(HolfuyStationsConfig.assetPath);
  }

  // --- refresh ---------------------------------------------------------------

  /// Ask whether a newer published file exists, and fetch it if so.
  ///
  /// Off the map path on purpose: [warmCache] calls this at startup. Every
  /// failure is swallowed - a pilot with no signal keeps the copy already on
  /// disk, which is the whole point of shipping one.
  Future<void> ensureFresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final checkedAt = prefs.getInt(_checkedAtKey) ?? 0;
      if (checkedAt != 0 &&
          DateTime.now().difference(
                  DateTime.fromMillisecondsSinceEpoch(checkedAt)) <
              MapConstants.holfuyStationFileCheckInterval) {
        return;
      }

      final response = await _client
          .head(Uri.parse(HolfuyStationsConfig.catalogUrl))
          .timeout(HolfuyStationsConfig.downloadTimeout);

      if (response.statusCode != 200) {
        LoggingService.structured('HOLFUY_STATIONS_CHECK_FAILED', {
          'status': response.statusCode,
        });
        return;
      }

      // Stamped only on a definitive answer: a check that failed because the
      // pilot had no signal must not count as "checked", or the throttle turns
      // one failure into a week of silence.
      await prefs.setInt(
          _checkedAtKey, DateTime.now().millisecondsSinceEpoch);

      final downloadedAt = prefs.getInt(_downloadedAtKey) ?? 0;
      final ageInDays = downloadedAt == 0
          ? MapConstants.holfuyStationFileMaxAge.inDays + 1
          : DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(downloadedAt))
              .inDays;

      final newer = freshness.isRemoteNewer(
        storedEtag: prefs.getString(_etagKey),
        storedLastModified: prefs.getString(_lastModifiedKey),
        remoteEtag: response.headers['etag'],
        remoteLastModified: response.headers['last-modified'],
        ageInDays: ageInDays,
        maxAgeInDays: MapConstants.holfuyStationFileMaxAge.inDays,
      );

      LoggingService.structured('HOLFUY_STATIONS_CHECK', {
        'update_available': newer,
        'age_days': ageInDays,
      });

      if (!newer) return;

      await _download(
        prefs: prefs,
        etag: response.headers['etag'],
        lastModified: response.headers['last-modified'],
      );
    } catch (error, stackTrace) {
      LoggingService.error(
          'Holfuy station file refresh failed', error, stackTrace);
    }
  }

  /// Fetch and validate the published file, then replace the local copy.
  ///
  /// Validated by parsing before it replaces anything: a truncated body or an
  /// HTML error page must leave the working catalogue alone rather than empty
  /// the map. Temp file plus rename, so a crash mid-write cannot leave a
  /// half-file that the next load would trust.
  Future<void> _download({
    required SharedPreferences prefs,
    String? etag,
    String? lastModified,
  }) async {
    final response = await _client
        .get(Uri.parse(HolfuyStationsConfig.catalogUrl))
        .timeout(HolfuyStationsConfig.downloadTimeout);

    if (response.statusCode != 200) {
      LoggingService.structured('HOLFUY_STATIONS_DOWNLOAD_FAILED', {
        'status': response.statusCode,
      });
      return;
    }

    final catalogue = HolfuyStationCatalogue.parse(response.body);
    if (catalogue.stations.isEmpty) {
      LoggingService.structured('HOLFUY_STATIONS_DOWNLOAD_REJECTED', {
        'reason': 'no usable stations in the published file',
      });
      return;
    }

    final file = await _localFile();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(response.body, flush: true);
    await tmp.rename(file.path);

    // Only non-null validators are stored. Writing an empty string for a header
    // the server omitted would make every later check compare "" against a
    // real ETag and re-download for nothing.
    if (etag != null) await prefs.setString(_etagKey, etag);
    if (lastModified != null) await prefs.setString(_lastModifiedKey, lastModified);
    await prefs.setInt(
        _downloadedAtKey, DateTime.now().millisecondsSinceEpoch);

    LoggingService.structured('HOLFUY_STATIONS_DOWNLOADED', {
      'stations': catalogue.stations.length,
      'skipped': catalogue.skipped,
      'generated_utc': catalogue.generatedUtc,
      'had_etag': etag != null,
    });
  }

  // --- test seams ------------------------------------------------------------

  @visibleForTesting
  Future<File> localFileForTest() => _localFile();

  @visibleForTesting
  Future<void> clearForTest() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _etagKey,
      _lastModifiedKey,
      _downloadedAtKey,
      _checkedAtKey,
    ]) {
      await prefs.remove(key);
    }
    final local = await _localFileOrNull();
    if (local != null) await local.delete();
  }

  // --- disk ------------------------------------------------------------------

  Future<File?> _localFileOrNull() async {
    try {
      final file = await _localFile();
      return await file.exists() ? file : null;
    } catch (error) {
      LoggingService.error('Could not read the Holfuy station file', error);
      return null;
    }
  }

  Future<File> _localFile() async {
    final root = directoryOverrideForTest ??
        (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(path.join(root, 'holfuy'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(path.join(dir.path, 'holfuy_stations.json'));
  }
}
