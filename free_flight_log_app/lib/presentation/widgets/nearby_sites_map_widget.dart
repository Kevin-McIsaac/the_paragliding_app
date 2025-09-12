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

class NearbySitesMapWidget extends StatefulWidget {
  final List<ParaglidingSite> sites;
  final Map<String, bool> siteFlightStatus;
  final Position? userPosition;
  final LatLng? centerPosition;
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
  
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(NearbySitesMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If center position changed, move map to new location
    if (widget.centerPosition != null && 
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
                
                // Search results dropdown
                if (widget.searchResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    margin: const EdgeInsets.only(top: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xCC000000), // More transparent for better map visibility
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.searchResults.length,
                      itemBuilder: (context, index) {
                        final site = widget.searchResults[index];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          title: Text(
                            site.name,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: site.country != null
                              ? Text(
                                  site.country!.toUpperCase(),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                )
                              : null,
                          trailing: const Icon(
                            Icons.location_on,
                            color: Colors.white70,
                            size: 16,
                          ),
                          onTap: () => widget.onSearchResultSelected(site),
                        );
                      },
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
              // Dismiss any open bottom sheets when tapping the map
              Navigator.of(context).popUntil((route) => route.isFirst);
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