import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
import '../../services/airspace_identification_service.dart';
import '../widgets/airspace_tooltip_widget.dart';

class NearbySitesMapWidget extends StatefulWidget {
  final List<ParaglidingSite> sites;
  final Map<String, bool> siteFlightStatus;
  final Position? userPosition;
  final LatLng? centerPosition;
  final LatLngBounds? boundsToFit; // Optional bounds for exact map fitting
  final double initialZoom;
  final MapProvider mapProvider;
  final bool isLegendExpanded;
  final VoidCallback onToggleLegend;
  final Function(MapProvider) onMapProviderChanged;
  final Function(ParaglidingSite)? onSiteSelected;
  final Function(LatLngBounds)? onBoundsChanged;
  final String searchQuery;
  final Function(String) onSearchChanged;
  final VoidCallback onRefreshLocation;
  final bool isLocationLoading;
  final List<ParaglidingSite> searchResults;
  final bool isSearching;
  final Function(ParaglidingSite) onSearchResultSelected;
  
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
    required this.onMapProviderChanged,
    this.onSiteSelected,
    this.onBoundsChanged,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onRefreshLocation,
    required this.isLocationLoading,
    required this.searchResults,
    required this.isSearching,
    required this.onSearchResultSelected,
  });

  @override
  State<NearbySitesMapWidget> createState() => _NearbySitesMapWidgetState();
}

class _NearbySitesMapWidgetState extends State<NearbySitesMapWidget> {
  final MapController _mapController = MapController();
  final FocusNode _searchFocusNode = FocusNode();
  final AirspaceOverlayManager _airspaceManager = AirspaceOverlayManager.instance;
  
  // Airspace overlay state
  List<Widget> _airspaceLayers = [];
  bool _airspaceLoading = false;
  bool _airspaceEnabled = false;
  Set<int> _visibleAirspaceTypes = {};

