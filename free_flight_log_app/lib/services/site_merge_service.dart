import '../data/models/site.dart';
import '../data/models/paragliding_site.dart';
import '../data/models/flight.dart';
import 'database_service.dart';
import 'logging_service.dart';

/// Service for handling site merging operations
class SiteMergeService {
  final DatabaseService _databaseService = DatabaseService.instance;

  /// Merge a local site into another local site
  Future<void> mergeLocalSites(Site sourceSite, Site targetSite) async {
    LoggingService.info('SiteMergeService: Merging local sites');
    
    try {
      // Get all flights associated with the source site
      final sourceFlights = await _databaseService.getFlightsBySite(sourceSite.id!);
      LoggingService.debug('SiteMergeService: Found ${sourceFlights.length} flights to reassign');
      
      // Reassign all flights to the target site
      for (final flight in sourceFlights) {
        final updatedFlight = flight.copyWith(launchSiteId: targetSite.id);
        await _databaseService.updateFlight(updatedFlight);
      }
      
      LoggingService.info('SiteMergeService: Reassigned ${sourceFlights.length} flights from ${sourceSite.name} to ${targetSite.name}');
      
      // Delete the source site
      await _databaseService.deleteSite(sourceSite.id!);
      LoggingService.info('SiteMergeService: Deleted source site ${sourceSite.name}');
      
    } catch (e) {
      LoggingService.error('SiteMergeService: Failed to merge sites', e);
      rethrow;
    }
  }

  /// Merge a local site into a Paragliding Earth API site
  Future<void> mergeIntoApiSite(Site sourceSite, ParaglidingSite apiSite) async {
    LoggingService.info('SiteMergeService: Merging local site into API site');
    
    try {
      // Get all flights associated with the source site
      final sourceFlights = await _databaseService.getFlightsBySite(sourceSite.id!);
      LoggingService.debug('SiteMergeService: Found ${sourceFlights.length} flights to reassign');
      
      // Create a new local site based on the API site
      final newSite = Site(
        name: apiSite.name,
        latitude: apiSite.latitude,
        longitude: apiSite.longitude,
        altitude: apiSite.altitude?.toDouble(),
        country: apiSite.country,
        customName: false, // Not custom since it's from API
      );
      
      final newSiteId = await _databaseService.insertSite(newSite);
      LoggingService.info('SiteMergeService: Created new site from API data with ID: $newSiteId');
      
      // Reassign all flights to the new site
      for (final flight in sourceFlights) {
        final updatedFlight = flight.copyWith(launchSiteId: newSiteId);
        await _databaseService.updateFlight(updatedFlight);
      }
      
      LoggingService.info('SiteMergeService: Reassigned ${sourceFlights.length} flights to new site');
      
      // Delete the source site
      await _databaseService.deleteSite(sourceSite.id!);
      LoggingService.info('SiteMergeService: Deleted source site ${sourceSite.name}');
      
    } catch (e) {
      LoggingService.error('SiteMergeService: Failed to merge into API site', e);
      rethrow;
    }
  }

  /// Create a new site and reassign nearby flights to it
  Future<int> createSiteAndReassignFlights({
    required String siteName,
    required double latitude,
    required double longitude,
    double? altitude,
    String? country,
    required List<Flight> nearbyFlights,
  }) async {
    LoggingService.info('SiteMergeService: Creating site and reassigning flights');
    
    try {
      // Create the new site
      final newSite = Site(
        name: siteName,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        country: country,
        customName: true, // User-created site
      );
      
      final newSiteId = await _databaseService.insertSite(newSite);
      LoggingService.info('SiteMergeService: Created new site "$siteName" with ID: $newSiteId');
      
      // Reassign nearby flights
      for (final flight in nearbyFlights) {
        final updatedFlight = flight.copyWith(launchSiteId: newSiteId);
        await _databaseService.updateFlight(updatedFlight);
      }
      
      LoggingService.info('SiteMergeService: Reassigned ${nearbyFlights.length} flights to new site');
      
      return newSiteId;
    } catch (e) {
      LoggingService.error('SiteMergeService: Failed to create site and reassign flights', e);
      rethrow;
    }
  }
}

extension FlightCopyWith on Flight {
  Flight copyWith({
    int? id,
    DateTime? date,
    String? launchTime,
    String? landingTime,
    int? duration,
    int? launchSiteId,
    double? launchLatitude,
    double? launchLongitude,
    double? launchAltitude,
    double? landingLatitude,
    double? landingLongitude,
    double? landingAltitude,
    String? landingDescription,
    double? maxAltitude,
    double? maxClimbRate,
    double? maxSinkRate,
    double? maxClimbRate5Sec,
    double? maxSinkRate5Sec,
    double? distance,
    double? straightDistance,
    int? wingId,
    String? notes,
    String? trackLogPath,
    String? originalFilename,
    String? source,
    String? timezone,
  }) {
    return Flight(
      id: id ?? this.id,
      date: date ?? this.date,
      launchTime: launchTime ?? this.launchTime,
      landingTime: landingTime ?? this.landingTime,
      duration: duration ?? this.duration,
      launchSiteId: launchSiteId ?? this.launchSiteId,
      launchLatitude: launchLatitude ?? this.launchLatitude,
      launchLongitude: launchLongitude ?? this.launchLongitude,
      launchAltitude: launchAltitude ?? this.launchAltitude,
      landingLatitude: landingLatitude ?? this.landingLatitude,
      landingLongitude: landingLongitude ?? this.landingLongitude,
      landingAltitude: landingAltitude ?? this.landingAltitude,
      landingDescription: landingDescription ?? this.landingDescription,
      maxAltitude: maxAltitude ?? this.maxAltitude,
      maxClimbRate: maxClimbRate ?? this.maxClimbRate,
      maxSinkRate: maxSinkRate ?? this.maxSinkRate,
      maxClimbRate5Sec: maxClimbRate5Sec ?? this.maxClimbRate5Sec,
      maxSinkRate5Sec: maxSinkRate5Sec ?? this.maxSinkRate5Sec,
      distance: distance ?? this.distance,
      straightDistance: straightDistance ?? this.straightDistance,
      wingId: wingId ?? this.wingId,
      notes: notes ?? this.notes,
      trackLogPath: trackLogPath ?? this.trackLogPath,
      originalFilename: originalFilename ?? this.originalFilename,
      source: source ?? this.source,
      timezone: timezone ?? this.timezone,
    );
  }
}