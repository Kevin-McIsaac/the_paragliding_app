import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/logging_service.dart';

/// Service for validating Cesium Ion access tokens
class CesiumTokenValidator {
  static const String _baseUrl = 'https://api.cesium.com/v1';
  static const Duration _timeout = Duration(seconds: 10);
  
  /// Validates a Cesium Ion access token by making a test API call
  /// Returns true if the token is valid, false otherwise
  static Future<bool> validateToken(String token) async {
    if (token.isEmpty) {
      LoggingService.warning('Cesium Token Validation', 'Token is empty');
      return false;
    }
    
    try {
      // Use the profile endpoint (/v1/me) which works better for token validation
      final response = await http.get(
        Uri.parse('$_baseUrl/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(_timeout);
      
      LoggingService.info('Cesium Token Validation: Response status ${response.statusCode}');
      
      if (response.statusCode == 200) {
        // Try to parse the response to ensure it's valid JSON
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('id')) {
          LoggingService.info('Cesium Token Validation: Token is valid for user ID ${data['id']}');
          return true;
        }
      } else if (response.statusCode == 401) {
        LoggingService.warning('Cesium Token Validation', 'Token is invalid or expired');
      } else if (response.statusCode == 403) {
        LoggingService.warning('Cesium Token Validation', 'Token lacks required permissions');
      } else {
        LoggingService.error('Cesium Token Validation', 'Unexpected status code: ${response.statusCode}, body: ${response.body}');
      }
      
      return false;
    } on TimeoutException {
      LoggingService.error('Cesium Token Validation', 'Request timed out after ${_timeout.inSeconds} seconds');
      return false;
    } on http.ClientException catch (e) {
      LoggingService.error('Cesium Token Validation', 'Network error: $e');
      return false;
    } on FormatException catch (e) {
      LoggingService.error('Cesium Token Validation', 'Invalid JSON response: $e');
      return false;
    } catch (e) {
      LoggingService.error('Cesium Token Validation', 'Unexpected error: $e');
      return false;
    }
  }
  
  /// Gets basic token information (for display purposes)
  /// Returns null if token is invalid or if there's an error
  static Future<Map<String, dynamic>?> getTokenInfo(String token) async {
    if (token.isEmpty) return null;
    
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data as Map<String, dynamic>?;
      }
      
      return null;
    } catch (e) {
      LoggingService.debug('Cesium Token Info: Failed to get token info: $e');
      return null;
    }
  }
  
  /// Checks if token validation is still fresh (always true once validated)
  static bool isValidationFresh(DateTime? validationDate) {
    return validationDate != null;
  }
  
  /// Formats a token for display (shows first 8 and last 4 characters)
  static String maskToken(String token) {
    if (token.length <= 12) {
      return '****...****';
    }
    
    return '${token.substring(0, 8)}...${token.substring(token.length - 4)}';
  }
}