import '../services/logging_service.dart';

/// Tracks performance metrics for the airspace rendering pipeline with clear stage boundaries
class AirspacePipelineMetrics {
  final Stopwatch _overallStopwatch = Stopwatch();
  final Stopwatch _currentStageStopwatch = Stopwatch();

  final Map<String, int> _stageDurations = {};
  String? _currentStage;

  /// Start the overall pipeline measurement
  void startPipeline() {
    _overallStopwatch.reset();
    _overallStopwatch.start();
    _stageDurations.clear();
    _currentStage = null;
  }

  /// Start a specific pipeline stage
  void startStage(String stageName) {
    _endCurrentStage();
    _currentStage = stageName;
    _currentStageStopwatch.reset();
    _currentStageStopwatch.start();
  }

  /// End the current stage if one is active
  void _endCurrentStage() {
    if (_currentStage != null && _currentStageStopwatch.isRunning) {
      _currentStageStopwatch.stop();
      _stageDurations[_currentStage!] = _currentStageStopwatch.elapsedMilliseconds;
      _currentStageStopwatch.reset();
    }
  }

  /// End the pipeline and log comprehensive metrics
  void endPipeline({
    required int airspaceCount,
    required String bounds,
    Map<String, dynamic>? additionalData,
  }) {
    _endCurrentStage();
    _overallStopwatch.stop();

    final totalMeasured = _stageDurations.values.fold(0, (sum, duration) => sum + duration);
    final overallDuration = _overallStopwatch.elapsedMilliseconds;
    final unmeasuredTime = overallDuration - totalMeasured;

    // Build comprehensive performance log
    final performanceData = {
      'pipeline_total_ms': overallDuration,
      'stages_total_ms': totalMeasured,
      'unmeasured_ms': unmeasuredTime,
      'airspace_count': airspaceCount,
      'bounds': bounds,
      ..._stageDurations.map((stage, duration) => MapEntry('${stage}_ms', duration)),
      ...?additionalData,
    };

    LoggingService.structuredLazy('AIRSPACE_PIPELINE', () => performanceData);

    // Log validation warning if stages don't add up properly
    if (unmeasuredTime.abs() > 5) { // Allow 5ms tolerance
      LoggingService.warning(
        'Pipeline timing mismatch: overall=${overallDuration}ms, stages=${totalMeasured}ms, diff=${unmeasuredTime}ms'
      );
    }
  }

  /// Get current stage durations (for intermediate logging)
  Map<String, int> get stageDurations => Map.unmodifiable(_stageDurations);

  /// Get overall duration so far
  int get overallDuration => _overallStopwatch.elapsedMilliseconds;
}