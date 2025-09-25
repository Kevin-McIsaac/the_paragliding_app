import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/paragliding_site.dart';
import '../../../services/map_bounds_manager.dart';
import '../../../services/logging_service.dart';
import '../../../utils/airspace_overlay_manager.dart';
import '../../../utils/map_provider.dart';
import '../../../utils/map_tile_provider.dart';
import '../../../utils/site_marker_utils.dart';
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
  int get siteLimit => 50; // Default site limit, can be overridden

  // Template methods for customization
  List<Widget> buildAdditionalLayers() => [];
  List<Widget> buildAdditionalLegendItems() => [];
  List<Widget> buildAdditionalControls() => [];
  void onSitesLoaded(List<ParaglidingSite> sites) {}
  void onMapReady() {}
  void onMapTap(TapPosition tapPosition, LatLng point) {}

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
            ...buildAdditionalLayers(),
          ],
        ),
        buildAttribution(),
        buildMapControls(),
        buildLegend(),
        if (buildLoadingIndicator() != null) buildLoadingIndicator()!,
      ],
    );
  }
}