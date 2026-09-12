import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../data/models/holfuy_reading.dart';
import '../../data/models/weather_station.dart';
import '../../data/models/weather_station_source.dart';
import '../../data/models/wind_data.dart';
import '../../services/weather_providers/holfuy_weather_provider.dart';
import '../../services/weather_providers/weather_station_provider_registry.dart';
import 'holfuy_marker.dart';
import 'package:url_launcher/url_launcher.dart';

/// Weather station marker showing wind direction and speed with barbed arrow
class WeatherStationMarker extends StatelessWidget {
  final WeatherStation station;
  final double maxWindSpeed;
  final double cautionWindSpeed;
  final VoidCallback? onTap;

  /// Called when a reading fetched on demand should be reflected on the map.
  /// Holfuy wind arrives only after a tap, so without this the station would
  /// keep the reading only inside the dialog that fetched it.
  ///
  /// For a Holfuy station this changes the tooltip, not the mark: the marker is
  /// [HolfuyMarker] before and after. It also seeds the cached reading the
  /// dialog reopens with.
  final void Function(WindData wind)? onReadingLoaded;

  static const double markerSize = 40.0;

  const WeatherStationMarker({
    super.key,
    required this.station,
    required this.maxWindSpeed,
    required this.cautionWindSpeed,
    this.onTap,
    this.onReadingLoaded,
  });

  /// Marker state helpers for WU PWS stations without wind:
  /// noData = station confirmed to report nothing usable; pending = readings
  /// still being fetched in the background.
  static bool _isNoDataStation(WeatherStation station) =>
      station.source == WeatherStationSource.weatherUndergroundPws &&
      station.observationType == 'WU PWS (no wind data)';

  static bool _isPendingStation(WeatherStation station) =>
      station.source == WeatherStationSource.weatherUndergroundPws &&
      station.observationType != 'WU PWS (no wind data)';

  /// A Holfuy station whose reading has not been fetched yet. Its wind is not
  /// missing - the app does not ask Holfuy until someone taps - so the tooltip
  /// says "tap for wind" rather than claiming the station has no data.
  ///
  /// The marker itself is [HolfuyMarker] either way; only the tooltip differs.
  static bool _isHolfuyUnread(WeatherStation station) =>
      station.source == WeatherStationSource.holfuy && station.windData == null;

  @override
  Widget build(BuildContext context) {
    final windData = station.windData;
    final String tooltipText;
    if (windData != null) {
      // Show "CALM" for winds < 1 km/h (direction meaningless when no wind)
      if (windData.speedKmh < 1.0) {
        tooltipText = '${station.name ?? station.id}\nCALM';
      } else {
        final gustsStr = windData.gustsKmh != null
            ? '-${windData.gustsKmh!.toStringAsFixed(1)}'
            : '';
        tooltipText = '${station.name ?? station.id}\n${windData.speedKmh.toStringAsFixed(1)}$gustsStr km/h from ${windData.directionDegrees.toStringAsFixed(0)}°';
      }
    } else if (_isNoDataStation(station)) {
      tooltipText = '${station.name ?? station.id}\nNo wind data (station reports none)';
    } else if (_isPendingStation(station)) {
      // Only WU PWS loads wind in the background; every other provider's
      // data-less station simply has no data.
      tooltipText = '${station.name ?? station.id}\nWind loading…';
    } else if (_isHolfuyUnread(station)) {
      final altitude = station.elevation != null
          ? '\n${station.elevation!.toStringAsFixed(0)}m'
          : '';
      tooltipText = '${station.name ?? station.id}$altitude\nTap for wind';
    } else {
      tooltipText = '${station.name ?? station.id}\nNo wind data';
    }

    return Tooltip(
      message: tooltipText,
      textStyle: const TextStyle(color: Colors.white, fontSize: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: GestureDetector(
        onTap: onTap ?? () => _showStationDialog(context),
        child: SizedBox(
          width: markerSize,
          height: markerSize,
          // Every Holfuy station is its own symbol, read or not: the wind barb
          // is a shared NOAA convention that says "this is a wind reading",
          // while Holfuy's mark says which service reported it. The reading
          // itself is in the tooltip and the dialog.
          child: station.source == WeatherStationSource.holfuy
              ? const HolfuyMarker()
              : CustomPaint(
                  painter: _WeatherStationPainter(
                    windData: windData,
                    pending: windData == null && _isPendingStation(station),
                    noData: windData == null && _isNoDataStation(station),
                  ),
                ),
        ),
      ),
    );
  }

  void _showStationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _WeatherStationDialog(
        station: station,
        maxWindSpeed: maxWindSpeed,
        cautionWindSpeed: cautionWindSpeed,
        onReadingLoaded: onReadingLoaded,
      ),
    );
  }
}

/// Custom painter for weather station marker with barbed arrow
class _WeatherStationPainter extends CustomPainter {
  final WindData? windData;

  /// No wind yet and a background reading pass is still working.
  final bool pending;

