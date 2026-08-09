import '../data/models/paragliding_site.dart';
import '../data/models/site.dart';
import 'database_service.dart';
import 'logging_service.dart';
import 'site_matching_service.dart';

/// One proposed move of a single flight to a different launch.
///
/// Carries both distances so the confirmation UI can show the pilot *why* a
/// move is proposed, and so it can be audited afterwards, without recomputing.
class LaunchRematch {
  final int flightId;
  final DateTime flightDate;

  final int fromSiteId;
  final String fromSiteName;
  final double fromDistanceMeters;

  /// The launch being moved to, as [SiteMatchingService] resolved it.
  final ParaglidingSite toSite;
  final double toDistanceMeters;

  const LaunchRematch({
    required this.flightId,
    required this.flightDate,
    required this.fromSiteId,
    required this.fromSiteName,
    required this.fromDistanceMeters,
    required this.toSite,
    required this.toDistanceMeters,
  });

  /// How much closer the proposed launch is, in metres.
  double get improvementMeters => fromDistanceMeters - toDistanceMeters;

  @override
  String toString() => 'flight $flightId: "$fromSiteName" '
      '(${fromDistanceMeters.round()}m) -> "${toSite.name}" '
      '(${toDistanceMeters.round()}m)';
}

/// Re-run site matching over flights that are already imported.
///
/// [SiteMatchingService.findNearestSite] now picks the genuinely nearest
/// launch across the flight log and the catalogue, so **new** imports land on
/// the right launch. This is the repair for the ones recorded before that:
///
///  * flights imported while the catalogue still had one pin per hill - Mt
///    Borah gained three more launches with the federated (ANSG) merge, and
///    flights up to a kilometre from the west pin had matched it because it
///    was the only entry;
///  * flights matched while the flight-log tier short-circuited, which put
///    takeoffs on a neighbouring launch's flown site.
///
/// It deliberately re-uses the matcher rather than reimplementing "nearest
/// launch", so there is one definition of a match and the repair cannot drift
/// from what an import would do today.
///
/// `rematchUnknownSites` does not cover this: it works per *site* and only on
/// rows named "Unknown". The point here is that flights sharing one site
/// belong to different launches, so this works per *flight*.
///
/// **This rewrites the pilot's flight log**, which exists nowhere else, so it
/// is split into [preview] and [apply]. Nothing is written until a caller
/// passes proposals back to [apply].
class LaunchRematchService {
  static final LaunchRematchService instance = LaunchRematchService._();
  LaunchRematchService._();

  /// How much closer the proposed launch must be before a flight is moved.
  ///
  /// The matcher returning something different is not on its own a reason to
  /// rewrite the log: its two local tiers search different radii (500m for the
  /// flight log, 2km for the catalogue), so a flight sitting correctly on a
  /// site 600m from its takeoff can match a catalogue pin further away still.
  /// Only a real improvement is worth a write.
  static const double minimumImprovementMeters = 100;

  /// Find flights the matcher would now put on a materially closer launch.
  ///
  /// Reads only, and offline: the matcher's network tier is disabled for the
  /// duration, or a preview over a few hundred flights would fire one HTTP
  /// request per flight the catalogue does not cover, and could trip the API
  /// into offline mode for everything that follows.
  ///
  /// Ordered by how wrong the current assignment is, so a caller showing a
  /// truncated list shows the worst offenders first.
  Future<List<LaunchRematch>> preview() async {
    final databaseService = DatabaseService.instance;
    final matcher = SiteMatchingService.instance;

    // Nothing initialises the matcher at app start - only the import path
    // does, lazily. Without this the flight-log tier returns null at its
    // uninitialised guard for every flight, so the flown-versus-catalogue
    // comparison this service depends on never happens and every flight looks
    // like it belongs somewhere else.
    if (!matcher.isReady) {
      await matcher.initialize();
    }

    final flights = await databaseService.getAllFlights();
    final sites = {
      for (final site in await databaseService.getAllSites())
        if (site.id != null) site.id!: site,
    };

    final proposals = <LaunchRematch>[];
    int skippedNoFix = 0;
    int skippedCustom = 0;

    final apiWasEnabled = matcher.isApiEnabled;
    matcher.setApiEnabled(false);
    try {
      for (final flight in flights) {
        final flightId = flight.id;
        final siteId = flight.launchSiteId;
        final latitude = flight.launchLatitude;
        final longitude = flight.launchLongitude;

        if (flightId == null || siteId == null) continue;
        if (latitude == null || longitude == null) continue;

        // Null Island: the launch fix was never valid, so no candidate is
        // meaningful. Same guard as rematchUnknownSites.
        if (latitude == 0 && longitude == 0) {
          skippedNoFix++;
          continue;
        }

        final currentSite = sites[siteId];
        if (currentSite == null) continue;

        // A site the pilot named themselves is a deliberate choice; moving its
        // flights to a catalogue launch would silently overrule them.
        if (currentSite.customName) {
          skippedCustom++;
          continue;
        }

        final match = await matcher.findNearestSite(
          latitude,
          longitude,
          preferredType: 'launch',
        );

        if (match == null || match.id == null) continue;

        // Already on the launch the matcher would choose. The matcher returns
        // catalogue rows and flown sites alike, and the two id spaces overlap,
        // so compare on whichever actually identifies this flight's site.
        final matchIsCurrentSite = match.isFromLocalDb
            ? match.id == currentSite.id
            : match.id == currentSite.catalogSiteId;
        if (matchIsCurrentSite) continue;

        final fromDistance = _distanceMeters(
            latitude, longitude, currentSite.latitude, currentSite.longitude);
        final toDistance = match.distanceTo(latitude, longitude);

        // A different match is not enough - it has to be a better one.
        if (fromDistance - toDistance < minimumImprovementMeters) continue;

        proposals.add(LaunchRematch(
          flightId: flightId,
          flightDate: flight.date,
          fromSiteId: siteId,
          fromSiteName: currentSite.name,
          fromDistanceMeters: fromDistance,
          toSite: match,
          toDistanceMeters: toDistance,
        ));
      }
    } finally {
      matcher.setApiEnabled(apiWasEnabled);
    }

    proposals.sort((a, b) => b.improvementMeters.compareTo(a.improvementMeters));

    LoggingService.structured('LAUNCH_REMATCH_PREVIEW', {
      'flights_checked': flights.length,
      'proposed': proposals.length,
      'skipped_no_fix': skippedNoFix,
      'skipped_custom_name': skippedCustom,
    });

    return proposals;
  }

