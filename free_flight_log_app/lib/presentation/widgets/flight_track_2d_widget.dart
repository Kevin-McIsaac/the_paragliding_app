import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';
import '../../services/database_service.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';
import '../../utils/site_marker_utils.dart';
import '../../utils/ui_utils.dart';
import '../screens/flight_track_3d_fullscreen.dart';

enum MapProvider {
  openStreetMap('Street Map', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', 18, '© OpenStreetMap contributors'),
  googleSatellite('Google Satellite', 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}', 18, '© Google'),
  esriWorldImagery('Esri Satellite', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', 18, '© Esri');

  const MapProvider(this.displayName, this.urlTemplate, this.maxZoom, this.attribution);
  
  final String displayName;
  final String urlTemplate;
  final int maxZoom;
  final String attribution;
}

class FlightTrack2DWidget extends StatefulWidget {
  final Flight flight;
  final double? height;
  
  const FlightTrack2DWidget({
    super.key,
    required this.flight,
    this.height = 400,
  });

  @override
  State<FlightTrack2DWidget> createState() => _FlightTrack2DWidgetState();
}

class _FlightTrack2DWidgetState extends State<FlightTrack2DWidget> {
  final IgcImportService _igcService = IgcImportService.instance;
  final DatabaseService _databaseService = DatabaseService.instance;
  final ParaglidingEarthApi _apiService = ParaglidingEarthApi.instance;
  final MapController _mapController = MapController();
  
  // Constants
  static const String _mapProviderKey = 'flight_track_2d_map_provider';
  static const String _legendExpandedKey = 'flight_track_2d_legend_expanded';
  static const double _chartHeight = 100.0;
  static const double _totalChartsHeight = 300.0; // 3 charts * 100px each
  static const double _mapPadding = 0.005;
  static const double _altitudePaddingFactor = 0.1;
  static const int _chartIntervalMinutes = 15;
  static const int _chartIntervalMs = _chartIntervalMinutes * 60 * 1000;
  
  List<IgcPoint> _trackPoints = [];
  Site? _launchSite;
  bool _isLoading = true;
  String? _error;
  MapProvider _selectedMapProvider = MapProvider.openStreetMap;
  int? _selectedTrackPointIndex;
  bool _selectionFromMap = false;
  bool _isLegendExpanded = false; // Default to collapsed for cleaner initial view
  
  // Site display state
  List<Site> _localSites = [];
  List<ParaglidingSite> _apiSites = [];
  Map<int, int> _siteFlightCounts = {};
  Timer? _debounceTimer;
  Timer? _loadingDelayTimer;
  LatLngBounds? _currentBounds;
  bool _isLoadingSites = false;
  bool _showLoadingIndicator = false;
  String? _lastLoadedBoundsKey;
  
  @override
  void initState() {
    super.initState();
    _loadMapProvider();
    _loadTrackData();
    _loadSiteData();
  }

  Future<void> _loadMapProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerName = prefs.getString(_mapProviderKey);
      if (providerName != null) {
        final provider = MapProvider.values.firstWhere(
          (p) => p.name == providerName,
          orElse: () => MapProvider.openStreetMap,
        );
        setState(() {
          _selectedMapProvider = provider;
        });
      }
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading map provider', e);
    }
  }

