import 'dart:io';
import 'package:flutter/services.dart';

class BuildInfo {
  static const String version = '1.0.0';
  static const String buildNumber = '1';
  
  static const MethodChannel _channel = MethodChannel('free_flight_log/build_info');
  
  // Cache the git commit to avoid multiple platform calls
  static String? _cachedGitCommit;
  
  // Get git commit hash from platform (Android) or fallback
  static Future<String> get gitCommit async {
    if (_cachedGitCommit != null) return _cachedGitCommit!;
    
    if (Platform.isAndroid) {
      try {
        final String result = await _channel.invokeMethod('getGitCommit');
        _cachedGitCommit = result;
        return result;
      } catch (e) {
        _cachedGitCommit = 'dev';
        return 'dev';
      }
    } else {
      _cachedGitCommit = 'dev';
      return 'dev';
    }
  }
  
  static String get fullVersion => '$version+$buildNumber';
  
  // Synchronous getter that returns cached value or 'dev'
  static String get buildIdentifier => _cachedGitCommit ?? 'dev';
}