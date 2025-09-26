import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/paragliding_site.dart';
import '../../services/logging_service.dart';
import '../../utils/map_constants.dart';
import 'common/base_map_widget.dart';
import 'common/map_overlays.dart';
import 'common/user_location_marker.dart';
import 'common/site_marker_layer.dart';

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
    super.height = 400,
    super.initialCenter,
    super.initialZoom = 10.0,
    super.mapController,
  });

  @override
  State<NearbySitesMap> createState() => _NearbySitesMapState();
}

class _NearbySitesMapState extends BaseMapState<NearbySitesMap> {
  ParaglidingSite? _selectedSite;

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
    // Clear selection on map tap
    setState(() {
      _selectedSite = null;
    });
  }

  void _onSiteMarkerTap(ParaglidingSite site) {
    // Don't show the map info card - just call parent's callback for PGE dialog
    widget.onSiteSelected?.call(site);
  }

  @override
  List<Widget> buildAdditionalLayers() {
    final layers = <Widget>[];

    // Site markers using the shared SiteMarkerLayer
    layers.add(
      SiteMarkerLayer(
        sites: widget.sites,
        showFlightCounts: true,
        onApiSiteClick: _onSiteMarkerTap,
        onLocalSiteClick: _onSiteMarkerTap, // Pass the original ParaglidingSite directly
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
        buildMap(), // Use buildMap() from BaseMapState
        ..._buildMapOverlays(),
      ],
    );
  }
}