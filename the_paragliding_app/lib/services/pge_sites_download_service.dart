import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../services/logging_service.dart';
import '../utils/http_freshness.dart' as freshness;
import '../utils/performance_monitor.dart';
import '../utils/preferences_helper.dart';

/// Configuration constants for PGE sites download
class PgeSitesConfig {
  /// Asset path for bundled CSV file
  static const String assetPath = 'assets/data/world_sites_extracted.csv.gz';

  /// The published catalogue, from the federation pipeline that builds it.
  ///
  /// `main` rather than a release asset because that branch only moves when a
  /// human merges the pipeline's weekly PR - so what the app follows is a
  /// catalogue someone has reviewed, and rolling back a bad one is a revert.
  ///
  /// Served uncompressed (~880 KB), though GitHub gzips it in transit and Dart
  /// decodes that transparently. Public so a network-tagged test can assert the
  /// URL still serves usable data, the way countryDataUrl() is in
  /// AirspaceCountryService.
  static const String catalogUrl =
      'https://raw.githubusercontent.com/Kevin-McIsaac/'
      'paragliding_site_federation/main/app/sites.csv';

  /// Maximum age before auto-refresh
  static const Duration maxAge = Duration(days: 30);

  /// Maximum sites per query
  static const int maxSitesPerQuery = 100;

  /// Spatial tolerance for site matching (~100m)
  static const double spatialTolerance = 0.001;

  /// Download timeout
  static const Duration downloadTimeout = Duration(minutes: 5);
}

/// Download status for PGE sites data
enum PgeSitesDownloadStatus {
  notDownloaded,
  downloading,
  completed,
  error,
  outdated,
}

/// Download progress information
class PgeSitesDownloadProgress {
  final int totalBytes;
  final int downloadedBytes;
  final PgeSitesDownloadStatus status;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const PgeSitesDownloadProgress({
    required this.totalBytes,
    required this.downloadedBytes,
    required this.status,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
  });

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;

  Duration? get duration => startedAt != null && completedAt != null
      ? completedAt!.difference(startedAt!)
      : null;

