import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/models/paragliding_site.dart';
import '../../services/logging_service.dart';
import '../../utils/site_marker_utils.dart';
import '../../utils/map_provider.dart';
import '../../utils/site_utils.dart';
import '../../utils/map_controls.dart';
import '../../utils/map_tile_provider.dart';
import '../../utils/airspace_overlay_manager.dart';
import '../../services/openaip_service.dart';
import '../../services/airspace_geojson_service.dart';
import '../../data/models/airspace_enums.dart';
import '../../services/airspace_identification_service.dart';
import '../widgets/airspace_info_popup.dart';
import '../widgets/airspace_hover_tooltip.dart';
import '../widgets/map_filter_fab.dart';
import '../widgets/map_legend_widget.dart';
import '../../utils/performance_monitor.dart';

class NearbySitesMapWidget extends StatefulWidget {
  final List<ParaglidingSite> sites;
  final Map<String, bool> siteFlightStatus;
  final Position? userPosition;
  final LatLng? centerPosition;
  final fm.LatLngBounds? boundsToFit; // Optional bounds for exact map fitting
  final double initialZoom;
  final MapProvider mapProvider;
  final bool isLegendExpanded;
  final VoidCallback onToggleLegend;
  final Function(ParaglidingSite)? onSiteSelected;
  final Function(fm.LatLngBounds)? onBoundsChanged;
  final String searchQuery;
  final Function(String) onSearchChanged;
  final VoidCallback onRefreshLocation;
  final bool isLocationLoading;
  final List<ParaglidingSite> searchResults;
  final bool isSearching;
  final Function(ParaglidingSite) onSearchResultSelected;
  final VoidCallback? onShowMapFilter;
  final bool hasActiveFilters;
  final bool sitesEnabled;
  final double maxAltitudeFt;
  final int filterUpdateCounter;
  final Map<IcaoClass, bool> excludedIcaoClasses;

  const NearbySitesMapWidget({
    super.key,
    required this.sites,
    required this.siteFlightStatus,
    this.userPosition,
    this.centerPosition,
    this.boundsToFit,
    this.initialZoom = 10.0,
    required this.mapProvider,
    required this.isLegendExpanded,
    required this.onToggleLegend,
    this.onSiteSelected,
    this.onBoundsChanged,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onRefreshLocation,
    required this.isLocationLoading,
    required this.searchResults,
    required this.isSearching,
    required this.onSearchResultSelected,
    this.onShowMapFilter,
    this.hasActiveFilters = false,
    this.sitesEnabled = true,
    this.maxAltitudeFt = 15000.0,
    this.filterUpdateCounter = 0,
    this.excludedIcaoClasses = const {},
  });

  @override
  State<NearbySitesMapWidget> createState() => _NearbySitesMapWidgetState();
}

class _NearbySitesMapWidgetState extends State<NearbySitesMapWidget> {
  final fm.MapController _mapController = fm.MapController();
  final FocusNode _searchFocusNode = FocusNode();
  final AirspaceOverlayManager _airspaceManager = AirspaceOverlayManager.instance;
  
  // Airspace overlay state
  List<Widget> _airspaceLayers = [];
  bool _airspaceLoading = false;
  bool _airspaceEnabled = false;
  Set<AirspaceType> _visibleAirspaceTypes = {};

  // Airspace tooltip state
  List<AirspaceData> _tooltipAirspaces = [];
  Offset? _tooltipPosition;
  bool _showTooltip = false;

  // Hover state
  Timer? _hoverDebounceTimer;
  LatLng? _hoverPosition;
  Offset? _hoverScreenPosition;
  AirspaceData? _hoveredAirspace;
  fm.Polygon? _highlightedPolygon;

  // Debouncing for render logs
  DateTime? _lastRenderLog;
  int _lastSiteCount = -1;
  double _lastZoom = -1;

  // Track current zoom level to avoid accessing MapController in build
  late double _currentZoom;

  // Unified map update debouncing
  Timer? _mapUpdateDebouncer;
  fm.LatLngBounds? _lastProcessedBounds;
  static const double _boundsThreshold = 0.001;
  static const int _debounceDurationMs = 750;

