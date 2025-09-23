import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../services/logging_service.dart';
import '../utils/performance_monitor.dart';

/// Configuration constants for PGE sites download
class PgeSitesConfig {
  /// Google Drive download URL - easily changeable
  static const String downloadUrl = 'https://drive.google.com/file/d/1cfCns9cihiJqLJZbiDJGOy1qeLZIW_h7/view?usp=drive_link';

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

  /// Convert Google Drive share URL to direct download URL
  String _convertGoogleDriveUrl(String shareUrl) {
    // Extract file ID from share URL
    final regex = RegExp(r'/file/d/([a-zA-Z0-9_-]+)');
    final match = regex.firstMatch(shareUrl);

    if (match != null) {
      final fileId = match.group(1);
      return 'https://drive.google.com/uc?export=download&id=$fileId';
    }

    // If already a direct URL, return as-is
    if (shareUrl.contains('drive.google.com/uc')) {
      return shareUrl;
    }

    throw ArgumentError('Invalid Google Drive URL format: $shareUrl');
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

  /// Download compressed sites data from Google Drive
  Future<bool> downloadSitesData({bool forceRedownload = false}) async {
    PerformanceMonitor.startOperation('PgeSitesDownload');

    try {
      final localFilePath = await _getLocalFilePath();
      final localFile = File(localFilePath);

      // Check if we need to download
      if (!forceRedownload && await localFile.exists()) {
        final stats = await localFile.stat();
        final age = DateTime.now().difference(stats.modified);

        if (age < PgeSitesConfig.maxAge) {
          LoggingService.info('[PGE_SITES] Local file is recent, skipping download');
          _updateProgress(const PgeSitesDownloadProgress(
            totalBytes: 0,
            downloadedBytes: 0,
            status: PgeSitesDownloadStatus.completed,
          ));
          return true;
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

      LoggingService.info('[PGE_SITES] Starting download from Google Drive');

      // Convert share URL to direct download URL
      final downloadUrl = _convertGoogleDriveUrl(PgeSitesConfig.downloadUrl);

      // Make request with timeout
      final response = await httpClient.get(
        Uri.parse(downloadUrl),
        headers: {
          'User-Agent': 'FreeFlightLog/1.0',
        },
      ).timeout(PgeSitesConfig.downloadTimeout);

      if (response.statusCode != 200) {
        throw HttpException('Download failed with status ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? response.bodyBytes.length;

      LoggingService.structured('PGE_SITES_DOWNLOAD_STARTED', {
        'total_bytes': totalBytes,
        'url': downloadUrl,
      });

      // Write to temporary file first
      final tempFile = File('$localFilePath.tmp');
      await tempFile.writeAsBytes(response.bodyBytes);

      // Verify file was written correctly
      final writtenStats = await tempFile.stat();
      if (writtenStats.size != response.bodyBytes.length) {
        throw FileSystemException('Downloaded file size mismatch');
      }

      // Move to final location atomically
      await tempFile.rename(localFilePath);

      final completedTime = DateTime.now();
      final duration = completedTime.difference(startTime);

      LoggingService.performance(
        'PGE Sites Download',
        duration,
        'Downloaded ${totalBytes} bytes'
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

      // Parse CSV manually (header: id,name,lng,lat,N,NE,E,SE,S,SW,W,NW)
      final lines = csvContent.trim().split('\n');
      final sites = <Map<String, dynamic>>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        try {
          // Parse CSV line (handle quoted fields)
          final fields = _parseCsvLine(line);

          if (fields.length >= 12) {
            sites.add({
              'id': int.tryParse(fields[0]) ?? 0,
              'name': fields[1].replaceAll('"', ''),
              'longitude': double.tryParse(fields[2]) ?? 0.0,
              'latitude': double.tryParse(fields[3]) ?? 0.0,
              'wind_n': int.tryParse(fields[4]) ?? 0,
              'wind_ne': int.tryParse(fields[5]) ?? 0,
              'wind_e': int.tryParse(fields[6]) ?? 0,
              'wind_se': int.tryParse(fields[7]) ?? 0,
              'wind_s': int.tryParse(fields[8]) ?? 0,
              'wind_sw': int.tryParse(fields[9]) ?? 0,
              'wind_w': int.tryParse(fields[10]) ?? 0,
              'wind_nw': int.tryParse(fields[11]) ?? 0,
            });
          }
        } catch (e) {
          LoggingService.warning('[PGE_SITES] Failed to parse CSV line: $line');
          // Continue with other lines
        }
      }

      LoggingService.info('[PGE_SITES] Parsed ${sites.length} sites from CSV');

      LoggingService.structured('PGE_SITES_PARSED', {
        'sites_count': sites.length,
        'compressed_size': compressedBytes.length,
        'decompressed_size': decompressedBytes.length,
      });

      return sites;

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES] Failed to parse CSV data', error, stackTrace);
      rethrow;
    }
  }

  /// Parse a single CSV line handling quoted fields
  List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    // Add final field
    fields.add(buffer.toString());

    return fields;
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

  /// Clean up resources
  void dispose() {
    _progressController.close();
    _httpClient?.close();
    _httpClient = null;
  }
}