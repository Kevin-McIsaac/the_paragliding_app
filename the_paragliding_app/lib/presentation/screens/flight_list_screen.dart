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

  // Sort flights based on current column and direction
  void _sortFlights() {
    _sortedFlights = List.from(_flights);
    FlightSortingUtils.sortFlights(_sortedFlights, _sortColumn, _sortAscending);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
          ? Text('${_selectedFlightIds.length} selected')
          : Text(widget.showInNavigation ? 'Flight Log' : 'The Paragliding App'),
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
      body: _isLoading && _flights.isEmpty
          ? AppPageLoadingSkeleton.flightList()
          : _errorMessage != null
              ? Center(
                  child: AppErrorState.loading(
                    message: _errorMessage!,
                    onRetry: () {
                      _clearError();
                      _loadData();
                    },
                  ),
                )
              : _flights.isEmpty
                  ? AppEmptyState.flights(
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
                    )
                  : _buildFlightList(_sortedFlights),
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