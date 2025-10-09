import 'package:flutter/material.dart';
import 'flight_list_screen.dart';
import 'nearby_sites_screen.dart';
import 'statistics_screen.dart';
import 'add_flight_screen.dart';
import '../../services/logging_service.dart';

/// Main navigation screen with bottom navigation bar.
///
/// Manages three primary views:
/// - Flight Log (with Add Flight FAB)
/// - Nearby Sites (no FAB)
/// - Statistics (no FAB)
///
/// Uses IndexedStack to preserve state when switching tabs.
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    LoggingService.info('MainNavigationScreen: Initialized with bottom navigation');
  }

  void _onDestinationSelected(int index) {
    // Capture old index before updating state
    final oldIndex = _selectedIndex;

    setState(() {
      _selectedIndex = index;
    });

    // Log navigation for debugging
    final destinations = ['Log Book', 'Nearby Sites', 'Statistics'];
    LoggingService.action('Navigation', 'bottom_nav_tap', {
      'destination': destinations[index],
      'from_index': oldIndex,
      'to_index': index,
    });
  }

  Widget? _buildFloatingActionButton() {
    // Only show FAB on Flight Log tab (index 0)
    if (_selectedIndex == 0) {
      return FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => const AddFlightScreen(),
            ),
          );

          // Notify FlightListScreen to reload if needed
          if (result == true && mounted) {
            // The FlightListScreen will handle its own reload via setState
            LoggingService.info('MainNavigationScreen: Flight added, triggering reload');
          }
        },
        tooltip: 'Add Flight',
        child: const Icon(Icons.add),
      );
    }

    // No FAB for other tabs
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          FlightListScreen(showInNavigation: true),
          NearbySitesScreen(),
          StatisticsScreen(),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.flight),
            selectedIcon: Icon(Icons.flight),
            label: 'Log Book',
            tooltip: 'View flight log book',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: 'Sites',
            tooltip: 'Find nearby flying sites',
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
