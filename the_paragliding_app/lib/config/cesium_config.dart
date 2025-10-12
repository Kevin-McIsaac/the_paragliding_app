/// Configuration for Cesium 3D Map
library;

import '../services/api_keys.dart';

class CesiumConfig {
  /// Get the Cesium Ion access token
  /// First checks for user-configured token, then falls back to environment/default
  static String get ionAccessToken {
    // Get from environment/default
    final token = ApiKeys.cesiumIonToken;
    if (token.isNotEmpty) {
      return token;
    }

    // Return empty string if no token configured
    // User can still provide their own token via the UI
    return '';
  }
  
  // Memory management settings
  static const int tileCacheSize = 25;
  static const int maximumMemoryUsageMB = 128;
  static const double maximumScreenSpaceError = 4.0;
  static const int maximumTextureSize = 1024;
  
  // Performance settings
  static const int targetFrameRate = 30;
  static const double resolutionScale = 0.85;
  
  // Cleanup intervals
  static const Duration memoryCleanupInterval = Duration(seconds: 30);
  static const Duration memoryMonitorInterval = Duration(seconds: 30);
}