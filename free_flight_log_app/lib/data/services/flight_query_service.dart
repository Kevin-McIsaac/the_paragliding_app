import 'package:sqflite/sqflite.dart';
import '../datasources/database_helper.dart';
import '../models/flight.dart';
import '../utils/pagination_result.dart';
import '../../services/logging_service.dart';

/// Service for complex flight queries and filtering operations
/// Handles all query-related operations that don't involve basic CRUD
class FlightQueryService {
  final DatabaseHelper _databaseHelper;

  /// Constructor with dependency injection
  FlightQueryService(this._databaseHelper);

  /// Get flights within a date range
  Future<List<Flight>> getFlightsByDateRange(DateTime start, DateTime end) async {
    LoggingService.debug('FlightQueryService: Getting flights by date range');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.date >= ? AND f.date <= ?
      ORDER BY f.date DESC, f.launch_time DESC
    ''', [start.toIso8601String(), end.toIso8601String()]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('FlightQueryService: Found ${flights.length} flights in date range');
    
    return flights;
  }

  /// Get all flights from a specific launch site
  Future<List<Flight>> getFlightsBySite(int siteId) async {
    LoggingService.debug('FlightQueryService: Getting flights by site $siteId');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.launch_site_id = ?
      ORDER BY f.date DESC, f.launch_time DESC
    ''', [siteId]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('FlightQueryService: Found ${flights.length} flights for site');
    
    return flights;
  }

  /// Get all flights with a specific wing
  Future<List<Flight>> getFlightsByWing(int wingId) async {
    LoggingService.debug('FlightQueryService: Getting flights by wing $wingId');
    
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.wing_id = ?
      ORDER BY f.date DESC, f.launch_time DESC
    ''', [wingId]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('FlightQueryService: Found ${flights.length} flights for wing');
    
    return flights;
  }

  /// Find a flight by original filename (used for fast duplicate detection)
  Future<Flight?> findFlightByFilename(String filename) async {
    LoggingService.debug('FlightQueryService: Checking for duplicate by filename: $filename');
    
    Database db = await _databaseHelper.database;
    
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE f.original_filename = ?
      LIMIT 1
    ''', [filename]);
    
    if (maps.isNotEmpty) {
      final flight = Flight.fromMap(maps.first);
      LoggingService.debug('FlightQueryService: Found duplicate by filename - Flight ID: ${flight.id}');
      return flight;
    }
    
