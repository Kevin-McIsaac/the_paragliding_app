import 'package:flutter/material.dart';
import '../../utils/database_reset_helper.dart';
import '../../services/site_matching_service.dart';

class DatabaseSettingsScreen extends StatefulWidget {
  const DatabaseSettingsScreen({super.key});

  @override
  State<DatabaseSettingsScreen> createState() => _DatabaseSettingsScreenState();
}

class _DatabaseSettingsScreenState extends State<DatabaseSettingsScreen> {
  Map<String, dynamic>? _dbStats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDatabaseStats();
  }

  Future<void> _loadDatabaseStats() async {
    setState(() => _isLoading = true);
    final stats = await DatabaseResetHelper.getDatabaseStats();
    setState(() {
      _dbStats = stats;
      _isLoading = false;
    });
  }

  Future<void> _resetDatabase() async {
    // Show confirmation dialog
    final confirmed = await _showConfirmationDialog(
      'Reset Database',
      'This will permanently delete ALL data including:\n\n'
      '• All flight records\n'
      '• All sites\n' 
      '• All wings\n'
      '• All track log files\n\n'
      'This action cannot be undone.\n\n'
      'Are you sure you want to continue?',
    );

    if (!confirmed) return;

    // Show loading
    _showLoadingDialog('Resetting database...');

    try {
      final result = await DatabaseResetHelper.resetDatabase();
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (result['success']) {
        _showSuccessDialog('Database Reset Complete', result['message']);
        await _loadDatabaseStats(); // Refresh stats
      } else {
        _showErrorDialog('Reset Failed', result['message']);
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog('Error', 'Failed to reset database: $e');
    }
  }

  Future<void> _clearFlights() async {
    final confirmed = await _showConfirmationDialog(
      'Clear All Flights',
      'This will permanently delete all flight records.\n\n'
      'Sites and wings will be preserved.\n\n'
      'This action cannot be undone.',
    );

    if (!confirmed) return;

    _showLoadingDialog('Clearing flights...');

    try {
      final result = await DatabaseResetHelper.clearAllFlights();
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (result['success']) {
        _showSuccessDialog('Flights Cleared', result['message']);
        await _loadDatabaseStats(); // Refresh stats
      } else {
        _showErrorDialog('Clear Failed', result['message']);
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog('Error', 'Failed to clear flights: $e');
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
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete All Data'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(String title, String message) {
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

  Future<void> _testApiConnection() async {
    // Show loading
    _showLoadingDialog('Testing ParaglidingEarth API connection...');

    try {
      final siteService = SiteMatchingService.instance;
      final isConnected = await siteService.testApiConnection();
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      // Show result
      if (mounted) {
        if (isConnected) {
          _showSuccessDialog(
            'API Connection Test',
            'Successfully connected to ParaglidingEarth.com API!\n\n'
            'Real-time site lookups are working.',
          );
        } else {
          _showErrorDialog(
            'API Connection Test',  
            'Failed to connect to ParaglidingEarth.com API.\n\n'
            'The app will use the local database as fallback.',
          );
        }
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      // Show error
      if (mounted) {
        _showErrorDialog('API Test Error', 'Error testing API connection: $e');
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.only(top: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Database Statistics
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Database Statistics',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          if (_dbStats != null) ...[
                            _buildStatRow('Version', '${_dbStats!['version'] ?? 'Unknown'}'),
                            _buildStatRow('Flights', '${_dbStats!['flights'] ?? 0}'),
                            _buildStatRow('Sites', '${_dbStats!['sites'] ?? 0}'),
                            _buildStatRow('Wings', '${_dbStats!['wings'] ?? 0}'),
                            _buildStatRow('Total Records', '${_dbStats!['total_records'] ?? 0}'),
                            _buildStatRow('Database Size', '${_dbStats!['size_kb'] ?? '0'}KB'),
                            const SizedBox(height: 8),
                            Text(
                              'Path: ${_dbStats!['path'] ?? 'Unknown'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Actions
                  const Text(
                    'Database Actions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  // Refresh Stats
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loadDatabaseStats,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Statistics'),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Clear Flights
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (_dbStats?['flights'] ?? 0) > 0 ? _clearFlights : null,
                      icon: const Icon(Icons.flight_takeoff),
                      label: Text('Clear All Flights (${_dbStats?['flights'] ?? 0})'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),

                  // Test API Connection
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _testApiConnection,
                      icon: const Icon(Icons.cloud_sync),
                      label: const Text('Test ParaglidingEarth API'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Danger Zone
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.red.withValues(alpha: 0.1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Danger Zone',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'The following action will permanently delete all data and cannot be undone.',
                          style: TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: (_dbStats?['total_records'] ?? 0) > 0 ? _resetDatabase : null,
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Reset Database'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Help Text
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'About Database Reset',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Database reset completely removes all data and recreates the database with the latest schema. '
                            'This is useful for:\n\n'
                            '• Starting fresh with no data\n'
                            '• Fixing database corruption issues\n'
                            '• Development and testing\n\n'
                            'The database will be recreated with the current version (${_dbStats?['version'] ?? 'Unknown'}) schema.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}