/// Centralized preference keys for map-related settings
class MapPreferences {
  // Shared across all map instances
  static const String mapProvider = 'map_provider';
  static const String legendExpanded = 'map_legend_expanded';

  // Feature toggles (shared where appropriate)
  static const String sitesEnabled = 'map_sites_enabled';
  static const String airspaceEnabled = 'map_airspace_enabled';

  // Legacy keys for migration (can be removed in future)
  // These are kept temporarily to allow smooth migration
  static const String legacyNearbyMapProvider = 'nearby_sites_map_provider';
  static const String legacyEditMapProvider = 'edit_site_map_provider';
  static const String legacyNearbyLegend = 'nearby_sites_legend_expanded';
  static const String legacyEditLegend = 'edit_site_legend_expanded';

  MapPreferences._(); // Prevent instantiation
}