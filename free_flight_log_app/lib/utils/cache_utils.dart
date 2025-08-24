import 'package:flutter/painting.dart';

/// Utility functions for managing map tile caching
class CacheUtils {
  /// Get information about the current image cache state
  static String getCacheInfo() {
    final cache = PaintingBinding.instance.imageCache;
    final sizeInMB = (cache.currentSizeBytes / (1024 * 1024)).toStringAsFixed(1);
    return '${cache.currentSize} tiles, $sizeInMB MB';
  }
  
  /// Clear all cached map tiles
  static void clearMapCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }
  
  /// Get the current cache size in bytes
  static int getCurrentCacheSize() {
    return PaintingBinding.instance.imageCache.currentSizeBytes;
  }
  
  /// Get the current number of cached tiles
  static int getCurrentCacheCount() {
    return PaintingBinding.instance.imageCache.currentSize;
  }
  
  /// Format bytes into human-readable units
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  
  /// Get detailed cache statistics
  static Map<String, dynamic> getCacheStats() {
    final cache = PaintingBinding.instance.imageCache;
    return {
      'tileCount': cache.currentSize,
      'sizeBytes': cache.currentSizeBytes,
      'sizeFormatted': formatBytes(cache.currentSizeBytes),
      'maxSizeBytes': cache.maximumSizeBytes,
      'maxSize': cache.maximumSize,
    };
  }
}