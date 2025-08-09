import 'dart:io';
import 'package:xml/xml.dart';
import '../data/models/paragliding_site.dart';
import '../services/logging_service.dart';

class KmlParser {
  /// Parse KML file from Paraglidingearth.com and extract paragliding sites
  static Future<List<ParaglidingSite>> parseKmlFile(String filePath) async {
    try {
      final file = File(filePath);
      final contents = await file.readAsString();
      return parseKmlString(contents);
    } catch (e) {
      LoggingService.error('KmlParser: Error reading KML file', e);
      return [];
    }
  }

  /// Parse KML string content and extract paragliding sites
  static List<ParaglidingSite> parseKmlString(String kmlContent) {
    try {
      final document = XmlDocument.parse(kmlContent);
      final sites = <ParaglidingSite>[];

      // Find all Placemark elements (each represents a site)
      final placemarks = document.findAllElements('Placemark');

      for (final placemark in placemarks) {
        final site = _parsePlacemark(placemark);
        if (site != null) {
          sites.add(site);
        }
      }

      LoggingService.info('KmlParser: Parsed ${sites.length} sites from KML');
      return sites;
    } catch (e) {
      LoggingService.error('KmlParser: Error parsing KML', e);
      return [];
    }
  }

  /// Parse individual Placemark element into ParaglidingSite
  static ParaglidingSite? _parsePlacemark(XmlElement placemark) {
    try {
      // Extract name
      final nameElement = placemark.findElements('name').firstOrNull;
      if (nameElement == null) return null;
      final name = nameElement.innerText.trim();
      if (name.isEmpty) return null;

      // Extract coordinates from Point geometry
      final pointElement = placemark.findElements('Point').firstOrNull;
      if (pointElement == null) return null;

      final coordinatesElement = pointElement.findElements('coordinates').firstOrNull;
      if (coordinatesElement == null) return null;

      final coordinatesText = coordinatesElement.innerText.trim();
      final coords = _parseCoordinates(coordinatesText);
      if (coords == null) return null;

      // Extract description and parse additional data
      final descriptionElement = placemark.findElements('description').firstOrNull;
      final description = descriptionElement?.innerText.trim();

      // Parse extended data for additional site information
      final extendedData = _parseExtendedData(placemark);

      // Determine site type from name/description
      final siteType = _determineSiteType(name, description);

      // Extract rating and other metadata
      final rating = _extractRating(description, extendedData);
      final windDirections = _extractWindDirections(description, extendedData);
      final country = _extractCountry(name, description, extendedData);
      final region = _extractRegion(name, description, extendedData);

      return ParaglidingSite(
        name: _cleanSiteName(name),
        latitude: coords['lat']!,
        longitude: coords['lon']!,
        altitude: coords['alt']?.round(),
        description: description,
        windDirections: windDirections,
        siteType: siteType,
        rating: rating,
        country: country,
        region: region,
        popularity: _calculatePopularity(description, extendedData),
      );
    } catch (e) {
      LoggingService.error('KmlParser: Error parsing placemark', e);
      return null;
    }
  }

