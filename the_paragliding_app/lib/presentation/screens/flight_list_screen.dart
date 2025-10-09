import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../services/database_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/ui_utils.dart';
import '../../utils/flight_sorting_utils.dart';
import '../../services/logging_service.dart';
import '../widgets/common/app_stat_card.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/app_empty_state.dart';
import '../widgets/common/app_loading_skeleton.dart';
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

class FlightListScreen extends StatefulWidget {
  /// Whether this screen is shown within MainNavigationScreen's bottom navigation.
  /// When true, removes Statistics and Nearby Sites from menu and hides FAB.
  final bool showInNavigation;

  const FlightListScreen({super.key, this.showInNavigation = false});

  @override
  State<FlightListScreen> createState() => _FlightListScreenState();
}

class _FlightListScreenState extends State<FlightListScreen> {
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
  
  // Selection mode state
  bool _isSelectionMode = false;
  Set<int> _selectedFlightIds = {};
  bool _isDeleting = false;

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

  // Date range helper methods
  DateTimeRange? _getDateRangeForPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (preset) {
      case 'all':
        return null;
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
      default:
        return null;
    }
  }

  String _formatDateRangeCompact(DateTimeRange? range) {
    if (range == null) return 'All time';

    // Compact format for button: "dd/mm-dd/mm" or "dd/mm/yy-dd/mm/yy"
    final start = range.start;
    final end = range.end;
    final now = DateTime.now();

    // If both dates are in current year, omit year
    if (start.year == now.year && end.year == now.year) {
      return '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}';
    }

    // Include year for clarity
    final startYear = start.year.toString().substring(2);
    final endYear = end.year.toString().substring(2);
    return '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/$startYear-${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}/$endYear';
  }

  Future<void> _selectDateRange() async {
    // Show popup menu with presets + custom option
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final String? selected = await showMenu<String>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(value: 'all', child: Text('All time')),
        const PopupMenuItem(value: '12_months', child: Text('Last 12 months')),
        const PopupMenuItem(value: '6_months', child: Text('Last 6 months')),
        const PopupMenuItem(value: '3_months', child: Text('Last 3 months')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'custom', child: Text('Custom range...')),
      ],
    );

    if (selected == null) return;

    if (selected == 'custom') {
      // Show date picker
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
      // Preset selected
      final newRange = _getDateRangeForPreset(selected);
      LoggingService.action('FlightList', 'select_date_preset', {
        'preset': selected,
      });

      setState(() {
        _selectedPreset = selected;
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

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedFlightIds.clear();
      }
    });
  }

  void _toggleFlightSelection(int flightId) {
    setState(() {
      if (_selectedFlightIds.contains(flightId)) {
        _selectedFlightIds.remove(flightId);
      } else {
        _selectedFlightIds.add(flightId);
      }
    });
  }

  void _selectAllFlights() {
    setState(() {
      _selectedFlightIds = _flights.map((flight) => flight.id!).toSet();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedFlightIds.clear();
    });
  }

  Future<void> _deleteSelectedFlights() async {
    if (_selectedFlightIds.isEmpty || _isDeleting) return;

    // Set deleting state immediately to prevent double-tap
    setState(() {
      _isDeleting = true;
    });

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Flights'),
        content: Text(
          'Are you sure you want to delete ${_selectedFlightIds.length} flight${_selectedFlightIds.length != 1 ? 's' : ''}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      // User cancelled, reset deleting state
      setState(() {
        _isDeleting = false;
      });
      return;
    }

    try {
      final flightCount = _selectedFlightIds.length;
      bool allDeleted = true;
      
      // Delete each flight
      for (final flightId in _selectedFlightIds) {
        try {
          await _databaseService.deleteFlight(flightId);
        } catch (e) {
          LoggingService.error('FlightListScreen: Failed to delete flight $flightId', e);
          allDeleted = false;
        }
      }
      
      if (mounted) {
        setState(() {
          _isDeleting = false;
          if (allDeleted) {
            _isSelectionMode = false;
            _selectedFlightIds.clear();
          }
        });
        
        if (allDeleted) {
          UiUtils.showSuccessMessage(context, '$flightCount flight${flightCount != 1 ? 's' : ''} deleted successfully');
          // Reload flights
          await _loadData();
        } else {
          UiUtils.showErrorMessage(context, 'Some flights could not be deleted');
        }
      }
    } catch (e) {
      // Handle any unexpected errors and reset state
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unexpected error during deletion: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearError() {
    setState(() {
      _errorMessage = null;
    });
  }

  /// Build date filter button for functional bar
  Widget _buildDateFilterButton() {
    final dateText = _selectedPreset == 'all'
        ? 'All time'
        : _selectedPreset == 'custom'
            ? _formatDateRangeCompact(_selectedDateRange)
            : _selectedPreset == '12_months'
                ? '12mo'
                : _selectedPreset == '6_months'
                    ? '6mo'
                    : '3mo';

    return InkWell(
      onTap: _selectDateRange,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minWidth: 90),
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
            const SizedBox(width: 6),
            Text(
              dateText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down,
              color: Colors.white70,
              size: 18,
            ),
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
            // Date filter button
            _buildDateFilterButton(),
            const SizedBox(width: 8),
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
            // Menu button
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70),
              onSelected: (value) async {
                if (value == 'import') {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (context) => const IgcImportScreen(),
                    ),
                  );

                  if (result == true) {
                    _loadData();
                  }
                } else if (value == 'select') {
                  _toggleSelectionMode();
                } else if (value == 'wings') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const WingManagementScreen(),
                    ),
                  );
                } else if (value == 'sites') {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (context) => const ManageSitesScreen(),
                    ),
                  );
                  if (result == true && mounted) {
                    await _loadData();
                  }
                } else if (value == 'database') {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (context) => const DataManagementScreen(),
                    ),
                  );

                  if (result == true) {
                    _loadData();
                  }
                } else if (value == 'about') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AboutScreen(),
                    ),
                  );
                } else if (value == 'preferences') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const PreferencesScreen(),
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'sites',
                  child: Row(
                    children: [
                      Icon(Icons.location_on),
                      SizedBox(width: 8),
                      Text('Manage Sites'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'wings',
                  child: Row(
                    children: [
                      Icon(Icons.paragliding),
                      SizedBox(width: 8),
                      Text('Manage Wings'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'import',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file),
                      SizedBox(width: 8),
                      Text('Import IGC'),
                    ],
                  ),
                ),
                if (_flights.isNotEmpty)
                  const PopupMenuItem(
                    value: 'select',
                    child: Row(
                      children: [
                        Icon(Icons.checklist),
                        SizedBox(width: 8),
                        Text('Select Flights'),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'database',
                  child: Row(
                    children: [
                      Icon(Icons.storage),
                      SizedBox(width: 8),
                      Text('Data Management'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'preferences',
                  child: Row(
                    children: [
                      Icon(Icons.settings),
                      SizedBox(width: 8),
                      Text('Preferences'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'about',
                  child: Row(
                    children: [
                      Icon(Icons.info),
                      SizedBox(width: 8),
                      Text('About'),
                    ],
                  ),
                ),
              ],
            ),
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
    // When in navigation mode, use dark functional bar instead of AppBar
    if (widget.showInNavigation) {
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

    // When not in navigation mode, use traditional AppBar
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
          ? Text('${_selectedFlightIds.length} selected')
          : const Text('The Paragliding App'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: _isSelectionMode 
          ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleSelectionMode,
            )
          : null,
        actions: _isSelectionMode 
          ? [
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Select All',
                onPressed: _selectAllFlights,
                ),
              if (_selectedFlightIds.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear Selection',
                  onPressed: _clearSelection,
                ),
              if (_selectedFlightIds.isNotEmpty)
                IconButton(
                  icon: _isDeleting 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete),
                  tooltip: 'Delete Selected',
                  onPressed: _isDeleting ? null : _deleteSelectedFlights,
                ),
            ]
          : [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'import') {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => const IgcImportScreen(),
                      ),
                    );
                    
                    if (result == true) {
                      _loadData();
                    }
                  } else if (value == 'select') {
                    _toggleSelectionMode();
                  } else if (value == 'wings') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const WingManagementScreen(),
                      ),
                    );
                  } else if (value == 'sites') {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => const ManageSitesScreen(),
                      ),
                    );
                    // Reload flights if sites were modified
                    if (result == true && mounted) {
                      await _loadData();
                    }
                  } else if (value == 'statistics') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const StatisticsScreen(),
                      ),
                    );
                  } else if (value == 'nearby_sites') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const NearbySitesScreen(),
                      ),
                    );
                  } else if (value == 'database') {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => const DataManagementScreen(),
                      ),
                    );
                    
                    if (result == true) {
                      _loadData(); // Reload flights if database was modified
                    }
                  } else if (value == 'about') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const AboutScreen(),
                      ),
                    );
                  } else if (value == 'preferences') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const PreferencesScreen(),
                      ),
                    );
                  }
                },
                itemBuilder: (context) => [
                  // Show Statistics and Nearby Sites only when NOT in navigation mode
                  if (!widget.showInNavigation) ...[
                    const PopupMenuItem(
                      value: 'statistics',
                      child: Row(
                        children: [
                          Icon(Icons.bar_chart),
                          SizedBox(width: 8),
                          Text('Statistics'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'nearby_sites',
                      child: Row(
                        children: [
                          Icon(Icons.map),
                          SizedBox(width: 8),
                          Text('Nearby Sites'),
                        ],
                      ),
                    ),
                  ],
                  const PopupMenuItem(
                    value: 'sites',
                    child: Row(
                      children: [
                        Icon(Icons.location_on),
                        SizedBox(width: 8),
                        Text('Manage Sites'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'wings',
                    child: Row(
                      children: [
                        Icon(Icons.paragliding),
                        SizedBox(width: 8),
                        Text('Manage Wings'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'import',
                    child: Row(
                      children: [
                        Icon(Icons.upload_file),
                        SizedBox(width: 8),
                        Text('Import IGC'),
                      ],
                    ),
                  ),
                  if (_flights.isNotEmpty)
                    const PopupMenuItem(
                      value: 'select',
                      child: Row(
                        children: [
                          Icon(Icons.checklist),
                          SizedBox(width: 8),
                          Text('Select Flights'),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'database',
                    child: Row(
                      children: [
                        Icon(Icons.storage),
                        SizedBox(width: 8),
                        Text('Data Management'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'preferences',
                    child: Row(
                      children: [
                        Icon(Icons.settings),
                        SizedBox(width: 8),
                        Text('Preferences'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'about',
                    child: Row(
                      children: [
                        Icon(Icons.info),
                        SizedBox(width: 8),
                        Text('About'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
      ),
      body: _buildMainContent(),
      // Only show FAB when NOT in navigation mode (MainNavigationScreen handles it)
      floatingActionButton: widget.showInNavigation
          ? null
          : FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (context) => const AddFlightScreen(),
                  ),
                );

                if (result == true) {
                  _loadData();
                }
              },
              tooltip: 'Add Flight',
              child: const Icon(Icons.add),
            ),
    );
  }


  Widget _buildFlightList(List<Flight> flights) {
    // Calculate stats based on selection mode
    int totalFlights;
    int totalTime;
    
    if (_isSelectionMode && _selectedFlightIds.isNotEmpty) {
      // In selection mode, count only selected flights
      final selectedFlights = flights.where((flight) => _selectedFlightIds.contains(flight.id)).toList();
      totalFlights = selectedFlights.length;
      totalTime = selectedFlights.fold(0, (sum, flight) => sum + flight.effectiveDuration);
    } else {
      // Normal mode: use totals from the database
      totalFlights = _totalFlights;
      totalTime = _totalDuration;
    }
    
    return Column(
      children: [
        AppStatCardGroup.flightList(
          cards: [
            AppStatCard.flightList(
              label: _isSelectionMode && _selectedFlightIds.isNotEmpty 
                  ? 'Selected Flights' 
                  : 'Total Flights',
              value: totalFlights.toString(),
            ),
            AppStatCard.flightList(
              label: _isSelectionMode && _selectedFlightIds.isNotEmpty 
                  ? 'Selected Time' 
                  : 'Total Time',
              value: DateTimeUtils.formatDuration(totalTime),
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
          showCheckboxColumn: _isSelectionMode,
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
            final isSelected = _selectedFlightIds.contains(flight.id);
            return DataRow(
              selected: isSelected,
              onSelectChanged: _isSelectionMode 
                  ? (selected) => _toggleFlightSelection(flight.id!)
                  : null,
              onLongPress: () {
                if (!_isSelectionMode) {
                  _toggleSelectionMode();
                  _toggleFlightSelection(flight.id!);
                }
              },
              cells: [
                DataCell(
                  Text(
                    flight.launchSiteName ?? 'Unknown Site',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: _isSelectionMode 
                      ? null 
                      : () async {
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
                  onTap: _isSelectionMode 
                      ? null 
                      : () async {
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
                  onTap: _isSelectionMode 
                      ? null 
                      : () async {
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
                  onTap: _isSelectionMode 
                      ? null 
                      : () async {
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
                  onTap: _isSelectionMode 
                      ? null 
                      : () async {
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
                  onTap: _isSelectionMode 
                      ? null 
                      : () async {
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