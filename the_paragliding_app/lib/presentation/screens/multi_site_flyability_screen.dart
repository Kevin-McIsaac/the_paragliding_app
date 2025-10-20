import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/wind_forecast.dart';
import '../../services/database_service.dart';
import '../../services/pge_sites_database_service.dart';
import '../../services/location_service.dart';
import '../../services/weather_service.dart';
import '../../services/logging_service.dart';
import '../../utils/preferences_helper.dart';
import '../widgets/multi_site_flyability_table.dart';
import '../widgets/week_summary_table.dart';

enum SiteSelectionMode {
  favorites,
  nearHere,
  nearSite,
}

extension SiteSelectionModeExtension on SiteSelectionMode {
  String get displayName {
    switch (this) {
      case SiteSelectionMode.favorites:
        return 'Favorites';
      case SiteSelectionMode.nearHere:
        return 'Near Here';
      case SiteSelectionMode.nearSite:
        return 'Near Site';
    }
  }

  IconData get icon {
    switch (this) {
      case SiteSelectionMode.favorites:
        return Icons.favorite;
      case SiteSelectionMode.nearHere:
        return Icons.my_location;
      case SiteSelectionMode.nearSite:
        return Icons.place;
    }
  }
}

class MultiSiteFlyabilityScreen extends StatefulWidget {
  const MultiSiteFlyabilityScreen({super.key});

  @override
  State<MultiSiteFlyabilityScreen> createState() => _MultiSiteFlyabilityScreenState();
}

class _MultiSiteFlyabilityScreenState extends State<MultiSiteFlyabilityScreen> with SingleTickerProviderStateMixin {
  // Selection mode and filters
  SiteSelectionMode _selectionMode = SiteSelectionMode.nearHere;
  int _distanceKm = 50; // 10, 50, or 100
  int _siteLimit = 10; // 10, 20, or 50
  ParaglidingSite? _selectedReferenceSite;

  // Site search state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<ParaglidingSite> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  // Data state
  List<ParaglidingSite> _sites = [];
  Map<String, WindForecast> _forecasts = {}; // Site key -> WindForecast
  bool _isLoading = false;
  String? _errorMessage;
  double _maxWindSpeed = 25.0;
  double _maxWindGusts = 30.0;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _loadPreferences();
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      _maxWindSpeed = await PreferencesHelper.getMaxWindSpeed();
      _maxWindGusts = await PreferencesHelper.getMaxWindGusts();

      final prefs = await SharedPreferences.getInstance();
      final modeString = prefs.getString('flyability_selection_mode') ?? 'nearHere';
      final distanceKm = prefs.getInt('flyability_distance_km') ?? 50;
      final siteLimit = prefs.getInt('flyability_site_limit') ?? 10;

      // Map saved string to enum
      SiteSelectionMode mode;
      switch (modeString) {
        case 'favorites':
          mode = SiteSelectionMode.favorites;
          break;
        case 'nearHere':
          mode = SiteSelectionMode.nearHere;
          break;
        case 'nearSite':
          mode = SiteSelectionMode.nearSite;
          break;
        default:
          mode = SiteSelectionMode.nearHere;
      }

