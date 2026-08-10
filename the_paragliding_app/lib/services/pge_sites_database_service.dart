import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../data/models/paragliding_site.dart';
import '../data/datasources/database_helper.dart';
import '../services/logging_service.dart';
import '../services/pge_sites_download_service.dart';
import '../services/site_matching_service.dart';
import '../utils/catalog_ref.dart';
import '../utils/performance_monitor.dart';

/// Service for managing PGE sites in local SQLite database
/// Provides fast spatial queries and search functionality
class PgeSitesDatabaseService {
  static final PgeSitesDatabaseService instance = PgeSitesDatabaseService._();
  PgeSitesDatabaseService._();

  /// Database table names
  static const String _pgeSitesTable = 'pge_sites';
  static const String _pgeSitesMetadataTable = 'pge_sites_metadata';
  static const String _countryCodesTable = 'country_codes';

  /// Add a column to an existing table if it is not already present.
  ///
  /// `initializeTables` uses CREATE TABLE IF NOT EXISTS, so an install that
  /// predates a column never gains it from the schema alone.
  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((c) => c['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    LoggingService.database('MIGRATE', 'Added $table.$column');
  }

  /// Give the rows an existing install already holds a [CatalogRef], so its
  /// favourites survive into the keyed table without waiting for a re-import.
  ///
  /// A row whose `source` is empty comes from the PGE-only export, where the id
  /// genuinely was a PGE id, so `pge:<id>` is correct rather than a guess.
  ///
  /// Rows that collide on a key are deleted down to one, because a duplicate
  /// makes the unique index - and so the upsert - impossible to create. The
  /// survivor is chosen favourite-first: a pre-federation install could hold one
  /// row per guide for a single physical launch, and picking arbitrarily would
  /// drop the pilot's favourite with only an aggregate count to show for it. A
  /// deleted catalogue row returns on the next import; a favourite does not.
  static Future<void> _backfillRefs(DatabaseExecutor db) async {
    final rows = await db.query(_pgeSitesTable,
        columns: ['id', 'source', 'is_favorite'], where: 'ref IS NULL');
    if (rows.isEmpty) return;

    int favourite(Map<String, Object?> row) => (row['is_favorite'] as int?) ?? 0;

    // Favourites first, so a collision keeps the row the pilot marked. Ties fall
    // back to the lowest id, which makes the outcome order-independent.
    final ordered = rows.toList()
      ..sort((a, b) {
        final byFavourite = favourite(b).compareTo(favourite(a));
        return byFavourite != 0
            ? byFavourite
            : (a['id'] as int).compareTo(b['id'] as int);
      });

    final keptFor = <String, int>{};
    var keyed = 0;
    var collided = 0;
    var favouritesDropped = 0;

    // Batched, not a write per row. On an upgrading install this is the whole
    // catalogue - ~11,700 rows - and it is awaited from
    // AppInitializationService.ensureTables(), which is on the launch path and
    // documented as cheap DDL. One round trip per row would make that promise
    // false and could visibly stall startup on a slow device.
    final batch = db.batch();

    for (final row in ordered) {
      final id = row['id'] as int;
      // forPgeId cannot return null, so every row gets a key. There is no
      // "unkeyable" case to count here - reporting one would mislead anyone
      // reading this log while chasing a lost favourite.
      final ref = CatalogRef.fromSource(row['source'] as String?) ??
          CatalogRef.forPgeId(id);

      final kept = keptFor[ref];
      if (kept != null) {
        if (favourite(row) == 1) favouritesDropped++;
        batch.delete(_pgeSitesTable, where: 'id = ?', whereArgs: [id]);
        collided++;
        LoggingService.database('MIGRATE',
            'Dropped duplicate catalogue row $id for $ref, keeping $kept');
        continue;
      }

      keptFor[ref] = id;
      batch.update(
        _pgeSitesTable,
        {'ref': ref, 'provider': CatalogRef.providerOf(ref)},
        where: 'id = ?',
        whereArgs: [id],
      );
      keyed++;
    }

    await batch.commit(noResult: true);

    LoggingService.structured('CATALOG_REF_BACKFILL', {
      'rows_keyed': keyed,
      'rows_collided_deleted': collided,
      // Non-zero only if an install held two favourited rows for one launch.
      // Called out rather than folded into the count above, because this is the
      // pilot's own data going missing.
      'favourites_dropped_in_collision': favouritesDropped,
    });
  }

  /// Initialize PGE sites tables if they don't exist
  Future<void> initializeTables() async {
    final db = await DatabaseHelper.instance.database;

    LoggingService.info('[PGE_SITES_DB] Initializing PGE sites tables');

    try {
      // Create pge_sites table with minimal schema matching CSV format
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_pgeSitesTable (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          longitude REAL NOT NULL,
          latitude REAL NOT NULL,
          altitude INTEGER,
          country TEXT,
          is_favorite INTEGER DEFAULT 0,

          -- Wind direction ratings (0=no good, 1=good, 2=excellent)
          wind_n INTEGER DEFAULT 0,
          wind_ne INTEGER DEFAULT 0,
          wind_e INTEGER DEFAULT 0,
          wind_se INTEGER DEFAULT 0,
          wind_s INTEGER DEFAULT 0,
          wind_sw INTEGER DEFAULT 0,
          wind_w INTEGER DEFAULT 0,
          wind_nw INTEGER DEFAULT 0,

          -- Which guides contributed this launch, e.g.
          -- "pge:4632;ansg:106-28". Rows can now come from more than
          -- one guide, so a site's origin is no longer implicit.
          source TEXT,

          -- Why a guide says this launch is shut, verbatim. Carried rather
          -- than the site being dropped: dropping it left the other guides'
          -- entries for the same place on the map with nothing to say it was
          -- closed, which is worse than either source alone.
          closed TEXT,

          -- Retained only so existing installs upgrade without a rebuild;
          -- nothing reads it since the incremental sync was retired.
          last_edit TEXT
        )
      ''');

      // Existing installs created this table before `source` existed.
      await _addColumnIfMissing(db, _pgeSitesTable, 'source', 'TEXT');
      await _addColumnIfMissing(db, _pgeSitesTable, 'closed', 'TEXT');

      // The catalogue's real key: the contributing guide's own identifier, e.g.
      // 'pge:4632'. See [CatalogRef]. The integer `id` column is retained only
      // because it is this table's rowid; nothing reads it, and the CSV's `id`
      // is no longer imported at all - it is a row number, so it moves whenever
      // the producer's output does.
      //
      // UNIQUE rather than PRIMARY KEY because a key cannot be added to an
      // existing table without rebuilding it, and a unique index is what
      // ON CONFLICT(ref) needs anyway.
      await _addColumnIfMissing(db, _pgeSitesTable, 'ref', 'TEXT');
      await _addColumnIfMissing(db, _pgeSitesTable, 'provider', 'TEXT');
      await _backfillRefs(db);
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_pge_sites_ref
        ON $_pgeSitesTable(ref)
      ''');

      // Create spatial indexes
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_pge_sites_spatial
        ON $_pgeSitesTable(latitude, longitude)
      ''');

      // Removed country and capabilities indexes as those columns no longer exist

      // Create composite index on wind directions for efficient wind-based queries
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_pge_sites_wind
        ON $_pgeSitesTable(wind_n, wind_ne, wind_e, wind_se, wind_s, wind_sw, wind_w, wind_nw)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_pge_sites_name
        ON $_pgeSitesTable(name)
      ''');

      // Create favorites index for fast favorite queries
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_pge_sites_favorite
        ON $_pgeSitesTable(is_favorite)
      ''');

      // Create metadata table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_pgeSitesMetadataTable (
          id INTEGER PRIMARY KEY,
          download_url TEXT NOT NULL,
          downloaded_at TEXT,
          file_size_bytes INTEGER,
          sites_count INTEGER,
          index_size_bytes INTEGER,
          version TEXT,
          status TEXT DEFAULT 'pending'
        )
      ''');

