import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'logging_service.dart';

/// Centralized API key management service
///
/// This service provides a single source of truth for all API keys used in the app.
/// It supports two methods of key injection:
/// 1. dart-define: For production builds via CI/CD (highest priority)
/// 2. flutter_dotenv: For local development (.env file)
///
/// Usage:
/// ```dart
/// final apiKey = ApiKeys.ffvlApiKey;
/// ```
class ApiKeys {
  // Flags to ensure API key source is logged only once
  static bool _ffvlLogged = false;
  static bool _googleMapsLogged = false;
  static bool _cesiumLogged = false;

  /// FFVL (French Free Flight Federation) Weather API Key
  static String get ffvlApiKey {
    // Try dart-define first (production builds)
    const fromEnv = String.fromEnvironment('FFVL_API_KEY');
    if (fromEnv.isNotEmpty) {
      if (!_ffvlLogged) {
        LoggingService.info('Using FFVL API key from dart-define');
        _ffvlLogged = true;
      }
      return fromEnv;
    }

    // Fall back to dotenv (development)
    final fromDotenv = dotenv.env['FFVL_API_KEY'] ?? '';
    if (fromDotenv.isNotEmpty) {
      if (!_ffvlLogged) {
        LoggingService.info('Using FFVL API key from .env file');
        _ffvlLogged = true;
      }
      return fromDotenv;
    }

    // No key found
    if (!_ffvlLogged) {
      LoggingService.warning('No FFVL API key found. Please set FFVL_API_KEY in .env file or via --dart-define');
      _ffvlLogged = true;
    }
    return '';
  }

  /// Google Maps API Key (optional)
  static String get googleMapsApiKey {
    // Try dart-define first (production builds)
    const fromEnv = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
    if (fromEnv.isNotEmpty) {
      if (!_googleMapsLogged) {
        LoggingService.info('Using Google Maps API key from dart-define');
        _googleMapsLogged = true;
      }
      return fromEnv;
    }

    // Fall back to dotenv (development)
    final fromDotenv = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    if (fromDotenv.isNotEmpty) {
      if (!_googleMapsLogged) {
        LoggingService.info('Using Google Maps API key from .env file');
        _googleMapsLogged = true;
      }
      return fromDotenv;
    }

    // Default placeholder (maps won't work but app won't crash)
    return 'YOUR_GOOGLE_MAPS_API_KEY_HERE';
  }

  /// OpenAIP API Key (optional, user-configurable)
  /// This is primarily for development defaults
  static String get openAipApiKey {
    // Try dart-define first (production builds)
    const fromEnv = String.fromEnvironment('OPENAIP_API_KEY');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }

    // Fall back to dotenv (development)
    final fromDotenv = dotenv.env['OPENAIP_API_KEY'] ?? '';
    return fromDotenv;
  }

  /// Cesium Ion Access Token (optional)
  /// For 3D map visualization with Cesium
  static String get cesiumIonToken {
    // Try dart-define first (production builds)
    const fromEnv = String.fromEnvironment('CESIUM_ION_TOKEN');
    if (fromEnv.isNotEmpty) {
      if (!_cesiumLogged) {
        LoggingService.info('Using Cesium Ion token from dart-define');
        _cesiumLogged = true;
      }
      return fromEnv;
    }

    // Fall back to dotenv (development)
    final fromDotenv = dotenv.env['CESIUM_ION_TOKEN'] ?? '';
    if (fromDotenv.isNotEmpty) {
      if (!_cesiumLogged) {
        LoggingService.info('Using Cesium Ion token from .env file');
        _cesiumLogged = true;
      }
      return fromDotenv;
    }

    // Default empty - user can provide their own
    return '';
  }

  /// Check if API keys are properly configured
  static bool get isConfigured {
    return ffvlApiKey.isNotEmpty;
  }

  /// Initialize dotenv (called from main.dart)
  /// Returns true if .env file was loaded successfully
  static Future<bool> initialize() async {
    try {
      await dotenv.load(fileName: '.env');
      LoggingService.info('Environment variables loaded from .env file');
      return true;
    } catch (e) {
      // .env file not found or error loading - this is OK in production
      LoggingService.info('.env file not found or could not be loaded (this is normal in production)');
      return false;
    }
  }

  /// Log current API key status (for debugging)
  static void logStatus() {
    LoggingService.structured('API_KEYS_STATUS', {
      'ffvl_configured': ffvlApiKey.isNotEmpty,
      'google_maps_configured': googleMapsApiKey != 'YOUR_GOOGLE_MAPS_API_KEY_HERE',
      'openaip_configured': openAipApiKey.isNotEmpty,
      'cesium_configured': cesiumIonToken.isNotEmpty,
      'source': _getKeySource(),
    });
  }

  static String _getKeySource() {
    // Check if any dart-define keys are present
    const ffvlFromEnv = String.fromEnvironment('FFVL_API_KEY');
    if (ffvlFromEnv.isNotEmpty) {
      return 'dart-define';
    }

    // Check if dotenv is loaded
    if (dotenv.env.isNotEmpty) {
      return 'dotenv';
    }

    return 'none';
  }
}