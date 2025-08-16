import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../data/models/flight.dart';
import '../data/models/site.dart';
import '../data/models/wing.dart';
import '../data/models/igc_file.dart';
import '../data/models/import_result.dart';
import '../data/repositories/flight_repository.dart';
import '../data/repositories/site_repository.dart';
import '../data/services/flight_query_service.dart';
import 'logging_service.dart';
import '../data/repositories/wing_repository.dart';
import 'igc_parser.dart';
import 'site_matching_service.dart';

/// Service for importing IGC files into the flight log
class IgcImportService {
  // Singleton pattern
  static IgcImportService? _instance;
  static IgcImportService get instance {
    _instance ??= IgcImportService._internal();
    return _instance!;
  }
  
  IgcImportService._internal();
  
  final FlightRepository _flightRepository = FlightRepository.instance;
  final SiteRepository _siteRepository = SiteRepository.instance;
  final WingRepository _wingRepository = WingRepository.instance;
  final FlightQueryService _queryService = FlightQueryService.instance;
  final IgcParser parser = IgcParser();

  /// Phase 1: Quick check for duplicate by filename (no parsing needed)
  Future<Flight?> checkForDuplicateByFilename(String filename) async {
    try {
      return await _queryService.findFlightByFilename(filename);
    } catch (e) {
      LoggingService.error('IgcImportService: Error checking filename duplicate', e);
      return null;
    }
  }

  /// Phase 2: Check if a flight with the same date and time already exists
  Future<Flight?> checkForDuplicate(String filePath) async {
    try {
      // Parse IGC file to get flight details
      final igcData = await parser.parseFileInIsolate(filePath);
      
      if (igcData.trackPoints.isEmpty) {
        return null;
      }

      // Format launch time to match database format
      final launchTime = _formatTime(igcData.launchTime);
      
      // Check for existing flight with same date and launch time
      return await _queryService.findFlightByDateTime(igcData.date, launchTime);
    } catch (e) {
      // If we can't parse the file, we can't check for duplicates
      return null;
    }
  }

  /// Import an IGC file with duplicate handling
  /// Returns ImportResult indicating what action was taken
  Future<ImportResult> importIgcFileWithDuplicateHandling(
    String filePath, {
    bool replace = false,
  }) async {
    final fileName = path.basename(filePath);
    
    try {
      // Parse IGC file
      final igcData = await parser.parseFileInIsolate(filePath);
      
      if (igcData.trackPoints.isEmpty) {
        return ImportResult.failed(
          fileName: fileName,
          errorMessage: 'No track points found in IGC file',
        );
      }

      // Format launch time to match database format
      final launchTime = _formatTime(igcData.launchTime);
      
      // Check for existing flight
      final existingFlight = await _queryService.findFlightByDateTime(
        igcData.date, 
        launchTime,
      );

      if (existingFlight != null && !replace) {
        // Duplicate found and user chose to skip
        return ImportResult.skipped(
          fileName: fileName,
          flightDate: igcData.date,
          flightTime: launchTime,
          duration: igcData.duration,
        );
      }

      // Create flight record (either new or replacement)
      final flight = await _createFlightFromIgcData(igcData, filePath);
      
      if (existingFlight != null && replace) {
        // Replace existing flight
        final updatedFlight = Flight(
          id: existingFlight.id,
          date: flight.date,
          launchTime: flight.launchTime,
          landingTime: flight.landingTime,
          duration: flight.duration,
          launchSiteId: flight.launchSiteId,
          landingLatitude: flight.landingLatitude,
          landingLongitude: flight.landingLongitude,
          landingAltitude: flight.landingAltitude,
          landingDescription: flight.landingDescription,
          wingId: flight.wingId,
          maxAltitude: flight.maxAltitude,
          maxClimbRate: flight.maxClimbRate,
          maxSinkRate: flight.maxSinkRate,
          maxClimbRate5Sec: flight.maxClimbRate5Sec,
          maxSinkRate5Sec: flight.maxSinkRate5Sec,
          distance: flight.distance,
          straightDistance: flight.straightDistance,
          trackLogPath: flight.trackLogPath,
          originalFilename: flight.originalFilename,
          source: flight.source,
          timezone: flight.timezone,
          notes: flight.notes,
          createdAt: existingFlight.createdAt, // Keep original creation time
        );
        
        await _flightRepository.updateFlight(updatedFlight);
        
        // Refresh site matching service after successful replacement
        // This updates the personalized fallback with potentially new sites
        final siteMatchingService = SiteMatchingService.instance;
        await siteMatchingService.refreshAfterFlightImport();
        
        return ImportResult.replaced(
          fileName: fileName,
          flightId: existingFlight.id,
          flightDate: igcData.date,
          flightTime: launchTime,
          duration: igcData.duration,
        );
      } else {
        // Import as new flight
        final savedFlightId = await _flightRepository.insertFlight(flight);
        
        // Refresh site matching service after successful import
        // This updates the personalized fallback with new sites
        final siteMatchingService = SiteMatchingService.instance;
        await siteMatchingService.refreshAfterFlightImport();

        return ImportResult.imported(
          fileName: fileName,
          flightId: savedFlightId,
          flightDate: igcData.date,
          flightTime: launchTime,
          duration: igcData.duration,
        );
      }
    } catch (e) {
      return ImportResult.failed(
        fileName: fileName,
        errorMessage: e.toString(),
      );
    }
  }

