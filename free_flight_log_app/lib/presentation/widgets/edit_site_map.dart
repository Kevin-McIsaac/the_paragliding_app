import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/site.dart';
import '../../services/logging_service.dart';
import '../../utils/map_constants.dart';
import 'common/base_map_widget.dart';

/// Specialized map widget for site editing
/// Extends BaseMapWidget to reuse common functionality
class EditSiteMap extends BaseMapWidget {
  final Site? existingSite;
  final LatLng initialLocation;
  final Function(LatLng) onLocationSelected;
  final VoidCallback? onMapReady;

  const EditSiteMap({
    super.key,
    this.existingSite,
    required this.initialLocation,
    required this.onLocationSelected,
    this.onMapReady,
    super.height = 500,
  });

  @override
  State<EditSiteMap> createState() => _EditSiteMapState();
}

class _EditSiteMapState extends BaseMapState<EditSiteMap> {
  late LatLng _selectedLocation;
  late DragMarker _dragMarker;

  @override
  String get mapProviderKey => 'edit_site_map_provider';

  @override
  String get legendExpandedKey => 'edit_site_legend_expanded';

  @override
  String get mapContext => 'edit_site';

  @override
  int get siteLimit => MapConstants.defaultSiteLimit; // Standard site limit

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _updateDragMarker();
  }

  void _updateDragMarker() {
    _dragMarker = DragMarker(
      key: ValueKey(_selectedLocation),
      point: _selectedLocation,
      size: const Size(85, 85),
      offset: const Offset(0, -42.5),
      builder: (_, point, __) {
        return Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withValues(alpha: 0.3),
                border: Border.all(
                  color: Colors.blue,
                  width: 2,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Colors.blue,
                    size: 30,
                  ),
                  // Small indicator showing it's draggable
                  Positioned(
                    bottom: 2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue, width: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: const Text(
                'Drag to move',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
      onDragEnd: (_, point) {
        setState(() {
          _selectedLocation = point;
        });
        widget.onLocationSelected(point);
        LoggingService.info('EditSiteMap: Location selected: '
            '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}');
      },
    );
  }

  @override
  void onMapReady() {
    super.onMapReady();
    widget.onMapReady?.call();

    // Center map on selected location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        mapController.move(_selectedLocation, 13.0);
      }
    });
  }

  @override
  void onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
      _updateDragMarker();
    });
    widget.onLocationSelected(point);

    // Animate to the new location
    mapController.move(point, mapController.camera.zoom);
  }

  @override
  List<Widget> buildAdditionalLayers() {
    return [
      // Draggable marker for site location
      DragMarkers(
        markers: [_dragMarker],
      ),
    ];
  }

  @override
  List<Widget> buildAdditionalLegendItems() {
    return [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.withValues(alpha: 0.3),
              border: Border.all(color: Colors.blue, width: 1),
            ),
            child: const Icon(
              Icons.location_on,
              color: Colors.blue,
              size: 10,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Site Location',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        'Tap or drag to set location',
        style: TextStyle(
          fontSize: 8,
          fontStyle: FontStyle.italic,
          color: Colors.white70,
        ),
      ),
    ];
  }

  List<Widget> _buildCoordinatesOverlay() {
    final overlays = <Widget>[];

    // Add instructions overlay at the bottom
    overlays.add(
      Positioned(
        bottom: 8,
        left: 8,
        right: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.info_outline,
                size: 14,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                'Lat: ${_selectedLocation.latitude.toStringAsFixed(6)}, '
                'Lon: ${_selectedLocation.longitude.toStringAsFixed(6)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return overlays;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        buildMap(),  // Use buildMap() from BaseMapState
        ..._buildCoordinatesOverlay(),
      ],
    );
  }
}