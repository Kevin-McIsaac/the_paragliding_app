import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/paragliding_site.dart';
import '../../services/logging_service.dart';
import '../../utils/site_marker_utils.dart';
import '../../presentation/screens/nearby_sites_screen.dart';

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
    if (widget.sites.isNotEmpty) {
      double avgLat = widget.sites.map((s) => s.latitude).reduce((a, b) => a + b) / widget.sites.length;
      double avgLng = widget.sites.map((s) => s.longitude).reduce((a, b) => a + b) / widget.sites.length;
      return LatLng(avgLat, avgLng);
    }
    
    // Fallback to a reasonable default (central Europe)
    return const LatLng(47.0, 8.0);
  }

  /// Create a unique key for site flight status lookup
  String _createSiteKey(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
  }

  List<Marker> _buildSiteMarkers() {
    return widget.sites.map((site) {
      final siteKey = _createSiteKey(site.latitude, site.longitude);
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
      SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.flownSiteColor, 'Local Sites (DB)'),
      const SizedBox(height: 4),
      SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.newSiteColor, 'API Sites'),
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
    // Count flown vs new sites for logging
    final flownSites = widget.sites.where((site) {
      final siteKey = _createSiteKey(site.latitude, site.longitude);
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