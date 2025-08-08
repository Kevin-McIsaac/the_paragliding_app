import 'package:flutter/material.dart';
import '../../data/models/igc_file.dart';

enum PlaybackState {
  stopped,
  playing,
  paused,
}

/// Controller for managing flight playback functionality
class FlightPlaybackController extends ChangeNotifier {
  // Track data
  final List<IgcPoint> trackPoints;
  final Duration totalDuration;
  final List<double> instantaneousClimbRates;
  final List<double> averagedClimbRates;
  
  // Playback state
  PlaybackState _state = PlaybackState.stopped;
  int _currentPointIndex = 0;
  double _playbackSpeed = 1.0;
  
  // Animation
  AnimationController? _animationController;
  Animation<double>? _animation;
  TickerProvider? _currentVsync;
  
  // Constructor
  FlightPlaybackController({
    required this.trackPoints,
    required this.instantaneousClimbRates,
    required this.averagedClimbRates,
  }) : totalDuration = trackPoints.isNotEmpty
      ? trackPoints.last.timestamp.difference(trackPoints.first.timestamp)
      : Duration.zero {
    // Initialize to first point
    if (trackPoints.isNotEmpty) {
      _currentPointIndex = 0;
    }
  }
  
  // Getters
  PlaybackState get state => _state;
  int get currentPointIndex => _currentPointIndex;
  double get playbackSpeed => _playbackSpeed;
  
  IgcPoint? get currentPoint => 
      trackPoints.isNotEmpty && _currentPointIndex < trackPoints.length
          ? trackPoints[_currentPointIndex]
          : null;
  
  Duration get currentTime => currentPoint != null
      ? currentPoint!.timestamp.difference(trackPoints.first.timestamp)
      : Duration.zero;
  
  double get progress => totalDuration.inMilliseconds > 0
      ? currentTime.inMilliseconds / totalDuration.inMilliseconds
      : 0.0;
  
  // Playback control methods
  void play(TickerProvider vsync) {
    if (_state == PlaybackState.playing) return;
    
    if (_currentPointIndex >= trackPoints.length - 1) {
      // Reset if at end
      _currentPointIndex = 0;
    }
    
    _currentVsync = vsync; // Store for later use
    _state = PlaybackState.playing;
    _startAnimation(vsync);
    notifyListeners();
  }
  
  void pause() {
    if (_state != PlaybackState.playing) return;
    
    _state = PlaybackState.paused;
    _animationController?.stop();
    notifyListeners();
  }
  
  void stop() {
    _state = PlaybackState.stopped;
    _currentPointIndex = 0;
    _animationController?.stop();
    _animationController?.dispose();
    _animationController = null;
    notifyListeners();
  }
  
  void togglePlayPause(TickerProvider vsync) {
    if (_state == PlaybackState.playing) {
      pause();
    } else {
      play(vsync);
    }
  }
  
  // Speed control
  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    
    // If currently playing, restart animation with new speed
    if (_state == PlaybackState.playing && _animationController != null && _currentVsync != null) {
      // Use current point index instead of animation progress to maintain position
      final currentIndex = _currentPointIndex;
      _animationController!.stop();
      
      // Restart animation from current point index with new speed
      _startAnimationFromIndex(currentIndex, _currentVsync!);
    }
    
