import 'package:flutter/material.dart';
import '../../data/models/flight.dart';
import '../../data/repositories/flight_repository.dart';
import 'add_flight_screen.dart';
import 'igc_import_screen.dart';
import 'flight_detail_screen.dart';
import 'wing_management_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadFlights();
  }

  Future<void> _loadFlights() async {
    try {
      final flights = await _flightRepository.getAllFlights();
      setState(() {
        _flights = flights;
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
                  }
                },
                itemBuilder: (context) => [
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
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard('Total Flights', _flights.length.toString()),
              _buildStatCard(
                'Total Time',
                _formatDuration(
                  _flights.fold(0, (sum, flight) => sum + flight.duration),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _flights.length,
            itemBuilder: (context, index) {
              final flight = _flights[index];
              return _buildFlightCard(flight);
            },
          ),
        ),
      ],
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

  Widget _buildFlightCard(Flight flight) {
    final isSelected = _selectedFlightIds.contains(flight.id);
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        leading: _isSelectionMode 
          ? Checkbox(
              value: isSelected,
              onChanged: (selected) => _toggleFlightSelection(flight.id!),
            )
          : CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(
                flight.source == 'igc' ? Icons.gps_fixed : Icons.flight_takeoff,
                color: Colors.white,
              ),
            ),
        title: Text(
          '${flight.date.day}/${flight.date.month}/${flight.date.year}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${flight.launchTime} - ${flight.landingTime}'),
            Text(
              'Duration: ${_formatDuration(flight.duration)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (flight.maxAltitude != null)
              Text('Max altitude: ${flight.maxAltitude!.toInt()}m'),
          ],
        ),
        trailing: _isSelectionMode 
          ? null 
          : const Icon(Icons.chevron_right),
        onTap: () async {
          if (_isSelectionMode) {
            _toggleFlightSelection(flight.id!);
          } else {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (context) => FlightDetailScreen(flight: flight),
              ),
            );
            if (result == true) {
              _loadFlights(); // Reload if flight was deleted
            }
          }
        },
        onLongPress: _isSelectionMode ? null : () {
          _toggleSelectionMode();
          _toggleFlightSelection(flight.id!);
        },
      ),
    );
  }
}