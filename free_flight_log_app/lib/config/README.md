# Configuration Management

## Cesium API Token Security

The `cesium_config.dart` file contains a Cesium Ion access token that is currently hardcoded for development purposes.

### ⚠️ Security Warning

**DO NOT** use hardcoded API tokens in production applications. The current implementation is for development only.

### Production Recommendations

For production deployments, consider these secure alternatives:

1. **Environment Variables**
   ```dart
   static String get ionAccessToken => 
     const String.fromEnvironment('CESIUM_ION_TOKEN', 
       defaultValue: 'development-token-here');
   ```

2. **Flutter Secure Storage**
   ```dart
   import 'package:flutter_secure_storage/flutter_secure_storage.dart';
   
   class SecureCesiumConfig {
     static const _storage = FlutterSecureStorage();
     
     static Future<String> getIonToken() async {
       return await _storage.read(key: 'cesium_ion_token') ?? '';
     }
   }
   ```

3. **Remote Configuration Service**
   - Firebase Remote Config
   - AWS AppConfig
   - Custom configuration API

4. **Build-Time Injection**
   ```bash
   flutter build apk --dart-define=CESIUM_TOKEN=$CESIUM_ION_TOKEN
   ```

### Token Management Best Practices

1. **Never commit tokens to version control**
   - Add `cesium_config.dart` to `.gitignore` if it contains real tokens
   - Use placeholder tokens in committed code

2. **Rotate tokens regularly**
   - Set up token rotation schedule
   - Monitor token usage on Cesium Ion dashboard

3. **Implement token restrictions**
   - Limit token to specific domains/apps
   - Set usage quotas
   - Monitor for unusual activity

4. **Use different tokens for different environments**
   - Development token with relaxed limits
   - Staging token with production-like restrictions
   - Production token with strict security

### Current Token Scope

The current development token provides access to:
- Cesium World Terrain
- Bing Maps Aerial imagery
- Basic geocoding services

For production use, obtain a dedicated token from:
https://cesium.com/ion/tokens