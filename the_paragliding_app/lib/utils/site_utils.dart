import '../data/models/site.dart';
import '../data/models/paragliding_site.dart';

/// Shared utilities for site operations across different map components
class SiteUtils {
  static const double _coordinateTolerance = 0.000001; // ~0.1 meter tolerance for floating point comparison
  
  /// Create a unique key for site flight status lookup
  /// Format: "latitude,longitude" with 6 decimal places precision
  static String createSiteKey(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
  }
  
  /// Which catalogue entries are already represented by a flown site.
  ///
  /// `catalog_ref` is the real link and survives both a pilot moving a
  /// site and the catalogue regenerating around it, neither of which leaves
  /// coordinates byte-identical. A flown site with no link has only its
  /// coordinates left to match on.
  ///
  /// Returns a predicate rather than testing one site, so a map full of
  /// markers costs one pass over the flown sites instead of one per
  /// catalogue entry.
  static bool Function(ParaglidingSite) duplicateOfFlownSite(
    Iterable<ParaglidingSite> flownSites,
  ) {
    final linkedRefs = <String>{};
    final unlinkedLocations = <String>{};

    for (final site in flownSites) {
      final ref = site.catalogRef;
      if (ref != null) {
        linkedRefs.add(ref);
      } else {
        unlinkedLocations.add(createSiteKey(site.latitude, site.longitude));
      }
    }

    // Both sides carry catalogRef now: on a flown site it is the link, on a
    // catalogue entry it is that row's own ref. Comparing them is exact, and
    // unlike the row number it was compared on before, it still means the same
    // launch after the catalogue is rebuilt.
    return (catalogSite) =>
        (catalogSite.catalogRef != null &&
            linkedRefs.contains(catalogSite.catalogRef)) ||
        unlinkedLocations
            .contains(createSiteKey(catalogSite.latitude, catalogSite.longitude));
  }

  /// Check if an API site is already represented by a local site
  /// Uses foreign key relationship when available, falls back to coordinates
  /// Used to avoid showing duplicate markers on maps
  static bool isDuplicateApiSite(ParaglidingSite apiSite, List<Site> localSites) {
    // First check if any local site is linked to this catalogue entry.
    // Compared on `catalogRef` both sides: this read `apiSite.id` before, which
    // now holds nothing for a catalogue row - and being an int against a String
    // the comparison was quietly always false rather than a type error.
    final linkedSite = localSites.where((localSite) =>
      localSite.catalogRef != null &&
      localSite.catalogRef == apiSite.catalogRef).firstOrNull;

    if (linkedSite != null) {
      return true; // Found exact FK match
    }

    // Fallback to coordinate-based matching for unlinked sites
    return localSites.any((localSite) =>
      localSite.catalogRef == null && // Only check unlinked sites
      (localSite.latitude - apiSite.latitude).abs() < _coordinateTolerance &&
      (localSite.longitude - apiSite.longitude).abs() < _coordinateTolerance
    );
  }

  /// Check if two coordinates are considered the same location
  /// Useful for site matching and deduplication
  static bool areCoordinatesEqual(double lat1, double lng1, double lat2, double lng2) {
    return (lat1 - lat2).abs() < _coordinateTolerance &&
           (lng1 - lng2).abs() < _coordinateTolerance;
  }
  
  /// Find a local site that matches the given coordinates
  /// Returns null if no match is found
  static Site? findMatchingLocalSite(double latitude, double longitude, List<Site> localSites) {
    return localSites.where((site) =>
      areCoordinatesEqual(latitude, longitude, site.latitude, site.longitude)
    ).firstOrNull;
  }

  /// Find a local site that is linked to the given PGE site ID
  /// More efficient than coordinate-based matching
  static Site? findLinkedLocalSite(String catalogRef, List<Site> localSites) {
    return localSites.where((site) => site.catalogRef == catalogRef).firstOrNull;
  }

  /// Check if a site is linked to PGE data
  static bool isSiteLinkedToPge(Site site) {
    return site.catalogRef != null;
  }

  /// Get sites grouped by their linking status for UI purposes
  static Map<String, List<Site>> groupSitesByLinkingStatus(List<Site> sites) {
    final linked = sites.where((site) => site.catalogRef != null).toList();
    final unlinked = sites.where((site) => site.catalogRef == null).toList();

    return {
      'linked': linked,
      'unlinked': unlinked,
    };
  }
}