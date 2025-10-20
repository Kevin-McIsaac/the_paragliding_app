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
  nearest3,
  nearest5,
  nearest7,
  nearest10,
}

extension SiteSelectionModeExtension on SiteSelectionMode {
  bool get isNearest => this != SiteSelectionMode.favorites;

  int get nearestCount {
    switch (this) {
      case SiteSelectionMode.nearest3:
        return 3;
      case SiteSelectionMode.nearest5:
        return 5;
      case SiteSelectionMode.nearest7:
        return 7;
      case SiteSelectionMode.nearest10:
        return 10;
      default:
        return 5;
    }
  }
}

class MultiSiteFlyabilityScreen extends StatefulWidget {
  const MultiSiteFlyabilityScreen({super.key});

  @override
  State<MultiSiteFlyabilityScreen> createState() => _MultiSiteFlyabilityScreenState();
}

class _MultiSiteFlyabilityScreenState extends State<MultiSiteFlyabilityScreen> with SingleTickerProviderStateMixin {
  SiteSelectionMode _selectionMode = SiteSelectionMode.nearest5;
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
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      _maxWindSpeed = await PreferencesHelper.getMaxWindSpeed();
      _maxWindGusts = await PreferencesHelper.getMaxWindGusts();

      final prefs = await SharedPreferences.getInstance();
      final modeString = prefs.getString('flyability_selection_mode') ?? 'nearest5';

      // Map saved string to enum
      SiteSelectionMode mode;
      switch (modeString) {
        case 'favorites':
          mode = SiteSelectionMode.favorites;
          break;
        case 'nearest3':
          mode = SiteSelectionMode.nearest3;
          break;
        case 'nearest5':
          mode = SiteSelectionMode.nearest5;
          break;
        case 'nearest7':
          mode = SiteSelectionMode.nearest7;
          break;
        case 'nearest10':
          mode = SiteSelectionMode.nearest10;
          break;
        default:
          mode = SiteSelectionMode.nearest5;
      }

      if (mounted) {
        setState(() {
          _selectionMode = mode;
        });
      }
    } catch (e) {
      LoggingService.error('Failed to load preferences', e);
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
          _errorMessage = _selectionMode == SiteSelectionMode.favorites
              ? 'No favorite sites found. Add some favorites first!'
              : 'No nearby sites found';
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
        'sites_count': sites.length,
        'forecasts_count': forecasts.length,
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

  Future<List<ParaglidingSite>> _loadSites() async {
    if (_selectionMode == SiteSelectionMode.favorites) {
      // Get favorites from both databases
      final localFavorites = await DatabaseService.instance.getFavoriteSites();
      final pgeFavorites = await PgeSitesDatabaseService.instance.getFavoriteSites();

      return [...pgeFavorites, ...localFavorites];
    } else {
      // Get N nearest sites from current location
      final position = await LocationService.instance.getCurrentPosition();

      if (position == null) {
        // Fallback to a default location or show error
        throw Exception('Unable to get current location');
      }

      // Get sites from PGE database within a reasonable radius
      final tolerance = 1.0; // ~111km radius
      final sites = await PgeSitesDatabaseService.instance.getSitesInBounds(
        north: position.latitude + tolerance,
        south: position.latitude - tolerance,
        east: position.longitude + tolerance,
        west: position.longitude - tolerance,
      );

      // Sort by distance and take nearest N
      sites.sort((a, b) {
        final distA = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          a.latitude,
          a.longitude,
        );
        final distB = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          b.latitude,
          b.longitude,
        );
        return distA.compareTo(distB);
      });

      return sites.take(_selectionMode.nearestCount).toList();
    }
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

  void _onSelectionModeChanged(SiteSelectionMode? mode) async {
    if (mode != null && mode != _selectionMode) {
      setState(() {
        _selectionMode = mode;
      });

      // Save preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('flyability_selection_mode', mode.name);

      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flyability Forecast'),
      ),
      body: Column(
        children: [
          // Site selection toggle with integrated count selection
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<SiteSelectionMode>(
                segments: const [
                  ButtonSegment<SiteSelectionMode>(
                    value: SiteSelectionMode.favorites,
                    label: Text('Favorites'),
                    icon: Icon(Icons.favorite),
                  ),
                  ButtonSegment<SiteSelectionMode>(
                    value: SiteSelectionMode.nearest3,
                    label: Text('Nearest: 3'),
                  ),
                  ButtonSegment<SiteSelectionMode>(
                    value: SiteSelectionMode.nearest5,
                    label: Text('Nearest: 5'),
                  ),
                  ButtonSegment<SiteSelectionMode>(
                    value: SiteSelectionMode.nearest7,
                    label: Text('Nearest: 7'),
                  ),
                  ButtonSegment<SiteSelectionMode>(
                    value: SiteSelectionMode.nearest10,
                    label: Text('Nearest: 10'),
                  ),
                ],
                selected: {_selectionMode},
                onSelectionChanged: (Set<SiteSelectionMode> newSelection) {
                  _onSelectionModeChanged(newSelection.first);
                },
              ),
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
                        ? const Center(child: Text('No sites to display'))
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
