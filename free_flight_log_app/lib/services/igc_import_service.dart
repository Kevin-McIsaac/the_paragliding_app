import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../data/models/flight.dart';
import '../data/models/site.dart';
import '../data/models/wing.dart';
import '../data/models/igc_file.dart';
import '../data/repositories/flight_repository.dart';
import '../data/repositories/site_repository.dart';
import '../data/repositories/wing_repository.dart';
import 'igc_parser.dart';

/// Service for importing IGC files into the flight log
class IgcImportService {
  final FlightRepository _flightRepository = FlightRepository();
  final SiteRepository _siteRepository = SiteRepository();
  final WingRepository _wingRepository = WingRepository();
  final IgcParser _parser = IgcParser();

  /// Import an IGC file and create a flight record
  Future<Flight> importIgcFile(String filePath) async {
    // Parse IGC file
    final igcData = await _parser.parseFile(filePath);
    
    if (igcData.trackPoints.isEmpty) {
      throw Exception('No track points found in IGC file');
    }

    // Calculate flight statistics
    final groundTrackDistance = igcData.calculateGroundTrackDistance();
    final straightDistance = igcData.calculateLaunchToLandingDistance();
    final climbRates = igcData.calculateClimbRates();
    final climbRates15Sec = igcData.calculate15SecondMaxClimbRates();
    
    // Get or create launch site
    Site? launchSite;
    if (igcData.launchSite != null) {
      final launchPoint = igcData.launchSite!;
      launchSite = await _siteRepository.findOrCreateSite(
        latitude: launchPoint.latitude,
        longitude: launchPoint.longitude,
        altitude: launchPoint.gpsAltitude.toDouble(),
        name: 'Launch ${_formatCoordinate(launchPoint.latitude, launchPoint.longitude)}',
      );
    }

    // Get or create landing site
    Site? landingSite;
    if (igcData.landingSite != null) {
      final landingPoint = igcData.landingSite!;
      landingSite = await _siteRepository.findOrCreateSite(
        latitude: landingPoint.latitude,
        longitude: landingPoint.longitude,
        altitude: landingPoint.gpsAltitude.toDouble(),
        name: 'Landing ${_formatCoordinate(landingPoint.latitude, landingPoint.longitude)}',
      );
    }

    // Get or create wing from glider information
    Wing? wing;
    print('=== DEBUG: IGC Import ===');
    print('gliderType: "${igcData.gliderType}"');
    print('gliderID: "${igcData.gliderID}"');
    if (igcData.gliderType.isNotEmpty || igcData.gliderID.isNotEmpty) {
      wing = await _findOrCreateWing(
        gliderType: igcData.gliderType,
        gliderID: igcData.gliderID,
      );
    }

    // Copy IGC file to app storage
    final trackLogPath = await _saveIgcFile(filePath);

    // Create flight record
    final flight = Flight(
      date: igcData.date,
      launchTime: _formatTime(igcData.launchTime),
      landingTime: _formatTime(igcData.landingTime),
      duration: igcData.duration,
      launchSiteId: launchSite?.id,
      landingSiteId: landingSite?.id,
      wingId: wing?.id,
      maxAltitude: igcData.maxAltitude,
      maxClimbRate: climbRates['maxClimb'],
      maxSinkRate: climbRates['maxSink'],
      maxClimbRate5Sec: climbRates15Sec['maxClimb15Sec'],
      maxSinkRate5Sec: climbRates15Sec['maxSink15Sec'],
      distance: groundTrackDistance,
      straightDistance: straightDistance,
      trackLogPath: trackLogPath,
      source: 'igc',
      notes: 'Imported from IGC file${igcData.pilot.isNotEmpty ? '\nPilot: ${igcData.pilot}' : ''}${igcData.gliderType.isNotEmpty ? '\nGlider: ${igcData.gliderType}' : ''}',
    );

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
      landingSiteId: flight.landingSiteId,
      wingId: flight.wingId,
      maxAltitude: flight.maxAltitude,
      maxClimbRate: flight.maxClimbRate,
      maxSinkRate: flight.maxSinkRate,
      maxClimbRate5Sec: flight.maxClimbRate5Sec,
      maxSinkRate5Sec: flight.maxSinkRate5Sec,
      distance: flight.distance,
      notes: flight.notes,
      trackLogPath: flight.trackLogPath,
      source: flight.source,
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

  /// Format coordinate for display
  String _formatCoordinate(double lat, double lon) {
    final latDir = lat >= 0 ? 'N' : 'S';
    final lonDir = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(3)}°$latDir ${lon.abs().toStringAsFixed(3)}°$lonDir';
  }

  /// Get track points from saved IGC file
  Future<List<IgcPoint>> getTrackPoints(String trackLogPath) async {
    try {
      final igcData = await _parser.parseFile(trackLogPath);
      return igcData.trackPoints;
    } catch (e) {
      print('Error reading track points: $e');
      return [];
    }
  }

  /// Get full IGC file data from saved file
  Future<IgcFile> getIgcFile(String trackLogPath) async {
    return await _parser.parseFile(trackLogPath);
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

    print('Debug: Creating wing with name="$wingName", manufacturer="$manufacturer", model="$model"');

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