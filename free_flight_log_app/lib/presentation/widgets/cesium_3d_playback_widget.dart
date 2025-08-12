import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'cesium/cesium_webview_controller.dart';
import '../../services/logging_service.dart';

/// Playback controls for 3D flight animation - matches 2D map panel layout
class Cesium3DPlaybackWidget extends StatefulWidget {
  final CesiumWebViewController controller;
  final List<Map<String, dynamic>> trackPoints;
  final VoidCallback? onClose;

  const Cesium3DPlaybackWidget({
    Key? key,
    required this.controller,
    required this.trackPoints,
    this.onClose,
  }) : super(key: key);

  @override
  State<Cesium3DPlaybackWidget> createState() => _Cesium3DPlaybackWidgetState();
}

class _Cesium3DPlaybackWidgetState extends State<Cesium3DPlaybackWidget> {
  bool _isPlaying = false;
  int _currentIndex = 0;
  int _totalPoints = 0;
  double _playbackSpeed = 30.0;  // Default to 30x speed
  bool _followMode = false;
  Timer? _updateTimer;
  
  // GlobalKey for speed button position
  final GlobalKey _speedButtonKey = GlobalKey();
  
  // Speed options for dropdown - match 2D map values (represent seconds per update)
  final List<double> _speedOptions = [1.0, 10.0, 30.0, 60.0, 120.0];

  @override
  void initState() {
    super.initState();
    _totalPoints = widget.trackPoints.length;
    _startUpdateTimer();
    
    // Set up JavaScript callback for position updates
    _setupJavaScriptCallbacks();
    
    // Set initial playback speed to 30x
    Future.delayed(const Duration(milliseconds: 500), () {
      widget.controller.setPlaybackSpeed(30.0);
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
  
  void _setupJavaScriptCallbacks() {
    // This would require WebView to call back to Flutter
    // For now, we'll use polling via timer
  }

  void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      if (!mounted) return;
      
      try {
        final state = await widget.controller.getPlaybackState();
        if (mounted && state != null) {
          // Only update if values have changed to avoid unnecessary rebuilds
          final newSpeed = state['playbackSpeed'] is int 
              ? (state['playbackSpeed'] as int).toDouble() 
              : (state['playbackSpeed'] ?? 1.0);
          
          if (_currentIndex != (state['currentIndex'] ?? 0) ||
              _isPlaying != (state['isPlaying'] ?? false) ||
              _playbackSpeed != newSpeed ||
              _followMode != (state['followMode'] ?? false)) {
            
            setState(() {
              _currentIndex = state['currentIndex'] ?? 0;
              _isPlaying = state['isPlaying'] ?? false;
              // Handle both int and double for playbackSpeed
              final speed = state['playbackSpeed'];
              _playbackSpeed = speed is int ? speed.toDouble() : (speed ?? 1.0);
              _followMode = state['followMode'] ?? false;
            });
          }
        }
      } catch (e) {
        // Cesium may not be fully loaded yet, ignore errors
      }
    });
  }

  String _formatTime(int pointIndex) {
    if (widget.trackPoints.isEmpty || pointIndex >= widget.trackPoints.length) {
      return '00:00';
    }
    
    // Use actual time from track points if available
    final seconds = pointIndex; // Simplification - should use actual timestamps
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      // Remove maxWidth constraint to span full width
      decoration: BoxDecoration(
        color: colorScheme.surface,
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Live stats row
              if (widget.trackPoints.isNotEmpty && _currentIndex < widget.trackPoints.length)
                _buildLiveStatsRow(),
              
              const SizedBox(height: 4),
              
              // Controls and timeline row
              _buildControlsAndTimelineRow(),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildLiveStatsRow() {
    if (_currentIndex >= widget.trackPoints.length) {
      return const SizedBox.shrink();
    }
    
    final point = widget.trackPoints[_currentIndex];
    // Use GPS altitude for statistics display
    final altitude = (point['altitude'] as num?)?.toDouble() ?? 0.0;
    final climbRate = (point['climbRate'] as num?)?.toDouble() ?? 0.0;
    
    // Debug log to see what data we're getting
    if (_currentIndex % 10 == 0) { // Log every 10th point to avoid spam
      LoggingService.debug('Cesium3DPlayback: Point $_currentIndex - climbRate in data: ${point['climbRate']}, parsed: $climbRate');
    }
    
    // Calculate ground speed if we have previous point
    double groundSpeed = 0.0;
    if (_currentIndex > 0) {
      final prevPoint = widget.trackPoints[_currentIndex - 1];
      final dlat = ((point['latitude'] as num) - (prevPoint['latitude'] as num)) * 111320;
      final dlon = ((point['longitude'] as num) - (prevPoint['longitude'] as num)) * 
                   111320 * math.cos((point['latitude'] as num) * (math.pi / 180));
      final distance = math.sqrt(dlat * dlat + dlon * dlon);
      
      // Parse timestamps and calculate actual time difference
      final currentTime = DateTime.parse(point['timestamp'] as String);
      final prevTime = DateTime.parse(prevPoint['timestamp'] as String);
      final timeDiff = currentTime.difference(prevTime).inSeconds;
      
      if (timeDiff > 0) {
        groundSpeed = distance / timeDiff; // m/s
      }
    }
    
    // Get time of day from timestamp
    String timeOfDay = '00:00';
    if (point['timestamp'] != null) {
      final currentTime = DateTime.parse(point['timestamp'] as String);
      timeOfDay = '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}';
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
          timeOfDay,
          Icons.schedule,
        ),
      ],
    );
  }
  
  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
  
  Widget _buildControlsAndTimelineRow() {
    return Row(
      children: [
        // Play/Pause button
        InkWell(
          onTap: () async {
            if (_isPlaying) {
              await widget.controller.pausePlayback();
            } else {
              await widget.controller.startPlayback();
            }
            // Don't set local state - let it update from getPlaybackState
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              size: 24,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        
        const SizedBox(width: 4),
        
        // Playback speed indicator
        InkWell(
          key: _speedButtonKey,
          onTap: _showSpeedMenu,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            alignment: Alignment.center,
            child: Text(
              '${_playbackSpeed.toInt()}x',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 8),
        
        // Timeline scrubber
        Expanded(
          child: _buildInlineTimelineScrubber(),
        ),
      ],
    );
  }
  
  Widget _buildInlineTimelineScrubber() {
    return SizedBox(
      height: 32,
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
              widthFactor: _totalPoints > 1 
                  ? _currentIndex / (_totalPoints - 1) 
                  : 0,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          
          // Scrubber handle
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              trackHeight: 4,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
            ),
            child: Slider(
              value: _currentIndex.toDouble(),
              min: 0,
              max: (_totalPoints - 1).toDouble(),
              onChanged: (value) async {
                final newIndex = value.round();
                // Only update if the change is significant to reduce GPU load
                if ((newIndex - _currentIndex).abs() >= 1) {
                  setState(() {
                    _currentIndex = newIndex;
                  });
                  await widget.controller.seekToPosition(newIndex);
                  // Haptic feedback on scrub
                  HapticFeedback.selectionClick();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
  
  void _showSpeedMenu() {
    // Get the render box of the speed button specifically
    final RenderBox button = _speedButtonKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    
    // Calculate position relative to the speed button
    final Offset buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);
    final Size buttonSize = button.size;
    
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(
        buttonPosition.dx,
        buttonPosition.dy,
        buttonSize.width,
        buttonSize.height,
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
    ).then((value) async {
      if (value != null) {
        setState(() {
          _playbackSpeed = value;
        });
        await widget.controller.setPlaybackSpeed(value);
      }
    });
  }
}