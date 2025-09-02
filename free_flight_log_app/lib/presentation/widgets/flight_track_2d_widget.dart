import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/flight.dart';
import '../../data/models/site.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';
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
  final MapController _mapController = MapController();
  
  // Constants
  static const String _mapProviderKey = 'flight_track_2d_map_provider';
  static const double _chartHeight = 100.0;
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

  double _calculateClimbRate(IgcPoint point1, IgcPoint point2) {
    final timeDiff = point2.timestamp.difference(point1.timestamp).inSeconds;
    if (timeDiff <= 0) return 0.0;
    
    final altitudeDiff = point2.gpsAltitude - point1.gpsAltitude;
    return altitudeDiff / timeDiff;
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
        width: 12,
        height: 12,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.yellow,
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
        width: 30,
        height: 30,
        child: Tooltip(
          message: _launchSite?.name ?? 'Launch Site',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.flight_takeoff,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ),
      // Landing marker
      Marker(
        point: LatLng(lastPoint.latitude, lastPoint.longitude),
        width: 30,
        height: 30,
        child: Tooltip(
          message: widget.flight.landingDescription ?? 'Landing Site',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.flight_land,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ),
    ];
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Tooltip(
        message: 'View in 3D',
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

  Widget _buildAltitudeChart() {
    if (_trackPoints.length < 2) {
      return SizedBox(height: _chartHeight, child: const Center(child: Text('Insufficient data for altitude chart')));
    }

    // Calculate time and altitude data points using actual timestamps
    final spots = _trackPoints.map((point) {
      return FlSpot(point.timestamp.millisecondsSinceEpoch.toDouble(), point.gpsAltitude.toDouble());
    }).toList();


    // Calculate altitude bounds
    final altitudes = _trackPoints.map((p) => p.gpsAltitude).toList();
    final minAlt = altitudes.reduce(math.min).toDouble();
    final maxAlt = altitudes.reduce(math.max).toDouble();
    final altRange = maxAlt - minAlt;
    final padding = altRange * _altitudePaddingFactor;

    // Create the line bar data to reuse in both places
    final lineBarData = LineChartBarData(
      spots: spots,
      isCurved: false,
      color: Colors.blue,
      barWidth: 1,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: Colors.grey.withValues(alpha: 0.25),
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
                0, // bar index
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
                    _selectionFromMap = false; // Reset flag since this is from chart
                  });
                }
              }
              // Don't clear selection when hover stops - keep crosshairs persistent
            },
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => Colors.blue.withValues(alpha: 0.8),
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  return LineTooltipItem(
                    '${barSpot.y.toInt()}m',
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
                    color: Colors.blue.withValues(alpha: 0.5),
                    strokeWidth: 1,
                    dashArray: [3, 3],
                  ),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 3,
                        color: Colors.blue,
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
            horizontalInterval: altRange / 4,
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
                showTitles: true,
                reservedSize: 15,
                interval: _chartIntervalMs.toDouble(),
                getTitlesWidget: (value, meta) {
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
          minY: minAlt - padding,
          maxY: maxAlt + padding,
          lineBarsData: [
            lineBarData,
          ],
        ),
      ),
    );
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
          height: (widget.height ?? 400) - _chartHeight - 20,
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
            ),
            children: [
              TileLayer(
                urlTemplate: _selectedMapProvider.urlTemplate,
                maxZoom: _selectedMapProvider.maxZoom.toDouble(),
                userAgentPackageName: 'com.example.free_flight_log_app',
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
          // Legend
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [
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
                  const Text('Track Color:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.normal, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      const Text('Climbing', style: TextStyle(fontSize: 10, color: Colors.black87)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      const Text('Sink (<1.5m/s)', style: TextStyle(fontSize: 10, color: Colors.black87)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(1.5))),
                      const SizedBox(width: 8),
                      const Text('Sink (>1.5m/s)', style: TextStyle(fontSize: 10, color: Colors.black87)),
                    ],
                  ),
                ],
              ),
            ),
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
            ],
          ),
        ),
        // Altitude Chart
        Stack(
          children: [
            _buildAltitudeChart(),
            // Title positioned at top center of chart
            const Positioned(
              top: 2,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Altitude (m)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}