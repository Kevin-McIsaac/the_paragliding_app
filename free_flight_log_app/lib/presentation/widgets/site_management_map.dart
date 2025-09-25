import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/flight.dart';
import '../../services/logging_service.dart';
import 'common/base_map_widget.dart';

/// Specialized map widget for site management and editing
/// Extends BaseMapWidget to reuse common functionality
class SiteManagementMap extends BaseMapWidget {
  final Site? selectedSourceSite;
  final List<Flight> launches;
  final bool isMergeMode;
  final Function(Site, dynamic)? onSiteMerge;  // dynamic can be Site or ParaglidingSite
  final Function(LatLng)? onLocationTap;
  final Function()? onMapReady;

  const SiteManagementMap({
    super.key,
    this.selectedSourceSite,
    this.launches = const [],
    this.isMergeMode = false,
    this.onSiteMerge,
    this.onLocationTap,
    this.onMapReady,
    super.height = 600,
  });

  @override
  State<SiteManagementMap> createState() => _SiteManagementMapState();
}

class _SiteManagementMapState extends BaseMapState<SiteManagementMap> {
  Site? _hoveredTargetSite;
  ParaglidingSite? _hoveredApiSite;

  @override
  String get mapProviderKey => 'site_management_map_provider';

  @override
  String get legendExpandedKey => 'site_management_legend_expanded';

  @override
  String get mapContext => 'site_management';

  @override
  int get siteLimit => 50;  // More sites for reference when managing

  @override
  void onMapReady() {
    super.onMapReady();
    widget.onMapReady?.call();
  }

  @override
  void onMapTap(TapPosition tapPosition, LatLng point) {
    widget.onLocationTap?.call(point);
  }

  @override
  List<Widget> buildAdditionalLayers() {
    final layers = <Widget>[];

    // Launch markers layer
    if (widget.launches.isNotEmpty) {
      layers.add(
        MarkerLayer(
          markers: widget.launches.map((launch) {
            final site = Site(
              id: launch.launchSiteId,
              name: launch.launchSiteName,
              latitude: launch.launchLatitude!,
              longitude: launch.launchLongitude!,
            );

            return Marker(
              point: LatLng(site.latitude, site.longitude),
              width: 30,
              height: 30,
              child: GestureDetector(
                onTap: () {
                  LoggingService.info('SiteManagementMap: Launch marker tapped: ${site.name}');
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orange.withValues(alpha: 0.3),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: const Icon(
                    Icons.flight_takeoff,
                    size: 16,
                    color: Colors.orange,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    // Draggable source site marker (merge mode)
    if (widget.isMergeMode && widget.selectedSourceSite != null) {
      final sourceSite = widget.selectedSourceSite!;
      layers.add(
        DragMarkers(
          markers: [
            DragMarker(
              key: ValueKey(sourceSite.id),
              point: LatLng(sourceSite.latitude, sourceSite.longitude),
              size: const Size(60, 60),
              offset: const Offset(0, -30),
              builder: (_, point, isDragging) {
                return Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDragging
                        ? Colors.green.withValues(alpha: 0.5)
                        : Colors.green.withValues(alpha: 0.3),
                    border: Border.all(
                      color: Colors.green,
                      width: 3,
                    ),
                    boxShadow: isDragging ? [
                      const BoxShadow(
                        color: Colors.black38,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ] : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.merge,
                        color: isDragging ? Colors.white : Colors.green,
                        size: 24,
                      ),
                      if (!isDragging)
                        const Text(
                          'Drag',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                );
              },
              onDragEnd: (details, point) {
                _handleMergeDragEnd(sourceSite, point);
              },
            ),
          ],
        ),
      );
    }

    // Hover indicators for merge targets
    if (_hoveredTargetSite != null || _hoveredApiSite != null) {
      final hoveredPoint = _hoveredTargetSite != null
          ? LatLng(_hoveredTargetSite!.latitude, _hoveredTargetSite!.longitude)
          : LatLng(_hoveredApiSite!.latitude, _hoveredApiSite!.longitude);

      layers.add(
        MarkerLayer(
          markers: [
            Marker(
              point: hoveredPoint,
              width: 80,
              height: 80,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withValues(alpha: 0.2),
                  border: Border.all(
                    color: Colors.blue,
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.merge_type,
                  color: Colors.blue,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return layers;
  }

  void _handleMergeDragEnd(Site sourceSite, LatLng dropPoint) {
    // Find the closest site or API site within merge distance
    const double mergeDistanceMeters = 100.0;
    final Distance distance = Distance();

    // Check flown sites first
    for (final site in sites.whereType<Site>()) {
      if (site.id == sourceSite.id) continue;  // Skip self

      final sitePoint = LatLng(site.latitude, site.longitude);
      final distanceMeters = distance.as(LengthUnit.Meter, dropPoint, sitePoint);

      if (distanceMeters <= mergeDistanceMeters) {
        widget.onSiteMerge?.call(sourceSite, site);
        return;
      }
    }

    // Check API sites
    for (final apiSite in sites.whereType<ParaglidingSite>()) {
      final sitePoint = LatLng(apiSite.latitude, apiSite.longitude);
      final distanceMeters = distance.as(LengthUnit.Meter, dropPoint, sitePoint);

      if (distanceMeters <= mergeDistanceMeters) {
        widget.onSiteMerge?.call(sourceSite, apiSite);
        return;
      }
    }

    // No valid merge target found
    LoggingService.info('SiteManagementMap: No merge target found at drop location');
  }

  @override
  List<Widget> buildAdditionalLegendItems() {
    final items = <Widget>[];

    if (widget.launches.isNotEmpty) {
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange.withValues(alpha: 0.3),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: const Icon(
                Icons.flight_takeoff,
                size: 10,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Launches',
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

    if (widget.isMergeMode) {
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.3),
                border: Border.all(color: Colors.green, width: 1),
              ),
              child: const Icon(
                Icons.merge,
                size: 10,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Merge Source',
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

  @override
  Widget build(BuildContext context) {
    return buildMap();  // Use buildMap() from BaseMapState
  }
}