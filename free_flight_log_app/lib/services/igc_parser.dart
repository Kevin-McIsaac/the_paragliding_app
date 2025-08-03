import 'dart:io';
import '../data/models/igc_file.dart';

/// Parser for IGC (International Gliding Commission) file format
class IgcParser {
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
          break;
          
        case 'B':
          // B record (track point)
          final point = _parseBRecord(line, flightDate ?? DateTime.now());
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

    return IgcFile(
      date: flightDate ?? DateTime.now(),
      pilot: pilot,
      gliderType: gliderType,
      gliderID: gliderID,
      trackPoints: trackPoints,
      headers: headers,
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
      print('Error parsing date: $e');
      return null;
    }
  }

  /// Parse B record (track point)
  IgcPoint? _parseBRecord(String line, DateTime flightDate) {
    // B record format: B HHMMSS DDMMmmmN DDDMMmmmE V PPPPP GGGGG
    // Example: B1101355206343N00006198WA0058700558
    
    if (line.length < 35) return null;
    
    try {
      // Time (HHMMSS)
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
      
      // Create timestamp
      final timestamp = DateTime(
        flightDate.year,
        flightDate.month,
        flightDate.day,
        hours,
        minutes,
        seconds,
      );
      
      return IgcPoint(
        timestamp: timestamp,
        latitude: latitude,
        longitude: longitude,
        pressureAltitude: pressureAlt,
        gpsAltitude: gpsAlt,
        isValid: isValid,
      );
    } catch (e) {
      print('Error parsing B record: $e');
      return null;
    }
  }
}