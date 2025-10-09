import 'package:flutter/material.dart';
import '../../utils/date_time_utils.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/app_empty_state.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final DatabaseService _databaseService = DatabaseService.instance;
  
  // Constants
  static const double _cardElevation = 2.0;
  static const EdgeInsets _cardPadding = EdgeInsets.all(16.0);
  static const EdgeInsets _scrollPadding = EdgeInsets.only(top: 16.0, bottom: 16.0);
  static const EdgeInsets _rowPadding = EdgeInsets.symmetric(vertical: 12);
  static const double _headerBorderWidth = 2.0;
  static const double _sectionSpacing = 24.0;
  
  // State variables
  List<Map<String, dynamic>> _yearlyStats = [];
  List<Map<String, dynamic>> _wingStats = [];
  List<Map<String, dynamic>> _siteStats = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  // Date range filtering
  DateTimeRange? _selectedDateRange;
  String _selectedPreset = 'all';
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final stopwatch = Stopwatch()..start();
      final opId = LoggingService.startOperation('STATS_LOAD');
      
      // Get date range for filtering
      DateTime? startDate = _selectedDateRange?.start;
      DateTime? endDate = _selectedDateRange?.end;
      
      // Log structured data about the statistics query
      LoggingService.structured('STATS_QUERY', {
        'operation_id': opId,
        'date_range_preset': _selectedPreset,
        'start_date': startDate?.toIso8601String().split('T')[0],
        'end_date': endDate?.toIso8601String().split('T')[0],
        'filter_type': _selectedPreset == 'custom' ? 'custom' : 'preset',
        'has_date_filter': startDate != null || endDate != null,
      });
      
      // Load all statistics in parallel
      final results = await Future.wait([
        _databaseService.getYearlyStatistics(startDate: startDate, endDate: endDate),
        _databaseService.getWingStatistics(startDate: startDate, endDate: endDate),
        _databaseService.getSiteStatistics(startDate: startDate, endDate: endDate),
      ]);
      
      stopwatch.stop();
      
      // Calculate total flights for performance context
      int totalFlights = 0;
      double totalHours = 0.0;
      for (final stat in results[0]) {
        totalFlights += stat['flight_count'] as int;
        totalHours += (stat['total_hours'] as num?)?.toDouble() ?? 0.0;
      }
      
      // Log performance with threshold monitoring
      LoggingService.performance(
        'Statistics Load',
        Duration(milliseconds: stopwatch.elapsedMilliseconds),
        'statistics loaded',
      );
      
      if (mounted) {
        setState(() {
          _yearlyStats = results[0];
          _wingStats = results[1];
          _siteStats = results[2];
          _isLoading = false;
        });
        
        // End operation with summary
        LoggingService.endOperation('STATS_LOAD', results: {
          'total_years': _yearlyStats.length,
          'total_wings': _wingStats.length,
          'total_sites': _siteStats.length,
          'total_flights': totalFlights,
          'total_hours': totalHours.toStringAsFixed(1),
          'duration_ms': stopwatch.elapsedMilliseconds,
          'filter_applied': startDate != null || endDate != null,
        });
      }
    } catch (e, stackTrace) {
      // Enhanced error logging with structured data
      LoggingService.structured('STATS_ERROR', {
        'error_type': e.runtimeType.toString(),
        'message': e.toString(),
        'date_range_preset': _selectedPreset,
        'filter_type': _selectedPreset == 'custom' ? 'custom' : 'preset',
        'recovery_action': 'user_retry_available',
        'stack_trace_length': stackTrace.toString().split('\n').length,
      });
      
      LoggingService.error('StatisticsScreen: Failed to load statistics', e, stackTrace);
      
      if (mounted) {
        setState(() {
          // Provide more specific error messages for different failure types
          if (e.toString().contains('date') || e.toString().contains('range')) {
            _errorMessage = 'Failed to filter statistics by date range. Please try a different date range.';
          } else if (e.toString().contains('database') || e.toString().contains('sql')) {
            _errorMessage = 'Database error while loading statistics. Please try again.';
          } else {
            _errorMessage = 'Failed to load statistics: $e';
          }
          _isLoading = false;
        });
      }
    }
  }

  void _clearError() {
    setState(() {
      _errorMessage = null;
    });
  }

  DateTimeRange? _getDateRangeForPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    switch (preset) {
      case 'all':
        return null;
      case 'this_year':
        return DateTimeRange(
          start: DateTime(now.year, 1, 1),
          end: today,
        );
      case '12_months':
        // Use Duration-based calculation for 12 months (approx 365 days)
        return DateTimeRange(
          start: today.subtract(const Duration(days: 365)),
          end: today,
        );
      case '6_months':
        // Use Duration-based calculation for 6 months (approx 183 days)  
        return DateTimeRange(
          start: today.subtract(const Duration(days: 183)),
          end: today,
        );
      case '3_months':
        // Use Duration-based calculation for 3 months (approx 91 days)
        return DateTimeRange(
          start: today.subtract(const Duration(days: 91)),
          end: today,
        );
      case '30_days':
        return DateTimeRange(
          start: today.subtract(const Duration(days: 30)),
          end: today,
        );
      default:
        return null;
    }
  }

  String _getPresetLabel(String preset) {
    switch (preset) {
      case 'all':
        return 'All time';
      case 'this_year':
        return 'This year';
      case '12_months':
        return 'Last 12 months';
      case '6_months':
        return 'Last 6 months';
      case '3_months':
        return 'Last 3 months';
      case '30_days':
        return 'Last 30 days';
      case 'custom':
        return 'Custom range';
      default:
        return preset;
    }
  }

  String _formatDateRange(DateTimeRange? range) {
    if (range == null) return 'All time';
    
    // Use smart formatting that includes year when dates span years or are not current year
    final startFormatted = DateTimeUtils.formatDateSmart(range.start);
    final endFormatted = DateTimeUtils.formatDateSmart(range.end);
    
    return '$startFormatted - $endFormatted';
  }

  String _buildFlightCountText() {
    // Calculate total flights from yearly stats (most reliable)
    int totalFlights = 0;
    double totalHours = 0.0;
    
    for (final stat in _yearlyStats) {
      totalFlights += stat['flight_count'] as int;
      totalHours += (stat['total_hours'] as num?)?.toDouble() ?? 0.0;
    }
    
    if (totalFlights == 0) {
      return 'No flights found in this period';
    } else if (totalFlights == 1) {
      return 'Showing 1 flight (${DateTimeUtils.formatHours(totalHours)})';
    } else {
      return 'Showing $totalFlights flights (${DateTimeUtils.formatHours(totalHours)})';
    }
  }

  Future<void> _selectPreset(String preset) async {
    // Log user action with context
    LoggingService.action('Statistics', 'select_date_preset', {
      'new_preset': preset,
      'previous_preset': _selectedPreset,
      'current_range': _formatDateRange(_selectedDateRange),
      'interaction_type': preset == 'custom' ? 'date_picker' : 'preset_chip',
    });
    
    if (preset == 'custom') {
      // Always show date picker when custom is tapped
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        initialDateRange: _selectedDateRange,
        helpText: 'Select date range for statistics',
      );
      if (picked != null) {
        // Validate that end date is not before start date
        if (picked.end.isBefore(picked.start)) {
          LoggingService.warning('Statistics: Invalid date range selected - end before start');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('End date cannot be before start date'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        LoggingService.structured('STATS_CUSTOM_RANGE', {
          'start_date': picked.start.toIso8601String().split('T')[0],
          'end_date': picked.end.toIso8601String().split('T')[0],
          'duration_days': picked.end.difference(picked.start).inDays,
        });
        
        setState(() {
          _selectedPreset = 'custom';
          _selectedDateRange = picked;
        });
        _loadData();
      } else {
        LoggingService.debug('Statistics: Date picker cancelled by user');
      }
    } else {
      final newRange = _getDateRangeForPreset(preset);
      LoggingService.structured('STATS_PRESET_SELECTED', {
        'preset': preset,
        'range_start': newRange?.start.toIso8601String().split('T')[0],
        'range_end': newRange?.end.toIso8601String().split('T')[0],
        'duration_days': newRange?.end.difference(newRange.start).inDays,
      });
      
      setState(() {
        _selectedPreset = preset;
        _selectedDateRange = newRange;
      });
      _loadData();
    }
  }

  Widget _buildDateRangeSelector() {
    final presets = ['all', '12_months', 'this_year', '6_months', '3_months', '30_days', 'custom'];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preset chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: presets.map((preset) {
              final isSelected = _selectedPreset == preset;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_getPresetLabel(preset)),
                  selected: isSelected,
                  onSelected: (_) => _selectPreset(preset),
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  // Add semantic labels for accessibility
                  tooltip: isSelected 
                    ? 'Currently showing ${_getPresetLabel(preset)} statistics'
                    : 'Show ${_getPresetLabel(preset)} statistics',
                ),
              );
            }).toList(),
          ),
        ),
        
        // Selected range display and flight count
        if (_selectedDateRange != null || !_isLoading) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedDateRange != null)
                  Text(
                    'Showing: ${_formatDateRange(_selectedDateRange)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (!_isLoading && _errorMessage == null)
                  Text(
                    _buildFlightCountText(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
        ],
        
        const SizedBox(height: 16),
      ],
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Statistics'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      // Add semantic label for the main content area
      body: Semantics(
        label: 'Flight statistics with date range filtering',
        child: _buildMainContent(),
      ),
    );
  }

  Widget _buildMainContent() {
    return _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Column(
                  children: [
                    // Always show date range selector
                    _buildDateRangeSelector(),
                    Expanded(
                      child: AppErrorState.loading(
                        message: _errorMessage!,
                        onRetry: () {
                          _clearError();
                          _loadData();
                        },
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    // Always show date range selector
                    _buildDateRangeSelector(),
                    Expanded(
                      child: _yearlyStats.isEmpty && 
                              _wingStats.isEmpty && 
                              _siteStats.isEmpty
                          ? AppEmptyState.statistics()
                          : SingleChildScrollView(
                              padding: _scrollPadding,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Yearly Statistics Section
                                  if (_yearlyStats.isNotEmpty) ...[
                                    _buildSectionHeader('Flights by Year', Icons.calendar_today),
                                    const SizedBox(height: 8),
                                    _buildYearlyStatsTable(_yearlyStats),
                                    const SizedBox(height: _sectionSpacing),
                                  ],
                                  
                                  // Wing Statistics Section
                                  if (_wingStats.isNotEmpty) ...[
                                    _buildSectionHeader('Flights by Wing', Icons.paragliding),
                                    const SizedBox(height: 8),
                                    _buildWingStatsTable(_wingStats),
                                    const SizedBox(height: _sectionSpacing),
                                  ],
                                  
                                  // Site Statistics Section
                                  if (_siteStats.isNotEmpty) ...[
                                    _buildSectionHeader('Flights by Site', Icons.location_on),
                                    const SizedBox(height: 8),
                                    _buildSiteStatsTable(_siteStats),
                                  ],
                                ],
                              ),
                            ),
                    ),
                  ],
                );
  }
  
  
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // Text style helpers
  TextStyle? get _headerTextStyle => Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      );

  TextStyle? get _bodyTextStyle => Theme.of(context).textTheme.bodyLarge;

  TextStyle? get _bodyBoldTextStyle => Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
      );

  TextStyle? get _primaryTextStyle => Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w500,
      );

  TextStyle? get _totalHeaderTextStyle => Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      );

  TextStyle? get _totalPrimaryTextStyle => Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      );

  // Common table building helpers
  Widget _buildTableHeader(List<String> headers, List<int> flexValues) {
    return Container(
      padding: _rowPadding,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: _headerBorderWidth,
          ),
        ),
      ),
      child: Row(
        children: headers.asMap().entries.map((entry) {
          final index = entry.key;
          final header = entry.value;
          return Expanded(
            flex: flexValues[index],
            child: Text(
              header,
              style: _headerTextStyle,
              textAlign: index == 0 ? TextAlign.start : 
                       index == headers.length - 1 ? TextAlign.right : 
                       TextAlign.center,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDataRow(List<Widget> cells, List<int> flexValues, {bool isLast = false}) {
    return Container(
      padding: _rowPadding,
      decoration: BoxDecoration(
        border: isLast ? null : Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: cells.asMap().entries.map((entry) {
          final index = entry.key;
          final cell = entry.value;
          return Expanded(
            flex: flexValues[index],
            child: cell,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTotalRow(String totalLabel, int totalFlights, double totalHours, List<int> flexValues) {
    return Container(
      padding: _rowPadding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: _headerBorderWidth,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: flexValues[0],
            child: Text(totalLabel, style: _totalHeaderTextStyle),
          ),
          Expanded(
            flex: flexValues[1],
            child: Text(
              totalFlights.toString(),
              style: _totalHeaderTextStyle,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: flexValues[2],
            child: Text(
              DateTimeUtils.formatHours(totalHours),
              style: _totalPrimaryTextStyle,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildYearlyStatsTable(List<Map<String, dynamic>> yearlyStats) {
    // Calculate totals
    double totalHours = 0;
    int totalFlights = 0;
    for (final stat in yearlyStats) {
      totalHours += (stat['total_hours'] as num?)?.toDouble() ?? 0.0;
      totalFlights += stat['flight_count'] as int;
    }
    
    const flexValues = [2, 2, 3];
    
    return Card(
      elevation: _cardElevation,
      child: Padding(
        padding: _cardPadding,
        child: Column(
          children: [
            _buildTableHeader(['Year', 'Flights', 'Total Hours'], flexValues),
            
            // Data Rows
            ...yearlyStats.asMap().entries.map((entry) {
              final index = entry.key;
              final stat = entry.value;
              return _buildDataRow([
                Text(stat['year'].toString(), style: _bodyBoldTextStyle),
                Text(stat['flight_count'].toString(), style: _bodyTextStyle, textAlign: TextAlign.center),
                Text(
                  DateTimeUtils.formatHours((stat['total_hours'] as num?)?.toDouble() ?? 0.0),
                  style: _primaryTextStyle,
                  textAlign: TextAlign.right,
                ),
              ], flexValues, isLast: index == yearlyStats.length - 1);
            }),
            
            _buildTotalRow('TOTAL', totalFlights, totalHours, flexValues),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWingStatsTable(List<Map<String, dynamic>> wingStats) {
    // Calculate totals
    double totalHours = 0;
    int totalFlights = 0;
    for (final stat in wingStats) {
      totalHours += (stat['total_hours'] as num?)?.toDouble() ?? 0.0;
      totalFlights += stat['flight_count'] as int;
    }
    
    const flexValues = [4, 2, 3];
    
    return Card(
      elevation: _cardElevation,
      child: Padding(
        padding: _cardPadding,
        child: Column(
          children: [
            _buildTableHeader(['Wing', 'Flights', 'Total Hours'], flexValues),
            
            // Data Rows
            ...wingStats.asMap().entries.map((entry) {
              final index = entry.key;
              final stat = entry.value;
              return _buildDataRow([
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (stat['name'] as String?) ?? 'Unknown Wing',
                      style: _bodyBoldTextStyle,
                    ),
                    if (stat['size'] != null && (stat['size'] as String).isNotEmpty)
                      Text(
                        'Size: ${stat['size']}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                Text(stat['flight_count'].toString(), style: _bodyTextStyle, textAlign: TextAlign.center),
                Text(
                  DateTimeUtils.formatHours((stat['total_hours'] as num?)?.toDouble() ?? 0.0),
                  style: _primaryTextStyle,
                  textAlign: TextAlign.right,
                ),
              ], flexValues, isLast: index == wingStats.length - 1 && wingStats.length == 1);
            }),
            
            // Total Row (if more than one wing)
            if (wingStats.length > 1)
              _buildTotalRow('TOTAL', totalFlights, totalHours, flexValues),
          ],
        ),
      ),
    );
  }

  Widget _buildSiteStatsTable(List<Map<String, dynamic>> siteStats) {
    // Group sites by country
    Map<String, List<Map<String, dynamic>>> groupedSites = {};
    double totalHours = 0;
    int totalFlights = 0;
    
    for (final stat in siteStats) {
      final country = (stat['country'] as String?) ?? 'Unknown Country';
      if (!groupedSites.containsKey(country)) {
        groupedSites[country] = [];
      }
      groupedSites[country]!.add(stat);
      
      // Calculate totals
      totalHours += (stat['total_hours'] as num?)?.toDouble() ?? 0.0;
      totalFlights += stat['flight_count'] as int;
    }
    
    // Sort countries (Unknown Country at the end)
    final sortedCountries = groupedSites.keys.toList();
    sortedCountries.sort((a, b) {
      if (a == 'Unknown Country' && b != 'Unknown Country') return 1;
      if (b == 'Unknown Country' && a != 'Unknown Country') return -1;
      return a.compareTo(b);
    });
    
    const flexValues = [4, 2, 3];
    final hasMultipleCountries = groupedSites.keys.length > 1;
    
    return Card(
      elevation: _cardElevation,
      child: Padding(
        padding: _cardPadding,
        child: Column(
          children: [
            _buildTableHeader(['Site', 'Flights', 'Total Hours'], flexValues),
            
            // Country Groups
            ...sortedCountries.expand((country) {
              final sites = groupedSites[country]!;
              return [
                // Country Header (only show if more than one country)
                if (hasMultipleCountries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.flag,
                          size: 16,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          country,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${sites.length} ${sites.length == 1 ? 'site' : 'sites'}',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Sites in this country
                ...sites.map((stat) => Container(
                  padding: _rowPadding,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Padding(
                          padding: EdgeInsets.only(left: hasMultipleCountries ? 24.0 : 0.0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  (stat['name'] as String?) ?? 'Unknown Site',
                                  style: _bodyBoldTextStyle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          stat['flight_count'].toString(),
                          style: _bodyTextStyle,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          DateTimeUtils.formatHours((stat['total_hours'] as num?)?.toDouble() ?? 0.0),
                          style: _primaryTextStyle,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                )),
              ];
            }),
            
            // Total Row (if more than one site)
            if (siteStats.length > 1)
              _buildTotalRow('TOTAL', totalFlights, totalHours, flexValues),
          ],
        ),
      ),
    );
  }
}