import 'package:flutter/material.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../utils/flyability_constants.dart';
import 'flyability_cell.dart';

/// Table widget displaying flyability for multiple sites across hours
/// Sites are shown as rows, hours (7am-7pm) as columns
class MultiSiteFlyabilityTable extends StatelessWidget {
  final List<ParaglidingSite> sites;
  final Map<String, List<WindData?>> windDataBySite; // Site key -> 13 hours of wind data
  final DateTime date;
  final double maxWindSpeed;
  final double maxWindGusts;

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
        defaultColumnWidth: const FixedColumnWidth(FlyabilityConstants.cellSize),
        columnWidths: const {
          0: FixedColumnWidth(FlyabilityConstants.siteColumnWidth), // Site name column wider
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
        ...List.generate(FlyabilityConstants.hoursToShow, (hour) =>
          _buildHeaderCell(context, '${hour + FlyabilityConstants.startHour}h')),
      ],
    );
  }

  Widget _buildHeaderCell(BuildContext context, String text, {bool isFirst = false}) {
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
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  TableRow _buildSiteRow(BuildContext context, ParaglidingSite site) {
    // Get site key for wind data lookup
    final siteKey = generateSiteKey(site);
    final siteWindData = windDataBySite[siteKey] ?? [];

    return TableRow(
      children: [
        // Site name cell
        Container(
          height: FlyabilityConstants.cellSize,
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
        ...List.generate(FlyabilityConstants.hoursToShow, (hourIndex) {
          if (hourIndex >= siteWindData.length || siteWindData[hourIndex] == null) {
            return _buildEmptyCell();
          }

          return FlyabilityCellWidget(
            windData: siteWindData[hourIndex]!,
            site: site,
            maxWindSpeed: maxWindSpeed,
            maxWindGusts: maxWindGusts,
          );
        }),
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
}
