import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/wind_forecast.dart';
import '../../services/weather_service.dart';
import '../../utils/flyability_helper.dart';
import '../../utils/flyability_constants.dart';
import 'flyability_cell.dart';
import 'multi_site_flyability_table.dart';
import 'site_forecast_table.dart';

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
  final double cautionWindSpeed;

  const WeekSummaryTable({
    super.key,
    required this.sites,
    required this.windDataByDay,
    required this.maxWindSpeed,
    required this.cautionWindSpeed,
  });

  @override
  State<WeekSummaryTable> createState() => _WeekSummaryTableState();
}

class _WeekSummaryTableState extends State<WeekSummaryTable> {
  // Track what detail is currently shown
  int? _selectedDayIndex;
  ParaglidingSite? _selectedSite;
  WindForecast? _selectedSiteForecast; // Forecast for the selected site
  bool _showingCellDetail = false;

  void _onDateHeaderTap(int dayIndex) {
    setState(() {
      if (_selectedDayIndex == dayIndex && !_showingCellDetail) {
        // Clicking same date again - clear selection
        _selectedDayIndex = null;
        _selectedSite = null;
        _selectedSiteForecast = null;
      } else {
        // Show all sites for this day
        _selectedDayIndex = dayIndex;
        _selectedSite = null;
        _selectedSiteForecast = null;
        _showingCellDetail = false;
      }
    });
  }

  void _onSiteNameTap(ParaglidingSite site) {
    setState(() {
      if (_selectedSite == site && !_showingCellDetail) {
        // Clicking same site again - clear selection
        _selectedSite = null;
        _selectedSiteForecast = null;
        _selectedDayIndex = null;
      } else {
        // Show all days for this site
        _selectedSite = site;
        _selectedDayIndex = null;
        _showingCellDetail = false;
      }
    });

    // Fetch forecast for selected site
    if (_selectedSite != null) {
      _loadSiteForecast();
    }
  }

  /// Load forecast for the currently selected site
  Future<void> _loadSiteForecast() async {
    if (_selectedSite == null) return;

    final forecast = await WeatherService.instance.getCachedForecast(
      _selectedSite!.latitude,
      _selectedSite!.longitude,
    );

    if (mounted) {
      setState(() {
        _selectedSiteForecast = forecast;
      });
    }
  }

  void _onCellTap(ParaglidingSite site, int dayIndex) {
    setState(() {
      if (_selectedSite == site && _selectedDayIndex == dayIndex && _showingCellDetail) {
        // Clicking same cell again - clear selection
        _selectedSite = null;
        _selectedSiteForecast = null;
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
            defaultColumnWidth: const FixedColumnWidth(48.0), // Week summary uses larger cells
            columnWidths: const {
              0: FixedColumnWidth(FlyabilityConstants.siteColumnWidth),
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
      // All days for selected site - build a simple date × hours table
      return _buildSiteDetailTable(context);
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
                    _selectedSiteForecast = null;
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
            date: date,
            maxWindSpeed: widget.maxWindSpeed,
            cautionWindSpeed: widget.cautionWindSpeed,
          ),
        ),
      ],
    );
  }

  Widget _buildSiteDetailTable(BuildContext context) {
    final siteKey = generateSiteKey(_selectedSite!);

    // Extract wind data for this site from the map
    final Map<int, List<WindData?>> siteWindData = {};
    for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
      final dayData = widget.windDataByDay[dayIndex];
      if (dayData != null && dayData.containsKey(siteKey)) {
        siteWindData[dayIndex] = dayData[siteKey]!;
      }
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
                  _selectedSite!.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _selectedSite = null;
                    _selectedSiteForecast = null;
                    _selectedDayIndex = null;
                    _showingCellDetail = false;
                  });
                },
                tooltip: 'Close detail view',
              ),
            ],
          ),
        ),
        RefreshIndicator(
          onRefresh: _loadSiteForecast,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(), // Ensure pull-to-refresh works
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16.0),
            child: IntrinsicWidth(
              child: SiteForecastTable(
                site: _selectedSite!,
                windDataByDay: siteWindData,
                maxWindSpeed: widget.maxWindSpeed,
                cautionWindSpeed: widget.cautionWindSpeed,
              ),
            ),
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
          height: FlyabilityConstants.headerHeight,
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
              height: FlyabilityConstants.headerHeight,
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
    final siteKey = generateSiteKey(site);
    final isSiteSelected = _selectedSite == site && !_showingCellDetail;

    return TableRow(
      children: [
        // Site name cell - clickable
        InkWell(
          onTap: () => _onSiteNameTap(site),
          child: Container(
            height: 48.0, // Week summary uses larger cells
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
      height: 48.0, // Week summary uses larger cells
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
          height: 48.0, // Week summary uses larger cells
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

      // Note: daylight times not available here as we don't have forecast objects
      // Only WindData is passed to this widget. This is acceptable as the week summary
      // shows aggregate flyability and doesn't need precise daylight filtering.
      return FlyabilityHelper.getFlyabilityLevel(
        windData: windData,
        siteDirections: site.windDirections,
        maxSpeed: widget.maxWindSpeed,
        cautionSpeed: widget.cautionWindSpeed,
      );
    }).toList();

    // Check for 2+ consecutive green hours
    if (FlyabilityHelper.hasConsecutiveLevels(
      levels: levels,
      targetLevel: FlyabilityLevel.safe,
    )) {
      return FlyabilityLevel.safe;
    }

    // Check for any red (unsafe) hours
    if (levels.contains(FlyabilityLevel.unsafe)) {
      return FlyabilityLevel.unsafe;
    }

    // Check for 2+ consecutive yellow hours
    if (FlyabilityHelper.hasConsecutiveLevels(
      levels: levels,
      targetLevel: FlyabilityLevel.caution,
    )) {
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
