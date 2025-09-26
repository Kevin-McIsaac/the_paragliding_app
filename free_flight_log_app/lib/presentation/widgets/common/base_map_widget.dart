import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/paragliding_site.dart';
import '../../../services/map_bounds_manager.dart';
import '../../../services/logging_service.dart';
import '../../../services/airspace_identification_service.dart';
import '../../../services/airspace_geojson_service.dart';
import '../../../utils/airspace_overlay_manager.dart';
import '../../../utils/map_provider.dart';
import '../../../utils/map_tile_provider.dart';
import '../../../utils/site_marker_utils.dart';
import '../../../utils/map_constants.dart';
import '../../../utils/map_calculation_utils.dart';
import '../airspace_info_popup.dart';
import 'map_loading_overlay.dart';

/// Base widget for all map implementations in the app
/// Provides common functionality for map provider selection, legend management,
/// site loading, and UI components
abstract class BaseMapWidget extends StatefulWidget {
  final double? height;
  final LatLng? initialCenter;
  final double initialZoom;
  final double minZoom;
  final MapController? mapController;

  const BaseMapWidget({
    super.key,
    this.height,
    this.initialCenter,
    this.initialZoom = 13.0,
    this.minZoom = 1.0,
    this.mapController,
  });
}

abstract class BaseMapState<T extends BaseMapWidget> extends State<T> {
  // Map controller
  late final MapController _mapController;

  // Map provider state
  MapProvider _selectedMapProvider = MapProvider.openStreetMap;

  // Legend state
  bool _isLegendExpanded = false;

  // Sites state
  List<ParaglidingSite> _sites = [];
  bool _isLoadingSites = false;
  Timer? _loadingDelayTimer;
  bool _showLoadingIndicator = false;

  // Airspace overlay state (optional)
  List<Widget> _airspaceLayers = [];
  bool _isLoadingAirspace = false;
  final AirspaceOverlayManager _airspaceManager = AirspaceOverlayManager.instance;
  Timer? _airspaceLoadingTimer;

  // Airspace interaction state
  List<AirspaceData> _tooltipAirspaces = [];
  Offset? _tooltipPosition;
  bool _showTooltip = false;
  List<Polygon> _highlightedPolygons = [];
  List<MapEntry<List<AirspaceData>, LatLng>> _airspaceLabels = []; // Grouped airspaces with their positions

  // Common UI constants
  static const BoxShadow standardElevatedShadow = BoxShadow(
    color: Colors.black26,
    blurRadius: 4,
    offset: Offset(0, 2),
  );

  // Abstract methods that subclasses must implement
  String get mapProviderKey; // Unique key for storing map provider preference
  String get legendExpandedKey; // Unique key for storing legend state
  String get mapContext; // Context for MapBoundsManager (e.g., 'nearby_sites')
  int get siteLimit => MapConstants.defaultSiteLimit; // Default site limit, can be overridden

  // Template methods for customization
  List<Widget> buildAdditionalLayers() => [];
  List<Widget> buildAdditionalLegendItems() => [];
  List<Widget> buildAdditionalControls() => [];
  void onSitesLoaded(List<ParaglidingSite> sites) {}
  void onMapReady() {}
  void onMapTap(TapPosition tapPosition, LatLng point) {
    LoggingService.info('$mapContext: Map tapped at ${point.latitude}, ${point.longitude}');

    // Handle airspace interaction if enabled
    if (enableAirspace) {
      LoggingService.info('$mapContext: Airspace enabled, handling interaction');
      handleAirspaceInteraction(tapPosition, point);
    } else {
      LoggingService.info('$mapContext: Airspace not enabled');
    }
  }

  // Allow subclasses to customize bounds loading
  bool get loadSitesOnBoundsChange => true;

  // Airspace configuration (subclasses can enable)
  bool get enableAirspace => false;
  double get maxAltitudeFt => 10000.0;
  void onAirspaceLoaded(List<Widget> layers) {}

