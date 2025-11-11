import 'dart:io';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

class BuildInfo {
  static const MethodChannel _channel = MethodChannel('the_paragliding_app/build_info');

  // Cache package info to avoid multiple platform calls
  static PackageInfo? _cachedPackageInfo;
  static String? _cachedGitCommit;
  static String? _cachedGitBranch;

  // Get package info from platform
  static Future<PackageInfo> get _packageInfo async {
    _cachedPackageInfo ??= await PackageInfo.fromPlatform();
    return _cachedPackageInfo!;
  }

  // Get version from pubspec.yaml (automatically synced)
  static Future<String> get version async {
    final info = await _packageInfo;
    return info.version;
  }

  // Get build number from pubspec.yaml (automatically synced)
  static Future<String> get buildNumber async {
    final info = await _packageInfo;
    return info.buildNumber;
  }

  // Get full version string (version+buildNumber)
  static Future<String> get fullVersion async {
    final info = await _packageInfo;
    return '${info.version}+${info.buildNumber}';
  }

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