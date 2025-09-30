import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../services/logging_service.dart';
import '../../utils/map_constants.dart';
import '../../utils/site_marker_utils.dart';
import 'common/base_map_widget.dart';
import 'common/map_overlays.dart';
import 'common/user_location_marker.dart';

/// Clean implementation of nearby sites map using BaseMapWidget architecture
/// Replaces the monolithic 1400+ line nearby_sites_map_widget.dart
class NearbySitesMap extends BaseMapWidget {
  final LatLng? userLocation;
  final List<ParaglidingSite> sites;
  final bool airspaceEnabled;
  final double maxAltitudeFt;
  final Function(ParaglidingSite)? onSiteSelected;
  final VoidCallback? onLocationRequest;
  final bool showUserLocation;
  final bool isLocationLoading;
  final Function(LatLngBounds)? onBoundsChanged;
  final Map<String, WindData> siteWindData;
  final double maxWindSpeed;
  final double maxWindGusts;

  const NearbySitesMap({
    super.key,
    this.userLocation,
    this.sites = const [],
    this.airspaceEnabled = false,
    this.maxAltitudeFt = 10000.0,
    this.onSiteSelected,
    this.onLocationRequest,
    this.showUserLocation = true,
    this.isLocationLoading = false,
    this.onBoundsChanged,
    this.siteWindData = const {},
    this.maxWindSpeed = 25.0,
    this.maxWindGusts = 30.0,
    super.height = 400,
    super.initialCenter,
    super.initialZoom = 10.0,
    super.mapController,
  });

  @override
  State<NearbySitesMap> createState() => _NearbySitesMapState();
}

class _NearbySitesMapState extends BaseMapState<NearbySitesMap> {
  @override
  String get mapProviderKey => 'nearby_sites_map_provider';

  @override
  String get legendExpandedKey => 'nearby_sites_legend_expanded';

  @override
  String get mapContext => 'nearby_sites';

  @override
  int get siteLimit => MapConstants.defaultSiteLimit; // Standard site limit

  @override
  bool get enableAirspace => widget.airspaceEnabled;

  @override
  double get maxAltitudeFt => widget.maxAltitudeFt;

  @override
  bool get loadSitesOnBoundsChange => false; // We use sites from parent

