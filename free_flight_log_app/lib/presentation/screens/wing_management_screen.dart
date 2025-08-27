import 'package:flutter/material.dart';
import '../../data/models/wing.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';
import 'edit_wing_screen.dart';

class WingManagementScreen extends StatefulWidget {
  const WingManagementScreen({super.key});

  @override
  State<WingManagementScreen> createState() => _WingManagementScreenState();
}

class _WingManagementScreenState extends State<WingManagementScreen> {
  final DatabaseService _databaseService = DatabaseService.instance;
  List<Wing> _wings = [];
  Map<int, int> _flightCounts = {}; // Store flight counts per wing
  bool _isLoading = false;
  String? _errorMessage;
  bool _isSelectionMode = false;
  final Set<int> _selectedWingIds = {};

  @override
  void initState() {
    super.initState();
    _loadWings();
  }

  Future<void> _loadWings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      LoggingService.debug('WingManagementScreen: Loading wings');
      final wings = await _databaseService.getAllWings();
      
      // Load flight counts for each wing
      Map<int, int> flightCounts = {};
      for (final wing in wings) {
        if (wing.id != null) {
          final stats = await _databaseService.getWingStatisticsById(wing.id!);
          flightCounts[wing.id!] = stats['totalFlights'] as int;
        }
      }
      
