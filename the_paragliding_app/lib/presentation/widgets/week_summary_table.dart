import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../utils/flyability_helper.dart';
import 'multi_site_flyability_table.dart';

/// Week summary table showing flyability for multiple sites across 7 days
/// Sites are rows, days are columns with color-coded daily summary
///
/// Interactive features:
/// - Click date header: Shows flyability for all sites on that day
/// - Click site name: Shows flyability for that site across all days
/// - Click cell: Shows hourly flyability for that specific site and day
class WeekSummaryTable extends StatefulWidget {
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
  State<WeekSummaryTable> createState() => _WeekSummaryTableState();
}

class _WeekSummaryTableState extends State<WeekSummaryTable> {
  // Track what detail is currently shown
  int? _selectedDayIndex;
  ParaglidingSite? _selectedSite;
  bool _showingCellDetail = false;

  void _onDateHeaderTap(int dayIndex) {
    setState(() {
      if (_selectedDayIndex == dayIndex && !_showingCellDetail) {
        // Clicking same date again - clear selection
        _selectedDayIndex = null;
        _selectedSite = null;
      } else {
        // Show all sites for this day
        _selectedDayIndex = dayIndex;
        _selectedSite = null;
        _showingCellDetail = false;
      }
    });
  }

  void _onSiteNameTap(ParaglidingSite site) {
    setState(() {
      if (_selectedSite == site && !_showingCellDetail) {
        // Clicking same site again - clear selection
        _selectedSite = null;
        _selectedDayIndex = null;
      } else {
        // Show all days for this site
        _selectedSite = site;
        _selectedDayIndex = null;
        _showingCellDetail = false;
      }
    });
  }

  void _onCellTap(ParaglidingSite site, int dayIndex) {
    setState(() {
      if (_selectedSite == site && _selectedDayIndex == dayIndex && _showingCellDetail) {
        // Clicking same cell again - clear selection
        _selectedSite = null;
        _selectedDayIndex = null;
        _showingCellDetail = false;
      } else {
        // Show hourly details for this specific site and day
        _selectedSite = site;
        _selectedDayIndex = dayIndex;
        _showingCellDetail = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: FixedColumnWidth(WeekSummaryTable._cellSize),
            columnWidths: const {
              0: FixedColumnWidth(WeekSummaryTable._siteColumnWidth),
            },
            border: TableBorder.all(
              color: Theme.of(context).dividerColor,
              width: 1.0,
            ),
            children: [
              _buildHeaderRow(context),
              ...widget.sites.map((site) => _buildSiteRow(context, site)),
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
            'Tap date, site, or cell to see hourly details',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),

        // Detail table (shown below summary)
        if (_selectedDayIndex != null || _selectedSite != null)
          _buildDetailSection(context),
      ],
    );
  }

  Widget _buildDetailSection(BuildContext context) {
    final date = _selectedDayIndex != null
        ? DateTime.now().add(Duration(days: _selectedDayIndex!))
        : null;

    String title;
    Map<String, List<WindData?>> windDataBySite;
    List<ParaglidingSite> sitesToShow;

    if (_showingCellDetail && _selectedSite != null && _selectedDayIndex != null) {
      // Single site, single day - show hourly breakdown
      title = '${_selectedSite!.name} - ${DateFormat('EEEE, MMMM d').format(date!)}';
      windDataBySite = {
        '${_selectedSite!.latitude.toStringAsFixed(4)}_${_selectedSite!.longitude.toStringAsFixed(4)}':
            widget.windDataByDay[_selectedDayIndex]?[
                    '${_selectedSite!.latitude.toStringAsFixed(4)}_${_selectedSite!.longitude.toStringAsFixed(4)}'] ??
                []
      };
      sitesToShow = [_selectedSite!];
    } else if (_selectedDayIndex != null) {
      // All sites for selected day
      title = DateFormat('EEEE, MMMM d').format(date!);
      windDataBySite = widget.windDataByDay[_selectedDayIndex] ?? {};
      sitesToShow = widget.sites;
    } else if (_selectedSite != null) {
      // All days for selected site - need to build map with multiple days
      title = _selectedSite!.name;
      final siteKey =
          '${_selectedSite!.latitude.toStringAsFixed(4)}_${_selectedSite!.longitude.toStringAsFixed(4)}';

      // For site view, we show each day as a separate "site" row
      // This is a workaround - we'll need to create synthetic data
      windDataBySite = {};
      sitesToShow = [];

      // Build a table where each row is a different day for this site
      for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
        final dayData = widget.windDataByDay[dayIndex];
        if (dayData != null && dayData.containsKey(siteKey)) {
          // Create a synthetic "site" for this day
          final dayDate = DateTime.now().add(Duration(days: dayIndex));
          final daySite = ParaglidingSite(
            id: null, // Synthetic site for display only
            name: DateFormat('EEE d').format(dayDate),
            latitude: _selectedSite!.latitude,
            longitude: _selectedSite!.longitude,
            windDirections: _selectedSite!.windDirections,
            siteType: _selectedSite!.siteType,
            country: _selectedSite!.country,
            region: _selectedSite!.region,
          );
          sitesToShow.add(daySite);
          final daySiteKey =
              '${daySite.latitude.toStringAsFixed(4)}_${daySite.longitude.toStringAsFixed(4)}';
          windDataBySite[daySiteKey] = dayData[siteKey]!;
        }
      }

      if (sitesToShow.isEmpty) {
        return const SizedBox.shrink();
      }
    } else {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32, thickness: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _selectedDayIndex = null;
                    _selectedSite = null;
                    _showingCellDetail = false;
                  });
                },
                tooltip: 'Close detail view',
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16.0),
          child: MultiSiteFlyabilityTable(
            sites: sitesToShow,
            windDataBySite: windDataBySite,
            date: date ?? DateTime.now(),
            maxWindSpeed: widget.maxWindSpeed,
            maxWindGusts: widget.maxWindGusts,
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
          height: WeekSummaryTable._headerHeight,
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

          final isSelected = _selectedDayIndex == dayIndex && !_showingCellDetail;

          return InkWell(
            onTap: () => _onDateHeaderTap(dayIndex),
            child: Container(
              height: WeekSummaryTable._headerHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              decoration: isSelected
                  ? BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    )
                  : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayName,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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
    final isSiteSelected = _selectedSite == site && !_showingCellDetail;

    return TableRow(
      children: [
        // Site name cell - clickable
        InkWell(
          onTap: () => _onSiteNameTap(site),
          child: Container(
            height: WeekSummaryTable._cellSize,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            decoration: isSiteSelected
                ? BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  )
                : null,
            child: Tooltip(
              message: site.name,
              child: Text(
                site.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSiteSelected ? FontWeight.bold : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        ),
        // Day cells
        ...List.generate(7, (dayIndex) {
          final dayData = widget.windDataByDay[dayIndex];
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
      height: WeekSummaryTable._cellSize,
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

    final isCellSelected = _selectedSite == site && _selectedDayIndex == dayIndex && _showingCellDetail;

    return InkWell(
      onTap: () => _onCellTap(site, dayIndex),
      child: Tooltip(
        message: tooltipMessage,
        child: Container(
          height: WeekSummaryTable._cellSize,
          alignment: Alignment.center,
          decoration: isCellSelected
              ? BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                )
              : null,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: isCellSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
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
        maxSpeed: widget.maxWindSpeed,
        maxGusts: widget.maxWindGusts,
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
