/// Pagination result container that holds paginated data and metadata
class PaginationResult<T> {
  final List<T> items;
  final int totalCount;
  final int page;
  final int pageSize;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final int totalPages;

  PaginationResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  })  : hasNextPage = page * pageSize < totalCount,
        hasPreviousPage = page > 1,
        totalPages = (totalCount / pageSize).ceil();

  /// Create empty pagination result
  static PaginationResult<T> empty<T>({int page = 1, int pageSize = 20}) {
    return PaginationResult<T>(
      items: [],
      totalCount: 0,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Get the range of items being displayed (e.g., "1-20 of 150")
  String get displayRange {
    if (totalCount == 0) return '0 of 0';
    
    final start = ((page - 1) * pageSize) + 1;
    final end = (page * pageSize).clamp(0, totalCount);
    return '$start-$end of $totalCount';
  }

  /// Get offset for database queries
  int get offset => (page - 1) * pageSize;

  @override
  String toString() {
    return 'PaginationResult(items: ${items.length}, totalCount: $totalCount, page: $page/$totalPages, range: $displayRange)';
  }
}

/// Pagination configuration parameters
class PaginationParams {
  final int page;
  final int pageSize;
  final String? sortBy;
  final bool ascending;
  final String? searchQuery;
  final Map<String, dynamic>? filters;

  const PaginationParams({
    this.page = 1,
    this.pageSize = 20,
    this.sortBy,
    this.ascending = false,
    this.searchQuery,
    this.filters,
  });

  /// Create copy with modified parameters
  PaginationParams copyWith({
    int? page,
    int? pageSize,
    String? sortBy,
    bool? ascending,
    String? searchQuery,
    Map<String, dynamic>? filters,
  }) {
    return PaginationParams(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
      searchQuery: searchQuery ?? this.searchQuery,
      filters: filters ?? this.filters,
    );
  }

  /// Get offset for database queries
  int get offset => (page - 1) * pageSize;

  /// Get next page parameters
  PaginationParams get nextPage => copyWith(page: page + 1);

  /// Get previous page parameters
  PaginationParams get previousPage => copyWith(page: (page - 1).clamp(1, page));

  @override
  String toString() {
    return 'PaginationParams(page: $page, pageSize: $pageSize, sortBy: $sortBy, ascending: $ascending, searchQuery: $searchQuery)';
  }
}