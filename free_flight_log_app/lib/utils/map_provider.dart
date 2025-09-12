/// Map provider configuration for consistent map tiles across the application
enum MapProvider {
  openStreetMap('Street Map', 'OSM', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', 18, '© OpenStreetMap contributors'),
  googleSatellite('Google Satellite', 'Google', 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}', 18, '© Google'),
  esriWorldImagery('Esri Satellite', 'Esri', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', 18, '© Esri');
  
  const MapProvider(this.displayName, this.shortName, this.urlTemplate, this.maxZoom, this.attribution);
  
  final String displayName;
  final String shortName;
  final String urlTemplate;
  final int maxZoom;
  final String attribution;
}