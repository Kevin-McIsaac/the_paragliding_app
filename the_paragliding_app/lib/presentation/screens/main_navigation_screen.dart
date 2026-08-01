import 'package:flutter/material.dart';
import 'flight_list_screen.dart';
import 'nearby_sites_screen.dart';
import 'statistics_screen.dart';
import 'multi_site_flyability_screen.dart';
import '../../services/logging_service.dart';
import '../../utils/preferences_helper.dart';

/// Main navigation screen with bottom navigation bar.
///
/// Manages four primary views:
/// - Flight Log
/// - Nearby Sites
/// - Forecast
/// - Statistics
///
/// Uses IndexedStack to preserve state when switching tabs. Tabs are built the
/// first time they are shown - each one loads data in initState, so building
/// them all up front would run four screens' worth of work at launch.
class MainNavigationScreen extends StatefulWidget {
  /// Tab to open on launch. Resolved by the splash screen so this screen never
  /// builds a default tab and then throws it away.
  final int initialIndex;

  const MainNavigationScreen({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _selectedIndex = widget.initialIndex;

  /// Tabs that have been shown at least once - IndexedStack keeps them alive
  late final Set<int> _builtTabs = {widget.initialIndex};

  // Type-safe GlobalKeys using the public state classes
  // This allows calling public methods like refreshData() without dynamic cast
  final GlobalKey<FlightListScreenState> _flightListKey = GlobalKey();
  final GlobalKey<StatisticsScreenState> _statisticsKey = GlobalKey();
  final GlobalKey<NearbySitesScreenState> _nearbySitesKey = GlobalKey();
  final GlobalKey<MultiSiteFlyabilityScreenState> _forecastKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    LoggingService.info('MainNavigationScreen: Initialized with bottom navigation');
  }

  /// Refresh flight list data (e.g., after adding a new flight).
  ///
  /// This is now completely type-safe:
  /// ```dart
  /// // ✅ Type-safe - compiler checks method exists
  /// await _flightListKey.currentState?.refreshData();
  ///
  /// // ❌ NEVER do this - unsafe and fragile
  /// // (_flightListKey.currentState as dynamic)?._loadData();
  /// ```
  ///
  /// Note: For new code, prefer callback pattern over GlobalKey when possible:
  /// ```dart
  /// // Preferred pattern for looser coupling
  /// FlightListScreen(onDataChanged: _handleDataChanged)
  /// ```
  Future<void> _refreshFlightList() async {
    // Type-safe call - compile-time checked, IDE autocomplete works
    await _flightListKey.currentState?.refreshData();
  }

  /// Refresh statistics data (e.g., after database changes).
  ///
  /// Type-safe call using the public StatisticsScreenState class.
  Future<void> _refreshStatistics() async {
    await _statisticsKey.currentState?.refreshData();
  }

  /// Refresh nearby sites data (e.g., after database changes or new airspace data).
  ///
  /// Type-safe call using the public NearbySitesScreenState class.
  /// This reloads both sites and airspace from the database.
  Future<void> _refreshNearbySites() async {
    await _nearbySitesKey.currentState?.refreshData();
  }

  /// Handle data changes from any screen's AppMenuButton.
  ///
  /// This is the centralized callback passed to all child screens.
  /// It refreshes all screens that may be affected by database changes:
  /// - FlightList: Shows flight records
  /// - Statistics: Shows aggregated flight data
  /// - NearbySites: Shows sites with flight status and airspace data
  Future<void> _handleDataChanged() async {
    // Refresh all three navigation screens to keep them in sync
    await Future.wait([
      _refreshFlightList(),
      _refreshStatistics(),
      _refreshNearbySites(),
    ]);
  }

  /// Public method to refresh all tabs.
  ///
  /// This method can be called by child screens (via callback) when they
  /// modify data that affects all three navigation tabs. For example:
  /// - IGC Import adds new flights → refreshes all tabs
  /// - Data Management deletes data → refreshes all tabs
  /// - Wing/Site Management modifies data → refreshes all tabs
  Future<void> refreshAllTabs() async {
    await _handleDataChanged();
  }

  void _onDestinationSelected(int index) {
    // Capture old index before updating state
    final oldIndex = _selectedIndex;

    setState(() {
      _selectedIndex = index;
      _builtTabs.add(index);
    });

    // Save the selected index to preferences
    PreferencesHelper.setLastNavigationIndex(index);

    // Refresh Forecast tab data when switching to it (index 1)
    if (index == 1 && oldIndex != 1) {
      _forecastKey.currentState?.refreshData();
    }

    // Log navigation for debugging
    final destinations = ['Sites', 'Forecast', 'Log Book', 'Statistics'];
    LoggingService.action('Navigation', 'bottom_nav_tap', {
      'destination': destinations[index],
      'from_index': oldIndex,
      'to_index': index,
    });
  }

  /// Build a tab only once it has been shown - unvisited tabs stay empty so
  /// their initState (and its database/network work) never runs
  Widget _buildTab(int index, Widget Function() builder) {
    return _builtTabs.contains(index) ? builder() : const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex;

    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: [
          _buildTab(0, () => NearbySitesScreen(
            key: _nearbySitesKey,
            onDataChanged: _handleDataChanged,
            onRefreshAllTabs: refreshAllTabs,
          )),
          _buildTab(1, () => MultiSiteFlyabilityScreen(key: _forecastKey)),
          _buildTab(2, () => FlightListScreen(
            key: _flightListKey,
            onDataChanged: _handleDataChanged,
            onRefreshAllTabs: refreshAllTabs,
          )),
          _buildTab(3, () => StatisticsScreen(
            key: _statisticsKey,
            onDataChanged: _handleDataChanged,
            onRefreshAllTabs: refreshAllTabs,
          )),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: 'Sites',
            tooltip: 'Find nearby flying sites',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Forecast',
            tooltip: 'View 7-day flyability forecast',
          ),
          NavigationDestination(
            icon: Icon(Icons.flight),
            selectedIcon: Icon(Icons.flight),
            label: 'Log Book',
            tooltip: 'View flight log book',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Statistics',
            tooltip: 'View flight statistics',
          ),
        ],
      ),
    );
  }
}
