import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/airspace_enums.dart';
import '../../services/nearby_sites_controller.dart';
import '../../services/logging_service.dart';
import '../../services/openaip_service.dart';
import '../../utils/map_provider.dart';
import '../widgets/nearby_sites_map_widget.dart';
import '../widgets/map_filter_dialog.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/site_details_dialog.dart';

/// Simplified nearby sites screen using NearbySitesController
///
/// Significantly reduced complexity by extracting business logic to controller
class NearbySitesScreen extends StatefulWidget {
  const NearbySitesScreen({super.key});

  @override
  State<NearbySitesScreen> createState() => _NearbySitesScreenState();
}

class _NearbySitesScreenState extends State<NearbySitesScreen> {
  final NearbySitesController _controller = NearbySitesController();
  final OpenAipService _openAipService = OpenAipService.instance;

  // UI state (separate from business logic)
  MapProvider _selectedMapProvider = MapProvider.openStreetMap;
  bool _isLegendExpanded = false;
  bool _sitesEnabled = true;
  bool _airspaceEnabled = true;
  double _maxAltitudeFt = 10000.0;
  Map<IcaoClass, bool> _excludedIcaoClasses = {};
  int _filterUpdateCounter = 0;
  LatLngBounds? _boundsToFit;

  // Constants
  static const String _mapProviderKey = 'nearby_sites_map_provider';
  static const String _legendExpandedKey = 'nearby_sites_legend_expanded';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _loadPreferences();
    _loadFilterSettings();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {
        // UI will rebuild based on controller state changes
      });
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerIndex = prefs.getInt(_mapProviderKey) ?? MapProvider.openStreetMap.index;
      final legendExpanded = prefs.getBool(_legendExpandedKey) ?? false;

      if (mounted) {
        setState(() {
          _selectedMapProvider = MapProvider.values[providerIndex];
          _isLegendExpanded = legendExpanded;
        });
      }
    } catch (e) {
      LoggingService.error('Failed to load preferences', e);
    }
  }

  Future<void> _loadFilterSettings() async {
    try {
      final icaoClasses = await _openAipService.getExcludedIcaoClasses();
      if (mounted) {
        setState(() {
          _excludedIcaoClasses = icaoClasses;
        });
      }
    } catch (e) {
      LoggingService.error('Failed to load filter settings', e);
    }
  }

  void _toggleLegend() async {
    setState(() {
      _isLegendExpanded = !_isLegendExpanded;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_legendExpandedKey, _isLegendExpanded);
    } catch (e) {
      LoggingService.error('Failed to save legend preference', e);
    }
  }

  void _onSiteSelected(ParaglidingSite site) {
    final siteKey = '${site.latitude.toStringAsFixed(6)},${site.longitude.toStringAsFixed(6)}';
    final hasFlights = _controller.siteFlightStatus[siteKey] ?? false;

    LoggingService.action('NearbySites', hasFlights ? 'flown_site_selected' : 'new_site_selected', {
      'site_name': site.name,
      'site_type': site.siteType,
      'has_flights': hasFlights,
    });

    _showSiteDetailsDialog(site);
  }

  void _showSiteDetailsDialog(ParaglidingSite site) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (context) => SiteDetailsDialog(
        site: null,
        paraglidingSite: site,
        userPosition: _controller.userPosition,
      ),
    );
  }

  void _onSearchResultSelected(ParaglidingSite site) {
    _controller.selectSearchResult(site);
    _jumpToSite(site);
  }

  void _jumpToSite(ParaglidingSite site) {
    final bounds = _controller.getBoundsForSite(site);

    setState(() {
      _boundsToFit = bounds;
    });

    // Clear bounds after map has fitted
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _boundsToFit = null;
        });
      }
    });

    LoggingService.action('NearbySites', 'location_jumped', {
      'site_name': site.name,
      'country': site.country,
    });
  }

  void _onBoundsChanged(LatLngBounds bounds) {
    _controller.onBoundsChanged(bounds);
  }

  Future<void> _onRefreshLocation() async {
    LoggingService.action('NearbySites', 'refresh_location', {});
    await _controller.refreshLocation();
  }

  void _showMapFilterDialog() async {
    try {
      final airspaceTypesEnum = await _openAipService.getExcludedAirspaceTypes();
      final icaoClassesEnum = await _openAipService.getExcludedIcaoClasses();
      final clippingEnabled = await _openAipService.isClippingEnabled();

      final airspaceTypes = <String, bool>{
        for (final entry in airspaceTypesEnum.entries)
          entry.key.abbreviation: entry.value
      };
      final icaoClasses = <String, bool>{
        for (final entry in icaoClassesEnum.entries)
          entry.key.abbreviation: entry.value
      };

      if (!mounted) return;

      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (context) => MapFilterDialog(
          sitesEnabled: _sitesEnabled,
          airspaceEnabled: _airspaceEnabled,
          airspaceTypes: airspaceTypes,
          icaoClasses: icaoClasses,
          maxAltitudeFt: _maxAltitudeFt,
          clippingEnabled: clippingEnabled,
          mapProvider: _selectedMapProvider,
          onApply: _handleFilterApply,
        ),
      );
    } catch (error, stackTrace) {
      LoggingService.error('Failed to show map filter dialog', error, stackTrace);
    }
  }

  void _handleFilterApply(
    bool sitesEnabled,
    bool airspaceEnabled,
    Map<String, bool> types,
    Map<String, bool> classes,
    double maxAltitudeFt,
    bool clippingEnabled,
    MapProvider mapProvider,
  ) async {
    // Update UI state
    setState(() {
      _sitesEnabled = sitesEnabled;
      _airspaceEnabled = airspaceEnabled;
      _maxAltitudeFt = maxAltitudeFt;
      _selectedMapProvider = mapProvider;
      _filterUpdateCounter++;
    });

    // Save preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_mapProviderKey, mapProvider.index);
    } catch (e) {
      LoggingService.error('Failed to save map provider preference', e);
    }

    // Update service settings
    try {
      if (airspaceEnabled) {
        final typesEnum = <AirspaceType, bool>{
          for (final entry in types.entries)
            AirspaceType.values.where((t) => t.abbreviation == entry.key).first: entry.value
        };
        final classesEnum = <IcaoClass, bool>{
          for (final entry in classes.entries)
            IcaoClass.values.where((c) => c.abbreviation == entry.key).first: entry.value
        };

        await _openAipService.setAirspaceEnabled(true);
        await _openAipService.setExcludedAirspaceTypes(typesEnum);
        await _openAipService.setExcludedIcaoClasses(classesEnum);
        await _openAipService.setClippingEnabled(clippingEnabled);

        setState(() {
          _excludedIcaoClasses = classesEnum;
        });
      } else {
        await _openAipService.setAirspaceEnabled(false);
      }
    } catch (error, stackTrace) {
      LoggingService.error('Failed to apply map filters', error, stackTrace);
    }
  }

  Future<bool> _hasActiveFilters() async {
    try {
      final types = await _openAipService.getExcludedAirspaceTypes();
      final classes = await _openAipService.getExcludedIcaoClasses();

      final hasDisabledTypes = types.values.contains(false);
      final hasDisabledClasses = classes.values.contains(false);

      return !_sitesEnabled || hasDisabledTypes || hasDisabledClasses;
    } catch (error) {
      LoggingService.error('Failed to check active filters', error);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Sites'),
      ),
      body: Stack(
        children: [
          // Main content
          if (_controller.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_controller.errorMessage != null)
            AppErrorState(
              message: _controller.errorMessage!,
              onRetry: () => _controller.initialize(),
            )
          else
            _buildMapContent(),

          // Search results overlay
          if (_controller.hasSearchResults)
            _buildSearchOverlay(),

          // Loading overlay
          if (_controller.sitesLoading)
            _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildMapContent() {
    // Cache the filter check to avoid rebuilding FutureBuilder
    return _MapContentWrapper(
      controller: _controller,
      boundsToFit: _boundsToFit,
      selectedMapProvider: _selectedMapProvider,
      isLegendExpanded: _isLegendExpanded,
      onToggleLegend: _toggleLegend,
      onSiteSelected: _onSiteSelected,
      onBoundsChanged: _onBoundsChanged,
      onRefreshLocation: _onRefreshLocation,
      onSearchResultSelected: _onSearchResultSelected,
      onShowMapFilter: _showMapFilterDialog,
      sitesEnabled: _sitesEnabled,
      maxAltitudeFt: _maxAltitudeFt,
      filterUpdateCounter: _filterUpdateCounter,
      excludedIcaoClasses: _excludedIcaoClasses,
    );
  }

  Widget _buildSearchOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        elevation: 8,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: _controller.isSearching
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Searching sites...'),
                  ],
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _controller.searchResults.length,
                itemBuilder: (context, index) {
                  final site = _controller.searchResults[index];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(context).primaryColor.withAlpha(25),
                      child: Text(
                        site.country?.toUpperCase().substring(0, 2) ?? '??',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                    title: Text(
                      site.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(site.country ?? 'Unknown'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _onSearchResultSelected(site),
                  );
                },
              ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned(
      top: 60,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(217),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(77),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
                strokeCap: StrokeCap.round,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Loading nearby sites...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Optimized wrapper to prevent excessive rebuilds of map widget
class _MapContentWrapper extends StatefulWidget {
  final NearbySitesController controller;
  final LatLngBounds? boundsToFit;
  final MapProvider selectedMapProvider;
  final bool isLegendExpanded;
  final VoidCallback onToggleLegend;
  final Function(ParaglidingSite) onSiteSelected;
  final Function(LatLngBounds) onBoundsChanged;
  final VoidCallback onRefreshLocation;
  final Function(ParaglidingSite) onSearchResultSelected;
  final VoidCallback onShowMapFilter;
  final bool sitesEnabled;
  final double maxAltitudeFt;
  final int filterUpdateCounter;
  final Map<IcaoClass, bool> excludedIcaoClasses;

  const _MapContentWrapper({
    required this.controller,
    this.boundsToFit,
    required this.selectedMapProvider,
    required this.isLegendExpanded,
    required this.onToggleLegend,
    required this.onSiteSelected,
    required this.onBoundsChanged,
    required this.onRefreshLocation,
    required this.onSearchResultSelected,
    required this.onShowMapFilter,
    required this.sitesEnabled,
    required this.maxAltitudeFt,
    required this.filterUpdateCounter,
    required this.excludedIcaoClasses,
  });

  @override
  State<_MapContentWrapper> createState() => _MapContentWrapperState();
}

class _MapContentWrapperState extends State<_MapContentWrapper> {
  bool? _cachedHasActiveFilters;

  @override
  void initState() {
    super.initState();
    _loadActiveFilters();
  }

  @override
  void didUpdateWidget(_MapContentWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only reload filters if the filter counter changed
    if (oldWidget.filterUpdateCounter != widget.filterUpdateCounter) {
      _loadActiveFilters();
    }
  }

  Future<void> _loadActiveFilters() async {
    try {
      final openAipService = OpenAipService.instance;
      final types = await openAipService.getExcludedAirspaceTypes();
      final classes = await openAipService.getExcludedIcaoClasses();

      final hasDisabledTypes = types.values.contains(false);
      final hasDisabledClasses = classes.values.contains(false);
      final hasActiveFilters = !widget.sitesEnabled || hasDisabledTypes || hasDisabledClasses;

      if (mounted && _cachedHasActiveFilters != hasActiveFilters) {
        setState(() {
          _cachedHasActiveFilters = hasActiveFilters;
        });
      }
    } catch (error) {
      LoggingService.error('Failed to check active filters', error);
      if (mounted && _cachedHasActiveFilters != false) {
        setState(() {
          _cachedHasActiveFilters = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't memoize the widget - let Flutter handle rebuilds naturally
    // Use a stable key to prevent widget recreation
    return NearbySitesMapWidget(
      key: const ValueKey('nearby_sites_map'), // Stable key prevents recreation
      sites: widget.controller.displayedSites,
      siteFlightStatus: widget.controller.siteFlightStatus,
      userPosition: widget.controller.userPosition,
      centerPosition: widget.controller.mapCenter,
      boundsToFit: widget.boundsToFit,
      initialZoom: 10.0,
      mapProvider: widget.selectedMapProvider,
      isLegendExpanded: widget.isLegendExpanded,
      onToggleLegend: widget.onToggleLegend,
      onSiteSelected: widget.onSiteSelected,
      onBoundsChanged: widget.onBoundsChanged,
      searchQuery: widget.controller.searchQuery,
      onSearchChanged: widget.controller.onSearchQueryChanged,
      onRefreshLocation: widget.onRefreshLocation,
      isLocationLoading: widget.controller.isLocationLoading,
      searchResults: widget.controller.searchResults,
      isSearching: widget.controller.isSearching,
      onSearchResultSelected: widget.onSearchResultSelected,
      onShowMapFilter: widget.onShowMapFilter,
      hasActiveFilters: _cachedHasActiveFilters ?? false,
      sitesEnabled: widget.sitesEnabled,
      maxAltitudeFt: widget.maxAltitudeFt,
      filterUpdateCounter: widget.filterUpdateCounter,
      excludedIcaoClasses: widget.excludedIcaoClasses,
    );
  }
}