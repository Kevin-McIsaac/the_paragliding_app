import 'dart:io';
import '../data/models/igc_file.dart';
import 'timezone_service.dart';
import 'logging_service.dart';

/// Parser for IGC (International Gliding Commission) file format
class IgcParser {
  // Cache for timezone detection per file to avoid duplicate logging
  static final Map<String, String?> _timezoneCache = {};
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
          final point = _parseBRecord(line, flightDate ?? DateTime.now(), null);
          if (point != null) {
            trackPoints.add(point);
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
      String? cachedTimezone = _timezoneCache[coordKey];
      
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
            _timezoneCache[coordKey] = cachedTimezone;
            
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
            timezone!,
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

    return IgcFile(
      date: flightDate ?? DateTime.now(),
      pilot: pilot,
      gliderType: gliderType,
      gliderID: gliderID,
      trackPoints: trackPoints,
      headers: headers,
      timezone: timezone,
    );
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
  String? _parseTimezone(String line) {
    try {
      String value = _extractHeaderValue(line, line.startsWith('HFTZNUTCOFFSET') ? 'HFTZNUTCOFFSET' : 'HFTZN');
      
      if (value.isEmpty) return null;
      
      // Remove trailing 'h' if present
      value = value.replaceAll(RegExp(r'h$'), '').trim();
      
      // Handle formats like "+10.00", "-05.30", "10.00"
      final regex = RegExp(r'^([+-]?)(\d{1,2})\.(\d{2})$');
      final match = regex.firstMatch(value);
      
      if (match != null) {
        String sign = match.group(1) ?? '';
        if (sign.isEmpty) sign = '+'; // Explicitly add + if no sign
        final hours = match.group(2)!.padLeft(2, '0');
        final minutes = match.group(3)!;
        
        return '$sign$hours:$minutes';
      }
      
      // Try simple integer format like "+10", "-5"
      final simpleRegex = RegExp(r'^([+-]?)(\d{1,2})$');
      final simpleMatch = simpleRegex.firstMatch(value);
      
      if (simpleMatch != null) {
        String sign = simpleMatch.group(1) ?? '';
        if (sign.isEmpty) sign = '+'; // Explicitly add + if no sign
        final hours = simpleMatch.group(2)!.padLeft(2, '0');
        return '$sign$hours:00';
      }
      
      return null;
    } catch (e) {
      LoggingService.error('IgcParser: Error parsing timezone', e);
      return null;
    }
  }

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
      
      // Create UTC timestamp
      DateTime timestamp = DateTime.utc(
        flightDate.year,
        flightDate.month,
        flightDate.day,
        hours,
        minutes,
        seconds,
      );
      
      // Convert UTC to local time if timezone is known
      if (timezone != null) {
        timestamp = _convertUtcToLocal(timestamp, timezone);
      }
      // If no timezone provided, keep as UTC
      
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
}