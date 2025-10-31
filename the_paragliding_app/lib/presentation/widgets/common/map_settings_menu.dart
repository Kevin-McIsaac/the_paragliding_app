import 'package:flutter/material.dart';
import '../../../utils/map_provider.dart';

/// Map settings menu button that consolidates map-related controls:
/// - Change Map Provider
/// - Refresh All
/// - Map Filters
///
/// This replaces the separate "Change Maps", "Refresh All", and "Map Filters" buttons
/// to provide a cleaner, more organized UI.
class MapSettingsMenu extends StatelessWidget {
  /// Current selected map provider
  final MapProvider selectedMapProvider;

  /// Callback when a new map provider is selected
  final void Function(MapProvider) onMapProviderSelected;

  /// Callback when "Refresh All" is selected
  final VoidCallback onRefreshAll;

  /// Callback when "Map Filters" is selected
  final VoidCallback onMapFilters;

  /// Callback when "Get Current Location" is selected
  final VoidCallback? onLocationRequest;

  /// Whether the refresh action should be disabled (e.g., during loading)
  final bool refreshDisabled;

  /// Whether any filters are currently active (shows orange indicator)
  final bool hasActiveFilters;

  const MapSettingsMenu({
    super.key,
    required this.selectedMapProvider,
    required this.onMapProviderSelected,
    required this.onRefreshAll,
    required this.onMapFilters,
    this.onLocationRequest,
    this.refreshDisabled = false,
    this.hasActiveFilters = false,
  });

  /// Get icon for a map provider
  IconData _getProviderIcon(MapProvider provider) {
    switch (provider) {
      case MapProvider.openStreetMap:
        return Icons.map;
      case MapProvider.googleSatellite:
        return Icons.satellite_alt;
      case MapProvider.esriWorldImagery:
        return Icons.satellite;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune),
      tooltip: 'Map Settings',
      onSelected: (value) {
        if (value == 'refresh') {
          if (!refreshDisabled) {
            onRefreshAll();
          }
        } else if (value == 'filters') {
          onMapFilters();
        } else if (value.startsWith('provider_')) {
          // Extract provider index from value
          final providerIndex = int.parse(value.split('_')[1]);
          onMapProviderSelected(MapProvider.values[providerIndex]);
        }
      },
      itemBuilder: (context) => [
        // Change Map Provider submenu
        PopupMenuItem<String>(
          enabled: false,
          child: Row(
            children: [
              Icon(
                _getProviderIcon(selectedMapProvider),
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Change Map Provider',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        // Map provider options (indented)
        ...MapProvider.values.map((provider) {
          final isSelected = provider == selectedMapProvider;
          return PopupMenuItem<String>(
            value: 'provider_${provider.index}',
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Row(
                children: [
                  Icon(
                    _getProviderIcon(provider),
                    size: 18,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.displayName,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : null,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
          );
        }),
        const PopupMenuDivider(),
        // Refresh All
        PopupMenuItem<String>(
          value: 'refresh',
          enabled: !refreshDisabled,
          child: Row(
            children: [
              Icon(
                Icons.refresh,
                color: refreshDisabled ? Colors.grey : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Refresh All',
                style: TextStyle(
                  color: refreshDisabled ? Colors.grey : null,
                ),
              ),
            ],
          ),
        ),
        // Map Filters
        const PopupMenuItem<String>(
          value: 'filters',
          child: Row(
            children: [
              Icon(Icons.filter_list),
              SizedBox(width: 8),
              Text('Map Filters'),
            ],
          ),
        ),
      ],
    );
  }
}
