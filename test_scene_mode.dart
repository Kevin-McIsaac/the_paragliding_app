import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../free_flight_log_app/lib/services/preferences_service.dart';

void main() {
  group('Scene Mode Preferences', () {
    late PreferencesService preferencesService;

    setUp(() async {
      // Set up shared preferences for testing
      SharedPreferences.setMockInitialValues({});
      preferencesService = PreferencesService();
      await preferencesService.init();
    });

    test('should default to 3D mode', () async {
      final mode = await preferencesService.getSceneMode();
      expect(mode, PreferencesService.sceneMode3D);
    });

    test('should save and retrieve 2D mode', () async {
      await preferencesService.setSceneMode(PreferencesService.sceneMode2D);
      final mode = await preferencesService.getSceneMode();
      expect(mode, PreferencesService.sceneMode2D);
    });

    test('should save and retrieve Columbus mode', () async {
      await preferencesService.setSceneMode(PreferencesService.sceneModeColumbus);
      final mode = await preferencesService.getSceneMode();
      expect(mode, PreferencesService.sceneModeColumbus);
    });

    test('should persist mode across service instances', () async {
      // Save mode with first instance
      await preferencesService.setSceneMode(PreferencesService.sceneMode2D);
      
      // Create new instance and check if mode persists
      final newService = PreferencesService();
      final mode = await newService.getSceneMode();
      expect(mode, PreferencesService.sceneMode2D);
    });

    test('should reject invalid scene modes', () async {
      final success = await preferencesService.setSceneMode('INVALID');
      expect(success, false);
      
      // Should still have default mode
      final mode = await preferencesService.getSceneMode();
      expect(mode, PreferencesService.sceneMode3D);
    });
  });
}