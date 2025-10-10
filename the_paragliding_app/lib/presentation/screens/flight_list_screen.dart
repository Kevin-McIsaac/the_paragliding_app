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
import 'add_flight_screen.dart';
import 'igc_import_screen.dart';
import 'flight_detail_screen.dart';
import 'wing_management_screen.dart';
import 'manage_sites_screen.dart';
import 'statistics_screen.dart';
import 'nearby_sites_screen.dart';
import 'data_management_screen.dart';
import 'about_screen.dart';
import 'preferences_screen.dart';

/// Flight list screen displaying all logged flights in a sortable, filterable table.
///
/// This screen is designed to be used within MainNavigationScreen's bottom navigation.
/// It provides search, date range filtering, and access to the app menu.
class FlightListScreen extends StatefulWidget {
  const FlightListScreen({super.key});

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
      final startTime = DateTime.now();
      
      // Load flights with all joined data
      final flights = await _databaseService.getAllFlights();
      
      // Get totals from database
      final stats = await _databaseService.getOverallStatistics();
      
      final duration = DateTime.now().difference(startTime);
      LoggingService.performance('Load flights', duration, '${flights.length} flights loaded');
      
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

  String _formatDateRangeCompact(DateTimeRange? range) {
    if (range == null) return 'All dates';

    // Format: "dd-MMM to dd-MMM" (e.g., "02-Oct to 10-Oct")
    final start = range.start;
    final end = range.end;

    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final startMonth = monthNames[start.month - 1];
    final endMonth = monthNames[end.month - 1];
    final startDay = start.day.toString().padLeft(2, '0');
    final endDay = end.day.toString().padLeft(2, '0');

    return '$startDay-$startMonth to $endDay-$endMonth';
  }

  Future<void> _selectDateRange() async {
    // Directly show date picker (no preset menu)
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
        _selectedDateRange = picked;
        _sortFlights();
      });
    }
  }

  void _clearDateRange() {
    setState(() {
      _selectedDateRange = null;
      _sortFlights();
    });
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

  /// Build date filter button for functional bar
  Widget _buildDateFilterButton() {
    final dateText = _formatDateRangeCompact(_selectedDateRange);
    final hasDateFilter = _selectedDateRange != null;

    return InkWell(
      onTap: _selectDateRange,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today,
              color: Colors.white70,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              dateText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (hasDateFilter) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: _clearDateRange,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.clear,
                    color: Colors.white70,
                    size: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build dark functional bar (like Sites/Statistics)
  Widget _buildFunctionalBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Search field
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search site name...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white70, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Date filter button
            _buildDateFilterButton(),
            const SizedBox(width: 8),
            // Menu button
            AppMenuButton(onDataChanged: _loadData),
          ],
        ),
      ),
    );
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
            _loadData();
          }
        },
      );
    }

    return _buildFlightList(_sortedFlights);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildFunctionalBar(),
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
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