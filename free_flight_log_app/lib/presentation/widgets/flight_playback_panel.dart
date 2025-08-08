import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/flight_playback_controller.dart';
import '../../data/models/igc_file.dart';

/// Bottom panel with timeline scrubber and playback controls
class FlightPlaybackPanel extends StatefulWidget {
  final FlightPlaybackController controller;
  final VoidCallback? onClose;
  
  const FlightPlaybackPanel({
    super.key,
    required this.controller,
    this.onClose,
  });
  
  @override
  State<FlightPlaybackPanel> createState() => _FlightPlaybackPanelState();
}

class _FlightPlaybackPanelState extends State<FlightPlaybackPanel> 
    with TickerProviderStateMixin {
  
  // Speed options
  final List<double> _speedOptions = [1.0, 10.0, 30.0, 60.0, 120.0];
  
  @override
  void initState() {
    super.initState();
    
    // Listen to controller changes
    widget.controller.addListener(_onControllerChanged);
  }
  
  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }
  
  void _onControllerChanged() {
    setState(() {
      // Update UI when controller state changes
    });
  }
  
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main playback panel
            _buildCollapsedView(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCollapsedView() {
    final currentTime = _formatDuration(widget.controller.currentTime.inSeconds);
    final totalTime = _formatDuration(widget.controller.totalDuration.inSeconds);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          // Live stats row
          _buildLiveStatsRow(),
          
          const SizedBox(height: 8),
          
          // Timeline scrubber
          _buildTimelineScrubber(),
          
          const SizedBox(height: 6),
          
          // Controls row (play/pause, time, and playback speed)
          Row(
            children: [
              // Play/Pause button
              IconButton(
                onPressed: () => widget.controller.togglePlayPause(this),
                icon: Icon(
                  widget.controller.state == PlaybackState.playing
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
                iconSize: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              
              // Time display
              Expanded(
                child: Text(
                  '$currentTime / $totalTime',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              
              // Playback speed indicator
              TextButton(
                onPressed: _showSpeedMenu,
                child: Text(
                  '${widget.controller.playbackSpeed.toInt()}x',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  
  Widget _buildTimelineScrubber() {
    final events = widget.controller.detectEvents();
    
    return SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Timeline track
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Progress fill
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: widget.controller.progress,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          
          // Event markers
          ...events.map((event) => _buildEventMarker(event)),
          
          // Scrubber handle
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              trackHeight: 4,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
            ),
            child: Slider(
              value: widget.controller.progress,
              onChanged: (value) {
                widget.controller.seekToProgress(value);
                // Haptic feedback on scrub
                HapticFeedback.selectionClick();
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEventMarker(FlightEvent event) {
    final progress = widget.controller.totalDuration.inMilliseconds > 0
        ? event.timestamp.difference(widget.controller.trackPoints.first.timestamp)
            .inMilliseconds / widget.controller.totalDuration.inMilliseconds
        : 0.0;
    
    Color markerColor;
    IconData? markerIcon;
    
    switch (event.type) {
      case EventType.takeoff:
        markerColor = Colors.green;
        markerIcon = Icons.flight_takeoff;
        break;
      case EventType.landing:
        markerColor = Colors.red;
        markerIcon = Icons.flight_land;
        break;
      case EventType.maxAltitude:
        markerColor = Colors.blue;
        markerIcon = Icons.terrain;
        break;
      case EventType.maxClimb:
        markerColor = Colors.orange;
        markerIcon = Icons.arrow_upward;
        break;
      case EventType.thermalEntry:
        markerColor = Colors.purple;
        markerIcon = Icons.air;
        break;
    }
    
    return Positioned(
      left: progress * (MediaQuery.of(context).size.width - 32),
      child: GestureDetector(
        onTap: () {
          widget.controller.seekToIndex(event.pointIndex);
          HapticFeedback.lightImpact();
        },
        child: Tooltip(
          message: event.label,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: markerColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// Build live stats row for main panel
  Widget _buildLiveStatsRow() {
    final point = widget.controller.currentPoint;
    if (point == null) {
      return const SizedBox.shrink();
    }
    
    final currentIndex = widget.controller.currentPointIndex;
    final altitude = point.pressureAltitude > 0 
        ? point.pressureAltitude 
        : point.gpsAltitude;
    
    // Get climb rate from controller's arrays
    double climbRate = 0.0;
    if (currentIndex < widget.controller.averagedClimbRates.length) {
      climbRate = widget.controller.averagedClimbRates[currentIndex];
    } else if (currentIndex < widget.controller.instantaneousClimbRates.length) {
      climbRate = widget.controller.instantaneousClimbRates[currentIndex];
    }
    
    // Calculate ground speed if we have previous point
    double groundSpeed = 0.0;
    if (currentIndex > 0 && currentIndex < widget.controller.trackPoints.length) {
      final prevPoint = widget.controller.trackPoints[currentIndex - 1];
      final currentPoint = widget.controller.trackPoints[currentIndex];
      
      // Simple distance calculation (good for small distances)
      final dlat = (currentPoint.latitude - prevPoint.latitude) * 111320; // meters per degree latitude
      final dlon = (currentPoint.longitude - prevPoint.longitude) * 111320 * math.cos(currentPoint.latitude * (math.pi / 180)); // meters per degree longitude
      final distance = math.sqrt(dlat * dlat + dlon * dlon); // meters
      
      final timeDiff = currentPoint.timestamp.difference(prevPoint.timestamp).inSeconds;
      if (timeDiff > 0) {
        groundSpeed = distance / timeDiff; // m/s
      }
    }
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(
          'Altitude',
          '${altitude.toStringAsFixed(0)}m',
          Icons.terrain,
        ),
        _buildStatItem(
          'Climb Rate',
          '${climbRate > 0 ? '+' : ''}${climbRate.toStringAsFixed(1)}m/s',
          climbRate > 0 ? Icons.trending_up : Icons.trending_down,
        ),
        _buildStatItem(
          'Speed',
          '${(groundSpeed * 3.6).toStringAsFixed(0)}km/h',
          Icons.speed,
        ),
        _buildStatItem(
          'Time',
          '${point.timestamp.hour.toString().padLeft(2, '0')}:${point.timestamp.minute.toString().padLeft(2, '0')}',
          Icons.schedule,
        ),
      ],
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
  
  void _showSpeedMenu() {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    
    showMenu<double>(
      context: context,
      position: position,
      items: _speedOptions.map((speed) => 
        PopupMenuItem(
          value: speed,
          child: Text('${speed.toInt()}x'),
        ),
      ).toList(),
    ).then((value) {
      if (value != null) {
        widget.controller.setPlaybackSpeed(value);
      }
    });
  }
  
  /// Format duration in seconds to mm:ss format
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}