  /// Create a flight record from IGC data (shared between import methods)
  Future<Flight> _createFlightFromIgcData(IgcFile igcData, String filePath) async {
    // Calculate flight statistics
    final groundTrackDistance = igcData.calculateGroundTrackDistance();
    final straightDistance = igcData.calculateLaunchToLandingDistance();
    final climbRates = igcData.calculateClimbRates();
    final climbRates15Sec = igcData.calculate15SecondMaxClimbRates();
    
    // Get or create launch site with paragliding site matching
    Site? launchSite;
    if (igcData.launchSite != null) {
      final launchPoint = igcData.launchSite!;
      
      // Try to match with a paragliding site to get name and location info
      final siteMatchingService = SiteMatchingService.instance;
      if (!siteMatchingService.isReady) {
        await siteMatchingService.initialize();
      }
      
      final matchedSite = await siteMatchingService.findNearestSite(
        launchPoint.latitude,
        launchPoint.longitude,
        maxDistance: 500, // 500m for launch sites
        preferredType: 'launch',
      );
      
      String siteName;
      String? country;
      
      if (matchedSite != null) {
        siteName = matchedSite.name;
        country = matchedSite.country;
        
        // Debug output to see what the API returned
        LoggingService.info('IgcImportService: API found site "$siteName" for coordinates ${launchPoint.latitude.toStringAsFixed(4)}, ${launchPoint.longitude.toStringAsFixed(4)}');
        LoggingService.debug('IgcImportService: Site details - Country: "${country ?? 'null'}"');
        LoggingService.debug('IgcImportService: Full site object: $matchedSite');
      } else {
        siteName = 'Unknown';
        country = null;
        LoggingService.info('IgcImportService: No API site found for coordinates ${launchPoint.latitude.toStringAsFixed(4)}, ${launchPoint.longitude.toStringAsFixed(4)}');
      }
      
      launchSite = await _siteRepository.findOrCreateSite(
        latitude: launchPoint.latitude,
        longitude: launchPoint.longitude,
        altitude: launchPoint.gpsAltitude.toDouble(),
        name: siteName,
        country: country,
      );
      
      // Debug output to see what was actually stored
      LoggingService.info('IgcImportService: Created/found site in database with ID ${launchSite.id}, name "${launchSite.name}", country "${launchSite.country ?? 'null'}"');
    }

    // Get landing coordinates (no longer create landing sites)
    double? landingLatitude;
    double? landingLongitude;
    double? landingAltitude;
    String? landingDescription;
    
    if (igcData.landingSite != null) {
      final landingPoint = igcData.landingSite!;
      landingLatitude = landingPoint.latitude;
      landingLongitude = landingPoint.longitude;
      landingAltitude = landingPoint.gpsAltitude.toDouble();
      
      // Don't lookup site names for landings - they can be anywhere
      // Leave description null so users can add their own meaningful descriptions
      landingDescription = null;
    }

    // Get or create wing from glider information
    Wing? wing;
    if (igcData.gliderType.isNotEmpty || igcData.gliderID.isNotEmpty) {
      wing = await _findOrCreateWing(
        gliderType: igcData.gliderType,
        gliderID: igcData.gliderID,
      );
    }

    // Copy IGC file to app storage
    final trackLogPath = await _saveIgcFile(filePath);
    
    // Get original filename
    final originalFilename = path.basename(filePath);

    // Create flight record
    return Flight(
      date: igcData.date,
      launchTime: _formatTime(igcData.launchTime),
      landingTime: _formatTime(igcData.landingTime),
      duration: igcData.duration,
      launchSiteId: launchSite?.id,
      landingLatitude: landingLatitude,
      landingLongitude: landingLongitude,
      landingAltitude: landingAltitude,
      landingDescription: landingDescription,
      wingId: wing?.id,
      maxAltitude: igcData.maxAltitude,
      maxClimbRate: climbRates['maxClimb'],
      maxSinkRate: climbRates['maxSink'],
      maxClimbRate5Sec: climbRates15Sec['maxClimb15Sec'],
      maxSinkRate5Sec: climbRates15Sec['maxSink15Sec'],
      distance: groundTrackDistance,
      straightDistance: straightDistance,
      trackLogPath: trackLogPath,
      originalFilename: originalFilename,
      source: 'igc',
      timezone: igcData.timezone,
      notes: 'Imported from IGC file: ${originalFilename}${igcData.pilot.isNotEmpty ? '\nPilot: ${igcData.pilot}' : ''}${igcData.gliderType.isNotEmpty ? '\nGlider: ${igcData.gliderType}' : ''}',
    );
  }

