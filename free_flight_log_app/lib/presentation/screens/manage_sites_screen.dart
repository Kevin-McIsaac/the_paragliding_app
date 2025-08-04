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
  Map<String, List<Site>> _groupedSites = {};
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'country'; // 'name', 'country', 'date' - default to country grouping
  bool _groupByCountry = true;

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
        site.name.toLowerCase().contains(_searchQuery) ||
        (site.country?.toLowerCase().contains(_searchQuery) ?? false)
      ).toList();
    }
    
    // Sort the filtered sites
    _sortSites();
    
    // Group sites by country if enabled
    if (_groupByCountry) {
      _groupSitesByCountry();
    }
  }
  
  void _groupSitesByCountry() {
    _groupedSites.clear();
    
    for (final site in _filteredSites) {
      final country = site.country ?? 'Unknown Country';
      if (!_groupedSites.containsKey(country)) {
        _groupedSites[country] = [];
      }
      _groupedSites[country]!.add(site);
    }
    
    // Sort countries alphabetically, but put "Unknown Country" at the end
    final sortedCountries = _groupedSites.keys.toList();
    sortedCountries.sort((a, b) {
      if (a == 'Unknown Country' && b != 'Unknown Country') return 1;
      if (b == 'Unknown Country' && a != 'Unknown Country') return -1;
      return a.compareTo(b);
    });
    
    // Rebuild grouped sites in sorted order
    final sortedGroupedSites = <String, List<Site>>{};
    for (final country in sortedCountries) {
      sortedGroupedSites[country] = _groupedSites[country]!;
      // Sort sites within each country by name
      sortedGroupedSites[country]!.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    
    _groupedSites = sortedGroupedSites;
  }
  
  void _sortSites() {
    switch (_sortBy) {
      case 'name':
        _filteredSites.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'country':
        _filteredSites.sort((a, b) {
          final countryA = a.country ?? 'ZZZ'; // Put sites without country at end
          final countryB = b.country ?? 'ZZZ';
          final countryComparison = countryA.compareTo(countryB);
          if (countryComparison == 0) {
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          return countryComparison;
        });
        break;
      case 'date':
        _filteredSites.sort((a, b) {
          final dateA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return dateB.compareTo(dateA); // Most recent first
        });
        break;
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
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort sites',
            onSelected: (value) {
              setState(() {
                _sortBy = value;
                _groupByCountry = (value == 'country');
                _filterSites(); // Re-apply sort and grouping
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(
                      Icons.text_fields,
                      color: _sortBy == 'name' ? Theme.of(context).primaryColor : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sort by Name',
                      style: TextStyle(
                        fontWeight: _sortBy == 'name' ? FontWeight.bold : null,
                        color: _sortBy == 'name' ? Theme.of(context).primaryColor : null,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'country',
                child: Row(
                  children: [
                    Icon(
                      Icons.flag,
                      color: _sortBy == 'country' ? Theme.of(context).primaryColor : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Group by Country',
                      style: TextStyle(
                        fontWeight: _sortBy == 'country' ? FontWeight.bold : null,
                        color: _sortBy == 'country' ? Theme.of(context).primaryColor : null,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'date',
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      color: _sortBy == 'date' ? Theme.of(context).primaryColor : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sort by Date Added',
                      style: TextStyle(
                        fontWeight: _sortBy == 'date' ? FontWeight.bold : null,
                        color: _sortBy == 'date' ? Theme.of(context).primaryColor : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search sites by name or country...',
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
                      child: _groupByCountry ? _buildGroupedSiteList() : _buildFlatSiteList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildGroupedSiteList() {
    if (_groupedSites.isEmpty) {
      return const Center(child: Text('No sites found'));
    }

    return ListView.builder(
      itemCount: _groupedSites.length,
      itemBuilder: (context, countryIndex) {
        final country = _groupedSites.keys.elementAt(countryIndex);
        final sites = _groupedSites[country]!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Country header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.flag,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    country,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${sites.length}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Sites in this country
            ...sites.map((site) => _SiteListTile(
              site: site,
              onEdit: () => _editSite(site),
              onDelete: () => _deleteSite(site),
            )),
            const SizedBox(height: 8), // Space between country groups
          ],
        );
      },
    );
  }

  Widget _buildFlatSiteList() {
    return ListView.builder(
      itemCount: _filteredSites.length,
      itemBuilder: (context, index) {
        final site = _filteredSites[index];
        return _SiteListTile(
          site: site,
          onEdit: () => _editSite(site),
          onDelete: () => _deleteSite(site),
        );
      },
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
            Row(
              children: [
                if (site.altitude != null) ...[
                  Text(
                    'Altitude: ${site.altitude!.toStringAsFixed(0)}m',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  if (site.country != null) ...[
                    Text(' • ', style: TextStyle(color: Colors.grey[600])),
                  ],
                ],
                if (site.country != null)
                  Text(
                    site.country!,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else
                  Text(
                    'Unknown Country',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
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
  late TextEditingController _countryController;
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
    _countryController = TextEditingController(
      text: widget.site.country ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _altitudeController.dispose();
    _countryController.dispose();
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _countryController,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                  hintText: 'Optional',
                ),
                validator: (value) {
                  // Country is optional, no validation needed
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
                country: _countryController.text.trim().isEmpty
                    ? null
                    : _countryController.text.trim(),
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