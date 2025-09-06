import 'package:flutter/material.dart';
import '../../utils/preferences_helper.dart';
import '../../services/logging_service.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  // 3D Visualization preferences
  String? _cesiumSceneMode;
  String? _cesiumBaseMap;
  bool? _cesiumTerrainEnabled;
  int? _cesiumTrailDuration;
  double? _cesiumQuality;
  
  
  
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      // Load 3D Visualization preferences
      final sceneMode = await PreferencesHelper.getCesiumSceneMode();
      final baseMap = await PreferencesHelper.getCesiumBaseMap();
      final terrainEnabled = await PreferencesHelper.getCesiumTerrainEnabled();
      final trailDuration = await PreferencesHelper.getCesiumTrailDuration();
      final quality = await PreferencesHelper.getCesiumQuality();
      
      if (mounted) {
        setState(() {
          _cesiumSceneMode = sceneMode;
          _cesiumBaseMap = baseMap ?? 'satellite';
          _cesiumTerrainEnabled = terrainEnabled;
          _cesiumTrailDuration = trailDuration;
          _cesiumQuality = quality;
          
          _isLoading = false;
        });
      }
      
      LoggingService.info('PreferencesScreen: Loaded preferences successfully');
    } catch (e) {
      LoggingService.error('PreferencesScreen: Failed to load preferences: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load preferences: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _isValidBaseMap(String? value) {
    const validMaps = ['openstreetmap', 'satellite', 'hybrid'];
    return value != null && validMaps.contains(value);
  }

  bool _isValidSceneMode(String? value) {
    const validModes = ['3D', 'Columbus', '2D'];
    return value != null && validModes.contains(value);
  }

  Future<void> _savePreference<T>(
    String prefName, 
    T value, 
    Future<void> Function(T) setter
  ) async {
    if (_isSaving) return;
    
    setState(() {
      _isSaving = true;
    });

    try {
      await setter(value);
      LoggingService.info('PreferencesScreen: Saved $prefName = $value');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved $prefName'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      LoggingService.error('PreferencesScreen: Failed to save $prefName: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save $prefName: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildSection(String title, List<Widget> children, {bool collapsed = false}) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: ExpansionTile(
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        initiallyExpanded: !collapsed,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(
    String title,
    String subtitle,
    bool? value,
    Function(bool) onChanged,
  ) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
      trailing: Switch(
        value: value ?? false,
        onChanged: onChanged,
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildDropdownRow<T>(
    String title,
    String subtitle,
    T? value,
    List<DropdownMenuItem<T>> items,
    Function(T?) onChanged,
  ) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
      trailing: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        hint: const Text('Select...'),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildSliderRow(
    String title,
    String subtitle,
    double? value,
    double min,
    double max,
    int? divisions,
    String Function(double) labelBuilder,
    Function(double) onChanged,
  ) {
    return ListTile(
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle.isNotEmpty) Text(subtitle),
          Slider(
            value: value ?? min,
            min: min,
            max: max,
            divisions: divisions,
            label: labelBuilder(value ?? min),
            onChanged: onChanged,
          ),
        ],
      ),
      contentPadding: EdgeInsets.zero,
    );
  }



  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Preferences'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          ListView(
            children: [
              // 3D Visualization Settings
              _buildSection('3D Visualization', [
                _buildSwitchRow(
                  'Enable Terrain',
                  'Show 3D terrain relief on maps',
                  _cesiumTerrainEnabled,
                  (value) {
                    setState(() {
                      _cesiumTerrainEnabled = value;
                    });
                    _savePreference('terrain enabled', value, PreferencesHelper.setCesiumTerrainEnabled);
                  },
                ),
                _buildDropdownRow<String>(
                  'Scene Mode',
                  'How the 3D globe is displayed',
                  _isValidSceneMode(_cesiumSceneMode) ? _cesiumSceneMode : null,
                  [
                    const DropdownMenuItem(value: '3D', child: Text('3D Globe')),
                    const DropdownMenuItem(value: 'Columbus', child: Text('Columbus View')),
                    const DropdownMenuItem(value: '2D', child: Text('2D Map')),
                  ],
                  (value) {
                    if (value != null) {
                      setState(() {
                        _cesiumSceneMode = value;
                      });
                      _savePreference('scene mode', value, PreferencesHelper.setCesiumSceneMode);
                    }
                  },
                ),
                _buildDropdownRow<String>(
                  'Base Map',
                  'The background imagery to display',
                  _isValidBaseMap(_cesiumBaseMap) ? _cesiumBaseMap : null,
                  [
                    const DropdownMenuItem(value: 'openstreetmap', child: Text('OpenStreetMap')),
                    const DropdownMenuItem(value: 'satellite', child: Text('Satellite')),
                    const DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
                  ],
                  (value) {
                    if (value != null) {
                      setState(() {
                        _cesiumBaseMap = value;
                      });
                      _savePreference('base map', value, PreferencesHelper.setCesiumBaseMap);
                    }
                  },
                ),
                _buildSliderRow(
                  'Trail Duration',
                  'How long the flight trail remains visible (seconds)',
                  _cesiumTrailDuration?.toDouble(),
                  10.0,
                  300.0,
                  29,
                  (value) => '${value.round()}s',
                  (value) {
                    setState(() {
                      _cesiumTrailDuration = value.round();
                    });
                    _savePreference('trail duration', value.round(), PreferencesHelper.setCesiumTrailDuration);
                  },
                ),
                _buildDropdownRow<double>(
                  'Rendering Quality',
                  'Higher quality uses more resources',
                  _cesiumQuality,
                  [
                    const DropdownMenuItem(value: 0.5, child: Text('Low')),
                    const DropdownMenuItem(value: 1.0, child: Text('Medium')),
                    const DropdownMenuItem(value: 1.5, child: Text('High')),
                    const DropdownMenuItem(value: 2.0, child: Text('Ultra')),
                  ],
                  (value) {
                    if (value != null) {
                      setState(() {
                        _cesiumQuality = value;
                      });
                      _savePreference('rendering quality', value, PreferencesHelper.setCesiumQuality);
                    }
                  },
                ),
              ]),


            ],
          ),
          if (_isSaving)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}