  @override
  void initState() {
    super.initState();

    // Center on user location if available
    if (widget.userLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          mapController.move(widget.userLocation!, 11.0);
        }
      });
    }
  }

  @override
  void onMapReady() {
    super.onMapReady();
    // Notify parent of initial bounds
    if (widget.onBoundsChanged != null) {
      final bounds = mapController.camera.visibleBounds;
      widget.onBoundsChanged!(bounds);
    }
  }

  @override
  void handleMapEvent(MapEvent event) {
    super.handleMapEvent(event);

    // Notify parent when bounds change
    if (widget.onBoundsChanged != null &&
        (event is MapEventMoveEnd ||
         event is MapEventFlingAnimationEnd ||
         event is MapEventDoubleTapZoomEnd ||
         event is MapEventScrollWheelZoom)) {
      final bounds = mapController.camera.visibleBounds;
      widget.onBoundsChanged!(bounds);
    }
  }

  @override
  void didUpdateWidget(NearbySitesMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update airspace when enabled state changes
    if (oldWidget.airspaceEnabled != widget.airspaceEnabled) {
      if (widget.airspaceEnabled) {
        loadAirspaceLayers(mapController.camera.visibleBounds);
      } else {
        setState(() {
          // Clear airspace layers when disabled
        });
      }
    }

    // Re-center on user location if it changes significantly
    if (widget.userLocation != null && oldWidget.userLocation != widget.userLocation) {
      final distance = oldWidget.userLocation != null
          ? _calculateDistance(oldWidget.userLocation!, widget.userLocation!)
          : double.infinity;

      if (distance > 100) {
        // Move if location changed by more than 100m
        mapController.move(widget.userLocation!, mapController.camera.zoom);
      }
    }
  }

  @override
  void onSitesLoaded(List<ParaglidingSite> sites) {
    super.onSitesLoaded(sites);

    // Log site loading for nearby sites
    LoggingService.structured('NEARBY_SITES_LOADED', {
      'count': sites.length,
      'has_user_location': widget.userLocation != null,
    });
  }

  @override
  void onMapTap(TapPosition tapPosition, LatLng point) {
    LoggingService.info('NearbySitesMap: onMapTap called at ${point.latitude}, ${point.longitude}');

    // Call parent to handle airspace interaction
    super.onMapTap(tapPosition, point);
  }

  void _onSiteMarkerTap(ParaglidingSite site) {
    // Don't show the map info card - just call parent's callback for PGE dialog
    widget.onSiteSelected?.call(site);
  }

  /// Determine if a site is flyable based on wind conditions
  bool _isSiteFlyable(ParaglidingSite site) {
    final windKey = '${site.latitude}_${site.longitude}';
    final wind = widget.siteWindData[windKey];

    if (wind == null) {
      return false; // No wind data available
    }

    if (site.windDirections.isEmpty) {
      return false; // Site has no defined wind directions
    }

    final isFlyable = wind.isFlyable(
      site.windDirections,
      widget.maxWindSpeed,
      widget.maxWindGusts,
    );

    // Log flyability decision with structured data
    if (isFlyable) {
      LoggingService.structured('SITE_FLYABLE', {
        'site': site.name,
        'wind_direction': wind.compassDirection,
        'wind_speed': wind.speedKmh.toStringAsFixed(1),
        'site_directions': site.windDirections.join(','),
      });
    }

    return isFlyable;
  }

  /// Get the marker color for a site based on flyability
  Color _getSiteMarkerColor(ParaglidingSite site) {
    // Check if site is flyable with current wind conditions
    final isFlyable = _isSiteFlyable(site);

    if (isFlyable) {
      return SiteMarkerUtils.flyableSiteColor; // Flyable with current wind!
    }

    // Default colors based on flight history
    return site.hasFlights
        ? SiteMarkerUtils.flownSiteColor
        : SiteMarkerUtils.newSiteColor;
  }

  /// Build markers for clustering with site data preserved
  List<Marker> _buildClusterableMarkers() {
    return widget.sites.map((site) {
      return Marker(
        point: LatLng(site.latitude, site.longitude),
        width: 140,
        height: 80,
        // Store site data in key for cluster color detection
        key: ValueKey(site),
        child: GestureDetector(
          onTap: () => _onSiteMarkerTap(site),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SiteMarkerUtils.buildSiteMarkerIcon(
                color: _getSiteMarkerColor(site),
              ),
              SiteMarkerUtils.buildSiteLabel(
                siteName: site.name,
                flightCount: site.hasFlights ? site.flightCount : null,
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  /// Build cluster marker showing count with color based on content
  Widget _buildClusterMarker(List<Marker> markers) {
    final count = markers.length;
    final displayText = count > 999 ? '999+' : count.toString();

    // Check if any sites are flyable
    final hasFlyableSites = markers.any((marker) {
      if (marker.key is ValueKey<ParaglidingSite>) {
        final site = (marker.key as ValueKey<ParaglidingSite>).value;
        return _isSiteFlyable(site);
      }
      return false;
    });

    // Check if any markers are flown sites (green)
    final hasFlownSites = markers.any((marker) {
      if (marker.key is ValueKey<ParaglidingSite>) {
        final site = (marker.key as ValueKey<ParaglidingSite>).value;
        return site.hasFlights;
      }
      return false;
    });

    // Use light green for flyable sites, purple for flown sites, blue for new sites
    final clusterColor = hasFlyableSites
        ? SiteMarkerUtils.flyableSiteColor
        : (hasFlownSites ? SiteMarkerUtils.flownSiteColor : SiteMarkerUtils.newSiteColor);

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: clusterColor.withValues(alpha: 0.9),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          displayText,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: count > 99 ? 10 : 12,
          ),
        ),
      ),
    );
  }

  @override
  List<Widget> buildAdditionalLayers() {
    final layers = <Widget>[];

    // Site markers with clustering
    layers.add(
      MarkerClusterLayerWidget(
        options: MarkerClusterLayerOptions(
          maxClusterRadius: 50,
          size: const Size(40, 40),
          disableClusteringAtZoom: 14,
          padding: const EdgeInsets.all(50),
          spiderfyCluster: true,
          zoomToBoundsOnClick: true,
          markers: _buildClusterableMarkers(),
          builder: (context, markers) => _buildClusterMarker(markers),
        ),
      ),
    );

    // User location marker
    if (widget.showUserLocation && widget.userLocation != null) {
      layers.add(
        UserLocationMarker(
          location: widget.userLocation!,
          showAccuracyCircle: true,
          animate: true,
        ),
      );
    }

    return layers;
  }

  @override
  List<Widget> buildAdditionalLegendItems() {
    final items = <Widget>[];

    if (widget.showUserLocation) {
      items.add(const SizedBox(height: 4));
      items.add(const UserLocationLegendItem());
    }

    return items;
  }

  List<Widget> _buildMapOverlays() {
    final overlays = <Widget>[];

    // Always show location button for refreshing location
    if (widget.onLocationRequest != null) {
      overlays.add(
        MapOverlayPositioned(
          position: MapOverlayPosition.bottomRight,
          child: LocationRequestOverlay(
            onLocationRequest: widget.onLocationRequest!,
            isLoading: widget.isLocationLoading,
          ),
        ),
      );
    }

    // Don't show map info card - parent handles site selection with PGE dialog

    return overlays;
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    // Simple distance calculation for nearby checking
    final latDiff = (point2.latitude - point1.latitude).abs();
    final lngDiff = (point2.longitude - point1.longitude).abs();
    return (latDiff * latDiff + lngDiff * lngDiff) * 111000; // Rough meters
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        buildMap(), // Use buildMap() which includes airspace popup
        ..._buildMapOverlays(),
      ],
    );
  }
}