  /// Import an IGC file and create a flight record (legacy method)
  Future<Flight> importIgcFile(String filePath) async {
    // Parse IGC file
    final igcData = await parser.parseFileInIsolate(filePath);
    
    if (igcData.trackPoints.isEmpty) {
      throw Exception('No track points found in IGC file');
    }

    // Create flight record
    final flight = await _createFlightFromIgcData(igcData, filePath);

    // Save to database
    final savedFlightId = await _flightRepository.insertFlight(flight);
    
    // Return the flight with the new ID
    return Flight(
      id: savedFlightId,
      date: flight.date,
      launchTime: flight.launchTime,
      landingTime: flight.landingTime,
      duration: flight.duration,
      launchSiteId: flight.launchSiteId,
      landingLatitude: flight.landingLatitude,
      landingLongitude: flight.landingLongitude,
      landingAltitude: flight.landingAltitude,
      landingDescription: flight.landingDescription,
      wingId: flight.wingId,
      maxAltitude: flight.maxAltitude,
      maxClimbRate: flight.maxClimbRate,
      maxSinkRate: flight.maxSinkRate,
      maxClimbRate5Sec: flight.maxClimbRate5Sec,
      maxSinkRate5Sec: flight.maxSinkRate5Sec,
      distance: flight.distance,
      straightDistance: flight.straightDistance,
      notes: flight.notes,
      trackLogPath: flight.trackLogPath,
      originalFilename: flight.originalFilename,
      source: flight.source,
      timezone: flight.timezone,
    );
  }

  /// Save IGC file to app storage
  Future<String> _saveIgcFile(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final igcDir = Directory(path.join(appDir.path, 'igc_tracks'));
    
    // Create directory if it doesn't exist
    if (!await igcDir.exists()) {
      await igcDir.create(recursive: true);
    }

    // Generate unique filename based on timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'track_$timestamp.igc';
    final destinationPath = path.join(igcDir.path, fileName);

    // Copy file
    final sourceFile = File(sourcePath);
    await sourceFile.copy(destinationPath);

    return destinationPath;
  }

