import 'package:flutter/material.dart';
import '../../data/models/site.dart';
import '../../utils/ui_utils.dart';
import 'edit_site_screen.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';

class ManageSitesScreen extends StatefulWidget {
  const ManageSitesScreen({super.key});

  @override
  State<ManageSitesScreen> createState() => _ManageSitesScreenState();
}

class _ManageSitesScreenState extends State<ManageSitesScreen> {
  final DatabaseService _databaseService = DatabaseService.instance;
  List<Site> _sites = [];
  List<Site> _filteredSites = [];
  Map<String, List<Site>> _groupedSites = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'country'; // 'name', 'country', 'date' - default to country grouping
  bool _groupByCountry = true;
  bool _isLoading = false;
  String? _errorMessage;

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

  Future<void> _loadSites() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      LoggingService.debug('ManageSitesScreen: Loading sites with flight counts');
      final sites = await _databaseService.getSitesWithFlightCounts();
      
      if (mounted) {
        setState(() {
          _sites = sites;
          _filterSites(sites);
          _isLoading = false;
        });
        LoggingService.info('ManageSitesScreen: Loaded ${sites.length} sites');
      }
    } catch (e) {
      LoggingService.error('ManageSitesScreen: Failed to load sites', e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load sites: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filterSites(_sites);
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
      case 'flights':
        _filteredSites.sort((a, b) {
          final flightCountA = a.flightCount ?? 0;
          final flightCountB = b.flightCount ?? 0;
          final countComparison = flightCountB.compareTo(flightCountA); // Most flights first
          if (countComparison == 0) {
            return a.name.toLowerCase().compareTo(b.name.toLowerCase()); // Then by name
          }
          return countComparison;
        });
        break;
    }
  }

  Future<void> _addNewSite() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const EditSiteScreen(),
      ),
    );

    if (result == true && mounted) {
      _loadSites();
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

    bool success = false;
    String? errorMessage;
    
    try {
      // Check if site can be deleted
      final canDelete = await _databaseService.canDeleteSite(site.id!);
      if (!canDelete) {
        errorMessage = 'Cannot delete site - it is used in flight records';
      } else {
        LoggingService.debug('ManageSitesScreen: Deleting site ${site.id}');
        await _databaseService.deleteSite(site.id!);
        success = true;
        LoggingService.info('ManageSitesScreen: Deleted site ${site.id}');
        await _loadSites(); // Reload the list
      }
    } catch (e) {
      LoggingService.error('ManageSitesScreen: Failed to delete site', e);
      errorMessage = 'Failed to delete site: $e';
    }
    
    if (mounted) {
      if (success) {
        UiUtils.showSuccessMessage(context, 'Site "${site.name}" deleted');
      } else {
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditSiteScreen(
          initialCoordinates: (latitude: site.latitude, longitude: site.longitude),
        ),
      ),
    );

    // Always refresh the site list when returning from EditSiteScreen
    // This ensures newly created sites (or merged/deleted sites) are reflected
    if (mounted) {
      await _loadSites();
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
                _filterSites(_sites); // Re-apply sort and grouping
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(
                      Icons.text_fields,
                      color: _sortBy == 'name' ? Theme.of(context).colorScheme.primary : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sort by Name',
                      style: TextStyle(
                        fontWeight: _sortBy == 'name' ? FontWeight.bold : null,
                        color: _sortBy == 'name' ? Theme.of(context).colorScheme.primary : null,
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
                      color: _sortBy == 'country' ? Theme.of(context).colorScheme.primary : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Group by Country',
                      style: TextStyle(
                        fontWeight: _sortBy == 'country' ? FontWeight.bold : null,
                        color: _sortBy == 'country' ? Theme.of(context).colorScheme.primary : null,
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
                      color: _sortBy == 'date' ? Theme.of(context).colorScheme.primary : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sort by Date Added',
                      style: TextStyle(
                        fontWeight: _sortBy == 'date' ? FontWeight.bold : null,
                        color: _sortBy == 'date' ? Theme.of(context).colorScheme.primary : null,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'flights',
                child: Row(
                  children: [
                    Icon(
                      Icons.flight_takeoff,
                      color: _sortBy == 'flights' ? Theme.of(context).colorScheme.primary : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sort by Flight Count',
                      style: TextStyle(
                        fontWeight: _sortBy == 'flights' ? FontWeight.bold : null,
                        color: _sortBy == 'flights' ? Theme.of(context).colorScheme.primary : null,
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
          : _errorMessage != null
              ? Center(
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
                        _errorMessage!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => _errorMessage = null);
                          _loadSites();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _sites.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.location_off,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No sites found',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sites will appear here after importing flights',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _filteredSites.isEmpty && _sites.isNotEmpty
                      ? Center(
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
                        )
                      : Column(
                          children: [
                            // Summary header  
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.only(top: 16, bottom: 16),
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewSite,
        tooltip: 'Add Site',
        child: const Icon(Icons.add),
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
        onTap: onEdit,
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
                Expanded(
                  child: Row(
                    children: [
                      if (site.country != null) ...[
                        Flexible(
                          child: Text(
                            site.country!,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(' • ', style: TextStyle(color: Colors.grey[600])),
                      ]
                      else ...[
                        Flexible(
                          child: Text(
                            'Unknown Country',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
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

