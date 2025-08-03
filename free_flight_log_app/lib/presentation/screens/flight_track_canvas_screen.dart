import 'package:flutter/material.dart';
import 'dart:math';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';

class FlightTrackCanvasScreen extends StatefulWidget {
  final Flight flight;

  const FlightTrackCanvasScreen({super.key, required this.flight});

  @override
  State<FlightTrackCanvasScreen> createState() => _FlightTrackCanvasScreenState();
}

class _FlightTrackCanvasScreenState extends State<FlightTrackCanvasScreen> {
  final IgcImportService _igcService = IgcImportService();
  
  List<IgcPoint> _trackPoints = [];
  bool _isLoading = true;
  String? _error;
  
  // Display options
  bool _showAltitudeColors = true;
  bool _showMarkers = true;
  bool _showStraightLine = true;

  @override
  void initState() {
    super.initState();
    _loadTrackData();
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
      final trackPoints = await _igcService.getTrackPoints(widget.flight.trackLogPath!);
      
      if (trackPoints.isEmpty) {
        setState(() {
          _error = 'No track points found';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _trackPoints = trackPoints;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _error = 'Error loading track data: $e';
        _isLoading = false;
      });
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  void _toggleAltitudeColors() {
    setState(() {
      _showAltitudeColors = !_showAltitudeColors;
    });
  }

  void _toggleMarkers() {
    setState(() {
      _showMarkers = !_showMarkers;
    });
  }

  void _toggleStraightLine() {
    setState(() {
      _showStraightLine = !_showStraightLine;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Track'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'markers':
                  _toggleMarkers();
                  break;
                case 'colors':
                  _toggleAltitudeColors();
                  break;
                case 'straight_line':
                  _toggleStraightLine();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'markers',
                child: Row(
                  children: [
                    Icon(_showMarkers ? Icons.visibility : Icons.visibility_off),
                    const SizedBox(width: 8),
                    Text('${_showMarkers ? 'Hide' : 'Show'} Markers'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'colors',
                child: Row(
                  children: [
                    Icon(_showAltitudeColors ? Icons.palette : Icons.palette_outlined),
                    const SizedBox(width: 8),
                    Text('${_showAltitudeColors ? 'Simple' : 'Altitude'} Colors'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'straight_line',
                child: Row(
                  children: [
                    Icon(_showStraightLine ? Icons.timeline : Icons.timeline_outlined),
                    const SizedBox(width: 8),
                    Text('${_showStraightLine ? 'Hide' : 'Show'} Straight Line'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : Column(
                  children: [
                    _buildStatsBar(),
                    Expanded(child: _buildTrackCanvas()),
                  ],
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Track Not Available',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    if (_trackPoints.isEmpty) return const SizedBox.shrink();

    final startPoint = _trackPoints.first;
    final endPoint = _trackPoints.last;
    final duration = _formatDuration(widget.flight.duration);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'Duration',
                duration,
                Icons.access_time,
              ),
              _buildStatItem(
                'Track Distance',
                widget.flight.distance != null 
                    ? '${widget.flight.distance!.toStringAsFixed(1)} km'
                    : 'N/A',
                Icons.timeline,
              ),
              _buildStatItem(
                'Max Alt',
                widget.flight.maxAltitude != null
                    ? '${widget.flight.maxAltitude!.toInt()} m'
                    : 'N/A',
                Icons.height,
              ),
              _buildStatItem(
                'Points',
                _trackPoints.length.toString(),
                Icons.gps_fixed,
              ),
            ],
          ),
          // Add straight distance row
          if (widget.flight.straightDistance != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Straight Distance',
                  '${widget.flight.straightDistance!.toStringAsFixed(1)} km',
                  Icons.straight,
                ),
                const SizedBox(width: 60), // Spacer for alignment
                const SizedBox(width: 60), // Spacer for alignment
                const SizedBox(width: 60), // Spacer for alignment
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildTrackCanvas() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: CustomPaint(
        painter: FlightTrackPainter(
          trackPoints: _trackPoints,
          showAltitudeColors: _showAltitudeColors,
          showMarkers: _showMarkers,
          showStraightLine: _showStraightLine,
          straightDistance: widget.flight.straightDistance,
        ),
      ),
    );
  }
}

class FlightTrackPainter extends CustomPainter {
  final List<IgcPoint> trackPoints;
  final bool showAltitudeColors;
  final bool showMarkers;
  final bool showStraightLine;
  final double? straightDistance;

  FlightTrackPainter({
    required this.trackPoints,
    required this.showAltitudeColors,
    required this.showMarkers,
    required this.showStraightLine,
    this.straightDistance,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trackPoints.isEmpty) return;

    // Calculate bounds
    final latitudes = trackPoints.map((p) => p.latitude);
    final longitudes = trackPoints.map((p) => p.longitude);
    final altitudes = trackPoints.map((p) => p.gpsAltitude);
    
    final minLat = latitudes.reduce((a, b) => a < b ? a : b);
    final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
    final minLng = longitudes.reduce((a, b) => a < b ? a : b);
    final maxLng = longitudes.reduce((a, b) => a > b ? a : b);
    final minAlt = altitudes.reduce((a, b) => a < b ? a : b);
    final maxAlt = altitudes.reduce((a, b) => a > b ? a : b);

    // Add padding
    const padding = 40.0;
    final drawableWidth = size.width - (padding * 2);
    final drawableHeight = size.height - (padding * 2);

    // Convert lat/lng to screen coordinates
    List<Offset> screenPoints = trackPoints.map((point) {
      final x = padding + ((point.longitude - minLng) / (maxLng - minLng)) * drawableWidth;
      final y = padding + ((maxLat - point.latitude) / (maxLat - minLat)) * drawableHeight;
      return Offset(x, y);
    }).toList();

    // Draw straight line (behind the track)
    if (showStraightLine && screenPoints.length >= 2) {
      _drawStraightLine(canvas, screenPoints.first, screenPoints.last);
    }

    // Draw track line
    if (screenPoints.length > 1) {
      if (showAltitudeColors) {
        _drawAltitudeColoredTrack(canvas, screenPoints, altitudes, minAlt, maxAlt);
      } else {
        _drawSimpleTrack(canvas, screenPoints);
      }
    }

    // Draw markers
    if (showMarkers && trackPoints.isNotEmpty) {
      _drawMarkers(canvas, screenPoints, altitudes, minAlt, maxAlt);
    }

    // Draw scale and info
    _drawScale(canvas, size, minLat, maxLat, minLng, maxLng);
  }

  void _drawStraightLine(Canvas canvas, Offset start, Offset end) {
    final paint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Create dashed line effect
    const dashWidth = 20.0;
    const dashSpace = 10.0;
    
    final path = Path();
    final distance = (end - start).distance;
    final direction = (end - start) / distance;
    
    double currentDistance = 0;
    while (currentDistance < distance) {
      final startPoint = start + direction * currentDistance;
      final endPoint = start + direction * (currentDistance + dashWidth).clamp(0, distance);
      
      path.moveTo(startPoint.dx, startPoint.dy);
      path.lineTo(endPoint.dx, endPoint.dy);
      
      currentDistance += dashWidth + dashSpace;
    }
    
    canvas.drawPath(path, paint);

    // Draw distance text at midpoint if available
    if (straightDistance != null) {
      final midPoint = Offset(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2,
      );

      _drawDistanceText(canvas, midPoint, '${straightDistance!.toStringAsFixed(1)} km');
    }
  }

  void _drawDistanceText(Canvas canvas, Offset position, String text) {
    // Draw background rectangle for text
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    
    // Background rectangle
    final backgroundRect = Rect.fromCenter(
      center: position,
      width: textPainter.width + 12,
      height: textPainter.height + 8,
    );
    
    final backgroundPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(backgroundRect, const Radius.circular(6)),
      backgroundPaint,
    );
    
    // Text
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy - textPainter.height / 2,
      ),
    );
  }

  void _drawSimpleTrack(Canvas canvas, List<Offset> screenPoints) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(screenPoints.first.dx, screenPoints.first.dy);
    
    for (int i = 1; i < screenPoints.length; i++) {
      path.lineTo(screenPoints[i].dx, screenPoints[i].dy);
    }
    
    canvas.drawPath(path, paint);
  }

  void _drawAltitudeColoredTrack(Canvas canvas, List<Offset> screenPoints, 
      Iterable<int> altitudes, int minAlt, int maxAlt) {
    final altList = altitudes.toList();
    
    for (int i = 0; i < screenPoints.length - 1; i++) {
      final normalizedAlt = maxAlt > minAlt 
          ? (altList[i] - minAlt) / (maxAlt - minAlt)
          : 0.0;
      
      final color = Color.lerp(
        Colors.blue,    // Low altitude
        Colors.red,     // High altitude
        normalizedAlt,
      )!;
      
      final paint = Paint()
        ..color = color
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      
      canvas.drawLine(screenPoints[i], screenPoints[i + 1], paint);
    }
  }

  void _drawMarkers(Canvas canvas, List<Offset> screenPoints, 
      Iterable<int> altitudes, int minAlt, int maxAlt) {
    final altList = altitudes.toList();
    
    // Find highest point
    int highestIndex = 0;
    for (int i = 1; i < altList.length; i++) {
      if (altList[i] > altList[highestIndex]) {
        highestIndex = i;
      }
    }

    // Launch marker (green)
    _drawMarker(canvas, screenPoints.first, Colors.green, 'L');
    
    // Landing marker (red)
    _drawMarker(canvas, screenPoints.last, Colors.red, 'X');
    
    // Highest point marker (blue)
    if (highestIndex < screenPoints.length) {
      _drawMarker(canvas, screenPoints[highestIndex], Colors.blue, 'H');
    }
  }

  void _drawMarker(Canvas canvas, Offset position, Color color, String label) {
    // Draw marker circle
    final markerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(position, 8, markerPaint);
    
    // Draw border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawCircle(position, 8, borderPaint);
    
    // Draw label
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy - textPainter.height / 2,
      ),
    );
  }

  void _drawScale(Canvas canvas, Size size, double minLat, double maxLat, 
      double minLng, double maxLng) {
    // Draw coordinate info in corners
    final textStyle = const TextStyle(
      color: Colors.black54,
      fontSize: 10,
    );

    // Top-left: Max lat, Min lng
    final topLeftPainter = TextPainter(
      text: TextSpan(
        text: '${maxLat.toStringAsFixed(4)}, ${minLng.toStringAsFixed(4)}',
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
    );
    topLeftPainter.layout();
    topLeftPainter.paint(canvas, const Offset(10, 10));

    // Top-right: Max lat, Max lng
    final topRightPainter = TextPainter(
      text: TextSpan(
        text: '${maxLat.toStringAsFixed(4)}, ${maxLng.toStringAsFixed(4)}',
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
    );
    topRightPainter.layout();
    topRightPainter.paint(canvas, Offset(size.width - topRightPainter.width - 10, 10));

    // Bottom-left: Min lat, Min lng
    final bottomLeftPainter = TextPainter(
      text: TextSpan(
        text: '${minLat.toStringAsFixed(4)}, ${minLng.toStringAsFixed(4)}',
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
    );
    bottomLeftPainter.layout();
    bottomLeftPainter.paint(canvas, Offset(10, size.height - bottomLeftPainter.height - 10));

    // Bottom-right: Min lat, Max lng
    final bottomRightPainter = TextPainter(
      text: TextSpan(
        text: '${minLat.toStringAsFixed(4)}, ${maxLng.toStringAsFixed(4)}',
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
    );
    bottomRightPainter.layout();
    bottomRightPainter.paint(canvas, Offset(
      size.width - bottomRightPainter.width - 10, 
      size.height - bottomRightPainter.height - 10
    ));
  }

  @override
  bool shouldRepaint(FlightTrackPainter oldDelegate) {
    return trackPoints != oldDelegate.trackPoints ||
           showAltitudeColors != oldDelegate.showAltitudeColors ||
           showMarkers != oldDelegate.showMarkers ||
           showStraightLine != oldDelegate.showStraightLine ||
           straightDistance != oldDelegate.straightDistance;
  }
}