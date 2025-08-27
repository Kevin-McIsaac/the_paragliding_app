import 'dart:io';
import '../data/models/igc_file.dart';
import 'timezone_service.dart';
import 'logging_service.dart';

/// Parser for IGC (International Gliding Commission) file format
class IgcParser {
  // LRU cache for timezone detection with size limit to prevent memory leaks
  static final _TimezoneCache _timezoneCache = _TimezoneCache();
  /// Parse IGC file from file path
  Future<IgcFile> parseFile(String filePath) async {
    final file = File(filePath);
    final lines = await file.readAsLines();
    return _parseLines(lines);
  }


  /// Parse IGC content from string
  IgcFile parseString(String content) {
    final lines = content.split('\n');
    return _parseLines(lines);
  }

  /// Parse IGC lines
  IgcFile _parseLines(List<String> lines) {
    final headers = <String, String>{};
    final trackPoints = <IgcPoint>[];
    DateTime? flightDate;
    String pilot = '';
    String gliderType = '';
    String gliderID = '';
    String? timezone;
    
    // Track current date for midnight crossing detection
    DateTime? currentDate;
    DateTime? previousTimestamp;

    for (final line in lines) {
      if (line.isEmpty) continue;

      final recordType = line[0];
      
      switch (recordType) {
        case 'H':
          // Header record
          _parseHeader(line, headers);
          
          // Extract specific header values
          if (line.startsWith('HFDTE')) {
            flightDate = _parseDate(line);
            currentDate = flightDate; // Initialize current date
          } else if (line.startsWith('HFPLTPILOT')) {
            pilot = _extractHeaderValue(line, 'HFPLTPILOT');
          } else if (line.startsWith('HFGTYGLIDERTYPE')) {
            gliderType = _extractHeaderValue(line, 'HFGTYGLIDERTYPE');
          } else if (line.startsWith('HFGIDGLIDERID')) {
            gliderID = _extractHeaderValue(line, 'HFGIDGLIDERID');
          } 
          // Commented out - always use GPS-based timezone detection instead
          // else if (line.startsWith('HFTZNUTCOFFSET') || line.startsWith('HFTZN')) {
          //   timezone = _parseTimezone(line);
          // }
          break;
          
        case 'B':
          // B record (track point) - parse as UTC initially, will convert later
          // Pass current date which may have been incremented for midnight crossing
          final point = _parseBRecord(line, currentDate ?? flightDate ?? DateTime.now(), null);
          if (point != null) {
            // Check for midnight crossing
            if (previousTimestamp != null) {
              // If current time is earlier than previous time, we've crossed midnight
              final currentTimeOnly = point.timestamp.hour * 3600 + 
                                     point.timestamp.minute * 60 + 
                                     point.timestamp.second;
              final previousTimeOnly = previousTimestamp.hour * 3600 + 
                                      previousTimestamp.minute * 60 + 
                                      previousTimestamp.second;
              
              if (currentTimeOnly < previousTimeOnly) {
                // Midnight crossing detected - increment the date
                currentDate = currentDate?.add(const Duration(days: 1));
                LoggingService.info('IgcParser: Midnight crossing detected at ${point.timestamp.hour}:${point.timestamp.minute}:${point.timestamp.second}');
                
                // Re-parse the B record with the incremented date
                final correctedPoint = _parseBRecord(line, currentDate ?? DateTime.now(), null);
                if (correctedPoint != null) {
                  trackPoints.add(correctedPoint);
                  previousTimestamp = correctedPoint.timestamp;
                }
              } else {
                trackPoints.add(point);
                previousTimestamp = point.timestamp;
              }
            } else {
              // First point
              trackPoints.add(point);
              previousTimestamp = point.timestamp;
            }
          }
          break;
          
        default:
          // Other record types - store in headers for reference
          headers[recordType] = line;
      }
    }

    // If no date found in headers, try to extract from first B record
    if (flightDate == null && trackPoints.isNotEmpty) {
      flightDate = trackPoints.first.timestamp;
    }
    
    // Always detect timezone from GPS coordinates (override any HFTZNUTCOFFSET)
    if (trackPoints.isNotEmpty) {
      final firstPoint = trackPoints.first;
      
      // Create cache key based on coordinates to avoid duplicate detection
      final coordKey = '${firstPoint.latitude.toStringAsFixed(3)},${firstPoint.longitude.toStringAsFixed(3)}';
      
      // Check cache first
      String? cachedTimezone = _timezoneCache.get(coordKey);
      
      if (cachedTimezone == null) {
        // Not in cache, detect timezone
        final detectedTimezone = TimezoneService.getTimezoneFromCoordinates(
          firstPoint.latitude,
          firstPoint.longitude,
        );
        
        if (detectedTimezone != null) {
          // Convert timezone identifier to offset string
          cachedTimezone = TimezoneService.getOffsetStringFromTimezone(
            detectedTimezone,
            flightDate ?? DateTime.now(),
          );
          
          if (cachedTimezone != null) {
            // Cache the result
            _timezoneCache.put(coordKey, cachedTimezone);
            
            // Log only on first detection
            // Log timezone detection results
            LoggingService.info('IgcParser: Detected timezone from GPS: $detectedTimezone ($cachedTimezone)');
          }
        }
      }
      
      if (cachedTimezone != null) {
        timezone = cachedTimezone;
        
        // Re-process all track points with the detected timezone
        // Since B records are in UTC, we need to convert them to local time
        for (int i = 0; i < trackPoints.length; i++) {
          final point = trackPoints[i];
          // The timestamp is currently in UTC, convert to local
          final localTime = _convertUtcToLocal(
            DateTime.utc(
              point.timestamp.year,
              point.timestamp.month,
              point.timestamp.day,
              point.timestamp.hour,
              point.timestamp.minute,
              point.timestamp.second,
            ),
            timezone,
          );
          
          trackPoints[i] = IgcPoint(
            timestamp: localTime,
            latitude: point.latitude,
            longitude: point.longitude,
            pressureAltitude: point.pressureAltitude,
            gpsAltitude: point.gpsAltitude,
            isValid: point.isValid,
          );
        }
      }
    }
    
    // Validate timestamps are in chronological order
    if (trackPoints.length > 1) {
      bool timestampsValid = true;
      for (int i = 1; i < trackPoints.length; i++) {
        if (trackPoints[i].timestamp.isBefore(trackPoints[i - 1].timestamp)) {
          LoggingService.warning(
            'IgcParser: Timestamp validation failed - point $i '
            '(${trackPoints[i].timestamp.toIso8601String()}) is before point ${i - 1} '
            '(${trackPoints[i - 1].timestamp.toIso8601String()})'
          );
          timestampsValid = false;
        }
      }
      
      if (timestampsValid) {
        LoggingService.debug('IgcParser: All ${trackPoints.length} timestamps are in chronological order');
      } else {
        LoggingService.error('IgcParser: Timestamps are not in chronological order - midnight crossing may not be handled correctly');
      }
    }

    // Create the IgcFile first
    final igcFile = IgcFile(
      date: flightDate ?? DateTime.now(),
      pilot: pilot,
      gliderType: gliderType,
      gliderID: gliderID,
      trackPoints: trackPoints,
      headers: headers,
      timezone: timezone,
    );
    
    // Now update track points with parent reference and index
    for (int i = 0; i < trackPoints.length; i++) {
      final point = trackPoints[i];
      trackPoints[i] = IgcPoint(
        timestamp: point.timestamp,
        latitude: point.latitude,
        longitude: point.longitude,
        pressureAltitude: point.pressureAltitude,
        gpsAltitude: point.gpsAltitude,
        isValid: point.isValid,
        parentFile: igcFile,
        pointIndex: i,
      );
    }
    
    return igcFile;
  }