  /// The station was checked and reports no usable wind - rendered as a
  /// dashed, dimmed circle so it reads as "station exists, has no data".
  final bool noData;

  _WeatherStationPainter({
    required this.windData,
    this.pending = false,
    this.noData = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Circle outline (NOAA style)
    final circleRadius = 6.0;

    if (noData) {
      // Dashed, dimmed circle: station alive but reports no wind.
      final dashPaint = Paint()
        ..color = Colors.grey[500]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      const dashCount = 8;
      const dashArc = 2 * math.pi / (dashCount * 2);
      for (var i = 0; i < dashCount; i++) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: circleRadius),
          i * dashArc * 2,
          dashArc,
          false,
          dashPaint,
        );
      }
      // Small centre dot: "no data here".
      canvas.drawCircle(
        center,
        1.5,
        Paint()..color = Colors.grey[500]!,
      );
      return;
    }

    if (pending) {
      // Lighter, thinner ring: wind still loading.
      final pendingPaint = Paint()
        ..color = Colors.grey[400]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, circleRadius, pendingPaint);
      return;
    }

    // Draw circle outline only (no fill)
    final circlePaint = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, circleRadius, circlePaint);

    // Draw wind barb only if wind speed >= 1 km/h (calm winds show circle only)
    final data = windData;
    if (data != null && data.speedKmh >= 1.0) {
      _drawWindBarb(canvas, center, circleRadius, data);
    }
  }

  void _drawWindBarb(Canvas canvas, Offset center, double circleRadius, WindData windData) {
    final barbPaint = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Convert wind direction to radians (meteorological convention: direction FROM)
    // Rotate so north (0°) points up
    final angle = (windData.directionDegrees - 90) * math.pi / 180;

    // Shaft starts at circle edge and extends outward
    final shaftStart = Offset(
      center.dx + circleRadius * math.cos(angle),
      center.dy + circleRadius * math.sin(angle),
    );

    final shaftLength = 25.0;
    final shaftEnd = Offset(
      shaftStart.dx + shaftLength * math.cos(angle),
      shaftStart.dy + shaftLength * math.sin(angle),
    );

    // Draw main shaft
    canvas.drawLine(shaftStart, shaftEnd, barbPaint);

    // Draw speed barbs
    _drawSpeedBarbs(canvas, shaftEnd, angle, windData.speedKmh, barbPaint);
  }

  void _drawSpeedBarbs(Canvas canvas, Offset shaftEnd, double angle, double speedKmh, Paint paint) {
    // Round to nearest 5 km/h (meteorological standard)
    final roundedSpeed = (speedKmh / 5).round() * 5.0;

    // Wind barbs: each full barb = 10 km/h, half barb = 5 km/h
    final fullBarbs = (roundedSpeed / 10).floor();
    final halfBarb = (roundedSpeed % 10) >= 5;

    final barbLength = 10.0;  // Longer barbs (more prominent)
    final barbSpacing = 5.0;  // Spacing between barbs
    final barbAngle = 60 * math.pi / 180; // 60 degrees from shaft

    // Start from the end of the shaft and work backwards
    double distanceFromEnd = 2.0; // Small offset from shaft end

    // Draw half barb first (closest to end, like NOAA standard)
    if (halfBarb && fullBarbs < 5) {
      final barbBase = Offset(
        shaftEnd.dx - distanceFromEnd * math.cos(angle),
        shaftEnd.dy - distanceFromEnd * math.sin(angle),
      );
      final barbTip = Offset(
        barbBase.dx + (barbLength / 2) * math.cos(angle + barbAngle),
        barbBase.dy + (barbLength / 2) * math.sin(angle + barbAngle),
      );
      canvas.drawLine(barbBase, barbTip, paint);
      distanceFromEnd += barbSpacing;
    }

    // Draw full barbs (working backwards from end)
    for (int i = 0; i < fullBarbs && i < 5; i++) {
      final barbBase = Offset(
        shaftEnd.dx - distanceFromEnd * math.cos(angle),
        shaftEnd.dy - distanceFromEnd * math.sin(angle),
      );
      final barbTip = Offset(
        barbBase.dx + barbLength * math.cos(angle + barbAngle),
        barbBase.dy + barbLength * math.sin(angle + barbAngle),
      );
      canvas.drawLine(barbBase, barbTip, paint);
      distanceFromEnd += barbSpacing;
    }
  }

  @override
  bool shouldRepaint(_WeatherStationPainter oldDelegate) {
    return oldDelegate.windData != windData ||
        oldDelegate.pending != pending ||
        oldDelegate.noData != noData;
  }
}

/// Dialog showing detailed weather station information.
///
/// For a Holfuy station this is where the wind is fetched, on demand - the only
/// moment the app reads Holfuy for a reading. The dialog shows a loading state,
/// then the reading, and reports it back so the marker behind it fills in too.
class _WeatherStationDialog extends StatefulWidget {
  final WeatherStation station;
  final double maxWindSpeed;
  final double cautionWindSpeed;
  final void Function(WindData wind)? onReadingLoaded;