    notifyListeners();
  }
  
  // Timeline scrubbing
  void seekToProgress(double progress) {
    progress = progress.clamp(0.0, 1.0);
    final targetTime = Duration(
      milliseconds: (totalDuration.inMilliseconds * progress).round()
    );
    seekToTime(targetTime);
  }
  
  void seekToTime(Duration time) {
    if (trackPoints.isEmpty) return;
    
    // Find the point closest to the target time
    final targetTimestamp = trackPoints.first.timestamp.add(time);
    
    int bestIndex = 0;
    Duration smallestDiff = Duration(days: 365);
    
    for (int i = 0; i < trackPoints.length; i++) {
      final diff = trackPoints[i].timestamp.difference(targetTimestamp).abs();
      if (diff < smallestDiff) {
        smallestDiff = diff;
        bestIndex = i;
      }
    }
    
    _currentPointIndex = bestIndex;
    notifyListeners();
  }
  
  void seekToIndex(int index) {
    if (index < 0 || index >= trackPoints.length) return;
    _currentPointIndex = index;
    notifyListeners();
  }
  
  // Skip controls
  void skipForward({Duration amount = const Duration(seconds: 10)}) {
    final newTime = currentTime + amount;
    if (newTime <= totalDuration) {
      seekToTime(newTime);
    } else {
      _currentPointIndex = trackPoints.length - 1;
      notifyListeners();
    }
  }
  
  void skipBackward({Duration amount = const Duration(seconds: 10)}) {
    final newTime = currentTime - amount;
    if (newTime >= Duration.zero) {
      seekToTime(newTime);
    } else {
      _currentPointIndex = 0;
      notifyListeners();
    }
  }
  
  // Animation management
  void _startAnimation(TickerProvider vsync) {
    _animationController?.dispose();
    
    final remainingPoints = trackPoints.length - _currentPointIndex - 1;
    if (remainingPoints <= 0) return;
    
    _animationController = AnimationController(
      vsync: vsync,
      duration: _calculateAnimationDuration(),
    );
    
    _animation = Tween<double>(
      begin: _currentPointIndex.toDouble(),
      end: (trackPoints.length - 1).toDouble(),
    ).animate(_animationController!);
    
    _animation!.addListener(() {
      final newIndex = _animation!.value.round();
      if (newIndex != _currentPointIndex) {
        _currentPointIndex = newIndex;
        notifyListeners();
      }
    });
    
    _animationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        stop();
      }
    });
    
    _animationController!.forward();
  }
  
  /// Start animation from a specific point index (used when changing speed during playback)
  void _startAnimationFromIndex(int startIndex, TickerProvider vsync) {
    _animationController?.dispose();
    
    // Set current position
    _currentPointIndex = startIndex.clamp(0, trackPoints.length - 1);
    
    // Create new animation from current position to end
    final remainingPoints = trackPoints.length - _currentPointIndex - 1;
    if (remainingPoints <= 0) {
      stop();
      return;
    }
    
    _animationController = AnimationController(
      vsync: vsync,
      duration: _calculateAnimationDuration(),
    );
    
    _animation = Tween<double>(
      begin: _currentPointIndex.toDouble(),
      end: (trackPoints.length - 1).toDouble(),
    ).animate(_animationController!);
    
    _animation!.addListener(() {
      final newIndex = _animation!.value.round();
      if (newIndex != _currentPointIndex) {
        _currentPointIndex = newIndex;
        notifyListeners();
      }
    });
    
    _animationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        stop();
      }
    });
    
    _animationController!.forward();
  }
  
  Duration _calculateAnimationDuration() {
    if (trackPoints.isEmpty || _currentPointIndex >= trackPoints.length - 1) {
      return Duration.zero;
    }
    
    final remainingTime = trackPoints.last.timestamp
        .difference(trackPoints[_currentPointIndex].timestamp);
    
    return Duration(
      milliseconds: (remainingTime.inMilliseconds / _playbackSpeed).round()
    );
  }
  
  // Event detection for timeline markers
  List<FlightEvent> detectEvents() {
    final events = <FlightEvent>[];
    
    if (trackPoints.isEmpty) return events;
    
    double maxAltitude = 0;
    int maxAltitudeIndex = 0;
    double maxClimbRate = 0;
    int maxClimbIndex = 0;
    
    // Analyze track for events
    for (int i = 0; i < trackPoints.length; i++) {
      final point = trackPoints[i];
      
      // Track max altitude
      final altitude = point.pressureAltitude > 0 
          ? point.pressureAltitude.toDouble() 
          : point.gpsAltitude.toDouble();
      
      if (altitude > maxAltitude) {
        maxAltitude = altitude;
        maxAltitudeIndex = i;
      }
      
      // Track max climb rate
      if (i < averagedClimbRates.length && averagedClimbRates[i] > maxClimbRate) {
        maxClimbRate = averagedClimbRates[i];
        maxClimbIndex = i;
      }
      
      // Detect thermal entry (sustained climb > 1.5 m/s)
      if (i < averagedClimbRates.length && averagedClimbRates[i] > 1.5) {
        // Check if this is a new thermal (not continuation)
        if (i == 0 || i - 1 >= averagedClimbRates.length || averagedClimbRates[i - 1] <= 1.5) {
          events.add(FlightEvent(
            type: EventType.thermalEntry,
            pointIndex: i,
            timestamp: point.timestamp,
            value: averagedClimbRates[i],
          ));
        }
      }
    }
    
    // Add milestone events
    events.add(FlightEvent(
      type: EventType.maxAltitude,
      pointIndex: maxAltitudeIndex,
      timestamp: trackPoints[maxAltitudeIndex].timestamp,
      value: maxAltitude,
    ));
    
    if (maxClimbRate > 0) {
      events.add(FlightEvent(
        type: EventType.maxClimb,
        pointIndex: maxClimbIndex,
        timestamp: trackPoints[maxClimbIndex].timestamp,
        value: maxClimbRate,
      ));
    }
    
    // Add takeoff and landing
    events.add(FlightEvent(
      type: EventType.takeoff,
      pointIndex: 0,
      timestamp: trackPoints.first.timestamp,
    ));
    
    events.add(FlightEvent(
      type: EventType.landing,
      pointIndex: trackPoints.length - 1,
      timestamp: trackPoints.last.timestamp,
    ));
    
    // Sort by timestamp
    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    return events;
  }
  
  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }
}

/// Represents a significant event during the flight
class FlightEvent {
  final EventType type;
  final int pointIndex;
  final DateTime timestamp;
  final double? value; // Optional value (altitude, climb rate, etc.)
  
  FlightEvent({
    required this.type,
    required this.pointIndex,
    required this.timestamp,
    this.value,
  });
  
  String get label {
    switch (type) {
      case EventType.takeoff:
        return 'Takeoff';
      case EventType.landing:
        return 'Landing';
      case EventType.maxAltitude:
        return 'Max Alt: ${value?.toStringAsFixed(0)}m';
      case EventType.maxClimb:
        return 'Max Climb: ${value?.toStringAsFixed(1)}m/s';
      case EventType.thermalEntry:
        return 'Thermal: +${value?.toStringAsFixed(1)}m/s';
      default:
        return type.toString();
    }
  }
}

enum EventType {
  takeoff,
  landing,
  maxAltitude,
  maxClimb,
  thermalEntry,
}