  PgeSitesDownloadProgress copyWith({
    int? totalBytes,
    int? downloadedBytes,
    PgeSitesDownloadStatus? status,
    String? errorMessage,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return PgeSitesDownloadProgress(
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// Service for downloading and managing PGE sites data from Google Drive
class PgeSitesDownloadService {
  static final PgeSitesDownloadService instance = PgeSitesDownloadService._();
  PgeSitesDownloadService._();

  /// Progress stream for UI updates
  final _progressController = StreamController<PgeSitesDownloadProgress>.broadcast();
  Stream<PgeSitesDownloadProgress> get progressStream => _progressController.stream;

  /// Current download progress
  PgeSitesDownloadProgress _currentProgress = const PgeSitesDownloadProgress(
    totalBytes: 0,
    downloadedBytes: 0,
    status: PgeSitesDownloadStatus.notDownloaded,
  );

  /// HTTP client for downloads
  static http.Client? _httpClient;
  static http.Client get httpClient {
    if (_httpClient == null) {
      _httpClient = http.Client();
      LoggingService.info('[PGE_SITES] HTTP client created for downloads');
    }
    return _httpClient!;
  }


  /// Get local file path for downloaded data
  Future<String> _getLocalFilePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final sitesDir = Directory(path.join(appDir.path, 'pge_sites'));

    if (!await sitesDir.exists()) {
      await sitesDir.create(recursive: true);
    }

    return path.join(sitesDir.path, 'world_sites_extracted.csv.gz');
  }

  /// Whether the catalogue shipped in this build differs from the copy on disk.
  ///
  /// A release ships a new catalogue, but the import only ran when the table
  /// was empty - so an upgrading user kept the previous one indefinitely and
  /// never saw sites added since they installed. Size is a sufficient signal:
  /// any real change to 11k+ rows moves it, and it costs no parsing.
  Future<bool> bundledCatalogDiffersFromLocal() async {
    try {
      final localFile = File(await _getLocalFilePath());
      if (!await localFile.exists()) return true;

      final ByteData data = await rootBundle.load(PgeSitesConfig.assetPath);
      final differs = (await localFile.stat()).size != data.lengthInBytes;
      if (differs) {
        LoggingService.info('[PGE_SITES] Bundled catalogue differs from local copy');
      }
      return differs;
    } catch (error) {
      LoggingService.error('[PGE_SITES] Could not compare bundled catalogue', error);
      return false;
    }
  }

  /// Whether the published catalogue differs from the copy on disk.
  ///
  /// Mostly the shared [isRemoteNewer] - that logic was a verbatim copy of the
  /// airspace service's, so a fix to it had to be made twice or be wrong in one
  /// place. One rule is added on top: **an unvalidated local copy is refreshed.**
  ///
  /// If nothing is stored, the local file cannot be shown to match what is
  /// published, and the age of the file says nothing about that - a "Reset to
  /// Bundled" leaves an older snapshot with a brand-new mtime, which is exactly
  /// the case where an age fallback answers "up to date" about stale data.
  ///
  /// The airspace exports keep the age fallback instead, deliberately: they are
  /// 13 MB each and pulling one on a hunch is expensive. The catalogue is 350 KB,
  /// so fetching when unsure is the cheaper mistake.
  static bool isRemoteNewer({
    required String? storedEtag,
    required String? storedLastModified,
    required String? remoteEtag,
    required String? remoteLastModified,
    required int ageInDays,
  }) {
    final haveNoValidators = storedEtag == null && storedLastModified == null;
    final serverOffersOne = remoteEtag != null || remoteLastModified != null;
    if (haveNoValidators && serverOffersOne) return true;

    return freshness.isRemoteNewer(
      storedEtag: storedEtag,
      storedLastModified: storedLastModified,
      remoteEtag: remoteEtag,
      remoteLastModified: remoteLastModified,
      ageInDays: ageInDays,
      maxAgeInDays: PgeSitesConfig.maxAge.inDays,
    );
  }

  /// Ask the server whether a newer catalogue exists.
  ///
  /// A HEAD request, so the answer costs a few hundred bytes rather than the
  /// whole file. Returns false whenever it cannot tell - an error or a non-200
  /// must not push a download that may be pointless, and the pilot can still
  /// refresh by hand from Data Management.
  Future<bool> checkForUpdate() async {
    try {
      final stored = await PreferencesHelper.getCatalogValidators();
      final downloadedAt = await PreferencesHelper.getPgeSitesDownloadDate();
      final ageInDays =
          DateTime.now().difference(downloadedAt ?? DateTime(2000)).inDays;

      final response = await httpClient
          .head(Uri.parse(PgeSitesConfig.catalogUrl))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        LoggingService.structured('CATALOG_UPDATE_CHECK_FAILED', {
          'status': response.statusCode,
        });
        return false;
      }

      // Stamped only now, on a definitive answer. Stamping before the request
      // meant a check that failed because the pilot had no signal - at a launch
      // site, the normal case - counted as "checked", and the automatic check is
      // throttled on this timestamp, so one failure blocked the next attempt for
      // a month.
      await PreferencesHelper.setCatalogCheckedNow();

      final available = isRemoteNewer(
        storedEtag: stored.etag,
        storedLastModified: stored.lastModified,
        remoteEtag: response.headers['etag'],
        remoteLastModified: response.headers['last-modified'],
        ageInDays: ageInDays,
      );

      LoggingService.structured('CATALOG_UPDATE_CHECK', {
        'update_available': available,
        'age_days': ageInDays,
        'had_validators': stored.etag != null || stored.lastModified != null,
      });

      return available;
    } catch (error) {
      LoggingService.error('[PGE_SITES] Catalogue update check failed', error);
      return false;
    }
  }

  /// Fetch the published catalogue and put it where the parser expects it.
  ///
  /// Written gzipped so there is one local format and [parseDownloadedData]
  /// needs no branch, and validated by parsing before it replaces anything: a
  /// truncated or HTML-error response must leave the working catalogue alone
  /// rather than empty the map. Temp file plus atomic rename, as the bundled
  /// copy already does.
  Future<bool> downloadFromRemote() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await httpClient
          .get(Uri.parse(PgeSitesConfig.catalogUrl))
          .timeout(PgeSitesConfig.downloadTimeout);

      if (response.statusCode != 200) {
        LoggingService.structured('CATALOG_DOWNLOAD_FAILED', {
          'status': response.statusCode,
        });
        return false;
      }

      // Sanity check before anything is written, so a truncated body or an HTML
      // error page cannot replace a working catalogue.
      //
      // Checked by column *name*, not by a literal header prefix. This used to
      // require `id,name,` and rejected the real file the day the producer added
      // its `ref` column - the guard failed the thing it exists to protect, and
      // no test saw it because they all import parsed rows and never come
      // through here. The app reads by name, so the honest question is whether
      // the columns it reads are present.
      final body = response.body;
      final header = body.split('\n').first.split(',').map((c) => c.trim()).toSet();
      const required = {'name', 'longitude', 'latitude', 'source'};
      final missing = required.difference(header);

      if (missing.isNotEmpty || body.length < 100000) {
        LoggingService.structured('CATALOG_DOWNLOAD_REJECTED', {
          'bytes': body.length,
          'missing_columns': missing.join(','),
          'header': header.take(6).join(','),
        });
        return false;
      }

      final localFilePath = await _getLocalFilePath();
      final tempFile = File('$localFilePath.tmp');
      await tempFile.writeAsBytes(gzip.encode(utf8.encode(body)));
      await tempFile.rename(localFilePath);

      // The file is in place, so the download has succeeded whatever happens
      // next. Recording the validators is bookkeeping: losing it costs one
      // redundant refresh, whereas reporting "Download Failed - sites unchanged"
      // after the sites did change tells the pilot the opposite of the truth.
      try {
        await PreferencesHelper.setCatalogValidators(
          etag: response.headers['etag'],
          lastModified: response.headers['last-modified'],
        );
        await PreferencesHelper.setPgeSitesDownloaded(true);
      } catch (error) {
        LoggingService.error(
            '[PGE_SITES] Catalogue saved but its validators were not', error);
      }

      stopwatch.stop();
      LoggingService.performance('Catalogue download', stopwatch.elapsed,
          '${body.length} bytes from the published catalogue');
      return true;
    } catch (error, stackTrace) {
      LoggingService.error(
          '[PGE_SITES] Catalogue download failed', error, stackTrace);
      return false;
    }
  }

