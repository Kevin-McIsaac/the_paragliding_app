import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/paragliding_site.dart';
import '../../services/logging_service.dart';
import 'common/base_map_widget.dart';

/// Enhanced map widget for displaying nearby sites
/// Extends BaseMapWidget to reuse common functionality
class NearbySitesMapEnhanced extends BaseMapWidget {
  final LatLng? userLocation;
  final Function(ParaglidingSite)? onSiteSelected;
  final VoidCallback? onLocationRequest;
  final bool showUserLocation;

  const NearbySitesMapEnhanced({
    super.key,
    this.userLocation,
    this.onSiteSelected,
    this.onLocationRequest,
    this.showUserLocation = true,
    super.height = 400,
  });

  @override
  State<NearbySitesMapEnhanced> createState() => _NearbySitesMapEnhancedState();
}

class _NearbySitesMapEnhancedState extends BaseMapState<NearbySitesMapEnhanced> {
  ParaglidingSite? _selectedSite;

  @override
  String get mapProviderKey => 'nearby_sites_map_provider';

  @override
  String get legendExpandedKey => 'nearby_sites_legend_expanded';

  @override
  String get mapContext => 'nearby_sites';

  @override
  int get siteLimit => 100; // Show more sites for nearby exploration

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

  @override
  List<Widget> buildAdditionalLayers() {
    final layers = <Widget>[];

    // User location marker
    if (widget.showUserLocation && widget.userLocation != null) {
      layers.add(
        MarkerLayer(
          markers: [
            Marker(
              point: widget.userLocation!,
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Accuracy circle
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue.withValues(alpha: 0.15),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                  ),
                  // Center dot
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue,
                      border: Border.all(
                        color: Colors.white,
                        width: 3,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return layers;
  }

  @override
  List<Widget> buildAdditionalLegendItems() {
    final items = <Widget>[];

    if (widget.showUserLocation) {
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withValues(alpha: 0.3),
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Your Location',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
      items.add(const SizedBox(height: 4));
    }

    return items;
  }

  List<Widget> _buildMapOverlays() {
    final overlays = <Widget>[];

    // Add location request button if no user location
    if (widget.userLocation == null && widget.onLocationRequest != null) {
      overlays.add(
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            mini: true,
            onPressed: widget.onLocationRequest,
            tooltip: 'Get current location',
            child: const Icon(Icons.my_location),
          ),
        ),
      );
    }

    // Add selected site info card
    if (_selectedSite != null) {
      overlays.add(
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Card(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedSite!.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectedSite = null;
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lat: ${_selectedSite!.latitude.toStringAsFixed(4)}, '
                    'Lon: ${_selectedSite!.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (_selectedSite!.hasFlights)
                    Text(
                      'Flights: ${_selectedSite!.flightCount}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.green,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.directions, size: 16),
                        label: const Text('Navigate'),
                        onPressed: () {
                          // TODO: Implement navigation
                          LoggingService.info('Navigate to site: ${_selectedSite!.name}');
                        },
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.info_outline, size: 16),
                        label: const Text('Details'),
                        onPressed: () {
                          widget.onSiteSelected?.call(_selectedSite!);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return overlays;
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