  const _WeatherStationDialog({
    required this.station,
    required this.maxWindSpeed,
    required this.cautionWindSpeed,
    this.onReadingLoaded,
  });

  @override
  State<_WeatherStationDialog> createState() => _WeatherStationDialogState();
}

class _WeatherStationDialogState extends State<_WeatherStationDialog> {
  WindData? _windData;

  /// The outcome of the on-tap read, so the dialog can say *why* there is no
  /// wind instead of reporting every outcome as "could not load".
  HolfuyReading? _result;
  bool _loading = false;

  WeatherStation get station => widget.station;

  @override
  void initState() {
    super.initState();
    _windData = station.windData;
    // Holfuy is the one source whose wind is not already attached by the time
    // the marker is drawn; asking for it here is the whole on-tap design.
    if (_windData == null && station.source == WeatherStationSource.holfuy) {
      _loadReading();
    }
  }

  Future<void> _loadReading() async {
    setState(() {
      _loading = true;
      _result = null;
    });

    final reading =
        await HolfuyWeatherProvider.instance.requestReading(station.id);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = reading;
      _windData = reading.wind;
    });

    final wind = reading.wind;
    if (wind != null) widget.onReadingLoaded?.call(wind);
  }

  String _getTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final windData = _windData;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: Station name and close button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${station.name ?? station.id} (${station.id})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Wind data section
              if (windData != null) ...[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Wind barb
                      SizedBox(
                        width: 50,
                        child: CustomPaint(
                          painter: _WeatherStationPainter(
                            windData: windData,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Wind info
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            // Wind speed and direction
                            Text(
                              () {
                                // Show "CALM" for winds < 1 km/h
                                if (windData.speedKmh < 1.0) {
                                  return 'CALM';
                                }
                                final gustsStr = windData.gustsKmh != null
                                    ? '-${windData.gustsKmh!.toStringAsFixed(1)}'
                                    : '';
                                return '${windData.speedKmh.toStringAsFixed(1)}$gustsStr km/h from ${windData.compassDirection} (${windData.directionDegrees.toStringAsFixed(0)}°)';
                              }(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Time and type on first line
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _buildInfoChip(Icons.access_time, _getTimeAgo(windData.timestamp)),
                                if (station.observationType != null)
                                  _buildInfoChip(Icons.sensors, station.observationType!),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Location and elevation on second line
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _buildInfoChip(Icons.location_on, '${station.latitude.toStringAsFixed(2)}°, ${station.longitude.toStringAsFixed(2)}°'),
                                if (station.elevation != null)
                                  _buildInfoChip(Icons.terrain, '${station.elevation!.toStringAsFixed(0)}m'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_loading) ...[
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Loading wind from Holfuy…',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ] else if (_result?.status == HolfuyReadingStatus.offline) ...[
                _buildOfflineNotice(_result!),
              ] else ...[
                Text(
                  station.source == WeatherStationSource.holfuy
                      ? "Couldn't reach Holfuy"
                      : 'No wind data available',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              // Attribution
              _buildAttribution(station),
            ],
          ),
        ),
      ),
    );
  }

  /// The station is up and telling us why it is silent.
  ///
  /// This is information, not an error: Holfuy stations are frequently
  /// solar-powered and go flat for days ("Battery is empty! Waiting for Sun...").
  /// Reporting that as "could not load" turns a working station into an app
  /// failure.
  Widget _buildOfflineNotice(HolfuyReading reading) {
    final reason = reading.offlineReason;
    final lastUpdate = reading.lastUpdate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          children: [
            Icon(Icons.cloud_off, size: 14, color: Colors.orangeAccent),
            SizedBox(width: 6),
            Text(
              'Station offline',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        if (reason != null) ...[
          const SizedBox(height: 6),
          Text(
            reason,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
        if (lastUpdate != null) ...[
          const SizedBox(height: 4),
          Text(
            'Last update: $lastUpdate',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white54),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }

  Widget _buildAttribution(WeatherStation station) {
    final provider = WeatherStationProviderRegistry.getProvider(station.source);

    // For Aviation Weather Center, Pioupiou, and FFVL stations, link to specific station observation page
    final String url;
    if (station.source == WeatherStationSource.awcMetar) {
      url = 'https://aviationweather.gov/data/metar/?decoded=1&ids=${station.id}';
    } else if (station.source == WeatherStationSource.pioupiou) {
      url = 'https://www.openwindmap.org/windbird-${station.id}';
    } else if ((station.source == WeatherStationSource.ffvl ||
                station.source == WeatherStationSource.weatherUndergroundPws ||
                station.source == WeatherStationSource.holfuy) &&
               station.dataUrl != null) {
      url = station.dataUrl!;
    } else {
      url = provider.attributionUrl;
    }

    return TextButton(
      onPressed: () async {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      },
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        'Data: ${provider.attributionName}',
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white38,
        ),
      ),
    );
  }
}