  /// Parse header record
  void _parseHeader(String line, Map<String, String> headers) {
    if (line.length < 2) return;
    
    final key = line.substring(0, 5);
    final value = line.substring(5);
    headers[key] = value;
  }

  /// Extract header value and clean up formatting
  String _extractHeaderValue(String line, String prefix) {
    if (line.length <= prefix.length) return '';
    
    String value = line.substring(prefix.length).trim();
    
    // Remove leading colon if present
    if (value.startsWith(':')) {
      value = value.substring(1).trim();
    }
    
    return value;
  }

  /// Parse timezone offset from HFTZNUTCOFFSET or similar header
  /// Converts formats like "+10.00h", "-05.30h" to standard "+10:00", "-05:30"

  /// Parse date from HFDTE record
  DateTime? _parseDate(String line) {
    // HFDTEDDMMYY where DD is day, MM is month, YY is year
    if (line.length < 11) return null;
    
    try {
      final dateStr = line.substring(5, 11); // DDMMYY
      final day = int.parse(dateStr.substring(0, 2));
      final month = int.parse(dateStr.substring(2, 4));
      final year = 2000 + int.parse(dateStr.substring(4, 6));
      
      return DateTime(year, month, day);
    } catch (e) {
      LoggingService.error('IgcParser: Error parsing date', e);
      return null;
    }
  }

