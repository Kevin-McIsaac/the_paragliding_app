import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'map_tile_provider.dart';

/// Utility functions for inspecting and clearing the on-disk map tile cache
/// shared by every map screen (see [MapTileProvider]).
class CacheUtils {
  static const _sizeMonitorFileName = 'sizeMonitor.bin';

  /// Directory flutter_map's built-in caching provider writes tiles to.
  static Future<Directory> _cacheDirectory() async {
    final cacheDir = await getApplicationCacheDirectory();
    return Directory(p.join(cacheDir.path, 'fm_cache'));
  }

  /// Number of cached tiles and their total size on disk.
  /// Returns zero for both if no map has been viewed yet.
  static Future<({int tileCount, int sizeBytes})> getDiskCacheStats() async {
    final dir = await _cacheDirectory();
    if (!await dir.exists()) return (tileCount: 0, sizeBytes: 0);

    var tileCount = 0;
    var sizeBytes = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (p.basename(entity.path) == _sizeMonitorFileName) continue;
      tileCount++;
      sizeBytes += await entity.length();
    }
    return (tileCount: tileCount, sizeBytes: sizeBytes);
  }

  /// Delete every cached tile. The shared caching provider re-initialises
  /// itself (with the same config) the next time any map loads a tile.
  static Future<void> clearDiskTileCache() async {
    await MapTileProvider.cachingProvider.destroy(deleteCache: true);
  }

  /// Format bytes into human-readable units
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
