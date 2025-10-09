import 'dart:async';
import '../data/models/paragliding_site.dart';
import '../utils/map_constants.dart';
import '../services/pge_sites_database_service.dart';
// API import removed - using local database only
import '../services/logging_service.dart';
import 'nearby_sites_search_state.dart';

/// Enhanced search manager that uses local PGE database first
/// Falls back to API only when local database is unavailable
class NearbySitesSearchManagerV2 {
  final SearchStateCallback _onStateChanged;
  final AutoJumpCallback? _onAutoJump;

  /// Current search state
  SearchState _state = SearchState.initial;

  /// Debounce timer for API calls
  Timer? _searchDebounce;

  /// Debounce duration for search queries
  static const Duration _searchDebounceDelay = Duration(milliseconds: MapConstants.searchDebounceMs);

  /// Minimum query length for search
  static const int _minQueryLength = 2;

  /// Maximum results to show in dropdown
  static const int _maxResults = 15;

  // Database availability check removed - always use local

  NearbySitesSearchManagerV2({
    required SearchStateCallback onStateChanged,
    AutoJumpCallback? onAutoJump,
  }) : _onStateChanged = onStateChanged,
       _onAutoJump = onAutoJump;

  // Database availability check removed - always use local

  /// Get current search state
  SearchState get state => _state;

  /// Enter search mode
  void enterSearchMode() {
    _updateState(_state.copyWith(isSearchMode: true));
  }

  /// Exit search mode and clear all state
  void exitSearchMode({ParaglidingSite? preservePinnedSite, bool pinnedSiteIsFromAutoJump = false}) {
    _searchDebounce?.cancel();
    if (preservePinnedSite != null) {
      _updateState(SearchState.initial.copyWith(
        pinnedSite: preservePinnedSite,
        pinnedSiteIsFromAutoJump: pinnedSiteIsFromAutoJump,
      ));
    } else {
      _updateState(SearchState.initial);
    }
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

    // Debounce the actual search
    _searchDebounce = Timer(_searchDebounceDelay, () {
      _performSearch(trimmedQuery);
    });
  }

  /// Select a search result
  void selectSearchResult(ParaglidingSite site) {
    LoggingService.action('NearbySitesV2', 'search_result_selected', {
      'site_name': site.name,
      'country': site.country,
      'data_source': 'local_db',
    });

    exitSearchMode(preservePinnedSite: site, pinnedSiteIsFromAutoJump: false);
  }

  /// Perform immediate search (triggered by Enter key)
  Future<void> performImmediateSearch(String query) async {
    final trimmedQuery = query.trim();

    _searchDebounce?.cancel();

    if (trimmedQuery.isEmpty || trimmedQuery.length < _minQueryLength) {
      return;
    }

    _updateState(_state.copyWith(
      query: trimmedQuery,
      isSearchMode: true,
      isSearching: true,
    ));

    try {
      final results = await _searchSites(trimmedQuery);
      final limitedResults = results.take(_maxResults).toList();

      if (limitedResults.length == 1) {
        final site = limitedResults.first;
        _onAutoJump?.call(site);
        exitSearchMode(preservePinnedSite: site, pinnedSiteIsFromAutoJump: false);

        LoggingService.action('NearbySitesV2', 'enter_key_single_result', {
          'site_name': site.name,
          'country': site.country,
          'data_source': 'local_db',
        });
      } else {
        _updateState(_state.copyWith(
          results: limitedResults,
          isSearching: false,
        ));

        LoggingService.action('NearbySitesV2', 'enter_key_search', {
          'query': trimmedQuery,
          'results_count': limitedResults.length,
          'data_source': 'local_db',
        });
      }
    } catch (e) {
      LoggingService.error('Enter key search failed', e);
      _updateState(_state.copyWith(
        results: [],
        isSearching: false,
      ));
    }
  }

  /// Perform the actual search
  Future<void> _performSearch(String query) async {
    try {
      final results = await _searchSites(query);
      final limitedResults = results.take(_maxResults).toList();

      var newState = _state.copyWith(
        results: limitedResults,
        isSearching: false,
      );

      // Auto-jump to single result
      if (limitedResults.length == 1) {
        final site = limitedResults.first;
        _onAutoJump?.call(site);
        exitSearchMode(preservePinnedSite: site, pinnedSiteIsFromAutoJump: true);

        LoggingService.action('NearbySitesV2', 'live_search_single_result_auto_exit', {
          'site_name': site.name,
          'country': site.country,
          'data_source': 'local_db',
        });

        return;
      }

      _updateState(newState);

      LoggingService.action('NearbySitesV2', 'search_performed', {
        'query': query,
        'results_count': results.length,
        'auto_selected': limitedResults.length == 1,
        'data_source': 'local_db',
      });

    } catch (e) {
      LoggingService.error('Search failed', e);
      _updateState(_state.copyWith(
        results: [],
        isSearching: false,
      ));
    }
  }

  /// Search sites using local database only
  Future<List<ParaglidingSite>> _searchSites(String query) async {
    // Always use local database
    LoggingService.info('NearbySitesSearchManagerV2: Searching local database for: $query');
    try {
      return await PgeSitesDatabaseService.instance.searchSitesByName(
        query: query,
      );
    } catch (e) {
      LoggingService.error('NearbySitesSearchManagerV2: Search failed', e);
      return [];
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
  List<ParaglidingSite> getDisplayedSites(List<ParaglidingSite> allSites) {
    if (_state.query.isNotEmpty && _state.results.isNotEmpty) {
      return _state.results;
    } else if (_state.query.isEmpty) {
      return allSites;
    } else {
      return allSites;
    }
  }

  /// Check if we should show the search dropdown
  bool shouldShowSearchDropdown() {
    return _state.isSearchMode && (_state.results.isNotEmpty || _state.isSearching);
  }
}

/// Callback types for search state updates
typedef SearchStateCallback = void Function(SearchState state);
typedef AutoJumpCallback = void Function(ParaglidingSite site);