import 'package:flutter/material.dart';
import '../../data/models/wing.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';
import 'edit_wing_screen.dart';
import '../widgets/wing_merge_dialog.dart';

class WingManagementScreen extends StatefulWidget {
  const WingManagementScreen({super.key});

  @override
  State<WingManagementScreen> createState() => _WingManagementScreenState();
}

class _WingManagementScreenState extends State<WingManagementScreen> {
  final DatabaseService _databaseService = DatabaseService.instance;
  List<Wing> _wings = [];
  Map<int, int> _flightCounts = {};
  bool _isLoading = false;
  String? _errorMessage;

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
      final opId = LoggingService.startOperation('WINGS_LOAD');
      
      // Log structured data about the wings query
      LoggingService.structured('WINGS_QUERY', {
        'operation_id': opId,
        'include_flight_counts': true,
      });
      
      final wings = await _databaseService.getAllWings();
      
      // Load flight counts for each wing
      Map<int, int> flightCounts = {};
      int totalFlights = 0;
      for (final wing in wings) {
        if (wing.id != null) {
          final stats = await _databaseService.getWingStatisticsById(wing.id!);
          final flights = stats['totalFlights'] as int;
          flightCounts[wing.id!] = flights;
          totalFlights += flights;
        }
      }
      
      stopwatch.stop();
      
      // Calculate active vs inactive wings
      final activeCount = wings.where((w) => w.active).length;
      final inactiveCount = wings.length - activeCount;
      
      // Log performance with threshold monitoring
      LoggingService.performance(
        'Wings Load',
        Duration(milliseconds: stopwatch.elapsedMilliseconds),
        'wings loaded with flight counts',
      );
      
      if (mounted) {
        setState(() {
          _wings = wings;
          _flightCounts = flightCounts;
          _isLoading = false;
        });
        
        // End operation with summary
        LoggingService.endOperation('WINGS_LOAD', results: {
          'total_wings': wings.length,
          'active_wings': activeCount,
          'inactive_wings': inactiveCount,
          'total_flights': totalFlights,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to load wings', e, stackTrace);
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load wings: $e';
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

  Future<void> _addNewWing() async {
    // Log user action
    LoggingService.action('WingManagement', 'add_wing_initiated', {
      'current_wing_count': _wings.length,
    });
    
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const EditWingScreen(),
      ),
    );

    if (result == true && mounted) {
      LoggingService.action('WingManagement', 'add_wing_completed', {
        'wing_added': true,
      });
      _loadData();
    } else {
      LoggingService.action('WingManagement', 'add_wing_cancelled', {});
    }
  }

  Future<void> _editWing(Wing wing) async {
    // Log user action with context
    LoggingService.action('WingManagement', 'edit_wing_initiated', {
      'wing_id': wing.id,
      'wing_name': wing.displayName,
      'is_active': wing.active,
    });
    
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => EditWingScreen(wing: wing),
      ),
    );