      if (mounted) {
        setState(() {
          _selectionMode = mode;
          _distanceKm = distanceKm;
          _siteLimit = siteLimit;
        });
      }
    } catch (e) {
      LoggingService.error('Failed to load preferences', e);
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('flyability_selection_mode', _selectionMode.name);
      await prefs.setInt('flyability_distance_km', _distanceKm);
      await prefs.setInt('flyability_site_limit', _siteLimit);
    } catch (e) {
      LoggingService.error('Failed to save preferences', e);
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load sites based on selection mode
      final sites = await _loadSites();

      if (sites.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = _getEmptyMessage();
        });
        return;
      }

      // Fetch wind forecasts for all sites
      final forecasts = await _fetchWindForecasts(sites);

      if (mounted) {
        setState(() {
          _sites = sites;
          _forecasts = forecasts;
          _isLoading = false;
        });
      }

      LoggingService.structured('MULTI_SITE_FLYABILITY_LOADED', {
        'mode': _selectionMode.name,
        'distance_km': _distanceKm,
        'site_limit': _siteLimit,
        'sites_count': sites.length,
        'forecasts_count': forecasts.length,
        'has_reference_site': _selectedReferenceSite != null,
      });
    } catch (e, stackTrace) {
      LoggingService.error('Failed to load flyability data', e, stackTrace);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load data: $e';
        });
      }
    }
  }

  String _getEmptyMessage() {
    switch (_selectionMode) {
      case SiteSelectionMode.favorites:
        return 'No favorite sites found. Add some favorites first!';
      case SiteSelectionMode.nearHere:
        return 'No sites found within ${_distanceKm}km';
      case SiteSelectionMode.nearSite:
        return _selectedReferenceSite == null
            ? 'Please search and select a reference site'
            : 'No sites found within ${_distanceKm}km of ${_selectedReferenceSite!.name}';
    }
  }

  Future<List<ParaglidingSite>> _loadSites() async {
    if (_selectionMode == SiteSelectionMode.favorites) {
      // Get favorites from both databases
      final localFavorites = await DatabaseService.instance.getFavoriteSites();
      final pgeFavorites = await PgeSitesDatabaseService.instance.getFavoriteSites();

      return [...pgeFavorites, ...localFavorites];
    } else if (_selectionMode == SiteSelectionMode.nearHere) {
      // Get sites near current location
      return _loadSitesNearPosition(await _getCurrentPosition());
    } else {
      // Near Site mode
      if (_selectedReferenceSite == null) {
        return [];
      }
      // Get sites near the selected reference site
      return _loadSitesNearPosition(
        Position(
          latitude: _selectedReferenceSite!.latitude,
          longitude: _selectedReferenceSite!.longitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        ),
      );
    }
  }

  Future<Position> _getCurrentPosition() async {
    final position = await LocationService.instance.getCurrentPosition();

    if (position == null) {
      throw Exception('Unable to get current location');
    }

    return position;
  }

  Future<List<ParaglidingSite>> _loadSitesNearPosition(Position position) async {
    // Convert distance to degrees (approximate: 1 degree ≈ 111km)
    final tolerance = _distanceKm / 111.0;

    // Get sites from PGE database within radius
    final sites = await PgeSitesDatabaseService.instance.getSitesInBounds(
      north: position.latitude + tolerance,
      south: position.latitude - tolerance,
      east: position.longitude + tolerance,
      west: position.longitude - tolerance,
    );

    // Filter by actual distance and sort
    final sitesWithDistance = sites.map((site) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        site.latitude,
        site.longitude,
      );
      return (site, distance);
    }).where((tuple) => tuple.$2 <= _distanceKm * 1000) // Filter to exact distance
        .toList();

    // Sort by distance
    sitesWithDistance.sort((a, b) => a.$2.compareTo(b.$2));

    // Take only the requested limit
    return sitesWithDistance
        .take(_siteLimit)
        .map((tuple) => tuple.$1)
        .toList();
  }

  Future<Map<String, WindForecast>> _fetchWindForecasts(List<ParaglidingSite> sites) async {
    final forecasts = <String, WindForecast>{};

    for (final site in sites) {
      try {
        // First try to get from cache
        var forecast = await WeatherService.instance.getCachedForecast(
          site.latitude,
          site.longitude,
        );

        // If not cached, fetch it
        if (forecast == null) {
          // Use getWindData which will fetch and cache the forecast
          final windData = await WeatherService.instance.getWindData(
            site.latitude,
            site.longitude,
            DateTime.now(),
          );

          // Now get the cached forecast that was just created
          if (windData != null) {
            forecast = await WeatherService.instance.getCachedForecast(
              site.latitude,
              site.longitude,
            );
          }
        }

        if (forecast != null) {
          final siteKey = '${site.latitude.toStringAsFixed(4)}_${site.longitude.toStringAsFixed(4)}';
          forecasts[siteKey] = forecast;
        }
      } catch (e) {
        LoggingService.error('Failed to fetch forecast for ${site.name}', e);
      }
    }

    return forecasts;
  }

  Map<String, List<WindData?>> _getWindDataForDay(int dayIndex) {
    final result = <String, List<WindData?>>{};
    final now = DateTime.now();

    for (final site in _sites) {
      final siteKey = '${site.latitude.toStringAsFixed(4)}_${site.longitude.toStringAsFixed(4)}';
      final forecast = _forecasts[siteKey];

      if (forecast == null) {
        result[siteKey] = List.filled(13, null);
        continue;
      }

      final windDataList = <WindData?>[];
      for (int hour = 7; hour <= 19; hour++) {
        final dateTime = now.add(Duration(days: dayIndex))
            .copyWith(hour: hour, minute: 0, second: 0, millisecond: 0, microsecond: 0);

        final windData = forecast.getAtTime(dateTime);
        windDataList.add(windData);
      }

      result[siteKey] = windDataList;
    }

    return result;
  }

  Map<int, Map<String, List<WindData?>>> _prepareWeekData() {
    final weekData = <int, Map<String, List<WindData?>>>{};
    for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
      weekData[dayIndex] = _getWindDataForDay(dayIndex);
    }
    return weekData;
  }

  void _navigateToDay(int dayIndex) {
    _tabController.animateTo(dayIndex + 1); // +1 because tab 0 is "Week"
  }

  void _onSelectionModeChanged(SiteSelectionMode? mode) {
    if (mode != null && mode != _selectionMode) {
      setState(() {
        _selectionMode = mode;
        // Clear reference site when switching away from "Near Site" mode
        if (mode != SiteSelectionMode.nearSite) {
          _selectedReferenceSite = null;
        }
      });

      _savePreferences();
      _loadData();
    }
  }

  void _onDistanceChanged(int? distance) {
    if (distance != null && distance != _distanceKm) {
      setState(() {
        _distanceKm = distance;
      });

      _savePreferences();
      _loadData();
    }
  }

  void _onLimitChanged(int? limit) {
    if (limit != null && limit != _siteLimit) {
      setState(() {
        _siteLimit = limit;
      });

      _savePreferences();
      _loadData();
    }
  }

  // Site search functionality
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();

    setState(() {
      _searchQuery = query.trim();
    });

    if (_searchQuery.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    if (_searchQuery.length < 2) {
      return; // Don't search for very short queries
    }

    // Debounce the search
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isSearching = true);

      try {
        final results = await PgeSitesDatabaseService.instance.searchSitesByName(
          query: _searchQuery,
        );

        if (mounted) {
          setState(() {
            _searchResults = results.take(15).toList();
            _isSearching = false;
          });
        }
      } catch (e) {
        LoggingService.error('Site search failed', e);
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
      }
    });
  }

  void _onSiteSelected(ParaglidingSite site) {
    LoggingService.action('MultiSiteFlyability', 'reference_site_selected', {
      'site_name': site.name,
      'country': site.country,
    });

    setState(() {
      _selectedReferenceSite = site;
      _searchController.clear();
      _searchQuery = '';
      _searchResults = [];
    });

    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flyability Forecast'),
      ),
      body: Column(
        children: [
          // Filter controls
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mode selection (3 buttons)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<SiteSelectionMode>(
                    segments: SiteSelectionMode.values.map((mode) {
                      return ButtonSegment<SiteSelectionMode>(
                        value: mode,
                        label: Text(mode.displayName),
                        icon: Icon(mode.icon),
                      );
                    }).toList(),
                    selected: {_selectionMode},
                    onSelectionChanged: (Set<SiteSelectionMode> newSelection) {
                      _onSelectionModeChanged(newSelection.first);
                    },
                  ),
                ),

                // Distance and Limit filters (only for nearHere and nearSite)
                if (_selectionMode != SiteSelectionMode.favorites) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Distance dropdown
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Distance',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<int>(
                              value: _distanceKm,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 10, child: Text('10 km')),
                                DropdownMenuItem(value: 50, child: Text('50 km')),
                                DropdownMenuItem(value: 100, child: Text('100 km')),
                              ],
                              onChanged: _onDistanceChanged,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Limit dropdown
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Limit',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<int>(
                              value: _siteLimit,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 10, child: Text('10 sites')),
                                DropdownMenuItem(value: 20, child: Text('20 sites')),
                                DropdownMenuItem(value: 50, child: Text('50 sites')),
                              ],
                              onChanged: _onLimitChanged,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                // Site search field (only for nearSite mode)
                if (_selectionMode == SiteSelectionMode.nearSite) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _selectedReferenceSite == null
                          ? 'Search for a reference site...'
                          : 'Reference: ${_selectedReferenceSite!.name}',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _selectedReferenceSite != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setState(() {
                                  _selectedReferenceSite = null;
                                  _searchController.clear();
                                  _searchQuery = '';
                                  _searchResults = [];
                                });
                                _loadData();
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),

                  // Search results dropdown
                  if (_searchQuery.isNotEmpty && (_isSearching || _searchResults.isNotEmpty))
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Searching sites...'),
                                ],
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final site = _searchResults[index];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    child: Text(
                                      site.country?.toUpperCase().substring(0, 2) ?? '??',
                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(
                                    site.name,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    site.country ?? 'Unknown',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onTap: () => _onSiteSelected(site),
                                );
                              },
                            ),
                    ),
                ],
              ],
            ),
          ),

          // Content with tabs
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _errorMessage!,
                                style: const TextStyle(fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadData,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _sites.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                _getEmptyMessage(),
                                style: const TextStyle(fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              // Tab Bar
                              TabBar(
                                controller: _tabController,
                                isScrollable: true,
                                tabs: [
                                  const Tab(text: 'Week'),
                                  ...List.generate(7, (index) {
                                    final date = DateTime.now().add(Duration(days: index));
                                    return Tab(
                                      text: DateFormat('EEE d').format(date),
                                    );
                                  }),
                                ],
                              ),
                              // Tab Views
                              Expanded(
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    // Week summary tab
                                    SingleChildScrollView(
                                      padding: const EdgeInsets.all(16.0),
                                      child: WeekSummaryTable(
                                        sites: _sites,
                                        windDataByDay: _prepareWeekData(),
                                        maxWindSpeed: _maxWindSpeed,
                                        maxWindGusts: _maxWindGusts,
                                        onDayTap: _navigateToDay,
                                      ),
                                    ),
                                    // Daily detail tabs
                                    ...List.generate(7, (dayIndex) {
                                      final date = DateTime.now().add(Duration(days: dayIndex));

                                      return SingleChildScrollView(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 16.0),
                                              child: Text(
                                                DateFormat('EEEE, MMMM d').format(date),
                                                style: Theme.of(context).textTheme.titleLarge,
                                              ),
                                            ),
                                            SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: MultiSiteFlyabilityTable(
                                                sites: _sites,
                                                windDataBySite: _getWindDataForDay(dayIndex),
                                                date: date,
                                                maxWindSpeed: _maxWindSpeed,
                                                maxWindGusts: _maxWindGusts,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}
