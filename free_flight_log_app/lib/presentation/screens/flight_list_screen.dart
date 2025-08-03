import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../data/repositories/flight_repository.dart';
import 'add_flight_screen.dart';
import 'igc_import_screen.dart';
import 'flight_detail_screen.dart';
import 'wing_management_screen.dart';
import 'statistics_screen.dart';

class FlightListScreen extends StatefulWidget {
  const FlightListScreen({super.key});

  @override
  State<FlightListScreen> createState() => _FlightListScreenState();
}

class _FlightListScreenState extends State<FlightListScreen> {
  final FlightRepository _flightRepository = FlightRepository();
  List<Flight> _flights = [];
  bool _isLoading = true;
  bool _isSelectionMode = false;
  Set<int> _selectedFlightIds = {};
  bool _isDeleting = false;
  
  // Sorting state
  String _sortColumn = 'datetime';
  bool _sortAscending = false; // Default to reverse (newest first)

  @override
  void initState() {
    super.initState();
    _loadFlights();
  }

  Future<void> _loadFlights() async {
    try {
      final flights = await _flightRepository.getAllFlights();
      setState(() {
        _flights = _sortFlights(flights);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading flights: $e')),
        );
      }
    }
  }
  
  List<Flight> _sortFlights(List<Flight> flights) {
    flights.sort((a, b) {
      int comparison;
      
      switch (_sortColumn) {
        case 'datetime':
          // Combine date and time for sorting
          final aDateTime = DateTime(
            a.date.year, a.date.month, a.date.day,
            int.parse(a.launchTime.split(':')[0]),
            int.parse(a.launchTime.split(':')[1]),
          );
          final bDateTime = DateTime(
            b.date.year, b.date.month, b.date.day,
            int.parse(b.launchTime.split(':')[0]),
            int.parse(b.launchTime.split(':')[1]),
          );
          comparison = aDateTime.compareTo(bDateTime);
          break;
        case 'duration':
          comparison = a.duration.compareTo(b.duration);
          break;
        case 'distance':
          final aDist = a.straightDistance ?? 0.0;
          final bDist = b.straightDistance ?? 0.0;
          comparison = aDist.compareTo(bDist);
          break;
        case 'altitude':
          final aAlt = a.maxAltitude ?? 0.0;
          final bAlt = b.maxAltitude ?? 0.0;
          comparison = aAlt.compareTo(bAlt);
          break;
        default:
          comparison = 0;
      }
      
      return _sortAscending ? comparison : -comparison;
    });
    
    return flights;
  }
  
  void _sort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _flights = _sortFlights(_flights);
    });
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
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
    if (_selectedFlightIds.isEmpty) return;

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

    if (confirmed == true) {
      setState(() {
        _isDeleting = true;
      });

      try {
        // Delete selected flights
        for (final flightId in _selectedFlightIds) {
          await _flightRepository.deleteFlight(flightId);
        }

        // Exit selection mode and reload flights
        setState(() {
          _isSelectionMode = false;
          _selectedFlightIds.clear();
          _isDeleting = false;
        });

        _loadFlights();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_selectedFlightIds.length} flight${_selectedFlightIds.length != 1 ? 's' : ''} deleted successfully'),
            ),
          );
        }
      } catch (e) {
        setState(() {
          _isDeleting = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting flights: $e')),
          );
        }
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
              if (_selectedFlightIds.length != _flights.length)
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
              IconButton(
                icon: const Icon(Icons.upload_file),
                tooltip: 'Import IGC',
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (context) => const IgcImportScreen(),
                    ),
                  );
                  
                  if (result == true) {
                    _loadFlights();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                  });
                  _loadFlights();
                },
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'select') {
                    _toggleSelectionMode();
                  } else if (value == 'wings') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const WingManagementScreen(),
                      ),
                    );
                  } else if (value == 'statistics') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const StatisticsScreen(),
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
                ],
              ),
            ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _flights.isEmpty
              ? _buildEmptyState()
              : _buildFlightList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => const AddFlightScreen(),
            ),
          );
          
          if (result == true) {
            _loadFlights();
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

  Widget _buildFlightList() {
    // Calculate stats based on selection mode
    final flightsToCount = _isSelectionMode && _selectedFlightIds.isNotEmpty 
        ? _flights.where((flight) => _selectedFlightIds.contains(flight.id)).toList()
        : _flights;
    
    final totalFlights = flightsToCount.length;
    final totalTime = flightsToCount.fold(0, (sum, flight) => sum + flight.duration);
    
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
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
                _formatDuration(totalTime),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildFlightTable(),
        ),
      ],
    );
  }
  
  Widget _buildFlightTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          showCheckboxColumn: _isSelectionMode,
          sortColumnIndex: _sortColumn == 'datetime' ? 0 
              : _sortColumn == 'duration' ? 1
              : _sortColumn == 'distance' ? 2
              : _sortColumn == 'altitude' ? 3
              : 0,
          sortAscending: _sortAscending,
          columns: [
            DataColumn(
              label: const Text('Launch Date & Time'),
              onSort: (columnIndex, ascending) => _sort('datetime'),
            ),
            DataColumn(
              label: const Text('Duration'),
              onSort: (columnIndex, ascending) => _sort('duration'),
            ),
            DataColumn(
              label: const Text('Distance (km)'),
              numeric: true,
              onSort: (columnIndex, ascending) => _sort('distance'),
            ),
            DataColumn(
              label: const Text('Max Alt (m)'),
              numeric: true,
              onSort: (columnIndex, ascending) => _sort('altitude'),
            ),
          ],
          rows: _flights.map((flight) {
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
                            _loadFlights(); // Reload if flight was deleted or modified
                          }
                        },
                ),
                DataCell(
                  Text(_formatDuration(flight.duration)),
                  onTap: _isSelectionMode 
                      ? null 
                      : () async {
                          final result = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (context) => FlightDetailScreen(flight: flight),
                            ),
                          );
                          if (result == true) {
                            _loadFlights(); // Reload if flight was deleted or modified
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
                            _loadFlights(); // Reload if flight was deleted or modified
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
                            _loadFlights(); // Reload if flight was deleted or modified
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