  /// Parse B record (track point)
  /// B records contain UTC time according to IGC specification
  IgcPoint? _parseBRecord(String line, DateTime flightDate, String? timezone) {
    // B record format: B HHMMSS DDMMmmmN DDDMMmmmE V PPPPP GGGGG
    // Example: B1101355206343N00006198WA0058700558
    // Time is in UTC according to IGC specification
    
    if (line.length < 35) return null;
    
    try {
      // Time (HHMMSS) - UTC time
      final hours = int.parse(line.substring(1, 3));
      final minutes = int.parse(line.substring(3, 5));
      final seconds = int.parse(line.substring(5, 7));
      
      // Latitude (DDMMmmmN/S)
      final latDegrees = int.parse(line.substring(7, 9));
      final latMinutes = int.parse(line.substring(9, 11));
      final latDecimals = int.parse(line.substring(11, 14));
      final latDirection = line[14]; // N or S
      
      double latitude = latDegrees + (latMinutes + latDecimals / 1000.0) / 60.0;
      if (latDirection == 'S') latitude = -latitude;
      
      // Longitude (DDDMMmmmE/W)
      final lonDegrees = int.parse(line.substring(15, 18));
      final lonMinutes = int.parse(line.substring(18, 20));
      final lonDecimals = int.parse(line.substring(20, 23));
      final lonDirection = line[23]; // E or W
      
      double longitude = lonDegrees + (lonMinutes + lonDecimals / 1000.0) / 60.0;
      if (lonDirection == 'W') longitude = -longitude;
      
      // Valid flag
      final isValid = line[24] == 'A';
      
      // Pressure altitude
      final pressureAlt = int.parse(line.substring(25, 30));
      
      // GPS altitude
      final gpsAlt = int.parse(line.substring(30, 35));
      
      // Create UTC timestamp - timezone conversion will be done later in bulk
      DateTime timestamp = DateTime.utc(
        flightDate.year,
        flightDate.month,
        flightDate.day,
        hours,
        minutes,
        seconds,
      );
      
      // NOTE: Timezone conversion is done later in bulk after detection
      // This avoids double conversion
      
      return IgcPoint(
        timestamp: timestamp,
        latitude: latitude,
        longitude: longitude,
        pressureAltitude: pressureAlt,
        gpsAltitude: gpsAlt,
        isValid: isValid,
      );
    } catch (e) {
      LoggingService.error('IgcParser: Error parsing B record', e);
      return null;
    }
  }

  /// Convert UTC time to local time using timezone offset
  /// Takes a UTC DateTime and converts it to local time using the timezone offset
  DateTime _convertUtcToLocal(DateTime utcTime, String timezone) {
    try {
      // Parse timezone offset (e.g., "+10:00", "-05:30")
      final regex = RegExp(r'^([+-])(\d{2}):(\d{2})$');
      final match = regex.firstMatch(timezone);
      
      if (match == null) {
        return utcTime; // Return original if timezone format is invalid
      }
      
      final isPositive = match.group(1) == '+';
      final hours = int.parse(match.group(2)!);
      final minutes = int.parse(match.group(3)!);
      
      final offsetMinutes = (hours * 60) + minutes;
      final duration = Duration(minutes: isPositive ? offsetMinutes : -offsetMinutes);
      
      // Convert UTC to local time by adding the offset
      // If timezone is +10:00, local time is UTC + 10 hours
      return utcTime.add(duration);
    } catch (e) {
      LoggingService.error('IgcParser: Error converting UTC to local time', e);
      return utcTime;
    }
  }
  
  /// Clear timezone cache to free memory (useful for memory management)
  static void clearTimezoneCache() {
    _timezoneCache.clear();
  }
  
  /// Get timezone cache statistics for monitoring
  static Map<String, dynamic> getTimezoneStats() {
    return _timezoneCache.getStats();
  }
}

/// LRU Cache for timezone detection to prevent memory leaks
/// Maintains a maximum size and evicts least recently used entries
class _TimezoneCache {
  static const int _maxSize = 100; // Reasonable limit for timezone cache
  
  final Map<String, String?> _cache = {};
  final List<String> _accessOrder = [];
  
  /// Get cached timezone for coordinate key
  String? get(String key) {
    final value = _cache[key];
    if (value != null) {
      // Update access order (move to end = most recently used)
      _accessOrder.remove(key);
      _accessOrder.add(key);
    }
    return value;
  }
  
  /// Store timezone in cache with LRU eviction
  void put(String key, String? value) {
    if (_cache.containsKey(key)) {
      // Update existing entry
      _cache[key] = value;
      _accessOrder.remove(key);
      _accessOrder.add(key);
    } else {
      // Add new entry
      _cache[key] = value;
      _accessOrder.add(key);
      
      // Evict oldest entries if cache is full
      while (_cache.length > _maxSize) {
        final oldestKey = _accessOrder.removeAt(0);
        _cache.remove(oldestKey);
        LoggingService.debug('IgcParser: Evicted timezone cache entry: $oldestKey');
      }
    }
  }
  
  /// Clear all cached entries (useful for memory management)
  void clear() {
    _cache.clear();
    _accessOrder.clear();
    LoggingService.info('IgcParser: Timezone cache cleared');
  }
  
  /// Get cache statistics for debugging
  Map<String, dynamic> getStats() {
    return {
      'size': _cache.length,
      'maxSize': _maxSize,
      'hitRate': _cache.isEmpty ? 0.0 : _accessOrder.length / _cache.length,
    };
  }
}