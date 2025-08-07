import 'package:flutter/material.dart';
import '../../../data/models/flight.dart';
import '../../../data/models/igc_file.dart';
import '../../../utils/date_time_utils.dart';

/// Different display modes for flight statistics
enum StatsDisplayMode {
  floating,    // Floating overlay with all stats
  labelOnly,   // Simple labels without values
  compact,     // Compact horizontal layout
}

/// Widget for displaying flight statistics in various formats
class FlightTrackStats extends StatelessWidget {
  final Flight flight;
  final IgcFile? igcData;
  final StatsDisplayMode mode;
  final bool showBackground;

  const FlightTrackStats({
    super.key,
    required this.flight,
    this.igcData,
    this.mode = StatsDisplayMode.floating,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case StatsDisplayMode.floating:
        return _buildFloatingStats(context);
      case StatsDisplayMode.labelOnly:
        return _buildLabelOnlyStats(context);
      case StatsDisplayMode.compact:
        return _buildCompactStats(context);
    }
  }

  Widget _buildFloatingStats(BuildContext context) {
    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.all(12),
        decoration: showBackground ? BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ) : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Flight Statistics',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ..._buildStatsList(context),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelOnlyStats(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: _buildStatsLabels(context),
      ),
    );
  }

  Widget _buildCompactStats(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: showBackground ? BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ) : null,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _buildCompactStatsList(context),
        ),
      ),
    );
  }

  List<Widget> _buildStatsList(BuildContext context) {
    final stats = <Widget>[];

    // Duration
    stats.add(_buildStatItem(
      context,
      'Duration',
      DateTimeUtils.formatDuration(flight.duration),
      Icons.access_time,
    ));

    // Distance
    if (flight.straightDistance != null) {
      stats.add(_buildStatItem(
        context,
        'Distance',
        '${flight.straightDistance!.toStringAsFixed(1)} km',
        Icons.straighten,
      ));
    }

    // Track distance
    if (flight.distance != null) {
      stats.add(_buildStatItem(
        context,
        'Track Distance',
        '${flight.distance!.toStringAsFixed(1)} km',
        Icons.timeline,
      ));
    }

    // Max altitude
    if (flight.maxAltitude != null) {
      stats.add(_buildStatItem(
        context,
        'Max Altitude',
        '${flight.maxAltitude!.toInt()} m',
        Icons.terrain,
      ));
    }

    // Max climb rate
    if (flight.maxClimbRate != null) {
      stats.add(_buildStatItem(
        context,
        'Max Climb',
        '${flight.maxClimbRate!.toStringAsFixed(1)} m/s',
        Icons.arrow_upward,
      ));
    }

    // Max sink rate
    if (flight.maxSinkRate != null) {
      stats.add(_buildStatItem(
        context,
        'Max Sink',
        '${flight.maxSinkRate!.abs().toStringAsFixed(1)} m/s',
        Icons.arrow_downward,
      ));
    }

    return stats;
  }

  List<Widget> _buildStatsLabels(BuildContext context) {
    final labels = <Widget>[];

    labels.add(_buildLabel(context, 'Duration'));
    if (flight.straightDistance != null) {
      labels.add(_buildLabel(context, 'Distance'));
    }
    if (flight.distance != null) {
      labels.add(_buildLabel(context, 'Track Distance'));
    }
    if (flight.maxAltitude != null) {
      labels.add(_buildLabel(context, 'Max Altitude'));
    }
    if (flight.maxClimbRate != null) {
      labels.add(_buildLabel(context, 'Max Climb'));
    }
    if (flight.maxSinkRate != null) {
      labels.add(_buildLabel(context, 'Max Sink'));
    }

    return labels;
  }

  List<Widget> _buildCompactStatsList(BuildContext context) {
    final stats = <Widget>[];
    var isFirst = true;

    void addStat(String value, IconData icon) {
      if (!isFirst) {
        stats.add(Container(
          width: 1,
          height: 20,
          color: Colors.grey[300],
          margin: const EdgeInsets.symmetric(horizontal: 12),
        ));
      }
      stats.add(_buildCompactStatItem(context, value, icon));
      isFirst = false;
    }

    addStat(DateTimeUtils.formatDuration(flight.duration), Icons.access_time);

    if (flight.straightDistance != null) {
      addStat('${flight.straightDistance!.toStringAsFixed(1)} km', Icons.straighten);
    }

    if (flight.maxAltitude != null) {
      addStat('${flight.maxAltitude!.toInt()} m', Icons.terrain);
    }

    if (flight.maxClimbRate != null) {
      addStat('${flight.maxClimbRate!.toStringAsFixed(1)} m/s', Icons.arrow_upward);
    }

    return stats;
  }

  Widget _buildStatItem(BuildContext context, String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCompactStatItem(BuildContext context, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}