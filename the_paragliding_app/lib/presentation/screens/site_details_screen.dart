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

class SiteDetailsScreen extends StatefulWidget {
  final Site? site;
  final ParaglidingSite? paraglidingSite;
  final Position? userPosition;
  final WindData? windData;
  final double maxWindSpeed;
  final double cautionWindSpeed;
  final Function(WindData)? onWindDataFetched;
  final Function()? onFavoriteToggled;

  const SiteDetailsScreen({
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
  State<SiteDetailsScreen> createState() => SiteDetailsScreenState();
}

class SiteDetailsScreenState extends State<SiteDetailsScreen> with SingleTickerProviderStateMixin {
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

  /// The catalogue entry behind a flown site, once resolved.
  ///
  /// Null until loaded, and for dialogs opened straight from the map where
  /// the catalogue entry was passed in already.
  ParaglidingSite? _catalogSite;

  /// Whichever record actually describes this launch: the catalogue entry
  /// passed in, or the one a flown site is linked to.
  ParaglidingSite? get _effectiveSite => widget.paraglidingSite ?? _catalogSite;

  /// The guides behind this launch, in catalogue order.
  ///
  /// Falls back to a single ParaglidingEarth tab when the catalogue predates
  /// source tracking, so an older database still shows what it always did
  /// rather than losing the tab entirely.
  List<({String provider, String id})> get _sourceTabs {
    final sources = _effectiveSite?.sources ?? const [];
    return sources.isEmpty ? const [(provider: 'pge', id: '')] : sources;
  }

  /// ParaglidingEarth's own id for this launch, from the catalogue's `source`.
  ///
  /// Null when no guide in this launch is PGE - an Australian launch Site
  /// Guide carries alone has no PGE detail to fetch.
  int? get _pgeSourceId {
    for (final source in _effectiveSite?.sources ?? const []) {
      if (source.provider == 'pge') return int.tryParse(source.id);
    }
    return null;
  }

  /// Guide names as a pilot would recognise them, not their internal keys.
  static String _sourceLabel(String provider) => switch (provider) {
        'pge' => 'PGE',
        'siteguide_au' => 'ANSG',
        _ => provider,
      };

  static String _sourceFullName(String provider) => switch (provider) {
        'pge' => 'ParaglidingEarth',
        'siteguide_au' => 'Australian National Site Guide',
        _ => provider,
      };

  /// What a tab holds, for the tooltip. The labels are short enough to be
  /// ambiguous on their own - "PGE" means nothing until you have seen it
  /// spelled out once.
  static String _sourceTooltip(String provider) =>
      '${_sourceFullName(provider)} site details';

  static String? _sourceUrl(String provider, String id) => switch (provider) {
        'pge' => 'https://www.paraglidingearth.com/?site=$id',
        // Site Guide ids are "<siteId>-<launchId>"; the page is per site.
        'siteguide_au' => 'https://siteguide.org.au/sites/details/${id.split('-').first}',
        _ => null,
      };

  /// Load the catalogue entry a flown site points at, and rebuild the tabs.
  ///
  /// A flown site knows only its IGC takeoff point and name, so it cannot say
  /// which guides describe the launch. The tab count depends on that, which
  /// is why the controller is replaced here rather than settled in initState.
  Future<void> _loadCatalogSite() async {
    final ref = widget.site?.catalogRef;
    if (widget.paraglidingSite != null || ref == null) return;

    final site = await PgeSitesDatabaseService.instance.getSiteByRef(ref);
    if (site == null || !mounted) return;

    setState(() {
      _catalogSite = site;
      _tabController?.dispose();
      _tabController = TabController(length: 1 + _sourceTabs.length, vsync: this);
    });
  }

  // Forecast table constants
  static const double _dayColumnWidth = 80.0;
  static const int _startHour = 7;
  static const int _endHour = 19;
  static const int _hoursToShow = 13; // 7am to 7pm inclusive

  @override
  void initState() {
    super.initState();
    // Weather, plus one tab per contributing guide.
    _tabController = TabController(length: 1 + _sourceTabs.length, vsync: this);
    // Resolve the catalogue entry first: it decides how many tabs there are,
    // and supplies the guide's own coordinates for the detail lookup.
    _loadCatalogSite().then((_) => _loadSiteDetails());
    _loadWindData();
    _loadWindForecast();
    _loadFavoriteStatus();
  }

  /// Where this screen's favourite lives: the catalogue, keyed by ref, or the
  /// pilot's own sites table, keyed by row id.
  ///
  /// A site linked to the catalogue always uses the catalogue, so one launch has
  /// one favourite however the pilot reached it. This used to be five branches
  /// duplicated across load and toggle, three of which existed only to pick
  /// between two meanings of `id`; a catalogue row carries `catalogRef` now
  /// whether or not it is also a flown site, so those collapse.
  ({String? catalogRef, int? localSiteId}) get _favouriteTarget {
    final catalogueSite = widget.paraglidingSite;
    if (catalogueSite != null) {
      if (catalogueSite.catalogRef != null) {
        return (catalogRef: catalogueSite.catalogRef, localSiteId: null);
      }
      // Unlinked flown site; an API-only result has no id and no favourite.
      return (
        catalogRef: null,
        localSiteId: catalogueSite.isFromLocalDb ? catalogueSite.id : null,
      );
    }

    final flownSite = widget.site;
    if (flownSite != null) {
      if (flownSite.catalogRef != null) {
        return (catalogRef: flownSite.catalogRef, localSiteId: null);
      }
      return (catalogRef: null, localSiteId: flownSite.id);
    }

    return (catalogRef: null, localSiteId: null);
  }

  /// Load favorite status for this site
  Future<void> _loadFavoriteStatus() async {
    final target = _favouriteTarget;
    final ref = target.catalogRef;
    final localSiteId = target.localSiteId;

    bool isFavorite = false;
    if (ref != null) {
      isFavorite = await PgeSitesDatabaseService.instance.isSiteFavorite(ref);
    } else if (localSiteId != null) {
      isFavorite = await DatabaseService.instance.isSiteFavorite(localSiteId);
    }

    LoggingService.structured('FAVORITES_LOAD', {
      'catalog_ref': ref,
      'local_site_id': localSiteId,
      'site_name': widget.paraglidingSite?.name ?? widget.site?.name ?? 'unknown',
      'is_favorite': isFavorite,
    });

    if (mounted) {
      setState(() {
        _isFavorite = isFavorite;
      });
    }
  }

  /// Toggle favorite status for this site
  Future<void> _toggleFavorite() async {
    final target = _favouriteTarget;
    final ref = target.catalogRef;
    final localSiteId = target.localSiteId;

    if (ref != null) {
      await PgeSitesDatabaseService.instance.toggleSiteFavorite(ref);
    } else if (localSiteId != null) {
      await DatabaseService.instance.toggleSiteFavorite(localSiteId);
    } else {
      return; // Nothing persisted to favourite.
    }

    final siteName = widget.paraglidingSite?.name ?? widget.site?.name;

    LoggingService.structured('FAVORITES_TOGGLE', {
      'catalog_ref': ref,
      'local_site_id': localSiteId,
      'site_name': siteName,
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
    for (final controller in _tabScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// A Scrollbar needs a controller attached to the view it decorates.
  ///
  /// Sharing the PrimaryScrollController across tabs throws once more than
  /// one tab exists: only the visible tab has a ScrollPosition, and the
  /// others assert while their scrollbar fades. Keyed per tab so each gets
  /// its own, and so a tab keeps its scroll offset when you come back to it.
  final Map<String, ScrollController> _tabScrollControllers = {};

  ScrollController _scrollControllerFor(String key) =>
      _tabScrollControllers.putIfAbsent(key, ScrollController.new);

  /// One tab's scrollable body.
  ///
  /// `thumbVisibility` is the point: at rest a Material scrollbar fades to
  /// nothing, so a tab holding several screens of guide prose looked exactly
  /// like one holding a paragraph. A permanent thumb is the only thing on
  /// screen that says there is more below.
  Widget _scrollableTab(String key, Widget child) {
    final controller = _scrollControllerFor(key);
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        child: child,
      ),
    );
  }

  Future<void> _loadSiteDetails() async {
    // The catalogue entry is the only thing that can answer this: a flown
    // record knows its IGC takeoff point and nothing about which guides
    // describe the launch.
    final catalogSite = _effectiveSite;
    if (catalogSite == null) return;

    setState(() {
      _isLoadingDetails = true;
      _loadingError = null;
    });

    try {
      final details =
          await ParaglidingEarthApi.instance.getDetailsForCatalogSite(catalogSite);

      if (mounted) {
        setState(() {
          _detailedData = details ?? {};

          // Keep the link available even when the fetch returned nothing,
          // since that is when you most want to go and look. Built from
          // ParaglidingEarth's own id, never the catalogue's.
          final pgeId = _pgeSourceId;
          if (pgeId != null) {
            _detailedData!['pge_link'] = 'https://www.paraglidingearth.com/?site=$pgeId';
          }

          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _detailedData = {};

          final pgeId = _pgeSourceId;
          if (pgeId != null) {
            _detailedData!['pge_link'] = 'https://www.paraglidingearth.com/?site=$pgeId';
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

    // Guide tabs need a controller and something for them to show.
    final bool showTabs = _tabController != null &&
        (_detailedData != null || widget.paraglidingSite != null);

    final flyabilityLine = _buildFlyabilityLine(windDirections);
    final characteristicsLine = _buildCharacteristicsLine();

    return Scaffold(
      appBar: AppBar(
        // The name and the favourite live here now. In the sheet they were a
        // headline and two icon buttons competing with the wind rose for one
        // row; an AppBar is where a page's identity and its actions belong,
        // and it pins them for free - which is what the sheet had to build by
        // hand out of a non-flex sibling.
        // Two lines, because one ellipsises exactly the part that matters:
        // "Mount Bakewell (top lau..." is the same title as the lower launch
        // a kilometre away, and which one you are reading decides which
        // access notes apply.
        title: Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        toolbarHeight: 72,
        actions: [
          IconButton(
            onPressed: _toggleFavorite,
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.red : null,
            ),
            tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
          ),
        ],
      ),
      // A Scaffold does not inset its own body, so without this the Android
      // gesture pill is drawn over the last line of whichever tab is open -
      // the same half of the inset problem the bottom sheet had, and just as
      // invisible until you look at a real phone.
      body: SafeArea(
        top: false,
        child: showTabs
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._buildHeaderContent(name, windDirections),
                      // The rose anchors the header and the facts sit beside
                      // it. They used to be stacked underneath, which left
                      // two thirds of the rose's row empty once the name
                      // moved to the AppBar - and the rose floating above the
                      // facts rather than belonging to them.
                      _buildRoseHeader(windDirections, [
                        if (flyabilityLine != null) flyabilityLine,
                        ..._buildOverviewContent(
                            name,
                            latitude,
                            longitude,
                            altitude,
                            country,
                            region,
                            rating,
                            siteType,
                            windDirections,
                            flightCount,
                            distanceText,
                            thermalFlag,
                            soaringFlag,
                            xcFlag),
                        if (characteristicsLine != null) characteristicsLine,
                      ]),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                // Below the header, the tabs take the rest of the page. On a
                // Scaffold body that is simply what Expanded means - no
                // extents, no fixed heights, and nothing to outgrow.
                TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  tabAlignment: TabAlignment.fill,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  // Material 3's own indicator and divider, rather than the
                  // 1px hairline the previous overrides produced - which is
                  // why these did not read as tabs.
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    const Tab(
                      child: Tooltip(
                        message: 'Flyability forecast by hour by day',
                        child: Text('Forecast', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    // One tab per contributing guide, named. The old single
                    // unlabelled tab held ParaglidingEarth data without saying
                    // so, and a launch can now come from more than one guide -
                    // which disagree on names, ratings and sometimes position.
                    for (final source in _sourceTabs)
                      Tab(
                        child: Tooltip(
                          message: _sourceTooltip(source.provider),
                          child: Text(
                            _sourceLabel(source.provider),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildWeatherTab(windDirections),
                      for (final source in _sourceTabs) _buildSourceTab(source),
                    ],
                  ),
                ),
              ],
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._buildHeaderContent(name, windDirections),
                  _buildRoseHeader(windDirections, [
                    if (flyabilityLine != null) flyabilityLine,
                    if (characteristicsLine != null) characteristicsLine,
                  ]),
                  const SizedBox(height: 8),
                  ..._buildSimpleContent(
                      name,
                      latitude,
                      longitude,
                      altitude,
                      country,
                      region,
                      rating,
                      siteType,
                      windDirections,
                      flightCount,
                      distanceText,
                      description),
                ],
              ),
            ),
      ),
    );
  }

  /// The closure warning, above everything else on the page.
  ///
  /// Shared by both layouts - the tabbed page and the plain scroll view a
  /// site with no guide entry gets.
  List<Widget> _buildHeaderContent(String name, List<String> windDirections) {
    return [
      // Closure notice, above everything else.
      //
      // A closed site used to be dropped from the catalogue
      // entirely, which left the other guides' entries for
      // the same place on the map looking like ordinary
      // launches - the app was less safe than either source
      // alone. Quinns Rocks is the case: closed pending a
      // council agreement, with two ParaglidingEarth entries
      // that do not know it.
      if (_effectiveSite?.closed != null) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Site closed',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _effectiveSite!.closed!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  /// An icon and the value it stands for, as one unbreakable unit.
  ///
  /// The point is the mainAxisSize.min Row: inside a Wrap these must be a
  /// single child, or a line break can put the glyph on one line and its
  /// value on the next - a terrain icon alone, then "150m" underneath.
  Widget _iconFact(IconData icon, String value, {bool bold = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: bold ? FontWeight.w500 : null,
              ),
        ),
      ],
    );
  }

  /// Wind rose on the left, whatever facts belong beside it on the right.
  ///
  /// Shared so the no-guides layout keeps the rose too - it is the one thing
  /// on this page that answers "is it on right now", and it should not
  /// disappear just because no guide has written the site up.
  Widget _buildRoseHeader(List<String> windDirections, List<Widget> facts) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (windDirections.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: WindRoseWidget(
              launchableDirections: windDirections,
              size: 72.0,
              windSpeed: _windData?.speedKmh,
              windDirection: _windData?.directionDegrees,
              centerDotColor: _getCenterDotColor(windDirections),
              centerDotTooltip: _getCenterDotTooltip(windDirections),
            ),
          ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: facts,
          ),
        ),
      ],
    );
  }

  /// The flyability verdict, in words.
  ///
  /// The rose's centre dot already carries this as a colour, and the sentence
  /// itself already existed - as the dot's tooltip, which needs a hover a
  /// phone does not have. Same helper the forecast table uses, so the wording
  /// cannot drift; it is just on screen now instead of behind a gesture that
  /// never happens.
  Widget? _buildFlyabilityLine(List<String> windDirections) {
    final presentation = _getWindRosePresentation(windDirections);
    final verdict = presentation?.tooltip;
    if (verdict == null) return null;

    // No coloured dot in front of it. The rose's centre dot is coloured from
    // this same presentation a few pixels away, and the sentence now says
    // "Unsafe" in words - a third encoding of one fact earns nothing. The
    // argument for adding this line was that colour should not be the only
    // carrier of the answer; that argument was for the words, not for a
    // second dot.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        verdict,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  /// What can be flown here, as the guide lists it.
  ///
  /// Kept out of the site-type icon's tooltip deliberately: the argument for
  /// showing the verdict applies here too - a tooltip needs a hover.
  Widget? _buildCharacteristicsLine() {
    if (_detailedData == null) return null;

    const flags = {
      'paragliding': 'Paragliding',
      'hanggliding': 'Hang Gliding',
      'hike': 'Hike',
      'thermals': 'Thermals',
      'soaring': 'Soaring',
      'xc': 'XC',
      'flatland': 'Flatland',
      'winch': 'Winch',
    };

    final characteristics = [
      for (final entry in flags.entries)
        if (_detailedData?[entry.key]?.toString() == '1') entry.value,
    ];
    if (characteristics.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Text(
        characteristics.join(', '),
        // Capped: it is the least important line in the header and, with
        // every flag set, the tallest - it was pushing the tabs down two
        // lines to list what the site allows.
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w300,
            ),
      ),
    );
  }

  List<Widget> _buildOverviewContent(String name, double latitude, double longitude, int? altitude, String? country, String? region, int? rating, String? siteType, List<String> windDirections, int? flightCount, String? distanceText, String? thermalFlag, String? soaringFlag, String? xcFlag) {
    return [
            // Site Type + Altitude + Wind directions + map link.
            //
            // A Wrap, not a Row: beside the wind rose this column is ~300dp,
            // and a Row ellipsised the launchable directions to "SW, W, ..."
            // - the one fact on the line a pilot is actually checking. It
            // flows onto a second line instead.
            //
            // Each icon travels inside the same Wrap child as its value.
            // Loose in the Wrap they are independent items, and a break
            // between any two strands the terrain glyph at the end of one
            // line with "150m" starting the next - which a long direction
            // list or a large system font size is enough to trigger.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                // No icon before the word: "Launch" is what the glyph meant,
                // and the tooltip it carried needed a hover a phone does not
                // have. The icons below stand in for words - altitude, wind,
                // map - rather than repeating one.
                if (siteType != null)
                  Text(
                    '${_formatSiteType(siteType)}:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                // Show altitude (prefer takeoff_altitude from API, fallback to general altitude)
                if (_detailedData?['takeoff_altitude'] != null || altitude != null)
                  _iconFact(
                    Icons.terrain,
                    '${_detailedData?['takeoff_altitude'] ?? altitude}m',
                  ),
                // Wind directions (compact)
                if (windDirections.isNotEmpty)
                  _iconFact(
                    Icons.air,
                    windDirections.join(', '),
                    bold: true,
                  ),
                // Map icon - opens maps app (directly after wind directions)
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
              // Wrap for the same reason as the launch line above, which was
              // fixed for this and left its sibling as a Row - and a Row
              // overflows with stripes rather than flowing.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    'Landing:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // Landing altitude
                  if (_detailedData?['landing_altitude'] != null)
                    _iconFact(
                      Icons.terrain,
                      '${_detailedData!['landing_altitude']}m',
                    ),
                  // Map icon for landing - uses landing coordinates if available
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

  /// One guide's view of this launch.
  ///
  /// ParaglidingEarth keeps the existing live detail fetch. Other guides show
  /// what the catalogue already holds and link out: the Australian Site Guide
  /// publishes no per-site endpoint - only a whole-country export - so the
  /// prose worth reading (hazards, access, landowners) stays on its own site
  /// rather than being shipped or fetched wholesale.
  Widget _buildSourceTab(({String provider, String id}) source) {
    if (source.provider == 'pge') return _buildTakeoffTab();

    final url = _sourceUrl(source.provider, source.id);
    final site = _effectiveSite;
    final fullName = _sourceFullName(source.provider);
    if (site == null) return const SizedBox.shrink();

    return _scrollableTab(
      source.provider,
      Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fullName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[300],
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'This launch as $fullName records it.',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
              const SizedBox(height: 16),
              _sourceDetailRow('Name', site.name),
              if (site.altitude != null)
                _sourceDetailRow('Altitude', '${site.altitude} m'),
              if (site.windDirections.isNotEmpty)
                _sourceDetailRow('Wind', site.windDirections.join(', ')),
              _sourceDetailRow(
                'Position',
                '${site.latitude.toStringAsFixed(5)}, ${site.longitude.toStringAsFixed(5)}',
              ),
              const SizedBox(height: 20),
              Text(
                'Conditions, hazards, access and landowner notes are published '
                'by $fullName and are not carried in the app.',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
              const SizedBox(height: 12),
              if (url != null)
                OutlinedButton.icon(
                  onPressed: () => _launchUrl(url),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text('Open in ${_sourceLabel(source.provider)}'),
                ),
            ],
          ),
      ),
    );
  }

  Widget _sourceDetailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              ),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  Widget _buildTakeoffTab() {
    return _scrollableTab(
      'pge',
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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

          // Link out from the tab, matching the other guides. It sits outside
          // the _detailedData branch so it is still there when the fetch
          // failed or the site has no detail - which is when you most want to
          // go and look.
          if (_detailedData?['pge_link'] != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _launchUrl(_detailedData!['pge_link']),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open in PGE'),
            ),
          ],
          ],
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

    // The table's height is fixed by its 7 rows, and FixedColumnTable handles
    // horizontal scrolling internally, so it needs no height cap of its own -
    // the tab scrolls it if the sheet is too short to show it whole. The
    // ConstrainedBox(maxHeight: 390) that used to be here neither scrolled
    // nor clipped: one extra row and it painted overflow stripes.
    return RefreshIndicator(
      onRefresh: _loadWindForecast,
      child: _scrollableTab(
        'forecast',
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
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
              // ParaglidingEarth's prose weather description used to repeat
              // here. It belongs to a guide, so it lives in that guide's tab
              // now that the tabs say which guide they are.
            ],
          ),
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
        return 'Launch';
      case 'landing':
        return 'Landing';
      case 'both':
        return 'Launch & Landing';
      default:
        return siteType;
    }
  }

  // _getSiteTypeIcon and _buildSiteCharacteristicsTooltip went with the
  // glyphs before "Launch" and "Landing". The tooltip listed the site's
  // characteristics, which _buildCharacteristicsLine now shows outright -
  // it had been computing that string for a hover no phone can perform.

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