  /// Parse coordinates string (format: "lon,lat,alt")
  static Map<String, double>? _parseCoordinates(String coordinatesText) {
    try {
      final parts = coordinatesText.split(',');
      if (parts.length < 2) return null;

      final lon = double.parse(parts[0].trim());
      final lat = double.parse(parts[1].trim());
      final alt = parts.length > 2 ? double.tryParse(parts[2].trim()) : null;

      // Validate coordinate ranges
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
        return null;
      }

      return {
        'lat': lat,
        'lon': lon,
        if (alt != null) 'alt': alt,
      };
    } catch (e) {
      return null;
    }
  }

  /// Parse ExtendedData elements for additional site information
  static Map<String, String> _parseExtendedData(XmlElement placemark) {
    final extendedData = <String, String>{};

    try {
      final extendedDataElement = placemark.findElements('ExtendedData').firstOrNull;
      if (extendedDataElement == null) return extendedData;

      // Parse Data elements
      final dataElements = extendedDataElement.findElements('Data');
      for (final dataElement in dataElements) {
        final name = dataElement.getAttribute('name');
        final valueElement = dataElement.findElements('value').firstOrNull;
        if (name != null && valueElement != null) {
          extendedData[name] = valueElement.innerText.trim();
        }
      }

      // Parse SimpleData elements (alternative format)
      final simpleDataElements = extendedDataElement.findElements('SimpleData');
      for (final simpleDataElement in simpleDataElements) {
        final name = simpleDataElement.getAttribute('name');
        if (name != null) {
          extendedData[name] = simpleDataElement.innerText.trim();
        }
      }
    } catch (e) {
      // Ignore parsing errors for extended data
    }

    return extendedData;
  }

  /// Determine site type from name and description
  static String _determineSiteType(String name, String? description) {
    final nameUpper = name.toUpperCase();
    final descUpper = description?.toUpperCase() ?? '';

    if (nameUpper.contains('LANDING') || nameUpper.contains('LZ') ||
        descUpper.contains('LANDING') || descUpper.contains('LZ')) {
      return 'landing';
    }

    if (nameUpper.contains('LAUNCH') || nameUpper.contains('TAKEOFF') ||
        descUpper.contains('LAUNCH') || descUpper.contains('TAKEOFF')) {
      return 'launch';
    }

    // Default to launch for paragliding sites
    return 'launch';
  }

  /// Extract rating from description or extended data
  static int _extractRating(String? description, Map<String, String> extendedData) {
    // Check extended data first
    final ratingStr = extendedData['rating'] ?? extendedData['stars'];
    if (ratingStr != null) {
      final rating = int.tryParse(ratingStr);
      if (rating != null && rating >= 1 && rating <= 5) {
        return rating;
      }
    }

    // Try to extract from description (look for star patterns)
    if (description != null) {
      final starMatch = RegExp(r'(\d+)\s*[★⭐*]\s*').firstMatch(description);
      if (starMatch != null) {
        final rating = int.tryParse(starMatch.group(1)!);
        if (rating != null && rating >= 1 && rating <= 5) {
          return rating;
        }
      }
    }

    return 0; // No rating found
  }

  /// Extract wind directions from description or extended data
  static List<String> _extractWindDirections(String? description, Map<String, String> extendedData) {
    final directions = <String>[];

    // Check extended data
    final windData = extendedData['wind'] ?? extendedData['wind_directions'];
    if (windData != null) {
      directions.addAll(_parseWindDirections(windData));
    }

    // Parse from description
    if (description != null && directions.isEmpty) {
      directions.addAll(_parseWindDirections(description));
    }

    return directions.toSet().toList(); // Remove duplicates
  }

  /// Parse wind directions from text
  static List<String> _parseWindDirections(String text) {
    final directions = <String>[];
    final compassDirections = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    
    for (final direction in compassDirections) {
      if (text.toUpperCase().contains(direction)) {
        directions.add(direction);
      }
    }

    return directions;
  }

  /// Extract country from name, description, or extended data
  static String? _extractCountry(String name, String? description, Map<String, String> extendedData) {
    // Check extended data first
    final country = extendedData['country'] ?? extendedData['Country'];
    if (country != null && country.isNotEmpty) {
      return country;
    }

    // Try to extract from site name (often in format "Site Name - Country")
    final nameParts = name.split(' - ');
    if (nameParts.length > 1) {
      final lastPart = nameParts.last.trim();
      if (lastPart.length >= 2 && lastPart.length <= 30) {
        return lastPart;
      }
    }

    return null;
  }

  /// Extract region from name, description, or extended data
  static String? _extractRegion(String name, String? description, Map<String, String> extendedData) {
    // Check extended data first
    final region = extendedData['region'] ?? extendedData['state'] ?? extendedData['province'];
    if (region != null && region.isNotEmpty) {
      return region;
    }

    return null;
  }

  /// Calculate popularity score based on available data
  static double? _calculatePopularity(String? description, Map<String, String> extendedData) {
    double score = 0.0;

    // Factors that indicate popularity:
    // - Rating
    final rating = _extractRating(description, extendedData);
    score += rating * 20; // 0-100 points for rating

    // - Detailed description (more text = more popular/documented)
    if (description != null && description.length > 100) {
      score += 30;
    } else if (description != null && description.length > 50) {
      score += 15;
    }

    // - Wind direction data available
    final windDirections = _extractWindDirections(description, extendedData);
    if (windDirections.isNotEmpty) {
      score += 20;
    }

    // - Altitude information
    if (extendedData.containsKey('altitude') || description?.contains('elevation') == true) {
      score += 10;
    }

    return score > 0 ? score : null;
  }

  /// Clean up site name by removing common prefixes/suffixes
  static String _cleanSiteName(String name) {
    String cleaned = name.trim();

    // Remove common prefixes
    final prefixes = ['Launch: ', 'Takeoff: ', 'LZ: ', 'Landing: '];
    for (final prefix in prefixes) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length).trim();
        break;
      }
    }

    // Remove coordinates suffix if present
    cleaned = cleaned.replaceAll(RegExp(r'\s*\([^)]*°[^)]*\)$'), '');

    return cleaned;
  }

  /// Filter sites to get the most popular ones
  static List<ParaglidingSite> filterPopularSites(List<ParaglidingSite> sites, int maxCount) {
    // Sort by popularity score (descending), then by rating, then by name
    sites.sort((a, b) {
      // Primary: Popularity score
      final aScore = a.popularity ?? 0;
      final bScore = b.popularity ?? 0;
      if (aScore != bScore) return bScore.compareTo(aScore);

      // Secondary: Rating
      if (a.rating != b.rating) return b.rating.compareTo(a.rating);

      // Tertiary: Name (alphabetical)
      return a.name.compareTo(b.name);
    });

    return sites.take(maxCount).toList();
  }
}