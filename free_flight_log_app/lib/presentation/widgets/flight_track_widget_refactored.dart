import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';
import '../../services/logging_service.dart';
import '../controllers/flight_playback_controller.dart';
import 'flight_track/flight_track_map.dart';
import 'flight_track/flight_track_legend.dart';
import 'flight_track/flight_track_stats.dart';
import 'flight_track/flight_altitude_chart_simple.dart';
import 'flight_playback_panel.dart';

/// Configuration for the flight track widget display
class FlightTrackConfig {
  final bool embedded;
  final bool showLegend;
  final bool showFAB;
  final bool interactive;
  final bool showStraightLine;
  final bool showChart;
  final bool showStats;
  final double? height;

  const FlightTrackConfig({
    this.embedded = false,
    this.showLegend = true,
    this.showFAB = true,
    this.interactive = true,
    this.showStraightLine = true,
    this.showChart = true,
    this.showStats = true,
    this.height,
  });

  const FlightTrackConfig.embedded({
    this.height = 250,
  }) : embedded = true,
       showLegend = false,
       showFAB = false,
       interactive = false,
       showStraightLine = true,
       showChart = false,
       showStats = false;

  const FlightTrackConfig.embeddedMap({
    this.height = 400,
  }) : embedded = true,
       showLegend = true,
       showFAB = true,
       interactive = true,
       showStraightLine = true,
       showChart = false,
       showStats = true;
}

/// Refactored Flight Track Widget - now modular and maintainable
class FlightTrackWidget extends StatefulWidget {
  final Flight flight;
  final FlightTrackConfig config;
  final bool autoLoad;

  const FlightTrackWidget({
    super.key,
    required this.flight,
    this.config = const FlightTrackConfig(),
    this.autoLoad = true,
  });

  @override
  State<FlightTrackWidget> createState() => _FlightTrackWidgetState();
}

