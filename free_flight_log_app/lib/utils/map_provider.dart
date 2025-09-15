/// Map provider configuration for consistent map tiles across the application
enum MapProvider {
  openStreetMap(
    'Street Map',
    'OSM',
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    18,
    '© OpenStreetMap contributors',
    'Show Open Street Maps'
  ),
  googleSatellite(
    'Google Satellite',
    'Google Satellite',
    'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
    18,
    '© Google',
    'Show Google Satellite Maps'
  ),
  esriWorldImagery(
    'Esri Satellite',
    'ESRI Satellite',
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    18,
    '© Esri',
    'Show the ESRI Satellite Maps'
  );

  const MapProvider(
    this.displayName,
    this.shortName,
    this.urlTemplate,
    this.maxZoom,
    this.attribution,
    this.tooltip
  );

  final String displayName;
  final String shortName;
  final String urlTemplate;
  final int maxZoom;
  final String attribution;
  final String tooltip;
}