      if (mounted) {
        setState(() {
          _wings = wings;
          _flightCounts = flightCounts;
          _isLoading = false;
        });
        LoggingService.info('WingManagementScreen: Loaded ${wings.length} wings with flight counts');
      }
    } catch (e) {
      LoggingService.error('WingManagementScreen: Failed to load wings', e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load wings: $e';
          _isLoading = false;
        });
      }
    }
  }
  
  String _getWingDisplayName(Wing wing) {
    List<String> parts = [];
    if (wing.manufacturer != null && wing.manufacturer!.isNotEmpty) {
      parts.add(wing.manufacturer!);
    }
    if (wing.model != null && wing.model!.isNotEmpty) {
      parts.add(wing.model!);
    }
    
    // If we have manufacturer/model, use them
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    
    // Otherwise fall back to name
    return wing.name;
  }

  Future<void> _addNewWing() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const EditWingScreen(),
      ),
    );

    if (result == true && mounted) {
      _loadWings();
    }
  }

  Future<void> _editWing(Wing wing) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => EditWingScreen(wing: wing),
      ),
    );

    if (result == true && mounted) {
      _loadWings();
    }
  }

  Future<void> _deleteWing(Wing wing) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Wing'),
        content: Text('Are you sure you want to delete "${wing.name}"? This action cannot be undone.'),
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
      
      try {
        // Check if wing can be deleted
        final canDelete = await _databaseService.canDeleteWing(wing.id!);
        if (!canDelete) {
          errorMessage = 'Cannot delete wing - it is used in flight records';
        } else {
          LoggingService.debug('WingManagementScreen: Deleting wing ${wing.id}');
          await _databaseService.deleteWing(wing.id!);
          success = true;
          LoggingService.info('WingManagementScreen: Deleted wing ${wing.id}');
          _loadWings(); // Reload the list
        }
      } catch (e) {
        LoggingService.error('WingManagementScreen: Failed to delete wing', e);
        errorMessage = 'Failed to delete wing: $e';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
                ? 'Wing "${wing.name}" deleted successfully'
                : errorMessage ?? 'Error deleting wing'),
            backgroundColor: success ? null : Colors.red,
          ),
        );
      }
    }
  }


  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedWingIds.clear();
      }
    });
  }
  
  void _toggleWingSelection(int wingId) {
    setState(() {
      if (_selectedWingIds.contains(wingId)) {
        _selectedWingIds.remove(wingId);
      } else {
        _selectedWingIds.add(wingId);
      }
    });
  }
  
  Future<void> _mergeSelectedWings() async {
    if (_selectedWingIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 2 wings to merge'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Get selected wings
    final selectedWings = _wings.where((w) => _selectedWingIds.contains(w.id)).toList();
    
    // Show dialog to select primary wing
    final primaryWing = await showDialog<Wing>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Primary Wing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose which wing to keep. The other wings will be merged into this one:'),
            const SizedBox(height: 16),
            ...selectedWings.map((wing) => ListTile(
              title: Text(_getWingDisplayName(wing)),
              subtitle: Text('${_flightCounts[wing.id!] ?? 0} flights'),
              onTap: () => Navigator.of(context).pop(wing),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    
    if (primaryWing == null) return;
    
    // Confirm merge
    final totalFlights = selectedWings
        .where((w) => w.id != primaryWing.id)
        .fold(0, (sum, w) => sum + (_flightCounts[w.id!] ?? 0));
    
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Wing Merge'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Primary wing: ${_getWingDisplayName(primaryWing)}'),
            const SizedBox(height: 8),
            const Text('Wings to merge:'),
            ...selectedWings
                .where((w) => w.id != primaryWing.id)
                .map((w) => Text('  • ${_getWingDisplayName(w)} (${_flightCounts[w.id!] ?? 0} flights)')),
            const SizedBox(height: 16),
            Text('This will reassign $totalFlights flights to the primary wing.'),
            const SizedBox(height: 8),
            const Text('The merged wing names will be saved as aliases.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // Perform merge
    setState(() => _isLoading = true);
    
    try {
      final wingIdsToMerge = selectedWings
          .where((w) => w.id != primaryWing.id)
          .map((w) => w.id!)
          .toList();
      
      await _databaseService.mergeWings(primaryWing.id!, wingIdsToMerge);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully merged ${wingIdsToMerge.length} wings into ${_getWingDisplayName(primaryWing)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      _toggleSelectionMode();
      _loadWings();
    } catch (e) {
      LoggingService.error('WingManagementScreen: Failed to merge wings', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error merging wings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleWingStatus(Wing wing) async {
    final updatedWing = Wing(
      id: wing.id,
      name: wing.name,
      manufacturer: wing.manufacturer,
      model: wing.model,
      size: wing.size,
      color: wing.color,
      purchaseDate: wing.purchaseDate,
      active: !wing.active,
      notes: wing.notes,
      createdAt: wing.createdAt,
    );

    bool success = false;
    try {
      LoggingService.debug('WingManagementScreen: Toggling wing ${wing.id} status');
      await _databaseService.updateWing(updatedWing);
      success = true;
      LoggingService.info('WingManagementScreen: Updated wing ${wing.id} status');
      _loadWings(); // Reload the list
    } catch (e) {
      LoggingService.error('WingManagementScreen: Failed to update wing status', e);
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Wing "${wing.name}" ${wing.active ? 'deactivated' : 'activated'}'
              : 'Error updating wing'),
          backgroundColor: success ? null : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode 
            ? '${_selectedWingIds.length} selected' 
            : 'Wing Management'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: [
          if (_isSelectionMode) ...[
            if (_selectedWingIds.length >= 2)
              IconButton(
                icon: const Icon(Icons.merge),
                tooltip: 'Merge Wings',
                onPressed: _mergeSelectedWings,
              ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.merge_type),
              tooltip: 'Select Wings to Merge',
              onPressed: _wings.length >= 2 ? _toggleSelectionMode : null,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Wing',
              onPressed: _addNewWing,
            ),
          ],
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
                          setState(() => _errorMessage = null);
                          _loadWings();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _wings.isEmpty
                  ? _buildEmptyState()
                  : _buildWingList(_wings),
      floatingActionButton: _isSelectionMode ? null : FloatingActionButton(
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
          Text(
            'Active Wings',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...activeWings.map((wing) => _buildWingCard(wing)),
        ],
        
        if (inactiveWings.isNotEmpty) ...[
          if (activeWings.isNotEmpty) const SizedBox(height: 24),
          Text(
            'Inactive Wings',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          ...inactiveWings.map((wing) => _buildWingCard(wing)),
        ],
      ],
    );
  }

  Widget _buildWingCard(Wing wing) {
    final isSelected = _selectedWingIds.contains(wing.id);
    
    return Opacity(
      opacity: wing.active ? 1.0 : 0.6,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
        child: GestureDetector(
          onDoubleTap: () => _isSelectionMode ? null : _editWing(wing),
          onTap: _isSelectionMode && wing.id != null 
              ? () => _toggleWingSelection(wing.id!) 
              : null,
          child: ListTile(
        leading: _isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: wing.id != null 
                    ? (value) => _toggleWingSelection(wing.id!)
                    : null,
              )
            : CircleAvatar(
          backgroundColor: wing.active 
            ? Theme.of(context).colorScheme.primary
            : Colors.grey[400],
          child: Icon(
            Icons.paragliding,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          _getWingDisplayName(wing),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: wing.active ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: (wing.size != null && wing.size!.isNotEmpty) || 
                  (wing.notes != null && wing.notes!.isNotEmpty)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wing.size != null && wing.size!.isNotEmpty)
                  Text(
                    'Size: ${wing.size}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                if (wing.notes != null && wing.notes!.isNotEmpty)
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
            if (wing.id != null && _flightCounts[wing.id!] != null && _flightCounts[wing.id!]! > 0)
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
            if (!_isSelectionMode) PopupMenuButton<String>(
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
                  const SizedBox(width: 8),
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
      ),
    );
  }
}