import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../services/database_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/flight_sorting_utils.dart';
import '../../services/logging_service.dart';
import '../widgets/common/app_stat_card.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/app_empty_state.dart';
import '../widgets/common/app_loading_skeleton.dart';
import '../widgets/common/app_menu_button.dart';
import 'igc_import_screen.dart';
import 'flight_detail_screen.dart';

/// Flight list screen displaying all logged flights in a sortable, filterable table.
///
/// This screen is designed to be used within MainNavigationScreen's bottom navigation.
/// It provides search, date range filtering, and access to the app menu.
class FlightListScreen extends StatefulWidget {
  final VoidCallback? onDataChanged;
  final Future<void> Function()? onRefreshAllTabs;

  const FlightListScreen({
    super.key,
    this.onDataChanged,
    this.onRefreshAllTabs,
  });

  @override
  State<FlightListScreen> createState() => FlightListScreenState();
}

/// State class for FlightListScreen.
///
/// Made public (not prefixed with _) to allow parent widgets to access
/// the refreshData() method through GlobalKey in a type-safe manner.
///
/// Example:
/// ```dart
/// final key = GlobalKey<FlightListScreenState>();
/// // ...
/// await key.currentState?.refreshData();
/// ```
class FlightListScreenState extends State<FlightListScreen> {
  final DatabaseService _databaseService = DatabaseService.instance;
  
  // State variables
  List<Flight> _flights = [];
  List<Flight> _sortedFlights = [];
  int _totalFlights = 0;
  int _totalDuration = 0;
  bool _isLoading = false;
  String? _errorMessage;
  
  // Sorting state
  String _sortColumn = 'datetime';
  bool _sortAscending = false;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Date range filtering
  DateTimeRange? _selectedDateRange;
  String _selectedPreset = 'all';

