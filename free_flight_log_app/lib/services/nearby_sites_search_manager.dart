import 'dart:async';
import '../data/models/paragliding_site.dart';
import '../services/paragliding_earth_api.dart';
import '../services/logging_service.dart';
import 'nearby_sites_search_state.dart';

/// Callback types for search state updates
typedef SearchStateCallback = void Function(SearchState state);
typedef AutoJumpCallback = void Function(ParaglidingSite site);

/// Consolidated search manager for nearby sites functionality
/// 
/// This class extracts all search logic from the screen widget and provides
/// a clean, testable interface for search operations.
class NearbySitesSearchManager {
  final ParaglidingEarthApi _api;
  final SearchStateCallback _onStateChanged;
  final AutoJumpCallback? _onAutoJump;

  /// Current search state
  SearchState _state = SearchState.initial;

  /// Debounce timer for API calls
  Timer? _searchDebounce;
  
  /// Debounce duration for search queries
  static const Duration _searchDebounceDelay = Duration(milliseconds: 300);

  /// Minimum query length for API search
  static const int _minQueryLength = 2;

  /// Maximum results to show in dropdown
  static const int _maxResults = 15;

  NearbySitesSearchManager({
    required SearchStateCallback onStateChanged,
    AutoJumpCallback? onAutoJump,
    ParaglidingEarthApi? api,
  }) : _onStateChanged = onStateChanged,
       _onAutoJump = onAutoJump,
       _api = api ?? ParaglidingEarthApi.instance;

  /// Get current search state
  SearchState get state => _state;

  /// Enter search mode
  void enterSearchMode() {
    _updateState(_state.copyWith(isSearchMode: true));
  }

  /// Exit search mode and clear all state
  void exitSearchMode() {
    _searchDebounce?.cancel();
    _updateState(SearchState.initial);
  }

  /// Handle search query change with debouncing
  void onSearchQueryChanged(String query) {
    final trimmedQuery = query.trim();
    
    // Cancel any existing search
    _searchDebounce?.cancel();
    
    // Clear results immediately if query is empty
    if (trimmedQuery.isEmpty) {
      _updateState(_state.copyWith(
        query: '',
        results: [],
        isSearching: false,
      ).clearPinnedSite());
      return;
    }
    
    // Update state with new query and start searching
    _updateState(_state.copyWith(
      query: trimmedQuery,
      isSearching: true,
    ));
    
    // Don't search for very short queries
    if (trimmedQuery.length < _minQueryLength) {
      _updateState(_state.copyWith(isSearching: false));
      return;
    }
    
    // Debounce the actual API call
    _searchDebounce = Timer(_searchDebounceDelay, () {
      _performSearch(trimmedQuery);
    });
  }

  /// Select a search result (called when user taps on result)
  void selectSearchResult(ParaglidingSite site) {
    // Clear auto-jump flag when user explicitly selects
    _updateState(_state.copyWith(
      pinnedSite: site,
      pinnedSiteIsFromAutoJump: false,
    ));

    LoggingService.action('NearbySites', 'search_result_selected', {
      'site_name': site.name,
      'country': site.country,
    });

    // Exit search mode to dismiss the results dropdown
    exitSearchMode();
  }

  /// Perform the actual API search
  Future<void> _performSearch(String query) async {
    try {
      final results = await _api.searchSitesByName(query);
      
      // Limit results for better UX
      final limitedResults = results.take(_maxResults).toList();
      
      // Update state with results
      var newState = _state.copyWith(
        results: limitedResults,
        isSearching: false,
      );

      // Auto-jump to single result but keep search active
      if (limitedResults.length == 1) {
        newState = newState.withAutoJumpPinnedSite(limitedResults.first);
        
        // Notify callback for map centering
        _onAutoJump?.call(limitedResults.first);
      }

      _updateState(newState);

      LoggingService.action('NearbySites', 'api_search_performed', {
        'query': query,
        'results_count': results.length,
        'auto_selected': limitedResults.length == 1,
      });

    } catch (e) {
      LoggingService.error('API search failed', e);
      
      _updateState(_state.copyWith(
        results: [],
        isSearching: false,
      ));
    }
  }

  /// Update internal state and notify callback
  void _updateState(SearchState newState) {
    _state = newState;
    _onStateChanged(_state);
  }

  /// Clean up resources
  void dispose() {
    _searchDebounce?.cancel();
  }

  /// Check if a site selection is a duplicate auto-jump
  bool isDuplicateAutoJump(ParaglidingSite site) {
    return _state.pinnedSite != null &&
           _state.pinnedSite!.name == site.name &&
           _state.pinnedSite!.latitude == site.latitude &&
           _state.pinnedSite!.longitude == site.longitude &&
           _state.pinnedSiteIsFromAutoJump;
  }

  /// Get sites to display based on search state and all sites
  /// This is a computed property that simplifies display logic
  List<ParaglidingSite> getDisplayedSites(List<ParaglidingSite> allSites) {
    if (_state.query.isNotEmpty && _state.results.isNotEmpty) {
      // Show search results
      return _state.results;
    } else if (_state.query.isEmpty) {
      // No search - show all sites
      return allSites;
    } else {
      // Search in progress or no results - keep showing current sites
      // This prevents sites from disappearing while typing
      return allSites;
    }
  }

  /// Check if we should show the search dropdown
  bool shouldShowSearchDropdown() {
    return _state.isSearchMode && (_state.results.isNotEmpty || _state.isSearching);
  }
}