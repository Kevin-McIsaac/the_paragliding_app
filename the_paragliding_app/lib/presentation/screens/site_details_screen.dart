import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/site.dart';
import '../../data/models/guide.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/wind_forecast.dart';
import '../../data/models/flyability_status.dart';
import '../models/site_marker_presentation.dart';
import '../../services/paragliding_earth_api.dart';
import '../../services/logging_service.dart';
import '../../services/weather_service.dart';
import '../../services/database_service.dart';
import '../../services/pge_sites_database_service.dart';
import '../../utils/flyability_helper.dart';
import '../widgets/wind_rose_widget.dart';
import '../widgets/site_forecast_table.dart';
import '../widgets/forecast_attribution_bar.dart';

/// How far a launch stands above its landing area, in whole metres.
///
/// Neither guide publishes this. ParaglidingEarth carries a takeoff and a
/// landing altitude and no drop between them; the Australian Site Guide has no
/// landing altitude at all, only prose. So it is the subtraction, and it means
/// something only when both figures are real and the landing is below.
///
/// Returns null rather than a negative number when it is not. A landing above
/// its launch is a winch or flatland site, or an altitude nobody filled in -
/// and "-401 m" printed beside a launch reads as a bug in the app rather than
/// as the gap in the data that it is.
///
/// Takes [Object?] because these arrive as XML element text, not numbers.
int? heightAboveLanding(Object? takeoffAltitude, Object? landingAltitude) {
  final takeoff = double.tryParse(takeoffAltitude?.toString() ?? '');
  final landing = double.tryParse(landingAltitude?.toString() ?? '');
  if (takeoff == null || landing == null) return null;

  final drop = takeoff - landing;
  return drop > 0 ? drop.round() : null;
}

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

  /// The other half of this site's group: a launch's landings, or a landing's
  /// launches.
  ///
  /// One field for both directions because it is one relationship, published by
  /// the guides as a shared `site_group` and symmetric by nature. Which way it
  /// is read follows from the open site's own type.
  ///
  /// Held rather than derived at build time because the join is a query. Empty
  /// for a catalogue published before the producer emitted the grouping.
  List<ParaglidingSite> _related = const [];

  /// Whichever record actually describes this launch: the catalogue entry
  /// passed in, or the one a flown site is linked to.
  ParaglidingSite? get _effectiveSite => widget.paraglidingSite ?? _catalogSite;

  /// The guides behind this launch, in catalogue order.
  ///
  /// Falls back to a single ParaglidingEarth tab when the catalogue predates
  /// source tracking, so an older database still shows what it always did
  /// rather than losing the tab entirely.
  /// A landing is reference information, not a site to assess.
  ///
  /// It has no wind directions, so the forecast table, the wind rose and the
  /// flyability verdict have nothing to work from - shown anyway they would
  /// read as "we checked and it is unflyable" rather than "this question does
  /// not apply".
  ///
  /// That is the *only* thing this decides. Everything else about a landing -
  /// its marker, its page, how it is reached, how it is queried - is a site
  /// like any other, told apart by its glyph. This flag used to be read as
  /// licence to suppress rather more, which is how the page ended up being a
  /// launch page with the launch taken out; what it shows instead is the
  /// launches it serves.
  bool get _isLanding => _effectiveSite?.siteType == 'landing';

  List<({String provider, String id})> get _sourceTabs {
    final sources = _effectiveSite?.sources ?? const [];
    return sources.isEmpty ? const [(provider: 'pge', id: '')] : sources;
  }

  // _pgeSourceId went with the synthesised `pge_link`. It parsed the PGE
  // source id as an int, which is null for a landing - whose id is its
  // takeoff's with `-lz` appended - so it could not have addressed those pages
  // anyway. The live lookup finds its record through
  // ParaglidingEarthApi.getDetailsForCatalogSite, and the link out is built
  // from the published registry.

  /// What a tab holds, for the tooltip. The labels are short enough to be
  /// ambiguous on their own - "PGE" means nothing until you have seen it
  /// spelled out once.
  ///
  /// The names themselves used to be three `switch` expressions here, and the
  /// site-page URLs a fourth. They are the producer's now - it publishes the
  /// guide list it federates from, so a guide added there is named here without
  /// an app release. See [Guides].
  static String _sourceTooltip(String provider) =>
      '${Guides.fullNameOf(provider)} site details';

  /// Credit for a guide's data, where the guide states a licence.
  ///
  /// Empty for one that does not - DHV publishes no terms with its export, and
  /// crediting it under someone else's licence would be a claim nobody made.
  List<Widget> _guideAttribution(String provider) {
    final guide = Guides.of(provider);
    if (guide == null || !guide.hasLicence) return const [];

    return [
      const SizedBox(height: 16),
      Text.rich(
        TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
          children: [
            TextSpan(text: 'Site data © ${guide.fullName}, licensed '),
            TextSpan(
              text: guide.licence,
              style: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchUrl(guide.licenceUrl),
            ),
          ],
        ),
      ),
    ];
  }

  /// This guide's page for the launch on screen.
  ///
  /// Takes the site rather than a `source` id, because the id that addresses a
  /// guide's page lives in `site_group` - see [Guide.siteUrl], and the 4,828
  /// links that were wrong while this derived one from `source`.
  String? _sourceUrl(String provider) =>
      Guides.of(provider)?.siteUrl(_effectiveSite?.siteGroup);

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
      _tabController = TabController(length: (_isLanding ? 0 : 1) + _sourceTabs.length, vsync: this);
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
    _tabController = TabController(length: (_isLanding ? 0 : 1) + _sourceTabs.length, vsync: this);
    // Resolve the catalogue entry first: it decides how many tabs there are,
    // and supplies the guide's own coordinates for the detail lookup.
    _loadCatalogSite().then((_) {
      _loadRelated();
      return _loadSiteDetails();
    });
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

  /// The other half of this site's group, from the catalogue.
  ///
  /// A launch loads its landings; a landing loads the launches it serves. The
  /// type inverts the query rather than blocking it, which is what gives a
  /// landing's page something to be about.
  ///
  /// Cheap and local - one indexed read - so it runs alongside the network
  /// fetch rather than after it.
  Future<void> _loadRelated() async {
    final site = _effectiveSite;
    if (site == null) return;

    final service = PgeSitesDatabaseService.instance;
    final related = site.siteType == 'landing'
        ? await service.getLaunchesForLanding(site)
        : await service.getLandingsForSite(site);
    if (mounted && related.isNotEmpty) {
      setState(() => _related = related);
    }
  }

  /// The other half of this site's group, listed nearest first.
  ///
  /// On a launch these are its landings, labelled `Landing:`. On a landing they
  /// are the launches it serves, labelled `Serves:` - the same rows read the
  /// other way, which is what stops a landing's page being a launch page with
  /// the launch bits hidden.
  ///
  /// Distance is shown because the two are not in sight of each other - the
  /// median gap is 1.7km - so "where is it" is the first question and a name
  /// alone does not answer it.
  Widget _buildRelatedSection(double latitude, double longitude) {
    final label = _isLanding ? 'Serves:' : 'Landing:';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final other in _related)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                // Opens that site's own page, whichever direction this is
                // being read in. Both routes to a landing - this row and the
                // map pin - now reach the same place, and the guide is one tab
                // further on rather than something a name does silently.
                //
                // Altitude is conditional because 153 landings have none, one
                // of them on Mt Broughton, which is where this started.
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SiteDetailsScreen(
                        site: null,
                        paraglidingSite: other,
                        maxWindSpeed: widget.maxWindSpeed,
                        cautionWindSpeed: widget.cautionWindSpeed,
                      ),
                    ),
                  ),
                  child: Text(
                    other.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                  ),
                ),
                if (other.altitude != null)
                  _iconFact(
                    Icons.terrain,
                    '${other.altitude} m AMSL',
                    tooltip: 'Altitude above mean sea level',
                  ),
                _iconFact(
                  Icons.straighten,
                  _formatDistance(other.distanceTo(latitude, longitude)),
                  tooltip: _isLanding
                      ? 'Distance from the landing'
                      : 'Distance from the launch',
                ),
                InkWell(
                  onTap: () => _launchMap(other.latitude, other.longitude),
                  child: const Icon(Icons.map, size: 16, color: Colors.blue),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _formatDistance(double metres) => metres < 1000
      ? '${metres.round()} m'
      : '${(metres / 1000).toStringAsFixed(1)} km';

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

          // No `pge_link` synthesised here any more. It existed so the tab kept
          // a link when the fetch returned nothing; the link is now built from
          // the catalogue row and the published registry, which needs no fetch
          // at all - so it is there whether this succeeded or not.
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _detailedData = {};
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
    // The header reads one record: the catalogue row the producer published.
    //
    // It used to coalesce three - flown site, then catalogue row, then a live
    // ParaglidingEarth lookup - which had the app re-deciding, field by field,
    // what the producer had already decided. On a merged launch that quietly
    // overruled it: selection.py picks one guide's record and names it in
    // `primary`, and the live lookup could put the losing guide's figure on
    // screen next to an attribution crediting the winner. Altitude was fixed
    // this way in #358; every other field kept the old shape until now.
    //
    // It also made the header wait on the network to draw at all, which is
    // exactly what a pilot at a launch site does not have.
    //
    // The pilot's own record still wins where it exists - a flown site's name,
    // position and altitude are theirs, and R5 says the catalogue never
    // overwrites them. That is not the pattern being removed; the pattern
    // being removed is a rival guide overriding the producer's choice.
    final catalogue = _effectiveSite;

    final String name = widget.site?.name ?? catalogue?.name ?? 'Unknown Site';
    final double latitude = widget.site?.latitude ?? catalogue?.latitude ?? 0.0;
    final double longitude = widget.site?.longitude ?? catalogue?.longitude ?? 0.0;
    final int? altitude = widget.site?.altitude?.toInt() ?? catalogue?.altitude;
    final List<String> windDirections = catalogue?.windDirections ?? const [];
    final String? siteType = catalogue?.siteType;
    final int? flightCount = widget.site?.flightCount;

    final flyabilityLine =
        _isLanding ? null : _buildFlyabilityLine(windDirections);

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
      //
      // One layout, always. This used to choose between the tabbed page and a
      // plainer scrolling one on `_detailedData != null || paraglidingSite !=
      // null` - so a flown site got the second layout until ParaglidingEarth
      // answered, and kept it forever offline. Nothing in the header needs the
      // network any more, so there is nothing to wait for and no second layout
      // to wait in.
      body: SafeArea(
        top: false,
        child: Column(
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
                        latitude,
                        longitude,
                        altitude,
                        siteType,
                        windDirections,
                        flightCount),
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
                if (!_isLanding)
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
                        Guides.labelOf(source.provider),
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
                  if (!_isLanding) _buildWeatherTab(windDirections),
                  for (final source in _sourceTabs) _buildSourceTab(source),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The closure warning, above everything else on the page.
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
  ///
  /// A [tooltip] wraps the pair rather than either half, for the same reason.
  /// It only ever elaborates on what the text already says - nothing on this
  /// row may depend on a hover, which a phone does not have.
  Widget _iconFact(IconData icon, String value,
      {bool bold = false, String? tooltip}) {
    final fact = Row(
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

    return tooltip == null ? fact : Tooltip(message: tooltip, child: fact);
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

  /// What can be flown here, as ParaglidingEarth lists it.
  ///
  /// This sat in the header until the header became catalogue-only. It is the
  /// one thing the header showed that no column of the catalogue carries -
  /// PGE publishes these flags, the other guides have nothing comparable, and
  /// the producer does not resolve them. So rather than the header claiming a
  /// fact one guide happens to hold, it sits with the rest of that guide's
  /// live prose, in that guide's tab, where its provenance is the tab's name.
  ///
  /// Still not a tooltip on the site-type icon, for the reason it left one:
  /// a tooltip needs a hover a phone does not have.
  List<Widget> _buildCharacteristicsSection() {
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
    if (characteristics.isEmpty) return const [];

    return [
      Row(
        children: [
          Icon(Icons.paragliding, size: 18, color: Colors.grey[300]),
          const SizedBox(width: 8),
          Text(
            'Characteristics',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[300],
                ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        characteristics.join(', '),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildOverviewContent(double latitude, double longitude, int? altitude, String? siteType, List<String> windDirections, int? flightCount) {
    // The two figures this screen actually shows, so the drop between them
    // cannot contradict either.
    //
    // Both used to come from ParaglidingEarth, because the catalogue had no
    // landing to subtract and mixing a PGE landing into a national guide's
    // launch would have meant two guides' numbers - sometimes two datums. It
    // now carries landings, so both come from one dataset that the producer
    // reconciled, which is a better answer than one guide's on its own.
    //
    // The remaining datum risk is upstream's and stays upstream's: Site Guide
    // publishes some above-ground heights as though they were AMSL, which is
    // an open issue in the pipeline and not something to paper over here.
    //
    // Only on a launch: `_related` holds landings there, but launches on a
    // landing's page, and "height above the launch" is not a figure anyone
    // wants.
    final launchAltitude = altitude;
    final landingAltitude =
        !_isLanding && _related.isNotEmpty ? _related.first.altitude : null;
    final drop = heightAboveLanding(launchAltitude, landingAltitude);

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
                // Altitude, above mean sea level and said so. AGL at a launch
                // is zero by definition, so an unlabelled figure invites the
                // reading it cannot have - and the guides do publish both:
                // Site Guide's height for Mt Bakewell is 255m above the
                // valley where PGE's is 436m AMSL. The unit is written out
                // rather than left to the tooltip, which a phone cannot hover.
                //
                // The catalogue, and nothing else.
                //
                // This was once the live lookup first, which quietly overruled
                // the producer on every merged launch: it decides which guide
                // wins a field, and for Abendberg that is DHV's 1823m, while
                // PGE's record says 1830m and was what showed. #358 put the
                // catalogue in front; the fallback behind it is gone now too,
                // so a launch shows one guide's figure or no figure - never a
                // second guide's, under an attribution naming the first.
                if (launchAltitude != null)
                  _iconFact(
                    Icons.terrain,
                    '$launchAltitude m AMSL',
                    tooltip: 'Altitude above mean sea level',
                  ),
                // How far the launch stands above its landing - the number a
                // pilot sizes up a site with, and the one neither guide
                // publishes. See heightAboveLanding.
                if (drop != null)
                  _iconFact(
                    Icons.height,
                    '$drop m',
                    tooltip: 'Height above the landing area',
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

            // Landing information, from the catalogue.
            //
            // This works offline and for launches PGE has never described - a
            // DHV-only or ANSG-only site showed no landing at all before it.
            //
            // There used to be a live-PGE fallback underneath, for launches the
            // catalogue has no landing for. It has been removed, and it costs
            // nothing: the producer already federates PGE's own `landing{}`
            // blob into landing rows, so where the catalogue has none PGE has
            // none either - measured over a sample of launches missing a
            // catalogue landing, not one had a live landing altitude. What the
            // fallback could still do was mix PGE's landing into a national
            // guide's launch, at two different datums.
            if (_related.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildRelatedSection(latitude, longitude),
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

    final url = _sourceUrl(source.provider);
    final site = _effectiveSite;
    final fullName = Guides.fullNameOf(source.provider);
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
              // Whose figures these are, said only as far as the catalogue can
              // back it. This used to read "as $fullName records it" on every
              // tab, which was unbackable: the catalogue keeps one set of
              // details per site and, until the producer emitted `primary`, did
              // not publish which guide it took them from.
              Text(
                _provenanceLine(source.provider),
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
              const SizedBox(height: 16),
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
                  label: Text('Open in ${Guides.labelOf(source.provider)}'),
                ),
            ],
          ),
      ),
    );
  }

  /// What this tab can honestly say about the figures it is showing.
  ///
  /// Three cases, because the catalogue supports exactly three answers:
  ///
  ///  * this guide won - the name, wind and position below are its own;
  ///  * another guide won - they are that guide's, and this tab exists because
  ///    this guide also describes the place. Saying so is the point: a pilot
  ///    reading the DHV tab on a launch PGE named should be told, not left to
  ///    assume;
  ///  * nobody said - a catalogue published before the producer emitted
  ///    `primary`, where the only truthful answer is that these are the
  ///    catalogue's figures and it does not record whose.
  ///
  /// Deliberately limited to name, wind and position. The producer gap-fills
  /// altitude and notes from a losing guide when the winner published none, so
  /// a broader claim would overstate what `primary` means - and the test that
  /// pins that distinction lives in the producer's repository.
  String _provenanceLine(String provider) {
    final thing = _isLanding ? 'landing' : 'launch';
    final primary = _effectiveSite?.primarySource;

    if (primary == null) {
      return 'One of the guides behind this $thing. The catalogue does not say '
          'which of them its name, wind and position came from.';
    }
    if (primary == provider) {
      return 'The name, wind and position below are as '
          '${Guides.fullNameOf(provider)} records this $thing.';
    }
    return 'Also describes this $thing. The name, wind and position below are '
        'as ${Guides.fullNameOf(primary)} records it - open '
        '${Guides.labelOf(provider)} for its own.';
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
            // ===== CHARACTERISTICS SECTION =====
            // First: what can be flown here at all, before the prose about
            // how. Moved out of the header, which now shows only what the
            // producer resolved - see _buildCharacteristicsSection.
            ..._buildCharacteristicsSection(),

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

          // ParaglidingEarth publishes its database under CC BY-SA 3.0, which
          // permits this use on condition the source is credited wherever the
          // content is shown. Outside the _detailedData branch for the same
          // reason as the link below: the tab is ParaglidingEarth's either way.
          //
          // Both the guide and its licence come from the published registry.
          // They were written out here, which meant the app asserting a
          // licence on a guide's behalf - fine while it was right, and one
          // release from being wrong. A guide that publishes no terms shows
          // none rather than borrowing this one.
          ..._guideAttribution('pge'),

          // Link out from the tab, built the same way as every other guide's.
          // Outside the _detailedData branch so it survives a failed fetch,
          // which is when you most want to go and look.
          //
          // This used to use `_detailedData['pge_link']`, synthesised from
          // `int.tryParse` of the PGE source id. That parse fails on a landing,
          // whose id is its takeoff's with `-lz` appended - so the button
          // simply disappeared from every PGE landing page rather than pointing
          // anywhere. The registry addresses a page by `site_group`, which
          // holds the takeoff's id, so those pages get a working link.
          if (_sourceUrl('pge') != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _launchUrl(_sourceUrl('pge')!),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text('Open in ${Guides.labelOf('pge')}'),
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
  // characteristics, which the PGE tab now shows outright - it had been
  // computing that string for a hover no phone can perform.
  //
  // _buildSimpleContent went with the live lookup the header used to wait on.
  // It was a second, differently-styled header ("436m altitude" where the real
  // one says "436 m AMSL") shown only in the gap before PGE answered, and it
  // was the only reader of region, rating and distance-from-user.

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