    LoggingService.debug('FlightQueryService: No duplicate found for filename: $filename');
    return null;
  }

  /// Find flight by date and launch time to check for duplicates during import
  Future<Flight?> findFlightByDateTime(DateTime date, String launchTime) async {
    LoggingService.debug('FlightQueryService: Checking for duplicate flight on ${date.toIso8601String()} at $launchTime');
    
    Database db = await _databaseHelper.database;
    
    // Format date as ISO string for database comparison
    final dateStr = date.toIso8601String().split('T')[0]; // Get just the date part
    
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE DATE(f.date) = ? AND f.launch_time = ?
      LIMIT 1
    ''', [dateStr, launchTime]);
    
    if (maps.isNotEmpty) {
      final duplicate = Flight.fromMap(maps.first);
      LoggingService.debug('FlightQueryService: Found duplicate flight with ID ${duplicate.id}');
      return duplicate;
    }
    
    LoggingService.debug('FlightQueryService: No duplicate flight found');
    return null;
  }

  /// Search flights by text query (searches notes, site names, etc.)
  Future<List<Flight>> searchFlights(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }
    
    LoggingService.debug('FlightQueryService: Searching flights with query: $query');
    
    Database db = await _databaseHelper.database;
    final searchTerm = '%${query.toLowerCase()}%';
    
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT f.*, 
             ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      WHERE LOWER(f.notes) LIKE ? 
         OR LOWER(ls.name) LIKE ?
      ORDER BY f.date DESC, f.launch_time DESC
    ''', [searchTerm, searchTerm]);
    
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    LoggingService.debug('FlightQueryService: Found ${flights.length} flights matching search');
    
    return flights;
  }

  /// Get flights with advanced pagination support
  Future<PaginationResult<Flight>> getFlightsPaginated(PaginationParams params) async {
    LoggingService.debug('FlightQueryService: Getting paginated flights with params: $params');
    
    Database db = await _databaseHelper.database;
    
    // Build query components
    String whereClause = _buildWhereClause(params);
    String orderClause = _buildOrderClause(params);
    List<dynamic> queryArgs = _buildQueryArgs(params);
    
    // Get total count for pagination metadata
    final totalCount = await _getTotalCount(whereClause, queryArgs);
    
    if (totalCount == 0) {
      return PaginationResult.empty<Flight>(page: params.page, pageSize: params.pageSize);
    }
    
    // Build main query with pagination
    final query = '''
      SELECT f.*, ls.name as launch_site_name
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      $whereClause
      $orderClause
      LIMIT ? OFFSET ?
    ''';
    
    final allArgs = [...queryArgs, params.pageSize, params.offset];
    
    List<Map<String, dynamic>> maps = await db.rawQuery(query, allArgs);
    final flights = maps.map((map) => Flight.fromMap(map)).toList();
    
    LoggingService.info('FlightQueryService: Retrieved ${flights.length}/$totalCount flights (page ${params.page})');
    
    return PaginationResult<Flight>(
      items: flights,
      totalCount: totalCount,
      page: params.page,
      pageSize: params.pageSize,
    );
  }

  /// Get flights with simple pagination (legacy method)
  Future<List<Flight>> getFlightsSimplePaginated({
    required int offset,
    required int limit,
    String? orderBy,
    bool ascending = false,
  }) async {
    final params = PaginationParams(
      page: (offset / limit).floor() + 1,
      pageSize: limit,
      sortBy: orderBy,
      ascending: ascending,
    );
    
    final result = await getFlightsPaginated(params);
    return result.items;
  }

  /// Get total count of flights (useful for pagination)
  Future<int> getTotalFlightCount() async {
    Database db = await _databaseHelper.database;
    List<Map<String, dynamic>> result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM flights'
    );
    return result.first['count'] as int;
  }
  
  /// Search flights with pagination support
  Future<PaginationResult<Flight>> searchFlightsPaginated(
    String searchQuery, 
    PaginationParams params
  ) async {
    LoggingService.debug('FlightQueryService: Searching flights with pagination: "$searchQuery"');
    
    final searchParams = params.copyWith(searchQuery: searchQuery);
    return await getFlightsPaginated(searchParams);
  }
  
  /// Get flights by date range with pagination
  Future<PaginationResult<Flight>> getFlightsByDateRangePaginated(
    DateTime startDate,
    DateTime endDate,
    PaginationParams params
  ) async {
    LoggingService.debug('FlightQueryService: Getting flights by date range with pagination');
    
    final filters = {
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      ...(params.filters ?? {})
    };
    
    final dateParams = params.copyWith(filters: filters);
    return await getFlightsPaginated(dateParams);
  }
  
  // Helper methods for query building
  
  String _buildWhereClause(PaginationParams params) {
    List<String> conditions = [];
    
    // Search query condition
    if (params.searchQuery != null && params.searchQuery!.isNotEmpty) {
      conditions.add('(LOWER(f.notes) LIKE ? OR LOWER(ls.name) LIKE ?)');
    }
    
    // Date range filter
    if (params.filters?['startDate'] != null) {
      conditions.add('f.date >= ?');
    }
    if (params.filters?['endDate'] != null) {
      conditions.add('f.date <= ?');
    }
    
    // Wing filter
    if (params.filters?['wingId'] != null) {
      conditions.add('f.wing_id = ?');
    }
    
    // Site filter
    if (params.filters?['siteId'] != null) {
      conditions.add('f.launch_site_id = ?');
    }
    
    return conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
  }
  
  String _buildOrderClause(PaginationParams params) {
    final sortColumn = _getSortColumn(params.sortBy);
    final direction = params.ascending ? 'ASC' : 'DESC';
    
    // Default sort: date DESC, launch_time DESC (optimized by composite index)
    if (params.sortBy == null || params.sortBy == 'date') {
      return 'ORDER BY f.date $direction, f.launch_time $direction';
    }
    
    return 'ORDER BY $sortColumn $direction, f.date DESC, f.launch_time DESC';
  }
  
  String _getSortColumn(String? sortBy) {
    switch (sortBy?.toLowerCase()) {
      case 'date':
      case 'datetime':
        return 'f.date';
      case 'duration':
        return 'f.duration';
      case 'altitude':
        return 'f.max_altitude';
      case 'distance':
        return 'f.distance';
      case 'straight_distance':
        return 'f.straight_distance';
      case 'site':
      case 'launch_site':
        return 'ls.name';
      case 'created':
        return 'f.created_at';
      case 'updated':
        return 'f.updated_at';
      default:
        return 'f.date';
    }
  }
  
  List<dynamic> _buildQueryArgs(PaginationParams params) {
    List<dynamic> args = [];
    
    // Search query arguments (add twice for notes and site name)
    if (params.searchQuery != null && params.searchQuery!.isNotEmpty) {
      final searchTerm = '%${params.searchQuery!.toLowerCase()}%';
      args.addAll([searchTerm, searchTerm]);
    }
    
    // Date range arguments
    if (params.filters?['startDate'] != null) {
      args.add(params.filters!['startDate']);
    }
    if (params.filters?['endDate'] != null) {
      args.add(params.filters!['endDate']);
    }
    
    // Wing filter
    if (params.filters?['wingId'] != null) {
      args.add(params.filters!['wingId']);
    }
    
    // Site filter
    if (params.filters?['siteId'] != null) {
      args.add(params.filters!['siteId']);
    }
    
    return args;
  }
  
  Future<int> _getTotalCount(String whereClause, List<dynamic> args) async {
    Database db = await _databaseHelper.database;
    
    final countQuery = '''
      SELECT COUNT(*) as count
      FROM flights f
      LEFT JOIN sites ls ON f.launch_site_id = ls.id
      $whereClause
    ''';
    
    List<Map<String, dynamic>> result = await db.rawQuery(countQuery, args);
    return result.first['count'] as int;
  }
}