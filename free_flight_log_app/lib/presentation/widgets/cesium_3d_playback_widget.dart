import 'package:flutter/material.dart';
import 'dart:async';
import 'cesium/cesium_webview_controller.dart';
import '../../services/logging_service.dart';

/// Playback controls for 3D flight animation
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
  double _playbackSpeed = 1.0;
  bool _followMode = false;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _totalPoints = widget.trackPoints.length;
    _startUpdateTimer();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (_isPlaying) {
        final state = await widget.controller.getPlaybackState();
        if (mounted) {
          setState(() {
            _currentIndex = state['currentIndex'] ?? 0;
            _isPlaying = state['isPlaying'] ?? false;
            _playbackSpeed = state['playbackSpeed'] ?? 1.0;
            _followMode = state['followMode'] ?? false;
          });
        }
      }
    });
  }

  String _formatTime(int pointIndex) {
    if (widget.trackPoints.isEmpty || pointIndex >= widget.trackPoints.length) {
      return '00:00';
    }
    
    // Assume 1 second per point for simplicity
    // In real implementation, use actual timestamps
    final seconds = pointIndex;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350, // Fixed width to avoid layout issues
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Flight Playback',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: widget.onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Timeline scrubber
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(_currentIndex),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      _formatTime(_totalPoints),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                Slider(
                  value: _currentIndex.toDouble(),
                  min: 0,
                  max: (_totalPoints - 1).toDouble(),
                  divisions: _totalPoints > 1 ? _totalPoints - 1 : 1,
                  onChanged: (value) {
                    setState(() {
                      _currentIndex = value.round();
                    });
                    widget.controller.seekToPosition(_currentIndex);
                  },
                  activeColor: Colors.blue,
                  inactiveColor: Colors.grey[700],
                ),
              ],
            ),
            
            // Playback controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Step backward
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  onPressed: () {
                    widget.controller.stepBackward();
                  },
                ),
                // Play/Pause
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: Colors.white,
                    size: 48,
                  ),
                  onPressed: () async {
                    if (_isPlaying) {
                      await widget.controller.pausePlayback();
                    } else {
                      await widget.controller.startPlayback();
                    }
                    setState(() {
                      _isPlaying = !_isPlaying;
                    });
                  },
                ),
                // Step forward
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  onPressed: () {
                    widget.controller.stepForward();
                  },
                ),
                // Stop
                IconButton(
                  icon: const Icon(Icons.stop_circle, color: Colors.white),
                  onPressed: () async {
                    await widget.controller.stopPlayback();
                    setState(() {
                      _isPlaying = false;
                      _currentIndex = 0;
                    });
                  },
                ),
              ],
            ),
            
            // Speed control
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  const Text(
                    'Speed:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: _playbackSpeed,
                      min: 0.25,
                      max: 8.0,
                      divisions: 15,
                      label: '${_playbackSpeed}x',
                      onChanged: (value) {
                        setState(() {
                          _playbackSpeed = value;
                        });
                        widget.controller.setPlaybackSpeed(value);
                      },
                      activeColor: Colors.orange,
                      inactiveColor: Colors.grey[700],
                    ),
                  ),
                  Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            
            // Follow mode toggle
            CheckboxListTile(
              title: const Text(
                'Follow Mode',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              subtitle: const Text(
                'Camera follows the pilot',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: _followMode,
              onChanged: (value) {
                setState(() {
                  _followMode = value ?? false;
                });
                widget.controller.setFollowMode(_followMode);
              },
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.blue,
            ),
            
            // Flight info
            if (widget.trackPoints.isNotEmpty && _currentIndex < widget.trackPoints.length)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildInfoItem(
                      'Altitude',
                      '${(widget.trackPoints[_currentIndex]['altitude'] as num?)?.toStringAsFixed(0) ?? 0}m',
                    ),
                    _buildInfoItem(
                      'Climb',
                      '${(widget.trackPoints[_currentIndex]['climbRate'] as num?)?.toStringAsFixed(1) ?? 0} m/s',
                      color: _getClimbRateColor((widget.trackPoints[_currentIndex]['climbRate'] as num?)?.toDouble() ?? 0.0),
                    ),
                    _buildInfoItem(
                      'Progress',
                      '${((_currentIndex / (_totalPoints - 1)) * 100).toStringAsFixed(0)}%',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _getClimbRateColor(double climbRate) {
    if (climbRate >= 0) {
      return Colors.green;
    } else if (climbRate > -1.5) {
      return Colors.blue;
    } else {
      return Colors.red;
    }
  }
}