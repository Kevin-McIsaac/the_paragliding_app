import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/wing.dart';
import '../../providers/wing_provider.dart';
import 'edit_wing_screen.dart';

class WingManagementScreen extends StatefulWidget {
  const WingManagementScreen({super.key});

  @override
  State<WingManagementScreen> createState() => _WingManagementScreenState();
}

class _WingManagementScreenState extends State<WingManagementScreen> {
  @override
  void initState() {
    super.initState();
    // Load wings when the widget is first created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WingProvider>().loadWings();
    });
  }

  Future<void> _addNewWing() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const EditWingScreen(),
      ),
    );

    if (result == true && mounted) {
      context.read<WingProvider>().loadWings();
    }
  }

  Future<void> _editWing(Wing wing) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => EditWingScreen(wing: wing),
      ),
    );

    if (result == true && mounted) {
      context.read<WingProvider>().loadWings();
    }
  }

  Future<void> _deleteWing(Wing wing) async {
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
      final success = await context.read<WingProvider>().deleteWing(wing.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
                ? 'Wing "${wing.name}" deleted successfully'
                : 'Error deleting wing'),
            backgroundColor: success ? null : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deactivateWing(Wing wing) async {
    // Deactivate by updating the wing with active = false
    final deactivatedWing = Wing(
      id: wing.id,
      name: wing.name,
      manufacturer: wing.manufacturer,
      model: wing.model,
      size: wing.size,
      color: wing.color,
      purchaseDate: wing.purchaseDate,
      active: false,
      notes: wing.notes,
      createdAt: wing.createdAt,
    );
    
    final success = await context.read<WingProvider>().updateWing(deactivatedWing);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
              ? 'Wing "${wing.name}" deactivated'
              : 'Error deactivating wing'),
          backgroundColor: success ? null : Colors.red,
        ),
      );
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

    final success = await context.read<WingProvider>().updateWing(updatedWing);
    
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
      body: Consumer<WingProvider>(
        builder: (context, wingProvider, child) {
          if (wingProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (wingProvider.errorMessage != null) {
            return Center(
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
                    wingProvider.errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      wingProvider.clearError();
                      wingProvider.loadWings();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          
          final wings = wingProvider.wings;
          
          if (wings.isEmpty) {
            return _buildEmptyState();
          }
          
          return _buildWingList(wings);
        },
      ),
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