    if (result == true && mounted) {
      LoggingService.action('WingManagement', 'edit_wing_completed', {
        'wing_id': wing.id,
        'wing_edited': true,
      });
      _loadData();
    } else {
      LoggingService.action('WingManagement', 'edit_wing_cancelled', {
        'wing_id': wing.id,
      });
    }
  }

  Future<void> _deleteWing(Wing wing) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Wing'),
        content: Text('Are you sure you want to delete "${wing.displayName}"? This action cannot be undone.'),
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

    if (confirmed == true && mounted) {
      bool success = false;
      String? errorMessage;
      
      // Log user action with rich context
      LoggingService.action('WingManagement', 'delete_wing_confirmed', {
        'wing_id': wing.id,
        'wing_name': wing.displayName,
        'flight_count': _flightCounts[wing.id!] ?? 0,
      });
      
      try {
        final canDelete = await _databaseService.canDeleteWing(wing.id!);
        if (!canDelete) {
          errorMessage = 'Cannot delete wing - it is used in flight records';
          LoggingService.structured('WING_DELETE_BLOCKED', {
            'wing_id': wing.id,
            'reason': 'has_flight_records',
            'flight_count': _flightCounts[wing.id!] ?? 0,
          });
        } else {
          await _databaseService.deleteWing(wing.id!);
          success = true;
          LoggingService.summary('WING_DELETED', {
            'wing_id': wing.id,
            'wing_name': wing.displayName,
            'was_active': wing.active,
          });
          _loadData();
        }
      } catch (e, stackTrace) {
        LoggingService.error('Failed to delete wing', e, stackTrace);
        errorMessage = 'Failed to delete wing: $e';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
                ? 'Wing "${wing.displayName}" deleted successfully'
                : errorMessage ?? 'Error deleting wing'),
            backgroundColor: success ? null : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleWingStatus(Wing wing) async {
    final updatedWing = wing.copyWith(active: !wing.active);

    // Log user action
    LoggingService.action('WingManagement', 'toggle_wing_status', {
      'wing_id': wing.id,
      'wing_name': wing.displayName,
      'from_active': wing.active,
      'to_active': !wing.active,
      'flight_count': _flightCounts[wing.id!] ?? 0,
    });

    bool success = false;
    try {
      await _databaseService.updateWing(updatedWing);
      success = true;
      LoggingService.structured('WING_STATUS_CHANGED', {
        'wing_id': wing.id,
        'wing_name': wing.displayName,
        'new_status': !wing.active ? 'active' : 'inactive',
      });
      _loadData();
    } catch (e, stackTrace) {
      LoggingService.error('Failed to update wing status', e, stackTrace);
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Wing "${wing.displayName}" ${wing.active ? 'deactivated' : 'activated'}'
              : 'Error updating wing'),
          backgroundColor: success ? null : Colors.red,
        ),
      );
    }
  }

  Future<void> _showMergeDialog() async {
    // Log user action with context
    LoggingService.action('WingManagement', 'merge_wings_initiated', {
      'total_wings': _wings.length,
      'active_wings': _wings.where((w) => w.active).length,
    });
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => WingMergeDialog(
        wings: _wings,
        flightCounts: _flightCounts,
      ),
    );

    if (result == true && mounted) {
      LoggingService.action('WingManagement', 'merge_wings_completed', {
        'wings_merged': true,
      });
      _loadData();
    } else {
      LoggingService.action('WingManagement', 'merge_wings_cancelled', {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wing Management'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_wings.length >= 2)
            IconButton(
              icon: const Icon(Icons.merge_type),
              tooltip: 'Merge Wings',
              onPressed: _showMergeDialog,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: Colors.red[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading wings',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          _clearError();
                          _loadData();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _wings.isEmpty
                  ? _buildEmptyState()
                  : _buildWingList(_wings),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewWing,
        tooltip: 'Add Wing',
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
            Icons.paragliding,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No wings found',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first wing to get started',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addNewWing,
            icon: const Icon(Icons.add),
            label: const Text('Add Wing'),
          ),
        ],
      ),
    );
  }

  Widget _buildWingList(List<Wing> wings) {
    final activeWings = wings.where((wing) => wing.active).toList();
    final inactiveWings = wings.where((wing) => !wing.active).toList();

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      children: [
        if (activeWings.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Active Wings',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...activeWings.map((wing) => _buildWingCard(wing)),
        ],
        
        if (inactiveWings.isNotEmpty) ...[
          if (activeWings.isNotEmpty) const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Inactive Wings',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...inactiveWings.map((wing) => _buildWingCard(wing)),
        ],
      ],
    );
  }

  Widget _buildWingCard(Wing wing) {
    return Opacity(
      opacity: wing.active ? 1.0 : 0.6,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: wing.active 
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[400],
            child: const Icon(
              Icons.paragliding,
              color: Colors.white,
              size: 20,
            ),
          ),
          title: Text(
            wing.displayName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              decoration: wing.active ? null : TextDecoration.lineThrough,
            ),
          ),
          subtitle: (wing.size?.isNotEmpty == true) || (wing.notes?.isNotEmpty == true)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (wing.size?.isNotEmpty == true)
                    Text(
                      'Size: ${wing.size}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  if (wing.notes?.isNotEmpty == true)
                    Text(
                      wing.notes!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              )
            : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (wing.id != null && (_flightCounts[wing.id!] ?? 0) > 0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_flightCounts[wing.id!]} flight${_flightCounts[wing.id!] == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _editWing(wing);
                      break;
                    case 'toggle':
                      _toggleWingStatus(wing);
                      break;
                    case 'delete':
                      _deleteWing(wing);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(wing.active ? Icons.visibility_off : Icons.visibility),
                        SizedBox(width: 8),
                        Text(wing.active ? 'Deactivate' : 'Activate'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: () => _editWing(wing),
        ),
      ),
    );
  }
}