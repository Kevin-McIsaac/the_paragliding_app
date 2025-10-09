import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';
import '../../../data/models/site.dart';
import '../../../data/models/paragliding_site.dart';
import '../../../utils/site_marker_utils.dart';

/// Widget that provides consistent site marker rendering across all map widgets
/// Handles both draggable and non-draggable markers with proper styling
class SiteMarkerLayer extends StatelessWidget {
  final List<ParaglidingSite> sites;
  final bool enableDragging;
  final Function(ParaglidingSite)? onLocalSiteClick;
  final Function(ParaglidingSite)? onLocalSiteLongPress;
  final Function(ParaglidingSite)? onApiSiteClick;
  final Function(ParaglidingSite)? onApiSiteLongPress;
  final Function(ParaglidingSite, LatLng)? onSiteDragEnd;
  final Site? highlightedSite;
  final bool showFlightCounts;

  const SiteMarkerLayer({
    super.key,
    required this.sites,
    this.enableDragging = false,
    this.onLocalSiteClick,
    this.onLocalSiteLongPress,
    this.onApiSiteClick,
    this.onApiSiteLongPress,
    this.onSiteDragEnd,
    this.highlightedSite,
    this.showFlightCounts = true,
  });

  @override
  Widget build(BuildContext context) {
    if (enableDragging) {
      return DragMarkers(
        markers: _buildDragMarkers(),
      );
    } else {
      return MarkerLayer(
        markers: _buildStaticMarkers(),
        rotate: false,
      );
    }
  }

  /// Build draggable markers for sites
  List<DragMarker> _buildDragMarkers() {
    final markers = <DragMarker>[];

    for (final site in sites) {
      if (site.hasFlights) {
        // Local site with flights - draggable
        markers.add(_buildLocalSiteDragMarker(site));
      } else {
        // API site without flights - not draggable
        markers.add(_buildApiSiteDragMarker(site));
      }
    }

    return markers;
  }

  /// Build static markers for sites
  List<Marker> _buildStaticMarkers() {
    final markers = <Marker>[];

    for (final site in sites) {
      markers.add(
        Marker(
          point: LatLng(site.latitude, site.longitude),
          width: 140,
          height: 80,
          child: GestureDetector(
            onTap: () {
              if (site.hasFlights && onLocalSiteClick != null) {
                onLocalSiteClick!(site);
              } else if (!site.hasFlights && onApiSiteClick != null) {
                onApiSiteClick!(site);
              }
            },
            onLongPress: () {
              if (site.hasFlights && onLocalSiteLongPress != null) {
                onLocalSiteLongPress!(site);
              } else if (!site.hasFlights && onApiSiteLongPress != null) {
                onApiSiteLongPress!(site);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMarkerIcon(site),
                _buildMarkerLabel(site),
              ],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  /// Build draggable marker for local site
  DragMarker _buildLocalSiteDragMarker(ParaglidingSite site) {
    return DragMarker(
      point: LatLng(site.latitude, site.longitude),
      size: const Size(140, 80),
      offset: const Offset(0, -SiteMarkerUtils.siteMarkerSize / 2),
      dragOffset: const Offset(0, -40),
      onTap: (point) => onLocalSiteClick?.call(site),
      onLongPress: (point) => onLocalSiteLongPress?.call(site),
      onDragEnd: (details, point) => onSiteDragEnd?.call(site, point),
      builder: (ctx, point, isDragging) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SiteMarkerUtils.buildSiteMarkerIcon(
                color: SiteMarkerUtils.flownSiteColor,
              ),
              // TODO: Fix highlighting for local sites
              // For now, we can't properly highlight local sites since we don't have the original Site ID
              // This would need the ParaglidingSite to track the local site ID separately
            ],
          ),
          SiteMarkerUtils.buildSiteLabel(
            siteName: site.name,
            flightCount: showFlightCounts ? site.flightCount : null,
          ),
        ],
      ),
    );
  }

  /// Build non-draggable marker for API site
  DragMarker _buildApiSiteDragMarker(ParaglidingSite site) {
    return DragMarker(
      point: LatLng(site.latitude, site.longitude),
      size: const Size(140, 80),
      offset: const Offset(0, -SiteMarkerUtils.siteMarkerSize / 2),
      disableDrag: true,
      onTap: (point) => onApiSiteClick?.call(site),
      onLongPress: (point) => onApiSiteLongPress?.call(site),
      builder: (ctx, point, isDragging) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SiteMarkerUtils.buildSiteMarkerIcon(
            color: SiteMarkerUtils.newSiteColor,
          ),
          SiteMarkerUtils.buildSiteLabel(
            siteName: site.name,
            flightCount: null, // API sites don't have flight counts
          ),
        ],
      ),
    );
  }