      // Create country codes table for ISO 3166-1 alpha-2 mappings
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_countryCodesTable (
          code TEXT PRIMARY KEY,
          name TEXT NOT NULL
        )
      ''');

      // Create index for country code lookups
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_country_codes_code
        ON $_countryCodesTable(code)
      ''');

      // Initialize country codes if table is empty
      await _initializeCountryCodes(db);

      LoggingService.info('[PGE_SITES_DB] Tables and indexes created successfully');

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to initialize tables', error, stackTrace);
      rethrow;
    }
  }

  /// Initialize country codes table with ISO 3166-1 alpha-2 mappings
  Future<void> _initializeCountryCodes(Database db) async {
    try {
      // Check if country codes are already populated
      final existingCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_countryCodesTable')
      ) ?? 0;

      if (existingCount > 0) {
        LoggingService.info('[PGE_SITES_DB] Country codes already initialized: $existingCount countries');
        return;
      }

      LoggingService.info('[PGE_SITES_DB] Initializing country codes table');

      // Insert country codes using batch for performance
      final batch = db.batch();

      // ISO 3166-1 alpha-2 country codes (simplified names for readability)
      final countryCodes = {
        'AD': 'Andorra', 'AE': 'United Arab Emirates', 'AF': 'Afghanistan',
        'AG': 'Antigua and Barbuda', 'AI': 'Anguilla', 'AL': 'Albania',
        'AM': 'Armenia', 'AO': 'Angola', 'AQ': 'Antarctica',
        'AR': 'Argentina', 'AS': 'American Samoa', 'AT': 'Austria',
        'AU': 'Australia', 'AW': 'Aruba', 'AX': 'Åland Islands',
        'AZ': 'Azerbaijan', 'BA': 'Bosnia and Herzegovina', 'BB': 'Barbados',
        'BD': 'Bangladesh', 'BE': 'Belgium', 'BF': 'Burkina Faso',
        'BG': 'Bulgaria', 'BH': 'Bahrain', 'BI': 'Burundi',
        'BJ': 'Benin', 'BL': 'Saint Barthélemy', 'BM': 'Bermuda',
        'BN': 'Brunei', 'BO': 'Bolivia', 'BQ': 'Bonaire',
        'BR': 'Brazil', 'BS': 'Bahamas', 'BT': 'Bhutan',
        'BV': 'Bouvet Island', 'BW': 'Botswana', 'BY': 'Belarus',
        'BZ': 'Belize', 'CA': 'Canada', 'CC': 'Cocos Islands',
        'CD': 'Congo (DRC)', 'CF': 'Central African Republic', 'CG': 'Congo',
        'CH': 'Switzerland', 'CI': 'Côte d\'Ivoire', 'CK': 'Cook Islands',
        'CL': 'Chile', 'CM': 'Cameroon', 'CN': 'China',
        'CO': 'Colombia', 'CR': 'Costa Rica', 'CU': 'Cuba',
        'CV': 'Cabo Verde', 'CW': 'Curaçao', 'CX': 'Christmas Island',
        'CY': 'Cyprus', 'CZ': 'Czech Republic', 'DE': 'Germany',
        'DJ': 'Djibouti', 'DK': 'Denmark', 'DM': 'Dominica',
        'DO': 'Dominican Republic', 'DZ': 'Algeria', 'EC': 'Ecuador',
        'EE': 'Estonia', 'EG': 'Egypt', 'EH': 'Western Sahara',
        'ER': 'Eritrea', 'ES': 'Spain', 'ET': 'Ethiopia',
        'FI': 'Finland', 'FJ': 'Fiji', 'FK': 'Falkland Islands',
        'FM': 'Micronesia', 'FO': 'Faroe Islands', 'FR': 'France',
        'GA': 'Gabon', 'GB': 'United Kingdom', 'GD': 'Grenada',
        'GE': 'Georgia', 'GF': 'French Guiana', 'GG': 'Guernsey',
        'GH': 'Ghana', 'GI': 'Gibraltar', 'GL': 'Greenland',
        'GM': 'Gambia', 'GN': 'Guinea', 'GP': 'Guadeloupe',
        'GQ': 'Equatorial Guinea', 'GR': 'Greece', 'GS': 'South Georgia',
        'GT': 'Guatemala', 'GU': 'Guam', 'GW': 'Guinea-Bissau',
        'GY': 'Guyana', 'HK': 'Hong Kong', 'HM': 'Heard Island',
        'HN': 'Honduras', 'HR': 'Croatia', 'HT': 'Haiti',
        'HU': 'Hungary', 'ID': 'Indonesia', 'IE': 'Ireland',
        'IL': 'Israel', 'IM': 'Isle of Man', 'IN': 'India',
        'IO': 'British Indian Ocean Territory', 'IQ': 'Iraq', 'IR': 'Iran',
        'IS': 'Iceland', 'IT': 'Italy', 'JE': 'Jersey',
        'JM': 'Jamaica', 'JO': 'Jordan', 'JP': 'Japan',
        'KE': 'Kenya', 'KG': 'Kyrgyzstan', 'KH': 'Cambodia',
        'KI': 'Kiribati', 'KM': 'Comoros', 'KN': 'Saint Kitts and Nevis',
        'KP': 'North Korea', 'KR': 'South Korea', 'KW': 'Kuwait',
        'KY': 'Cayman Islands', 'KZ': 'Kazakhstan', 'LA': 'Laos',
        'LB': 'Lebanon', 'LC': 'Saint Lucia', 'LI': 'Liechtenstein',
        'LK': 'Sri Lanka', 'LR': 'Liberia', 'LS': 'Lesotho',
        'LT': 'Lithuania', 'LU': 'Luxembourg', 'LV': 'Latvia',
        'LY': 'Libya', 'MA': 'Morocco', 'MC': 'Monaco',
        'MD': 'Moldova', 'ME': 'Montenegro', 'MF': 'Saint Martin',
        'MG': 'Madagascar', 'MH': 'Marshall Islands', 'MK': 'North Macedonia',
        'ML': 'Mali', 'MM': 'Myanmar', 'MN': 'Mongolia',
        'MO': 'Macao', 'MP': 'Northern Mariana Islands', 'MQ': 'Martinique',
        'MR': 'Mauritania', 'MS': 'Montserrat', 'MT': 'Malta',
        'MU': 'Mauritius', 'MV': 'Maldives', 'MW': 'Malawi',
        'MX': 'Mexico', 'MY': 'Malaysia', 'MZ': 'Mozambique',
        'NA': 'Namibia', 'NC': 'New Caledonia', 'NE': 'Niger',
        'NF': 'Norfolk Island', 'NG': 'Nigeria', 'NI': 'Nicaragua',
        'NL': 'Netherlands', 'NO': 'Norway', 'NP': 'Nepal',
        'NR': 'Nauru', 'NU': 'Niue', 'NZ': 'New Zealand',
        'OM': 'Oman', 'PA': 'Panama', 'PE': 'Peru',
        'PF': 'French Polynesia', 'PG': 'Papua New Guinea', 'PH': 'Philippines',
        'PK': 'Pakistan', 'PL': 'Poland', 'PM': 'Saint Pierre and Miquelon',
        'PN': 'Pitcairn', 'PR': 'Puerto Rico', 'PS': 'Palestine',
        'PT': 'Portugal', 'PW': 'Palau', 'PY': 'Paraguay',
        'QA': 'Qatar', 'RE': 'Réunion', 'RO': 'Romania',
        'RS': 'Serbia', 'RU': 'Russia', 'RW': 'Rwanda',
        'SA': 'Saudi Arabia', 'SB': 'Solomon Islands', 'SC': 'Seychelles',
        'SD': 'Sudan', 'SE': 'Sweden', 'SG': 'Singapore',
        'SH': 'Saint Helena', 'SI': 'Slovenia', 'SJ': 'Svalbard and Jan Mayen',
        'SK': 'Slovakia', 'SL': 'Sierra Leone', 'SM': 'San Marino',
        'SN': 'Senegal', 'SO': 'Somalia', 'SR': 'Suriname',
        'SS': 'South Sudan', 'ST': 'Sao Tome and Principe', 'SV': 'El Salvador',
        'SX': 'Sint Maarten', 'SY': 'Syria', 'SZ': 'Eswatini',
        'TC': 'Turks and Caicos Islands', 'TD': 'Chad', 'TF': 'French Southern Territories',
        'TG': 'Togo', 'TH': 'Thailand', 'TJ': 'Tajikistan',
        'TK': 'Tokelau', 'TL': 'Timor-Leste', 'TM': 'Turkmenistan',
        'TN': 'Tunisia', 'TO': 'Tonga', 'TR': 'Turkey',
        'TT': 'Trinidad and Tobago', 'TV': 'Tuvalu', 'TW': 'Taiwan',
        'TZ': 'Tanzania', 'UA': 'Ukraine', 'UG': 'Uganda',
        'UM': 'United States Minor Outlying Islands', 'US': 'United States', 'UY': 'Uruguay',
        'UZ': 'Uzbekistan', 'VA': 'Vatican City', 'VC': 'Saint Vincent and the Grenadines',
        'VE': 'Venezuela', 'VG': 'British Virgin Islands', 'VI': 'U.S. Virgin Islands',
        'VN': 'Vietnam', 'VU': 'Vanuatu', 'WF': 'Wallis and Futuna',
        'WS': 'Samoa', 'YE': 'Yemen', 'YT': 'Mayotte',
        'ZA': 'South Africa', 'ZM': 'Zambia', 'ZW': 'Zimbabwe',
      };

      countryCodes.forEach((code, name) {
        batch.insert(
          _countryCodesTable,
          {'code': code, 'name': name},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      });

      await batch.commit(noResult: true);

      LoggingService.info('[PGE_SITES_DB] Initialized ${countryCodes.length} country codes');

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to initialize country codes', error, stackTrace);
      // Non-critical error - continue without country name conversion
    }
  }

  /// Import sites data from downloaded CSV
  ///
  /// [rows] exists so tests can drive this exact transaction - the delete,
  /// the favourite carry-over and the one-time relink - rather than a
  /// reimplementation of it. Production always parses the bundled catalogue.
  ///
  /// [snapshotIsComplete] is false when the parser dropped rows on the way in.
  /// Absence then means "this snapshot lost it", not "the producer withdrew it",
  /// and the two must not be confused: withdrawal deletes the catalogue row and
  /// the favourite sitting on it. A stale row that lingers until the next clean
  /// snapshot costs the pilot nothing; a deleted favourite is theirs and gone.
  Future<bool> importSitesData({
    @visibleForTesting List<Map<String, dynamic>>? rows,
    @visibleForTesting bool snapshotIsComplete = true,
  }) async {
    PerformanceMonitor.startOperation('PgeSitesImport');
    final stopwatch = Stopwatch()..start();

    try {
      // Parse downloaded data
      final snapshot = rows != null
          ? CatalogSnapshot(rows: rows, skipped: snapshotIsComplete ? 0 : 1)
          : await PgeSitesDownloadService.instance.parseDownloadedData();
      final sitesData = snapshot.rows;
      final mayDelete = snapshot.isComplete;

      if (sitesData.isEmpty) {
        LoggingService.warning('[PGE_SITES_DB] No sites data to import');
        return false;
      }

      final db = await DatabaseHelper.instance.database;

      LoggingService.info('[PGE_SITES_DB] Starting import of ${sitesData.length} sites');

      // Upsert on the catalogue's stable key, then remove whatever the snapshot
      // no longer lists.
      //
      // This used to delete the table and re-insert, which is why the favourites
      // had to be read out and written back - and why a rebuilt catalogue could
      // hand a flown site another launch's data, since the rows came back under
      // new positional ids. Keying on `ref` removes both problems at once:
      // is_favorite is never deleted, so it survives structurally rather than by
      // being copied, and a row keeps its identity across a rebuild.
      //
      // `sites.catalog_ref` is deliberately left alone. A ref that vanishes is
      // simply absent from the LEFT JOIN, which shows the pilot no wind or
      // altitude - and because refs are never reused, the link starts working
      // again by itself if the guide restores the entry. Clearing it would make
      // that unrecoverable.
      var inserted = 0;
      var updated = 0;
      var unkeyable = 0;
      var deleted = 0;
      var superseded = 0;

      await db.transaction((txn) async {
        // Key anything still unkeyed before matching on refs. initializeTables
        // does this for the rows an upgrade inherits, but the invariant belongs
        // here too: this is the only place rows are written, and a row that
        // reaches the upsert without a ref cannot be matched, so its favourite
        // would be stranded on a row the delete step then leaves behind.
        await _backfillRefs(txn);

        final existingRefs = (await txn.query(_pgeSitesTable, columns: ['ref']))
            .map((row) => row['ref'] as String?)
            .whereType<String>()
            .toSet();
        // Frozen before the loop. `existingRefs` grows as the snapshot is keyed
        // below, and a ref this import has just introduced is not evidence that
        // the database already held the row.
        final priorRefs = Set<String>.of(existingRefs);
        final snapshotRefs = <String>{};
        // Tokens a surviving row names but is not keyed on, so the delete step
        // can tell a merge apart from a withdrawal.
        final supersededBy = <String, String>{};

        final batch = txn.batch();
        for (final siteData in sitesData) {
          // The CSV's own `id` is not imported: it is a row number that moves
          // whenever the producer's output does.
          //
          // A row the database already holds keeps the key it is stored under,
          // instead of being re-derived from precedence every import. A launch
          // first described only by `ansg:106-28` gains `pge:4632` the day PGE
          // picks it up - routine as federation grows - and precedence alone
          // would rename the row. A rename here is a delete plus an insert: the
          // favourite goes with the deleted row, and every `sites.catalog_ref`
          // pointing at it dangles for good, because the old key is never
          // emitted again. Precedence therefore only keys rows that are new.
          // Three rules, in this order, and the order is the point:
          //
          //  1. a row this database already holds keeps the key it is stored
          //     under, whatever the catalogue now says. Re-keying is a delete
          //     plus an insert, which takes the favourite with it and dangles
          //     every sites.catalog_ref for good;
          //  2. otherwise the key the producer emitted. It decides, so that one
          //     side owns the policy - and it derives it from the same
          //     precedence this app used to apply itself;
          //  3. otherwise derive it, for a catalogue published before the column
          //     existed. That is the bundled asset of an older release, so it is
          //     the offline path rather than a hypothetical.
          final tokens = CatalogRef.tokensOf(siteData['source'] as String?);
          final held = tokens.where(priorRefs.contains);
          final ref = held.isNotEmpty
              ? held.first
              : (siteData['ref'] as String?) ??
                  CatalogRef.fromSource(siteData['source'] as String?);
          if (ref == null) {
            unkeyable++;
            continue;
          }
          snapshotRefs.add(ref);
          // Every other token on this row names the same launch.
          for (final token in tokens) {
            if (token != ref) supersededBy[token] = ref;
          }
          // add() reports whether the ref is new to this batch, so a ref
          // appearing twice in one snapshot counts as one insert and one update
          // rather than two inserts - the upsert is what actually happens, and
          // the audit log should say so.
          existingRefs.add(ref) ? inserted++ : updated++;

          batch.rawInsert('''
            INSERT INTO $_pgeSitesTable
              (ref, provider, name, longitude, latitude, altitude, country,
               wind_n, wind_ne, wind_e, wind_se, wind_s, wind_sw, wind_w, wind_nw,
               source, closed)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(ref) DO UPDATE SET
              provider = excluded.provider,
              name = excluded.name,
              longitude = excluded.longitude,
              latitude = excluded.latitude,
              altitude = excluded.altitude,
              country = excluded.country,
              wind_n = excluded.wind_n, wind_ne = excluded.wind_ne,
              wind_e = excluded.wind_e, wind_se = excluded.wind_se,
              wind_s = excluded.wind_s, wind_sw = excluded.wind_sw,
              wind_w = excluded.wind_w, wind_nw = excluded.wind_nw,
              source = excluded.source,
              closed = excluded.closed
          ''', [
            ref,
            CatalogRef.providerOf(ref),
            siteData['name'],
            siteData['longitude'],
            siteData['latitude'],
            siteData['altitude'],
            siteData['country'],
            siteData['wind_n'] ?? 0,
            siteData['wind_ne'] ?? 0,
            siteData['wind_e'] ?? 0,
            siteData['wind_se'] ?? 0,
            siteData['wind_s'] ?? 0,
            siteData['wind_sw'] ?? 0,
            siteData['wind_w'] ?? 0,
            siteData['wind_nw'] ?? 0,
            siteData['source'],
            siteData['closed'],
          ]);
        }
        await batch.commit(noResult: true);

        for (final gone in mayDelete ? priorRefs.difference(snapshotRefs) : <String>{}) {
          final successor = supersededBy[gone];
          if (successor != null) {
            // Two guides' entries merged into one catalogue row. The launch did
            // not go away, so neither should the favourite nor the flown site's
            // link. Unlike the positional relink this change removed, the two
            // keys are known to name one launch, because the surviving row
            // still lists the old key in its own `source`.
            await txn.rawUpdate(
              'UPDATE $_pgeSitesTable SET is_favorite = 1 WHERE ref = ? AND '
              'EXISTS (SELECT 1 FROM $_pgeSitesTable WHERE ref = ? '
              'AND is_favorite = 1)',
              [successor, gone],
            );
            await txn.update('sites', {'catalog_ref': successor},
                where: 'catalog_ref = ?', whereArgs: [gone]);
            superseded++;
          }
          deleted += await txn
              .delete(_pgeSitesTable, where: 'ref = ?', whereArgs: [gone]);
        }
      });

      // Replaces the old CATALOG_RELINK log. "Favourites survived" is a claim
      // about the user's own data, so it needs evidence here rather than
      // confidence - a silent rewrite cannot be checked afterwards.
      final favourites = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM $_pgeSitesTable WHERE is_favorite = 1'));
      final dangling = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM sites s WHERE s.catalog_ref IS NOT NULL '
        'AND NOT EXISTS (SELECT 1 FROM $_pgeSitesTable c WHERE c.ref = s.catalog_ref)',
      ));

      LoggingService.structured('CATALOG_IMPORT', {
        'rows_inserted': inserted,
        'rows_updated': updated,
        'rows_deleted': deleted,
        'rows_superseded_by_merge': superseded,
        'rows_unkeyable_skipped': unkeyable,
        // Absent rows were left alone because the snapshot arrived incomplete.
        // Called out so a catalogue that quietly stops shrinking is traceable.
        'deletions_suppressed': !mayDelete,
        'favourites_held': favourites ?? 0,
        'site_links_dangling': dangling ?? 0,
      });

      // The matcher caches flight-log sites, and each cached entry carries a
      // copy of its site's catalog_ref (Site.toParaglidingSite). A fresh import
      // can turn a dangling ref live again, so the cache must not outlive it.
      //
      // Invalidated rather than reloaded: reload() awaits initialize(), which
      // awaits AppInitializationService.initializeInBackground() - and that is
      // often the very call that is running this import. Awaiting its own
      // memoised future would deadlock. Dropping the cache is synchronous, and
      // the next match rebuilds it.
      SiteMatchingService.instance.invalidate();

      stopwatch.stop();

      // Update metadata
      await _updateImportMetadata(sitesData.length);

      LoggingService.performance(
        'PGE Sites Import',
        stopwatch.elapsed,
        'Imported ${sitesData.length} sites'
      );

      LoggingService.structured('PGE_SITES_IMPORTED', {
        'sites_count': sitesData.length,
        'import_duration_ms': stopwatch.elapsedMilliseconds,
      });

      PerformanceMonitor.endOperation('PgeSitesImport', metadata: {
        'success': true,
        'sites_imported': sitesData.length,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });

      return true;

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to import sites data', error, stackTrace);

      PerformanceMonitor.endOperation('PgeSitesImport', metadata: {
        'success': false,
        'error': error.toString(),
      });

      return false;
    }
  }

  /// Get sites within bounding box (primary map query)
  Future<List<ParaglidingSite>> getSitesInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    PerformanceMonitor.startOperation('PgeSitesQuery_Bounds');
    final stopwatch = Stopwatch()..start();

    try {
      final db = await DatabaseHelper.instance.database;

      // Build query with optional wind direction filtering
      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];

      // Spatial bounds
      whereConditions.add('latitude BETWEEN ? AND ?');
      whereArgs.addAll([south, north]);

      whereConditions.add('longitude BETWEEN ? AND ?');
      whereArgs.addAll([west, east]);

      // All sites are paragliding sites now (column removed)

      final whereClause = whereConditions.join(' AND ');

      // Query with LEFT JOIN to get country names
      final results = await db.rawQuery('''
        SELECT
          s.*,
          COALESCE(cc.name, s.country) as country_name
        FROM $_pgeSitesTable s
        LEFT JOIN $_countryCodesTable cc ON UPPER(s.country) = cc.code
        WHERE $whereClause
      ''', whereArgs);

      stopwatch.stop();

      final sites = results.map((row) => _mapRowToParaglidingSite(row)).toList();

      // Single consolidated performance log
      PerformanceMonitor.endOperation('PgeSitesQuery_Bounds', metadata: {
        'sites_found': sites.length,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });

      return sites;

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Bounds query failed', error, stackTrace);

      PerformanceMonitor.endOperation('PgeSitesQuery_Bounds', metadata: {
        'success': false,
        'error': error.toString(),
      });

      return [];
    }
  }

  /// Search sites by name with optional geographic proximity
  Future<List<ParaglidingSite>> searchSitesByName({
    required String query,
    double? centerLatitude,
    double? centerLongitude,
    int limit = 20,
  }) async {
    PerformanceMonitor.startOperation('PgeSitesQuery_Search');

    try {
      final db = await DatabaseHelper.instance.database;

      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];

      // Name search
      whereConditions.add('s.name LIKE ?');
      whereArgs.add('%$query%');

      // All sites are paragliding sites now (column removed)

      final whereClause = whereConditions.join(' AND ');

      // Build ORDER BY clause
      String orderBy = 's.name';
      if (centerLatitude != null && centerLongitude != null) {
        // Order by proximity using simple distance calculation
        orderBy = '(ABS(s.latitude - $centerLatitude) + ABS(s.longitude - $centerLongitude)), s.name';
      }

      // Query with LEFT JOIN to get country names
      final results = await db.rawQuery('''
        SELECT
          s.*,
          COALESCE(cc.name, s.country) as country_name
        FROM $_pgeSitesTable s
        LEFT JOIN $_countryCodesTable cc ON UPPER(s.country) = cc.code
        WHERE $whereClause
        ORDER BY $orderBy
        LIMIT $limit
      ''', whereArgs);

      final sites = results.map((row) => _mapRowToParaglidingSite(row)).toList();

      LoggingService.structured('PGE_SITES_SEARCH_QUERY', {
        'query': query,
        'sites_found': sites.length,
        'has_center_point': centerLatitude != null && centerLongitude != null,
      });

      PerformanceMonitor.endOperation('PgeSitesQuery_Search', metadata: {
        'sites_found': sites.length,
        'query_length': query.length,
      });

      return sites;

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Search query failed', error, stackTrace);

      PerformanceMonitor.endOperation('PgeSitesQuery_Search', metadata: {
        'success': false,
        'error': error.toString(),
      });

      return [];
    }
  }

  /// Find nearest site to coordinates
  Future<ParaglidingSite?> findNearestSite({
    required double latitude,
    required double longitude,
    double maxDistanceKm = 0.5,
  }) async {
    try {
      final tolerance = maxDistanceKm / 111.0; // Approximate degrees per km

      final sites = await getSitesInBounds(
        north: latitude + tolerance,
        south: latitude - tolerance,
        east: longitude + tolerance,
        west: longitude - tolerance,
      );

      if (sites.isEmpty) return null;

      // Find closest site by distance
      ParaglidingSite? nearest;
      double minDistance = double.infinity;

      for (final site in sites) {
        final distance = site.distanceTo(latitude, longitude);
        if (distance < minDistance) {
          minDistance = distance;
          nearest = site;
        }
      }

      // Check distance constraint
      if (nearest != null && minDistance <= maxDistanceKm * 1000) {
        return nearest;
      }

      return null;

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Nearest site query failed', error, stackTrace);
      return null;
    }
  }

  /// Get database statistics
  Future<Map<String, dynamic>> getDatabaseStats() async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Get sites count
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM $_pgeSitesTable');
      final sitesCount = countResult.first['count'] as int;

      // Get database file size
      final dbPath = db.path;
      final dbFile = File(dbPath);
      final dbSize = await dbFile.exists() ? (await dbFile.stat()).size : 0;

      // Get metadata
      final metadataResult = await db.query(
        _pgeSitesMetadataTable,
        orderBy: 'downloaded_at DESC',
        limit: 1,
      );

      final metadata = metadataResult.isNotEmpty ? metadataResult.first : null;

      return {
        'sites_count': sitesCount,
        'database_size_bytes': dbSize,
        'last_imported_at': metadata?['downloaded_at'],
        'import_status': metadata?['status'] ?? 'not_imported',
        'source_file_size_bytes': metadata?['file_size_bytes'] ?? 0,
      };

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to get database stats', error, stackTrace);
      return {
        'sites_count': 0,
        'database_size_bytes': 0,
        'error': error.toString(),
      };
    }
  }

  /// Update import metadata
  Future<void> _updateImportMetadata(int sitesCount) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final downloadStatus = await PgeSitesDownloadService.instance.getDownloadStatus();

      final metadata = {
        'download_url': PgeSitesConfig.assetPath,  // Use existing column name
        'downloaded_at': DateTime.now().toIso8601String(),
        'sites_count': sitesCount,
        'file_size_bytes': downloadStatus['file_size_bytes'] ?? 0,
        'status': 'completed',
        'version': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      // Clear existing metadata and insert new
      await db.delete(_pgeSitesMetadataTable);
      await db.insert(_pgeSitesMetadataTable, metadata);

    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to update metadata', error, stackTrace);
    }
  }

  /// Convert database row to ParaglidingSite model
  ParaglidingSite _mapRowToParaglidingSite(Map<String, dynamic> row) {
    // Build wind directions list
    final windDirections = <String>[];
    final windMap = {
      'N': row['wind_n'] ?? 0,
      'NE': row['wind_ne'] ?? 0,
      'E': row['wind_e'] ?? 0,
      'SE': row['wind_se'] ?? 0,
      'S': row['wind_s'] ?? 0,
      'SW': row['wind_sw'] ?? 0,
      'W': row['wind_w'] ?? 0,
      'NW': row['wind_nw'] ?? 0,
    };

    windMap.forEach((direction, value) {
      if (value != null && value >= 1) {
        windDirections.add(direction);
      }
    });

    return ParaglidingSite(
      // The catalogue row's identity is its ref, not its rowid: the rowid comes
      // from insertion order and means nothing across a rebuild. `id` is left
      // null so nothing can accidentally key on it - ParaglidingSite.id means
      // "a row in the pilot's own sites table" everywhere else.
      catalogRef: row['ref'] as String?,
      name: row['name'] as String? ?? 'Unknown Site',
      latitude: (row['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (row['longitude'] as num?)?.toDouble() ?? 0.0,
      altitude: row['altitude'] as int?,  // Now stored in database
      description: '', // Not available from PGE API
      windDirections: windDirections,
      siteType: 'launch', // PGE sites are primarily launch sites
      rating: null,
      country: row['country_name'] as String? ?? row['country'] as String?,  // Use full name from JOIN or fallback to code
      source: row['source'] as String?,
      closed: row['closed'] as String?,
      region: null,
      popularity: null,
    );
  }

  /// Check if local database is available and up to date
  Future<bool> isDataAvailable() async {
    try {
      final stats = await getDatabaseStats();
      return stats['sites_count'] > 0;
    } catch (e) {
      return false;
    }
  }

  /// Clear all PGE sites data
  Future<void> clearData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(_pgeSitesTable);
      await db.delete(_pgeSitesMetadataTable);
      LoggingService.info('[PGE_SITES_DB] Cleared all PGE sites data');
    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to clear data', error, stackTrace);
    }
  }

  /// Toggle favorite status for a catalogue entry, by its [CatalogRef].
  Future<void> toggleSiteFavorite(String ref) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.execute(
        'UPDATE $_pgeSitesTable SET is_favorite = CASE WHEN is_favorite = 1 THEN 0 ELSE 1 END WHERE ref = ?',
        [ref]
      );
      LoggingService.action('Favorites', 'toggle_catalog_site', {'ref': ref});
    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to toggle favorite', error, stackTrace);
      rethrow;
    }
  }

  /// Check if a catalogue entry is favorited, by its [CatalogRef].
  Future<bool> isSiteFavorite(String ref) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query(
        _pgeSitesTable,
        columns: ['is_favorite'],
        where: 'ref = ?',
        whereArgs: [ref]
      );
      return result.isNotEmpty && result.first['is_favorite'] == 1;
    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to check favorite status', error, stackTrace);
      return false;
    }
  }

  /// Get all favorite PGE sites
  /// The catalogue entry a flown site is linked to.
  ///
  /// A flown site carries only what its IGC gave it - a name and the takeoff
  /// coordinates - so on its own it knows nothing about which guides describe
  /// the launch, and its position can be a hundred metres from the guide's
  /// pin. Both matter to the details dialog, so it resolves the catalogue row
  /// rather than working from the flown record.
  Future<ParaglidingSite?> getSiteByRef(String ref) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT s.*, COALESCE(cc.name, s.country) as country_name
      FROM $_pgeSitesTable s
      LEFT JOIN $_countryCodesTable cc ON UPPER(s.country) = cc.code
      WHERE s.ref = ?
      LIMIT 1
    ''', [ref]);
    if (rows.isEmpty) return null;
    return _mapRowToParaglidingSite(rows.first);
  }

  /// A guide's own id for a catalogue entry, e.g. `sourceIdFor('pge:4632',
  /// 'ansg')`.
  ///
  /// A ref names one guide, so a request destined for a *different* guide still
  /// has to be translated through `source`. Handing the wrong guide an id it
  /// did not issue silently addresses another site altogether.
  Future<String?> sourceIdFor(String ref, String provider) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      _pgeSitesTable,
      columns: ['source'],
      where: 'ref = ?',
      whereArgs: [ref],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    // Tokenised by CatalogRef, not split here: `source` is stored verbatim as
    // the producer wrote it, so a provider it has since renamed still appears
    // under the old prefix. Comparing the raw string against the current name
    // would quietly find nothing.
    for (final token in CatalogRef.tokensOf(rows.first['source'] as String?)) {
      if (token.startsWith('$provider:')) {
        return token.substring(provider.length + 1);
      }
    }
    return null;
  }

  Future<List<ParaglidingSite>> getFavoriteSites() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final results = await db.rawQuery('''
        SELECT s.*, COALESCE(cc.name, s.country) as country_name
        FROM $_pgeSitesTable s
        LEFT JOIN $_countryCodesTable cc ON UPPER(s.country) = cc.code
        WHERE s.is_favorite = 1
      ''');

      final sites = results.map((row) => _mapRowToParaglidingSite(row)).toList();

      LoggingService.structured('PGE_SITES_FAVORITES_QUERY', {
        'favorites_count': sites.length,
      });

      return sites;
    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to get favorite sites', error, stackTrace);
      return [];
    }
  }
}