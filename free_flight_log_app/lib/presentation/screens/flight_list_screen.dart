import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/flight.dart';
import '../../providers/flight_provider.dart';
import '../../utils/date_time_utils.dart';
import 'add_flight_screen.dart';
import 'igc_import_screen.dart';
import 'flight_detail_screen.dart';
import 'wing_management_screen.dart';
import 'manage_sites_screen.dart';
import 'statistics_screen.dart';
import 'database_settings_screen.dart';
import 'about_screen.dart';

class FlightListScreen extends StatefulWidget {
  const FlightListScreen({super.key});

  @override
  State<FlightListScreen> createState() => _FlightListScreenState();
}

class _FlightListScreenState extends State<FlightListScreen> {
  bool _isSelectionMode = false;
  Set<int> _selectedFlightIds = {};
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    // Load flights when the widget is first created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FlightProvider>().loadFlights();
    });
  }

  // Refresh flights from provider
  Future<void> _refreshFlights() async {
    await context.read<FlightProvider>().loadFlights();
  }
  
  void _sort(String column) {
    final provider = context.read<FlightProvider>();
    if (provider.sortColumn == column) {
      provider.setSorting(column, !provider.sortAscending);
    } else {
      provider.setSorting(column, true);
    }
  }


  /// Format time with timezone information

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
      final flightProvider = context.read<FlightProvider>();
      _selectedFlightIds = flightProvider.flights.map((flight) => flight.id!).toSet();
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
      final flightProvider = context.read<FlightProvider>();
      final flightCount = _selectedFlightIds.length;
      final success = await flightProvider.deleteFlights(_selectedFlightIds.toList());
      
      if (mounted) {
        setState(() {
          _isDeleting = false;
          if (success) {
            _isSelectionMode = false;
            _selectedFlightIds.clear();
          }
        });
        
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$flightCount flight${flightCount != 1 ? 's' : ''} deleted successfully'),
            ),
          );
        } else if (flightProvider.errorMessage != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(flightProvider.errorMessage!),
              backgroundColor: Colors.red,
            ),
          );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode 
          ? Text('${_selectedFlightIds.length} selected')
          : const Text('Free Flight Log'),
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
                      _refreshFlights();
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
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ManageSitesScreen(),
                      ),
                    );
                  } else if (value == 'statistics') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const StatisticsScreen(),
                      ),
                    );
                  } else if (value == 'database') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const DatabaseSettingsScreen(),
                      ),
                    );
                  } else if (value == 'about') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const AboutScreen(),
                      ),
                    );
                  }
                },
                itemBuilder: (context) => [
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
                  if (context.read<FlightProvider>().flights.isNotEmpty)
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
                        Text('Database Settings'),
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
      body: Consumer<FlightProvider>(
        builder: (context, flightProvider, child) {
          if (flightProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (flightProvider.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading flights',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    flightProvider.errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      flightProvider.clearError();
                      flightProvider.loadFlights();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          
          final flights = flightProvider.sortedFlights;
          
          if (flights.isEmpty) {
            return _buildEmptyState();
          }
          
          return _buildFlightList(flights, flightProvider);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => const AddFlightScreen(),
            ),
          );
          
          if (result == true) {
            _refreshFlights();
          }
        },
        tooltip: 'Add Flight',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.flight_takeoff,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No flights recorded yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to log your first flight',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlightList(List<Flight> flights, FlightProvider flightProvider) {
    // Calculate stats based on selection mode
    final flightsToCount = _isSelectionMode && _selectedFlightIds.isNotEmpty 
        ? flights.where((flight) => _selectedFlightIds.contains(flight.id)).toList()
        : flights;
    
    final totalFlights = flightsToCount.length;
    final totalTime = flightsToCount.fold(0, (sum, flight) => sum + flight.duration);
    
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(top: 16, bottom: 16),
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard(
                _isSelectionMode && _selectedFlightIds.isNotEmpty 
                    ? 'Selected Flights' 
                    : 'Total Flights', 
                totalFlights.toString(),
              ),
              _buildStatCard(
                _isSelectionMode && _selectedFlightIds.isNotEmpty 
                    ? 'Selected Time' 
                    : 'Total Time',
                DateTimeUtils.formatDuration(totalTime),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildFlightTable(flights, flightProvider),
        ),
      ],
    );
  }
  
  Widget _buildFlightTable(List<Flight> flights, FlightProvider flightProvider) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          showCheckboxColumn: _isSelectionMode,
          sortColumnIndex: flightProvider.sortColumn == 'launch_site' ? 0
              : flightProvider.sortColumn == 'datetime' ? 1
              : flightProvider.sortColumn == 'duration' ? 2
              : flightProvider.sortColumn == 'track_distance' ? 3
              : flightProvider.sortColumn == 'distance' ? 4
              : flightProvider.sortColumn == 'altitude' ? 5
              : 0,
          sortAscending: flightProvider.sortAscending,
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
                            _refreshFlights(); // Reload if flight was deleted or modified
                          }
                        },
                ),
                DataCell(
                  Text(
                    '${flight.date.day.toString().padLeft(2, '0')}/'
                    '${flight.date.month.toString().padLeft(2, '0')}/'
                    '${flight.date.year} ${flight.launchTime}',
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
                            _refreshFlights(); // Reload if flight was deleted or modified
                          }
                        },
                ),
                DataCell(
                  Text(DateTimeUtils.formatDuration(flight.duration)),
                  onTap: _isSelectionMode 
                      ? null 
                      : () async {
                          final result = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (context) => FlightDetailScreen(flight: flight),
                            ),
                          );
                          if (result == true) {
                            _refreshFlights(); // Reload if flight was deleted or modified
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
                            _refreshFlights(); // Reload if flight was deleted or modified
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
                            _refreshFlights(); // Reload if flight was deleted or modified
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
                            _refreshFlights(); // Reload if flight was deleted or modified
                          }
                        },
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );
  }

}