  /// Build marker icon based on site type
  Widget _buildMarkerIcon(ParaglidingSite site) {
    return SiteMarkerUtils.buildSiteMarkerIcon(
      color: site.markerColor,
    );
  }

  /// Build marker label with site name and optional flight count
  Widget _buildMarkerLabel(ParaglidingSite site) {
    return SiteMarkerUtils.buildSiteLabel(
      siteName: site.name,
      flightCount: (showFlightCounts && site.hasFlights) ? site.flightCount : null,
    );
  }
}

/// Widget for rendering launch and landing markers
class FlightEndpointMarkers extends StatelessWidget {
  final double? launchLatitude;
  final double? launchLongitude;
  final double? landingLatitude;
  final double? landingLongitude;
  final String? landingDescription;
  final Function(LatLng)? onLaunchTap;
  final Function(LatLng)? onLandingTap;

  const FlightEndpointMarkers({
    super.key,
    this.launchLatitude,
    this.launchLongitude,
    this.landingLatitude,
    this.landingLongitude,
    this.landingDescription,
    this.onLaunchTap,
    this.onLandingTap,
  });

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];

    // Launch marker
    if (launchLatitude != null && launchLongitude != null) {
      final launchPoint = LatLng(launchLatitude!, launchLongitude!);
      markers.add(
        Marker(
          point: launchPoint,
          width: 32,
          height: 32,
          child: GestureDetector(
            onTap: () => onLaunchTap?.call(launchPoint),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SiteMarkerUtils.buildLaunchMarkerIcon(
                  color: SiteMarkerUtils.launchColor,
                  size: SiteMarkerUtils.launchMarkerSize,
                ),
                const Icon(
                  Icons.flight_takeoff,
                  color: Colors.white,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Landing marker
    if (landingLatitude != null && landingLongitude != null) {
      final landingPoint = LatLng(landingLatitude!, landingLongitude!);
      markers.add(
        Marker(
          point: landingPoint,
          width: 32,
          height: 32,
          child: GestureDetector(
            onTap: () => onLandingTap?.call(landingPoint),
            child: Tooltip(
              message: landingDescription ?? 'Landing Site',
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SiteMarkerUtils.buildLandingMarkerIcon(
                    color: SiteMarkerUtils.landingColor,
                    size: SiteMarkerUtils.launchMarkerSize,
                  ),
                  const Icon(
                    Icons.flight_land,
                    color: Colors.white,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MarkerLayer(
      markers: markers,
      rotate: false,
    );
  }
}

/// Widget for rendering multiple launch markers (e.g., in edit site screen)
class LaunchMarkersLayer extends StatelessWidget {
  final List<({double latitude, double longitude, DateTime date, double? altitude})> launches;
  final Function(LatLng, {double? altitude, String? siteName})? onLaunchLongPress;

  const LaunchMarkersLayer({
    super.key,
    required this.launches,
    this.onLaunchLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: launches.map((launch) {
        final point = LatLng(launch.latitude, launch.longitude);
        final dateStr = launch.date.toLocal().toString().split(' ')[0];

        return Marker(
          point: point,
          width: (SiteMarkerUtils.launchMarkerSize * 0.75) + 4,
          height: (SiteMarkerUtils.launchMarkerSize * 0.75) + 4,
          child: GestureDetector(
            onLongPress: () => onLaunchLongPress?.call(
              point,
              altitude: launch.altitude,
              siteName: 'Launch $dateStr',
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SiteMarkerUtils.buildLaunchMarkerIcon(
                  color: SiteMarkerUtils.launchColor,
                  size: SiteMarkerUtils.launchMarkerSize * 0.75,
                ),
                const Icon(
                  Icons.flight_takeoff,
                  color: Colors.white,
                  size: 10,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}