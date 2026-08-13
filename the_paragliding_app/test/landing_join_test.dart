import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/datasources/database_helper.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';

import 'helpers/test_helpers.dart';

/// A landing is tied to its launch by the group the guides publish, never by
/// distance.
///
/// Measured over DHV's export the median gap from a landing to its own takeoff
/// is 1,672m and only 9% fall within 250m, so proximity would attach almost
/// none of them - and would attach the wrong ones, since a neighbouring hill's
/// field is often nearer than your own.
void main() {
  setUpAll(() async {
    await TestHelpers.initializeDatabaseForTesting();
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    await DatabaseHelper.instance.database;
    await PgeSitesDatabaseService.instance.initializeTables();
  });

  tearDown(() async => DatabaseHelper.instance.close());

  Future<void> insert({
    required String ref,
    required String name,
    required String type,
    required String group,
    double lat = 47.46,
    double lon = 12.20,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('pge_sites', {
      'ref': ref, 'name': name, 'latitude': lat, 'longitude': lon,
      'country': 'at', 'site_type': type, 'site_group': group,
    });
  }

  ParaglidingSite launch(String group, {double lat = 47.46}) => ParaglidingSite(
        name: 'A launch', latitude: lat, longitude: 12.20,
        siteType: 'launch', siteGroup: group,
      );

  test('a launch finds the landings sharing its group', () async {
    await insert(ref: 'dhv:1-lz', name: 'Landeplatz 1', type: 'landing',
        group: 'dhv:1', lat: 47.50);
    await insert(ref: 'dhv:2-lz', name: 'Another hill Landeplatz',
        type: 'landing', group: 'dhv:2', lat: 47.47);

    final landings = await PgeSitesDatabaseService.instance
        .getLandingsForSite(launch('dhv:1'));

    // The one 4km away belongs to this launch; the one 1km away does not.
    expect(landings.map((l) => l.name), ['Landeplatz 1']);
  });

  test('a landing serving several launches is found from each', () async {
    // 28.5% of DHV landings sit under a Gelände with more than one launch, and
    // PGE republishes one field on every takeoff it serves.
    await insert(ref: 'pge:9-lz', name: 'Shared field', type: 'landing',
        group: 'dhv:266;pge:22752');

    for (final group in ['dhv:266', 'pge:22752']) {
      final landings = await PgeSitesDatabaseService.instance
          .getLandingsForSite(launch(group));
      expect(landings.map((l) => l.name), ['Shared field'], reason: group);
    }
  });

  test('a token is not matched by a longer one it prefixes', () async {
    // `pge:463` must not find a landing grouped under `pge:4632`.
    await insert(ref: 'pge:4632-lz', name: 'Not mine', type: 'landing',
        group: 'pge:4632');

    final landings = await PgeSitesDatabaseService.instance
        .getLandingsForSite(launch('pge:463'));

    expect(landings, isEmpty);
  });

  test('a launch with no group has no landings', () async {
    await insert(ref: 'dhv:1-lz', name: 'Landeplatz', type: 'landing',
        group: 'dhv:1');

    expect(
      await PgeSitesDatabaseService.instance.getLandingsForSite(launch('')),
      isEmpty,
    );
  });

  test('only landings are returned, never another launch', () async {
    await insert(ref: 'dhv:1-a', name: 'Sibling launch', type: 'launch',
        group: 'dhv:1');
    await insert(ref: 'dhv:1-lz', name: 'Landeplatz', type: 'landing',
        group: 'dhv:1');

    final landings = await PgeSitesDatabaseService.instance
        .getLandingsForSite(launch('dhv:1'));

    expect(landings.map((l) => l.name), ['Landeplatz']);
  });
}
