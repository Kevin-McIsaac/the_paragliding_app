import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../services/logging_service.dart';

class DatabaseHelper {
  static const _databaseName = "FlightLog.db";
  static const _databaseVersion = 2; // v2: Added pge_site_id foreign key for deduplication

  // Singleton pattern
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async => _database ??= await _initDatabase();

  /// Initialize database with v1.0 schema
  ///
  /// PRE-RELEASE STRATEGY: No migrations needed since app hasn't been released.
  /// All schema changes during development require clearing app data.
  ///
  /// POST-RELEASE STRATEGY: Start migrations from v2 when app is released.
  /// This ensures a clean baseline for production users.
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    LoggingService.database('INIT', 'Opening database at: $path');

    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE flights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        launch_time TEXT NOT NULL,
        landing_time TEXT NOT NULL,
        duration INTEGER NOT NULL,
        launch_site_id INTEGER,
        launch_latitude REAL,
        launch_longitude REAL,
        launch_altitude REAL,
        landing_latitude REAL,
        landing_longitude REAL,
        landing_altitude REAL,
        landing_description TEXT,
        max_altitude REAL,
        max_climb_rate REAL,
        max_sink_rate REAL,
        max_climb_rate_5_sec REAL,
        max_sink_rate_5_sec REAL,
        distance REAL,
        straight_distance REAL,
        fai_triangle_distance REAL,
        fai_triangle_points TEXT,
        wing_id INTEGER,
        notes TEXT,
        track_log_path TEXT,
        original_filename TEXT,
        source TEXT CHECK(source IN ('manual', 'igc', 'parajournal')),
        timezone TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        max_ground_speed REAL,
        avg_ground_speed REAL,
        thermal_count INTEGER,
        avg_thermal_strength REAL,
        total_time_in_thermals INTEGER,
        best_thermal REAL,
        avg_ld REAL,
        longest_glide REAL,
        climb_percentage REAL,
        gps_fix_quality REAL,
        recording_interval REAL,
        takeoff_index INTEGER,
        landing_index INTEGER,
        detected_takeoff_time TEXT,
        detected_landing_time TEXT,
        closing_point_index INTEGER,
        closing_distance REAL,
        FOREIGN KEY (launch_site_id) REFERENCES sites (id),
        FOREIGN KEY (wing_id) REFERENCES wings (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE sites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        country TEXT,
        custom_name INTEGER DEFAULT 0,
        pge_site_id INTEGER,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE wings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        manufacturer TEXT,
        model TEXT,
        size TEXT,
        color TEXT,
        purchase_date TEXT,
        active INTEGER DEFAULT 1,
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE wing_aliases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wing_id INTEGER NOT NULL,
        alias_name TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (wing_id) REFERENCES wings (id) ON DELETE CASCADE,
        UNIQUE(alias_name)
      )
    ''');

    // Create country codes table for ISO 3166-1 alpha-2 mappings (shared with PGE database)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS country_codes (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');

    // Initialize country codes
    await _initializeCountryCodes(db);

    // Create optimized indexes for query performance
    await _createIndexes(db);
  }
  
  /// Create database indexes for optimal query performance
  Future<void> _createIndexes(Database db) async {
    LoggingService.database('INDEX', 'Creating essential indexes');
    
    try {
      // Essential indexes for <5000 records
      
      // 1. Foreign key index for launch site joins (used in almost every query)
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_launch_site ON flights(launch_site_id)');
      
      // 2. Foreign key index for wing joins
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_wing ON flights(wing_id)');
      
      // 3. Composite index for most common query pattern: ORDER BY date DESC, launch_time DESC
      await db.execute('CREATE INDEX IF NOT EXISTS idx_flights_date_time ON flights(date DESC, launch_time DESC)');
      
      // 4. Index for wing aliases lookup
      await db.execute('CREATE INDEX IF NOT EXISTS idx_wing_aliases_wing_id ON wing_aliases(wing_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_wing_aliases_alias_name ON wing_aliases(alias_name)');

      // 5. Spatial indexes for sites table to optimize bounding box queries
      // These are critical for getSitesInBounds() performance
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_latitude ON sites(latitude)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_longitude ON sites(longitude)');
      // Composite index for the most common spatial query pattern
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_lat_lon ON sites(latitude, longitude)');

      // 6. Index for site name searches
      // Used in searchSitesByName() for autocomplete and site search features
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_name ON sites(name)');

      // 7. Index for PGE site foreign key relationship
      // Critical for deduplication and site linking operations
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_pge_site_id ON sites(pge_site_id)');

      // 8. Index for country code lookups
      await db.execute('CREATE INDEX IF NOT EXISTS idx_country_codes_code ON country_codes(code)');

      LoggingService.database('INDEX', 'Successfully created essential indexes');
    } catch (e) {
      LoggingService.error('DatabaseHelper: Failed to create indexes', e);
      rethrow;
    }
  }

  /// Initialize country codes table with ISO 3166-1 alpha-2 mappings
  Future<void> _initializeCountryCodes(Database db) async {
    try {
      // Check if country codes are already populated
      final existingCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM country_codes')
      ) ?? 0;

      if (existingCount > 0) {
        LoggingService.database('INIT', 'Country codes already initialized: $existingCount countries');
        return;
      }

      LoggingService.database('INIT', 'Initializing country codes table');

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
          'country_codes',
          {'code': code, 'name': name},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      });

      await batch.commit(noResult: true);

      LoggingService.database('INIT', 'Initialized ${countryCodes.length} country codes');

    } catch (error, stackTrace) {
      LoggingService.error('DatabaseHelper: Failed to initialize country codes', error, stackTrace);
      // Non-critical error - continue without country name conversion
    }
  }

  /// Handle database upgrades with migration logic
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    LoggingService.database('MIGRATE', 'Upgrading database from v$oldVersion to v$newVersion');

    try {
      // Migration from v1 to v2: Add pge_site_id foreign key
      if (oldVersion < 2) {
        LoggingService.database('MIGRATE', 'Applying migration v1 -> v2: Adding pge_site_id column');

        // Add pge_site_id column to sites table
        await db.execute('ALTER TABLE sites ADD COLUMN pge_site_id INTEGER');

        // Create index for the new foreign key column
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sites_pge_site_id ON sites(pge_site_id)');

        LoggingService.database('MIGRATE', 'Successfully added pge_site_id column and index');

        // Trigger data migration to match existing sites with PGE sites
        await _migrateExistingSitesToPgeMapping(db);
      }

      LoggingService.database('MIGRATE', 'Database migration completed successfully');
    } catch (e) {
      LoggingService.error('DatabaseHelper: Database migration failed', e);
      rethrow;
    }
  }

  /// Migrate existing sites to match with PGE sites using coordinate-based lookup
  Future<void> _migrateExistingSitesToPgeMapping(Database db) async {
    LoggingService.database('MIGRATE', 'Starting site-to-PGE mapping migration');

    try {
      // Check if PGE sites table exists and has data
      final pgeSitesExist = await db.rawQuery('''
        SELECT name FROM sqlite_master
        WHERE type='table' AND name='pge_sites'
      ''');

      if (pgeSitesExist.isEmpty) {
        LoggingService.database('MIGRATE', 'PGE sites table not found, skipping site mapping');
        return;
      }

      final pgeSitesCount = await db.rawQuery('SELECT COUNT(*) as count FROM pge_sites');
      final pgeCount = pgeSitesCount.first['count'] as int;

      if (pgeCount == 0) {
        LoggingService.database('MIGRATE', 'PGE sites table empty, skipping site mapping');
        return;
      }

      // Get all existing local sites
      final localSites = await db.query('sites', where: 'pge_site_id IS NULL');

      if (localSites.isEmpty) {
        LoggingService.database('MIGRATE', 'No local sites to migrate');
        return;
      }

      LoggingService.database('MIGRATE', 'Matching ${localSites.length} local sites with $pgeCount PGE sites');

      int matchedCount = 0;
      const double coordinateTolerance = 0.0001; // ~10m tolerance

      for (final localSite in localSites) {
        final lat = localSite['latitude'] as double;
        final lng = localSite['longitude'] as double;
        final siteId = localSite['id'] as int;

        // Find closest PGE site within tolerance
        final matches = await db.rawQuery('''
          SELECT id, latitude, longitude,
                 ABS(latitude - ?) + ABS(longitude - ?) as distance
          FROM pge_sites
          WHERE ABS(latitude - ?) < ? AND ABS(longitude - ?) < ?
          ORDER BY distance
          LIMIT 1
        ''', [lat, lng, lat, coordinateTolerance, lng, coordinateTolerance]);

        if (matches.isNotEmpty) {
          final pgeSiteId = matches.first['id'] as int;

          // Update the local site with the PGE site ID
          await db.update(
            'sites',
            {'pge_site_id': pgeSiteId},
            where: 'id = ?',
            whereArgs: [siteId],
          );

          matchedCount++;
        }
      }

      LoggingService.database('MIGRATE', 'Site mapping migration completed: $matchedCount/${localSites.length} sites matched');
    } catch (e) {
      LoggingService.error('DatabaseHelper: Site mapping migration failed', e);
      // Don't rethrow - this is a data enrichment operation, not critical
    }
  }

  /// Force recreation of the database (use when migration fails)
  Future<void> recreateDatabase() async {
    final path = join(await getDatabasesPath(), _databaseName);
    
    // Close existing connection
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    
    // Delete the database file
    await deleteDatabase(path);
    
    // Recreate the database
    _database = await _initDatabase();
  }

  /// Validate database schema to ensure all expected columns exist
  /// This provides an additional safety net beyond migrations
  Future<bool> validateDatabaseSchema() async {
    try {
      final db = await database;
      
      // Check flights table has all expected columns
      final flightColumns = await db.rawQuery("PRAGMA table_info(flights)");
      final expectedFlightColumns = {
        'id', 'date', 'launch_time', 'landing_time', 'duration',
        'launch_site_id', 'launch_latitude', 'launch_longitude', 'launch_altitude',
        'landing_latitude', 'landing_longitude', 'landing_altitude', 'landing_description',
        'max_altitude', 'max_climb_rate', 'max_sink_rate', 'max_climb_rate_5_sec', 'max_sink_rate_5_sec',
        'distance', 'straight_distance', 'fai_triangle_distance', 'fai_triangle_points',
        'wing_id', 'notes', 'track_log_path', 'original_filename', 'source',
        'timezone', 'created_at', 'updated_at',
        'max_ground_speed', 'avg_ground_speed', 'thermal_count', 'avg_thermal_strength',
        'total_time_in_thermals', 'best_thermal', 'avg_ld', 'longest_glide',
        'climb_percentage', 'gps_fix_quality', 'recording_interval',
        'takeoff_index', 'landing_index', 'detected_takeoff_time', 'detected_landing_time',
        'closing_point_index', 'closing_distance'
      };
      
      final actualFlightColumns = flightColumns.map((col) => col['name'] as String).toSet();
      final missingFlightColumns = expectedFlightColumns.difference(actualFlightColumns);
      
      if (missingFlightColumns.isNotEmpty) {
        LoggingService.error('DatabaseHelper: Missing flight columns: ${missingFlightColumns.join(', ')}');
        return false;
      }
      
      // Check sites table has all expected columns
      final siteColumns = await db.rawQuery("PRAGMA table_info(sites)");
      final expectedSiteColumns = {
        'id', 'name', 'latitude', 'longitude', 'altitude', 'country', 'custom_name', 'pge_site_id', 'created_at'
      };
      
      final actualSiteColumns = siteColumns.map((col) => col['name'] as String).toSet();
      final missingSiteColumns = expectedSiteColumns.difference(actualSiteColumns);
      
      if (missingSiteColumns.isNotEmpty) {
        LoggingService.error('DatabaseHelper: Missing site columns: ${missingSiteColumns.join(', ')}');
        return false;
      }
      
      // Check wings table has all expected columns
      final wingColumns = await db.rawQuery("PRAGMA table_info(wings)");
      final expectedWingColumns = {
        'id', 'name', 'manufacturer', 'model', 'size', 'color', 'purchase_date', 'active', 'notes', 'created_at'
      };
      
      final actualWingColumns = wingColumns.map((col) => col['name'] as String).toSet();
      final missingWingColumns = expectedWingColumns.difference(actualWingColumns);
      
      if (missingWingColumns.isNotEmpty) {
        LoggingService.error('DatabaseHelper: Missing wing columns: ${missingWingColumns.join(', ')}');
        return false;
      }
      
      // Check wing_aliases table has all expected columns
      final wingAliasColumns = await db.rawQuery("PRAGMA table_info(wing_aliases)");
      final expectedWingAliasColumns = {
        'id', 'wing_id', 'alias_name', 'created_at'
      };
      
      final actualWingAliasColumns = wingAliasColumns.map((col) => col['name'] as String).toSet();
      final missingWingAliasColumns = expectedWingAliasColumns.difference(actualWingAliasColumns);
      
      if (missingWingAliasColumns.isNotEmpty) {
        LoggingService.error('DatabaseHelper: Missing wing_aliases columns: ${missingWingAliasColumns.join(', ')}');
        return false;
      }
      
      // Check database version
      final version = await db.getVersion();
      if (version != _databaseVersion) {
        LoggingService.error('DatabaseHelper: Database version mismatch. Expected: $_databaseVersion, Actual: $version');
        return false;
      }
      
      LoggingService.info('DatabaseHelper: Database schema validation successful (v$version)');
      return true;
    } catch (e) {
      LoggingService.error('DatabaseHelper: Schema validation failed', e);
      return false;
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}