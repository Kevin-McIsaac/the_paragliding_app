import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../utils/flyability_helper.dart';

/// Week summary table showing flyability for multiple sites across 7 days
/// Sites are rows, days are columns with color-coded daily summary
class WeekSummaryTable extends StatelessWidget {
  final List<ParaglidingSite> sites;
  final Map<int, Map<String, List<WindData?>>> windDataByDay; // dayIndex -> siteKey -> hourly data
  final double maxWindSpeed;
  final double maxWindGusts;
  final Function(int dayIndex)? onDayTap;

  static const double _cellSize = 48.0;
  static const double _siteColumnWidth = 120.0;
  static const double _headerHeight = 36.0;

  const WeekSummaryTable({
    super.key,
    required this.sites,
    required this.windDataByDay,
    required this.maxWindSpeed,
    required this.maxWindGusts,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(_cellSize),
            columnWidths: const {
              0: FixedColumnWidth(_siteColumnWidth),
            },
            border: TableBorder.all(
              color: Theme.of(context).dividerColor,
              width: 1.0,
            ),
            children: [
              _buildHeaderRow(context),
              ...sites.map((site) => _buildSiteRow(context, site)),
            ],
          ),
        ),

        // Legend
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem(
                FlyabilityHelper.getColorForLevel(FlyabilityLevel.safe),
                'Flyable (2+ consecutive green hours)',
              ),
              _buildLegendItem(
                FlyabilityHelper.getColorForLevel(FlyabilityLevel.caution),
                'Caution',
              ),
              _buildLegendItem(
                FlyabilityHelper.getColorForLevel(FlyabilityLevel.unsafe),
                'Not Flyable',
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'Tap any day column to see hourly details',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  TableRow _buildHeaderRow(BuildContext context) {
    final now = DateTime.now();

    return TableRow(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      children: [
        Container(
          height: _headerHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: const Text(
            'Site',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        ...List.generate(7, (dayIndex) {
          final date = now.add(Duration(days: dayIndex));
          final dayName = DateFormat('EEE').format(date);
          final dayNum = DateFormat('d').format(date);

          return InkWell(
            onTap: () => onDayTap?.call(dayIndex),
            child: Container(
              height: _headerHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    dayNum,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  TableRow _buildSiteRow(BuildContext context, ParaglidingSite site) {
    final siteKey = '${site.latitude.toStringAsFixed(4)}_${site.longitude.toStringAsFixed(4)}';

    return TableRow(
      children: [
        // Site name cell
        Container(
          height: _cellSize,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Tooltip(
            message: site.name,
            child: Text(
              site.name,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
        // Day cells
        ...List.generate(7, (dayIndex) {
          final dayData = windDataByDay[dayIndex];
          if (dayData == null) return _buildEmptyCell();

          final siteWindData = dayData[siteKey];
          if (siteWindData == null) return _buildEmptyCell();

          return _buildSummaryCell(
            context: context,
            site: site,
            dayIndex: dayIndex,
            hourlyData: siteWindData,
          );
        }),
      ],
    );
  }

  Widget _buildEmptyCell() {
    return Container(
      height: _cellSize,
      alignment: Alignment.center,
      child: const Text(
        '-',
        style: TextStyle(fontSize: 10, color: Colors.grey),
      ),
    );
  }

  Widget _buildSummaryCell({
    required BuildContext context,
    required ParaglidingSite site,
    required int dayIndex,
    required List<WindData?> hourlyData,
  }) {
    // Calculate daily summary (peak hours: 10am-4pm, indices 3-9 in 7am-7pm range)
    final peakHours = hourlyData.sublist(3, 10); // 10am (index 3) to 4pm (index 9)

    final flyabilityLevel = _calculateDailySummary(
      peakHours: peakHours,
      site: site,
    );

    final bgColor = FlyabilityHelper.getColorForLevel(flyabilityLevel);

    // Generate tooltip
    final tooltipMessage = _generateTooltip(
      flyabilityLevel: flyabilityLevel,
      peakHours: peakHours,
      site: site,
      dayIndex: dayIndex,
    );

    return InkWell(
      onTap: () => onDayTap?.call(dayIndex),
      child: Tooltip(
        message: tooltipMessage,
        child: Container(
          height: _cellSize,
          alignment: Alignment.center,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
            ),
          ),
        ),
      ),
    );
  }

  FlyabilityLevel _calculateDailySummary({
    required List<WindData?> peakHours,
    required ParaglidingSite site,
  }) {
    // Calculate flyability for each peak hour
    final levels = peakHours.map((windData) {
      if (windData == null) return null;

      return FlyabilityHelper.getFlyabilityLevel(
        windData: windData,
        siteDirections: site.windDirections,
        maxSpeed: maxWindSpeed,
        maxGusts: maxWindGusts,
      );
    }).toList();

    // Check for 2+ consecutive green hours
    bool hasTwoConsecutiveGreen = false;
    for (int i = 0; i < levels.length - 1; i++) {
      if (levels[i] == FlyabilityLevel.safe && levels[i + 1] == FlyabilityLevel.safe) {
        hasTwoConsecutiveGreen = true;
        break;
      }
    }

    if (hasTwoConsecutiveGreen) {
      return FlyabilityLevel.safe;
    }

    // Check for any red (unsafe) hours
    if (levels.contains(FlyabilityLevel.unsafe)) {
      return FlyabilityLevel.unsafe;
    }

    // Check for 2+ consecutive yellow hours
    bool hasTwoConsecutiveYellow = false;
    for (int i = 0; i < levels.length - 1; i++) {
      if (levels[i] == FlyabilityLevel.caution && levels[i + 1] == FlyabilityLevel.caution) {
        hasTwoConsecutiveYellow = true;
        break;
      }
    }

    if (hasTwoConsecutiveYellow) {
      return FlyabilityLevel.caution;
    }

    // Default to unsafe if no clear pattern
    return FlyabilityLevel.unsafe;
  }

  String _generateTooltip({
    required FlyabilityLevel flyabilityLevel,
    required List<WindData?> peakHours,
    required ParaglidingSite site,
    required int dayIndex,
  }) {
    final date = DateTime.now().add(Duration(days: dayIndex));
    final formattedDate = DateFormat('EEE, MMM d').format(date);

    final levelText = flyabilityLevel == FlyabilityLevel.safe
        ? 'Flyable'
        : flyabilityLevel == FlyabilityLevel.caution
            ? 'Caution'
            : 'Not Flyable';

    return '$formattedDate - ${site.name}\n$levelText (based on 10am-4pm conditions)\nTap to see hourly details';
  }

  IconData _getIconForLevel(FlyabilityLevel level) {
    switch (level) {
      case FlyabilityLevel.safe:
        return Icons.check_circle;
      case FlyabilityLevel.caution:
        return Icons.warning;
      case FlyabilityLevel.unsafe:
        return Icons.cancel;
      case FlyabilityLevel.unknown:
        return Icons.help_outline;
    }
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}
