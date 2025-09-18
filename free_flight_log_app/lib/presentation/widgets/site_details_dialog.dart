import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/location_service.dart';
import '../../services/logging_service.dart';

/// Dialog widget for displaying detailed information about a paragliding site
///
/// Supports both local sites (from database) and API sites (from ParaglidingEarth)
/// and loads detailed information dynamically from the API.
class SiteDetailsDialog extends StatefulWidget {
  final Site? site;
  final ParaglidingSite? paraglidingSite;
  final Position? userPosition;

  const SiteDetailsDialog({
    super.key,
    this.site,
    this.paraglidingSite,
    this.userPosition,
  });

  @override
  State<SiteDetailsDialog> createState() => _SiteDetailsDialogState();
}

class _SiteDetailsDialogState extends State<SiteDetailsDialog> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _detailedData;
  bool _isLoadingDetails = false;
  String? _loadingError;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    // Create tab controller for both local and API sites - both can have detailed data
    _tabController = TabController(length: 5, vsync: this); // 5 tabs: Takeoff, Rules, Access, Weather, Comments
    _loadSiteDetails();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadSiteDetails() async {
    // Load detailed data from API for both local sites and API sites
    double latitude;
    double longitude;

    if (widget.paraglidingSite != null) {
      // API site - use its coordinates
      latitude = widget.paraglidingSite!.latitude;
      longitude = widget.paraglidingSite!.longitude;
    } else if (widget.site != null) {
      // Local site - use its coordinates to fetch API data
      latitude = widget.site!.latitude;
      longitude = widget.site!.longitude;
    } else {
      return; // No site data available
    }

    setState(() {
      _isLoadingDetails = true;
      _loadingError = null;
    });

    try {
      final details = await ParaglidingEarthApi.instance.getSiteDetails(
        latitude,
        longitude,
      );

      if (mounted) {
        setState(() {
          _detailedData = details;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
          _loadingError = 'Failed to load detailed information';
        });
        LoggingService.error('Error loading site details', e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine which site data to use
    final String name = widget.site?.name ?? widget.paraglidingSite?.name ?? 'Unknown Site';
    final double latitude = widget.site?.latitude ?? widget.paraglidingSite?.latitude ?? 0.0;
    final double longitude = widget.site?.longitude ?? widget.paraglidingSite?.longitude ?? 0.0;
    final int? altitude = widget.site?.altitude?.toInt() ?? widget.paraglidingSite?.altitude ?? _detailedData?['altitude'];
    final String? country = widget.site?.country ?? widget.paraglidingSite?.country ?? _detailedData?['country'];
    // Extract data from ParaglidingSite OR from fetched API data for local sites
    final String? region = widget.paraglidingSite?.region ?? _detailedData?['region'];
    final String? description = widget.paraglidingSite?.description ?? _detailedData?['description'];
    final int? rating = widget.paraglidingSite?.rating ?? _detailedData?['rating'];
    final List<String> windDirections = widget.paraglidingSite?.windDirections ??
        (_detailedData?['wind_directions'] as List<dynamic>?)?.cast<String>() ?? [];
    final String? siteType = widget.paraglidingSite?.siteType ?? _detailedData?['site_type'];
    final int? flightCount = widget.site?.flightCount;

    // Calculate distance if user position is available
    String? distanceText;
    if (widget.userPosition != null) {
      final distance = LocationService.instance.calculateDistance(
        widget.userPosition!.latitude,
        widget.userPosition!.longitude,
        latitude,
        longitude,
      );
      distanceText = LocationService.formatDistance(distance);
    }

    return Dialog(
      elevation: 16,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with name, rating, and close button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Show detailed view if we have a tab controller and either ParaglidingSite or fetched API data
            if (_tabController != null && (_detailedData != null || widget.paraglidingSite != null)) ...[
              // Overview content (always visible)
              ..._buildOverviewContent(name, latitude, longitude, altitude, country, region, rating, siteType, windDirections, flightCount, distanceText),

              const SizedBox(height: 8),

              // Tabs for detailed information
              if (_tabController != null)
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 40,
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: false,
                          tabAlignment: TabAlignment.fill,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                          indicatorWeight: 1.0,
                          indicatorPadding: EdgeInsets.zero,
                        tabs: const [
                          Tab(icon: Tooltip(message: 'Takeoff', child: Icon(Icons.flight_takeoff, size: 18))),
                          Tab(icon: Tooltip(message: 'Rules', child: Icon(Icons.policy, size: 18))),
                          Tab(icon: Tooltip(message: 'Access', child: Icon(Icons.location_on, size: 18))),
                          Tab(icon: Tooltip(message: 'Weather', child: Icon(Icons.cloud, size: 18))),
                          Tab(icon: Tooltip(message: 'Comments', child: Icon(Icons.comment, size: 18))),
                        ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildTakeoffTab(),
                            _buildRulesTab(),
                            _buildAccessTab(),
                            _buildWeatherTab(),
                            _buildCommentsTab(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildActionButtons(name, latitude, longitude),
                    ],
                  ),
                ),
            ] else
              ..._buildSimpleContent(name, latitude, longitude, altitude, country, region, rating, siteType, windDirections, flightCount, distanceText, description),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildOverviewContent(String name, double latitude, double longitude, int? altitude, String? country, String? region, int? rating, String? siteType, List<String> windDirections, int? flightCount, String? distanceText) {
    return [
            // Row 1: Location + Distance + Rating (moved to header)
            Row(
              children: [
                // Location info
                if (region != null || country != null) ...[
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      [region, country].where((s) => s != null && s.isNotEmpty).join(', '),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                // Distance
                if (distanceText != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.straighten, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '$distanceText away',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),

            // Row 2: Site Type + Altitude + Wind
            Row(
              children: [
                // Site type with characteristics tooltip
                if (siteType != null) ...[
                  Icon(
                    _getSiteTypeIcon(siteType),
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: _buildSiteCharacteristicsTooltip(),
                    child: Text(
                      _formatSiteType(siteType),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  ),
                  // Takeoff altitude from API data (if available)
                  if (_detailedData?['takeoff_altitude'] != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.height, size: 14, color: Colors.grey),
                    const SizedBox(width: 2),
                    Text(
                      '${_detailedData!['takeoff_altitude']}m',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
                // Altitude (existing site data)
                if (altitude != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.terrain, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${altitude}m',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                // Wind directions (compact)
                if (windDirections.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.air, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      windDirections.join(', '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),

            // Flight count (for local sites) - only show if present
            if (flightCount != null && flightCount > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.flight, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    '$flightCount ${flightCount == 1 ? 'flight' : 'flights'} logged',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
    ];
  }

  Widget _buildTakeoffTab() {
    return Scrollbar(
      child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          if (_isLoadingDetails)
            const Center(child: CircularProgressIndicator())
          else if (_loadingError != null)
            Center(child: Text(_loadingError!, style: const TextStyle(color: Colors.red)))
          else if (_detailedData != null) ...[
            // Takeoff instructions
            if (_detailedData!['takeoff_description'] != null && _detailedData!['takeoff_description']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['takeoff_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // Landing information
            if (_detailedData!['landing_description'] != null && _detailedData!['landing_description']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['landing_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // Parking information
            if (_detailedData!['takeoff_parking_description'] != null && _detailedData!['takeoff_parking_description']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['takeoff_parking_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // Altitude information
            if (widget.paraglidingSite?.altitude != null) ...[
              Text(
                '${widget.paraglidingSite!.altitude}m above sea level',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
          ] else
            const Center(child: Text('No takeoff information available')),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildRulesTab() {
    return Scrollbar(
      child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoadingDetails)
              const Center(child: CircularProgressIndicator())
            else if (_loadingError != null)
              Center(child: Text(_loadingError!, style: const TextStyle(color: Colors.red)))
            else if (_detailedData != null && _detailedData!['flight_rules'] != null && _detailedData!['flight_rules']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['flight_rules']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else
              const Center(child: Text('No flight rules available')),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildAccessTab() {
    return Scrollbar(
      child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoadingDetails)
              const Center(child: CircularProgressIndicator())
            else if (_loadingError != null)
              Center(child: Text(_loadingError!, style: const TextStyle(color: Colors.red)))
            else if (_detailedData != null && _detailedData!['going_there'] != null && _detailedData!['going_there']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['going_there']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else
              const Center(child: Text('No access information available')),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildWeatherTab() {
    return Scrollbar(
      child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoadingDetails)
              const Center(child: CircularProgressIndicator())
            else if (_loadingError != null)
              Center(child: Text(_loadingError!, style: const TextStyle(color: Colors.red)))
            else if (_detailedData != null && _detailedData!['weather'] != null && _detailedData!['weather']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['weather']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else
              const Center(child: Text('No weather information available')),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildCommentsTab() {
    return Scrollbar(
      child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoadingDetails)
              const Center(child: CircularProgressIndicator())
            else if (_loadingError != null)
              Center(child: Text(_loadingError!, style: const TextStyle(color: Colors.red)))
            else if (_detailedData != null) ...[
            // Pilot comments
            if (_detailedData!['comments'] != null && _detailedData!['comments']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['comments']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else
              const Center(child: Text('No pilot comments available')),
            ] else
              const Center(child: Text('No pilot comments available')),
          ],
        ),
      ),
      ),
    );
  }

  /// Launch navigation to coordinates
  Future<void> _launchNavigation(double latitude, double longitude) async {
    final uri = Uri.parse('https://maps.google.com/?daddr=$latitude,$longitude');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      LoggingService.action('NearbySites', 'launch_navigation', {
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (e) {
      LoggingService.error('NearbySites: Could not launch navigation', e);
    }
  }

  /// Launch URL in external browser
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      LoggingService.action('NearbySites', 'launch_url', {'url': url});
    } catch (e) {
      LoggingService.error('NearbySites: Could not launch URL', e);
    }
  }

  Widget _buildActionButtons(String name, double latitude, double longitude) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _launchNavigation(latitude, longitude);
            },
            icon: const Icon(Icons.navigation),
            label: const Text('Navigate'),
          ),
        ),
        // View on PGE button for API sites
        if (widget.paraglidingSite != null && _detailedData != null && _detailedData!['pgeid'] != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                final pgeUrl = 'https://www.paraglidingearth.com/pgearth/index.php?site=${_detailedData!['pgeid']}';
                _launchUrl(pgeUrl);
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('View Full Details on ParaglidingEarth'),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildSimpleContent(String name, double latitude, double longitude, int? altitude, String? country, String? region, int? rating, String? siteType, List<String> windDirections, int? flightCount, String? distanceText, String? description) {
    return [
      // Simple layout for local sites or sites without detailed data

      // Location info
      if (region != null || country != null) ...[
        Row(
          children: [
            const Icon(Icons.location_on, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [region, country].where((s) => s != null && s.isNotEmpty).join(', '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],

      // Altitude
      if (altitude != null) ...[
        Row(
          children: [
            const Icon(Icons.terrain, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              '${altitude}m altitude',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],

      // Distance
      if (distanceText != null) ...[
        Row(
          children: [
            const Icon(Icons.straighten, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              '$distanceText away',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],

      // Flight count (for local sites)
      if (flightCount != null && flightCount > 0) ...[
        Row(
          children: [
            const Icon(Icons.flight, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              '$flightCount ${flightCount == 1 ? 'flight' : 'flights'} logged',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],

      // Site type (for API sites)
      if (siteType != null) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.info_outline, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              'Type: ${_formatSiteType(siteType)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],

      // Wind directions (for API sites)
      if (windDirections.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.air, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Wind: ${windDirections.join(', ')}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],

      // Description (fallback for local sites)
      if (description != null && description.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(
          'Description',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],

      const SizedBox(height: 20),

      // Action buttons
      _buildActionButtons(name, latitude, longitude),
    ];
  }

  String _formatSiteType(String siteType) {
    switch (siteType.toLowerCase()) {
      case 'launch':
        return 'Launch Site';
      case 'landing':
        return 'Landing Zone';
      case 'both':
        return 'Launch & Landing';
      default:
        return siteType;
    }
  }

  IconData _getSiteTypeIcon(String siteType) {
    switch (siteType.toLowerCase()) {
      case 'launch':
        return Icons.flight_takeoff;
      case 'landing':
        return Icons.flight_land;
      case 'both':
        return Icons.flight;
      default:
        return Icons.location_on;
    }
  }

  String _buildSiteCharacteristicsTooltip() {
    if (_detailedData == null) return 'Site information';

    List<String> characteristics = [];

    // Check all possible characteristics that can have value "1"
    final characteristicMap = {
      'paragliding': 'Paragliding',
      'hanggliding': 'Hanggliding',
      'hike': 'Hike',
      'thermals': 'Thermals',
      'soaring': 'Soaring',
      'xc': 'XC',
      'flatland': 'Flatland',
      'winch': 'Winch',
    };

    characteristicMap.forEach((key, label) {
      if (_detailedData![key]?.toString() == '1') {
        characteristics.add(label);
      }
    });

    return characteristics.isNotEmpty
        ? characteristics.join(', ')
        : 'Site information';
  }
}