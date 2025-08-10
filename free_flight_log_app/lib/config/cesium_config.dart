/// Configuration for Cesium 3D Map
/// This file contains the Cesium Ion access token and other configuration
/// 
/// TODO: In production, this should be stored securely and not committed to version control
/// Consider using:
/// - Environment variables
/// - Flutter secure storage
/// - Remote configuration service
/// - Build-time injection

class CesiumConfig {
  // WARNING: This token should not be hardcoded in production
  // Move to secure storage or environment variables
  static const String ionAccessToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiIzYzkwM2EwNS00YjU2LTRiMzEtYjE3NC01ODlkYWM3MjMzNmEiLCJpZCI6MzMwMjc0LCJpYXQiOjE3NTQ3MjUxMjd9.IizVx3Z5iR9Xe1TbswK-FKidO9UoWa5pqa4t66NK8W0';
  
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