import 'package:flutter/material.dart';
import '../../data/models/site.dart';
import '../../data/repositories/site_repository.dart';

class ManageSitesScreen extends StatefulWidget {
  const ManageSitesScreen({super.key});

  @override
  State<ManageSitesScreen> createState() => _ManageSitesScreenState();
}

class _ManageSitesScreenState extends State<ManageSitesScreen> {
  final SiteRepository _siteRepository = SiteRepository();
  List<Site> _sites = [];
  List<Site> _filteredSites = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSites();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filterSites();
    });
  }

  void _filterSites() {
    if (_searchQuery.isEmpty) {
      _filteredSites = List.from(_sites);
    } else {
      _filteredSites = _sites.where((site) =>
        site.name.toLowerCase().contains(_searchQuery)
      ).toList();
    }
  }

  Future<void> _loadSites() async {
    setState(() => _isLoading = true);
    try {
      final sites = await _siteRepository.getAllSites();
      setState(() {
        _sites = sites;
        _filterSites();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showErrorDialog('Error', 'Failed to load sites: $e');
      }
    }
  }

  Future<void> _deleteSite(Site site) async {
    // Check if site can be deleted
    final canDelete = await _siteRepository.canDeleteSite(site.id!);
    
    if (!canDelete) {
      _showErrorDialog(
        'Cannot Delete Site',
        'This site is used in flight records and cannot be deleted.\n\n'
        'You can edit the site name or other details instead.',
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await _showConfirmationDialog(
      'Delete Site',
      'Are you sure you want to delete "${site.name}"?\n\n'
      'This action cannot be undone.',
    );

    if (!confirmed) return;

    try {
      await _siteRepository.deleteSite(site.id!);
      await _loadSites(); // Refresh list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Site "${site.name}" deleted')),
        );
        // Return true to indicate sites were modified
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Error', 'Failed to delete site: $e');
      }
    }
  }

  Future<void> _editSite(Site site) async {
    final result = await showDialog<Site>(
      context: context,
      builder: (context) => _EditSiteDialog(site: site),
    );

    if (result != null) {
      try {
        await _siteRepository.updateSite(result);
        await _loadSites(); // Refresh list
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Site "${result.name}" updated')),
          );
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog('Error', 'Failed to update site: $e');
        }
      }
    }
  }

  Future<bool> _showConfirmationDialog(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Sites'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search sites...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredSites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _searchQuery.isEmpty ? Icons.location_off : Icons.search_off,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty 
                            ? 'No sites found'
                            : 'No sites match your search',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Sites will appear here after importing flights'
                            : 'Try a different search term',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary header  
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: Text(
                        'Showing ${_filteredSites.length} of ${_sites.length} sites',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    // Site list
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredSites.length,
                        itemBuilder: (context, index) {
                          final site = _filteredSites[index];
                          return _SiteListTile(
                            site: site,
                            onEdit: () => _editSite(site),
                            onDelete: () => _deleteSite(site),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _SiteListTile extends StatelessWidget {
  final Site site;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SiteListTile({
    required this.site,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.location_on),
        title: Text(
          site.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${site.latitude.toStringAsFixed(6)}, ${site.longitude.toStringAsFixed(6)}',
              style: TextStyle(
                fontFamily: 'monospace',
                color: Colors.grey[600],
              ),
            ),
            if (site.altitude != null)
              Text(
                'Altitude: ${site.altitude!.toStringAsFixed(0)}m',
                style: TextStyle(color: Colors.grey[600]),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
                break;
              case 'delete':
                onDelete();
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
      ),
    );
  }
}

class _EditSiteDialog extends StatefulWidget {
  final Site site;

  const _EditSiteDialog({required this.site});

  @override
  State<_EditSiteDialog> createState() => _EditSiteDialogState();
}

class _EditSiteDialogState extends State<_EditSiteDialog> {
  late TextEditingController _nameController;
  late TextEditingController _latitudeController;
  late TextEditingController _longitudeController;
  late TextEditingController _altitudeController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.site.name);
    _latitudeController = TextEditingController(text: widget.site.latitude.toString());
    _longitudeController = TextEditingController(text: widget.site.longitude.toString());
    _altitudeController = TextEditingController(
      text: widget.site.altitude?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _altitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Site'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Site Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Site name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latitudeController,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        final lat = double.tryParse(value.trim());
                        if (lat == null || lat < -90 || lat > 90) {
                          return 'Invalid latitude';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _longitudeController,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        final lon = double.tryParse(value.trim());
                        if (lon == null || lon < -180 || lon > 180) {
                          return 'Invalid longitude';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _altitudeController,
                decoration: const InputDecoration(
                  labelText: 'Altitude (m)',
                  border: OutlineInputBorder(),
                  hintText: 'Optional',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final alt = double.tryParse(value.trim());
                    if (alt == null) {
                      return 'Invalid altitude';
                    }
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final updatedSite = widget.site.copyWith(
                name: _nameController.text.trim(),
                latitude: double.parse(_latitudeController.text.trim()),
                longitude: double.parse(_longitudeController.text.trim()),
                altitude: _altitudeController.text.trim().isEmpty
                    ? null
                    : double.parse(_altitudeController.text.trim()),
                customName: true, // Mark as custom since user edited it
              );
              Navigator.of(context).pop(updatedSite);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}