import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/flyability_status.dart';
import '../../data/models/weather_station.dart';
import '../../services/logging_service.dart';
import '../../utils/map_calculation_utils.dart';
import '../../utils/map_constants.dart';
import '../../utils/site_marker_utils.dart';
import '../../utils/site_utils.dart';
import '../models/site_marker_presentation.dart';
import 'common/base_map_widget.dart';
import 'common/map_overlays.dart';
import 'common/user_location_marker.dart';
import 'weather_station_marker.dart';

/// Clean implementation of nearby sites map using BaseMapWidget architecture
/// Replaces the monolithic 1400+ line nearby_sites_map_widget.dart
class NearbySitesMap extends BaseMapWidget {
  final LatLng? userLocation;
  final List<ParaglidingSite> sites;
  final bool airspaceEnabled;
  final double maxAltitudeFt;
  final bool airspaceClippingEnabled;
  final Function(ParaglidingSite)? onSiteSelected;
  final VoidCallback? onLocationRequest;
  final bool showUserLocation;
  final bool isLocationLoading;
  final Function(LatLngBounds)? onBoundsChanged;
  final VoidCallback? onSitesDataVersionChanged; // Called when sites data changes (bypasses bounds check)
  final Map<String, WindData> siteWindData;
  final Map<String, FlyabilityStatus> siteFlyabilityStatus;
  final double maxWindSpeed;
  final double cautionWindSpeed;
  final DateTime selectedDateTime;
  final bool forecastEnabled;
  final List<WeatherStation> weatherStations;
  final Map<String, WindData> stationWindData;
  final bool weatherStationsEnabled;
  final int airspaceDataVersion; // Increment to trigger airspace reload
  final int sitesDataVersion; // Increment to trigger sites reload

