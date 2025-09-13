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
import 'airspace_controls_widget.dart';

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
  List<TileLayer> _airspaceLayers = [];
  bool _airspaceLoading = false;
  bool _airspaceControlsExpanded = false;
  
  @override
  void initState() {
    super.initState();
    _loadAirspaceLayers();
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
    // React to all movement and zoom end events to reload sites
    if (event is MapEventMoveEnd || 
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd ||
        event is MapEventScrollWheelZoom) {
      
      if (widget.onBoundsChanged != null) {
        final bounds = _mapController.camera.visibleBounds;
        widget.onBoundsChanged!(bounds);
      }
    }
  }
  
  /// Load airspace overlay layers based on user preferences
  Future<void> _loadAirspaceLayers() async {
    if (_airspaceLoading) return;
    
    setState(() {
      _airspaceLoading = true;
    });
    
    try {
      final layers = await _airspaceManager.buildEnabledOverlayLayers();
      
      if (mounted) {
        setState(() {
          _airspaceLayers = layers;
          _airspaceLoading = false;
        });
        
        LoggingService.structured('AIRSPACE_LAYERS_LOADED', {
          'layer_count': layers.length,
          'widget_mounted': mounted,
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
  
  /// Refresh airspace layers when settings change
  void refreshAirspaceLayers() {
    _loadAirspaceLayers();
  }
  
  /// Toggle airspace controls expanded state
  void _toggleAirspaceControls() {
    setState(() {
      _airspaceControlsExpanded = !_airspaceControlsExpanded;
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
                SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.flownSiteColor, 'Local Sites (DB)'),
                const SizedBox(height: 4),
                SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.newSiteColor, 'API Sites'),
              ],
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Airspace controls - still causing mouse tracker issues despite fixes
          // TODO: Investigate widget hierarchy and layout constraints causing the issue
          // Align(
          //   alignment: Alignment.topCenter,
          //   child: AirspaceControlsWidget(
          //     isExpanded: _airspaceControlsExpanded,
          //     onToggleExpanded: _toggleAirspaceControls,
          //     onLayersChanged: refreshAirspaceLayers,
          //   ),
          // ),
          
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
      ],
    );
  }
}