class _FlightTrackWidgetState extends State<FlightTrackWidget> 
    with WidgetsBindingObserver {
  final IgcImportService _importService = IgcImportService();
  
  IgcFile? _igcData;
  bool _isLoading = false;
  String? _errorMessage;
  bool _showChart = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    if (widget.autoLoad) {
      _loadFlightData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(FlightTrackWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Reload if flight changed
    if (oldWidget.flight.id != widget.flight.id) {
      _loadFlightData();
    }
  }

  Future<void> _loadFlightData() async {
    if (widget.flight.trackLogPath == null) {
      LoggingService.debug('FlightTrackWidget: No track log path for flight ${widget.flight.id}');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      LoggingService.debug('FlightTrackWidget: Loading IGC data from ${widget.flight.trackLogPath}');
      final startTime = DateTime.now();
      
      final igcData = await _importService.parser.parseFile(widget.flight.trackLogPath!);
      
      final duration = DateTime.now().difference(startTime);
      LoggingService.performance('Load IGC data', duration, '${igcData.trackPoints.length} track points');

      if (mounted) {
        setState(() {
          _igcData = igcData;
          _isLoading = false;
        });
      }
    } catch (e) {
      LoggingService.error('FlightTrackWidget: Failed to load IGC data', e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load track data: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _toggleChart() {
    setState(() {
      _showChart = !_showChart;
    });
    LoggingService.ui('FlightTrackWidget', 'Toggle chart', _showChart ? 'show' : 'hide');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingWidget();
    }

    if (_errorMessage != null) {
      return _buildErrorWidget();
    }

    return _buildMainWidget();
  }

  Widget _buildLoadingWidget() {
    return Container(
      height: widget.config.height ?? 400,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading flight track...'),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      height: widget.config.height ?? 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              'Error Loading Track',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.red[700],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.red[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadFlightData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainWidget() {
    // Check if we need to show chart alongside map
    final showChart = widget.config.showChart && (_igcData?.trackPoints.isNotEmpty ?? false);

    // If embedded mode, return the unified widget directly
    if (widget.config.embedded) {
      return showChart ? _buildUnifiedVisualization() : _buildMapSection();
    }

    // For full screen mode, wrap in scroll view
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: showChart ? _buildUnifiedVisualization() : _buildMapSection(),
    );
  }

  Widget _buildMapSection() {
    return Container(
      height: widget.config.height ?? 400,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Main map
          FlightTrackMap(
            flight: widget.flight,
            igcData: _igcData,
            config: FlightMapConfig(
              interactive: widget.config.interactive,
              showStraightLine: widget.config.showStraightLine,
              height: widget.config.height,
            ),
          ),

          // Legend (if enabled)
          if (widget.config.showLegend && (_igcData?.trackPoints.isNotEmpty ?? false))
            Positioned(
              top: 16,
              left: 16,
              child: FlightTrackLegend(
                igcData: _igcData,
                compact: widget.config.embedded,
              ),
            ),

          // Statistics (if enabled)
          if (widget.config.showStats && (_igcData?.trackPoints.isNotEmpty ?? false))
            FlightTrackStats(
              flight: widget.flight,
              igcData: _igcData,
              mode: widget.config.embedded 
                  ? StatsDisplayMode.compact 
                  : StatsDisplayMode.floating,
            ),

          // Map controls (if interactive) - disabled for now
          // TODO: Add map controller instance to enable controls
          // if (widget.config.interactive && widget.config.showFAB)
          //   FlightMapControls(
          //     mapController: _mapController,
          //     onLayerChanged: () => setState(() {}),
          //   ),

          // Chart toggle FAB (if enabled)
          if (widget.config.showFAB && 
              widget.config.showChart && 
              (_igcData?.trackPoints.isNotEmpty ?? false))
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                onPressed: _toggleChart,
                tooltip: _showChart ? 'Hide Chart' : 'Show Chart',
                child: Icon(_showChart ? Icons.show_chart_outlined : Icons.show_chart),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUnifiedVisualization() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Map section (no individual container/shadow)
            _buildMapContent(),
            
            // Chart section (if toggled on)
            if (_showChart) _buildChartContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildMapContent() {
    return SizedBox(
      height: widget.config.height ?? 400,
      child: Stack(
        children: [
          // Main map (no border radius - handled by parent ClipRRect)
          FlightTrackMap(
            flight: widget.flight,
            igcData: _igcData,
            config: FlightMapConfig(
              interactive: widget.config.interactive,
              showStraightLine: widget.config.showStraightLine,
              height: widget.config.height,
            ),
          ),

          // Legend (if enabled)
          if (widget.config.showLegend && (_igcData?.trackPoints.isNotEmpty ?? false))
            Positioned(
              top: 16,
              left: 16,
              child: FlightTrackLegend(
                igcData: _igcData,
                compact: widget.config.embedded,
              ),
            ),

          // Statistics (if enabled)
          if (widget.config.showStats && (_igcData?.trackPoints.isNotEmpty ?? false))
            FlightTrackStats(
              flight: widget.flight,
              igcData: _igcData,
              mode: widget.config.embedded 
                  ? StatsDisplayMode.compact 
                  : StatsDisplayMode.floating,
            ),

          // Chart toggle FAB (if enabled)
          if (widget.config.showFAB && 
              widget.config.showChart && 
              (_igcData?.trackPoints.isNotEmpty ?? false))
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                onPressed: _toggleChart,
                tooltip: _showChart ? 'Hide Chart' : 'Show Chart',
                child: Icon(_showChart ? Icons.show_chart_outlined : Icons.show_chart),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChartContent() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // Title
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Flight Altitude Profile',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Chart content
          Expanded(
            child: FlightAltitudeChart(
              flight: widget.flight,
              igcData: _igcData,
              height: double.infinity, // Let it expand to fill
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    if (!_showChart || (_igcData?.trackPoints.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }

    return FlightAltitudeChart(
      flight: widget.flight,
      igcData: _igcData,
      height: 200,
    );
  }
}