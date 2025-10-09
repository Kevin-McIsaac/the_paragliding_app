/// Country information for airspace data
class CountryInfo {
  final String code;
  final String name;
  final int estimatedSizeMB;

  const CountryInfo({
    required this.code,
    required this.name,
    required this.estimatedSizeMB,
  });
}

/// Metadata about downloaded country data
class CountryMetadata {
  final String countryCode;
  final int airspaceCount;
  final DateTime downloadTime;
  final String? etag;
  final String? lastModified;
  final int version;

  CountryMetadata({
    required this.countryCode,
    required this.airspaceCount,
    required this.downloadTime,
    this.etag,
    this.lastModified,
    required this.version,
  });

  factory CountryMetadata.fromJson(Map<String, dynamic> json) {
    return CountryMetadata(
      countryCode: json['countryCode'] as String,
      airspaceCount: json['airspaceCount'] as int,
      downloadTime: DateTime.parse(json['downloadTime'] as String),
      etag: json['etag'] as String?,
      lastModified: json['lastModified'] as String?,
      version: json['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'countryCode': countryCode,
      'airspaceCount': airspaceCount,
      'downloadTime': downloadTime.toIso8601String(),
      'etag': etag,
      'lastModified': lastModified,
      'version': version,
    };
  }

  bool get needsUpdate {
    // Check if data is older than 30 days
    final age = DateTime.now().difference(downloadTime);
    return age.inDays > 30;
  }

  double get sizeMB {
    // Rough estimate based on airspace count
    return airspaceCount * 0.001; // ~1KB per airspace average
  }
}

/// Result of a country download operation
class DownloadResult {
  final bool success;
  final String countryCode;
  final int? airspaceCount;
  final double? sizeMB;
  final int durationMs;
  final String? error;

  DownloadResult({
    required this.success,
    required this.countryCode,
    this.airspaceCount,
    this.sizeMB,
    required this.durationMs,
    this.error,
  });
}

/// Country download status for UI
enum DownloadStatus {
  notDownloaded,
  downloading,
  downloaded,
  updateAvailable,
  error,
}

/// UI model for country selection
class CountrySelectionModel {
  final CountryInfo info;
  final bool isSelected;
  final bool isDownloaded;
  final DownloadStatus status;
  final double? downloadProgress;
  final CountryMetadata? metadata;

  CountrySelectionModel({
    required this.info,
    required this.isSelected,
    required this.isDownloaded,
    required this.status,
    this.downloadProgress,
    this.metadata,
  });

  CountrySelectionModel copyWith({
    bool? isSelected,
    bool? isDownloaded,
    DownloadStatus? status,
    double? downloadProgress,
    CountryMetadata? metadata,
  }) {
    return CountrySelectionModel(
      info: info,
      isSelected: isSelected ?? this.isSelected,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      status: status ?? this.status,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      metadata: metadata ?? this.metadata,
    );
  }
}