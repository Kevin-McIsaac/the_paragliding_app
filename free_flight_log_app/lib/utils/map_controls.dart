import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'map_provider.dart';
import '../services/logging_service.dart';

/// Standardized map control widgets and utilities for consistent UI across all maps
class MapControls {
  static const BoxDecoration _standardMapControlDecoration = BoxDecoration(
    color: Color(0x80000000),
    borderRadius: BorderRadius.all(Radius.circular(4)),
    boxShadow: [
      BoxShadow(
        color: Colors.black26,
        blurRadius: 4,
        offset: Offset(0, 2),
      ),
    ],
  );

  static const BoxDecoration _standardAttributionDecoration = BoxDecoration(
    borderRadius: BorderRadius.all(Radius.circular(4)),
    boxShadow: [
      BoxShadow(
        color: Colors.black26,
        blurRadius: 4,
        offset: Offset(0, 2),
      ),
    ],
  );

  /// Get icon for map provider
  static IconData getProviderIcon(MapProvider provider) {
    switch (provider) {
      case MapProvider.openStreetMap:
        return Icons.map;
      case MapProvider.googleSatellite:
        return Icons.satellite_alt;
      case MapProvider.esriWorldImagery:
        return Icons.terrain;
    }
  }

  /// Build standardized map provider selector
  static Widget buildMapProviderSelector({
    required MapProvider currentProvider,
    required Function(MapProvider) onProviderChanged,
    String tooltip = 'Change Maps',
  }) {
    return Container(
      decoration: _standardMapControlDecoration,
      child: PopupMenuButton<MapProvider>(
        tooltip: tooltip,
        onSelected: onProviderChanged,
        initialValue: currentProvider,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                getProviderIcon(currentProvider),
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
                  getProviderIcon(provider),
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
    );
  }

  /// Build standardized map controls column
  static Widget buildMapControls({
    required MapProvider currentProvider,
    required Function(MapProvider) onProviderChanged,
    List<Widget> additionalControls = const [],
  }) {
    return Column(
      children: [
        buildMapProviderSelector(
          currentProvider: currentProvider,
          onProviderChanged: onProviderChanged,
        ),
        ...additionalControls,
      ],
    );
  }

  /// Build standardized attribution widget with support for multiple data sources
  static Widget buildAttribution({
    required MapProvider provider,
    bool showAirspaceAttribution = false,
    bool showSitesAttribution = false,
  }) {
    return Positioned(
      bottom: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: _standardAttributionDecoration.copyWith(
          color: Colors.grey[900]!.withValues(alpha: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Map provider attribution
            GestureDetector(
              onTap: () => _launchAttributionUrl(provider),
              child: Text(
                'Maps: ${provider.attribution}',
                style: const TextStyle(fontSize: 8, color: Colors.white70),
              ),
            ),
            // Airspace attribution
            if (showAirspaceAttribution) ...[
              const Text(
                ' | ',
                style: TextStyle(fontSize: 8, color: Colors.white54),
              ),
              GestureDetector(
                onTap: () => _launchDataSourceUrl('openaip'),
                child: const Text(
                  'Airspace: OpenAIP.net',
                  style: TextStyle(fontSize: 8, color: Colors.white70),
                ),
              ),
            ],
            // Sites attribution
            if (showSitesAttribution) ...[
              const Text(
                ' | ',
                style: TextStyle(fontSize: 8, color: Colors.white54),
              ),
              GestureDetector(
                onTap: () => _launchDataSourceUrl('paraglidingearth'),
                child: const Text(
                  'Sites: paraglidingearth.com',
                  style: TextStyle(fontSize: 8, color: Colors.white70),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Launch attribution URL for the given provider
  static Future<void> _launchAttributionUrl(MapProvider provider) async {
    String url;
    switch (provider) {
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
      LoggingService.error('MapControls: Could not launch attribution URL', e);
    }
  }

  /// Launch URL for data source attribution
  static Future<void> _launchDataSourceUrl(String source) async {
    String url;
    switch (source) {
      case 'openaip':
        url = 'https://www.openaip.net';
        break;
      case 'paraglidingearth':
        url = 'https://www.paraglidingearth.com';
        break;
      default:
        return;
    }

    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      LoggingService.error('MapControls: Could not launch data source URL', e);
    }
  }

  /// Build positioned controls in top-right corner
  static Widget buildPositionedControls({
    required MapProvider currentProvider,
    required Function(MapProvider) onProviderChanged,
    List<Widget> additionalControls = const [],
  }) {
    return Positioned(
      top: 8,
      right: 8,
      child: buildMapControls(
        currentProvider: currentProvider,
        onProviderChanged: onProviderChanged,
        additionalControls: additionalControls,
      ),
    );
  }
}