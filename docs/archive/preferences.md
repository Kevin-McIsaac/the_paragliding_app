
# Cesium 3D Map Preferences

- Scene Mode (cesium_scene_mode): 3D, 2D, or Columbus view - default: '3D'
- Base Map (cesium_base_map): Selected imagery provider - default: 'Bing Maps Aerial'
- Terrain Enabled (cesium_terrain_enabled): Whether terrain is shown - default: true
- Navigation Help Dialog (cesium_navigation_help_dialog_open): Whether help dialog is open - default: false
- Fly Through Mode (cesium_fly_through_mode): Whether fly-through animation is enabled - default: false
- Trail Duration (cesium_trail_duration): How many seconds of trail to show - default: 5
- Quality/Resolution (cesium_quality): Resolution scale (0.75, 1.0, 2.0)

## Cesium Ion Token Preferences

- User Token (cesium_user_token): User's own Cesium Ion token for premium maps
- Token Validated (cesium_token_validated): Whether the token has been validated
- Token Validation Date (cesium_token_validation_date): When the token was last validated

  IGC Import Preferences:

- Last Folder (igc_last_folder): Last folder used for IGC imports

## How Preferences Are Used

1. On Widget Initialization: The _loadPreferences() method in cesium_3d_map_inappwebview.dart loads all saved preferences when the widget initializes.
2. Passed to JavaScript: Preferences are passed to the Cesium JavaScript code through the configuration object when loading the HTML:
savedSceneMode: "$_savedSceneMode",
savedBaseMap: "$_savedBaseMap",
savedTerrainEnabled: $_savedTerrainEnabled,
// etc...
1. JavaScript Usage: The cesium.js file uses these preferences during initialization:

- Scene mode determines the initial view
- Base map selects the imagery provider
- Terrain preference is checked but currently always loads terrain (line 854-857 in cesium.js)
- Quality sets the resolution scale
- Token determines if premium maps are available

2. Runtime Updates: When users change settings in the Cesium view, JavaScript callbacks update the preferences:

- Scene mode changes trigger onSceneModeChanged handler
- Base map changes trigger onImageryProviderChanged handler
- Other settings have their respective handlers

## Key Issue with Terrain

The current implementation in main branch:

- Saves the terrain preference (_savedTerrainEnabled)
- Passes it to JavaScript configuration
- But always loads terrain regardless of the preference (line 854-857 in cesium.js forces terrain loading)
- The preference is only used for progressive loading after 5 seconds (lines 913-921)3
