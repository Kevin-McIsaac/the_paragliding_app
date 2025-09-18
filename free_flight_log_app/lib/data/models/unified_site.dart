import 'package:flutter/material.dart';
import 'site.dart';
import 'paragliding_site.dart';
import '../../utils/site_marker_utils.dart';

/// Unified site model that represents both local (database) and API sites
/// in a single, consistent format for use across all map views.
class UnifiedSite {
  // Core fields
  final String name;
  final double latitude;
  final double longitude;
  final double? altitude;
  final String? country;
  final String? region;

  // Source tracking
  final bool isLocalSite;      // true = from DB, false = from API
  final int? localSiteId;       // Database ID if local
  final int? apiSiteId;         // API ID if from ParaglidingEarth

  // Flight data
  final int flightCount;        // 0 for API-only sites

  const UnifiedSite({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.country,
    this.region,
    required this.isLocalSite,
    this.localSiteId,
    this.apiSiteId,
    required this.flightCount,
  });

  // Computed properties
  bool get hasFlights => flightCount > 0;
  bool get isApiSite => apiSiteId != null;

  // Helper to get marker color
  Color get markerColor => hasFlights
    ? SiteMarkerUtils.flownSiteColor
    : SiteMarkerUtils.newSiteColor;

  // Create a unique key for deduplication
  String get locationKey => '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

  // Create from local Site
  factory UnifiedSite.fromLocalSite(Site site, {int flightCount = 0}) {
    return UnifiedSite(
      name: site.name,
      latitude: site.latitude,
      longitude: site.longitude,
      altitude: site.altitude,
      country: site.country,
      region: null,
      isLocalSite: true,
      localSiteId: site.id,
      apiSiteId: null,
      flightCount: flightCount,
    );
  }

  // Create from API ParaglidingSite
  factory UnifiedSite.fromApiSite(ParaglidingSite site, {int flightCount = 0}) {
    return UnifiedSite(
      name: site.name,
      latitude: site.latitude,
      longitude: site.longitude,
      altitude: site.altitude?.toDouble(),
      country: site.country,
      region: site.region,
      isLocalSite: false,
      localSiteId: null,
      apiSiteId: site.id,  // This is int? from ParaglidingSite
      flightCount: flightCount,
    );
  }

  // Create merged (local site enriched with API data)
  factory UnifiedSite.merged({
    required Site localSite,
    required ParaglidingSite apiSite,
    required int flightCount,
  }) {
    return UnifiedSite(
      name: localSite.name, // Prefer local name
      latitude: localSite.latitude,
      longitude: localSite.longitude,
      altitude: localSite.altitude ?? apiSite.altitude?.toDouble(),
      country: localSite.country ?? apiSite.country,
      region: apiSite.region,
      isLocalSite: true,
      localSiteId: localSite.id,
      apiSiteId: apiSite.id,
      flightCount: flightCount,
    );
  }

  // Convert back to Site for database operations
  Site toLocalSite() {
    return Site(
      id: localSiteId,
      name: name,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      country: country,
    );
  }

  // Convert to ParaglidingSite for API operations
  ParaglidingSite toApiSite() {
    return ParaglidingSite(
      id: apiSiteId,
      name: name,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude?.toInt(),
      country: country,
      region: region,
      siteType: 'launch',  // Required field, default to launch
    );
  }

  // Convert to ParaglidingSite for display (backward compatibility)
  ParaglidingSite toParaglidingSite() {
    return ParaglidingSite(
      id: apiSiteId,
      name: name,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude?.toInt(),
      country: country,
      region: region,
      siteType: 'launch', // Required field, default to launch
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnifiedSite &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;

  @override
  String toString() => 'UnifiedSite(name: $name, lat: $latitude, lon: $longitude, '
      'isLocal: $isLocalSite, flights: $flightCount)';
}