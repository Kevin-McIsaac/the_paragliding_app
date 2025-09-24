import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
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
import '../widgets/map_filter_fab.dart';
import '../widgets/map_legend_widget.dart';
import '../widgets/common/map_loading_overlay.dart';
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
  final bool airspaceEnabled; // Add prop for airspace enabled state
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
    this.airspaceEnabled = true, // Default to true if not provided
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
  // Remove internal _airspaceEnabled state - use widget.airspaceEnabled instead

  // Airspace tooltip state
  List<AirspaceData> _tooltipAirspaces = [];
  Offset? _tooltipPosition;
  bool _showTooltip = false;

  // Selected airspace state
  final List<fm.Polygon> _highlightedPolygons = [];

  // Debouncing for render logs
  DateTime? _lastRenderLog;
  int _lastSiteCount = -1;
  double _lastZoom = -1;

  // Track current zoom level to avoid accessing MapController in build
  late double _currentZoom;

  // Unified map update debouncing
  Timer? _mapUpdateDebouncer;
  Timer? _performanceMonitorThrottle;
  fm.LatLngBounds? _lastProcessedBounds;
  static const double _boundsThreshold = 0.001;
  static const int _debounceDurationMs = 750;

  // Cached markers to avoid recreation on every build
  List<fm.Marker>? _cachedSiteMarkers;
  String? _cachedSiteMarkersKey;

  // Separate loading states for parallel operations
  bool _isLoadingSites = false;
  bool _isLoadingAirspace = false;
  int? _loadedSiteCount;
  int? _loadedAirspaceCount;

  
  @override
  void initState() {
    super.initState();
    _currentZoom = widget.initialZoom; // Initialize with the initial zoom
    // Only load airspace if enabled
    if (widget.airspaceEnabled) {
      _loadAirspaceStatus();
      // Delay airspace loading until after the first frame to ensure MapController is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadAirspaceLayers();
      });
    }
  }


  @override
  void didUpdateWidget(NearbySitesMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Diagnostic logging for rebuild triggers
    final List<String> changes = [];
    if (oldWidget.sites != widget.sites) {
      changes.add('sites(${oldWidget.sites.length}→${widget.sites.length})');
    }
    if (oldWidget.siteFlightStatus != widget.siteFlightStatus) {
      changes.add('siteFlightStatus');
    }
    if (oldWidget.userPosition != widget.userPosition) {
      changes.add('userPosition');
    }
    if (oldWidget.centerPosition != widget.centerPosition) {
      changes.add('centerPosition');
    }
    if (oldWidget.searchQuery != widget.searchQuery) {
      changes.add('searchQuery(${oldWidget.searchQuery}→${widget.searchQuery})');
    }
    if (oldWidget.airspaceEnabled != widget.airspaceEnabled) {
      changes.add('airspaceEnabled(${oldWidget.airspaceEnabled}→${widget.airspaceEnabled})');
    }
    if (oldWidget.filterUpdateCounter != widget.filterUpdateCounter) {
      changes.add('filterUpdateCounter(${oldWidget.filterUpdateCounter}→${widget.filterUpdateCounter})');
    }

    if (changes.isNotEmpty) {
      LoggingService.structured('MAP_WIDGET_UPDATE', {
        'changes': changes.join(', '),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    // Track site count changes
    if (oldWidget.sites != widget.sites) {
      setState(() {
        _loadedSiteCount = widget.sites.length;
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
        oldWidget.airspaceEnabled != widget.airspaceEnabled ||
        oldWidget.maxAltitudeFt != widget.maxAltitudeFt ||
        oldWidget.filterUpdateCounter != widget.filterUpdateCounter) {
      // Reload overlays with new filter settings
      if (widget.airspaceEnabled) {
        _loadAirspaceLayers();
      } else {
        // Clear airspace layers if disabled
        setState(() {
          _airspaceLayers = [];
          _airspaceLoading = false;
        });
      }
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
        // Load airspace and sites data for the new bounds
        Future.delayed(const Duration(milliseconds: 100), () {
          _loadVisibleData();
        });
      });
    }
    // Priority 2: Fallback to center/zoom for normal navigation
    else if (widget.centerPosition != null &&
             oldWidget.centerPosition != widget.centerPosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(widget.centerPosition!, widget.initialZoom);
        // Load airspace and sites data for the new location
        // Add slight delay to ensure map has finished moving
        Future.delayed(const Duration(milliseconds: 100), () {
          _loadVisibleData();
        });
      });
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _mapController.dispose();
    _mapUpdateDebouncer?.cancel();
    _performanceMonitorThrottle?.cancel();
    super.dispose();
  }

  void _onMapReady() {
    // Initial load of all data when map is ready
    _loadVisibleData();
  }
  
  void _onMapEvent(fm.MapEvent event) {
    // Throttle frame performance monitoring during map interactions to reduce overhead
    if (event is fm.MapEventMove || event is fm.MapEventFlingAnimation) {
      // Cancel any existing throttle timer
      _performanceMonitorThrottle?.cancel();

      // Throttle frame monitoring to once per 200ms to reduce overhead
      _performanceMonitorThrottle = Timer(const Duration(milliseconds: 200), () {
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
      });
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
    LoggingService.info('Loading visible data for bounds: ${bounds.west.toStringAsFixed(2)},${bounds.south.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)},${bounds.north.toStringAsFixed(2)}, zoom: ${_currentZoom.toStringAsFixed(1)}');

    // Set loading states before starting parallel loads
    setState(() {
      _isLoadingSites = widget.sitesEnabled;
      _isLoadingAirspace = widget.airspaceEnabled; // Use prop instead of internal state
      _loadedSiteCount = null;
      _loadedAirspaceCount = null;
    });

    // Build list of futures to load in parallel
    final futures = <Future>[];

    if (widget.sitesEnabled) {
      futures.add(
        _loadSitesForBounds(bounds).then((_) {
          // Loading state is cleared by the parent's onBoundsChanged callback
        }),
      );
    }

    if (widget.airspaceEnabled) {
      futures.add(
        _loadAirspaceLayers().then((_) {
          setState(() {
            _isLoadingAirspace = false;
          });
        }),
      );
    }

    // Load in parallel if there are any futures
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
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

    // Only notify parent to track bounds when sites are enabled
    // This prevents unnecessary pipeline execution when sites are disabled
    if (widget.onBoundsChanged != null) {
      widget.onBoundsChanged!(bounds);
    }
  }

  /// Load airspace overlay layers based on user preferences and current map view
  Future<void> _loadAirspaceLayers() async {
    if (_airspaceLoading || !widget.airspaceEnabled) return;

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
          // visibleTypes tracked internally, not stored
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
      // No longer need to track internal state - using widget.airspaceEnabled
      // Just load the status for display purposes
      await OpenAipService.instance.isAirspaceEnabled();
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

  /// Handle click for airspace identification
  void _handleAirspaceInteraction(Offset screenPosition, LatLng mapPoint) async {
    if (!widget.airspaceEnabled) return;

    // Identify airspaces at the point (using map coordinates from FlutterMap)
    final allAirspaces = AirspaceIdentificationService.instance.identifyAirspacesAtPoint(mapPoint);

    // Update filter status for all identified airspaces
    await _updateAirspaceFilterStatus(allAirspaces);

    // Filter to only visible airspaces (not hidden by current filter settings)
    final visibleAirspaces = allAirspaces.where((airspace) => !airspace.isCurrentlyFiltered).toList();

    // Sort visible airspaces by lower altitude limit (ascending), then by upper altitude limit (ascending)
    visibleAirspaces.sort((a, b) {
      int lowerCompare = a.getLowerAltitudeInFeet().compareTo(b.getLowerAltitudeInFeet());
      if (lowerCompare != 0) return lowerCompare;
      return a.getUpperAltitudeInFeet().compareTo(b.getUpperAltitudeInFeet());
    });

    if (allAirspaces.isNotEmpty) {
      // Check if clicking near the same position (toggle behavior)
      if (_showTooltip && _tooltipPosition != null && _isSimilarPosition(screenPosition, _tooltipPosition!)) {
        // Toggle: hide tooltip if clicking the same area
        _hideTooltip();
      } else if (visibleAirspaces.isNotEmpty) {
        // Get the lowest altitude visible airspace for highlighting
        final lowestAirspace = visibleAirspaces.first;
        final lowestAltitude = lowestAirspace.getLowerAltitudeInFeet();

        // Find all visible airspaces with the same lowest altitude
        final airspacesToHighlight = visibleAirspaces.where((airspace) =>
          airspace.getLowerAltitudeInFeet() == lowestAltitude).toList();

        // Store selected airspace for reference
        // Track selected airspace for highlighting

        // Clear existing highlights before adding new ones
        _highlightedPolygons.clear();

        // Find all clipped polygons at the click point
        final allClickedPolygons = _findAllClickedPolygonPoints(mapPoint);

        // Highlight all airspaces with the same lowest altitude
        for (int i = 0; i < airspacesToHighlight.length; i++) {
          final airspace = airspacesToHighlight[i];
          // Use indexed polygon from the found list, or null if not enough polygons
          final polygonPoints = i < allClickedPolygons.length ? allClickedPolygons[i] : null;
          _createHighlightedPolygon(airspace, polygonPoints, i);
        }

        setState(() {
          _tooltipAirspaces = allAirspaces; // Show all airspaces (including filtered)
          _tooltipPosition = screenPosition;
          _showTooltip = true;
        });
      } else {
        // Only filtered airspaces found - show tooltip but no highlighting
        setState(() {
          _tooltipAirspaces = allAirspaces; // Show all airspaces (including filtered)
          _tooltipPosition = screenPosition;
          _showTooltip = true;
        });
        _clearSelection(); // Clear any existing highlights
      }
    } else {
      // No airspaces found, hide tooltip and clear selection
      _hideTooltip();
      _clearSelection();
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
      final isClassFiltered = excludedClasses[airspace.icaoClass] == true;
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
    _clearSelection();
  }

  /// Clear the selected airspace and highlighted polygons
  void _clearSelection() {
    if (mounted) {
      setState(() {
        // Clear selected airspace
        _highlightedPolygons.clear();
      });
    }
  }

  /// Test if a point is inside a polygon using ray casting algorithm
  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    bool inside = false;
    int len = polygon.length;
    for (int i = 0, j = len - 1; i < len; j = i++) {
      if ((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude) &&
          point.longitude < (polygon[j].longitude - polygon[i].longitude) *
          (point.latitude - polygon[i].latitude) /
          (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Find all clipped polygon points that contain the click point from rendered layers
  List<List<LatLng>> _findAllClickedPolygonPoints(LatLng clickPoint) {
    final foundPolygons = <List<LatLng>>[];
    // Iterate through rendered airspace layers
    for (final layer in _airspaceLayers) {
      if (layer is fm.PolygonLayer) {
        for (final polygon in layer.polygons) {
          // Check if this polygon contains the click point
          if (_pointInPolygon(clickPoint, polygon.points)) {
            foundPolygons.add(polygon.points); // Add all clipped polygon points
          }
        }
      }
    }
    return foundPolygons;
  }

  /// Create a highlighted polygon for the selected airspace and add it to the list
  void _createHighlightedPolygon(AirspaceData airspace, [List<LatLng>? polygonPoints, int labelIndex = 0]) {
    // Use provided points or fallback to full polygon from identification service
    final points = polygonPoints ??
        AirspaceIdentificationService.instance.getPolygonForAirspace(airspace);
    if (points == null || points.isEmpty) return;

    // Get the airspace style
    final style = AirspaceGeoJsonService.instance.getStyleForAirspace(airspace);

    // Calculate enhanced opacity (2x with minimum 0.3 for visibility)
    final baseOpacity = style.fillColor.a / 255.0;
    final enhancedOpacity = math.max(0.3, (baseOpacity * 2.0).clamp(0.0, 0.6));

    // For multiple labels, add an index indicator to distinguish them
    final labelSuffix = labelIndex > 0 ? ' [${labelIndex + 1}]' : '';

    final highlightedPolygon = fm.Polygon(
      points: points,
      color: style.fillColor.withValues(alpha: enhancedOpacity),
      borderColor: style.borderColor,
      borderStrokeWidth: style.borderWidth * 1.5,
      // Add label with airspace information and index suffix
      label: '${airspace.name}$labelSuffix\n'
             '${airspace.type.abbreviation}'
             ', ${airspace.icaoClass.displayName}'
             ', ${airspace.lowerAltitude} - ${airspace.upperAltitude}',
      labelStyle: const TextStyle(
        color: Colors.black,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
      // Use centroid placement for all labels
      labelPlacementCalculator: const fm.PolygonLabelPlacementCalculator.centroid(),
    );

    setState(() {
      _highlightedPolygons.add(highlightedPolygon);
    });
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

    // Create cache key from sites data and flight status
    final cacheKey = '${widget.sites.length}_${widget.siteFlightStatus.length}_${widget.sitesEnabled}';

    // Return cached markers if data hasn't changed
    if (_cachedSiteMarkersKey == cacheKey && _cachedSiteMarkers != null) {
      LoggingService.debug('[PERFORMANCE] Using cached site markers');
      return _cachedSiteMarkers!;
    }

    LoggingService.debug('[PERFORMANCE] Building new site markers (cache miss)');

    // Build new markers
    _cachedSiteMarkers = widget.sites.map((site) {
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

    // Update cache key
    _cachedSiteMarkersKey = cacheKey;

    return _cachedSiteMarkers!;
  }

  // All sites are now subject to clustering
  List<fm.Marker> _buildAllSiteMarkers() {
    if (!widget.sitesEnabled) return [];

    // Create simple markers for all sites - clustering will handle grouping
    return widget.sites.map((site) {
      final siteKey = SiteUtils.createSiteKey(site.latitude, site.longitude);
      final isFlownSite = widget.siteFlightStatus[siteKey] ?? false;
      // Create simplified markers for better performance with large datasets
      return fm.Marker(
        point: LatLng(site.latitude, site.longitude),
        width: 40,  // Smaller size for better performance
        height: 50,
        child: GestureDetector(
          onTap: () {
            widget.onSiteSelected?.call(site);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon colored based on flown status - new sites are green
              SiteMarkerUtils.buildSiteMarkerIcon(
                color: isFlownSite ? SiteMarkerUtils.flownSiteColor : Colors.green,
              ),
              // Only show name at higher zoom levels (handled by clustering)
              if (_currentZoom > 10)
                SiteMarkerUtils.buildSiteLabel(
                  siteName: site.name,
                ),
            ],
          ),
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
                color: Colors.black.withValues(alpha:0.3),
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
            isExpanded: widget.isLegendExpanded,
            onToggleExpanded: widget.onToggleLegend,
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
                      color: Colors.black.withValues(alpha:0.85),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha:0.1),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.4),
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
                              color: Colors.white.withValues(alpha:0.05),
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withValues(alpha:0.1),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '${widget.searchResults.length} site${widget.searchResults.length == 1 ? '' : 's'} found',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha:0.7),
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
                                color: Colors.white.withValues(alpha:0.05),
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
                                    highlightColor: Colors.white.withValues(alpha:0.1),
                                    splashColor: Colors.white.withValues(alpha:0.05),
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
                                              color: Colors.deepPurple.withValues(alpha:0.2),
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
                                                          color: Colors.white.withValues(alpha:0.6),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    if (distanceText != null) ...[
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '• $distanceText',
                                                        style: TextStyle(
                                                          color: Colors.white.withValues(alpha:0.5),
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
                                            color: Colors.white.withValues(alpha:0.3),
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
                      color: Colors.black.withValues(alpha:0.85),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha:0.1),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.4),
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

    
    // Only log significant changes or every 5 seconds
    final totalSites = widget.sites.length;
    final currentZoom = _currentZoom; // Use state variable instead of MapController
    final now = DateTime.now();
    final shouldLog = _lastRenderLog == null ||
        now.difference(_lastRenderLog!).inSeconds >= 5 ||
        totalSites != _lastSiteCount ||
        (currentZoom - _lastZoom).abs() > 0.5;

    if (shouldLog) {
      LoggingService.info('[MAP] ${widget.sites.length} sites, ${_airspaceLayers.isNotEmpty ? "airspaces loaded" : "no airspaces"}, zoom: ${_currentZoom.toStringAsFixed(1)}');
      _lastRenderLog = now;
      _lastSiteCount = totalSites;
      _lastZoom = currentZoom;
    }

    // Track marker creation time
    final markerStopwatch = Stopwatch()..start();
    final userMarkers = _buildUserLocationMarker();
    // Note: All markers are now built together and clustered
    // _buildAllSiteMarkers() is called directly in the clustering layer
    markerStopwatch.stop();

    // Build the widget tree
    final mapWidget = Stack(
      children: [
        // FlutterMap with native click handling for airspace tooltip
        // Wrapped in RepaintBoundary to isolate map repaints from widget tree
        RepaintBoundary(
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
                // Track zoom without rebuilding widget
                // Only update internal state, no setState needed
                _currentZoom = position.zoom;
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
              if (_highlightedPolygons.isNotEmpty) ...[
                fm.PolygonLayer(
                  polygons: _highlightedPolygons,
                ),
              ],

              // Clustered sites layer (now includes all sites)
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 100, // Reduced from 180 - less aggressive clustering
                  size: const Size(40, 40),
                  disableClusteringAtZoom: 11, // Increased from 10 - show individuals sooner
                  markers: _buildAllSiteMarkers(),
                  builder: (context, markers) {
                    // Check if any marker in the cluster is a flown site
                    bool hasFlownSite = false;
                    for (final marker in markers) {
                      final markerPoint = marker.point;
                      final siteKey = SiteUtils.createSiteKey(markerPoint.latitude, markerPoint.longitude);
                      if (widget.siteFlightStatus[siteKey] ?? false) {
                        hasFlownSite = true;
                        break;
                      }
                    }

                    // Simplified cluster marker for performance
                    final count = markers.length;
                    final displayText = count > 999 ? '999+' : count.toString();

                    return Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasFlownSite
                            ? SiteMarkerUtils.flownSiteColor.withValues(alpha: 0.9)
                            : Colors.green.withValues(alpha: 0.9),
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
                  },
                ),
              ),

              // User location marker layer
              if (userMarkers.isNotEmpty)
                fm.MarkerLayer(
                  markers: userMarkers,
                ),
            ],
          ),
        ),

        // Map overlays - must remain direct children of Stack due to Positioned widgets
        _buildAttribution(),
        _buildTopControlBar(),


        // Airspace info popup
        if (_showTooltip && _tooltipPosition != null) ...[
          AirspaceInfoPopup(
            airspaces: _tooltipAirspaces,
            position: _tooltipPosition!,
            screenSize: MediaQuery.of(context).size,
            onClose: _hideTooltip,
          ),
        ],

        // Loading overlay for parallel loading operations
        if (_isLoadingSites || _isLoadingAirspace)
          MapLoadingOverlay.multiple(
            items: [
              if (_isLoadingSites)
                MapLoadingItem(
                  label: 'Loading sites',
                  icon: Icons.place,
                  iconColor: Colors.green,
                  count: _loadedSiteCount,
                ),
              if (_isLoadingAirspace)
                MapLoadingItem(
                  label: 'Loading airspace',
                  icon: Icons.layers,
                  iconColor: Colors.blue,
                  count: _loadedAirspaceCount,
                ),
            ],
          ),
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
        'zoom': _currentZoom,
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
        'site_markers': widget.sites.length,
      });
    }

    return mapWidget;
  }


}