  @override
  void initState() {
    super.initState();
    // Load flights immediately without delay
    // The splash screen already handled initialization
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await _loadData();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Public method to refresh flight data.
  ///
  /// This method can be called by parent widgets using a GlobalKey:
  /// ```dart
  /// final key = GlobalKey<State<FlightListScreen>>();
  /// // ...
  /// (key.currentState as _FlightListScreenState?)?.refreshData();
  /// ```
  ///
  /// However, prefer using callbacks (e.g., onDataChanged) when possible
  /// to avoid tight coupling between parent and child widgets.
  Future<void> refreshData() async {
    await _loadData();
  }

  // Load flights from database
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final totalStartTime = DateTime.now();

      // Load flights from database
      final flightsStartTime = DateTime.now();
      final flights = await _databaseService.getAllFlights();
      final flightsDuration = DateTime.now().difference(flightsStartTime);

      // Get totals from database
      final statsStartTime = DateTime.now();
      final stats = await _databaseService.getOverallStatistics();
      final statsDuration = DateTime.now().difference(statsStartTime);

      final totalDuration = DateTime.now().difference(totalStartTime);

      // Log breakdown of timings
      LoggingService.structured('FLIGHT_LIST_LOAD_BREAKDOWN', {
        'flights_query_ms': flightsDuration.inMilliseconds,
        'stats_query_ms': statsDuration.inMilliseconds,
        'total_ms': totalDuration.inMilliseconds,
        'flight_count': flights.length,
      });

      LoggingService.performance('Load flights', totalDuration, '${flights.length} flights loaded');

      if (mounted) {
        setState(() {
          _flights = flights;
          _totalFlights = stats['totalFlights'] as int? ?? 0;
          _totalDuration = stats['totalDuration'] as int? ?? 0;
          _sortFlights();
          _isLoading = false;
        });
        LoggingService.info('FlightListScreen: Loaded ${flights.length} flights');
      }
    } catch (e) {
      LoggingService.error('FlightListScreen: Failed to load flights', e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load flights: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Sort and filter flights based on current column, direction, date range, and search query
  void _sortFlights() {
    // Start with all flights
    _sortedFlights = List.from(_flights);

    // First apply date range filter if one is selected
    if (_selectedDateRange != null) {
      _sortedFlights = _sortedFlights.where((flight) {
        return flight.date.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
               flight.date.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    // Then apply search filter if there's a query
    if (_searchQuery.isNotEmpty) {
      _sortedFlights = _sortedFlights.where((flight) {
        final siteName = flight.launchSiteName?.toLowerCase() ?? '';
        return siteName.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Finally apply sorting
    FlightSortingUtils.sortFlights(_sortedFlights, _sortColumn, _sortAscending);
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _sortFlights();
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
        return DateTimeRange(
          start: today.subtract(const Duration(days: 365)),
          end: today,
        );
      case '6_months':
        return DateTimeRange(
          start: today.subtract(const Duration(days: 183)),
          end: today,
        );
      case '3_months':
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

    final startFormatted = DateTimeUtils.formatDateSmart(range.start);
    final endFormatted = DateTimeUtils.formatDateSmart(range.end);

    return '$startFormatted - $endFormatted';
  }

  Future<void> _selectPreset(String preset) async {
    LoggingService.action('FlightList', 'select_date_preset', {
      'new_preset': preset,
      'previous_preset': _selectedPreset,
    });

    if (preset == 'custom') {
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        initialDateRange: _selectedDateRange,
        helpText: 'Select date range for flights',
      );

      if (picked != null) {
        LoggingService.structured('FLIGHT_LIST_CUSTOM_RANGE', {
          'start_date': picked.start.toIso8601String().split('T')[0],
          'end_date': picked.end.toIso8601String().split('T')[0],
          'duration_days': picked.end.difference(picked.start).inDays,
        });

        setState(() {
          _selectedPreset = 'custom';
          _selectedDateRange = picked;
          _sortFlights();
        });
      }
    } else {
      final newRange = _getDateRangeForPreset(preset);
      setState(() {
        _selectedPreset = preset;
        _selectedDateRange = newRange;
        _sortFlights();
      });
    }
  }

  void _sort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _sortFlights();
    });
  }

  void _clearError() {
    setState(() {
      _errorMessage = null;
    });
  }

  /// Build main content (used by both navigation and non-navigation modes)
  Widget _buildMainContent() {
    if (_isLoading && _flights.isEmpty) {
      return AppPageLoadingSkeleton.flightList();
    }

    if (_errorMessage != null) {
      return Center(
        child: AppErrorState.loading(
          message: _errorMessage!,
          onRetry: () {
            _clearError();
            _loadData();
          },
        ),
      );
    }

    if (_flights.isEmpty) {
      return AppEmptyState.flights(
        onAddFlight: () async {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => const IgcImportScreen(),
            ),
          );

          if (result == true) {
            // Refresh all tabs when importing succeeds
            if (widget.onRefreshAllTabs != null) {
              await widget.onRefreshAllTabs!();
            } else {
              _loadData();
            }
          }
        },
      );
    }

    return _buildFlightList(_sortedFlights);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search site name...',
              hintStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.7)),
              prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: Colors.white),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      padding: EdgeInsets.zero,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        actions: [
          // Date filter dropdown button
          PopupMenuButton<String>(
            onSelected: _selectPreset,
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, size: 16),
                const SizedBox(width: 4),
                Text(
                  _selectedPreset == 'custom' && _selectedDateRange != null
                      ? _formatDateRange(_selectedDateRange)
                      : _getPresetLabel(_selectedPreset),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('All time'),
              ),
              const PopupMenuItem(
                value: '12_months',
                child: Text('Last 12 months'),
              ),
              const PopupMenuItem(
                value: '6_months',
                child: Text('Last 6 months'),
              ),
              const PopupMenuItem(
                value: '3_months',
                child: Text('Last 3 months'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'custom',
                child: Text('Custom range...'),
              ),
            ],
          ),
          AppMenuButton(
            onDataChanged: _loadData,
            onRefreshAllTabs: widget.onRefreshAllTabs,
          ),
        ],
      ),
      body: _buildMainContent(),
    );
  }


  Widget _buildFlightList(List<Flight> flights) {
    return Column(
      children: [
        AppStatCardGroup.flightList(
          cards: [
            AppStatCard.flightList(
              label: 'Total Flights',
              value: _totalFlights.toString(),
            ),
            AppStatCard.flightList(
              label: 'Total Time',
              value: DateTimeUtils.formatDuration(_totalDuration),
            ),
          ],
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
        Expanded(
          child: _buildFlightTable(flights),
        ),
      ],
    );
  }
  
  Widget _buildFlightTable(List<Flight> flights) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          children: [
            DataTable(
          sortColumnIndex: _sortColumn == 'launch_site' ? 0
              : _sortColumn == 'datetime' ? 1
              : _sortColumn == 'duration' ? 2
              : _sortColumn == 'track_distance' ? 3
              : _sortColumn == 'distance' ? 4
              : _sortColumn == 'altitude' ? 5
              : 0,
          sortAscending: _sortAscending,
          columns: [
            DataColumn(
              label: const Text('Launch Site'),
              onSort: (columnIndex, ascending) => _sort('launch_site'),
            ),
            DataColumn(
              label: const Text('Launch Date & Time'),
              onSort: (columnIndex, ascending) => _sort('datetime'),
            ),
            DataColumn(
              label: const Text('Duration'),
              onSort: (columnIndex, ascending) => _sort('duration'),
            ),
            DataColumn(
              label: const Text('Track Dist (km)'),
              numeric: true,
              onSort: (columnIndex, ascending) => _sort('track_distance'),
            ),
            DataColumn(
              label: const Text('Straight Dist (km)'),
              numeric: true,
              onSort: (columnIndex, ascending) => _sort('distance'),
            ),
            DataColumn(
              label: const Text('Max Alt (m)'),
              numeric: true,
              onSort: (columnIndex, ascending) => _sort('altitude'),
            ),
          ],
          rows: flights.map((flight) {
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    flight.launchSiteName ?? 'Unknown Site',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => FlightDetailScreen(flight: flight),
                      ),
                    );
                    if (result == true) {
                      _loadData(); // Reload if flight was deleted or modified
                    }
                  },
                ),
                DataCell(
                  Text(
                    '${flight.date.day.toString().padLeft(2, '0')}/'
                    '${flight.date.month.toString().padLeft(2, '0')}/'
                    '${flight.date.year} ${flight.effectiveLaunchTime}',
                  ),
                  onTap: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => FlightDetailScreen(flight: flight),
                      ),
                    );
                    if (result == true) {
                      _loadData(); // Reload if flight was deleted or modified
                    }
                  },
                ),
                DataCell(
                  Text(DateTimeUtils.formatDuration(flight.effectiveDuration)),
                  onTap: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => FlightDetailScreen(flight: flight),
                      ),
                    );
                    if (result == true) {
                      _loadData(); // Reload if flight was deleted or modified
                    }
                  },
                ),
                DataCell(
                  Text(
                    flight.distance != null 
                        ? flight.distance!.toStringAsFixed(1)
                        : '-',
                  ),
                  onTap: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => FlightDetailScreen(flight: flight),
                      ),
                    );
                    if (result == true) {
                      _loadData(); // Reload if flight was deleted or modified
                    }
                  },
                ),
                DataCell(
                  Text(
                    flight.straightDistance != null 
                        ? flight.straightDistance!.toStringAsFixed(1)
                        : '-',
                  ),
                  onTap: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => FlightDetailScreen(flight: flight),
                      ),
                    );
                    if (result == true) {
                      _loadData(); // Reload if flight was deleted or modified
                    }
                  },
                ),
                DataCell(
                  Text(
                    flight.maxAltitude != null 
                        ? flight.maxAltitude!.toInt().toString()
                        : '-',
                  ),
                  onTap: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => FlightDetailScreen(flight: flight),
                      ),
                    );
                    if (result == true) {
                      _loadData(); // Reload if flight was deleted or modified
                    }
                  },
                ),
              ],
            );
          }).toList(),
        ),
        ],
        ),
      ),
    );
  }

}