import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/site.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/wind_forecast.dart';
import '../../data/models/flyability_status.dart';
import '../models/site_marker_presentation.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';
import '../../services/location_service.dart';
import '../../services/weather_service.dart';
import '../../services/database_service.dart';
import '../../services/pge_sites_database_service.dart';
import '../../utils/flyability_helper.dart';
import '../widgets/wind_rose_widget.dart';
import '../widgets/site_forecast_table.dart';
import '../widgets/forecast_attribution_bar.dart';

class SiteDetailsDialog extends StatefulWidget {
  final Site? site;
  final ParaglidingSite? paraglidingSite;
  final Position? userPosition;
  final WindData? windData;
  final double maxWindSpeed;
  final double cautionWindSpeed;
  final Function(WindData)? onWindDataFetched;
  final Function()? onFavoriteToggled;

  const SiteDetailsDialog({
    super.key,
    this.site,
    this.paraglidingSite,
    this.userPosition,
    this.windData,
    required this.maxWindSpeed,
    required this.cautionWindSpeed,
    this.onWindDataFetched,
    this.onFavoriteToggled,
  });

  @override
  State<SiteDetailsDialog> createState() => SiteDetailsDialogState();
}

class SiteDetailsDialogState extends State<SiteDetailsDialog> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _detailedData;
  bool _isLoadingDetails = false;
  String? _loadingError;
  TabController? _tabController;

  // Wind data state
  WindData? _windData;
  WindForecast? _windForecast;
  bool _isLoadingForecast = false;

  // Favorites state
  bool _isFavorite = false;

  // Forecast table constants
  static const double _dayColumnWidth = 80.0;
  static const int _startHour = 7;
  static const int _endHour = 19;
  static const int _hoursToShow = 13; // 7am to 7pm inclusive

  @override
  void initState() {
    super.initState();
    // Create tab controller for both local and API sites - both can have detailed data
    _tabController = TabController(length: 2, vsync: this); // 2 tabs: Takeoff, Weather
    _loadSiteDetails();
    _loadWindData();
    _loadWindForecast();
    _loadFavoriteStatus();
  }

  /// Load favorite status for this site
  Future<void> _loadFavoriteStatus() async {
    // Determine which database and ID to use for favorites
    // Rule: For sites with pge_site_id, always use PGE database as single source of truth
    bool isFavorite = false;
    String source = 'unknown';
    int? effectiveId;

    // Check ParaglidingSite first (this is what we usually have)
    if (widget.paraglidingSite != null) {
      // Check if this is linked to a PGE site
      if (widget.paraglidingSite!.pgeSiteId != null) {
        // Linked to PGE site - use PGE database (single source of truth)
        effectiveId = widget.paraglidingSite!.pgeSiteId;
        source = 'pge_via_paragliding_site';
        isFavorite = await PgeSitesDatabaseService.instance.isSiteFavorite(effectiveId!);
      } else if (widget.paraglidingSite!.isFromLocalDb) {
        // Custom local site - use local database
        effectiveId = widget.paraglidingSite!.id;
        if (effectiveId != null) {
          source = 'local';
          isFavorite = await DatabaseService.instance.isSiteFavorite(effectiveId);
        }
      } else {
        // Pure PGE site (not in local DB) - use PGE database
        effectiveId = widget.paraglidingSite!.id;
        if (effectiveId != null) {
          source = 'pge';
          isFavorite = await PgeSitesDatabaseService.instance.isSiteFavorite(effectiveId);
        }
      }
    } else if (widget.site != null) {
      // Fallback to Site object (rare case)
      if (widget.site!.pgeSiteId != null) {
        // Linked to PGE site - use PGE database (single source of truth)
        effectiveId = widget.site!.pgeSiteId;
        source = 'pge_via_site';
        isFavorite = await PgeSitesDatabaseService.instance.isSiteFavorite(effectiveId!);
      } else if (widget.site!.id != null) {
        // Custom local site - use local database
        effectiveId = widget.site!.id;
        source = 'local_via_site';
        isFavorite = await DatabaseService.instance.isSiteFavorite(effectiveId!);
      }
    }

    final siteName = widget.paraglidingSite?.name ?? widget.site?.name ?? 'unknown';
    LoggingService.structured('FAVORITES_LOAD', {
      'source': source,
      'effective_id': effectiveId,
      'site_name': siteName,
      'is_favorite': isFavorite,
      'pge_site_present': widget.paraglidingSite != null,
      'local_site_present': widget.site != null,
      'paragliding_site_pge_site_id': widget.paraglidingSite?.pgeSiteId,
      'local_pge_site_id': widget.site?.pgeSiteId,
    });

    if (mounted) {
      setState(() {
        _isFavorite = isFavorite;
      });
    }
  }

  /// Toggle favorite status for this site
  Future<void> _toggleFavorite() async {
    // Determine which database and ID to use for favorites toggle
    // Rule: For sites with pge_site_id, always use PGE database as single source of truth
    String? siteName;
    String source = 'unknown';
    int? effectiveId;

    // Check ParaglidingSite first (this is what we usually have)
    if (widget.paraglidingSite != null) {
      siteName = widget.paraglidingSite!.name;
      // Check if this is linked to a PGE site
      if (widget.paraglidingSite!.pgeSiteId != null) {
        // Linked to PGE site - use PGE database (single source of truth)
        effectiveId = widget.paraglidingSite!.pgeSiteId;
        source = 'pge_via_paragliding_site';
        await PgeSitesDatabaseService.instance.toggleSiteFavorite(effectiveId!);
      } else if (widget.paraglidingSite!.isFromLocalDb) {
        // Custom local site - use local database
        effectiveId = widget.paraglidingSite!.id;
        if (effectiveId != null) {
          source = 'local';
          await DatabaseService.instance.toggleSiteFavorite(effectiveId);
        }
      } else {
        // Pure PGE site (not in local DB) - use PGE database
        effectiveId = widget.paraglidingSite!.id;
        if (effectiveId != null) {
          source = 'pge';
          await PgeSitesDatabaseService.instance.toggleSiteFavorite(effectiveId);
        }
      }
    } else if (widget.site != null) {
      siteName = widget.site!.name;
      // Fallback to Site object (rare case)
      if (widget.site!.pgeSiteId != null) {
        // Linked to PGE site - use PGE database (single source of truth)
        effectiveId = widget.site!.pgeSiteId;
        source = 'pge_via_site';
        await PgeSitesDatabaseService.instance.toggleSiteFavorite(effectiveId!);
      } else if (widget.site!.id != null) {
        // Custom local site - use local database
        effectiveId = widget.site!.id;
        source = 'local_via_site';
        await DatabaseService.instance.toggleSiteFavorite(effectiveId!);
      }
    }

    if (effectiveId == null) {
      return; // No valid site ID
    }

    LoggingService.structured('FAVORITES_TOGGLE', {
      'source': source,
      'effective_id': effectiveId,
      'site_name': siteName,
      'pge_site_present': widget.paraglidingSite != null,
      'local_site_present': widget.site != null,
      'paragliding_site_pge_site_id': widget.paraglidingSite?.pgeSiteId,
      'local_pge_site_id': widget.site?.pgeSiteId,
    });

    // Reload favorite status to get updated value
    await _loadFavoriteStatus();

    // Notify parent screen that favorite was toggled
    if (widget.onFavoriteToggled != null) {
      widget.onFavoriteToggled!();
    }

    if (mounted && siteName != null) {
      // Show snackbar confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFavorite
                ? 'Added $siteName to favorites'
                : 'Removed $siteName from favorites',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
    int? pgeSiteId;

    if (widget.paraglidingSite != null) {
      // API site - use its coordinates and ID
      latitude = widget.paraglidingSite!.latitude;
      longitude = widget.paraglidingSite!.longitude;
      // For PGE sites: use pgeSiteId if available (linked local sites), otherwise use id (pure PGE sites)
      pgeSiteId = widget.paraglidingSite!.pgeSiteId ?? widget.paraglidingSite!.id;
    } else if (widget.site != null) {
      // Local site - use its coordinates and possibly linked PGE site ID
      latitude = widget.site!.latitude;
      longitude = widget.site!.longitude;
      pgeSiteId = widget.site!.pgeSiteId;
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
        siteId: pgeSiteId,
      );

      if (mounted) {
        setState(() {
          _detailedData = details ?? {};

          // Generate PGE link from site ID if available
          // This ensures the link is always available even if API call fails or doesn't include it
          if (pgeSiteId != null) {
            _detailedData!['pge_link'] = 'https://www.paraglidingearth.com/?site=$pgeSiteId';
          }

          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Even if API fails, create empty map and add PGE link if we have site ID
          _detailedData = {};

          if (pgeSiteId != null) {
            _detailedData!['pge_link'] = 'https://www.paraglidingearth.com/?site=$pgeSiteId';
          }

          _isLoadingDetails = false;
          _loadingError = 'Failed to load detailed information';
        });
        LoggingService.error('Error loading site details', e);
      }
    }
  }

  Future<void> _loadWindData() async {
    // If wind data was already provided by parent, use it
    if (widget.windData != null) {
      _windData = widget.windData;
      return;
    }

    // Otherwise, fetch wind data ourselves

    try {
      // Get coordinates from either paraglidingSite or site
      double latitude;
      double longitude;

      if (widget.paraglidingSite != null) {
        latitude = widget.paraglidingSite!.latitude;
        longitude = widget.paraglidingSite!.longitude;
      } else if (widget.site != null) {
        latitude = widget.site!.latitude;
        longitude = widget.site!.longitude;
      } else {
        return;
      }

      LoggingService.info('[SITE_DIALOG] Fetching wind data for site at $latitude, $longitude');

      final windData = await WeatherService.instance.getWindData(
        latitude,
        longitude,
        DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _windData = windData;
        });

        // Notify parent to update its cache
        if (windData != null && widget.onWindDataFetched != null) {
          widget.onWindDataFetched!(windData);
        }

        LoggingService.info('[SITE_DIALOG] Wind data fetched successfully: ${windData?.compassDirection} ${windData?.speedKmh}km/h');
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch wind data for site dialog', e, stackTrace);
    }
  }

  Future<void> _loadWindForecast() async {
    setState(() {
      _isLoadingForecast = true;
    });

    try {
      // Get coordinates from either paraglidingSite or site
      double latitude;
      double longitude;

      if (widget.paraglidingSite != null) {
        latitude = widget.paraglidingSite!.latitude;
        longitude = widget.paraglidingSite!.longitude;
      } else if (widget.site != null) {
        latitude = widget.site!.latitude;
        longitude = widget.site!.longitude;
      } else {
        return;
      }

      LoggingService.info('[SITE_DIALOG] Fetching 7-day forecast for site at $latitude, $longitude');

      // Fetch wind data which will cache the 7-day forecast
      await WeatherService.instance.getWindData(
        latitude,
        longitude,
        DateTime.now(),
      );

      // Access the cached forecast
      final forecast = await WeatherService.instance.getCachedForecast(latitude, longitude);

      if (mounted) {
        setState(() {
          _windForecast = forecast;
          _isLoadingForecast = false;
        });

        LoggingService.info('[SITE_DIALOG] 7-day forecast loaded: ${forecast?.timestamps.length ?? 0} hours');
      }
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch wind forecast for site dialog', e, stackTrace);
      if (mounted) {
        setState(() {
          _isLoadingForecast = false;
        });
      }
    }
  }


  /// Get wind rose center dot presentation (color and tooltip) based on flyability
  SiteMarkerPresentation? _getWindRosePresentation(List<String> windDirections) {
    // If no wind data available, return null (wind rose will use default styling)
    if (_windData == null) {
      return null;
    }

    // Create a minimal temporary site object for presentation calculation
    // This allows us to reuse the centralized flyability logic
    final tempSite = ParaglidingSite(
      name: '',
      latitude: 0.0,
      longitude: 0.0,
      windDirections: windDirections.where((d) => d.trim().isNotEmpty).toList(),
      siteType: 'launch',
    );

    // Calculate flyability status using FlyabilityHelper for 3-level logic
    FlyabilityStatus? status;
    if (windDirections.isNotEmpty) {
      final flyabilityLevel = FlyabilityHelper.getFlyabilityLevel(
        windData: _windData!,
        siteDirections: tempSite.windDirections,
        maxSpeed: widget.maxWindSpeed,
        cautionSpeed: widget.cautionWindSpeed,
      );

      // Convert FlyabilityLevel to FlyabilityStatus
      switch (flyabilityLevel) {
        case FlyabilityLevel.safe:
          status = FlyabilityStatus.flyable;
          break;
        case FlyabilityLevel.caution:
          status = FlyabilityStatus.caution;
          break;
        case FlyabilityLevel.unsafe:
          status = FlyabilityStatus.notFlyable;
          break;
        case FlyabilityLevel.unknown:
          status = FlyabilityStatus.unknown;
          break;
      }
    }

    return SiteMarkerPresentation.forFlyability(
      site: tempSite,
      status: status,
      windData: _windData,
      maxWindSpeed: widget.maxWindSpeed,
      cautionWindSpeed: widget.cautionWindSpeed,
      forecastEnabled: true,
    );
  }

  /// Get the center dot color based on flyability status
  Color? _getCenterDotColor(List<String> windDirections) {
    return _getWindRosePresentation(windDirections)?.color;
  }

  /// Get the center dot tooltip showing flyability reason
  String? _getCenterDotTooltip(List<String> windDirections) {
    return _getWindRosePresentation(windDirections)?.tooltip;
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
    // Check for both null and empty wind directions to ensure fallback to API data
    final List<String> windDirections =
        (widget.paraglidingSite?.windDirections.isNotEmpty == true
            ? widget.paraglidingSite!.windDirections
            : (_detailedData?['wind_directions'] as List<dynamic>?)?.cast<String>()) ?? [];

    final String? siteType = widget.paraglidingSite?.siteType ?? _detailedData?['site_type'];
    final int? flightCount = widget.site?.flightCount;

    // Extract flight characteristics flags
    final String? thermalFlag = _detailedData?['thermals']?.toString();
    final String? soaringFlag = _detailedData?['soaring']?.toString();
    final String? xcFlag = _detailedData?['xc']?.toString();

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

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  spreadRadius: 2,
                  blurRadius: 8,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Content wrapper with padding
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with wind rose, name, rating, and close button
                      Row(
                        children: [
                          // Wind rose widget (compact size for header)
                          if (windDirections.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 12.0),
                              child: WindRoseWidget(
                                launchableDirections: windDirections,
                                size: 60.0,
                                windSpeed: _windData?.speedKmh,
                                windDirection: _windData?.directionDegrees,
                                centerDotColor: _getCenterDotColor(windDirections),
                                centerDotTooltip: _getCenterDotTooltip(windDirections),
                              ),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Make name clickable if PGE link is available
                                if (_detailedData?['pge_link'] != null)
                                  InkWell(
                                    onTap: () => _launchUrl(_detailedData!['pge_link']),
                                    child: Text(
                                      name,
                                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    name,
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                // Flight characteristics directly under title
                                if (_detailedData != null) ...[
                                  () {
                                    final characteristics = <String>[];

                                    if (_detailedData?['paragliding']?.toString() == '1') {
                                      characteristics.add('Paragliding');
                                    }
                                    if (_detailedData?['hanggliding']?.toString() == '1') {
                                      characteristics.add('Hang Gliding');
                                    }
                                    if (_detailedData?['hike']?.toString() == '1') {
                                      characteristics.add('Hike');
                                    }
                                    if (_detailedData?['thermals']?.toString() == '1') {
                                      characteristics.add('Thermals');
                                    }
                                    if (_detailedData?['soaring']?.toString() == '1') {
                                      characteristics.add('Soaring');
                                    }
                                    if (_detailedData?['xc']?.toString() == '1') {
                                      characteristics.add('XC');
                                    }
                                    if (_detailedData?['flatland']?.toString() == '1') {
                                      characteristics.add('Flatland');
                                    }
                                    if (_detailedData?['winch']?.toString() == '1') {
                                      characteristics.add('Winch');
                                    }

                                    if (characteristics.isNotEmpty) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text(
                                          characteristics.join(', '),
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w300,
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }(),
                                ],
                              ],
                            ),
                          ),
                          // Favorite button with heart icon
                          IconButton(
                            onPressed: _toggleFavorite,
                            icon: Icon(
                              _isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: _isFavorite ? Colors.red : null,
                            ),
                            tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
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
                        ..._buildOverviewContent(name, latitude, longitude, altitude, country, region, rating, siteType, windDirections, flightCount, distanceText, thermalFlag, soaringFlag, xcFlag),

                        const SizedBox(height: 8),

                        // Tabs for detailed information
                        if (_tabController != null)
                          SizedBox(
                            height: 450, // Fixed height for tab content
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 40,
                                  child: TabBar(
                                    controller: _tabController,
                                    isScrollable: false,
                                    tabAlignment: TabAlignment.fill,
                                    labelPadding: EdgeInsets.symmetric(horizontal: 8),
                                    indicatorWeight: 1.0,
                                    indicatorPadding: EdgeInsets.zero,
                                  tabs: const [
                                    Tab(icon: Tooltip(message: 'Site Weather', child: Icon(Icons.air, size: 18))),
                                    Tab(icon: Tooltip(message: 'Site Information', child: Icon(Icons.info_outline, size: 18))),
                                  ],
                                  ),
                                ),
                                Expanded(
                                  child: TabBarView(
                                    controller: _tabController,
                                    children: [
                                      _buildWeatherTab(windDirections),
                                      _buildTakeoffTab(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ] else
                        ..._buildSimpleContent(name, latitude, longitude, altitude, country, region, rating, siteType, windDirections, flightCount, distanceText, description),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  List<Widget> _buildOverviewContent(String name, double latitude, double longitude, int? altitude, String? country, String? region, int? rating, String? siteType, List<String> windDirections, int? flightCount, String? distanceText, String? thermalFlag, String? soaringFlag, String? xcFlag) {
    return [
            // Row 2: Site Type + Altitude + Wind + Directions
            Row(
              children: [
                // Site type with characteristics tooltip on icon
                if (siteType != null) ...[
                  Tooltip(
                    message: _buildSiteCharacteristicsTooltip(),
                    child: Icon(
                      _getSiteTypeIcon(siteType),
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatSiteType(siteType),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Text(':', style: TextStyle(color: Colors.grey)),
                ],
                // Show altitude (prefer takeoff_altitude from API, fallback to general altitude)
                if (_detailedData?['takeoff_altitude'] != null || altitude != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.terrain, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${_detailedData?['takeoff_altitude'] ?? altitude}m',
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
                // Map icon - opens maps app (directly after wind directions)
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => _launchMap(latitude, longitude),
                  child: const Icon(
                    Icons.map,
                    size: 16,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),

            // Landing information row (if available)
            if (_detailedData?['landing_altitude'] != null || _detailedData?['landing_description'] != null || _detailedData?['landing_lat'] != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  // Landing icon with tooltip
                  Tooltip(
                    message: 'Landing information',
                    child: const Icon(
                      Icons.flight_land,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Landing Site',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Text(':', style: TextStyle(color: Colors.grey)),
                  // Landing altitude
                  if (_detailedData?['landing_altitude'] != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.terrain, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${_detailedData!['landing_altitude']}m',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  // Map icon for landing - uses landing coordinates if available
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () {
                      final landingLat = double.tryParse(_detailedData?['landing_lat']?.toString() ?? '');
                      final landingLng = double.tryParse(_detailedData?['landing_lng']?.toString() ?? '');
                      if (landingLat != null && landingLng != null) {
                        _launchMap(landingLat, landingLng);
                      } else {
                        _launchMap(latitude, longitude);
                      }
                    },
                    child: const Icon(
                      Icons.map,
                      size: 16,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ],

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
            Center(child: Text(_loadingError!, style: TextStyle(color: Colors.red)))
          else if (_detailedData != null) ...[
            // ===== TAKEOFF SECTION =====
            Row(
              children: [
                Icon(Icons.flight_takeoff, size: 18, color: Colors.grey[300]),
                const SizedBox(width: 8),
                Text(
                  'Takeoff',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[300],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Takeoff instructions
            if (_detailedData!['takeoff_description'] != null && _detailedData!['takeoff_description']!.toString().isNotEmpty) ...[
              Text(
                _detailedData!['takeoff_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // ===== WEATHER SECTION =====
            if (_detailedData!['weather'] != null && _detailedData!['weather']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.cloud, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Weather Information',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _detailedData!['weather']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // ===== LANDING SECTION =====
            if (_detailedData!['landing_description'] != null && _detailedData!['landing_description']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.flight_land, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Landing',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _detailedData!['landing_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            
            // Parking information
            if (_detailedData!['takeoff_parking_description'] != null && _detailedData!['takeoff_parking_description']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.local_parking, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Parking Information',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _detailedData!['takeoff_parking_description']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              // Add navigation to parking location if coordinates available
              if (_detailedData!['landing'] != null &&
                  _detailedData!['landing']['landing_parking_lat'] != null &&
                  _detailedData!['landing']['landing_parking_lng'] != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    final lat = double.tryParse(_detailedData!['landing']['landing_parking_lat'].toString());
                    final lng = double.tryParse(_detailedData!['landing']['landing_parking_lng'].toString());
                    if (lat != null && lng != null) {
                      _launchNavigation(lat, lng);
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.directions, size: 16, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text(
                        'Navigate to parking',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],

            // Flight Rules section
            if (_detailedData!['flight_rules'] != null && _detailedData!['flight_rules']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.policy, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Flight Rules & Regulations',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _detailedData!['flight_rules']!.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // Access Instructions section
            if (_detailedData!['going_there'] != null && _detailedData!['going_there']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.directions_car, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Access Instructions',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildLinkableText(_detailedData!['going_there']!.toString()),
              const SizedBox(height: 16),
            ],

            // Community Comments section
            if (_detailedData!['comments'] != null && _detailedData!['comments']!.toString().isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Local Information',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildLinkableText(_detailedData!['comments']!.toString()),
              const SizedBox(height: 16),
            ],

            // Alternate Takeoffs section
            if (_detailedData!['alternate_takeoffs'] != null && _hasAlternateTakeoffs(_detailedData!['alternate_takeoffs'])) ...[
              Row(
                children: [
                  Icon(Icons.alt_route, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Alternative Launch Points',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildAlternateTakeoffs(_detailedData!['alternate_takeoffs']),
              const SizedBox(height: 16),
            ],

            // Alternate Landings section
            if (_detailedData!['landing'] != null && _detailedData!['landing']['alternate_landings'] != null) ...[
              Row(
                children: [
                  Icon(Icons.alt_route, size: 18, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  Text(
                    'Alternative Landing Zones',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildAlternateLandings(_detailedData!['landing']['alternate_landings']),
            ],

            // Last updated information
            if (_detailedData!['last_edit'] != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.update, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'Last updated: ${_detailedData!['last_edit']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ] else
            const Center(child: Text('No takeoff information available')),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildWeatherTab(List<String> windDirections) {
    // Handle loading and error states first
    if (_isLoadingForecast) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_windForecast == null) {
      return const Center(child: Text('No forecast data available'));
    }

    // Column with forecast table and weather description - make scrollable to avoid overflow
    return RefreshIndicator(
      onRefresh: () async {
        await _loadWindForecast();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(), // Ensure pull-to-refresh works
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Forecast table - constrain max height for nested scrolling
            // FixedColumnTable handles horizontal scrolling internally
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 390), // Increased to accommodate attribution
              child: Padding(
                padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ForecastAttributionBar(
                      forecast: _windForecast,
                      onRefresh: () {
                        _loadWindForecast();
                      },
                    ),
                    _build7DayForecastTable(windDirections),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8.0),
          // Weather description info box
          if (_detailedData?['weather'] != null && _detailedData!['weather']!.toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _detailedData!['weather']!.toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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

  Widget _build7DayForecastTable(List<String> windDirections) {
    if (_windForecast == null) return const SizedBox.shrink();

    // Create a temporary ParaglidingSite with the wind directions for flyability calculation
    final tempSite = ParaglidingSite(
      id: 0,
      name: '',
      latitude: 0,
      longitude: 0,
      windDirections: windDirections,
      siteType: 'launch',
    );

    // Prepare wind data in the format expected by SiteForecastTable
    final windDataByDay = _prepareWindDataByDay();

    return SiteForecastTable(
      site: tempSite,
      windDataByDay: windDataByDay,
      maxWindSpeed: widget.maxWindSpeed,
      cautionWindSpeed: widget.cautionWindSpeed,
      dateColumnWidth: _dayColumnWidth,
    );
  }

  /// Prepare wind data in the format expected by SiteForecastTable
  /// Returns `Map<int, List<WindData?>>` where:
  ///   - key is day index (0-6 for next 7 days)
  ///   - value is list of hourly WindData (7am-7pm, 13 hours total)
  Map<int, List<WindData?>> _prepareWindDataByDay() {
    final Map<int, List<WindData?>> windDataByDay = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Initialize 7 days with empty hourly data
    for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
      windDataByDay[dayIndex] = List.filled(_hoursToShow, null);
    }

    // Fill in data from forecast
    for (int i = 0; i < _windForecast!.timestamps.length; i++) {
      final timestamp = _windForecast!.timestamps[i];
      final hour = timestamp.hour;

      // Only include hours between 7am and 7pm
      if (hour >= _startHour && hour <= _endHour) {
        // Calculate day index (0-6)
        final forecastDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
        final dayIndex = forecastDate.difference(today).inDays;

        // Only include if within next 7 days
        if (dayIndex >= 0 && dayIndex < 7) {
          // Calculate hour index (0-12 for 7am-7pm)
          final hourIndex = hour - _startHour;

          if (hourIndex >= 0 && hourIndex < _hoursToShow) {
            // Create WindData for this hour
            windDataByDay[dayIndex]![hourIndex] = WindData(
              speedKmh: _windForecast!.speedsKmh[i],
              directionDegrees: _windForecast!.directionsDegs[i],
              gustsKmh: _windForecast!.gustsKmh[i],
              precipitationMm: _windForecast!.precipitationMm[i],
              timestamp: timestamp,
            );
          }
        }
      }
    }

    return windDataByDay;
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

  /// Launch map to view a location (not navigate)
  Future<void> _launchMap(double latitude, double longitude) async {
    final uri = Uri.parse('https://maps.google.com/?q=$latitude,$longitude');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      LoggingService.action('NearbySites', 'launch_map', {
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (e) {
      LoggingService.error('NearbySites: Could not launch map', e);
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

  /// Build clickable text that turns URLs into links
  Widget _buildLinkableText(String text) {
    // Simple URL detection - matches http/https URLs
    final urlRegex = RegExp(r'https?://[^\s]+');
    final matches = urlRegex.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      // Add text before the URL
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: Theme.of(context).textTheme.bodyMedium,
        ));
      }

      // Add the clickable URL
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(url),
      ));

      lastEnd = match.end;
    }

    // Add remaining text after the last URL
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: Theme.of(context).textTheme.bodyMedium,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  /// Check if alternate takeoffs data has valid content
  bool _hasAlternateTakeoffs(dynamic alternateData) {
    if (alternateData == null) return false;

    List<dynamic> alternates = [];
    if (alternateData is Map && alternateData.containsKey('alternate_takeoff')) {
      final alt = alternateData['alternate_takeoff'];
      if (alt is List) {
        alternates = alt;
      } else {
        alternates = [alt];
      }
    } else if (alternateData is List) {
      alternates = alternateData;
    } else {
      alternates = [alternateData];
    }

    // Check if any alternate has meaningful data (lat/lng or description)
    for (final alternate in alternates) {
      if (alternate is Map) {
        final hasCoords = alternate['lat'] != null || alternate['lng'] != null;
        final hasDesc = alternate['description']?.toString().isNotEmpty == true;
        final hasName = alternate['name']?.toString().isNotEmpty == true;
        if (hasCoords || hasDesc || hasName) {
          return true;
        }
      }
    }
    return false;
  }

  /// Build alternate takeoffs section
  Widget _buildAlternateTakeoffs(dynamic alternateData) {
    if (alternateData == null) {
      return const SizedBox.shrink();
    }

    // Handle both single alternate takeoff and list of alternates
    List<dynamic> alternates = [];
    if (alternateData is Map && alternateData.containsKey('alternate_takeoff')) {
      final alt = alternateData['alternate_takeoff'];
      if (alt is List) {
        alternates = alt;
      } else {
        alternates = [alt];
      }
    } else if (alternateData is List) {
      alternates = alternateData;
    } else {
      alternates = [alternateData];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: alternates.asMap().entries.map((entry) {
        final index = entry.key;
        final alternate = entry.value;

        if (alternate is! Map) return const SizedBox.shrink();

        final name = alternate['name']?.toString();
        final lat = double.tryParse(alternate['lat']?.toString() ?? '');
        final lng = double.tryParse(alternate['lng']?.toString() ?? '');
        final altitude = alternate['altitude']?.toString();
        final description = alternate['description']?.toString();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.flag, size: 16, color: Colors.purple.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name?.isNotEmpty == true ? name! : 'Alternate ${index + 1}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (lat != null && lng != null)
                    InkWell(
                      onTap: () => _launchNavigation(lat, lng),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(
                            'Navigate',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (altitude != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.terrain, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${altitude}m',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
              if (description?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Build alternate landings section
  Widget _buildAlternateLandings(dynamic alternateData) {
    if (alternateData == null) {
      return const SizedBox.shrink();
    }

    // Handle both single alternate landing and list of alternates
    List<dynamic> alternates = [];
    if (alternateData is Map && alternateData.containsKey('alternate_landing')) {
      final alt = alternateData['alternate_landing'];
      if (alt is List) {
        alternates = alt;
      } else {
        alternates = [alt];
      }
    } else if (alternateData is List) {
      alternates = alternateData;
    } else {
      alternates = [alternateData];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: alternates.asMap().entries.map((entry) {
        final index = entry.key;
        final alternate = entry.value;

        if (alternate is! Map) return const SizedBox.shrink();

        final name = alternate['name']?.toString();
        final lat = double.tryParse(alternate['lat']?.toString() ?? '');
        final lng = double.tryParse(alternate['lng']?.toString() ?? '');
        final altitude = alternate['altitude']?.toString();
        final description = alternate['description']?.toString();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.teal.shade200),
            borderRadius: BorderRadius.circular(8),
            color: Colors.teal.shade50,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.teal.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name?.isNotEmpty == true ? name! : 'Alternate Landing ${index + 1}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (lat != null && lng != null)
                    InkWell(
                      onTap: () => _launchNavigation(lat, lng),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(
                            'Navigate',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (altitude != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.terrain, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${altitude}m',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
              if (description?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
