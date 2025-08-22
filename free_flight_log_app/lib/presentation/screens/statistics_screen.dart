import 'package:flutter/material.dart';
import '../../utils/date_time_utils.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';
import 'edit_site_screen.dart';
import '../../data/models/site.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final DatabaseService _databaseService = DatabaseService.instance;
  
  // State variables
  List<Map<String, dynamic>> _yearlyStats = [];
  List<Map<String, dynamic>> _wingStats = [];
  List<Map<String, dynamic>> _siteStats = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _loadAllStatistics();
  }
  
  Future<void> _loadAllStatistics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      LoggingService.debug('StatisticsScreen: Loading all statistics');
      
      // Load all statistics in parallel
      final results = await Future.wait([
        _databaseService.getYearlyStatistics(),
        _databaseService.getWingStatistics(),
        _databaseService.getSiteStatistics(),
      ]);
      
      if (mounted) {
        setState(() {
          _yearlyStats = results[0];
          _wingStats = results[1];
          _siteStats = results[2];
          _isLoading = false;
        });
        
        LoggingService.info('StatisticsScreen: Loaded statistics - '
            '${_yearlyStats.length} years, ${_wingStats.length} wings, ${_siteStats.length} sites');
      }
    } catch (e) {
      LoggingService.error('StatisticsScreen: Failed to load statistics', e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load statistics: $e';
          _isLoading = false;
        });
      }
    }
  }
  
  void _clearError() {
    setState(() {
      _errorMessage = null;
    });
  }
  
  Future<void> _editSite(int siteId) async {
    try {
      LoggingService.debug('StatisticsScreen: Fetching site $siteId for editing');
      
      // Fetch the complete Site object
      final site = await _databaseService.getSite(siteId);
      if (site == null) {
        LoggingService.warning('StatisticsScreen: Site $siteId not found');
        return;
      }
      
      if (!mounted) return;
      
      // Navigate to edit screen
      final updatedSite = await Navigator.of(context).push<Site>(
        MaterialPageRoute(
          builder: (context) => EditSiteScreen(site: site),
        ),
      );
      
      // If site was updated, save changes and refresh statistics
      if (updatedSite != null && mounted) {
        LoggingService.debug('StatisticsScreen: Updating site ${updatedSite.id}');
        await _databaseService.updateSite(updatedSite);
        
        // Refresh statistics to show any changes
        await _loadAllStatistics();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Site "${updatedSite.name}" updated'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      LoggingService.error('StatisticsScreen: Failed to edit site', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to edit site: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Statistics'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ?
 Center(
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
                        'Error loading statistics',
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
                          _clearError();
                          _loadAllStatistics();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _yearlyStats.isEmpty && 
                  _wingStats.isEmpty && 
                  _siteStats.isEmpty
                  ? _buildEmptyState()
                  : SingleChildScrollView(
            padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Yearly Statistics Section
                if (_yearlyStats.isNotEmpty) ...[
                  _buildSectionHeader('Flights by Year', Icons.calendar_today),
                  const SizedBox(height: 8),
                  _buildYearlyStatsTable(_yearlyStats),
                  const SizedBox(height: 24),
                ],
                
                // Wing Statistics Section
                if (_wingStats.isNotEmpty) ...[
                  _buildSectionHeader('Flights by Wing', Icons.paragliding),
                  const SizedBox(height: 8),
                  _buildWingStatsTable(_wingStats),
                  const SizedBox(height: 24),
                ],
                
                // Site Statistics Section
                if (_siteStats.isNotEmpty) ...[
                  _buildSectionHeader('Flights by Site', Icons.location_on),
                  const SizedBox(height: 8),
                  _buildSiteStatsTable(_siteStats),
                ],
              ],
            ),
          ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bar_chart,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No flight data yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Statistics will appear once you log some flights',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildYearlyStatsTable(List<Map<String, dynamic>> yearlyStats) {
    // Calculate totals
    double totalHours = 0;
    int totalFlights = 0;
    for (final stat in yearlyStats) {
      totalHours += (stat['total_hours'] as num?)?.toDouble() ?? 0.0;
      totalFlights += stat['flight_count'] as int;
    }
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Header Row
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Year',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Flights',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Total Hours',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            
            // Data Rows
            ...yearlyStats.map((stat) => Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      stat['year'].toString(),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      stat['flight_count'].toString(),
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      DateTimeUtils.formatHours((stat['total_hours'] as num?)?.toDouble() ?? 0.0),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            )),
            
            // Total Row
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'TOTAL',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      totalFlights.toString(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      DateTimeUtils.formatHours(totalHours),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWingStatsTable(List<Map<String, dynamic>> wingStats) {
    // Calculate totals
    double totalHours = 0;
    int totalFlights = 0;
    for (final stat in wingStats) {
      totalHours += (stat['total_hours'] as num?)?.toDouble() ?? 0.0;
      totalFlights += stat['flight_count'] as int;
    }
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Header Row
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Wing',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Flights',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Total Hours',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            
            // Data Rows
            ...wingStats.map((stat) => Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (stat['name'] as String?) ?? 'Unknown Wing',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (stat['size'] != null && (stat['size'] as String).isNotEmpty)
                          Text(
                            'Size: ${stat['size']}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      stat['flight_count'].toString(),
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      DateTimeUtils.formatHours((stat['total_hours'] as num?)?.toDouble() ?? 0.0),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            )),
            
            // Total Row (if more than one wing)
            if (wingStats.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        'TOTAL',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        totalFlights.toString(),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        DateTimeUtils.formatHours(totalHours),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSiteStatsTable(List<Map<String, dynamic>> siteStats) {
    // Group sites by country
    Map<String, List<Map<String, dynamic>>> groupedSites = {};
    double totalHours = 0;
    int totalFlights = 0;
    
    for (final stat in siteStats) {
      final country = (stat['country'] as String?) ?? 'Unknown Country';
      if (!groupedSites.containsKey(country)) {
        groupedSites[country] = [];
      }
      groupedSites[country]!.add(stat);
      
      // Calculate totals
      totalHours += (stat['total_hours'] as num?)?.toDouble() ?? 0.0;
      totalFlights += stat['flight_count'] as int;
    }
    
    // Sort countries (Unknown Country at the end)
    final sortedCountries = groupedSites.keys.toList();
    sortedCountries.sort((a, b) {
      if (a == 'Unknown Country' && b != 'Unknown Country') return 1;
      if (b == 'Unknown Country' && a != 'Unknown Country') return -1;
      return a.compareTo(b);
    });
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Header Row
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Site',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Flights',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Total Hours',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            
            // Country Groups
            ...sortedCountries.expand((country) {
              final sites = groupedSites[country]!;
              return [
                // Country Header (only show if more than one country)
                if (groupedSites.keys.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.flag,
                          size: 16,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          country,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${sites.length} ${sites.length == 1 ? 'site' : 'sites'}',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Sites in this country
                ...sites.map((stat) => Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: stat['id'] != null 
                      ? () => _editSite(stat['id'] as int)
                      : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Padding(
                              padding: EdgeInsets.only(left: groupedSites.keys.length > 1 ? 24.0 : 0.0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      (stat['name'] as String?) ?? 'Unknown Site',
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              stat['flight_count'].toString(),
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              DateTimeUtils.formatHours((stat['total_hours'] as num?)?.toDouble() ?? 0.0),
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
              ];
            }),
            
            // Total Row (if more than one site)
            if (siteStats.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        'TOTAL',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        totalFlights.toString(),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        DateTimeUtils.formatHours(totalHours),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}