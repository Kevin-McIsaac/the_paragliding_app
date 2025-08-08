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
  bool _isExpanded = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  
  // Speed options
  final List<double> _speedOptions = [1.0, 10.0, 30.0, 60.0];
  
  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
    
    // Listen to controller changes
    widget.controller.addListener(_onControllerChanged);
  }
  
  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _expandController.dispose();
    super.dispose();
  }
  
  void _onControllerChanged() {
    setState(() {
      // Update UI when controller state changes
    });
  }
  
  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
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
            // Drag handle
            GestureDetector(
              onTap: _toggleExpanded,
              child: Container(
                height: 6,
                width: 40,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            
            // Collapsed view - minimal controls
            _buildCollapsedView(),
            
            // Expanded view - full controls
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: _buildExpandedView(),
            ),
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
          // Timeline scrubber
          _buildTimelineScrubber(),
          
          const SizedBox(height: 8),
          
          // Minimal controls row
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
              
              // Speed indicator
              TextButton(
                onPressed: _showSpeedMenu,
                child: Text(
                  '${widget.controller.playbackSpeed.toInt()}x',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              // Expand/Collapse button
              IconButton(
                onPressed: _toggleExpanded,
                icon: Icon(_isExpanded ? Icons.expand_more : Icons.expand_less),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildExpandedView() {
    final point = widget.controller.currentPoint;
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Full playback controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Skip backward
              IconButton(
                onPressed: () => widget.controller.skipBackward(),
                icon: const Icon(Icons.replay_10),
                iconSize: 28,
              ),
              
              // Stop
              IconButton(
                onPressed: widget.controller.stop,
                icon: const Icon(Icons.stop),
                iconSize: 28,
              ),
              
              // Play/Pause (larger)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: IconButton(
                  onPressed: () => widget.controller.togglePlayPause(this),
                  icon: Icon(
                    widget.controller.state == PlaybackState.playing
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  iconSize: 40,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              
              // Skip forward
              IconButton(
                onPressed: () => widget.controller.skipForward(),
                icon: const Icon(Icons.forward_10),
                iconSize: 28,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Speed controls - wrapped for mobile
          Row(
            children: [
              const Text('Speed: '),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4.0,
                  children: _speedOptions.map((speed) => 
                    ChoiceChip(
                      label: Text('${speed.toInt()}x'),
                      selected: widget.controller.playbackSpeed == speed,
                      onSelected: (selected) {
                        if (selected) {
                          widget.controller.setPlaybackSpeed(speed);
                        }
                      },
                    ),
                  ).toList(),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Live statistics
          if (point != null) _buildLiveStats(point),
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
  
  Widget _buildLiveStats(IgcPoint point) {
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
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'Altitude',
            '${altitude.toStringAsFixed(0)}m',
            Icons.height,
          ),
          _buildStatItem(
            'Climb Rate',
            '${climbRate > 0 ? '+' : ''}${climbRate.toStringAsFixed(1)}m/s',
            climbRate > 0 ? Icons.arrow_upward : Icons.arrow_downward,
          ),
          // Note: groundSpeed not available in IgcPoint, skip for now
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