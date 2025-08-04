import 'package:flutter/material.dart';
import '../../data/models/wing.dart';
import '../../data/repositories/wing_repository.dart';
import 'edit_wing_screen.dart';

class WingManagementScreen extends StatefulWidget {
  const WingManagementScreen({super.key});

  @override
  State<WingManagementScreen> createState() => _WingManagementScreenState();
}

class _WingManagementScreenState extends State<WingManagementScreen> {
  final WingRepository _wingRepository = WingRepository();
  List<Wing> _wings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWings();
  }

  Future<void> _loadWings() async {
    try {
      final wings = await _wingRepository.getAllWings();
      setState(() {
        _wings = wings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading wings: $e')),
        );
      }
    }
  }

  Future<void> _addNewWing() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const EditWingScreen(),
      ),
    );

    if (result == true) {
      _loadWings();
    }
  }

  Future<void> _editWing(Wing wing) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => EditWingScreen(wing: wing),
      ),
    );

    if (result == true) {
      _loadWings();
    }
  }

  Future<void> _deleteWing(Wing wing) async {
    // Check if wing can be deleted (not used in flights)
    final canDelete = await _wingRepository.canDeleteWing(wing.id!);
    
    if (!canDelete) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cannot Delete Wing'),
            content: const Text(
              'This wing is used in one or more flights and cannot be deleted. '
              'You can deactivate it instead to hide it from new flight entries.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _deactivateWing(wing);
                },
                child: const Text('Deactivate'),
              ),
            ],
          ),
        );
      }
      return;
    }

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

    if (confirmed == true) {
      try {
        await _wingRepository.deleteWing(wing.id!);
        _loadWings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Wing "${wing.name}" deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting wing: $e')),
          );
        }
      }
    }
  }

  Future<void> _deactivateWing(Wing wing) async {
    try {
      await _wingRepository.deactivateWing(wing.id!);
      _loadWings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wing "${wing.name}" deactivated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deactivating wing: $e')),
        );
      }
    }
  }

  Future<void> _toggleWingStatus(Wing wing) async {
    try {
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

      await _wingRepository.updateWing(updatedWing);
      _loadWings();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Wing "${wing.name}" ${wing.active ? 'deactivated' : 'activated'}'
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating wing: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wing Management'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Wing',
            onPressed: _addNewWing,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _wings.isEmpty
              ? _buildEmptyState()
              : _buildWingList(),
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

  Widget _buildWingList() {
    final activeWings = _wings.where((wing) => wing.active).toList();
    final inactiveWings = _wings.where((wing) => !wing.active).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
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
    return Opacity(
      opacity: wing.active ? 1.0 : 0.6,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onDoubleTap: () => _editWing(wing),
          child: ListTile(
        leading: CircleAvatar(
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
          wing.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: wing.active ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wing.manufacturer != null || wing.model != null)
              Text('${wing.manufacturer ?? ''} ${wing.model ?? ''}'.trim()),
            if (wing.size != null)
              Text('Size: ${wing.size}'),
          ],
        ),
        trailing: PopupMenuButton<String>(
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
        onTap: () => _editWing(wing),
        ),
        ),
      ),
    );
  }
}