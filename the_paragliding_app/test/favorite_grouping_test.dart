import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
import 'package:the_paragliding_app/presentation/screens/nearby_sites_screen.dart';

/// Covers the order of the Sites screen's favourites menu.
///
/// A pilot can favourite a landing from its own page, so the menu holds both
/// kinds and has to say which launch a landing belongs to. The grouping rule is
/// the intricate part and is pure, so it is tested directly rather than through
/// a screen that would need a database, a position fix and a popup.
void main() {
  // Sites are placed on a line of latitude so "nearer" in the tests means the
  // same thing it means on the screen, without any of them being coincident.
  ParaglidingSite launch(String name, {double lat = 47.0, String? group}) =>
      ParaglidingSite(
        name: name,
        latitude: lat,
        longitude: 12.0,
        siteType: 'launch',
        siteGroup: group,
      );

  ParaglidingSite landing(String name, {double lat = 47.0, String? group}) =>
      ParaglidingSite(
        name: name,
        latitude: lat,
        longitude: 12.0,
        siteType: 'landing',
        siteGroup: group,
      );

  List<String> namesOf(List<FavoriteRow> rows) =>
      rows.map((row) => '${row.isNested ? '  ' : ''}${row.site.name}').toList();

  test('a landing follows the launch it serves', () {
    final rows = NearbySitesScreenState.groupFavorites([
      launch('Hohe Salve', group: 'dhv:100'),
      launch('Kranzhorn', lat: 47.5, group: 'dhv:200'),
      landing('Hohe Salve Landeplatz', lat: 47.01, group: 'dhv:100'),
    ]);

    expect(namesOf(rows), [
      'Hohe Salve',
      '  Hohe Salve Landeplatz',
      'Kranzhorn',
    ]);
  });

  test('a landing serving several favourited launches is listed once', () {
    // 28.5% of DHV landings serve more than one launch. Listing one under each
    // would show a pilot who favourited four launches on the same hill their
    // landing four times, which is what "one row per favourite" rules out.
    final rows = NearbySitesScreenState.groupFavorites([
      launch('Far Launch', lat: 47.9, group: 'dhv:100;dhv:300'),
      launch('Near Launch', lat: 47.1, group: 'dhv:100'),
      landing('Shared Landeplatz', lat: 47.0, group: 'dhv:100'),
    ]);

    expect(namesOf(rows), [
      'Far Launch',
      'Near Launch',
      '  Shared Landeplatz',
    ], reason: 'nests under the nearer of the two launches it serves, once');
  });

  test('a landing whose launch is not favourited stays at top level', () {
    // It is the pilot's favourite. Dropping it would be the bug this whole
    // change fixes, and heading it with a launch they did not choose would put
    // something in the list they never marked.
    final rows = NearbySitesScreenState.groupFavorites([
      launch('Unrelated', group: 'dhv:200'),
      landing('Orphan Landeplatz', lat: 47.2, group: 'dhv:100'),
    ]);

    expect(namesOf(rows), ['Unrelated', 'Orphan Landeplatz']);
  });

  test('proximity alone never nests a landing', () {
    // The rule the site pages use, restated here: a landing sits a median 1.7km
    // from its launch and a neighbouring hill's field is often closer, so
    // distance decides only between launches that already share a token.
    final rows = NearbySitesScreenState.groupFavorites([
      launch('Wrong Hill', group: 'dhv:200'),
      landing('Landeplatz', lat: 47.00001, group: 'dhv:100'),
    ]);

    expect(namesOf(rows), ['Wrong Hill', 'Landeplatz']);
  });

  test('a landing with no group is left where it is', () {
    // A custom site the pilot added themselves has no site_group, so there is
    // nothing to join on and nothing to guess from.
    final rows = NearbySitesScreenState.groupFavorites([
      launch('Hohe Salve', group: 'dhv:100'),
      landing('My Field'),
    ]);

    expect(namesOf(rows), ['Hohe Salve', 'My Field']);
  });

  test('the order the favourites arrive in is preserved', () {
    // The caller has already sorted by distance from the pilot, or left the
    // list as loaded when there is no fix. Grouping must not resort it.
    final rows = NearbySitesScreenState.groupFavorites([
      launch('Third', lat: 47.3, group: 'dhv:300'),
      launch('First', lat: 47.1, group: 'dhv:100'),
      launch('Second', lat: 47.2, group: 'dhv:200'),
    ]);

    expect(namesOf(rows), ['Third', 'First', 'Second']);
  });

  test('several landings under one launch are nearest first', () {
    final rows = NearbySitesScreenState.groupFavorites([
      launch('Hohe Salve', group: 'dhv:100'),
      landing('Far Landeplatz', lat: 47.3, group: 'dhv:100'),
      landing('Near Landeplatz', lat: 47.05, group: 'dhv:100'),
    ]);

    expect(namesOf(rows), [
      'Hohe Salve',
      '  Near Landeplatz',
      '  Far Landeplatz',
    ]);
  });

  test('no favourites is no rows', () {
    expect(NearbySitesScreenState.groupFavorites([]), isEmpty);
  });
}
