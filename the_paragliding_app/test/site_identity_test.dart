import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';

/// Covers [ParaglidingSite.siteKey] and the equality built on it.
///
/// `nearby_sites_screen.dart` keys `_siteFlyabilityStatus` by siteKey, and
/// `nearby_sites_map.dart` keys marker widgets by `ValueKey(site)`. Both once
/// assumed one site per coordinate - an invariant that held only because the
/// bounds loader deduped every coordinate collision away, including real ones.
/// Now that two launches can legitimately share a point, they have to be
/// distinguishable, or one silently takes on the other's wind verdict.
///
/// Deliberately touches no database: these are pure model tests, and a
/// file-level database setUp would re-seed 249 country codes per test for
/// nothing (see CLAUDE.md on issue #280).
void main() {
  ParaglidingSite siteAt({
    int? id,
    required String name,
    bool isFromLocalDb = false,
    double latitude = -31.848,
    double longitude = 116.777,
  }) =>
      ParaglidingSite(
        id: id,
        name: name,
        latitude: latitude,
        longitude: longitude,
        siteType: 'launch',
        isFromLocalDb: isFromLocalDb,
      );

  test('distinguishes two catalog launches sharing name and point', () {
    // Catalogue ids 166 and 210: both named "Øksnanuten", both at
    // 58.7608,5.98167. Same name at the same point is exactly what the old
    // name-plus-coordinates equality could not tell apart - and the bundled
    // catalogue has 23 shared-coordinate groups.
    final first = siteAt(id: 166, name: 'Øksnanuten');
    final second = siteAt(id: 210, name: 'Øksnanuten');

    expect(first.siteKey, isNot(second.siteKey));
    expect(first, isNot(equals(second)),
        reason: 'marker widgets are keyed ValueKey(site); equal keys let '
            'Flutter reconcile one marker onto the other');

    // The concrete failure this prevents: per-site state collapsing to one
    // entry, so the second site reads back the first site's verdict.
    final flyability = {first.siteKey: 'S only', second.siteKey: 'E/SE/S'};
    expect(flyability, hasLength(2),
        reason: 'per-site state must not collapse for co-located sites');
  });

  test('separates local and catalog id spaces, which overlap', () {
    final flown = siteAt(id: 42, name: 'Flown', isFromLocalDb: true);
    final catalog = siteAt(id: 42, name: 'Catalog');

    expect(flown.siteKey, isNot(catalog.siteKey),
        reason: 'sites.id 42 and pge_sites.id 42 are unrelated rows');
  });

  group('sites with no id', () {
    // ParaglidingEarthApi builds sites without an id (paragliding_earth_api
    // .dart:469), so this branch is reachable. It keeps name as well as
    // coordinates, matching the equality that preceded siteKey - dropping the
    // name would make two different API launches at one point compare equal,
    // and colliding ValueKeys trip Flutter's duplicate-key assertion.
    test('falls back to name and coordinates', () {
      final unsaved = siteAt(id: null, name: 'Unsaved API result');

      expect(unsaved.siteKey, 'coord:Unsaved API result@-31.848000,116.777000');
    });

    test('still separates two different launches at one point', () {
      expect(siteAt(id: null, name: 'North launch'),
          isNot(equals(siteAt(id: null, name: 'South launch'))));
    });

    test('treats the same unsaved launch as equal', () {
      expect(siteAt(id: null, name: 'Same launch'),
          equals(siteAt(id: null, name: 'Same launch')));
    });
  });
}
