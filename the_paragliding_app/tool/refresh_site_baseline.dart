// Rebuilds the site-metadata baseline from the published catalogue.
//
//   dart run tool/refresh_site_baseline.dart            # fetch the live catalogue
//   dart run tool/refresh_site_baseline.dart path.csv   # or read a local copy
//
// Writes two files that `test/site_metadata_test.dart` reads:
//
//   test/fixtures/site_metadata_catalogue.csv   the pinned rows
//   test/fixtures/site_metadata_baseline.json   what the app should show for them
//
// Why the expected values are computed here and not in the test: a test that
// recomputes what it is checking only proves it agrees with itself. This script
// reads the guides' own columns and works the answers out in plain, obvious code
// - compass order written out, altitudes subtracted - with no app code involved.
// The test then drives the real import, the real query and the real widget, and
// compares against these. Two implementations, and the numbers land in the diff
// where a human can check them against the guide's own page.
//
// Re-run it when the producer changes a value the baseline pins. That is a
// deliberate, reviewable diff, which is the point: the alternative is a test
// that follows the catalogue wherever it goes and so asserts nothing.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:csv/csv.dart';

/// The published catalogue, the same URL the app follows.
const String catalogUrl = 'https://raw.githubusercontent.com/Kevin-McIsaac/'
    'paragliding_site_federation/main/app/sites.csv';

/// The launches the baseline pins, chosen to cover every source shape the
/// catalogue publishes, and why each one is here.
///
/// Real sites rather than invented ones, because the shapes themselves are the
/// subject: a launch keyed under PGE but named by DHV, an Australian launch
/// whose landing is shared with PGE, a German name with an umlaut, a hill with
/// three landing fields at two different altitudes. None of those survive being
/// made up.
const Map<String, String> pinnedLaunches = {
  // pge only - the bulk of the catalogue (10,763 launches).
  'pge:10004': 'ParaglidingEarth alone, with its own landing',

  // dhv only - a German hill PGE has no entry for at all.
  'dhv:1009-neuwied-rodenbach-startplatz': 'DHV alone, launch and landing',

  // ansg only - Australia, and its landing is a *merged* ansg+pge row, so the
  // group intersection has to cross providers to find it.
  'ansg:138-251': 'Site Guide alone, landing shared with ParaglidingEarth',

  // dhv + pge - keyed under PGE, named by DHV, umlaut in the name, and three
  // landings in the group at two different altitudes. Which one the app calls
  // nearest decides whether the drop reads 70 m or 18 m, so it is pinned.
  'pge:10043': 'DHV and PGE merged, three landings, non-ASCII name',

  // dhv + pge where the landing is merged too, and the drop is nearly 1000 m.
  'pge:10170': 'DHV and PGE merged, landing merged as well',

  // ansg + pge - the other merge shape, 89 launches.
  'pge:11480': 'Site Guide and PGE merged',
};

const List<String> compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

Future<String> _load(List<String> args) async {
  if (args.isNotEmpty) return File(args.first).readAsStringSync();

  stderr.writeln('Fetching $catalogUrl');
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(catalogUrl))).close();
    if (response.statusCode != 200) {
      throw StateError('catalogue fetch failed: HTTP ${response.statusCode}');
    }
    return response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

String _field(CsvRow row, String name) => (row[name] ?? '').toString();

/// Every `provider:id` token in a `;`-separated column.
List<String> _tokens(String value) =>
    value.split(';').map((t) => t.trim()).where((t) => t.contains(':')).toList();

/// The directions a guide marks as usable, in compass order.
///
/// A cell is 0, 1 (good) or 2 (excellent); anything above zero is a direction
/// you can launch in, and the app shows both the same way.
List<String> _winds(CsvRow row) => [
      for (final d in compass)
        if ((int.tryParse(_field(row, 'wind_${d.toLowerCase()}')) ?? 0) > 0) d,
    ];

/// Great-circle distance in metres. Written out rather than imported so the
/// ordering this baseline pins is arrived at independently of the app's own.
double _distance(CsvRow a, CsvRow b) {
  double rad(String field, CsvRow row) =>
      (double.tryParse(_field(row, field)) ?? 0) * pi / 180;

  final lat1 = rad('latitude', a), lat2 = rad('latitude', b);
  final dLat = lat2 - lat1;
  final dLon = rad('longitude', b) - rad('longitude', a);
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
  return 6371000 * 2 * atan2(sqrt(h), sqrt(1 - h));
}