  MapController get mapController => _mapController;
  MapProvider get selectedMapProvider => _selectedMapProvider;
  List<ParaglidingSite> get sites => _sites;
  bool get isLegendExpanded => _isLegendExpanded;
  bool get isLoadingSites => _isLoadingSites;
  bool get showLoadingIndicator => _showLoadingIndicator;

  @override
  void initState() {
    super.initState();
    _mapController = widget.mapController ?? MapController();
    _loadMapProviderPreference();
    _loadLegendState();
  }

  @override
  void dispose() {
    _loadingDelayTimer?.cancel();
    _airspaceLoadingTimer?.cancel();
    if (widget.mapController == null) {
      _mapController.dispose();
    }
    super.dispose();
  }

  /// Load the saved map provider preference
  Future<void> _loadMapProviderPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProviderName = prefs.getString(mapProviderKey);

      if (savedProviderName != null) {
        final provider = MapProvider.values.firstWhere(
          (p) => p.name == savedProviderName,
          orElse: () => MapProvider.openStreetMap,
        );

        if (mounted) {
          setState(() {
            _selectedMapProvider = provider;
          });
          LoggingService.debug('$mapContext: Loaded map provider preference: ${provider.displayName}');
        }
      }
    } catch (e) {
      LoggingService.error('$mapContext: Error loading map provider preference', e);
    }
  }

  /// Save the map provider preference
  Future<void> _saveMapProviderPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(mapProviderKey, _selectedMapProvider.name);
    } catch (e) {
      LoggingService.error('$mapContext: Error saving map provider preference', e);
    }
  }

  /// Load the saved legend expansion state
  Future<void> _loadLegendState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isExpanded = prefs.getBool(legendExpandedKey) ?? false;

      if (mounted) {
        setState(() {
          _isLegendExpanded = isExpanded;
        });
      }
    } catch (e) {
      LoggingService.error('$mapContext: Error loading legend state', e);
    }
  }

  /// Save the legend expansion state
  Future<void> _saveLegendState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(legendExpandedKey, _isLegendExpanded);
    } catch (e) {
      LoggingService.error('$mapContext: Error saving legend state', e);
    }
  }

  /// Toggle legend expansion state
  void toggleLegend() {
    setState(() {
      _isLegendExpanded = !_isLegendExpanded;
    });
    _saveLegendState();
  }

  /// Select a new map provider
  void selectMapProvider(MapProvider provider) {
    setState(() {
      _selectedMapProvider = provider;
    });

    // Enforce zoom limits for the new provider
    enforceZoomLimits();

    _saveMapProviderPreference();
  }

  /// Enforce zoom limits for the current map provider
  void enforceZoomLimits() {
    final currentZoom = _mapController.camera.zoom;
    final maxZoom = _selectedMapProvider.maxZoom.toDouble();

    if (currentZoom > maxZoom) {
      _mapController.move(_mapController.camera.center, maxZoom);
    }
  }

  /// Handle map ready event
  void handleMapReady() {
    onMapReady();

    final bounds = _mapController.camera.visibleBounds;

    if (loadSitesOnBoundsChange) {
      loadSitesForBounds(bounds);
    }

    if (enableAirspace) {
      loadAirspaceLayers(bounds);
    }
  }

  /// Handle map events
  void handleMapEvent(MapEvent event) {
    // Enforce zoom limits
    enforceZoomLimits();

    // React to movement and zoom events to reload sites and airspace
    if ((event is MapEventMoveEnd ||
         event is MapEventFlingAnimationEnd ||
         event is MapEventDoubleTapZoomEnd ||
         event is MapEventScrollWheelZoom)) {

      updateMapBounds();
    }
  }

  /// Update map bounds and load sites/airspace
  void updateMapBounds() {
    final bounds = _mapController.camera.visibleBounds;

    if (loadSitesOnBoundsChange) {
      loadSitesForBounds(bounds);
    }

    if (enableAirspace) {
      loadAirspaceLayers(bounds);
    }
  }

  /// Load sites for the given bounds using MapBoundsManager
  void loadSitesForBounds(LatLngBounds bounds) {
    if (!loadSitesOnBoundsChange) return;

    setState(() => _isLoadingSites = true);

    // Show loading indicator after delay to prevent flashing
    _loadingDelayTimer?.cancel();
    _loadingDelayTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _isLoadingSites) {
        setState(() => _showLoadingIndicator = true);
      }
    });

    // Use MapBoundsManager for debounced loading
    MapBoundsManager.instance.loadSitesForBoundsDebounced(
      context: mapContext,
      bounds: bounds,
      siteLimit: siteLimit,
      includeFlightCounts: true,
      zoomLevel: mapController.camera.zoom,
      onLoaded: (result) {
        if (mounted) {
          setState(() {
            _sites = result.sites;
            _isLoadingSites = false;
            _showLoadingIndicator = false;
          });
          _loadingDelayTimer?.cancel();

          LoggingService.info('$mapContext: Loaded ${result.sites.length} sites');

          // Notify subclass
          onSitesLoaded(result.sites);
        }
      },
    );
  }

  /// Load airspace overlay layers if enabled
  Future<void> loadAirspaceLayers(LatLngBounds bounds) async {
    if (!enableAirspace || _isLoadingAirspace) return;

    setState(() => _isLoadingAirspace = true);

    try {
      final center = LatLng(
        (bounds.south + bounds.north) / 2,
        (bounds.west + bounds.east) / 2,
      );
      final zoom = _mapController.camera.zoom;

      final layers = await _airspaceManager.buildEnabledOverlayLayers(
        center: center,
        zoom: zoom,
        visibleBounds: bounds,
        maxAltitudeFt: maxAltitudeFt,
      );

      if (mounted) {
        setState(() {
          _airspaceLayers = layers;
          _isLoadingAirspace = false;
        });

        LoggingService.info('$mapContext: Loaded ${layers.length} airspace layers');

        // Notify subclass
        onAirspaceLoaded(layers);
      }
    } catch (e) {
      LoggingService.error('$mapContext: Error loading airspace layers', e);
      if (mounted) {
        setState(() {
          _isLoadingAirspace = false;
          _airspaceLayers = [];
        });
      }
    }
  }

  /// Get the appropriate icon for a map provider
  IconData getProviderIcon(MapProvider provider) {
    switch (provider) {
      case MapProvider.openStreetMap:
        return Icons.map;
      case MapProvider.googleSatellite:
        return Icons.satellite;
      case MapProvider.esriWorldImagery:
        return Icons.terrain;
    }
  }

  /// Build the tile layer for the selected map provider
  Widget buildTileLayer() {
    return TileLayer(
      urlTemplate: _selectedMapProvider.urlTemplate,
      userAgentPackageName: 'com.freeflightlog.free_flight_log_app',
      maxNativeZoom: _selectedMapProvider.maxZoom,
      maxZoom: _selectedMapProvider.maxZoom.toDouble(),
      tileProvider: MapTileProvider.createInstance(),
      errorTileCallback: MapTileProvider.getErrorCallback(),
    );
  }

  /// Build the map provider selector button
  Widget buildMapProviderButton() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x80000000),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [standardElevatedShadow],
      ),
      child: PopupMenuButton<MapProvider>(
        tooltip: 'Change Maps',
        onSelected: selectMapProvider,
        initialValue: _selectedMapProvider,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                getProviderIcon(_selectedMapProvider),
                size: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ],
          ),
        ),
        itemBuilder: (context) => MapProvider.values.map((provider) =>
          PopupMenuItem<MapProvider>(
            value: provider,
            child: Row(
              children: [
                Icon(
                  getProviderIcon(provider),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(provider.displayName),
                ),
              ],
            ),
          )
        ).toList(),
      ),
    );
  }

  /// Handle airspace interaction on map tap
  /// Made protected (not private) so subclasses can call it when needed
  void handleAirspaceInteraction(TapPosition tapPosition, LatLng point) {
    try {
      LoggingService.info('$mapContext: Identifying airspace at ${point.latitude}, ${point.longitude}');

      // Identify airspace at tap point - returns synchronous list
      final identificationService = AirspaceIdentificationService.instance;
      final airspaces = identificationService.identifyAirspacesAtPoint(point);

      LoggingService.info('$mapContext: Found ${airspaces.length} airspaces at tap location');

      if (airspaces.isNotEmpty && mounted) {
        LoggingService.info('$mapContext: Showing airspace popup for ${airspaces.first.name}');

        // Find ALL clipped polygons that contain the tap point and their centroids
        final result = _findClippedPolygonsWithCentroids(point, airspaces);

        setState(() {
          _tooltipAirspaces = airspaces;
          _tooltipPosition = tapPosition.global;
          _showTooltip = true;
          _highlightedPolygons = result.$1; // Highlighted polygons
          _airspaceLabels = result.$2; // Airspace/centroid pairs
        });
      } else if (mounted) {
        LoggingService.info('$mapContext: No airspace found at tap location, clearing popup');
        // Clear tooltip if no airspace found
        setState(() {
          _tooltipAirspaces = [];
          _tooltipPosition = null;
          _showTooltip = false;
          _highlightedPolygons = [];
          _airspaceLabels = [];
        });
      }
    } catch (e) {
      LoggingService.error('$mapContext: Error identifying airspace', e);
    }
  }

  /// Find clipped polygons that contain the tap point with their centroids
  (List<Polygon>, List<MapEntry<List<AirspaceData>, LatLng>>) _findClippedPolygonsWithCentroids(
      LatLng point, List<AirspaceData> airspaces) {
    final highlightedPolygons = <Polygon>[];
    final individualLabels = <MapEntry<AirspaceData, LatLng>>[];

    // We need to match each polygon to its airspace
    // Since we can't directly match them, we'll use the airspaces list
    // and check each polygon if it contains the tap point
    int airspaceIndex = 0;

    // Search through the rendered airspace layers for all polygons containing the tap point
    for (final layer in _airspaceLayers) {
      if (layer is PolygonLayer) {
        for (final polygon in layer.polygons) {
          // Check if this polygon contains the tap point
          if (_pointInPolygon(point, polygon.points)) {
            // Create highlighted version with double opacity
            // Keep original color but increase opacity
            final originalColor = polygon.color ?? Colors.blue.withValues(alpha: 0.2);
            final highlightedPolygon = Polygon(
              points: polygon.points,
              borderStrokeWidth: (polygon.borderStrokeWidth ?? 1.0) * 1.5, // Slightly thicker border
              borderColor: polygon.borderColor ?? Colors.blue,
              color: originalColor.withValues(
                alpha: ((originalColor.a * 255.0).round() * 2).clamp(0, 255) / 255.0, // Double opacity
              ),
            );
            highlightedPolygons.add(highlightedPolygon);

            // Calculate centroid and associate with airspace
            final centroid = _calculatePolygonCentroid(polygon.points);
            if (airspaceIndex < airspaces.length) {
              individualLabels.add(MapEntry(airspaces[airspaceIndex], centroid));
              airspaceIndex++;
            }
          }
        }
      }
    }

    // Group nearby labels to prevent overlap
    final groupedLabels = _groupNearbyLabels(individualLabels);

    LoggingService.info('$mapContext: Found ${highlightedPolygons.length} polygons, grouped into ${groupedLabels.length} labels');
    return (highlightedPolygons, groupedLabels);
  }

  /// Simple point-in-polygon test using ray casting
  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;

    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;

      if (((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
      j = i;
    }

    return inside;
  }

  /// Calculate centroid of a polygon
  LatLng _calculatePolygonCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);

    double totalLat = 0;
    double totalLng = 0;

    for (final point in points) {
      totalLat += point.latitude;
      totalLng += point.longitude;
    }

    return LatLng(totalLat / points.length, totalLng / points.length);
  }

  /// Group nearby labels to prevent overlap
  List<MapEntry<List<AirspaceData>, LatLng>> _groupNearbyLabels(
      List<MapEntry<AirspaceData, LatLng>> individualLabels) {

    if (individualLabels.isEmpty) return [];

    // Group labels that are within 1000 meters of each other
    const double groupingThresholdMeters = 1000.0;

    // Keep track of which labels have been grouped
    final groupedIndices = <int>{};
    final result = <MapEntry<List<AirspaceData>, LatLng>>[];

    for (int i = 0; i < individualLabels.length; i++) {
      if (groupedIndices.contains(i)) continue;

      final currentLabel = individualLabels[i];
      final group = <AirspaceData>[currentLabel.key];
      final positions = <LatLng>[currentLabel.value];
      groupedIndices.add(i);

      // Find all other labels within threshold distance
      for (int j = i + 1; j < individualLabels.length; j++) {
        if (groupedIndices.contains(j)) continue;

        final otherLabel = individualLabels[j];
        final distance = MapCalculationUtils.haversineDistance(
          currentLabel.value,
          otherLabel.value
        );

        if (distance <= groupingThresholdMeters) {
          group.add(otherLabel.key);
          positions.add(otherLabel.value);
          groupedIndices.add(j);
        }
      }

      // Calculate average position for the group
      double avgLat = 0;
      double avgLng = 0;
      for (final pos in positions) {
        avgLat += pos.latitude;
        avgLng += pos.longitude;
      }
      final groupPosition = LatLng(avgLat / positions.length, avgLng / positions.length);

      result.add(MapEntry(group, groupPosition));
    }

    return result;
  }

  /// Build airspace label widget for single or grouped airspaces
  Widget _buildAirspaceLabel(List<AirspaceData> airspaces) {
    if (airspaces.isEmpty) return const SizedBox.shrink();

    // For a single airspace, show full details
    if (airspaces.length == 1) {
      final airspace = airspaces.first;
      // Format altitude range using AirspaceData's properties
      final lower = airspace.lowerAltitude;
      final upper = airspace.upperAltitude;
      String altitudeRange;

      if (lower == upper || upper.isEmpty) {
        altitudeRange = lower;
      } else if (lower.isEmpty) {
        altitudeRange = upper;
      } else {
        altitudeRange = '$lower-$upper';
      }

      return IgnorePointer( // Don't interfere with map interaction
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Line 1: Airspace name
            Text(
              airspace.name,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 4, offset: const Offset(1, 1)),
                  Shadow(color: Colors.black, blurRadius: 4, offset: const Offset(-1, -1)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Line 2: Type, ICAO Class, Altitude
            Text(
              '${airspace.type.abbreviation}, ${airspace.icaoClass.displayName}, $altitudeRange',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 3, offset: const Offset(1, 1)),
                  Shadow(color: Colors.black, blurRadius: 3, offset: const Offset(-1, -1)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    // For grouped airspaces, show combined info
    final firstAirspace = airspaces.first;
    final typeClasses = airspaces.map((a) =>
      '${a.type.abbreviation}/${a.icaoClass.displayName}'
    ).toSet().join(', ');

    return IgnorePointer( // Don't interfere with map interaction
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line 1: Show first airspace name or "Multiple Airspaces"
          Text(
            airspaces.length == 2 ? firstAirspace.name : 'Multiple Airspaces',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 4, offset: const Offset(1, 1)),
                Shadow(color: Colors.black, blurRadius: 4, offset: const Offset(-1, -1)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Line 2: Combined types/classes
          Text(
            typeClasses,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 3, offset: const Offset(1, 1)),
                Shadow(color: Colors.black, blurRadius: 3, offset: const Offset(-1, -1)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Build the attribution widget
  Widget buildAttribution() {
    return Positioned(
      bottom: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[900]!.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          _selectedMapProvider.attribution,
          style: const TextStyle(fontSize: 8, color: Colors.white70),
        ),
      ),
    );
  }

  /// Build the collapsible legend widget
  Widget buildLegend() {
    final legendItems = <Widget>[
      // Common legend items
      SiteMarkerUtils.buildLegendItem(
        context,
        Icons.location_on,
        SiteMarkerUtils.flownSiteColor,
        'Flown Sites'
      ),
      const SizedBox(height: 4),
      SiteMarkerUtils.buildLegendItem(
        context,
        Icons.location_on,
        SiteMarkerUtils.newSiteColor,
        'New Sites'
      ),
      // Add airspace legend items if enabled
      if (enableAirspace && _airspaceLayers.isNotEmpty) ...[
        const SizedBox(height: 4),
        ...SiteMarkerUtils.buildAirspaceLegendItems(),
      ],
      // Add subclass-specific legend items
      ...buildAdditionalLegendItems(),
    ];

    return Positioned(
      top: 8,
      left: 8,
      child: SiteMarkerUtils.buildCollapsibleMapLegend(
        context: context,
        isExpanded: _isLegendExpanded,
        onToggle: toggleLegend,
        legendItems: legendItems,
      ),
    );
  }

  /// Build the loading indicator
  Widget? buildLoadingIndicator() {
    if (!_showLoadingIndicator) return null;

    return MapLoadingOverlay.single(
      label: 'Loading sites',
      icon: Icons.place,
      iconColor: Colors.green,
    );
  }

  /// Build the map controls (provider selector and additional controls)
  Widget buildMapControls() {
    final additionalControls = buildAdditionalControls();

    return Positioned(
      top: 8,
      right: 8,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...additionalControls,
          if (additionalControls.isNotEmpty) const SizedBox(width: 8),
          buildMapProviderButton(),
        ],
      ),
    );
  }

  /// Build the complete map widget with all layers and overlays
  Widget buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.initialCenter ?? const LatLng(46.9480, 7.4474),
            initialZoom: widget.initialZoom,
            minZoom: widget.minZoom,
            maxZoom: _selectedMapProvider.maxZoom.toDouble(),
            onMapReady: handleMapReady,
            onMapEvent: handleMapEvent,
            onTap: onMapTap,
          ),
          children: [
            buildTileLayer(),
            // Add airspace layers before site markers
            if (enableAirspace) ..._airspaceLayers,
            // Add highlighted polygons layer
            if (_highlightedPolygons.isNotEmpty)
              PolygonLayer(polygons: _highlightedPolygons),
            // Add label markers at polygon centroids
            if (_airspaceLabels.isNotEmpty)
              MarkerLayer(
                markers: _airspaceLabels.map((entry) {
                  return Marker(
                    point: entry.value, // Centroid position
                    width: 200,
                    height: 60,
                    child: _buildAirspaceLabel(entry.key), // Airspace data
                  );
                }).toList(),
              ),
            ...buildAdditionalLayers(),
          ],
        ),
        buildAttribution(),
        buildMapControls(),
        buildLegend(),
        if (buildLoadingIndicator() != null) buildLoadingIndicator()!,
        // Add airspace info popup
        if (_showTooltip && _tooltipPosition != null && _tooltipAirspaces.isNotEmpty)
          AirspaceInfoPopup(
            position: _tooltipPosition!,
            airspaces: _tooltipAirspaces,
            screenSize: MediaQuery.of(context).size,
            onClose: () {
              setState(() {
                _showTooltip = false;
                _tooltipAirspaces = [];
                _tooltipPosition = null;
                _highlightedPolygons = [];
                _airspaceLabels = [];
              });
            },
          ),
      ],
    );
  }
}