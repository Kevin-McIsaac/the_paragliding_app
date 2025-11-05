import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../utils/flyability_constants.dart';
import 'flyability_cell.dart';
import 'fixed_column_table.dart';

/// Shared widget for displaying a single site's 7-day flyability forecast
///
/// Displays a Date × Hours table with:
/// - 7 rows (days)
/// - 13 columns (hours from 7am to 7pm)
/// - Color-coded flyability cells using FlyabilityCellWidget
///
/// Used by:
/// - Site details dialog - when viewing a site's full forecast
/// - Week summary table - when clicking a site name to see details
///
/// Note: Attribution bar should be added by parent widget using ForecastAttributionBar
class SiteForecastTable extends StatelessWidget {
  final ParaglidingSite site;
  final Map<int, List<WindData?>> windDataByDay; // dayIndex (0-6) -> hourly data (7am-7pm)
  final double maxWindSpeed;
  final double cautionWindSpeed;
  final double? dateColumnWidth;

  const SiteForecastTable({
    super.key,
    required this.site,
    required this.windDataByDay,
    required this.maxWindSpeed,
    required this.cautionWindSpeed,
    this.dateColumnWidth = 80.0,
  });

  @override
  Widget build(BuildContext context) {
    final tableBorder = TableBorder.all(
      color: Theme.of(context).dividerColor,
      width: 1.0,
    );

    return FixedColumnTable(
      firstColumnWidth: dateColumnWidth!,
      fullTable: Table(
        defaultColumnWidth: const FixedColumnWidth(FlyabilityConstants.cellSize),
        columnWidths: {
          0: FixedColumnWidth(dateColumnWidth!),
        },
        border: tableBorder,
        children: [
          _buildHeaderRow(context),
          ...List.generate(7, (dayIndex) => _buildDataRow(context, dayIndex)),
        ],
      ),
      firstColumnTable: Table(
        columnWidths: {
          0: FixedColumnWidth(dateColumnWidth!),
        },
        border: tableBorder,
        children: [
          _buildHeaderRowFirstColumnOnly(context),
          ...List.generate(7, (dayIndex) => _buildDataRowFirstColumnOnly(context, dayIndex)),
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
        _buildHeaderCell('Date', isFirst: true),
        ...List.generate(
          FlyabilityConstants.hoursToShow,
          (hour) => _buildHeaderCell('${hour + FlyabilityConstants.startHour}h'),
        ),
      ],
    );
  }

  Widget _buildHeaderCell(String text, {bool isFirst = false}) {
    return Container(
      height: FlyabilityConstants.cellSize,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isFirst ? FontWeight.bold : FontWeight.w500,
          fontSize: isFirst ? 12 : 10,
        ),
      ),
    );
  }

  TableRow _buildDataRow(BuildContext context, int dayIndex) {
    final date = DateTime.now().add(Duration(days: dayIndex));
    final siteWindData = windDataByDay[dayIndex];

    return TableRow(
      children: [
        // Date cell
        Container(
          height: FlyabilityConstants.cellSize,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            _formatDate(date),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
        // Hour cells (7am-7pm)
        ...List.generate(FlyabilityConstants.hoursToShow, (hourIndex) {
          if (siteWindData == null || hourIndex >= siteWindData.length || siteWindData[hourIndex] == null) {
            return _buildEmptyCell();
          }

          final windData = siteWindData[hourIndex]!;
          return FlyabilityCellWidget(
            windData: windData,
            site: site,
            maxWindSpeed: maxWindSpeed,
            cautionWindSpeed: cautionWindSpeed,
          );
        }),
      ],
    );
  }

  /// Build header row with only the first column (for fixed column overlay)
  TableRow _buildHeaderRowFirstColumnOnly(BuildContext context) {
    return TableRow(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      children: [
        _buildHeaderCell('Date', isFirst: true),
      ],
    );
  }

  /// Build data row with only the first column (for fixed column overlay)
  TableRow _buildDataRowFirstColumnOnly(BuildContext context, int dayIndex) {
    final date = DateTime.now().add(Duration(days: dayIndex));

    return TableRow(
      children: [
        Container(
          height: FlyabilityConstants.cellSize,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            _formatDate(date),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCell() {
    return Container(
      height: FlyabilityConstants.cellSize,
      alignment: Alignment.center,
      child: const Text('-', style: TextStyle(fontSize: 10, color: Colors.grey)),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) return 'Today';
    if (checkDate == today.add(const Duration(days: 1))) return 'Tomorrow';

    // Format as "Mon 23" or "Tue 24"
    return DateFormat('EEE d').format(date);
  }
}
