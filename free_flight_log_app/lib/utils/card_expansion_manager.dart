import 'package:shared_preferences/shared_preferences.dart';
import '../services/logging_service.dart';

/// Utility class for managing card expansion states across the application.
/// Supports both persistent (saved to preferences) and session-only modes.
class CardExpansionManager {
  static const String _keyPrefix = 'card_expansion_';
  
  final String _screenId;
  final bool _persistent;
  final Map<String, bool> _sessionStates = {};
  final Map<String, bool> _defaultStates = {};
  
  /// Creates a CardExpansionManager for a specific screen.
  /// 
  /// [screenId] - Unique identifier for the screen (e.g., 'flight_detail', 'data_management')
  /// [persistent] - Whether to save states to SharedPreferences (default: true)
  CardExpansionManager({
    required String screenId,
    bool persistent = true,
  }) : _screenId = screenId, _persistent = persistent;
  
  /// Registers a card type with its default expansion state.
  /// Must be called before using getState() or setState().
  void registerCard(String cardType, {bool defaultExpanded = true}) {
    _defaultStates[cardType] = defaultExpanded;
    if (!_persistent) {
      _sessionStates[cardType] = defaultExpanded;
    }
  }
  
  /// Registers multiple card types at once.
  void registerCards(Map<String, bool> cards) {
    cards.forEach((cardType, defaultExpanded) {
      registerCard(cardType, defaultExpanded: defaultExpanded);
    });
  }
  
  /// Gets the current expansion state for a card type.
  bool getState(String cardType) {
    if (!_defaultStates.containsKey(cardType)) {
      LoggingService.warning('CardExpansionManager: Card type "$cardType" not registered for screen "$_screenId"');
      return true; // Default to expanded
    }
    
    if (!_persistent) {
      return _sessionStates[cardType] ?? _defaultStates[cardType]!;
    }
    
    // For persistent mode, we'll load from preferences during loadStates()
    // This method should only be called after loadStates() has been called
    return _sessionStates[cardType] ?? _defaultStates[cardType]!;
  }
  
  /// Sets the expansion state for a card type.
  /// In persistent mode, automatically saves to preferences.
  Future<void> setState(String cardType, bool expanded) async {
    if (!_defaultStates.containsKey(cardType)) {
      LoggingService.warning('CardExpansionManager: Card type "$cardType" not registered for screen "$_screenId"');
      return;
    }
    
    _sessionStates[cardType] = expanded;
    
    if (_persistent) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = _getPreferenceKey(cardType);
        await prefs.setBool(key, expanded);
        
        LoggingService.debug('CardExpansionManager: Saved expansion state for "$cardType" = $expanded');
      } catch (e) {
        LoggingService.error('CardExpansionManager: Failed to save expansion state for "$cardType"', e);
      }
    }
  }
  
  /// Loads all registered card states from preferences (persistent mode only).
  /// Should be called during screen initialization.
  Future<void> loadStates() async {
    if (!_persistent) {
      return; // Session-only mode doesn't need loading
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      for (final cardType in _defaultStates.keys) {
        final key = _getPreferenceKey(cardType);
        final storedState = prefs.getBool(key);
        _sessionStates[cardType] = storedState ?? _defaultStates[cardType]!;
      }
      
      LoggingService.debug('CardExpansionManager: Loaded expansion states for screen "$_screenId"');
    } catch (e) {
      LoggingService.error('CardExpansionManager: Failed to load expansion states for screen "$_screenId"', e);
      // Fall back to default states
      _sessionStates.addAll(_defaultStates);
    }
  }
  
  /// Gets all current expansion states as a map.
  Map<String, bool> getAllStates() {
    final result = <String, bool>{};
    for (final cardType in _defaultStates.keys) {
      result[cardType] = getState(cardType);
    }
    return result;
  }
  
  /// Creates an onExpansionChanged callback for use with ExpansionTile.
  /// Returns a function that automatically updates the state when called.
  void Function(bool) createExpansionCallback(String cardType, void Function() onStateChanged) {
    return (bool expanded) {
      setState(cardType, expanded);
      onStateChanged(); // Trigger UI update (typically setState)
    };
  }
  
  /// Clears all saved states for this screen (persistent mode only).
  /// Useful for debugging or resetting preferences.
  Future<void> clearAllStates() async {
    if (!_persistent) {
      _sessionStates.clear();
      _sessionStates.addAll(_defaultStates);
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      for (final cardType in _defaultStates.keys) {
        final key = _getPreferenceKey(cardType);
        await prefs.remove(key);
      }
      
      _sessionStates.clear();
      _sessionStates.addAll(_defaultStates);
      
      LoggingService.info('CardExpansionManager: Cleared all expansion states for screen "$_screenId"');
    } catch (e) {
      LoggingService.error('CardExpansionManager: Failed to clear expansion states for screen "$_screenId"', e);
    }
  }
  
  String _getPreferenceKey(String cardType) {
    return '$_keyPrefix${_screenId}_$cardType';
  }
}

/// Pre-configured card expansion managers for common screens.
class CardExpansionManagers {
  
  /// Creates a CardExpansionManager for the Flight Detail screen with standard card types.
  static CardExpansionManager createFlightDetailManager() {
    final manager = CardExpansionManager(screenId: 'flight_detail');
    manager.registerCards({
      'flight_details': true,
      'flight_statistics': true,
      'flight_track': true,
      'flight_notes': true, // Always expanded, but can be managed
    });
    return manager;
  }
  
  /// Creates a CardExpansionManager for the Data Management screen with standard card types.
  static CardExpansionManager createDataManagementManager({bool persistent = false}) {
    final manager = CardExpansionManager(screenId: 'data_management', persistent: persistent);
    manager.registerCards({
      'database_stats': false,
      'backup_status': false,
      'map_cache': false,
      'igc_cleanup': false,
      'api_test': false,
      'premium_maps': false,
    });
    return manager;
  }
  
  /// Creates a session-only CardExpansionManager for any screen.
  static CardExpansionManager createSessionManager(String screenId, Map<String, bool> cardDefaults) {
    final manager = CardExpansionManager(screenId: screenId, persistent: false);
    manager.registerCards(cardDefaults);
    return manager;
  }
}