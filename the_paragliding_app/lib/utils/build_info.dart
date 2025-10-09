import 'dart:io';
import 'package:flutter/services.dart';

class BuildInfo {
  static const String version = '1.0.0';
  static const String buildNumber = '1';
  
  static const MethodChannel _channel = MethodChannel('the_paragliding_app/build_info');
  
  // Cache the git commit to avoid multiple platform calls
  static String? _cachedGitCommit;
  static String? _cachedGitBranch;
  
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
  
  // Get git branch name from platform (Android) or fallback
  static Future<String> get gitBranch async {
    if (_cachedGitBranch != null) return _cachedGitBranch!;
    
    if (Platform.isAndroid) {
      try {
        final String result = await _channel.invokeMethod('getGitBranch');
        _cachedGitBranch = result;
        return result;
      } catch (e) {
        _cachedGitBranch = 'main';
        return 'main';
      }
    } else {
      _cachedGitBranch = 'main';
      return 'main';
    }
  }
  
  // Synchronous getter that returns cached value or 'dev'
  static String get buildIdentifier => _cachedGitCommit ?? 'dev';
  
  // Synchronous getter for branch name
  static String get branchName => _cachedGitBranch ?? 'main';
}