  /// Format time for display
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Get site name using paragliding site matching or fallback to coordinates
  Future<String> _getSiteName(
    double latitude,
    double longitude, {
    String? siteType,
  }) async {
    // Ensure site matching service is initialized
    final siteMatchingService = SiteMatchingService.instance;
    if (!siteMatchingService.isReady) {
      await siteMatchingService.initialize();
    }

    // Try to get a paragliding site name (without prefix to avoid redundant "Launch"/"Landing")
    return await siteMatchingService.getSiteNameSuggestion(
      latitude,
      longitude,
      prefix: '', // Remove prefix to avoid "Launch 47.123°N" - coordinates already indicate position
      siteType: siteType,
    );
  }

  /// Format coordinate for display (fallback method)
  String _formatCoordinate(double lat, double lon) {
    final latDir = lat >= 0 ? 'N' : 'S';
    final lonDir = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(3)}°$latDir ${lon.abs().toStringAsFixed(3)}°$lonDir';
  }

  /// Get track points from saved IGC file
  Future<List<IgcPoint>> getTrackPoints(String trackLogPath) async {
    try {
      // Use isolate parsing for better performance
      final igcData = await parser.parseFileInIsolate(trackLogPath);
      return igcData.trackPoints;
    } catch (e) {
      LoggingService.error('IgcImportService: Error reading track points', e);
      return [];
    }
  }
  
  /// Get track points with timezone information from saved IGC file
  Future<({List<IgcPoint> points, String? timezone})> getTrackPointsWithTimezone(String trackLogPath) async {
    try {
      // Use isolate parsing for better performance
      final igcData = await parser.parseFileInIsolate(trackLogPath);
      return (points: igcData.trackPoints, timezone: igcData.timezone);
    } catch (e) {
      LoggingService.error('IgcImportService: Error reading track points with timezone', e);
      return (points: <IgcPoint>[], timezone: null);
    }
  }

  /// Get full IGC file data from saved file
  Future<IgcFile> getIgcFile(String trackLogPath) async {
    // Use isolate parsing for better performance
    return await parser.parseFileInIsolate(trackLogPath);
  }

  /// Find existing wing or create new one from IGC glider information
  Future<Wing?> _findOrCreateWing({
    required String gliderType,
    required String gliderID,
  }) async {
    
    // If no glider information, return null
    if (gliderType.isEmpty && gliderID.isEmpty) {
      return null;
    }

    // Get all existing wings
    final existingWings = await _wingRepository.getAllWings();
    
    // Try to find existing wing by matching glider type or ID
    for (final wing in existingWings) {
      // Check if wing name, manufacturer, or model matches glider info
      final wingInfo = '${wing.manufacturer ?? ''} ${wing.model ?? ''}'.trim();
      final wingName = wing.name.toLowerCase();
      final gliderTypeLower = gliderType.toLowerCase();
      final gliderIDLower = gliderID.toLowerCase();
      
      if (wingName.contains(gliderTypeLower) ||
          wingInfo.toLowerCase().contains(gliderTypeLower) ||
          (gliderID.isNotEmpty && wingName.contains(gliderIDLower))) {
        return wing;
      }
    }

    // No existing wing found, create new one
    String wingName = gliderType.isNotEmpty ? gliderType : gliderID;
    String? manufacturer;
    String? model;
    
    // Try to parse manufacturer and model from glider type
    if (gliderType.isNotEmpty) {
      final parts = gliderType.trim().split(' ');
      if (parts.length >= 2) {
        manufacturer = parts[0];
        model = parts.sublist(1).join(' ');
      } else {
        manufacturer = parts[0];
      }
    }

    final newWing = Wing(
      name: wingName,
      manufacturer: manufacturer,
      model: model,
      active: true,
      notes: 'Automatically created from IGC import',
    );

    LoggingService.debug('IgcImportService: Creating wing with name="$wingName", manufacturer="$manufacturer", model="$model"');

    final wingId = await _wingRepository.insertWing(newWing);
    
    return Wing(
      id: wingId,
      name: newWing.name,
      manufacturer: newWing.manufacturer,
      model: newWing.model,
      size: newWing.size,
      color: newWing.color,
      purchaseDate: newWing.purchaseDate,
      active: newWing.active,
      notes: newWing.notes,
      createdAt: newWing.createdAt,
    );
  }
}