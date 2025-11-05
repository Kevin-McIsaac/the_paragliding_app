import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/weather_model.dart';
import '../../services/weather_service.dart';
import '../../services/logging_service.dart';
import '../../utils/preferences_helper.dart';
import '../../utils/flyability_helper.dart';
import '../../utils/flyability_constants.dart';
import 'multi_site_flyability_table.dart';
import 'site_forecast_table.dart';
import 'multi_model_forecast_table.dart';
import 'fixed_column_table.dart';

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
  bool _showingCellDetail = false;

  // Multi-model comparison data
  Map<WeatherModel, List<WindData?>>? _multiModelData;
  bool _loadingMultiModel = false;
  bool _showingAllModels = false;
  WeatherModel? _selectedModel;

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

    // Fetch forecast for selected site
    if (_selectedSite != null) {
      _loadSiteForecast();
    }
  }

  /// Load forecast for the currently selected site
  Future<void> _loadSiteForecast() async {
    if (_selectedSite == null) return;

    // Pre-fetch and cache forecast for the selected site
    await WeatherService.instance.getCachedForecast(
      _selectedSite!.latitude,
      _selectedSite!.longitude,
    );
  }

  void _onCellTap(ParaglidingSite site, int dayIndex) {
    if (_selectedSite == site && _selectedDayIndex == dayIndex && _showingCellDetail) {
      // Clicking same cell again - clear selection
      setState(() {
        _selectedSite = null;
        _selectedDayIndex = null;
        _showingCellDetail = false;
        _multiModelData = null;
        _showingAllModels = false;
      });
    } else {
      // Show hourly details for this specific site and day
      setState(() {
        _selectedSite = site;
        _selectedDayIndex = dayIndex;
        _showingCellDetail = true;
        _multiModelData = null; // Clear previous data
        _showingAllModels = false; // Reset to single model view
      });

      // Load only the currently selected model (instant, uses cache)
      _loadCurrentModelForecast();
    }
  }

  /// Load forecast for only the currently selected model (instant, from cache)
  Future<void> _loadCurrentModelForecast() async {
    if (_selectedSite == null || _selectedDayIndex == null) return;

    // Capture current selection to validate later (prevent race conditions)
    final requestSite = _selectedSite;
    final requestDayIndex = _selectedDayIndex;

    try {
      // Load selected model from preferences
      final modelApiValue = await PreferencesHelper.getWeatherForecastModel();
      _selectedModel = WeatherModel.fromApiValue(modelApiValue);

      final date = DateTime.now().add(Duration(days: requestDayIndex!));

      // Get cached forecast for current model only
      final forecast = await WeatherService.instance.getCachedForecast(
        requestSite!.latitude,
        requestSite.longitude,
      );

      if (forecast != null) {
        // Extract hourly data for 7am-7pm for the selected day
        final hourlyData = <WindData?>[];
        for (int hour = FlyabilityConstants.startHour;
             hour <= FlyabilityConstants.startHour + FlyabilityConstants.hoursToShow - 1;
             hour++) {
          final dateTime = DateTime(date.year, date.month, date.day, hour);
          final windData = forecast.getAtTime(dateTime);
          hourlyData.add(windData);
        }

        // Only show model if it has at least one valid data point
        final hasValidData = hourlyData.any((windData) => windData != null);

        // Validate selection hasn't changed before updating state
        if (mounted && _selectedSite == requestSite && _selectedDayIndex == requestDayIndex) {
          setState(() {
            _multiModelData = hasValidData ? {_selectedModel!: hourlyData} : null;
          });

          LoggingService.structured('CURRENT_MODEL_FORECAST_LOADED', {
            'site': requestSite.name,
            'day_index': requestDayIndex,
            'model': _selectedModel!.displayName,
            'from_cache': true,
            'has_valid_data': hasValidData,
          });
        } else {
          LoggingService.debug('Discarding stale forecast data for ${requestSite.name} day $requestDayIndex');
        }
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to load current model forecast', e, stackTrace);
    }
  }

  /// Load remaining weather models (triggered by "More forecasts..." button)
  Future<void> _loadRemainingModels() async {
    if (_selectedSite == null || _selectedDayIndex == null) return;

    // Capture current selection to validate later (prevent race conditions)
    final requestSite = _selectedSite;
    final requestDayIndex = _selectedDayIndex;

    setState(() {
      _loadingMultiModel = true;
    });

    try {
      final date = DateTime.now().add(Duration(days: requestDayIndex!));
      final modelDataMap = <WeatherModel, List<WindData?>>{};

      // Preserve current model data
      if (_multiModelData != null) {
        modelDataMap.addAll(_multiModelData!);
      }

      // Fetch forecasts for ALL models (includes cache check, so current model won't be re-fetched)
      final stopwatch = Stopwatch()..start();
      final forecasts = await WeatherService.instance.getAllModelForecasts(
        requestSite!.latitude,
        requestSite.longitude,
      );
      stopwatch.stop();

      // Extract hourly data for 7am-7pm for the selected day from each model's forecast
      for (final entry in forecasts.entries) {
        final model = entry.key;
        final forecast = entry.value;

        final hourlyData = <WindData?>[];
        for (int hour = FlyabilityConstants.startHour;
             hour <= FlyabilityConstants.startHour + FlyabilityConstants.hoursToShow - 1;
             hour++) {
          final dateTime = DateTime(date.year, date.month, date.day, hour);
          final windData = forecast.getAtTime(dateTime);
          hourlyData.add(windData);
        }

        modelDataMap[model] = hourlyData;
      }

      // Filter out models with no valid data (all null entries)
      final modelsBeforeFilter = modelDataMap.length;
      modelDataMap.removeWhere((model, hourlyData) =>
        hourlyData.every((windData) => windData == null)
      );
      final modelsAfterFilter = modelDataMap.length;

      // Validate selection hasn't changed before updating state
      if (mounted && _selectedSite == requestSite && _selectedDayIndex == requestDayIndex) {
        setState(() {
          _multiModelData = modelDataMap;
          _loadingMultiModel = false;
          _showingAllModels = true;
        });

        LoggingService.structured('ALL_MODELS_FORECAST_LOADED', {
          'site': requestSite.name,
          'day_index': requestDayIndex,
          'models_loaded': modelDataMap.length,
          'models_filtered': modelsBeforeFilter - modelsAfterFilter,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
      } else {
        // Selection changed, just reset loading state
        if (mounted) {
          setState(() {
            _loadingMultiModel = false;
          });
        }
        LoggingService.debug('Discarding stale model forecasts for ${requestSite.name} day $requestDayIndex');
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to load remaining model forecasts', e, stackTrace);
      if (mounted) {
        setState(() {
          _loadingMultiModel = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tableBorder = TableBorder.all(
      color: Theme.of(context).dividerColor,
      width: 1.0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table with fixed first column
        FixedColumnTable(
          firstColumnWidth: FlyabilityConstants.siteColumnWidth,
          fullTable: Table(
            defaultColumnWidth: const FixedColumnWidth(48.0), // Week summary uses larger cells
            columnWidths: const {
              0: FixedColumnWidth(FlyabilityConstants.siteColumnWidth),
            },
            border: tableBorder,
            children: [
              _buildHeaderRow(context),
              ...widget.sites.map((site) => _buildSiteRow(context, site)),
            ],
          ),
          firstColumnTable: Table(
            columnWidths: const {
              0: FixedColumnWidth(FlyabilityConstants.siteColumnWidth),
            },
            border: tableBorder,
            children: [
              _buildHeaderRowFirstColumnOnly(context),
              ...widget.sites.map((site) => _buildSiteRowFirstColumnOnly(context, site)),
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
                'Flyable',
                '2+ consecutive green hours',
              ),
              _buildLegendItem(
                FlyabilityHelper.getColorForLevel(FlyabilityLevel.caution),
                'Caution',
                '2+ consecutive orange or green+orange pair',
              ),
              _buildLegendItem(
                FlyabilityHelper.getColorForLevel(FlyabilityLevel.unsafe),
                'Not Flyable',
                'unsafe conditions',
              ),
              _buildLegendItem(
                FlyabilityHelper.getColorForLevel(FlyabilityLevel.unknown),
                'Unknown',
                'scattered/insufficient data',
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
      // Single site, single day - show multi-model comparison
      return _buildMultiModelDetailSection(context);
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

  Widget _buildMultiModelDetailSection(BuildContext context) {
    final date = DateTime.now().add(Duration(days: _selectedDayIndex!));
    final title = '${_selectedSite!.name} - ${DateFormat('EEEE, MMMM d').format(date)}';

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _showingAllModels
                          ? 'Comparing all weather models'
                          : 'Using ${_selectedModel?.displayName ?? "current"} model',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _selectedDayIndex = null;
                    _selectedSite = null;
                    _showingCellDetail = false;
                    _multiModelData = null;
                  });
                },
                tooltip: 'Close detail view',
              ),
            ],
          ),
        ),
        if (_multiModelData != null && _multiModelData!.isNotEmpty)
          Column(
            children: [
              // Always show table when data exists
              // FixedColumnTable handles horizontal scrolling internally
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: MultiModelForecastTable(
                  site: _selectedSite!,
                  date: date,
                  windDataByModel: _multiModelData!,
                  maxWindSpeed: widget.maxWindSpeed,
                  cautionWindSpeed: widget.cautionWindSpeed,
                  selectedModel: _selectedModel,
                ),
              ),
              // Show loading indicator BELOW table when loading additional models
              if (_loadingMultiModel)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Loading additional forecasts...',
                        style: TextStyle(fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                )
              // Show "More forecasts..." button when not loading and only showing current model
              else if (!_showingAllModels && _multiModelData!.length == 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: OutlinedButton.icon(
                    onPressed: _loadRemainingModels,
                    icon: const Icon(Icons.add_chart, size: 20),
                    label: const Text('More forecasts...'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ),
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text('Failed to load forecast'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _loadCurrentModelForecast,
                    child: const Text('Retry'),
                  ),
                ],
              ),
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

  /// Build header row with only the first column (for fixed column overlay)
  TableRow _buildHeaderRowFirstColumnOnly(BuildContext context) {
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
      ],
    );
  }

  /// Build site row with only the first column (for fixed column overlay)
  TableRow _buildSiteRowFirstColumnOnly(BuildContext context, ParaglidingSite site) {
    final isSiteSelected = _selectedSite == site && !_showingCellDetail;

    return TableRow(
      children: [
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

    // Check for 2+ consecutive yellow hours OR green+orange pair
    // This checks for flyable windows BEFORE penalizing for scattered red hours
    if (FlyabilityHelper.hasConsecutiveLevels(
      levels: levels,
      targetLevel: FlyabilityLevel.caution,
    ) || _hasGreenOrangePair(levels)) {
      return FlyabilityLevel.caution;
    }

    // Check for any red (unsafe) hours
    if (levels.contains(FlyabilityLevel.unsafe)) {
      return FlyabilityLevel.unsafe;
    }

    // Default to unknown if no clear pattern (scattered/insufficient data)
    return FlyabilityLevel.unknown;
  }

  /// Check if there's a consecutive pair of green and orange hours (in any order)
  bool _hasGreenOrangePair(List<FlyabilityLevel?> levels) {
    for (int i = 0; i < levels.length - 1; i++) {
      final current = levels[i];
      final next = levels[i + 1];

      if (current == null || next == null) continue;

      // Check for green+orange or orange+green pair
      if ((current == FlyabilityLevel.safe && next == FlyabilityLevel.caution) ||
          (current == FlyabilityLevel.caution && next == FlyabilityLevel.safe)) {
        return true;
      }
    }
    return false;
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

  Widget _buildLegendItem(Color color, String label, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Row(
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
            label,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
