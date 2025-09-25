import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../data/models/paragliding_site.dart';

/// Reusable info card for displaying site or point information on maps
class MapInfoCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Map<String, String>? details;
  final List<Widget>? actions;
  final VoidCallback? onClose;
  final Color? accentColor;

  const MapInfoCard({
    super.key,
    required this.title,
    this.subtitle,
    this.details,
    this.actions,
    this.onClose,
    this.accentColor,
  });

  factory MapInfoCard.forSite(
    ParaglidingSite site, {
    VoidCallback? onClose,
    VoidCallback? onNavigate,
    VoidCallback? onDetails,
  }) {
    final details = <String, String>{};

    details['Location'] = 'Lat: ${site.latitude.toStringAsFixed(4)}, Lon: ${site.longitude.toStringAsFixed(4)}';

    if (site.hasFlights) {
      details['Flights'] = '${site.flightCount}';
    }

    if (site.altitude != null) {
      details['Altitude'] = '${site.altitude!.toStringAsFixed(0)}m';
    }

    if (site.country != null && site.country!.isNotEmpty) {
      details['Country'] = site.country!;
    }

    final actions = <Widget>[];

    if (onNavigate != null) {
      actions.add(
        TextButton.icon(
          icon: const Icon(Icons.directions, size: 16),
          label: const Text('Navigate'),
          onPressed: onNavigate,
        ),
      );
    }

    if (onDetails != null) {
      actions.add(
        TextButton.icon(
          icon: const Icon(Icons.info_outline, size: 16),
          label: const Text('Details'),
          onPressed: onDetails,
        ),
      );
    }

    return MapInfoCard(
      title: site.name,
      subtitle: site.hasFlights ? 'Flown Site' : 'New Site',
      details: details,
      actions: actions.isNotEmpty ? actions : null,
      onClose: onClose,
      accentColor: site.hasFlights ? Colors.blue : Colors.deepPurple,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and close button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 20,
                  ),
              ],
            ),

            // Details section
            if (details != null && details!.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...details!.entries.map((entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.key}: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 12,
                          color: entry.key == 'Flights' ? Colors.green : null,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],

            // Actions section
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Overlay widget for displaying coordinates on maps
class CoordinatesOverlay extends StatelessWidget {
  final LatLng coordinates;
  final String? label;
  final IconData? icon;
  final Color backgroundColor;
  final Color textColor;

  const CoordinatesOverlay({
    super.key,
    required this.coordinates,
    this.label,
    this.icon,
    this.backgroundColor = const Color(0xB0000000), // 70% black
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: textColor.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
          ],
          if (label != null) ...[
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 11,
                color: textColor.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          Text(
            'Lat: ${coordinates.latitude.toStringAsFixed(6)}, '
            'Lon: ${coordinates.longitude.toStringAsFixed(6)}',
            style: TextStyle(
              fontSize: 11,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Location request button overlay for maps
class LocationRequestOverlay extends StatelessWidget {
  final VoidCallback onLocationRequest;
  final bool isLoading;
  final String tooltip;

  const LocationRequestOverlay({
    super.key,
    required this.onLocationRequest,
    this.isLoading = false,
    this.tooltip = 'Get current location',
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      mini: true,
      onPressed: isLoading ? null : onLocationRequest,
      tooltip: tooltip,
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.my_location),
    );
  }
}

/// Wrapper widget to position overlays on maps consistently
class MapOverlayPositioned extends StatelessWidget {
  final MapOverlayPosition position;
  final Widget child;
  final EdgeInsets padding;

  const MapOverlayPositioned({
    super.key,
    required this.position,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    switch (position) {
      case MapOverlayPosition.topLeft:
        return Positioned(
          top: padding.top,
          left: padding.left,
          child: child,
        );
      case MapOverlayPosition.topRight:
        return Positioned(
          top: padding.top,
          right: padding.right,
          child: child,
        );
      case MapOverlayPosition.bottomLeft:
        return Positioned(
          bottom: padding.bottom,
          left: padding.left,
          child: child,
        );
      case MapOverlayPosition.bottomRight:
        return Positioned(
          bottom: padding.bottom,
          right: padding.right,
          child: child,
        );
      case MapOverlayPosition.bottomCenter:
        return Positioned(
          bottom: padding.bottom,
          left: padding.left,
          right: padding.right,
          child: child,
        );
      case MapOverlayPosition.topCenter:
        return Positioned(
          top: padding.top,
          left: padding.left,
          right: padding.right,
          child: child,
        );
    }
  }
}

/// Enum for standard overlay positions
enum MapOverlayPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  bottomCenter,
  topCenter,
}

/// Distance label overlay for displaying distances on maps
class DistanceLabel extends StatelessWidget {
  final LatLng position;
  final double distanceKm;
  final Color backgroundColor;
  final Color textColor;

  const DistanceLabel({
    super.key,
    required this.position,
    required this.distanceKm,
    this.backgroundColor = const Color(0xB0000000),
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(3),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        '${distanceKm.toStringAsFixed(1)}km',
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}