import 'package:flutter/material.dart';
import '../../screens/igc_import_screen.dart';
import '../../screens/add_flight_screen.dart';
import '../../screens/wing_management_screen.dart';
import '../../screens/manage_sites_screen.dart';
import '../../screens/data_management_screen.dart';
import '../../screens/preferences_screen.dart';
import '../../screens/about_screen.dart';

/// Shared menu button used across main navigation screens (Log Book, Sites, Statistics).
///
/// Provides access to common actions:
/// - Import IGC
/// - Add Flight
/// - Manage Sites
/// - Manage Wings
/// - Data Management
/// - Preferences
/// - About
class AppMenuButton extends StatelessWidget {
  /// Optional callback to reload data after Import IGC or Add Flight actions.
  /// Used in Log Book screen to refresh flight list.
  final VoidCallback? onDataChanged;

  const AppMenuButton({
    super.key,
    this.onDataChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white70),
      onSelected: (value) async {
        if (value == 'import') {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => const IgcImportScreen(),
            ),
          );

          if (result == true && onDataChanged != null) {
            onDataChanged!();
          }
        } else if (value == 'add_flight') {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => const AddFlightScreen(),
            ),
          );

          if (result == true && onDataChanged != null) {
            onDataChanged!();
          }
        } else if (value == 'wings') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const WingManagementScreen(),
            ),
          );
        } else if (value == 'sites') {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => const ManageSitesScreen(),
            ),
          );
          // Reload data if sites were modified (mainly for Log Book)
          if (result == true && onDataChanged != null) {
            onDataChanged!();
          }
        } else if (value == 'database') {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => const DataManagementScreen(),
            ),
          );

          if (result == true && onDataChanged != null) {
            onDataChanged!();
          }
        } else if (value == 'about') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const AboutScreen(),
            ),
          );
        } else if (value == 'preferences') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const PreferencesScreen(),
            ),
          );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'import',
          child: Row(
            children: [
              Icon(Icons.upload_file),
              SizedBox(width: 8),
              Text('Import IGC'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'add_flight',
          child: Row(
            children: [
              Icon(Icons.add),
              SizedBox(width: 8),
              Text('Add Flight'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'sites',
          child: Row(
            children: [
              Icon(Icons.location_on),
              SizedBox(width: 8),
              Text('Manage Sites'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'wings',
          child: Row(
            children: [
              Icon(Icons.paragliding),
              SizedBox(width: 8),
              Text('Manage Wings'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'database',
          child: Row(
            children: [
              Icon(Icons.storage),
              SizedBox(width: 8),
              Text('Data Management'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'preferences',
          child: Row(
            children: [
              Icon(Icons.settings),
              SizedBox(width: 8),
              Text('Preferences'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'about',
          child: Row(
            children: [
              Icon(Icons.info),
              SizedBox(width: 8),
              Text('About'),
            ],
          ),
        ),
      ],
    );
  }
}
