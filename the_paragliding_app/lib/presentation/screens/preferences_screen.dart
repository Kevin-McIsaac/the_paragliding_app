import 'package:flutter/material.dart';
import '../../utils/preferences_helper.dart';
import '../../utils/ui_utils.dart';
import '../../utils/card_expansion_manager.dart';
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
  
  // Takeoff/Landing Detection preferences
  double? _detectionSpeedThreshold;
  double? _detectionClimbRateThreshold;
  double? _triangleClosingDistance;
  int? _triangleSamplingInterval;

  // Wind Threshold preferences (using RangeValues: start = caution, end = unsafe)
  RangeValues? _windSpeedRange;

  bool _isLoading = true;
  bool _isSaving = false;

  // Card expansion state manager
  CardExpansionManager? _expansionManager;

  @override
  void initState() {
    super.initState();
    _expansionManager = CardExpansionManagers.createPreferencesManager();
    _loadPreferences();
    _loadCardExpansionStates();
  }

  Future<void> _loadCardExpansionStates() async {
    await _expansionManager?.loadStates();
    setState(() {
      // Update UI with loaded expansion states
    });
  }

  Future<void> _loadPreferences() async {
    try {
      // Load 3D Visualization preferences
      final sceneMode = await PreferencesHelper.getCesiumSceneMode();
      final baseMap = await PreferencesHelper.getCesiumBaseMap();
      final terrainEnabled = await PreferencesHelper.getCesiumTerrainEnabled();
      final trailDuration = await PreferencesHelper.getCesiumTrailDuration();
      final quality = await PreferencesHelper.getCesiumQuality();
      
      // Load Detection preferences
      final speedThreshold = await PreferencesHelper.getDetectionSpeedThreshold();
      final climbRateThreshold = await PreferencesHelper.getDetectionClimbRateThreshold();
      final triangleClosingDistance = await PreferencesHelper.getTriangleClosingDistance();
      final triangleSamplingInterval = await PreferencesHelper.getTriangleSamplingInterval();

      // Load Wind Threshold preferences and combine into RangeValues
      final maxWindSpeed = await PreferencesHelper.getMaxWindSpeed();
      final cautionWindSpeed = await PreferencesHelper.getCautionWindSpeed();

      if (mounted) {
        setState(() {
          _cesiumSceneMode = sceneMode;
          _cesiumBaseMap = baseMap ?? 'satellite';
          _cesiumTerrainEnabled = terrainEnabled;
          _cesiumTrailDuration = trailDuration;
          _cesiumQuality = quality;

          _detectionSpeedThreshold = speedThreshold;
          _detectionClimbRateThreshold = climbRateThreshold;
          _triangleClosingDistance = triangleClosingDistance;
          _triangleSamplingInterval = triangleSamplingInterval;

          // Combine caution and max values into RangeValues (start = caution, end = unsafe)
          // Clamp values to valid ranges
          final cautionSpeed = cautionWindSpeed.clamp(20.0, 50.0);
          final maxSpeed = maxWindSpeed.clamp(20.0, 50.0);
          _windSpeedRange = RangeValues(
            cautionSpeed < maxSpeed ? cautionSpeed : maxSpeed - 1,
            maxSpeed > cautionSpeed ? maxSpeed : cautionSpeed + 1,
          );


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
        UiUtils.showErrorMessage(context, 'Failed to load preferences: $e');
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

  bool _isValidTrailDuration(int? value) {
    return value != null && PreferencesHelper.validCesiumTrailDurations.contains(value);
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
        UiUtils.showSuccessMessage(context, 'Saved $prefName');
      }
    } catch (e) {
      LoggingService.error('PreferencesScreen: Failed to save $prefName: $e');
      if (mounted) {
        UiUtils.showErrorMessage(context, 'Failed to save $prefName: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildSection(String title, List<Widget> children, {required String expansionKey}) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: ExpansionTile(
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        initiallyExpanded: _expansionManager?.getState(expansionKey) ?? true,
        onExpansionChanged: (expanded) {
          _expansionManager?.setState(expansionKey, expanded);
          setState(() {
            // Update UI with new expansion state
          });
        },
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

  Widget _buildRangeSliderRow(
    String title,
    String subtitle,
    RangeValues values,
    double min,
    double max,
    Function(RangeValues) onChanged,
    Function(RangeValues)? onChangeEnd,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(title),
          subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
          trailing: Text(
            '${values.start.toInt()}-${values.end.toInt()} km/h',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        RangeSlider(
          values: values,
          min: min,
          max: max,
          labels: RangeLabels(
            '${values.start.toInt()} km/h',
            '${values.end.toInt()} km/h',
          ),
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${min.toInt()} km/h',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
              Text(
                '${max.toInt()} km/h',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
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
              _buildSection('3D Visualization', expansionKey: '3d_visualization', [
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
                _buildDropdownRow<int>(
                  'Trail Duration',
                  'How long the flight trail remains visible',
                  _isValidTrailDuration(_cesiumTrailDuration) ? _cesiumTrailDuration : null,
                  [
                    const DropdownMenuItem(value: 60, child: Text('1 minute')),
                    const DropdownMenuItem(value: 120, child: Text('2 minutes')),
                    const DropdownMenuItem(value: 180, child: Text('3 minutes')),
                    const DropdownMenuItem(value: 240, child: Text('4 minutes')),
                    const DropdownMenuItem(value: 300, child: Text('5 minutes')),
                  ],
                  (value) {
                    if (value != null) {
                      setState(() {
                        _cesiumTrailDuration = value;
                      });
                      _savePreference('trail duration', value, PreferencesHelper.setCesiumTrailDuration);
                    }
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

              // Flight Detection Settings
              _buildSection('Flight Detection', expansionKey: 'flight_detection', [
                _buildDropdownRow<double>(
                  'Speed Threshold',
                  'Minimum 5-second average ground speed for takeoff/landing detection',
                  _detectionSpeedThreshold,
                  PreferencesHelper.validSpeedThresholds.map((speed) =>
                    DropdownMenuItem(
                      value: speed,
                      child: Text('${speed.toStringAsFixed(0)} km/h'),
                    )
                  ).toList(),
                  (value) {
                    if (value != null) {
                      setState(() {
                        _detectionSpeedThreshold = value;
                      });
                      _savePreference('speed threshold', value, PreferencesHelper.setDetectionSpeedThreshold);
                    }
                  },
                ),
                _buildDropdownRow<double>(
                  'Climb Rate Threshold',
                  'Minimum absolute 5-second average climb rate for takeoff/landing detection',
                  _detectionClimbRateThreshold,
                  PreferencesHelper.validClimbRateThresholds.map((rate) =>
                    DropdownMenuItem(
                      value: rate,
                      child: Text('${rate.toStringAsFixed(1)} m/s'),
                    )
                  ).toList(),
                  (value) {
                    if (value != null) {
                      setState(() {
                        _detectionClimbRateThreshold = value;
                      });
                      _savePreference('climb rate threshold', value, PreferencesHelper.setDetectionClimbRateThreshold);
                    }
                  },
                ),
                _buildDropdownRow<double>(
                  'Triangle Closing Distance',
                  'Maximum distance of return to launch to consider a flight as closed triangle',
                  _triangleClosingDistance,
                  PreferencesHelper.validTriangleClosingDistances.map((distance) =>
                    DropdownMenuItem(
                      value: distance,
                      child: Text('${distance.toStringAsFixed(0)} m'),
                    )
                  ).toList(),
                  (value) {
                    if (value != null) {
                      setState(() {
                        _triangleClosingDistance = value;
                      });
                      _savePreference('triangle closing distance', value, PreferencesHelper.setTriangleClosingDistance);
                    }
                  },
                ),
                _buildDropdownRow<int>(
                  'Triangle Calculation Sampling',
                  'Time interval between sample points for triangle optimization (shorter = more precise but slower)\n\n'
                  '• 15s - Maximum precision, best for short flights\n'
                  '• 30s - High precision, good balance for most flights (recommended)\n'
                  '• 60s - Standard precision, recommended for long flights',
                  _triangleSamplingInterval,
                  PreferencesHelper.validTriangleSamplingIntervals.map((interval) =>
                    DropdownMenuItem(
                      value: interval,
                      child: Text(_getTriangleSamplingDescription(interval)),
                    )
                  ).toList(),
                  (value) {
                    if (value != null) {
                      setState(() {
                        _triangleSamplingInterval = value;
                      });
                      _savePreference('triangle sampling interval', value, PreferencesHelper.setTriangleSamplingInterval);
                    }
                  },
                ),
              ]),

              // Wind Threshold Settings
              _buildSection('Wind Thresholds for Flyability', expansionKey: 'wind_thresholds', [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'These settings determine what is considered safe flyable (launching) conditions which determines the colour of the site marker in the map',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                _buildRangeSliderRow(
                  'Wind Speed',
                  'Caution (left) to unsafe (right) thresholds (default: 20-25 km/h)',
                  _windSpeedRange ?? const RangeValues(20.0, 25.0),
                  20.0,
                  50.0,
                  // onChanged: Update UI immediately while dragging
                  (values) {
                    setState(() {
                      _windSpeedRange = values;
                    });
                  },
                  // onChangeEnd: Save to preferences only when user releases slider
                  (values) async {
                    await PreferencesHelper.setCautionWindSpeed(values.start);
                    await PreferencesHelper.setMaxWindSpeed(values.end);
                    LoggingService.info('PreferencesScreen: Saved wind speed | caution=${values.start.toInt()} unsafe=${values.end.toInt()} km/h');
                    if (mounted) {
                      UiUtils.showSuccessMessage(context, 'Saved wind speed thresholds');
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
  
  /// Get user-friendly description for triangle sampling intervals
  String _getTriangleSamplingDescription(int interval) {
    return '${interval}s';
  }
}