  // Separate loading states for parallel operations
  bool _isLoadingSites = false;
  bool _isLoadingAirspace = false;
  int? _loadedSiteCount;
  int? _loadedAirspaceCount;

  
  @override
  void initState() {
    super.initState();
    _currentZoom = widget.initialZoom; // Initialize with the initial zoom
    _loadAirspaceStatus();
    // Delay airspace loading until after the first frame to ensure MapController is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAirspaceLayers();
    });
  }


  @override
  void didUpdateWidget(NearbySitesMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Track site count changes
    if (oldWidget.sites != widget.sites && widget.sites != null) {
      setState(() {
        _loadedSiteCount = widget.sites!.length;
        _isLoadingSites = false; // Sites have been loaded
      });
    }

    // Check if sites were just enabled - reload site data
    if (oldWidget.sitesEnabled != widget.sitesEnabled) {
      if (widget.sitesEnabled) {
        // Sites were just enabled - reload all data for current bounds
        // Clear last bounds to force a reload even if bounds are the same
        _lastProcessedBounds = null;
        _loadVisibleData();
      }
    }

    // Check if filter properties changed and reload overlays if needed
    if (oldWidget.sitesEnabled != widget.sitesEnabled ||
        oldWidget.maxAltitudeFt != widget.maxAltitudeFt ||
        oldWidget.filterUpdateCounter != widget.filterUpdateCounter) {
      // Reload overlays with new filter settings
      _loadAirspaceLayers();
      // Refresh tooltip with updated filter status if currently open
      _refreshTooltipIfOpen();
    }

    // Priority 1: Check if we should fit to exact bounds (for precise area display)
    if (widget.boundsToFit != null &&
        oldWidget.boundsToFit != widget.boundsToFit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.fitCamera(
          fm.CameraFit.bounds(
            bounds: widget.boundsToFit!,
            padding: const EdgeInsets.all(20), // Small padding for visibility
          ),
        );
      });
    }
    // Priority 2: Fallback to center/zoom for normal navigation
    else if (widget.centerPosition != null && 
             oldWidget.centerPosition != widget.centerPosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(widget.centerPosition!, widget.initialZoom);
      });
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _mapController.dispose();
    _hoverDebounceTimer?.cancel();
    _mapUpdateDebouncer?.cancel();
    super.dispose();
  }

  void _onMapReady() {
    // Initial load of all data when map is ready
    _loadVisibleData();
  }
  
  void _onMapEvent(fm.MapEvent event) {
    // Log frame performance during map interactions
    if (event is fm.MapEventMove || event is fm.MapEventFlingAnimation) {
      // Log frame jank during movement
      final frameStats = PerformanceMonitor.getFrameRateStats();
      final droppedFrames = frameStats['dropped_frames'] as int;
      if (droppedFrames > 5) {
        LoggingService.structured('FRAME_JANK', {
          'dropped_frames': droppedFrames,
          'total_frames': frameStats['total_frames'],
          'fps': (frameStats['fps'] as double).toStringAsFixed(1),
          'worst_frame_ms': (frameStats['avg_frame_time_ms'] as double).toStringAsFixed(1),
          'context': event is fm.MapEventMove ? 'map_pan' : 'map_fling',
        });
      }
    }

    // React to all movement and zoom end events to reload sites and airspace
    if (event is fm.MapEventMoveEnd ||
        event is fm.MapEventFlingAnimationEnd ||
        event is fm.MapEventDoubleTapZoomEnd ||
        event is fm.MapEventScrollWheelZoom) {

      // Unified debounced handler for ALL bounds-based loading
      _mapUpdateDebouncer?.cancel();
      _mapUpdateDebouncer = Timer(
        const Duration(milliseconds: _debounceDurationMs),
        () {
          // Log frame performance summary after map movement ends
          PerformanceMonitor.logFrameRatePerformance();
          _loadVisibleData();
        },
      );
    }
  }

  /// Unified method to load all visible data (sites and airspace) with debouncing
  Future<void> _loadVisibleData() async {
    if (!_isMapReady()) return;

    final bounds = _mapController.camera.visibleBounds;

    // Check threshold to avoid redundant loads
    if (!_boundsChangedSignificantly(bounds)) return;

    _lastProcessedBounds = bounds;

    // Log the unified loading event
    LoggingService.info('Loading visible data for bounds: ${bounds.west.toStringAsFixed(2)},${bounds.south.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)},${bounds.north.toStringAsFixed(2)}');

    // Set loading states before starting parallel loads
    setState(() {
      _isLoadingSites = widget.sitesEnabled;
      _isLoadingAirspace = _airspaceEnabled;
      _loadedSiteCount = null;
      _loadedAirspaceCount = null;
    });

    // Parallel load both sites and airspace
    await Future.wait([
      _loadSitesForBounds(bounds).then((_) {
        // Loading state is cleared by the parent's onBoundsChanged callback
      }),
      _loadAirspaceLayers().then((_) {
        setState(() {
          _isLoadingAirspace = false;
        });
      }),
    ]);
  }

  /// Check if map controller is ready
  bool _isMapReady() {
    try {
      _mapController.camera.center;
      return true;
    } catch (e) {
      LoggingService.info('MapController not ready for data loading');
      return false;
    }
  }

  /// Check if bounds have changed significantly
  bool _boundsChangedSignificantly(fm.LatLngBounds newBounds) {
    if (_lastProcessedBounds == null) return true;

    return (newBounds.north - _lastProcessedBounds!.north).abs() >= _boundsThreshold ||
           (newBounds.south - _lastProcessedBounds!.south).abs() >= _boundsThreshold ||
           (newBounds.east - _lastProcessedBounds!.east).abs() >= _boundsThreshold ||
           (newBounds.west - _lastProcessedBounds!.west).abs() >= _boundsThreshold;
  }

  /// Load sites for the given bounds
  Future<void> _loadSitesForBounds(fm.LatLngBounds bounds) async {

    // Skip loading sites if they're disabled
    if (!widget.sitesEnabled) {
      return;
    }

    // Notify parent to handle site loading
    if (widget.onBoundsChanged != null) {
      widget.onBoundsChanged!(bounds);
    }
  }

  /// Load airspace overlay layers based on user preferences and current map view
  Future<void> _loadAirspaceLayers() async {
    if (_airspaceLoading) return;

    setState(() {
      _airspaceLoading = true;
    });

    try {
      // Check if MapController is ready by trying to access camera properties
      try {
        // This will throw if the map hasn't been rendered yet
        _mapController.camera.center;
      } catch (e) {
        LoggingService.info('MapController not ready yet, skipping airspace load');
        setState(() {
          _airspaceLoading = false;
        });
        return;
      }

      // Get actual viewport bounds instead of calculated expanded bounds
      final visibleBounds = _mapController.camera.visibleBounds;
      final center = _mapController.camera.center;
      final zoom = _mapController.camera.zoom;

      final layers = await _airspaceManager.buildEnabledOverlayLayers(
        center: center,
        zoom: zoom,
        visibleBounds: visibleBounds,  // Pass actual viewport bounds
        maxAltitudeFt: widget.maxAltitudeFt,
      );

      if (mounted) {
        // Get the visible airspace types from the service for legend filtering
        final visibleTypes = AirspaceGeoJsonService.instance.visibleAirspaceTypes;

        setState(() {
          _airspaceLayers = layers;
          _airspaceLoading = false;
          _visibleAirspaceTypes = visibleTypes;
          _loadedAirspaceCount = layers.length;
        });

        LoggingService.structured('AIRSPACE_LAYERS_LOADED', {
          'layer_count': layers.length,
          'visible_types_count': visibleTypes.length,
          'visible_types': visibleTypes.toList(),
          'widget_mounted': mounted,
          'center': '${center.latitude},${center.longitude}',
          'zoom': zoom,
        });
      }
    } catch (error, stackTrace) {
      LoggingService.error('Failed to load airspace layers', error, stackTrace);

      if (mounted) {
        setState(() {
          _airspaceLayers = [];
          _airspaceLoading = false;
        });
      }
    }
  }
  
  /// Load airspace status for legend display
  Future<void> _loadAirspaceStatus() async {
    try {
      final enabled = await OpenAipService.instance.isAirspaceEnabled();
      if (mounted) {
        setState(() {
          _airspaceEnabled = enabled;
        });
      }
    } catch (error, stackTrace) {
      LoggingService.error('Failed to load airspace status', error, stackTrace);
    }
  }

  /// Refresh airspace layers when settings change
  void refreshAirspaceLayers() {
    _loadAirspaceStatus(); // Also refresh the status for legend
    _loadAirspaceLayers();
  }

  /// Convert numeric airspace types back to string abbreviations for legacy compatibility
  Set<String> _convertNumericTypesToStrings(Set<int> numericTypes) {
    const numericToString = {
      0: 'Unknown',
      1: 'A',
      2: 'E',
      3: 'C',
      4: 'CTR',
      5: 'E',
      6: 'TMA',
      7: 'G',
      8: 'CTR',
      9: 'TMA',
      10: 'CTA',
      11: 'R',
      12: 'P',
      13: 'ATZ',
      14: 'D',
      15: 'R',
      16: 'TMA',
      17: 'CTR',
      18: 'R',
      19: 'P',
      20: 'D',
      21: 'TMA',
      26: 'CTA',
    };

    return numericTypes.map((type) => numericToString[type] ?? 'Unknown').toSet();
  }

  /// Handle click for airspace identification
  void _handleAirspaceInteraction(Offset screenPosition, LatLng mapPoint) async {
    if (!_airspaceEnabled) return;

    // Identify airspaces at the point (using map coordinates from FlutterMap)
    final allAirspaces = AirspaceIdentificationService.instance.identifyAirspacesAtPoint(mapPoint);

    // Update filter status for all identified airspaces
    await _updateAirspaceFilterStatus(allAirspaces);

    // Sort all airspaces by lower altitude limit (ascending), then by upper altitude limit (ascending)
    allAirspaces.sort((a, b) {
      int lowerCompare = a.getLowerAltitudeInFeet().compareTo(b.getLowerAltitudeInFeet());
      if (lowerCompare != 0) return lowerCompare;
      return a.getUpperAltitudeInFeet().compareTo(b.getUpperAltitudeInFeet());
    });

    if (allAirspaces.isNotEmpty) {
      // Check if clicking near the same position (toggle behavior)
      if (_showTooltip && _tooltipPosition != null && _isSimilarPosition(screenPosition, _tooltipPosition!)) {
        // Toggle: hide tooltip if clicking the same area
        _hideTooltip();
      } else {
        // Show tooltip for all airspaces (filtered and unfiltered)
        // Clear hover state when showing popup
        _clearHover();
        setState(() {
          _tooltipAirspaces = allAirspaces;
          _tooltipPosition = screenPosition;
          _showTooltip = true;
        });
      }
    } else {
      // No airspaces found, hide tooltip
      _hideTooltip();
    }
  }

  /// Update airspace filter status flags based on current filter settings
  Future<void> _updateAirspaceFilterStatus(List<AirspaceData> airspaces) async {
    if (airspaces.isEmpty) return;

    // Get current exclusion settings
    final excludedTypes = await OpenAipService.instance.getExcludedAirspaceTypes();
    final excludedClasses = await OpenAipService.instance.getExcludedIcaoClasses();

    // Update filter status for each airspace
    for (final airspace in airspaces) {
      // Check if airspace is filtered: true = excluded/filtered out, false/null = shown
      final isTypeFiltered = excludedTypes[airspace.type] == true;
      final isClassFiltered = excludedClasses[airspace.icaoClass ?? IcaoClass.none] == true;
      final isElevationFiltered = airspace.getLowerAltitudeInFeet() > widget.maxAltitudeFt;

      // Mark if this airspace is currently filtered out
      airspace.isCurrentlyFiltered = isTypeFiltered || isClassFiltered || isElevationFiltered;
    }
  }

  /// Refresh tooltip if currently open by re-identifying airspaces with updated filter status
  Future<void> _refreshTooltipIfOpen() async {
    if (!_showTooltip || _tooltipPosition == null) return;

    try {
      // Convert screen position back to map coordinates
      // We need to estimate the LatLng from the screen position
      // The exact conversion requires the map controller's current state
      final camera = _mapController.camera;
      final bounds = camera.visibleBounds;
      final size = MediaQuery.of(context).size;

      // Convert screen position to normalized coordinates (0-1)
      final normalizedX = _tooltipPosition!.dx / size.width;
      final normalizedY = _tooltipPosition!.dy / size.height;

      // Convert to LatLng based on current map bounds
      final lat = bounds.north - (bounds.north - bounds.south) * normalizedY;
      final lng = bounds.west + (bounds.east - bounds.west) * normalizedX;
      final mapPoint = LatLng(lat, lng);

      // Re-identify airspaces at the same location
      final allAirspaces = AirspaceIdentificationService.instance.identifyAirspacesAtPoint(mapPoint);

      // Update filter status for all identified airspaces
      await _updateAirspaceFilterStatus(allAirspaces);

      // Sort airspaces by altitude (same as original logic)
      allAirspaces.sort((a, b) {
        int lowerCompare = a.getLowerAltitudeInFeet().compareTo(b.getLowerAltitudeInFeet());
        if (lowerCompare != 0) return lowerCompare;
        return a.getUpperAltitudeInFeet().compareTo(b.getUpperAltitudeInFeet());
      });

      // Update tooltip with refreshed airspace data
      if (mounted) {
        setState(() {
          _tooltipAirspaces = allAirspaces;
        });
      }
    } catch (error, stackTrace) {
      LoggingService.error('Failed to refresh tooltip airspaces', error, stackTrace);
    }
  }

  /// Check if two positions are similar (within 50 pixels)
  bool _isSimilarPosition(Offset pos1, Offset pos2) {
    const double threshold = 50.0;
    return (pos1 - pos2).distance < threshold;
  }


  /// Hide the airspace tooltip immediately
  void _hideTooltip() {
    if (_showTooltip) {
      setState(() {
        _showTooltip = false;
        _tooltipAirspaces = [];
        _tooltipPosition = null;
      });
    }
  }

  /// Handle hover over map to show lightweight tooltip
  void _handleHover(Offset screenPosition) {
    if (!_airspaceEnabled || _showTooltip) return; // Don't show hover when popup is open

    // Debounce hover detection to avoid excessive calculations
    _hoverDebounceTimer?.cancel();
    _hoverDebounceTimer = Timer(const Duration(milliseconds: 100), () async {
      // Convert screen position to map coordinates
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      try {
        // Get map point from screen position
        final localPosition = renderBox.globalToLocal(screenPosition);
        // Use custom offset to handle the coordinate conversion
        final mapPoint = _mapController.camera.offsetToCrs(
          Offset(localPosition.dx, localPosition.dy),
        );

        // Identify airspaces at hover point
        final airspaces = AirspaceIdentificationService.instance.identifyAirspacesAtPoint(mapPoint);

        // Filter out excluded airspaces
        final excludedTypes = await OpenAipService.instance.getExcludedAirspaceTypes();
        final excludedClasses = await OpenAipService.instance.getExcludedIcaoClasses();

        final visibleAirspaces = airspaces.where((airspace) {
          final isTypeExcluded = excludedTypes[airspace.type] == true;
          final isClassExcluded = excludedClasses[airspace.icaoClass ?? IcaoClass.none] == true;
          final isElevationExcluded = airspace.getLowerAltitudeInFeet() > widget.maxAltitudeFt;
          return !isTypeExcluded && !isClassExcluded && !isElevationExcluded;
        }).toList();

        if (visibleAirspaces.isEmpty) {
          _clearHover();
          return;
        }

        // Sort by lower altitude to get the lowest airspace
        visibleAirspaces.sort((a, b) =>
          a.getLowerAltitudeInFeet().compareTo(b.getLowerAltitudeInFeet()));

        final lowestAirspace = visibleAirspaces.first;

        // Get polygon for highlighting
        final polygonPoints = AirspaceIdentificationService.instance.getPolygonForAirspace(lowestAirspace);

        if (polygonPoints != null && mounted) {
          setState(() {
            _hoveredAirspace = lowestAirspace;
            _hoverPosition = mapPoint;
            _hoverScreenPosition = screenPosition;

            // Create highlighted polygon with 60% opacity
            _highlightedPolygon = fm.Polygon(
              points: polygonPoints,
              color: lowestAirspace.icaoClass?.fillColor.withOpacity(0.6) ??
                     Colors.grey.withOpacity(0.6),
              borderColor: lowestAirspace.icaoClass?.borderColor ?? Colors.grey,
              borderStrokeWidth: 2.0,
            );
          });
        }
      } catch (error) {
        LoggingService.error('Error handling hover', error);
      }
    });
  }

  /// Clear hover state
  void _clearHover() {
    _hoverDebounceTimer?.cancel();
    if (_hoveredAirspace != null && mounted) {
      setState(() {
        _hoveredAirspace = null;
        _hoverPosition = null;
        _hoverScreenPosition = null;
        _highlightedPolygon = null;
      });
    }
  }




  LatLng _getInitialCenter() {
    // Priority: explicit center position, user position, or default
    if (widget.centerPosition != null) {
      return widget.centerPosition!;
    }
    
    if (widget.userPosition != null) {
      return LatLng(widget.userPosition!.latitude, widget.userPosition!.longitude);
    }
    
    // Default to center of all sites if available
    if (widget.sites.isNotEmpty) {
      double avgLat = widget.sites.map((s) => s.latitude).reduce((a, b) => a + b) / widget.sites.length;
      double avgLng = widget.sites.map((s) => s.longitude).reduce((a, b) => a + b) / widget.sites.length;
      return LatLng(avgLat, avgLng);
    }
    
    // Fallback to a reasonable default (central Europe)
    return const LatLng(47.0, 8.0);
  }


  List<fm.Marker> _buildSiteMarkers() {
    // Don't show site markers if sites are disabled
    if (!widget.sitesEnabled) {
      return [];
    }

    return widget.sites.map((site) {
      final siteKey = SiteUtils.createSiteKey(site.latitude, site.longitude);
      final hasFlights = widget.siteFlightStatus[siteKey] ?? false;
      
      return fm.Marker(
        point: LatLng(site.latitude, site.longitude),
        width: 140,
        height: 80,
        child: GestureDetector(
          onTap: () {
            widget.onSiteSelected?.call(site);
          },
          child: SiteMarkerUtils.buildDisplaySiteMarker(
            position: LatLng(site.latitude, site.longitude),
            siteName: site.name,
            isFlownSite: hasFlights, // Blue for flown sites, purple for new sites
            flightCount: hasFlights ? 1 : null, // Show indicator if flown
            tooltip: hasFlights ? '${site.name} (Flown)' : site.name,
          ).child,
        ),
      );
    }).toList();
  }

  List<fm.Marker> _buildUserLocationMarker() {
    if (widget.userPosition == null) return [];
    
    return [
      fm.Marker(
        point: LatLng(widget.userPosition!.latitude, widget.userPosition!.longitude),
        width: 30,
        height: 30,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: const Icon(
            Icons.my_location,
            color: Colors.white,
            size: 16,
          ),
        ),
      ),
    ];
  }



  // Add methods for map controls, legend, and attribution

  Widget _buildTopControlBar() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend with ICAO classes
          MapLegendWidget(
            isMergeMode: false, // Merge mode not relevant for this widget
            sitesEnabled: widget.sitesEnabled,
            excludedIcaoClasses: widget.excludedIcaoClasses,
          ),
          
          const SizedBox(width: 8),
          
          // Airspace controls moved to AppBar to avoid gesture conflicts
          
          const SizedBox(width: 8),
          
          // Search bar with dropdown
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0x80000000),
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      if (widget.isSearching)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        )
                      else
                        const Icon(Icons.search, size: 20, color: Colors.white70),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          focusNode: _searchFocusNode,
                          initialValue: widget.searchQuery,
                          onChanged: widget.onSearchChanged,
                          onFieldSubmitted: widget.onSearchChanged, // Trigger search on Enter
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Search sites worldwide...',
                            hintStyle: TextStyle(color: Colors.white70, fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                        ),
                      ),
                      // Clear search button
                      if (widget.searchQuery.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => widget.onSearchChanged(''),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            child: const Icon(
                              Icons.clear,
                              size: 18,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Search results dropdown with enhanced UX
                if (widget.searchResults.isNotEmpty)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutQuad,
                    constraints: const BoxConstraints(maxHeight: 300),
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Results header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withOpacity(0.1),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '${widget.searchResults.length} site${widget.searchResults.length == 1 ? '' : 's'} found',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                if (widget.isSearching)
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white70,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Results list
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: widget.searchResults.length,
                              separatorBuilder: (context, index) => Container(
                                height: 1,
                                margin: const EdgeInsets.symmetric(horizontal: 16),
                                color: Colors.white.withOpacity(0.05),
                              ),
                              itemBuilder: (context, index) {
                                final site = widget.searchResults[index];
                                // Calculate distance if user position is available
                                String? distanceText;
                                if (widget.userPosition != null) {
                                  final distance = Geolocator.distanceBetween(
                                    widget.userPosition!.latitude,
                                    widget.userPosition!.longitude,
                                    site.latitude,
                                    site.longitude,
                                  );
                                  if (distance < 1000) {
                                    distanceText = '${distance.toStringAsFixed(0)}m';
                                  } else {
                                    distanceText = '${(distance / 1000).toStringAsFixed(1)}km';
                                  }
                                }
                                
                                // Get country flag emoji
                                String countryFlag = '';
                                if (site.country != null) {
                                  // Simple country code to flag emoji mapping
                                  final countryCode = site.country!.toUpperCase();
                                  final flagMap = {
                                    'AU': '🇦🇺', 'AUSTRALIA': '🇦🇺',
                                    'NZ': '🇳🇿', 'NEW ZEALAND': '🇳🇿',
                                    'US': '🇺🇸', 'USA': '🇺🇸', 'UNITED STATES': '🇺🇸',
                                    'CA': '🇨🇦', 'CANADA': '🇨🇦',
                                    'GB': '🇬🇧', 'UK': '🇬🇧', 'UNITED KINGDOM': '🇬🇧',
                                    'FR': '🇫🇷', 'FRANCE': '🇫🇷',
                                    'DE': '🇩🇪', 'GERMANY': '🇩🇪',
                                    'ES': '🇪🇸', 'SPAIN': '🇪🇸',
                                    'IT': '🇮🇹', 'ITALY': '🇮🇹',
                                    'CH': '🇨🇭', 'SWITZERLAND': '🇨🇭',
                                    'AT': '🇦🇹', 'AUSTRIA': '🇦🇹',
                                    'JP': '🇯🇵', 'JAPAN': '🇯🇵',
                                    'CN': '🇨🇳', 'CHINA': '🇨🇳',
                                    'IN': '🇮🇳', 'INDIA': '🇮🇳',
                                    'BR': '🇧🇷', 'BRAZIL': '🇧🇷',
                                    'MX': '🇲🇽', 'MEXICO': '🇲🇽',
                                    'ZA': '🇿🇦', 'SOUTH AFRICA': '🇿🇦',
                                  };
                                  countryFlag = flagMap[countryCode] ?? '';
                                }
                                
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      widget.onSearchResultSelected(site);
                                      // Maintain focus on search bar after selecting result
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        _searchFocusNode.requestFocus();
                                      });
                                    },
                                    highlightColor: Colors.white.withOpacity(0.1),
                                    splashColor: Colors.white.withOpacity(0.05),
                                    canRequestFocus: false, // Prevent stealing focus from search bar
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          // Site icon with color coding
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: Colors.deepPurple.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.paragliding,
                                              color: Colors.deepPurple,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Site info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  site.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    if (countryFlag.isNotEmpty) ...[
                                                      Text(
                                                        countryFlag,
                                                        style: const TextStyle(fontSize: 14),
                                                      ),
                                                      const SizedBox(width: 6),
                                                    ],
                                                    if (site.country != null)
                                                      Text(
                                                        site.country!,
                                                        style: TextStyle(
                                                          color: Colors.white.withOpacity(0.6),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    if (distanceText != null) ...[
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '• $distanceText',
                                                        style: TextStyle(
                                                          color: Colors.white.withOpacity(0.5),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Arrow indicator
                                          Icon(
                                            Icons.arrow_forward_ios,
                                            color: Colors.white.withOpacity(0.3),
                                            size: 14,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Empty search state
                if (widget.searchQuery.isNotEmpty && widget.searchResults.isEmpty && !widget.isSearching)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutQuad,
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_off,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'No sites found for "${widget.searchQuery}"',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Location button
          GestureDetector(
            onTap: widget.isLocationLoading ? null : widget.onRefreshLocation,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0x80000000),
                borderRadius: BorderRadius.all(Radius.circular(4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: widget.isLocationLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.my_location,
                        size: 20,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
          
          const SizedBox(width: 12),

          // Filter button
          if (widget.onShowMapFilter != null)
            MapFilterButton(
              hasActiveFilters: widget.hasActiveFilters,
              sitesEnabled: widget.sitesEnabled,
              onPressed: widget.onShowMapFilter!,
            ),

          if (widget.onShowMapFilter != null)
            const SizedBox(width: 12),

        ],
      ),
    );
  }

  Widget _buildAttribution() {
    return MapControls.buildAttribution(
      provider: widget.mapProvider,
      showAirspaceAttribution: _airspaceLayers.isNotEmpty,
      showSitesAttribution: widget.sites.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Track widget rebuild
    PerformanceMonitor.trackWidgetRebuild('NearbySitesMapWidget');

    // Start timing the build
    final buildStopwatch = Stopwatch()..start();

    // Count flown vs new sites for logging
    final flownSites = widget.sites.where((site) {
      final siteKey = SiteUtils.createSiteKey(site.latitude, site.longitude);
      return widget.siteFlightStatus[siteKey] ?? false;
    }).length;
    final newSites = widget.sites.length - flownSites;
    
    // Only log significant changes or every 5 seconds
    final totalSites = widget.sites.length;
    final currentZoom = _currentZoom; // Use state variable instead of MapController
    final now = DateTime.now();
    final shouldLog = _lastRenderLog == null ||
        now.difference(_lastRenderLog!).inSeconds >= 5 ||
        totalSites != _lastSiteCount ||
        (currentZoom - _lastZoom).abs() > 0.5;

    if (shouldLog) {
      LoggingService.info('[MAP] ${widget.sites.length} sites, ${_airspaceLayers.isNotEmpty ? "airspaces loaded" : "no airspaces"}');
      _lastRenderLog = now;
      _lastSiteCount = totalSites;
      _lastZoom = currentZoom;
    }

    // Track marker creation time
    final markerStopwatch = Stopwatch()..start();
    final userMarkers = _buildUserLocationMarker();
    final siteMarkers = _buildSiteMarkers();
    markerStopwatch.stop();

    // Build the widget tree
    final mapWidget = Stack(
      children: [
        // FlutterMap with native click handling for airspace tooltip
        MouseRegion(
          onHover: (event) => _handleHover(event.position),
          onExit: (_) => _clearHover(),
          child: fm.FlutterMap(
            mapController: _mapController,
            options: fm.MapOptions(
              initialCenter: _getInitialCenter(),
              initialZoom: widget.initialZoom,
              minZoom: 3.0,
              maxZoom: widget.mapProvider.maxZoom.toDouble(),
              onMapReady: _onMapReady,
              onMapEvent: _onMapEvent,
              onPositionChanged: (position, hasGesture) {
                // Update current zoom when map position changes
                setState(() {
                  _currentZoom = position.zoom ?? widget.initialZoom;
                });
              },
              interactionOptions: const fm.InteractionOptions(
                flags: fm.InteractiveFlag.all,
              ),
              onTap: (tapPosition, point) {
                // Handle airspace tooltip on click with proper coordinates
                _handleAirspaceInteraction(tapPosition.global, point);

                // Clear search when tapping the map
                if (widget.searchQuery.isNotEmpty) {
                  widget.onSearchChanged('');
                }
              },
            ),
            children: [
              // Map tiles layer
              fm.TileLayer(
                urlTemplate: widget.mapProvider.urlTemplate,
                userAgentPackageName: 'com.example.free_flight_log_app',
                maxZoom: widget.mapProvider.maxZoom.toDouble(),
                tileProvider: MapTileProvider.createInstance(),
                errorTileCallback: MapTileProvider.getErrorCallback(),
              ),

              // Airspace overlay layers (between base map and markers)
              ..._airspaceLayers,

              // Highlighted airspace layer (on top of other airspaces)
              if (_highlightedPolygon != null) ...[
                fm.PolygonLayer(
                  polygons: [_highlightedPolygon!],
                ),
              ],

              // Site markers layer
              fm.MarkerLayer(
                markers: [
                  ...userMarkers,
                  ...siteMarkers,
                ],
              ),
            ],
          ),
        ),

        // Map overlays
        _buildAttribution(),
        _buildTopControlBar(),

        // Hover tooltip (lightweight, shows only when hovering)
        if (_hoveredAirspace != null && _hoverScreenPosition != null && !_showTooltip) ...[
          AirspaceHoverTooltip(
            airspace: _hoveredAirspace!,
            position: _hoverScreenPosition!,
            screenSize: MediaQuery.of(context).size,
          ),
        ],

        // Airspace info popup
        if (_showTooltip && _tooltipPosition != null) ...[
          AirspaceInfoPopup(
            airspaces: _tooltipAirspaces,
            position: _tooltipPosition!,
            screenSize: MediaQuery.of(context).size,
            onClose: _hideTooltip,
          ),
        ],

        // Stacked progress list for parallel loading operations
        if (_isLoadingSites || _isLoadingAirspace) ...[
          Positioned(
            top: 60,
            right: 16,
            child: Container(
              constraints: BoxConstraints(maxWidth: 220),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isLoadingSites) _buildLoadingItem(
                    'Loading sites',
                    _loadedSiteCount,
                    Icons.place,
                    Colors.green,
                  ),
                  if (_isLoadingSites && _isLoadingAirspace)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white.withOpacity(0.2),
                    ),
                  if (_isLoadingAirspace) _buildLoadingItem(
                    'Loading airspace',
                    _loadedAirspaceCount,
                    Icons.layers,
                    Colors.blue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    buildStopwatch.stop();

    // Only log slow builds (>20ms) to reduce noise
    final buildTime = buildStopwatch.elapsedMilliseconds;
    if (buildTime > 20) {
      LoggingService.structured('RENDER_PERF_SLOW', {
        'widget': 'NearbySitesMapWidget',
        'build_total_ms': buildTime,
        'marker_creation_ms': markerStopwatch.elapsedMilliseconds,
        'site_count': widget.sites.length,
        'airspace_layers': _airspaceLayers.length,
        'airspace_polygons': _airspaceLayers.isNotEmpty
            ? _airspaceLayers.fold<int>(0, (sum, layer) {
                if (layer is fm.PolygonLayer) {
                  return sum + layer.polygons.length;
                }
                return sum;
              })
            : 0,
        'user_markers': userMarkers.length,
        'site_markers': siteMarkers.length,
      });
    }

    return mapWidget;
  }

  /// Convert numeric type code to string type for filtering compatibility
  String _getTypeStringFromCode(int typeCode) {
    // Map numeric codes back to the string types used by the filtering system
    final typeMap = {
      0: 'UNKNOWN',
      1: 'A',
      2: 'B',
      3: 'C',
      4: 'CTR',
      5: 'E',
      6: 'TMA',
      7: 'G',
      8: 'CTR',
      9: 'TMA',
      10: 'CTA',
      11: 'R',
      12: 'P',
      13: 'CTR',  // ATZ mapped to CTR for filtering
      14: 'D',
      15: 'R',
      16: 'TMA',
      17: 'CTR',
      18: 'R',
      19: 'P',
      20: 'D',
      21: 'TMA',
      22: 'CTA',
      23: 'CTA',
      24: 'CTA',
      25: 'CTA',
      26: 'CTA',
    };

    return typeMap[typeCode] ?? 'UNKNOWN';
  }

  /// Build individual loading item for the stacked progress list
  Widget _buildLoadingItem(String label, int? count, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Icon indicator
          Icon(
            icon,
            size: 16,
            color: iconColor.withOpacity(0.8),
          ),
          const SizedBox(width: 8),
          // Loading spinner
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
              strokeCap: StrokeCap.round,
            ),
          ),
          const SizedBox(width: 10),
          // Text label
          Expanded(
            child: Text(
              count != null ? '$label ($count)' : '$label...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}