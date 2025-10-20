import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../utils/flyability_helper.dart';

/// Table widget displaying flyability for multiple sites across hours
/// Sites are shown as rows, hours (7am-7pm) as columns
class MultiSiteFlyabilityTable extends StatelessWidget {
  final List<ParaglidingSite> sites;
  final Map<String, List<WindData?>> windDataBySite; // Site key -> 13 hours of wind data
  final DateTime date;
  final double maxWindSpeed;
  final double maxWindGusts;

  // Table constants matching SiteDetailsDialog
  static const double _cellSize = 36.0;
  static const double _siteColumnWidth = 120.0;
  static const int _startHour = 7;
  static const int _hoursToShow = 13; // 7am to 7pm inclusive

  const MultiSiteFlyabilityTable({
    super.key,
    required this.sites,
    required this.windDataBySite,
    required this.date,
    required this.maxWindSpeed,
    required this.maxWindGusts,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(_cellSize),
        columnWidths: const {
          0: FixedColumnWidth(_siteColumnWidth), // Site name column wider
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
    );
  }

  TableRow _buildHeaderRow(BuildContext context) {
    return TableRow(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      children: [
        _buildHeaderCell(context, 'Site', isFirst: true),
        ...List.generate(_hoursToShow, (hour) =>
          _buildHeaderCell(context, '${hour + _startHour}h')),
      ],
    );
  }

  Widget _buildHeaderCell(BuildContext context, String text, {bool isFirst = false}) {
    return Container(
      height: _cellSize,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isFirst ? FontWeight.bold : FontWeight.w500,
          fontSize: isFirst ? 12 : 10,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  TableRow _buildSiteRow(BuildContext context, ParaglidingSite site) {
    // Get site key for wind data lookup
    final siteKey = '${site.latitude.toStringAsFixed(4)}_${site.longitude.toStringAsFixed(4)}';
    final siteWindData = windDataBySite[siteKey] ?? [];

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
        // Hour cells
        ...List.generate(_hoursToShow, (hourIndex) {
          if (hourIndex >= siteWindData.length || siteWindData[hourIndex] == null) {
            return _buildEmptyCell();
          }

          return _buildForecastCell(
            context: context,
            site: site,
            windData: siteWindData[hourIndex]!,
          );
        }),
      ],
    );
  }

  Widget _buildEmptyCell() {
    return Container(
      height: _cellSize,
      alignment: Alignment.center,
      child: const Text('-', style: TextStyle(fontSize: 10, color: Colors.grey)),
    );
  }

  Widget _buildForecastCell({
    required BuildContext context,
    required ParaglidingSite site,
    required WindData windData,
  }) {
    // Calculate flyability using centralized helper
    final flyabilityLevel = FlyabilityHelper.getFlyabilityLevel(
      windData: windData,
      siteDirections: site.windDirections,
      maxSpeed: maxWindSpeed,
      maxGusts: maxWindGusts,
    );

    // Get color with full opacity
    final bgColor = FlyabilityHelper.getColorForLevel(flyabilityLevel);

    // Generate tooltip with detailed flyability explanation
    final tooltipMessage = FlyabilityHelper.getTooltipForLevel(
      level: flyabilityLevel,
      windData: windData,
      siteDirections: site.windDirections,
      maxSpeed: maxWindSpeed,
      maxGusts: maxWindGusts,
    );

    return Tooltip(
      message: tooltipMessage,
      child: Container(
        height: _cellSize,
        color: bgColor,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Wind arrow and speed with white color for contrast
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Using Transform.rotate for wind direction arrow
                Transform.rotate(
                  angle: windData.directionDegrees * (pi / 180), // Convert degrees to radians
                  child: const Icon(
                    Icons.arrow_upward,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${windData.speedKmh.round()}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
