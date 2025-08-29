class BuildInfo {
  static const String version = '1.0.0';
  static const String buildNumber = '1';
  static const String gitCommit = 'a51bd3e';
  
  static String get fullVersion => '$version+$buildNumber';
  static String get buildIdentifier => gitCommit;
}