void main(List<String> args) async {
  final csvText = await _load(args);
  final rows = csv.decodeWithHeaders(csvText);
  if (rows.isEmpty) throw StateError('catalogue parsed to nothing');

  final headers = csvText.split('\n').first.trimRight().split(',');
  final byRef = {for (final row in rows) _field(row, 'ref'): row};

  // A landing is reachable from every group token it carries.
  final landingsByGroupToken = <String, List<CsvRow>>{};
  for (final row in rows) {
    if (_field(row, 'site_type') != 'landing') continue;
    for (final token in _tokens(_field(row, 'site_group'))) {
      landingsByGroupToken.putIfAbsent(token, () => []).add(row);
    }
  }

  final selected = <String, CsvRow>{};
  final baseline = <String, dynamic>{};

  for (final entry in pinnedLaunches.entries) {
    final launch = byRef[entry.key];
    if (launch == null) {
      throw StateError(
        'pinned launch ${entry.key} is no longer in the catalogue - replace it '
        'with another of the same shape rather than dropping the shape',
      );
    }

    // Every landing grouped with this launch, nearest first. One landing often
    // serves several launches and one launch often has several landings, so
    // this is a set union over the group tokens, deduplicated by ref.
    final landings = <String, CsvRow>{};
    for (final token in _tokens(_field(launch, 'site_group'))) {
      for (final landing in landingsByGroupToken[token] ?? const <CsvRow>[]) {
        landings[_field(landing, 'ref')] = landing;
      }
    }
    if (landings.isEmpty) {
      throw StateError('${entry.key} has no grouped landing to measure against');
    }
    final ordered = landings.values.toList()
      ..sort((a, b) => _distance(launch, a).compareTo(_distance(launch, b)));

    selected[entry.key] = launch;
    for (final landing in ordered) {
      selected[_field(landing, 'ref')] = landing;
    }

    final launchAltitude = int.tryParse(_field(launch, 'altitude'));
    final nearestAltitude = int.tryParse(_field(ordered.first, 'altitude'));
    final drop = launchAltitude != null && nearestAltitude != null
        ? launchAltitude - nearestAltitude
        : null;

    baseline[entry.key] = {
      'why': entry.value,
      'sources': [
        for (final token in _tokens(_field(launch, 'source')))
          {
            'provider': token.substring(0, token.indexOf(':')),
            'id': token.substring(token.indexOf(':') + 1),
          },
      ],
      'name': _field(launch, 'name'),
      'altitude_m': launchAltitude,
      'wind': _winds(launch),
      // Which guide supplied the name, wind and position above - not the
      // altitude, which gap-fills from a losing guide when the winner had none.
      // Null only for a catalogue published before the producer emitted it.
      'primary': _field(launch, 'primary').isEmpty
          ? null
          : _field(launch, 'primary'),
      // Nearest first, which is the order the launch's landings are listed in
      // and therefore which one the height is measured against.
      'landings': [
        for (final landing in ordered)
          {
            'ref': _field(landing, 'ref'),
            'name': _field(landing, 'name'),
            'altitude_m': int.tryParse(_field(landing, 'altitude')),
            'distance_m': _distance(launch, landing).round(),
          },
      ],
      // Neither guide publishes this; it is launch minus nearest landing, and
      // means something only when the landing is below.
      'height_above_landing_m': drop != null && drop > 0 ? drop : null,
    };
  }

  final fixtures = Directory('test/fixtures');
  if (!fixtures.existsSync()) fixtures.createSync(recursive: true);

  // Re-encoded rather than sliced out of the text: guide prose carries hard
  // line breaks, so a catalogue row is not a line and cannot be copied as one.
  // Every column is kept, in the producer's own order, so the fixture exercises
  // the same header-driven parse the download does.
  final table = [
    headers,
    for (final row in selected.values)
      [for (final header in headers) _field(row, header)],
  ];
  //
  // Written with LF endings. The encoder defaults to CRLF, which git rewrites
  // on the next checkout - so the committed fixture would differ from the bytes
  // this wrote, and a regeneration would show a diff on every line.
  File('test/fixtures/site_metadata_catalogue.csv')
      .writeAsStringSync('${Csv(lineDelimiter: '\n').encode(table)}\n');

  const encoder = JsonEncoder.withIndent('  ');
  File('test/fixtures/site_metadata_baseline.json').writeAsStringSync(
    // No timestamp: a regeneration that changes nothing must produce no diff,
    // or the file stops being evidence that a value moved.
    '${encoder.convert({
          'generated_from': catalogUrl,
          'launches': baseline,
        })}\n',
  );

  stderr.writeln('Wrote ${baseline.length} launches, '
      '${selected.length} catalogue rows.');
}
