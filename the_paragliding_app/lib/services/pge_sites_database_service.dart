import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../data/models/paragliding_site.dart';
import '../data/datasources/database_helper.dart';
import '../services/logging_service.dart';
import '../services/pge_sites_download_service.dart';
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
          wind_nw INTEGER DEFAULT 0
        )
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
  Future<bool> importSitesData() async {
    PerformanceMonitor.startOperation('PgeSitesImport');
    final stopwatch = Stopwatch()..start();

    try {
      // Parse downloaded data
      final sitesData = await PgeSitesDownloadService.instance.parseDownloadedData();

      if (sitesData.isEmpty) {
        LoggingService.warning('[PGE_SITES_DB] No sites data to import');
        return false;
      }

      final db = await DatabaseHelper.instance.database;

      LoggingService.info('[PGE_SITES_DB] Starting import of ${sitesData.length} sites');

      // Clear existing data and import in transaction
      await db.transaction((txn) async {
        // Clear existing sites
        await txn.delete(_pgeSitesTable);
        LoggingService.info('[PGE_SITES_DB] Cleared existing sites data');

        // Prepare batch insert
        final batch = txn.batch();

        for (final siteData in sitesData) {
          // Map CSV data directly to database fields (schema now includes altitude and country)
          final dbData = {
            'id': siteData['id'],
            'name': siteData['name'],
            'longitude': siteData['longitude'],
            'latitude': siteData['latitude'],
            'altitude': siteData['altitude'],  // New field
            'country': siteData['country'],    // New field
            'wind_n': siteData['wind_n'] ?? 0,
            'wind_ne': siteData['wind_ne'] ?? 0,
            'wind_e': siteData['wind_e'] ?? 0,
            'wind_se': siteData['wind_se'] ?? 0,
            'wind_s': siteData['wind_s'] ?? 0,
            'wind_sw': siteData['wind_sw'] ?? 0,
            'wind_w': siteData['wind_w'] ?? 0,
            'wind_nw': siteData['wind_nw'] ?? 0,
          };

          batch.insert(_pgeSitesTable, dbData);
        }

        // Execute batch insert
        await batch.commit(noResult: true);
      });

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

      LoggingService.performance(
        'PGE Sites Bounds Query',
        stopwatch.elapsed,
        'Found ${sites.length} sites in bounds'
      );

      LoggingService.structured('PGE_SITES_BOUNDS_QUERY', {
        'bounds': '$west,$south,$east,$north',
        'sites_found': sites.length,
        'query_duration_ms': stopwatch.elapsedMilliseconds,
      });

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
      id: row['id'] as int?,
      name: row['name'] as String? ?? 'Unknown Site',
      latitude: (row['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (row['longitude'] as num?)?.toDouble() ?? 0.0,
      altitude: row['altitude'] as int?,  // Now stored in database
      description: '', // Not available from PGE API
      windDirections: windDirections,
      siteType: 'launch', // PGE sites are primarily launch sites
      rating: null,
      country: row['country_name'] as String? ?? row['country'] as String?,  // Use full name from JOIN or fallback to code
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

  /// Toggle favorite status for a PGE site
  Future<void> toggleSiteFavorite(int siteId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.execute(
        'UPDATE $_pgeSitesTable SET is_favorite = CASE WHEN is_favorite = 1 THEN 0 ELSE 1 END WHERE id = ?',
        [siteId]
      );
      LoggingService.action('Favorites', 'toggle_pge_site', {'site_id': siteId});
    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to toggle favorite', error, stackTrace);
      rethrow;
    }
  }

  /// Check if a PGE site is favorited
  Future<bool> isSiteFavorite(int siteId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query(
        _pgeSitesTable,
        columns: ['is_favorite'],
        where: 'id = ?',
        whereArgs: [siteId]
      );
      return result.isNotEmpty && result.first['is_favorite'] == 1;
    } catch (error, stackTrace) {
      LoggingService.error('[PGE_SITES_DB] Failed to check favorite status', error, stackTrace);
      return false;
    }
  }

  /// Get all favorite PGE sites
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