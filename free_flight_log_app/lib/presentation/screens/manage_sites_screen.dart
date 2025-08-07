import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/site.dart';
import '../../utils/ui_utils.dart';
import '../widgets/edit_site_dialog.dart';
import '../../providers/site_provider.dart';

class ManageSitesScreen extends StatefulWidget {
  const ManageSitesScreen({super.key});

  @override
  State<ManageSitesScreen> createState() => _ManageSitesScreenState();
}

class _ManageSitesScreenState extends State<ManageSitesScreen> {
  List<Site> _filteredSites = [];
  Map<String, List<Site>> _groupedSites = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'country'; // 'name', 'country', 'date' - default to country grouping
  bool _groupByCountry = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SiteProvider>().loadSitesWithFlightCounts();
    });
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
      _filterSites(context.read<SiteProvider>().sites);
    });
  }

  void _filterSites(List<Site> sites) {
    if (_searchQuery.isEmpty) {
      _filteredSites = List.from(sites);
    } else {
      _filteredSites = sites.where((site) =>
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


  Future<void> _deleteSite(Site site) async {
    if (!mounted) return;
    
    // Show confirmation dialog
    final confirmed = await UiUtils.showDeleteConfirmation(
      context,
      'Delete Site',
      'Are you sure you want to delete "${site.name}"?\n\n'
      'This action cannot be undone.',
    );

    if (!confirmed || !mounted) return;

    final success = await context.read<SiteProvider>().deleteSite(site.id!);
    
    if (mounted) {
      if (success) {
        UiUtils.showSuccessMessage(context, 'Site "${site.name}" deleted');
        // Return true to indicate sites were modified
        Navigator.of(context).pop(true);
      } else {
        final errorMessage = context.read<SiteProvider>().errorMessage;
        if (errorMessage != null) {
          if (errorMessage.contains('used in flight records')) {
            UiUtils.showErrorDialog(
              context,
              'Cannot Delete Site',
              'This site is used in flight records and cannot be deleted.\n\n'
              'You can edit the site name or other details instead.',
            );
          } else {
            UiUtils.showErrorDialog(context, 'Error', errorMessage);
          }
        }
      }
    }
  }

  Future<void> _editSite(Site site) async {
    final result = await showDialog<Site>(
      context: context,
      builder: (context) => EditSiteDialog(site: site),
    );

    if (result != null && mounted) {
      final success = await context.read<SiteProvider>().updateSite(result);
      
      if (mounted) {
        if (success) {
          UiUtils.showSuccessMessage(context, 'Site "${result.name}" updated');
        } else {
          final errorMessage = context.read<SiteProvider>().errorMessage;
          if (errorMessage != null) {
            UiUtils.showErrorDialog(context, 'Error', errorMessage);
          }
        }
      }
    }
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
                final provider = context.read<SiteProvider>();
                _filterSites(provider.sites); // Re-apply sort and grouping
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
      body: Consumer<SiteProvider>(
        builder: (context, siteProvider, child) {
          // Update filtered sites when provider data changes
          if (siteProvider.sites.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _filterSites(siteProvider.sites);
            });
          }

          if (siteProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (siteProvider.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading sites',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    siteProvider.errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      siteProvider.clearError();
                      siteProvider.loadSitesWithFlightCounts();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (_filteredSites.isEmpty && siteProvider.sites.isEmpty) {
            return Center(
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
            );
          }

          if (_filteredSites.isEmpty && siteProvider.sites.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.search_off,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No sites match your search',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try a different search term',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Summary header  
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text(
                  'Showing ${_filteredSites.length} of ${siteProvider.sites.length} sites',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              // Site list
              Expanded(
                child: _groupByCountry ? _buildGroupedSiteList() : _buildFlatSiteList(),
              ),
            ],
          );
        },
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
      child: GestureDetector(
        onDoubleTap: onEdit,
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
                  Text(' • ', style: TextStyle(color: Colors.grey[600])),
                ],
                if (site.country != null) ...[
                  Text(
                    site.country!,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(' • ', style: TextStyle(color: Colors.grey[600])),
                ]
                else ...[
                  Text(
                    'Unknown Country',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  Text(' • ', style: TextStyle(color: Colors.grey[600])),
                ],
                Text(
                  '${site.flightCount ?? 0} flights',
                  style: TextStyle(
                    color: site.flightCount != null && site.flightCount! > 0 
                      ? Colors.green[600] 
                      : Colors.grey[600],
                    fontWeight: FontWeight.w500,
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
      ),
    );
  }
}