  // Airspace tooltip state
  List<AirspaceData> _tooltipAirspaces = [];
  Offset? _tooltipPosition;
  bool _showTooltip = false;

  
  @override
  void initState() {
    super.initState();
    _loadAirspaceStatus();
    // Delay airspace loading until after the first frame to ensure MapController is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAirspaceLayers();
    });
  }


  @override
  void didUpdateWidget(NearbySitesMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Priority 1: Check if we should fit to exact bounds (for precise area display)
    if (widget.boundsToFit != null && 
        oldWidget.boundsToFit != widget.boundsToFit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.fitCamera(
          CameraFit.bounds(
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
    super.dispose();
  }

  void _onMapReady() {
    // Initial load of sites when map is ready
    if (widget.onBoundsChanged != null) {
      final bounds = _mapController.camera.visibleBounds;
      widget.onBoundsChanged!(bounds);
    }
  }
  
  void _onMapEvent(MapEvent event) {
    // React to all movement and zoom end events to reload sites and airspace
    if (event is MapEventMoveEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd ||
        event is MapEventScrollWheelZoom) {

      // Reload site data
      if (widget.onBoundsChanged != null) {
        final bounds = _mapController.camera.visibleBounds;
        widget.onBoundsChanged!(bounds);
      }

      // Reload airspace data for new viewport
      _loadAirspaceLayers();
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

      // Get current map center and zoom for GeoJSON request
      final center = _mapController.camera.center;
      final zoom = _mapController.camera.zoom;

      final layers = await _airspaceManager.buildEnabledOverlayLayers(
        center: center,
        zoom: zoom,
      );

      if (mounted) {
        // Get the visible airspace types from the service for legend filtering
        final visibleTypes = AirspaceGeoJsonService.instance.visibleAirspaceTypes;

        setState(() {
          _airspaceLayers = layers;
          _airspaceLoading = false;
          _visibleAirspaceTypes = visibleTypes;
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

    // Filter airspaces by enabled types only
    final enabledTypes = await OpenAipService.instance.getEnabledAirspaceTypes();
    final filteredAirspaces = allAirspaces.where((airspace) {
      // Convert numeric type to string type for filtering
      final typeString = _getTypeStringFromCode(airspace.type);
      return enabledTypes[typeString] ?? false;
    }).toList();

    // Sort airspaces by lower altitude limit (ascending)
    filteredAirspaces.sort((a, b) => a.getLowerAltitudeInFeet().compareTo(b.getLowerAltitudeInFeet()));

    if (filteredAirspaces.isNotEmpty) {
      // Check if clicking near the same position (toggle behavior)
      if (_showTooltip && _tooltipPosition != null && _isSimilarPosition(screenPosition, _tooltipPosition!)) {
        // Toggle: hide tooltip if clicking the same area
        _hideTooltip();
      } else {
        // Show tooltip immediately
        setState(() {
          _tooltipAirspaces = filteredAirspaces;
          _tooltipPosition = screenPosition;
          _showTooltip = true;
        });
      }
    } else {
      // No airspaces found, hide tooltip
      _hideTooltip();
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


  List<Marker> _buildSiteMarkers() {
    return widget.sites.map((site) {
      final siteKey = SiteUtils.createSiteKey(site.latitude, site.longitude);
      final hasFlights = widget.siteFlightStatus[siteKey] ?? false;
      
      return Marker(
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

  List<Marker> _buildUserLocationMarker() {
    if (widget.userPosition == null) return [];
    
    return [
      Marker(
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
                color: Colors.black.withValues(alpha: 0.3),
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
  Widget _buildMapControls() {
    return MapControls.buildMapControls(
      currentProvider: widget.mapProvider,
      onProviderChanged: widget.onMapProviderChanged,
    );
  }



  Widget _buildTopControlBar() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend (existing) - aligned to top
          Align(
            alignment: Alignment.topCenter,
            child: SiteMarkerUtils.buildCollapsibleMapLegend(
              context: context,
              isExpanded: widget.isLegendExpanded,
              onToggle: widget.onToggleLegend,
              legendItems: [
                // Site legend items
                SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.flownSiteColor, 'Local Sites (DB)'),
                const SizedBox(height: 4),
                SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.newSiteColor, 'API Sites'),

                // Airspace legend items (only when airspace is enabled)
                if (_airspaceEnabled) ...[
                  const SizedBox(height: 8),
                  // Airspace section title
                  const Text(
                    'Airspace Types',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Airspace type legend items with tooltips (filtered by visible types)
                  ...SiteMarkerUtils.buildAirspaceLegendItems(visibleTypes: _convertNumericTypesToStrings(_visibleAirspaceTypes)),
                ],
              ],
            ),
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
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
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
                              color: Colors.white.withValues(alpha: 0.05),
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '${widget.searchResults.length} site${widget.searchResults.length == 1 ? '' : 's'} found',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
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
                                color: Colors.white.withValues(alpha: 0.05),
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
                                    highlightColor: Colors.white.withValues(alpha: 0.1),
                                    splashColor: Colors.white.withValues(alpha: 0.05),
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
                                              color: Colors.deepPurple.withValues(alpha: 0.2),
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
                                                          color: Colors.white.withValues(alpha: 0.6),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    if (distanceText != null) ...[
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '• $distanceText',
                                                        style: TextStyle(
                                                          color: Colors.white.withValues(alpha: 0.5),
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
                                            color: Colors.white.withValues(alpha: 0.3),
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
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
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
          
          // Map controls (existing)
          _buildMapControls(),
        ],
      ),
    );
  }

  Widget _buildAttribution() {
    return MapControls.buildAttribution(provider: widget.mapProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Count flown vs new sites for logging
    final flownSites = widget.sites.where((site) {
      final siteKey = SiteUtils.createSiteKey(site.latitude, site.longitude);
      return widget.siteFlightStatus[siteKey] ?? false;
    }).length;
    final newSites = widget.sites.length - flownSites;
    
    LoggingService.structured('NEARBY_SITES_MAP_RENDER', {
      'local_site_count': flownSites,
      'api_site_count': newSites,
      'has_user_position': widget.userPosition != null,
      'has_center_position': widget.centerPosition != null,
      'initial_zoom': widget.initialZoom,
      'map_provider': widget.mapProvider.shortName,
      'airspace_layer_count': _airspaceLayers.length,
      'airspace_loading': _airspaceLoading,
    });

    return Stack(
      children: [
        // FlutterMap with native click handling for airspace tooltip
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _getInitialCenter(),
            initialZoom: widget.initialZoom,
            minZoom: 3.0,
            maxZoom: widget.mapProvider.maxZoom.toDouble(),
            onMapReady: _onMapReady,
            onMapEvent: _onMapEvent,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
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
                TileLayer(
                  urlTemplate: widget.mapProvider.urlTemplate,
                  userAgentPackageName: 'com.example.free_flight_log_app',
                  maxZoom: widget.mapProvider.maxZoom.toDouble(),
                  tileProvider: MapTileProvider.createInstance(),
                  errorTileCallback: MapTileProvider.getErrorCallback(),
                ),

                // Airspace overlay layers (between base map and markers)
                ..._airspaceLayers,

                // Site markers layer
                MarkerLayer(
                  markers: [
                    ..._buildUserLocationMarker(),
                    ..._buildSiteMarkers(),
                  ],
                ),
              ],
            ),

        // Map overlays
        _buildAttribution(),
        _buildTopControlBar(),

        // Airspace tooltip
        if (_showTooltip && _tooltipPosition != null)
          AirspaceTooltipWidget(
            airspaces: _tooltipAirspaces,
            position: _tooltipPosition!,
            screenSize: MediaQuery.of(context).size,
            onClose: _hideTooltip,
          ),
      ],
    );
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
}