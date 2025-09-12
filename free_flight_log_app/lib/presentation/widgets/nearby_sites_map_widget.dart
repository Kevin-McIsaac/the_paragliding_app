import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../services/logging_service.dart';
import '../../utils/site_marker_utils.dart';
import '../../presentation/screens/nearby_sites_screen.dart';

class NearbySitesMapWidget extends StatefulWidget {
  final List<Site> localSites;
  final List<ParaglidingSite> apiSites;
  final Position? userPosition;
  final LatLng? centerPosition;
  final double initialZoom;
  final MapProvider mapProvider;
  final bool isLegendExpanded;
  final VoidCallback onToggleLegend;
  final Function(MapProvider) onMapProviderChanged;
  final Function(Site)? onSiteSelected;
  final Function(ParaglidingSite)? onApiSiteSelected;
  final Function(LatLngBounds)? onBoundsChanged;
  
  const NearbySitesMapWidget({
    super.key,
    required this.localSites,
    required this.apiSites,
    this.userPosition,
    this.centerPosition,
    this.initialZoom = 10.0,
    required this.mapProvider,
    required this.isLegendExpanded,
    required this.onToggleLegend,
    required this.onMapProviderChanged,
    this.onSiteSelected,
    this.onApiSiteSelected,
    this.onBoundsChanged,
  });

  @override
  State<NearbySitesMapWidget> createState() => _NearbySitesMapWidgetState();
}

class _NearbySitesMapWidgetState extends State<NearbySitesMapWidget> {
  final MapController _mapController = MapController();
  
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
    if (widget.localSites.isNotEmpty) {
      double avgLat = widget.localSites.map((s) => s.latitude).reduce((a, b) => a + b) / widget.localSites.length;
      double avgLng = widget.localSites.map((s) => s.longitude).reduce((a, b) => a + b) / widget.localSites.length;
      return LatLng(avgLat, avgLng);
    }
    
    // Fallback to a reasonable default (central Europe)
    return const LatLng(47.0, 8.0);
  }

  List<Marker> _buildLocalSiteMarkers() {
    return widget.localSites.map((site) {
      final bool hasFlights = site.flightCount != null && site.flightCount! > 0;
      
      return Marker(
        point: LatLng(site.latitude, site.longitude),
        width: 140,
        height: 80,
        child: GestureDetector(
          onTap: () {
            _showLocalSiteDetails(site);
            widget.onSiteSelected?.call(site);
          },
          child: SiteMarkerUtils.buildDisplaySiteMarker(
            position: LatLng(site.latitude, site.longitude),
            siteName: site.name,
            isFlownSite: hasFlights,
            flightCount: site.flightCount,
            tooltip: '${site.name}${site.flightCount != null ? ' (${site.flightCount} flights)' : ''}',
          ).child,
        ),
      );
    }).toList();
  }

  List<Marker> _buildApiSiteMarkers() {
    return widget.apiSites.map((site) {
      return Marker(
        point: LatLng(site.latitude, site.longitude),
        width: 140,
        height: 80,
        child: GestureDetector(
          onTap: () {
            _showApiSiteDetails(site);
            widget.onApiSiteSelected?.call(site);
          },
          child: SiteMarkerUtils.buildDisplaySiteMarker(
            position: LatLng(site.latitude, site.longitude),
            siteName: site.name,
            isFlownSite: false, // API sites are always "new"
            flightCount: null,
            tooltip: site.name,
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

  void _showLocalSiteDetails(Site site) {
    widget.onSiteSelected?.call(site);
  }

  void _showApiSiteDetails(ParaglidingSite site) {
    widget.onApiSiteSelected?.call(site);
  }



  // Add methods for map controls, legend, and attribution
  Widget _buildMapControls() {
    return Column(
      children: [
        // Map provider selector
        Container(
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
          child: PopupMenuButton<MapProvider>(
            tooltip: 'Change Maps',
            onSelected: widget.onMapProviderChanged,
            initialValue: widget.mapProvider,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getProviderIcon(widget.mapProvider),
                    size: 16,
                    color: Colors.white,
                  ),
                  const Icon(
                    Icons.arrow_drop_down, 
                    size: 16,
                    color: Colors.white,
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
                      _getProviderIcon(provider),
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
        ),
      ],
    );
  }

  IconData _getProviderIcon(MapProvider provider) {
    switch (provider) {
      case MapProvider.openStreetMap:
        return Icons.map;
      case MapProvider.googleSatellite:
        return Icons.satellite_alt;
      case MapProvider.esriWorldImagery:
        return Icons.terrain;
    }
  }

  Widget _buildLegend() {
    final legendItems = <Widget>[
      SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.flownSiteColor, 'Flown Sites'),
      const SizedBox(height: 4),
      SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.newSiteColor, 'New Sites'),
    ];
    
    return Positioned(
      top: 8,
      left: 8,
      child: SiteMarkerUtils.buildCollapsibleMapLegend(
        context: context,
        isExpanded: widget.isLegendExpanded,
        onToggle: widget.onToggleLegend,
        legendItems: legendItems,
      ),
    );
  }

  Widget _buildAttribution() {
    return Positioned(
      bottom: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[900]!.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: GestureDetector(
          onTap: () async {
            // Open appropriate copyright page based on provider
            String url;
            switch (widget.mapProvider) {
              case MapProvider.openStreetMap:
                url = 'https://www.openstreetmap.org/copyright';
                break;
              case MapProvider.googleSatellite:
                url = 'https://www.google.com/permissions/geoguidelines/';
                break;
              case MapProvider.esriWorldImagery:
                url = 'https://www.esri.com/en-us/legal/terms/full-master-agreement';
                break;
            }
            final uri = Uri.parse(url);
            try {
              await launchUrl(uri, mode: LaunchMode.platformDefault);
            } catch (e) {
              LoggingService.error('NearbySitesMapWidget: Could not launch URL', e);
            }
          },
          child: Text(
            widget.mapProvider.attribution,
            style: const TextStyle(fontSize: 8, color: Colors.white70),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    LoggingService.structured('NEARBY_SITES_MAP_RENDER', {
      'local_site_count': widget.localSites.length,
      'api_site_count': widget.apiSites.length,
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
            ),
            
            // Site markers layer
            MarkerLayer(
              markers: [
                ..._buildUserLocationMarker(),
                ..._buildLocalSiteMarkers(),
                ..._buildApiSiteMarkers(),
              ],
            ),
          ],
        ),
        
        // Map overlays
        _buildAttribution(),
        Positioned(
          top: 8,
          right: 8,
          child: _buildMapControls(),
        ),
        _buildLegend(),
      ],
    );
  }
}