  /// Apply [proposals], moving each flight to its proposed launch.
  ///
  /// Creates a local site for a launch that has none yet, reusing one already
  /// linked to that catalogue row. Sites left with no flights are reported
  /// rather than deleted - a pilot may have favourited one, and an empty site
  /// is recoverable where a deleted one is not.
  Future<Map<String, dynamic>> apply(
    List<LaunchRematch> proposals, {
    void Function(int current, int total)? onProgress,
  }) async {
    if (proposals.isEmpty) {
      return {
        'success': true,
        'message': 'No flights to re-match',
        'flights_moved': 0,
        'sites_created': 0,
        'sites_left_empty': <String>[],
      };
    }

    final databaseService = DatabaseService.instance;

    int moved = 0;
    int created = 0;
    final touchedSiteIds = <int>{};

    try {
      final sitesBefore = (await databaseService.getAllSites()).length;

      for (var i = 0; i < proposals.length; i++) {
        onProgress?.call(i + 1, proposals.length);
        final proposal = proposals[i];
        final match = proposal.toSite;

        // The catalogue id behind the match, whichever source it came from. A
        // flight-log match carries the local sites.id in `id`; the id spaces
        // overlap, so passing that as a catalogue id links the site to an
        // unrelated launch.
        final catalogId =
            match.isFromLocalDb ? match.catalogSiteId : match.id;

        // findOrCreateSite resolves by catalogue id first and falls back to
        // the nearest site within its radius, so an unlinked row the pilot
        // already has for this launch is reused rather than duplicated. Doing
        // that here by hand is what produced twin site rows.
        final target = await databaseService.findOrCreateSite(
          latitude: match.latitude,
          longitude: match.longitude,
          name: match.name,
          altitude: match.altitude?.toDouble(),
          country: match.country,
          catalogSiteId: catalogId,
        );

        if (target.id == proposal.fromSiteId) continue;

        final flight = await databaseService.getFlight(proposal.flightId);
        if (flight == null) continue;

        await databaseService
            .updateFlight(flight.copyWith(launchSiteId: target.id));
        touchedSiteIds.add(proposal.fromSiteId);
        moved++;
      }

      created = (await databaseService.getAllSites()).length - sitesBefore;

      // Sites the moves may have emptied, reported for the caller to surface.
      final emptied = <String>[];
      for (final siteId in touchedSiteIds) {
        if (await databaseService.getFlightCountForSite(siteId) == 0) {
          final site = await databaseService.getSite(siteId);
          if (site != null) emptied.add(site.name);
        }
      }

      // Sites were added underneath the matcher's cache; a stale cache would
      // let the next import match against a site list that predates this run.
      await SiteMatchingService.instance.reload();

      LoggingService.structured('LAUNCH_REMATCH_APPLIED', {
        'flights_moved': moved,
        'sites_created': created,
        'sites_left_empty': emptied.length,
      });

      return {
        'success': true,
        'message': 'Moved $moved flight${moved == 1 ? '' : 's'}'
            '${created == 0 ? '' : ' to $created new launch${created == 1 ? '' : 'es'}'}',
        'flights_moved': moved,
        'sites_created': created,
        'sites_left_empty': emptied,
      };
    } catch (error, stackTrace) {
      LoggingService.error(
          'LaunchRematchService: Failed to apply re-match', error, stackTrace);

      // The real counts, not zero. Each move is committed on its own - there
      // is no transaction around the loop - so a failure partway through
      // leaves everything before it already written. Reporting 0 told the
      // pilot nothing had changed when their log had been rewritten.
      LoggingService.structured('LAUNCH_REMATCH_FAILED', {
        'flights_moved': moved,
        'proposals': proposals.length,
      });
      return {
        'success': false,
        'message': moved == 0
            ? 'Error re-matching flights: $error'
            : 'Error after moving $moved of ${proposals.length} flights: $error',
        'flights_moved': moved,
        'sites_created': created,
        'sites_left_empty': <String>[],
      };
    }
  }

  /// Great-circle distance in metres.
  ///
  /// [ParaglidingSite.distanceTo] covers the matched side; a flown [Site] has
  /// no equivalent, so the current-site leg is measured here.
  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    return ParaglidingSite(
      name: '',
      latitude: lat2,
      longitude: lon2,
      siteType: 'launch',
    ).distanceTo(lat1, lon1);
  }
}
