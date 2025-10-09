import 'package:flutter/material.dart';
import '../../data/models/site.dart';

/// Result wrapper to distinguish between cancellation and selection
class SiteSelectionResult {
  final Site? selectedSite;
  
  const SiteSelectionResult(this.selectedSite);
}

/// Custom dialog for site selection with search functionality and country grouping
class SiteSelectionDialog extends StatefulWidget {
  final List<Site> sites;
  final Site? currentSite;
  final String title;

  const SiteSelectionDialog({
    super.key,
    required this.sites,
    required this.currentSite,
    required this.title,
  });

  @override
  State<SiteSelectionDialog> createState() => _SiteSelectionDialogState();
}

class _SiteSelectionDialogState extends State<SiteSelectionDialog> {
  late List<Site> _filteredSites;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Site? _selectedSite;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredSites = widget.sites;
    _selectedSite = widget.currentSite;
    
    // Sort sites alphabetically for easier browsing
    _filteredSites.sort((a, b) => a.name.compareTo(b.name));
    
    // Scroll to selected item after the widget is built
    if (_selectedSite != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelectedSite();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  void _scrollToSelectedSite() {
    if (_selectedSite == null || !_scrollController.hasClients) return;
    
    // Find the index of the selected site
    final index = _filteredSites.indexOf(_selectedSite!);
    if (index == -1) return;
    
    // Account for "No site" option and divider (2 items before the list)
    // Estimate item height: ListTile with dense:true is approximately 56 pixels
    // Plus we need to account for country headers when not searching
    double scrollPosition = 0;
    
    if (_searchQuery.isEmpty) {
      // When showing grouped view, calculate position including headers
      final Map<String, List<Site>> countryGroupedSites = {};
      for (final site in _filteredSites) {
        final country = site.country ?? 'Unknown Country';
        countryGroupedSites.putIfAbsent(country, () => []).add(site);
      }
      
      final sortedCountries = countryGroupedSites.keys.toList()..sort((a, b) {
        if (a == 'Unknown Country' && b != 'Unknown Country') return 1;
        if (a != 'Unknown Country' && b == 'Unknown Country') return -1;
        return a.compareTo(b);
      });
      
      for (final country in sortedCountries) {
        countryGroupedSites[country]!.sort((a, b) => a.name.compareTo(b.name));
      }
      
      // Calculate position
      int itemsBeforeSelected = 0;
      bool found = false;
      for (final country in sortedCountries) {
        itemsBeforeSelected++; // Country header
        for (final site in countryGroupedSites[country]!) {
          if (site == _selectedSite) {
            found = true;
            break;
          }
          itemsBeforeSelected++;
        }
        if (found) break;
      }
      
      // Account for "No site" option (56px) and divider (1px)
      scrollPosition = 57 + (itemsBeforeSelected * 56.0);
    } else {
      // Flat list when searching
      // Account for "No site" option (56px) and divider (1px)
      scrollPosition = 57 + (index * 56.0);
    }
    
    // Ensure we don't scroll beyond the maximum extent
    if (_scrollController.position.maxScrollExtent > 0) {
      scrollPosition = scrollPosition.clamp(0, _scrollController.position.maxScrollExtent);
    }
    
    // Animate to the position
    _scrollController.animateTo(
      scrollPosition,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _filterSites(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredSites = List.from(widget.sites)
          ..sort((a, b) => a.name.compareTo(b.name));
      } else {
        _filteredSites = widget.sites
            .where((site) => 
                site.name.toLowerCase().contains(_searchQuery) ||
                (site.country?.toLowerCase().contains(_searchQuery) ?? false))
            .toList()
          ..sort((a, b) {
            // Prioritize sites that start with the search query
            final aStarts = a.name.toLowerCase().startsWith(_searchQuery);
            final bStarts = b.name.toLowerCase().startsWith(_searchQuery);
            if (aStarts && !bStarts) return -1;
            if (!aStarts && bStarts) return 1;
            return a.name.compareTo(b.name);
          });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Group sites by country for better organization
    final Map<String, List<Site>> countryGroupedSites = {};
    for (final site in _filteredSites) {
      final country = site.country ?? 'Unknown Country';
      countryGroupedSites.putIfAbsent(country, () => []).add(site);
    }
    
    // Sort countries alphabetically, but keep "Unknown Country" at the end
    final sortedCountries = countryGroupedSites.keys.toList()..sort((a, b) {
      if (a == 'Unknown Country' && b != 'Unknown Country') return 1;
      if (a != 'Unknown Country' && b == 'Unknown Country') return -1;
      return a.compareTo(b);
    });
    
    // Sort sites within each country
    for (final country in sortedCountries) {
      countryGroupedSites[country]!.sort((a, b) => a.name.compareTo(b.name));
    }

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search sites or countries...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterSites('');
                      },
                    )
                  : null,
            ),
            onChanged: _filterSites,
            autofocus: true,
          ),
          if (_filteredSites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_filteredSites.length} site${_filteredSites.length != 1 ? 's' : ''} found',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400, // Fixed height for better UX
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // No site option
            ListTile(
              title: const Text('No site'),
              leading: Radio<Site?>(
                value: null,
                // ignore: deprecated_member_use
                groupValue: _selectedSite,
                // ignore: deprecated_member_use
                onChanged: (Site? value) {
                  setState(() {
                    _selectedSite = value;
                  });
                },
              ),
              onTap: () {
                setState(() {
                  _selectedSite = null;
                });
              },
              dense: true,
            ),
            const Divider(),
            // Site list
            Expanded(
              child: _filteredSites.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, 
                               size: 48, 
                               color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No sites match your search',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _searchQuery.isEmpty 
                          ? sortedCountries.fold<int>(0, (count, country) => 
                              count + 1 + countryGroupedSites[country]!.length) // Country header + sites
                          : _filteredSites.length,
                      itemBuilder: (context, index) {
                        if (_searchQuery.isNotEmpty) {
                          // When searching, show flat list
                          final site = _filteredSites[index];
                          return ListTile(
                            title: Text(
                              site.name,
                              style: site.name == 'Unknown'
                                  ? TextStyle(fontStyle: FontStyle.italic,
                                            color: Colors.grey[600])
                                  : null,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (site.altitude != null)
                                  Text('${site.altitude!.toInt()} m'),
                                if (site.country != null)
                                  Text(
                                    site.country!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                            leading: Radio<Site>(
                              value: site,
                              // ignore: deprecated_member_use
                              groupValue: _selectedSite,
                              // ignore: deprecated_member_use
                              onChanged: (Site? value) {
                                setState(() {
                                  _selectedSite = value;
                                });
                              },
                            ),
                            onTap: () {
                              setState(() {
                                _selectedSite = site;
                              });
                            },
                            dense: true,
                          );
                        } else {
                          // When not searching, show hierarchical structure
                          return _buildHierarchicalItem(index, countryGroupedSites);
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // Return null for cancellation
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(SiteSelectionResult(_selectedSite)),
          child: const Text('Select'),
        ),
      ],
    );
  }

  Widget _buildHierarchicalItem(int index, Map<String, List<Site>> countryGroupedSites) {
    // Calculate which item we're showing based on the hierarchical structure
    int currentIndex = 0;
    
    for (final country in countryGroupedSites.keys.toList()..sort((a, b) {
      if (a == 'Unknown Country' && b != 'Unknown Country') return 1;
      if (a != 'Unknown Country' && b == 'Unknown Country') return -1;
      return a.compareTo(b);
    })) {
      if (currentIndex == index) {
        // Country header
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          margin: const EdgeInsets.only(top: 8),
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          child: Text(
            country,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      }
      currentIndex++;
      
      final sites = countryGroupedSites[country]!;
      for (final site in sites) {
        if (currentIndex == index) {
          // Site item
          return Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ListTile(
              title: Text(
                site.name,
                style: site.name == 'Unknown'
                    ? TextStyle(fontStyle: FontStyle.italic,
                              color: Colors.grey[600])
                    : null,
              ),
              subtitle: site.altitude != null
                  ? Text('${site.altitude!.toInt()} m')
                  : null,
              leading: Radio<Site>(
                value: site,
                // ignore: deprecated_member_use
                groupValue: _selectedSite,
                // ignore: deprecated_member_use
                onChanged: (Site? value) {
                  setState(() {
                    _selectedSite = value;
                  });
                },
              ),
              onTap: () {
                setState(() {
                  _selectedSite = site;
                });
              },
              dense: true,
            ),
          );
        }
        currentIndex++;
      }
    }
    
    // Fallback (shouldn't reach here)
    return const SizedBox.shrink();
  }
}