  Future<void> _saveMapProvider(MapProvider provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_mapProviderKey, provider.name);
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error saving map provider', e);
    }
  }

  Future<void> _loadLegendPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isExpanded = prefs.getBool(_legendExpandedKey) ?? true; // Default to expanded
      setState(() {
        _isLegendExpanded = isExpanded;
      });
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading legend preference', e);
    }
  }

  Future<void> _saveLegendPreference(bool isExpanded) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_legendExpandedKey, isExpanded);
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error saving legend preference', e);
    }
  }

  void _toggleLegend() {
    setState(() {
      _isLegendExpanded = !_isLegendExpanded;
    });
    _saveLegendPreference(_isLegendExpanded);
  }

  Widget _buildCollapsibleLegend() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle button header
          InkWell(
            onTap: _toggleLegend,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isLegendExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Legend',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: _isLegendExpanded 
                ? CrossFadeState.showFirst 
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Site legend items (always shown for consistent layout)
                  SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.flownSiteColor, 'Flown Sites'),
                  const SizedBox(height: 4),
                  SiteMarkerUtils.buildLegendItem(context, Icons.location_on, SiteMarkerUtils.newSiteColor, 'New Sites'),
                  const SizedBox(height: 4),
                  // Launch and landing markers
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SiteMarkerUtils.buildLaunchMarkerIcon(
                              color: SiteMarkerUtils.launchColor,
                              size: 16,
                            ),
                            const Icon(
                              Icons.flight_takeoff,
                              color: Colors.white,
                              size: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Launch', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SiteMarkerUtils.buildLandingMarkerIcon(
                              color: SiteMarkerUtils.landingColor,
                              size: 16,
                            ),
                            const Icon(
                              Icons.flight_land,
                              color: Colors.white,
                              size: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Landing', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      Text('Climb', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      Text('Sink (<1.5m/s)', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      Text('Sink (>1.5m/s)', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSiteData() async {
    if (widget.flight.launchSiteId != null) {
      try {
        final site = await _databaseService.getSite(widget.flight.launchSiteId!);
        setState(() {
          _launchSite = site;
        });
      } catch (e) {
        LoggingService.error('FlightTrack2DWidget: Error loading site data', e);
      }
    }
  }

  Future<void> _loadTrackData() async {
    if (widget.flight.trackLogPath == null) {
      setState(() {
        _error = 'No track data available for this flight';
        _isLoading = false;
      });
      return;
    }

    try {
      final trackData = await _igcService.getTrackPointsWithTimezone(widget.flight.trackLogPath!);
      
      if (trackData.points.isEmpty) {
        setState(() {
          _error = 'No track points found';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _trackPoints = trackData.points;
        _isLoading = false;
      });
      
      LoggingService.info('FlightTrack2DWidget: Loaded ${_trackPoints.length} track points');
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading track data', e);
      setState(() {
        _error = 'Error loading track data: $e';
        _isLoading = false;
      });
    }
  }

  /// Load sites within the current map bounds
  Future<void> _loadSitesForBounds(LatLngBounds bounds) async {
    // Create a unique key for these bounds to prevent duplicate requests
    final boundsKey = '${bounds.north.toStringAsFixed(6)}_${bounds.south.toStringAsFixed(6)}_${bounds.east.toStringAsFixed(6)}_${bounds.west.toStringAsFixed(6)}';
    if (_lastLoadedBoundsKey == boundsKey) {
      return; // Same bounds already loaded
    }

    setState(() => _isLoadingSites = true);
    
    // Show loading indicator after 500ms delay to prevent flashing
    _loadingDelayTimer?.cancel();
    _loadingDelayTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _isLoadingSites) {
        setState(() => _showLoadingIndicator = true);
      }
    });

    try {
      // Load local sites from database
      final localSites = await _databaseService.getSitesInBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      );

      // Load API sites from ParaglidingEarth
      List<ParaglidingSite> apiSites = [];
      try {
        apiSites = await _apiService.getSitesInBounds(
          bounds.north,
          bounds.south,
          bounds.east,
          bounds.west,
        );
      } catch (apiError) {
        LoggingService.error('FlightTrack2DWidget: Error loading API sites', apiError);
        // Continue without API sites if they fail to load
      }

      if (mounted) {
        setState(() {
          _localSites = localSites;
          _apiSites = apiSites;
          _isLoadingSites = false;
          _showLoadingIndicator = false;
        });
        _loadingDelayTimer?.cancel();
        
        _lastLoadedBoundsKey = boundsKey;
        
        // Load flight counts for the newly loaded sites
        _loadFlightCounts();
      }
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading sites', e);
      if (mounted) {
        setState(() {
          _isLoadingSites = false;
          _showLoadingIndicator = false;
        });
        _loadingDelayTimer?.cancel();
      }
    }
  }

  /// Load flight counts for local sites
  Future<void> _loadFlightCounts() async {
    try {
      final Map<int, int> flightCounts = {};
      
      // Load flight counts for all local sites
      for (final site in _localSites) {
        if (site.id != null) {
          final count = await _databaseService.getFlightCountForSite(site.id!);
          flightCounts[site.id!] = count;
        }
      }
      
      if (mounted) {
        setState(() {
          _siteFlightCounts = flightCounts;
        });
      }
    } catch (e) {
      LoggingService.error('FlightTrack2DWidget: Error loading flight counts', e);
    }
  }

  /// Check if an API site duplicates a local site (same coordinates)
  bool _isDuplicateApiSite(ParaglidingSite apiSite) {
    const double tolerance = 0.000001; // ~0.1 meter tolerance for floating point comparison
    
    return _localSites.any((localSite) =>
      (localSite.latitude - apiSite.latitude).abs() < tolerance &&
      (localSite.longitude - apiSite.longitude).abs() < tolerance
    );
  }

  /// Debounced site loading when map bounds change
  void _onMapPositionChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        final bounds = _mapController.camera.visibleBounds;
        _currentBounds = bounds;
        _loadSitesForBounds(bounds);
      }
    });
  }

  double _calculateClimbRate(IgcPoint point1, IgcPoint point2) {
    final timeDiff = point2.timestamp.difference(point1.timestamp).inSeconds;
    if (timeDiff <= 0) return 0.0;
    
    final altitudeDiff = point2.gpsAltitude - point1.gpsAltitude;
    return altitudeDiff / timeDiff;
  }

  /// Calculate smoothed ground speed using 5-second time-based moving average
  /// Similar to the existing climbRate5s implementation but for ground speed
  double _getSmoothedGroundSpeed(IgcPoint point) {
    if (point.parentFile == null || point.pointIndex == null) {
      return point.groundSpeed;
    }
    
    final tracks = point.parentFile!.trackPoints;
    final currentIndex = point.pointIndex!;
    
    if (currentIndex >= tracks.length || currentIndex == 0) {
      return point.groundSpeed; // Fallback to instantaneous for first point
    }
    
    // Find the first point in the 5-second window (looking backwards from current point)
    IgcPoint? firstInWindow;
    for (int i = currentIndex - 1; i >= 0; i--) {
      final timeDiff = point.timestamp.difference(tracks[i].timestamp).inSeconds;
      if (timeDiff >= 5) {
        firstInWindow = tracks[i];
        break;
      }
    }
    
    // If we don't have enough points in the window, use instantaneous rate
    if (firstInWindow == null || firstInWindow == point) {
      return point.groundSpeed;
    }
    
    // Calculate the average ground speed over the 5-second window
    final timeDiffSeconds = point.timestamp.difference(firstInWindow.timestamp).inSeconds.toDouble();
    
    if (timeDiffSeconds <= 0) {
      return point.groundSpeed; // Fallback to instantaneous
    }
    
    // Calculate distance traveled over the time window using simple Pythagorean formula
    final distanceMeters = _calculateSimpleDistance(
      firstInWindow.latitude, firstInWindow.longitude,
      point.latitude, point.longitude
    );
    
    // Convert to km/h: (meters/second) * 3.6
    return (distanceMeters / timeDiffSeconds) * 3.6;
  }
  
  /// Calculate distance between two lat/lng points using simple Pythagorean formula
  /// For small distances (GPS points), Earth curvature correction is negligible
  double _calculateSimpleDistance(double lat1, double lng1, double lat2, double lng2) {
    // Convert degrees to approximate meters at mid-latitude
    final avgLat = (lat1 + lat2) / 2;
    final metersPerDegreeLat = 111319.9; // meters per degree latitude (constant)
    final metersPerDegreeLng = 111319.9 * math.cos(avgLat * math.pi / 180); // varies by latitude
    
    final deltaLat = (lat2 - lat1) * metersPerDegreeLat;
    final deltaLng = (lng2 - lng1) * metersPerDegreeLng;
    
    return math.sqrt(deltaLat * deltaLat + deltaLng * deltaLng);
  }

  Color _getClimbRateColor(double climbRate) {
    if (climbRate >= 0) return Colors.green;
    if (climbRate > -1.5) return Colors.blue;
    return Colors.red;
  }

  List<Polyline> _buildColoredTrackLines() {
    if (_trackPoints.length < 2) return [];
    
    List<Polyline> lines = [];
    List<LatLng> currentSegment = [LatLng(_trackPoints[0].latitude, _trackPoints[0].longitude)];
    Color currentColor = Colors.blue; // Default for first point
    
    for (int i = 1; i < _trackPoints.length; i++) {
      final climbRate = _calculateClimbRate(_trackPoints[i-1], _trackPoints[i]);
      final color = _getClimbRateColor(climbRate);
      
      if (color != currentColor && currentSegment.length > 1) {
        // Finish current segment
        lines.add(Polyline(
          points: currentSegment,
          strokeWidth: 3.0,
          color: currentColor,
        ));
        
        // Start new segment with the last point of previous segment
        currentSegment = [currentSegment.last];
        currentColor = color;
      }
      
      currentSegment.add(LatLng(_trackPoints[i].latitude, _trackPoints[i].longitude));
      currentColor = color;
    }
    
    // Add final segment
    if (currentSegment.length > 1) {
      lines.add(Polyline(
        points: currentSegment,
        strokeWidth: 3.0,
        color: currentColor,
      ));
    }
    
    return lines;
  }

  void _onMapTapped(LatLng position) {
    final closestIndex = _findClosestTrackPointByPosition(position);
    if (closestIndex == -1) return;
    
    setState(() {
      _selectedTrackPointIndex = closestIndex;
      _selectionFromMap = true;
    });
  }
  
  double _calculateDistance(LatLng point1, LatLng point2) {
    // Simple distance calculation (Haversine would be more accurate but this is sufficient)
    final lat1Rad = point1.latitude * (math.pi / 180);
    final lat2Rad = point2.latitude * (math.pi / 180);
    final deltaLat = (point2.latitude - point1.latitude) * (math.pi / 180);
    final deltaLng = (point2.longitude - point1.longitude) * (math.pi / 180);
    
    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLng / 2) * math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return 6371000 * c; // Earth radius in meters
  }

  /// Finds the closest track point index by geographic distance
  int _findClosestTrackPointByPosition(LatLng position) {
    if (_trackPoints.isEmpty) return -1;
    
    int closestIndex = 0;
    double minDistance = _calculateDistance(position, LatLng(_trackPoints[0].latitude, _trackPoints[0].longitude));
    
    for (int i = 1; i < _trackPoints.length; i++) {
      final distance = _calculateDistance(position, LatLng(_trackPoints[i].latitude, _trackPoints[i].longitude));
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    
    return closestIndex;
  }

  /// Finds the closest track point index by timestamp
  int _findClosestTrackPointByTimestamp(int targetTimestamp) {
    if (_trackPoints.isEmpty) return -1;
    
    int closestIndex = 0;
    double minDifference = (targetTimestamp - _trackPoints[0].timestamp.millisecondsSinceEpoch).abs().toDouble();
    
    for (int i = 1; i < _trackPoints.length; i++) {
      final difference = (targetTimestamp - _trackPoints[i].timestamp.millisecondsSinceEpoch).abs().toDouble();
      if (difference < minDifference) {
        minDifference = difference;
        closestIndex = i;
      }
    }
    
    return closestIndex;
  }

  List<Marker> _buildTrackPointMarker() {
    if (_selectedTrackPointIndex == null || _selectedTrackPointIndex! >= _trackPoints.length) {
      return [];
    }
    
    final point = _trackPoints[_selectedTrackPointIndex!];
    
    return [
      Marker(
        point: LatLng(point.latitude, point.longitude),
        width: 16,
        height: 16,
        child: Container(
          decoration: const BoxDecoration(
            color: SiteMarkerUtils.selectedPointColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Marker> _buildMarkers() {
    if (_trackPoints.isEmpty) return [];
    
    final firstPoint = _trackPoints.first;
    final lastPoint = _trackPoints.last;
    
    return [
      // Launch marker
      Marker(
        point: LatLng(firstPoint.latitude, firstPoint.longitude),
        width: 32,
        height: 32,
        child: AppTooltip(
          message: _launchSite?.name ?? 'Launch Site',
          child: Stack(
            alignment: Alignment.center,
            children: [
              SiteMarkerUtils.buildLaunchMarkerIcon(
                color: SiteMarkerUtils.launchColor,
                size: SiteMarkerUtils.launchMarkerSize,
              ),
              const Icon(
                Icons.flight_takeoff,
                color: Colors.white,
                size: 14,
              ),
            ],
          ),
        ),
      ),
      // Landing marker
      Marker(
        point: LatLng(lastPoint.latitude, lastPoint.longitude),
        width: 32,
        height: 32,
        child: AppTooltip(
          message: widget.flight.landingDescription ?? 'Landing Site',
          child: Stack(
            alignment: Alignment.center,
            children: [
              SiteMarkerUtils.buildLandingMarkerIcon(
                color: SiteMarkerUtils.landingColor,
                size: SiteMarkerUtils.launchMarkerSize,
              ),
              const Icon(
                Icons.flight_land,
                color: Colors.white,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Build site markers using shared helper functions
  List<Marker> _buildSiteMarkers() {
    List<Marker> markers = [];
    
    // Add local sites (flown sites - blue)
    for (final site in _localSites) {
      final flightCount = site.id != null ? _siteFlightCounts[site.id] : null;
      markers.add(
        SiteMarkerUtils.buildDisplaySiteMarker(
          position: LatLng(site.latitude, site.longitude),
          siteName: site.name,
          isFlownSite: true, // Local sites are always flown sites
          flightCount: flightCount,
          tooltip: flightCount != null && flightCount > 0 
            ? '${site.name} ($flightCount flight${flightCount == 1 ? '' : 's'})'
            : site.name,
        ),
      );
    }
    
    // Add API sites (new sites - green), excluding duplicates
    for (final site in _apiSites) {
      if (!_isDuplicateApiSite(site)) {
        markers.add(
          SiteMarkerUtils.buildDisplaySiteMarker(
            position: LatLng(site.latitude, site.longitude),
            siteName: site.name,
            isFlownSite: false, // API sites are new sites
            flightCount: null, // API sites don't have local flight counts
            tooltip: site.name,
          ),
        );
      }
    }
    
    return markers;
  }

  LatLngBounds _calculateBounds() {
    if (_trackPoints.isEmpty) {
      return LatLngBounds(
        const LatLng(46.9480, 7.4474),
        const LatLng(46.9580, 7.4574),
      );
    }
    
    double minLat = _trackPoints.first.latitude;
    double maxLat = _trackPoints.first.latitude;
    double minLng = _trackPoints.first.longitude;
    double maxLng = _trackPoints.first.longitude;
    
    for (final point in _trackPoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    
    // Add padding
    return LatLngBounds(
      LatLng(minLat - _mapPadding, minLng - _mapPadding),
      LatLng(maxLat + _mapPadding, maxLng + _mapPadding),
    );
  }

  void _fitMapToBounds() {
    if (_trackPoints.isNotEmpty) {
      final bounds = _calculateBounds();
      _mapController.fitCamera(CameraFit.bounds(bounds: bounds));
      
      // Load sites for the new bounds after fitting
      _loadSitesForBounds(bounds);
    }
  }

  void _openFullscreen3D() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlightTrack3DFullscreenScreen(flight: widget.flight),
      ),
    );
  }

  IconData _getProviderIcon(MapProvider provider) {
    switch (provider) {
      case MapProvider.openStreetMap:
        return Icons.map;
      case MapProvider.googleSatellite:
        return Icons.satellite;
      case MapProvider.esriWorldImagery:
        return Icons.terrain;
    }
  }
  
  Widget _buildMapProviderButton() {
    return Container(
      decoration: BoxDecoration(
        color: Color(0x80000000),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: PopupMenuButton<MapProvider>(
        tooltip: 'Change Maps',
        onSelected: (provider) async {
          setState(() {
            _selectedMapProvider = provider;
          });
          await _saveMapProvider(provider);
        },
        initialValue: _selectedMapProvider,
        itemBuilder: (context) => MapProvider.values.map((provider) {
          return PopupMenuItem<MapProvider>(
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
          );
        }).toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getProviderIcon(_selectedMapProvider),
                size: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _build3DViewButton() {
    return Container(
      decoration: BoxDecoration(
        color: Color(0x80000000),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AppTooltip(
        message: '3D Fly Through',
        child: InkWell(
          onTap: _openFullscreen3D,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Icon(
              Icons.threed_rotation,
              size: 16,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSynchronizedChart({
    required String title,
    required String unit,
    required Color color,
    required double Function(IgcPoint) dataExtractor,
    bool showTimeLabels = false,
  }) {
    if (_trackPoints.length < 2) {
      return SizedBox(height: _chartHeight, child: Center(child: Text('Insufficient data for $title chart')));
    }

    // Calculate data points using actual timestamps
    final spots = _trackPoints.map((point) {
      return FlSpot(point.timestamp.millisecondsSinceEpoch.toDouble(), dataExtractor(point));
    }).toList();

    // Calculate bounds
    final values = spots.map((s) => s.y).toList();
    final minVal = values.reduce(math.min);
    final maxVal = values.reduce(math.max);
    final valRange = maxVal - minVal;
    final padding = valRange * _altitudePaddingFactor;

    // Create the line bar data
    final lineBarData = LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color,
      barWidth: 1,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.15),
      ),
      showingIndicators: _selectedTrackPointIndex != null 
        ? [_selectedTrackPointIndex!] 
        : [],
    );

    return Container(
      height: _chartHeight,
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: LineChart(
        LineChartData(
          showingTooltipIndicators: _selectedTrackPointIndex != null ? [
            ShowingTooltipIndicators([
              LineBarSpot(
                lineBarData,
                0,
                spots[_selectedTrackPointIndex!],
              ),
            ])
          ] : [],
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
              if (touchResponse != null && touchResponse.lineBarSpots != null && touchResponse.lineBarSpots!.isNotEmpty) {
                final spot = touchResponse.lineBarSpots!.first;
                final targetTimestamp = spot.x.toInt();
                final closestIndex = _findClosestTrackPointByTimestamp(targetTimestamp);
                
                if (closestIndex != -1) {
                  setState(() {
                    _selectedTrackPointIndex = closestIndex;
                    _selectionFromMap = false;
                  });
                }
              }
            },
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => color.withValues(alpha: 0.8),
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  final value = barSpot.y;
                  final displayValue = unit == 'm' ? value.toInt().toString() : value.toStringAsFixed(1);
                  return LineTooltipItem(
                    '$displayValue$unit',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  );
                }).toList();
              },
            ),
            getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
              return spotIndexes.map((spotIndex) {
                return TouchedSpotIndicatorData(
                  FlLine(
                    color: color.withValues(alpha: 0.5),
                    strokeWidth: 1,
                    dashArray: [3, 3],
                  ),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 3,
                        color: color,
                        strokeWidth: 1,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                );
              }).toList();
            },
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: valRange / 4,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey[350]!,
                strokeWidth: 0.5,
              );
            },
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: false,
                reservedSize: 0,
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: showTimeLabels,
                reservedSize: showTimeLabels ? 15 : 0,
                interval: _chartIntervalMs.toDouble(),
                getTitlesWidget: (value, meta) {
                  if (!showTimeLabels) return const SizedBox.shrink();
                  
                  final targetTimestamp = value.toInt();
                  final closestIndex = _findClosestTrackPointByTimestamp(targetTimestamp);
                  
                  if (closestIndex == -1) {
                    return const SizedBox.shrink();
                  }
                  
                  final closestPoint = _trackPoints[closestIndex];
                  final timeString = '${closestPoint.timestamp.hour.toString().padLeft(2, '0')}:${closestPoint.timestamp.minute.toString().padLeft(2, '0')}';
                  return Text(
                    timeString,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: spots.first.x,
          maxX: spots.last.x,
          minY: minVal - padding,
          maxY: maxVal + padding,
          lineBarsData: [
            lineBarData,
          ],
        ),
      ),
    );
  }

  Widget _buildChartWithTitle(String title, Widget chart) {
    return Stack(
      children: [
        chart,
        Positioned(
          top: 2,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _loadingDelayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_error != null) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Flight Track Map
        SizedBox(
          height: (widget.height ?? 400) - _totalChartsHeight - 20,
          child: Stack(
            children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _trackPoints.isNotEmpty
                  ? LatLng(_trackPoints.first.latitude, _trackPoints.first.longitude)
                  : const LatLng(46.9480, 7.4474),
              initialZoom: 13.0,
              minZoom: 1.0,
              maxZoom: _selectedMapProvider.maxZoom.toDouble(),
              onMapReady: _fitMapToBounds,
              onTap: (tapPosition, point) => _onMapTapped(point),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  _onMapPositionChanged();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _selectedMapProvider.urlTemplate,
                maxZoom: _selectedMapProvider.maxZoom.toDouble(),
                userAgentPackageName: 'com.example.free_flight_log_app',
              ),
              MarkerLayer(
                markers: _buildSiteMarkers(),
              ),
              PolylineLayer(
                polylines: _buildColoredTrackLines(),
              ),
              MarkerLayer(
                markers: [..._buildMarkers(), ..._buildTrackPointMarker()],
              ),
            ],
          ),
          // Top right controls (map provider and 3D view)
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _build3DViewButton(),
                const SizedBox(width: 8),
                _buildMapProviderButton(),
              ],
            ),
          ),
          // Collapsible Legend for track colors and sites
          Positioned(
            top: 8,
            left: 8,
            child: _buildCollapsibleLegend(),
          ),
          // Attribution
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[900]!.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _selectedMapProvider.attribution,
                style: const TextStyle(fontSize: 8, color: Colors.white70),
              ),
            ),
          ),
          // Bottom center loading indicator like Site Maps
          if (_showLoadingIndicator)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Loading sites...',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
        // Three synchronized charts
        _buildChartWithTitle(
          'Altitude (m)',
          _buildSynchronizedChart(
            title: 'altitude',
            unit: 'm',
            color: Colors.blue,
            dataExtractor: (point) => point.gpsAltitude.toDouble(),
            showTimeLabels: true,
          ),
        ),
        _buildChartWithTitle(
          'Climb Rate (m/s)',
          _buildSynchronizedChart(
            title: 'climb rate',
            unit: 'm/s',
            color: Colors.green,
            dataExtractor: (point) => point.climbRate5s,
            showTimeLabels: false,
          ),
        ),
        _buildChartWithTitle(
          'Ground Speed (km/h)',
          _buildSynchronizedChart(
            title: 'ground speed',
            unit: 'km/h',
            color: Colors.orange,
            dataExtractor: (point) => _getSmoothedGroundSpeed(point),
            showTimeLabels: false,
          ),
        ),
      ],
    );
  }
}