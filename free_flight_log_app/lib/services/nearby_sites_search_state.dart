import '../data/models/paragliding_site.dart';

/// Consolidated state management for nearby sites search functionality
/// 
/// This class replaces multiple scattered state variables with a single, 
/// well-defined state object that tracks all search-related state.
class SearchState {
  final String query;
  final bool isSearchMode;
  final List<ParaglidingSite> results;
  final bool isSearching;
  final ParaglidingSite? pinnedSite;
  final bool pinnedSiteIsFromAutoJump;

  const SearchState({
    this.query = '',
    this.isSearchMode = false,
    this.results = const [],
    this.isSearching = false,
    this.pinnedSite,
    this.pinnedSiteIsFromAutoJump = false,
  });

  /// Creates an initial/empty search state
  static const SearchState initial = SearchState();

  /// Returns true if search is currently active (has query or results)
  bool get isActive => query.isNotEmpty || results.isNotEmpty;

  /// Returns true if there's a single search result
  bool get hasSingleResult => results.length == 1;

  /// Returns true if search has results to display
  bool get hasResults => results.isNotEmpty;

  /// Returns true if search is empty but was previously active
  bool get isEmpty => query.isEmpty && results.isEmpty && isSearchMode;

  /// Creates a new SearchState with updated values
  SearchState copyWith({
    String? query,
    bool? isSearchMode,
    List<ParaglidingSite>? results,
    bool? isSearching,
    ParaglidingSite? pinnedSite,
    bool? pinnedSiteIsFromAutoJump,
  }) {
    return SearchState(
      query: query ?? this.query,
      isSearchMode: isSearchMode ?? this.isSearchMode,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      pinnedSite: pinnedSite ?? this.pinnedSite,
      pinnedSiteIsFromAutoJump: pinnedSiteIsFromAutoJump ?? this.pinnedSiteIsFromAutoJump,
    );
  }

  /// Creates a new SearchState with cleared pinned site
  SearchState clearPinnedSite() {
    return copyWith(
      pinnedSite: null,
      pinnedSiteIsFromAutoJump: false,
    );
  }

  /// Creates a new SearchState for entering search mode
  SearchState enterSearchMode({required String query}) {
    return copyWith(
      query: query,
      isSearchMode: true,
      isSearching: true,
    );
  }

  /// Creates a new SearchState for exiting search mode
  SearchState exitSearchMode() {
    return const SearchState(
      query: '',
      isSearchMode: false,
      results: [],
      isSearching: false,
      pinnedSite: null,
      pinnedSiteIsFromAutoJump: false,
    );
  }

  /// Creates a new SearchState with search results
  SearchState withResults(List<ParaglidingSite> results) {
    return copyWith(
      results: results,
      isSearching: false,
    );
  }

  /// Creates a new SearchState with a pinned site from auto-jump
  SearchState withAutoJumpPinnedSite(ParaglidingSite site) {
    return copyWith(
      pinnedSite: site,
      pinnedSiteIsFromAutoJump: true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchState &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          isSearchMode == other.isSearchMode &&
          results == other.results &&
          isSearching == other.isSearching &&
          pinnedSite == other.pinnedSite &&
          pinnedSiteIsFromAutoJump == other.pinnedSiteIsFromAutoJump;

  @override
  int get hashCode =>
      query.hashCode ^
      isSearchMode.hashCode ^
      results.hashCode ^
      isSearching.hashCode ^
      pinnedSite.hashCode ^
      pinnedSiteIsFromAutoJump.hashCode;

  @override
  String toString() {
    return 'SearchState('
        'query: $query, '
        'isSearchMode: $isSearchMode, '
        'results: ${results.length}, '
        'isSearching: $isSearching, '
        'pinnedSite: ${pinnedSite?.name}, '
        'pinnedSiteIsFromAutoJump: $pinnedSiteIsFromAutoJump'
        ')';
  }
}