  /// Copy bundled CSV file to local storage
  Future<bool> downloadSitesData({bool forceRedownload = false}) async {
    PerformanceMonitor.startOperation('PgeSitesDownload');

    try {
      final localFilePath = await _getLocalFilePath();
      final localFile = File(localFilePath);

      // Load bundled CSV file from assets
      final ByteData data = await rootBundle.load(PgeSitesConfig.assetPath);
      final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      final totalBytes = bytes.length;

      // Check if we need to download
      if (!forceRedownload && await localFile.exists()) {
        final stats = await localFile.stat();
        final age = DateTime.now().difference(stats.modified);

        // Age alone is not enough: a release ships a new catalogue, and the
        // copy on disk can be days old and still stale. Without the size
        // check an upgrading user kept the previous catalogue - and its site
        // ids - for up to maxAge, so newly added launches simply did not
        // appear for a month after installing the release that added them.
        final sameAsBundled = stats.size == totalBytes;

        if (age < PgeSitesConfig.maxAge && sameAsBundled) {
          LoggingService.info('[PGE_SITES] Local file matches the bundled catalogue, skipping copy');
          _updateProgress(const PgeSitesDownloadProgress(
            totalBytes: 0,
            downloadedBytes: 0,
            status: PgeSitesDownloadStatus.completed,
          ));
          return true;
        }

        if (!sameAsBundled) {
          LoggingService.info(
            '[PGE_SITES] Bundled catalogue changed (${stats.size} -> $totalBytes bytes), refreshing',
          );
        }
      }

      // Start download
      final startTime = DateTime.now();
      _updateProgress(PgeSitesDownloadProgress(
        totalBytes: 0,
        downloadedBytes: 0,
        status: PgeSitesDownloadStatus.downloading,
        startedAt: startTime,
      ));

      LoggingService.info('[PGE_SITES] Copying bundled CSV file to local storage');

      LoggingService.structured('PGE_SITES_DOWNLOAD_STARTED', {
        'total_bytes': totalBytes,
        'source': 'bundled_asset',
      });

      // Write to temporary file first
      final tempFile = File('$localFilePath.tmp');
      await tempFile.writeAsBytes(bytes);

      // Verify file was written correctly
      final writtenStats = await tempFile.stat();
      if (writtenStats.size == 0) {
        throw FileSystemException('Written file is empty');
      }

      // Move to final location atomically
      await tempFile.rename(localFilePath);

      // The local copy is now the bundled one, so the validators describing the
      // *published* file no longer describe it. Left in place, a later check
      // would compare the unchanged remote ETag against them and report "up to
      // date" while the pilot sits on the older shipped snapshot - the opposite
      // of what both buttons are for.
      //
      // Its own try: the file is already in place by now, so a preferences
      // failure is not a failed download and must not be reported as one. The
      // cost of losing this write is one redundant refresh, not stale data.
      try {
        await PreferencesHelper.setCatalogValidators(
            etag: null, lastModified: null);
      } catch (error) {
        LoggingService.error(
            '[PGE_SITES] Could not clear catalogue validators', error);
      }

      final completedTime = DateTime.now();
      final duration = completedTime.difference(startTime);

      LoggingService.performance(
        'PGE Sites Download',
        duration,
        'Downloaded $totalBytes bytes'
      );

      LoggingService.structured('PGE_SITES_DOWNLOAD_COMPLETED', {
        'total_bytes': totalBytes,
        'duration_ms': duration.inMilliseconds,
        'file_path': localFilePath,
      });

      _updateProgress(PgeSitesDownloadProgress(
        totalBytes: totalBytes,
        downloadedBytes: totalBytes,
        status: PgeSitesDownloadStatus.completed,
        startedAt: startTime,
        completedAt: completedTime,
      ));

      PerformanceMonitor.endOperation('PgeSitesDownload', metadata: {
        'success': true,
        'bytes_downloaded': totalBytes,
        'duration_ms': duration.inMilliseconds,
      });

      return true;

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES] Download failed', error, stackTrace);

      _updateProgress(_currentProgress.copyWith(
        status: PgeSitesDownloadStatus.error,
        errorMessage: error.toString(),
      ));

      PerformanceMonitor.endOperation('PgeSitesDownload', metadata: {
        'success': false,
        'error': error.toString(),
      });

      return false;
    }
  }

  /// Parse downloaded CSV data
  Future<List<Map<String, dynamic>>> parseDownloadedData() async {
    final localFilePath = await _getLocalFilePath();
    final localFile = File(localFilePath);

    if (!await localFile.exists()) {
      throw FileSystemException('Downloaded data file not found');
    }

    LoggingService.info('[PGE_SITES] Parsing downloaded CSV data');

    try {
      // Read and decompress file
      final compressedBytes = await localFile.readAsBytes();
      final decompressedBytes = gzip.decode(compressedBytes);
      final csvContent = utf8.decode(decompressedBytes);

      // Parsed by *column name*, not position.
      //
      // This was a hand-rolled split('\n') plus a field splitter, reading
      // fixed indices. Two things went wrong with that. Guide prose contains
      // hard line breaks, and a newline inside a quoted field silently tore a
      // record in two - 43 of 11,703 rows. And every column was addressed by
      // number, so longitude sitting before latitude was a permanent trap: a
      // swap parses cleanly and puts every site in the wrong hemisphere.
      //
      // Reading by header removes both. Column order no longer matters, and a
      // new column can be added anywhere without touching this.
      final rows = csv.decodeWithHeaders(csvContent);
      final sites = <Map<String, dynamic>>[];

      for (final row in rows) {
        try {
          String field(String name) => (row[name] ?? '').toString();
          String? optional(String name) {
            final value = field(name);
            return value.isEmpty ? null : value;
          }

          final id = int.tryParse(field('id'));
          if (id == null) continue; // not a data row

          sites.add({
            'id': id,
            // The key this launch is stored under, chosen by the producer. Null
            // for a catalogue published before the column existed, which the
            // import falls back to deriving - see importSitesData.
            'ref': optional('ref'),
            'name': field('name'),
            'longitude': double.tryParse(field('longitude')) ?? 0.0,
            'latitude': double.tryParse(field('latitude')) ?? 0.0,
            'altitude': int.tryParse(field('altitude')),
            'country': field('country'),
            'wind_n': int.tryParse(field('wind_n')) ?? 0,
            'wind_ne': int.tryParse(field('wind_ne')) ?? 0,
            'wind_e': int.tryParse(field('wind_e')) ?? 0,
            'wind_se': int.tryParse(field('wind_se')) ?? 0,
            'wind_s': int.tryParse(field('wind_s')) ?? 0,
            'wind_sw': int.tryParse(field('wind_sw')) ?? 0,
            'wind_w': int.tryParse(field('wind_w')) ?? 0,
            'wind_nw': int.tryParse(field('wind_nw')) ?? 0,
            // Which guides contributed this launch, e.g.
            // "pge:4632;ansg:106-28".
            'source': field('source'),
            // Why a guide says the launch is shut, verbatim. Absent from an
            // older catalogue, which reads as null rather than failing.
            'closed': optional('closed'),
          });
        } catch (e) {
          LoggingService.warning('[PGE_SITES] Failed to parse CSV row: $row');
        }
      }

      LoggingService.info('[PGE_SITES] Parsed ${sites.length} sites from CSV');

      LoggingService.structured('PGE_SITES_PARSED', {
        'sites_count': sites.length,
        'compressed_size': compressedBytes.length,
        'decompressed_size': decompressedBytes.length,
        'closed_sites': sites.where((s) => s['closed'] != null).length,
      });

      return sites;

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES] Failed to parse CSV data', error, stackTrace);
      rethrow;
    }
  }

  /// Get download status and metadata
  Future<Map<String, dynamic>> getDownloadStatus() async {
    try {
      final localFilePath = await _getLocalFilePath();
      final localFile = File(localFilePath);

      if (await localFile.exists()) {
        final stats = await localFile.stat();
        final age = DateTime.now().difference(stats.modified);

        return {
          'exists': true,
          'file_size_bytes': stats.size,
          'downloaded_at': stats.modified.toIso8601String(),
          'age_hours': age.inHours,
          'is_outdated': age > PgeSitesConfig.maxAge,
          'file_path': localFilePath,
        };
      } else {
        return {
          'exists': false,
          'file_size_bytes': 0,
          'downloaded_at': null,
          'age_hours': null,
          'is_outdated': true,
          'file_path': localFilePath,
        };
      }
    } catch (error) {
      LoggingService.error('[PGE_SITES] Failed to get download status', error);
      return {
        'exists': false,
        'error': error.toString(),
      };
    }
  }

  /// Update progress and notify listeners
  void _updateProgress(PgeSitesDownloadProgress progress) {
    _currentProgress = progress;
    _progressController.add(progress);
  }

  /// Get current progress
  PgeSitesDownloadProgress get currentProgress => _currentProgress;

  /// Delete the local downloaded file to force re-download
  Future<bool> deleteLocalFile() async {
    try {
      final localFilePath = await _getLocalFilePath();
      final localFile = File(localFilePath);

      if (await localFile.exists()) {
        await localFile.delete();
        LoggingService.info('[PGE_SITES] Deleted local file: $localFilePath');
        return true;
      }
      return false;
    } catch (error) {
      LoggingService.error('[PGE_SITES] Failed to delete local file', error);
      return false;
    }
  }

  /// Clean up resources
  void dispose() {
    _progressController.close();
    _httpClient?.close();
    _httpClient = null;
  }
}