  const NearbySitesMap({
    super.key,
    this.userLocation,
    this.sites = const [],
    this.airspaceEnabled = false,
    this.maxAltitudeFt = 10000.0,
    this.airspaceClippingEnabled = true,
    this.onSiteSelected,
    this.onLocationRequest,
    this.showUserLocation = true,
    this.isLocationLoading = false,
    this.onBoundsChanged,
    this.onSitesDataVersionChanged,
    this.siteWindData = const {},
    this.siteFlyabilityStatus = const {},
    this.maxWindSpeed = 25.0,
    this.cautionWindSpeed = 20.0,
    required this.selectedDateTime,
    this.forecastEnabled = true,
    this.weatherStations = const [],
    this.stationWindData = const {},
    this.weatherStationsEnabled = true,
    this.airspaceDataVersion = 0,
    this.sitesDataVersion = 0,
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

    // Notify parent when bounds change - include MapEventMove for cluster zoom animations
    if (widget.onBoundsChanged != null &&
        (event is MapEventMoveEnd ||
         event is MapEventMove ||
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
    // Reload airspace when settings change (affects clipping and filtering)
    else if (widget.airspaceEnabled &&
             (oldWidget.maxAltitudeFt != widget.maxAltitudeFt ||
              oldWidget.airspaceClippingEnabled != widget.airspaceClippingEnabled)) {
      loadAirspaceLayers(mapController.camera.visibleBounds);
    }
    // Reload airspace when data version changes (new airspace data downloaded)
    else if (widget.airspaceEnabled &&
             oldWidget.airspaceDataVersion != widget.airspaceDataVersion) {
      LoggingService.info('Airspace data version changed (${oldWidget.airspaceDataVersion} -> ${widget.airspaceDataVersion}), scheduling airspace reload');
      // Schedule reload after build completes to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          loadAirspaceLayers(mapController.camera.visibleBounds);
        }
      });
    }

    // Reload sites when data version changes (PGE sites downloaded/deleted)
    if (oldWidget.sitesDataVersion != widget.sitesDataVersion) {
      LoggingService.info('[SITES_VERSION] Sites data version changed (${oldWidget.sitesDataVersion} -> ${widget.sitesDataVersion}), triggering immediate reload');
      // Call dedicated callback that bypasses bounds-changed check (like Map Filter does)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.onSitesDataVersionChanged != null) {
          LoggingService.info('[SITES_VERSION] Calling onSitesDataVersionChanged for immediate database reload');
          widget.onSitesDataVersionChanged!();
        }
      });
    }

    // Re-center on user location if it changes significantly
    if (widget.userLocation != null && oldWidget.userLocation != widget.userLocation) {
      final distance = oldWidget.userLocation != null
          ? MapCalculationUtils.quickDistanceMeters(oldWidget.userLocation!, widget.userLocation!)
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

  /// Get the marker presentation (color, tooltip, opacity) for a site
  SiteMarkerPresentation _getSiteMarkerPresentation(ParaglidingSite site) {
    final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
    final status = widget.siteFlyabilityStatus[key];
    final windData = widget.siteWindData[key];

    final presentation = SiteMarkerPresentation.forFlyability(
      site: site,
      status: status,
      windData: windData,
      maxWindSpeed: widget.maxWindSpeed,
      cautionWindSpeed: widget.cautionWindSpeed,
      forecastEnabled: widget.forecastEnabled,
    );

    // Special case: When forecast is enabled but no wind data, show zoom hint
    if (widget.forecastEnabled &&
        windData == null &&
        site.windDirections.isNotEmpty &&
        (status == null || status == FlyabilityStatus.unknown)) {
      return SiteMarkerPresentation(
        color: presentation.color,
        tooltip: '⚠️ Zoom in for wind forecast',
        opacity: presentation.opacity,
      );
    }

    return presentation;
  }

  /// Build markers for clustering with site data preserved
  List<Marker> _buildClusterableMarkers() {
    return widget.sites.map((site) {
      final presentation = _getSiteMarkerPresentation(site);

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
              Tooltip(
                message: presentation.tooltip ?? '',
                child: Opacity(
                  opacity: presentation.opacity,
                  child: SiteMarkerUtils.buildSiteMarkerIcon(
                    color: presentation.color,
                  ),
                ),
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

    // Check if any sites are flyable (green)
    final hasFlyableSites = markers.any((marker) {
      if (marker.key is ValueKey<ParaglidingSite>) {
        final site = (marker.key as ValueKey<ParaglidingSite>).value;
        final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
        final status = widget.siteFlyabilityStatus[key];
        return status == FlyabilityStatus.flyable;
      }
      return false;
    });

    // Check if any sites are caution (orange)
    final hasCautionSites = markers.any((marker) {
      if (marker.key is ValueKey<ParaglidingSite>) {
        final site = (marker.key as ValueKey<ParaglidingSite>).value;
        final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
        final status = widget.siteFlyabilityStatus[key];
        return status == FlyabilityStatus.caution;
      }
      return false;
    });

    // Check if any sites are not flyable (red)
    final hasNotFlyableSites = markers.any((marker) {
      if (marker.key is ValueKey<ParaglidingSite>) {
        final site = (marker.key as ValueKey<ParaglidingSite>).value;
        final key = SiteUtils.createSiteKey(site.latitude, site.longitude);
        final status = widget.siteFlyabilityStatus[key];
        return status == FlyabilityStatus.notFlyable;
      }
      return false;
    });

    // Check if any sites have no wind directions defined
    final hasNoWindDirectionsSites = markers.any((marker) {
      if (marker.key is ValueKey<ParaglidingSite>) {
        final site = (marker.key as ValueKey<ParaglidingSite>).value;
        return site.windDirections.isEmpty;
      }
      return false;
    });

    // Priority: Green if any flyable > Orange if any caution > Red if any not flyable > Grey for all unknown/loading
    final clusterColor = hasFlyableSites
        ? SiteMarkerUtils.flyableSiteColor
        : (hasCautionSites
            ? SiteMarkerUtils.strongWindSiteColor
            : (hasNotFlyableSites ? SiteMarkerUtils.notFlyableSiteColor : SiteMarkerUtils.unknownFlyabilitySiteColor));

    // Use reduced opacity only for clusters with unknown/loading sites that DO have wind directions
    // Sites with no wind directions OR known status get solid opacity
    // When forecast is disabled, all clusters get solid opacity
    final hasAnyKnownStatus = hasFlyableSites || hasCautionSites || hasNotFlyableSites;
    final alpha = (!widget.forecastEnabled || hasAnyKnownStatus || hasNoWindDirectionsSites) ? 0.9 : 0.5;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: clusterColor.withValues(alpha: alpha),
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

    // Weather station markers (only if enabled and zoom ≥ 10)
    // Check if map controller is initialized before accessing camera
    if (widget.weatherStationsEnabled && widget.weatherStations.isNotEmpty) {
      try {
        final zoom = MapConstants.roundZoomForDisplay(mapController.camera.zoom);
        if (zoom >= MapConstants.minForecastZoom) {
          layers.add(
            MarkerLayer(
              markers: _buildWeatherStationMarkers(),
            ),
          );
        }
      } catch (e) {
        // Map controller not yet initialized, skip weather stations for this frame
        LoggingService.debug('Map controller not yet initialized, skipping weather stations');
      }
    }

    return layers;
  }

  /// Build weather station markers
  List<Marker> _buildWeatherStationMarkers() {
    return widget.weatherStations.map((station) {
      // Get wind data for this station using the unique key (source:id)
      final windData = widget.stationWindData[station.key];

      // Create station with wind data
      final stationWithWind = station.copyWith(windData: windData);

      return Marker(
        point: LatLng(station.latitude, station.longitude),
        width: WeatherStationMarker.markerSize,
        height: WeatherStationMarker.markerSize,
        child: WeatherStationMarker(
          station: stationWithWind,
          maxWindSpeed: widget.maxWindSpeed,
          cautionWindSpeed: widget.cautionWindSpeed,
        ),
      );
    }).toList();
  }

  @override
  List<Widget> buildCustomSiteLegendItems() {
    // Override site legend with flyability-based colors for Nearby Sites
    return [
      // Wind forecast date/time
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.air, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            DateFormat('MMM d, h:mm a').format(widget.selectedDateTime),
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
        ],
      ),
      const SizedBox(height: 4),
      SiteMarkerUtils.buildLegendItem(
        context,
        Icons.location_on,
        SiteMarkerUtils.flyableSiteColor,
        'Flyable',
      ),
      const SizedBox(height: 4),
      SiteMarkerUtils.buildLegendItem(
        context,
        Icons.location_on,
        SiteMarkerUtils.strongWindSiteColor,
        'Strong',
      ),
      const SizedBox(height: 4),
      SiteMarkerUtils.buildLegendItem(
        context,
        Icons.location_on,
        SiteMarkerUtils.notFlyableSiteColor,
        'Not Flyable',
      ),
      const SizedBox(height: 4),
      SiteMarkerUtils.buildLegendItem(
        context,
        Icons.location_on,
        SiteMarkerUtils.unknownFlyabilitySiteColor,
        'Unknown',
      ),
    ];
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