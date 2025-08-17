// Cesium 3D Map JavaScript Module
// Handles initialization, memory management, and lifecycle

// Global state management
const cesiumState = {
    viewer: null,
    flightTrackEntity: null,
    igcPoints: [],
    terrainExaggeration: 1.0,
    timezone: '+00:00',
    timezoneOffsetSeconds: 0,
    playback: {
        followMode: false,
        showPilot: null,
        positionProperty: null
    },
    sceneMode: null,  // Will be set to current scene mode
    sceneModeChanging: false,  // Flag to track if scene mode is changing
    flyThroughMode: {
        enabled: false,
        trailDuration: 5000,  // milliseconds (kept for future use but not used in progressive mode)
        dynamicTrackPrimitive: null, // Primitive for per-vertex colored dynamic track
        showDynamicTrack: false,      // Track visibility state
        igcPoints: null,              // Store the IGC points for global access
        fullTrackEntity: null,
        curtainWallEntity: null,      // Static curtain wall hanging from track
        dynamicCurtainEntity: null,    // Dynamic curtain for progressive mode
        lastUpdateTime: null,
        updateInterval: 100,  // Update every 100ms for smooth animation
        progressiveMode: false,  // Changed to false - now using ribbon mode
        ribbonMode: 'animation-time',  // Ribbon based on animation time
        ribbonAnimationSeconds: 3.0,   // Default 3 seconds of animation time
        ribbonStartTime: null,         // Track when ribbon starts
        onTickCallback: null           // Store the onTick callback for cleanup
    },
    flightTrackHomeView: null  // Store the home view for flight track
};

// Compatibility aliases for easier refactoring
let viewer = null;
let flightTrackEntity = null;
let igcPoints = [];
let currentTerrainExaggeration = 1.0;

// Logging wrapper for conditional output
const cesiumLog = {
    debug: (message) => {
        if (window.cesiumConfig && window.cesiumConfig.debug) {
            console.log('[Cesium Debug] ' + message);
        }
    },
    info: (message) => {
        console.log('[Cesium] ' + message);
    },
    error: (message) => {
        console.error('[Cesium Error] ' + message);
    }
};

// Main initialization function
function initializeCesium(config) {
    // Set Cesium Ion token
    Cesium.Ion.defaultAccessToken = config.token;
    
    cesiumLog.info('Starting Cesium initialization...');
    
    // Store track points if provided during initialization
    const hasInitialTrack = config.trackPoints && config.trackPoints.length > 0;
    if (hasInitialTrack) {
        cesiumLog.info('Initial track data provided with ' + config.trackPoints.length + ' points');
    }
    
    try {
        // Create custom imagery provider view models for limited base layer options
        const imageryViewModels = [];
        
        // Bing Maps Aerial
        imageryViewModels.push(new Cesium.ProviderViewModel({
            name: 'Bing Maps Aerial',
            iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/bingAerial.png'),
            tooltip: 'Bing Maps aerial imagery',
            creationFunction: function () {
                return Cesium.IonImageryProvider.fromAssetId(2);
            }
        }));
        
        // Bing Maps Aerial with Labels
        imageryViewModels.push(new Cesium.ProviderViewModel({
            name: 'Bing Maps Aerial with Labels',
            iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/bingAerialLabels.png'),
            tooltip: 'Bing Maps aerial imagery with labels',
            creationFunction: function () {
                return Cesium.IonImageryProvider.fromAssetId(3);
            }
        }));
        
        // Bing Maps Roads
        imageryViewModels.push(new Cesium.ProviderViewModel({
            name: 'Bing Maps Roads',
            iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/bingRoads.png'),
            tooltip: 'Bing Maps standard road maps',
            creationFunction: function () {
                return Cesium.IonImageryProvider.fromAssetId(4);
            }
        }));
        
        // OpenStreetMap
        imageryViewModels.push(new Cesium.ProviderViewModel({
            name: 'OpenStreetMap',
            iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/openStreetMap.png'),
            tooltip: 'OpenStreetMap',
            creationFunction: function () {
                return new Cesium.OpenStreetMapImageryProvider({
                    url: 'https://a.tile.openstreetmap.org/'
                });
            }
        }));
        
        // Create terrain provider view models (only world terrain)
        const terrainViewModels = [];
        terrainViewModels.push(new Cesium.ProviderViewModel({
            name: 'World Terrain',
            iconUrl: Cesium.buildModuleUrl('Widgets/Images/TerrainProviders/CesiumWorldTerrain.png'),
            tooltip: 'High-resolution global terrain',
            creationFunction: function () {
                return Cesium.createWorldTerrainAsync({
                    requestWaterMask: false,
                    requestVertexNormals: true  // Enable for better terrain shading
                });
            }
        }));
        
        terrainViewModels.push(new Cesium.ProviderViewModel({
            name: 'No Terrain',
            iconUrl: Cesium.buildModuleUrl('Widgets/Images/TerrainProviders/Ellipsoid.png'),
            tooltip: 'WGS84 ellipsoid',
            creationFunction: function () {
                return new Cesium.EllipsoidTerrainProvider();
            }
        }));
        
        // Apply saved preferences from Flutter
        let selectedImageryProvider = imageryViewModels[0]; // Default to Bing Aerial
        let selectedTerrainProvider = terrainViewModels[0]; // Default to World Terrain
        let navigationHelpDialogOpen = false; // Default to closed
        
        if (config.savedBaseMap) {
            const found = imageryViewModels.find(vm => vm.name === config.savedBaseMap);
            if (found) {
                selectedImageryProvider = found;
                cesiumLog.info('Applying saved base map preference: ' + config.savedBaseMap);
            }
        }
        
        if (config.savedTerrainEnabled !== undefined) {
            selectedTerrainProvider = config.savedTerrainEnabled ? terrainViewModels[0] : terrainViewModels[1];
            cesiumLog.info('Applying saved terrain preference: ' + (config.savedTerrainEnabled ? 'enabled' : 'disabled'));
        }
        
        if (config.savedNavigationHelpDialogOpen !== undefined) {
            navigationHelpDialogOpen = config.savedNavigationHelpDialogOpen;
            cesiumLog.info('Navigation help dialog should be ' + (navigationHelpDialogOpen ? 'open' : 'closed'));
        }
        
        // Aggressively optimized Cesium viewer settings for minimal memory usage
        viewer = new Cesium.Viewer("cesiumContainer", {
            terrain: Cesium.Terrain.fromWorldTerrain({
                requestWaterMask: false,  // Disable water effects
                requestVertexNormals: true,  // Enable for better terrain shading
                requestMetadata: false  // Disable metadata
            }),
            scene3DOnly: false,  // Enable 2D/3D/Columbus view modes
            requestRenderMode: true,  // Only render on demand
            maximumRenderTimeChange: Infinity,  // Reduce re-renders
            targetFrameRate: 60,  // Higher frame rate for smoother experience
            resolutionScale: 1.0,  // Full resolution for better quality
            
            // WebGL context options for better quality
            contextOptions: {
                webgl: {
                    powerPreference: 'high-performance',  // Use high-performance GPU
                    antialias: true,  // Enable antialiasing for smoother edges
                    preserveDrawingBuffer: false,
                    failIfMajorPerformanceCaveat: false,
                    depth: true,
                    stencil: false,
                    alpha: false
                }
            },
            
            // Enable Cesium's native animation controls
            baseLayerPicker: true,
            imageryProviderViewModels: imageryViewModels,  // Use custom limited imagery providers
            selectedImageryProviderViewModel: selectedImageryProvider,  // Use saved or default
            terrainProviderViewModels: terrainViewModels,  // Use custom limited terrain providers
            selectedTerrainProviderViewModel: selectedTerrainProvider,  // Use saved or default
            geocoder: true,
            homeButton: true,  // Enable home button
            sceneModePicker: true,
            navigationHelpButton: true,  // Always show the button
            navigationInstructionsInitiallyVisible: navigationHelpDialogOpen,  // Set initial state based on saved preference
            animation: true,  // Enable native animation widget
            timeline: true,   // Enable native timeline widget
            fullscreenButton: true,
            vrButton: false,
            infoBox: true,  // Enable info box for entity information
            selectionIndicator: true,
            shadows: false,
            shouldAnimate: false,  // Start paused
        });
        
        
        // Load saved scene mode preference or default to 3D
        const savedSceneMode = loadSceneModePreference();
        if (savedSceneMode && savedSceneMode !== Cesium.SceneMode.SCENE3D) {
            viewer.scene.mode = savedSceneMode;
        }
        cesiumState.sceneMode = viewer.scene.mode;
        
        // Add scene mode change listener
        viewer.scene.morphComplete.addEventListener(onSceneModeChanged);
        viewer.scene.morphStart.addEventListener(onSceneModeChanging);
        
        // Configure scene for better quality
        viewer.scene.globe.enableLighting = false;
        viewer.scene.globe.showGroundAtmosphere = true;  // Enable atmosphere for better visuals
        viewer.scene.fog.enabled = true;  // Enable fog for depth perception
        viewer.scene.fog.density = 0.0001;  // Reduce fog density for clearer distant views
        viewer.scene.fog.screenSpaceErrorFactor = 2.0;  // Adjust fog based on terrain detail
        viewer.scene.globe.depthTestAgainstTerrain = true;  // Enable terrain occlusion
        viewer.scene.screenSpaceCameraController.enableCollisionDetection = false;
        
        // Enable HDR rendering for better dynamic range
        viewer.scene.highDynamicRange = true;
        
        // Enhanced tile cache management for quality
        viewer.scene.globe.tileCacheSize = 300;  // Increased cache for smoother panning
        viewer.scene.globe.preloadSiblings = true;  // Preload adjacent tiles for smoother panning
        viewer.scene.globe.preloadAncestors = true;  // Preload parent tiles for better loading
        
        // Tile memory budget - increase for better quality
        viewer.scene.globe.maximumMemoryUsage = 512;  // Higher memory limit for better quality
        
        // Better quality with reasonable performance
        viewer.scene.globe.maximumScreenSpaceError = 2;  // Higher terrain detail for better clarity
        
        // Higher texture resolution
        viewer.scene.maximumTextureSize = 2048;  // Higher resolution textures
        
        // Optimize texture atlas for better memory efficiency
        viewer.scene.globe.textureCache = viewer.scene.globe.textureCache || {};
        viewer.scene.globe.maximumTextureAtlasMemory = 256 * 1024 * 1024;  // 256MB texture atlas limit
        
        // Set explicit tile load limits
        viewer.scene.globe.loadingDescendantLimit = 15;  // Balanced concurrent tile loads
        viewer.scene.globe.immediatelyLoadDesiredLevelOfDetail = false;  // Progressive loading for better performance
        
        // Enable FXAA for better edge quality
        viewer.scene.fxaa = true;
        viewer.scene.msaaSamples = 8;  // Increased MSAA for smoother edges
        
        // Set terrain exaggeration for better visibility
        viewer.scene.globe.terrainExaggeration = 1.2;  // 20% exaggeration for clearer elevation changes
        viewer.scene.globe.terrainExaggerationRelativeHeight = 0.0;
        
        // Configure imagery provider for better performance
        const imageryProvider = viewer.imageryLayers.get(0);
        if (imageryProvider) {
            imageryProvider.brightness = 1.0;
            imageryProvider.contrast = 1.0;
            imageryProvider.saturation = 1.0;
        }
        
        // Only set initial camera view if no track points provided
        // If track points are provided, the view will be set after creating the track
        if (!hasInitialTrack) {
            viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(config.lon, config.lat, config.altitude),
                orientation: {
                    heading: Cesium.Math.toRadians(0),
                    pitch: Cesium.Math.toRadians(-45),
                    roll: 0.0
                }
            });
        }
        
        // Add keyboard listener for stats position control
        document.addEventListener('keydown', function(event) {
        });
        
        // Add Cesium native event listeners for preference changes
        if (viewer.baseLayerPicker) {
            // Watch for imagery provider changes
            const imageryObservable = Cesium.knockout.getObservable(
                viewer.baseLayerPicker.viewModel, 
                'selectedImagery'
            );
            imageryObservable.subscribe(function(newImagery) {
                if (newImagery) {
                    cesiumLog.info('Imagery provider changed to: ' + newImagery.name);
                    // Send to Flutter
                    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                        window.flutter_inappwebview.callHandler('onImageryProviderChanged', newImagery.name);
                    }
                }
            });
            
            // Watch for terrain provider changes
            const terrainObservable = Cesium.knockout.getObservable(
                viewer.baseLayerPicker.viewModel,
                'selectedTerrain'
            );
            terrainObservable.subscribe(function(newTerrain) {
                if (newTerrain) {
                    const isTerrainEnabled = newTerrain.name !== 'No Terrain';
                    cesiumLog.info('Terrain changed to: ' + newTerrain.name + ' (enabled: ' + isTerrainEnabled + ')');
                    // Send to Flutter
                    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                        window.flutter_inappwebview.callHandler('onTerrainProviderChanged', isTerrainEnabled);
                    }
                }
            });
        }
        
        // Handle tile memory exceeded events
        viewer.scene.globe.tileLoadProgressEvent.addEventListener(function() {
            // Monitor for memory issues
            const globe = viewer.scene.globe;
            if (globe._surface && globe._surface._tilesToRender) {
                const tileCount = globe._surface._tilesToRender.length;
                if (tileCount > 50) {  // Increased threshold for higher quality settings
                    // Only log occasionally to reduce spam
                    if (Math.random() < 0.1) {  // Log 10% of the time
                        }
                    // Temporarily increase screen space error to reduce tile count
                    viewer.scene.globe.maximumScreenSpaceError = 3;  // Less aggressive reduction
                    
                    // Reset after a delay
                    setTimeout(() => {
                        viewer.scene.globe.maximumScreenSpaceError = 2;  // Reset to our new default
                    }, 3000);
                }
            }
        });
        
        // Track initial load with minimal logging
        let lastTileCount = -1;
        let loadComplete = false;
        const loadingStartTime = Date.now();
        
        const tileLoadHandler = function(queuedTileCount) {
            if (queuedTileCount === 0 && !loadComplete) {
                loadComplete = true;
                const loadTime = ((Date.now() - loadingStartTime) / 1000).toFixed(2);
                cesiumLog.info('Initial tile load complete in ' + loadTime + 's');
                document.getElementById('loadingOverlay').style.display = 'none';
                
                // Remove the listener after initial load
                viewer.scene.globe.tileLoadProgressEvent.removeEventListener(tileLoadHandler);
            } else if (config.debug && !loadComplete) {
                // Only log significant changes in debug mode
                const change = Math.abs(lastTileCount - queuedTileCount);
                if (change > 10 || (queuedTileCount === 0 && lastTileCount > 0)) {
                    lastTileCount = queuedTileCount;
                }
            }
        };
        viewer.scene.globe.tileLoadProgressEvent.addEventListener(tileLoadHandler);
        
        // Simple memory management - let browser handle most cleanup
        
        cesiumLog.info('Cesium viewer initialized successfully');
        
        // Apply saved scene mode preference if not 3D (the default)
        if (config.savedSceneMode && config.savedSceneMode !== '3D') {
            cesiumLog.info('Applying saved scene mode: ' + config.savedSceneMode);
            setTimeout(function() {
                setSceneMode(config.savedSceneMode);
            }, 500); // Small delay to ensure viewer is fully initialized
        }
        
        // Fly-through mode is now automatic based on playback state
        // No need to load preferences
        
        // If track points were provided, create the track immediately
        if (hasInitialTrack) {
            cesiumLog.info('Creating initial track with ' + config.trackPoints.length + ' points');
            // Use a small delay to ensure viewer is fully ready
            setTimeout(() => {
                createColoredFlightTrack(config.trackPoints);
                cesiumLog.info('Initial track created and view set');
                
                // Fly-through mode is now automatic - no manual setup needed
            }, 100);
        } else {
        }
        
        // Store viewer globally for cleanup
        window.viewer = viewer;
        
        // Track navigation help dialog state changes for saving preferences
        if (viewer.navigationHelpButton && viewer.navigationHelpButton.viewModel) {
            const navHelpVM = viewer.navigationHelpButton.viewModel;
            
            // Check if showInstructions observable exists (indicates dialog state)
            if (navHelpVM.showInstructions !== undefined) {
                const instructionsObservable = Cesium.knockout.getObservable(navHelpVM, 'showInstructions');
                if (instructionsObservable) {
                    // The dialog is already in the correct initial state thanks to navigationInstructionsInitiallyVisible
                    // Now we just need to track future changes for saving preferences
                    
                    // Use a flag to prevent saving the initial state
                    let isInitialState = true;
                    setTimeout(function() {
                        isInitialState = false;
                        cesiumLog.info('Navigation help dialog initialized with saved preference: ' + 
                                      (navigationHelpDialogOpen ? 'open' : 'closed'));
                    }, 1000);
                    
                    // Subscribe to future changes
                    instructionsObservable.subscribe(function(isShowing) {
                        cesiumLog.info('Navigation help dialog ' + (isShowing ? 'opened' : 'closed') + 
                                     (isInitialState ? ' (initial)' : ' (user action)'));
                        // Only save if this is a user action, not the initial state
                        if (!isInitialState && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                            window.flutter_inappwebview.callHandler('onNavigationHelpDialogStateChanged', isShowing);
                        }
                    });
                }
            }
        }
        
        // Customize home button behavior to return to flight track view
        if (viewer.homeButton && viewer.homeButton.viewModel) {
            cesiumLog.info('Customizing home button behavior for flight track');
            
            // Listen for home button clicks
            viewer.homeButton.viewModel.command.beforeExecute.addEventListener(function(commandInfo) {
                // If we have flight track entities, fly to them
                const trackEntities = cesiumState.flyThroughMode.fullTrackEntities || 
                                    (flightTrackEntity ? [flightTrackEntity] : null);
                
                if (trackEntities && trackEntities.length > 0) {
                    cesiumLog.info('Home button: returning to flight track view');
                    
                    // Cancel the default behavior
                    commandInfo.cancel = true;
                    
                    // Fly to the track entities with the saved offset
                    const offset = cesiumState.flightTrackHomeView?.offset || 
                                 new Cesium.HeadingPitchRange(
                                     Cesium.Math.toRadians(0),
                                     Cesium.Math.toRadians(-45),
                                     0
                                 );
                    
                    viewer.flyTo(trackEntities, {
                        duration: 3.0,
                        offset: offset
                    });
                } else {
                    // No flight track loaded, let default behavior proceed
                    cesiumLog.info('Home button: using default view (no flight track)');
                }
            });
        }
        
    } catch (error) {
        cesiumLog.error('Initialization error: ' + error.message);
        if (config.debug) {
            cesiumLog.error('Stack: ' + error.stack);
        }
        document.getElementById('loadingOverlay').innerHTML = 'Error loading Cesium: ' + error.message;
    }
}

// === PHASE 1 FEATURES: 3D Terrain, Flight Track, Camera Controls ===

// Feature 1: Terrain controls
function setTerrainExaggeration(value) {
    if (!viewer || !viewer.scene || !viewer.scene.globe) return;
    
    currentTerrainExaggeration = value;
    viewer.scene.globe.terrainExaggeration = value;
    viewer.scene.globe.terrainExaggerationRelativeHeight = 0.0;
}

function switchBaseMap(mapType) {
    if (!viewer) return;
    
    const layers = viewer.imageryLayers;
    layers.removeAll();
    
    switch(mapType) {
        case 'satellite':
            // Default Bing Maps aerial
            layers.addImageryProvider(new Cesium.BingMapsImageryProvider({
                url: 'https://dev.virtualearth.net',
                mapStyle: Cesium.BingMapsStyle.AERIAL_WITH_LABELS
            }));
            break;
        case 'terrain':
            // OpenStreetMap
            layers.addImageryProvider(new Cesium.OpenStreetMapImageryProvider({
                url: 'https://a.tile.openstreetmap.org/'
            }));
            break;
        case 'hybrid':
            // Satellite with labels
            layers.addImageryProvider(new Cesium.BingMapsImageryProvider({
                url: 'https://dev.virtualearth.net',
                mapStyle: Cesium.BingMapsStyle.AERIAL_WITH_LABELS_ON_DEMAND
            }));
            break;
        default:
            // Ion default imagery
            layers.addImageryProvider(new Cesium.IonImageryProvider({ assetId: 2 }));
    }
    
    cesiumLog.info('Base map switched to: ' + mapType);
}

// Helper functions for managing multiple track segments
function showAllTrackSegments(show) {
    if (cesiumState.flyThroughMode.fullTrackEntities) {
        cesiumState.flyThroughMode.fullTrackEntities.forEach(entity => {
            if (entity && entity.polyline) {
                entity.polyline.show = show;
            }
        });
    } else if (cesiumState.flyThroughMode.fullTrackEntity && cesiumState.flyThroughMode.fullTrackEntity.polyline) {
        // Fallback for single entity (backwards compatibility)
        cesiumState.flyThroughMode.fullTrackEntity.polyline.show = show;
    }
}

// Feature 2: 3D Flight Track Rendering
// Create flight track with Cesium-native features
function createColoredFlightTrack(points) {
    if (!viewer || !points || points.length === 0) return;
    
    igcPoints = points;
    
    // Extract and store timezone from the first point if available
    let trackTimezone = '+00:00'; // Default to UTC
    let timezoneOffsetSeconds = 0; // Offset in seconds for time calculations
    
    // Debug: Check what's in the first point
    if (points.length > 0) {
    }
    
    if (points.length > 0 && points[0].timezone) {
        trackTimezone = points[0].timezone;
        cesiumLog.info('Track timezone detected: ' + trackTimezone);
        
        // Parse timezone offset for display adjustments
        const tzMatch = trackTimezone.match(/^([+-])(\d{2}):(\d{2})$/);
        if (tzMatch) {
            const sign = tzMatch[1] === '+' ? 1 : -1;
            const hours = parseInt(tzMatch[2], 10);
            const minutes = parseInt(tzMatch[3], 10);
            timezoneOffsetSeconds = sign * ((hours * 3600) + (minutes * 60));
            cesiumLog.info('Timezone offset in seconds: ' + timezoneOffsetSeconds);
        }
        
        // Store timezone globally for display formatting
        window.flightTimezone = trackTimezone;
        window.flightTimezoneOffsetSeconds = timezoneOffsetSeconds;
        
        // Configure Animation widget to show local time
        if (viewer.animation && timezoneOffsetSeconds !== 0) {
            cesiumLog.info('Configuring Animation widget for timezone: ' + trackTimezone);
            
            // Store original formatters
            const originalDateFormatter = viewer.animation.viewModel.dateFormatter;
            const originalTimeFormatter = viewer.animation.viewModel.timeFormatter;
            
            // Override date formatter to show local date
            viewer.animation.viewModel.dateFormatter = function(julianDate, viewModel) {
                // Add timezone offset to show local time
                const localJulianDate = Cesium.JulianDate.addSeconds(
                    julianDate, 
                    timezoneOffsetSeconds, 
                    new Cesium.JulianDate()
                );
                const gregorian = Cesium.JulianDate.toGregorianDate(localJulianDate);
                
                // Format the date
                const year = gregorian.year;
                const month = (gregorian.month).toString().padStart(2, '0');
                const day = gregorian.day.toString().padStart(2, '0');
                
                return year + '-' + month + '-' + day;
            };
            
            // Override time formatter to show local time with timezone
            viewer.animation.viewModel.timeFormatter = function(julianDate, viewModel) {
                // Add timezone offset to show local time
                const localJulianDate = Cesium.JulianDate.addSeconds(
                    julianDate,
                    timezoneOffsetSeconds,
                    new Cesium.JulianDate()
                );
                const gregorian = Cesium.JulianDate.toGregorianDate(localJulianDate);
                
                const hours = gregorian.hour.toString().padStart(2, '0');
                const minutes = gregorian.minute.toString().padStart(2, '0');
                const seconds = Math.floor(gregorian.second).toString().padStart(2, '0');
                
                // Include timezone indicator
                return hours + ':' + minutes + ':' + seconds + ' ' + trackTimezone;
            };
            
            cesiumLog.info('Animation widget configured for local time display');
        }
        
        // Configure Timeline to show local time
        if (viewer.timeline && timezoneOffsetSeconds !== 0) {
            cesiumLog.info('Configuring Timeline for timezone: ' + trackTimezone);
            
            // Override the timeline's date formatter to show local time
            viewer.timeline.makeLabel = function(date) {
                // Add timezone offset to the Julian date to get local time
                const localJulianDate = Cesium.JulianDate.addSeconds(date, timezoneOffsetSeconds, new Cesium.JulianDate());
                const gregorian = Cesium.JulianDate.toGregorianDate(localJulianDate);
                
                // Format as HH:MM:SS with timezone indicator
                const hours = gregorian.hour.toString().padStart(2, '0');
                const minutes = gregorian.minute.toString().padStart(2, '0');
                const seconds = Math.floor(gregorian.second).toString().padStart(2, '0');
                
                return hours + ':' + minutes + ':' + seconds + ' ' + trackTimezone;
            };
            
            cesiumLog.info('Timeline configured for local time display');
        }
    } else {
        cesiumLog.info('No timezone information found in track data, using UTC');
    }
    
    // Clear existing entities
    viewer.entities.removeAll();
    playbackState.showPilot = null;
    
    // Helper function to get color based on 15s climb rate
    function getClimbRateColorForPoint(climbRate15s) {
        if (climbRate15s >= 0) {
            return Cesium.Color.GREEN; // Green: Any climb (rate >= 0 m/s)
        } else if (climbRate15s > -1.5) {
            return Cesium.Color.DODGERBLUE; // Blue: Weak sink (-1.5 < rate < 0 m/s)
        } else {
            return Cesium.Color.RED; // Red: Strong sink (rate <= -1.5 m/s)
        }
    }
    
    // Create colored segments based on 15s climb rate
    const segments = [];
    let currentSegment = null;
    
    for (let i = 0; i < points.length; i++) {
        const point = points[i];
        const climbRate15s = point.climbRate15s || point.climbRate || 0; // Use 15s rate, fallback to instantaneous
        const color = getClimbRateColorForPoint(climbRate15s);
        
        const position = Cesium.Cartesian3.fromDegrees(
            point.longitude,
            point.latitude,
            point.altitude
        );
        
        // Check if we need to start a new segment (color changed)
        if (!currentSegment || !color.equals(currentSegment.color)) {
            // Save previous segment if it has at least 2 points
            if (currentSegment && currentSegment.positions.length >= 2) {
                segments.push(currentSegment);
            }
            
            // Start new segment with overlap point for continuity
            currentSegment = {
                color: color,
                positions: currentSegment && currentSegment.positions.length > 0 
                    ? [currentSegment.positions[currentSegment.positions.length - 1], position]
                    : [position]
            };
        } else {
            currentSegment.positions.push(position);
        }
    }
    
    // Add the last segment
    if (currentSegment && currentSegment.positions.length >= 2) {
        segments.push(currentSegment);
    }
    
    // Create polyline entities for each segment
    const trackEntities = [];
    segments.forEach((segment, index) => {
        const entity = viewer.entities.add({
            name: `Flight Track Segment ${index + 1}`,
            show: true,
            polyline: {
                positions: segment.positions,
                width: 3,
                material: segment.color.withAlpha(0.9),
                clampToGround: false,
                show: true
            }
        });
        trackEntities.push(entity);
    });
    
    // Store reference to first entity for framing (or create a combined entity)
    flightTrackEntity = trackEntities[0] || null;
    
    // Store all track entities for fly-through mode management
    cesiumState.flyThroughMode.fullTrackEntities = trackEntities;
    cesiumState.flyThroughMode.fullTrackEntity = flightTrackEntity; // Keep for compatibility
    
    cesiumLog.info(`Created colored track with ${segments.length} segments`);
    
    // Create curtain wall that hangs from track to ground
    // Build positions array for the wall (all track points)
    const wallPositions = points.map(point => 
        Cesium.Cartesian3.fromDegrees(
            point.longitude,
            point.latitude,
            point.altitude
        )
    );
    
    // Extract altitudes for the wall
    const wallHeights = points.map(point => point.altitude);
    
    const curtainWallEntity = viewer.entities.add({
        name: 'Flight Track Curtain',
        show: true,  // Visible by default
        wall: {
            positions: wallPositions,  // All track positions
            maximumHeights: wallHeights,  // Flight altitudes
            // minimumHeights not specified = extends to ground automatically
            material: Cesium.Color.DODGERBLUE.withAlpha(0.1),  // 10% opaque
            outline: false
        }
    });
    
    // Store curtain wall entity
    cesiumState.flyThroughMode.curtainWallEntity = curtainWallEntity;
    cesiumLog.info('Created curtain wall with ' + wallHeights.length + ' segments');
    
    // Store the igcPoints for global access
    cesiumState.flyThroughMode.igcPoints = igcPoints;
    
    // Set up onTick callback for dynamic updates
    cesiumState.flyThroughMode.onTickCallback = function() {
        // Throttle updates to every 100ms
        const now = Date.now();
        if (!cesiumState.flyThroughMode.lastUpdateTime || 
            now - cesiumState.flyThroughMode.lastUpdateTime > cesiumState.flyThroughMode.updateInterval) {
            cesiumState.flyThroughMode.lastUpdateTime = now;
            updateDynamicTrackPrimitive();
        }
    };
    
    // Add the onTick listener
    viewer.clock.onTick.addEventListener(cesiumState.flyThroughMode.onTickCallback);
    
    // Create dynamic curtain wall for fly-through mode (initially hidden)
    const dynamicCurtainEntity = viewer.entities.add({
        name: 'Dynamic Flight Curtain',
        show: false,  // Initially hidden
        wall: {
            positions: new Cesium.CallbackProperty(function(time, result) {
                // This function will be called every frame to update positions
                if (!cesiumState.flyThroughMode.enabled) {
                    return [];  // Return empty array when disabled
                }
                
                // Use the same trail positions as the dynamic track
                return calculateTrailPositions(time);
            }, false),
            maximumHeights: new Cesium.CallbackProperty(function(time, result) {
                // This function will be called every frame to update heights
                if (!cesiumState.flyThroughMode.enabled) {
                    return [];  // Return empty array when disabled
                }
                
                // Get altitudes for current trail positions
                return calculateTrailAltitudes(time);
            }, false),
            // minimumHeights not specified = extends to ground automatically
            material: Cesium.Color.DODGERBLUE.withAlpha(0.1),  // 10% opaque
            outline: false
        }
    });
    
    cesiumState.flyThroughMode.dynamicCurtainEntity = dynamicCurtainEntity;
    cesiumLog.info('Created dynamic curtain wall for progressive mode');
    
    // Set up time-based animation if timestamps are available
    if (points[0].timestamp) {
        setupTimeBasedAnimation(points);
    } else {
        // Fallback to index-based animation
        playbackState.currentIndex = 0;
        updatePilotPosition(0);
    }
    
    // Zoom to track with padding for UI
    zoomToEntitiesWithPadding(0.9); // 90% screen coverage
    
    cesiumLog.info('Single blue track created with ' + points.length + ' points');
}


// Setup Cesium-native time-based animation
function setupTimeBasedAnimation(points) {
    if (!viewer || !points || points.length === 0) return;
    
    cesiumLog.info('Setting up time-based animation with ' + points.length + ' points');
    
    // Parse timestamps and create time intervals
    const startTime = Cesium.JulianDate.fromIso8601(points[0].timestamp);
    const stopTime = Cesium.JulianDate.fromIso8601(points[points.length - 1].timestamp);
    
    
    // Create sampled position property for smooth interpolation
    const positionProperty = new Cesium.SampledPositionProperty();
    positionProperty.setInterpolationOptions({
        interpolationDegree: 2,
        interpolationAlgorithm: Cesium.LagrangePolynomialApproximation
    });
    
    // Add samples for each point
    let sampleCount = 0;
    points.forEach((point, index) => {
        const time = Cesium.JulianDate.fromIso8601(point.timestamp);
        const position = Cesium.Cartesian3.fromDegrees(
            point.longitude,
            point.latitude,
            point.altitude
        );
        positionProperty.addSample(time, position);
        sampleCount++;
        
        if (index % 100 === 0) {
        }
    });
    
    cesiumLog.info('Added ' + sampleCount + ' position samples');
    
    // Get first position for pilot initialization
    const firstPos = Cesium.Cartesian3.fromDegrees(
        points[0].longitude,
        points[0].latitude,
        points[0].altitude
    );
    
    // Create pilot entity with Cesium native time-dynamic position
    const pilotEntity = viewer.entities.add({
        name: 'Pilot',
        availability: new Cesium.TimeIntervalCollection([
            new Cesium.TimeInterval({
                start: startTime,
                stop: stopTime
            })
        ]),
        position: positionProperty,  // Native Cesium SampledPositionProperty
        // Pilot marker
        point: {
            pixelSize: 16,
            color: Cesium.Color.YELLOW,
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            heightReference: Cesium.HeightReference.NONE,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,  // Always visible
            scaleByDistance: new Cesium.NearFarScalar(1000, 1.5, 100000, 0.5)  // Scale with distance
        }
    });
    
    cesiumLog.info('Created pilot entity with id: ' + pilotEntity.id);
    
    // Store pilot entity reference
    playbackState.showPilot = pilotEntity;
    playbackState.positionProperty = positionProperty;
    
    // Configure viewer clock for playback
    viewer.clock.startTime = startTime.clone();
    viewer.clock.stopTime = stopTime.clone();
    viewer.clock.currentTime = startTime.clone();
    viewer.clock.clockRange = Cesium.ClockRange.CLAMPED; // Stop at end instead of looping
    viewer.clock.multiplier = 60;
    viewer.clock.shouldAnimate = false; // Start paused
    
    cesiumLog.info('Clock configured - start: ' + viewer.clock.startTime.toString() + 
                 ', current: ' + viewer.clock.currentTime.toString());
    
    // Set timeline bounds
    if (viewer.timeline) {
        viewer.timeline.zoomTo(startTime, stopTime);
    }
    
    // Force initial position evaluation
    const initialPosition = positionProperty.getValue(startTime);
    if (initialPosition) {
        cesiumLog.info('Initial pilot position is valid');
    } else {
        cesiumLog.error('Initial pilot position is null!');
    }
    
    // Use the existing pilot entity with time-dynamic position
    playbackState.showPilot = pilotEntity;
    playbackState.positionProperty = positionProperty;
    
    // Show the stats container when track is loaded
    const statsContainer = document.getElementById('statsContainer');
    const cesiumContainer = document.getElementById('cesiumContainer');
    if (statsContainer) {
        statsContainer.classList.add('visible');
        statsContainer.innerHTML = '<span>Initializing...</span>';
        // Resize cesium container to make room for stats
        if (cesiumContainer) {
            cesiumContainer.classList.add('with-stats');
        }
        // Force Cesium to resize after container change
        if (viewer) {
            setTimeout(() => {
                viewer.resize();
            }, 350); // Wait for CSS transition
        }
    }
    
    // Automatic ribbon mode will be managed by clock.onTick listener
    // Start with full track visible (at beginning)
    cesiumState.flyThroughMode.enabled = false;
    
    // Only force continuous rendering if ribbon trail is enabled and playing
    // Otherwise use on-demand rendering for better performance
    if (cesiumState.flyThroughMode.enabled && viewer.clock.shouldAnimate) {
        viewer.scene.requestRenderMode = false;  // Continuous rendering for smooth ribbon
    } else {
        viewer.scene.requestRenderMode = true;  // On-demand rendering when paused or ribbon disabled
    }
    
    // Track animation state for play-at-end detection and automatic ribbon mode
    let wasAnimating = false;
    let previousRibbonState = false;
    
    // Add clock tick listener to update statistics label and manage rendering mode
    viewer.clock.onTick.addEventListener(function(clock) {
        // Check position in timeline
        const atStart = Cesium.JulianDate.secondsDifference(clock.currentTime, clock.startTime) < 0.5;
        const atEnd = Cesium.JulianDate.compare(clock.currentTime, clock.stopTime) >= 0;
        const isStopped = !clock.shouldAnimate;
        
        // Automatic ribbon mode: show full track when stopped at start/end, ribbon otherwise
        const shouldShowRibbon = !(isStopped && (atStart || atEnd));
        
        // Update ribbon mode if changed
        if (shouldShowRibbon !== previousRibbonState) {
            if (shouldShowRibbon) {
                // Enable ribbon mode
                cesiumLog.info('Auto-enabling ribbon trail (playing or mid-flight)');
                
                // Hide full track, show dynamic track
                showAllTrackSegments(false);
                showDynamicTrackSegments(true);
                
                // Hide static curtain, show dynamic curtain
                if (cesiumState.flyThroughMode.curtainWallEntity) {
                    cesiumState.flyThroughMode.curtainWallEntity.show = false;
                }
                if (cesiumState.flyThroughMode.dynamicCurtainEntity) {
                    cesiumState.flyThroughMode.dynamicCurtainEntity.show = true;
                }
                
                cesiumState.flyThroughMode.enabled = true;
            } else {
                // Disable ribbon mode, show full track
                cesiumLog.info('Auto-disabling ribbon trail (stopped at start/end)');
                
                // Show full track, hide dynamic track
                showAllTrackSegments(true);
                showDynamicTrackSegments(false);
                
                // Show static curtain, hide dynamic curtain
                if (cesiumState.flyThroughMode.curtainWallEntity) {
                    cesiumState.flyThroughMode.curtainWallEntity.show = true;
                }
                if (cesiumState.flyThroughMode.dynamicCurtainEntity) {
                    cesiumState.flyThroughMode.dynamicCurtainEntity.show = false;
                }
                
                cesiumState.flyThroughMode.enabled = false;
            }
            previousRibbonState = shouldShowRibbon;
        }
        
        // Check if we just started playing from the end
        const justStartedPlaying = clock.shouldAnimate && !wasAnimating;
        const justStoppedPlaying = !clock.shouldAnimate && wasAnimating;
        
        if (atEnd && justStartedPlaying) {
            // Reset to start when play is clicked at end
            clock.currentTime = clock.startTime.clone();
            cesiumLog.info('Animation reset to start - play clicked at end');
        }
        
        // Manage rendering mode based on animation state and ribbon mode
        if (cesiumState.flyThroughMode.enabled) {
            if (justStartedPlaying) {
                // Just started playing - enable continuous rendering
                viewer.scene.requestRenderMode = false;
            } else if (justStoppedPlaying) {
                // Just paused/stopped - switch to on-demand rendering
                viewer.scene.requestRenderMode = true;
                viewer.scene.requestRender(); // Render once to show current state
            }
        } else {
            // Full track mode - always use on-demand rendering
            if (viewer.scene.requestRenderMode === false) {
                viewer.scene.requestRenderMode = true;
            }
        }
        
        wasAnimating = clock.shouldAnimate;
        
        // Force scene update
        viewer.scene.requestRender();
        
        const statsContainer = document.getElementById('statsContainer');
        if (statsContainer) {
                
                // Find current point index based on time
                const totalSeconds = Cesium.JulianDate.secondsDifference(clock.currentTime, clock.startTime);
                const totalDuration = Cesium.JulianDate.secondsDifference(clock.stopTime, clock.startTime);
                const progress = totalSeconds / totalDuration;
                const currentIndex = Math.min(Math.floor(progress * points.length), points.length - 1);
                
                if (currentIndex >= 0 && currentIndex < points.length) {
                    const currentPoint = points[currentIndex];
                    
                    // Use pre-calculated ground speed if available, otherwise calculate
                    let speed = currentPoint.groundSpeed || 0;
                    if (!speed && currentIndex > 0) {
                        const prevPoint = points[currentIndex - 1];
                        const distance = Cesium.Cartesian3.distance(
                            Cesium.Cartesian3.fromDegrees(prevPoint.longitude, prevPoint.latitude, prevPoint.altitude),
                            Cesium.Cartesian3.fromDegrees(currentPoint.longitude, currentPoint.latitude, currentPoint.altitude)
                        );
                        const timeDiff = Cesium.JulianDate.secondsDifference(
                            Cesium.JulianDate.fromIso8601(currentPoint.timestamp),
                            Cesium.JulianDate.fromIso8601(prevPoint.timestamp)
                        );
                        if (timeDiff > 0) {
                            speed = (distance / timeDiff) * 3.6; // Convert m/s to km/h
                        }
                    }
                    
                    // Get altitude and climb rate (now pre-calculated in IgcPoint)
                    const altitude = currentPoint.gpsAltitude || currentPoint.altitude || 0;
                    const climbRate = currentPoint.climbRate || 0;
                    
                    // Format time (HH:MM format for compact display) in local timezone
                    let timeStr;
                    let tzLabel = '';
                    
                    if (window.flightTimezoneOffsetSeconds && window.flightTimezoneOffsetSeconds !== 0) {
                        // Convert to local time
                        const localJulianDate = Cesium.JulianDate.addSeconds(
                            clock.currentTime,
                            window.flightTimezoneOffsetSeconds,
                            new Cesium.JulianDate()
                        );
                        const gregorian = Cesium.JulianDate.toGregorianDate(localJulianDate);
                        timeStr = gregorian.hour.toString().padStart(2, '0') + ':' + 
                                gregorian.minute.toString().padStart(2, '0');
                        tzLabel = window.flightTimezone ? ' (' + window.flightTimezone + ')' : '';
                    } else {
                        // Fallback to UTC
                        const date = Cesium.JulianDate.toDate(clock.currentTime);
                        timeStr = date.getHours().toString().padStart(2, '0') + ':' + 
                                date.getMinutes().toString().padStart(2, '0');
                        tzLabel = ' (UTC)';
                    }
                    
                    // Choose climb icon based on rate
                    const climbIcon = climbRate > 0.1 ? 'trending_up' : climbRate < -0.1 ? 'trending_down' : 'trending_flat';
                    const climbSign = climbRate >= 0 ? '+' : '';
                    
                    // Create HTML with Material Icons in vertical layout
                    const labelHTML = 
                        '<div class="stat-item">' +
                            '<i class="material-icons">height</i>' +
                            '<div class="stat-value">' + altitude.toFixed(0) + 'm</div>' +
                            '<div class="stat-label">Altitude</div>' +
                        '</div>' +
                        '<div class="stat-item">' +
                            '<i class="material-icons">' + climbIcon + '</i>' +
                            '<div class="stat-value">' + climbSign + climbRate.toFixed(1) + 'm/s</div>' +
                            '<div class="stat-label">Climb</div>' +
                        '</div>' +
                        '<div class="stat-item">' +
                            '<i class="material-icons">speed</i>' +
                            '<div class="stat-value">' + speed.toFixed(1) + 'km/h</div>' +
                            '<div class="stat-label">Speed</div>' +
                        '</div>' +
                        '<div class="stat-item">' +
                            '<i class="material-icons">access_time</i>' +
                            '<div class="stat-value">' + timeStr + '</div>' +
                            '<div class="stat-label">Time' + tzLabel + '</div>' +
                        '</div>';
                    
                    statsContainer.innerHTML = labelHTML;
                }
                
                // Removed debug logging - not needed for production
            }
    });
    
    cesiumLog.info('Time-based animation configured with Cesium native features and clock listener');
}

function getClimbRateColor(climbRate) {
    // Kept for compatibility but no longer used for track visualization
    if (climbRate >= 0) {
        return '#4CAF50';  // Green: Any climb (rate >= 0 m/s)
    } else if (climbRate > -1.5) {
        return '#1976D2';  // Royal Blue: Weak sink (-1.5 < rate < 0 m/s)
    } else {
        return '#FF0000';  // Red: Strong sink (rate <= -1.5 m/s)
    }
}

// Set track transparency
function setTrackOpacity(opacity) {
    if (!viewer) return;
    
    viewer.entities.values.forEach(entity => {
        if (entity.polyline) {
            const material = entity.polyline.material;
            if (material && material.color) {
                entity.polyline.material.color = material.color.getValue().withAlpha(opacity);
            }
        }
    });
    
}

// Feature 3: Camera Controls
function setCameraPreset(preset) {
    if (!viewer || igcPoints.length === 0) return;
    
    // Calculate center of flight
    let minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    let sumAlt = 0;
    
    igcPoints.forEach(point => {
        minLat = Math.min(minLat, point.latitude);
        maxLat = Math.max(maxLat, point.latitude);
        minLon = Math.min(minLon, point.longitude);
        maxLon = Math.max(maxLon, point.longitude);
        sumAlt += point.altitude;
    });
    
    const centerLat = (minLat + maxLat) / 2;
    const centerLon = (minLon + maxLon) / 2;
    const avgAlt = sumAlt / igcPoints.length;
    
    switch(preset) {
        case 'topDown':
            viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(centerLon, centerLat, avgAlt + 5000),
                orientation: {
                    heading: 0,
                    pitch: Cesium.Math.toRadians(-90),
                    roll: 0
                }
            });
            break;
            
        case 'sideProfile':
            viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(centerLon - 0.05, centerLat, avgAlt + 2000),
                orientation: {
                    heading: Cesium.Math.toRadians(90),
                    pitch: 0,
                    roll: 0
                }
            });
            break;
            
        case 'pilotView':
            if (igcPoints.length > 0) {
                const point = igcPoints[Math.floor(igcPoints.length / 2)];
                viewer.camera.setView({
                    destination: Cesium.Cartesian3.fromDegrees(
                        point.longitude,
                        point.latitude,
                        point.altitude
                    ),
                    orientation: {
                        heading: Cesium.Math.toRadians(0),
                        pitch: Cesium.Math.toRadians(-10),
                        roll: 0
                    }
                });
            }
            break;
            
        case 'threeFourView':
            viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(
                    centerLon - 0.03, 
                    centerLat - 0.03, 
                    avgAlt + 3000
                ),
                orientation: {
                    heading: Cesium.Math.toRadians(45),
                    pitch: Cesium.Math.toRadians(-30),
                    roll: 0
                }
            });
            break;
            
        default:
            // Reset to default view with padding
            zoomToEntitiesWithPadding(0.9); // 90% screen coverage
    }
    
    cesiumLog.info('Camera preset: ' + preset);
}

// Zoom to entities with padding for UI elements
function zoomToEntitiesWithPadding(padding) {
    if (!viewer) return;
    
    // If we have multiple track segments, zoom to all of them
    const entitiesToFrame = cesiumState.flyThroughMode.fullTrackEntities || 
                           (flightTrackEntity ? [flightTrackEntity] : []);
    
    if (entitiesToFrame.length === 0) return;
    
    // Use Cesium's built-in entity framing with custom offset
    // This doesn't change the camera transform mode, so left-drag remains pan
    viewer.flyTo(entitiesToFrame, {
        duration: 3.0,
        offset: new Cesium.HeadingPitchRange(
            Cesium.Math.toRadians(0),   // Heading: 0 = North
            Cesium.Math.toRadians(-45), // Pitch: -45 = looking down at 45 degree angle
            0                            // Range: 0 = auto-calculate based on entity size
        )
    }).then(function() {
        // Store this view as the home view for the flight track
        cesiumState.flightTrackHomeView = {
            entities: entitiesToFrame,
            offset: new Cesium.HeadingPitchRange(
                Cesium.Math.toRadians(0),
                Cesium.Math.toRadians(-45),
                0
            )
        };
        cesiumLog.info('Flight track framed in view');
    });
}

// Smooth camera fly to location
function flyToLocation(lon, lat, alt, duration) {
    if (!viewer) return;
    
    viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(lon, lat, alt),
        duration: duration || 3.0,
        complete: function() {
        }
    });
}

// Enable/disable camera controls
function setCameraControlsEnabled(enabled) {
    if (!viewer) return;
    
    const controller = viewer.scene.screenSpaceCameraController;
    controller.enableRotate = enabled;
    controller.enableTranslate = enabled;
    controller.enableZoom = enabled;
    controller.enableTilt = enabled;
    controller.enableLook = enabled;
    
}

// Cleanup function to be called from Flutter before disposal
function cleanupCesium() {
    
    // Hide stats container and restore cesium container size
    const statsContainer = document.getElementById('statsContainer');
    const cesiumContainer = document.getElementById('cesiumContainer');
    if (statsContainer) {
        statsContainer.classList.remove('visible');
        statsContainer.innerHTML = '';
    }
    if (cesiumContainer) {
        cesiumContainer.classList.remove('with-stats');
    }
    
    // Clear the cleanup timer first
    // Cleanup timer removed - using simpler approach
    
    // Remove event listeners
    if (window.viewer && viewer.scene && viewer.scene.globe) {
        viewer.scene.globe.tileLoadProgressEvent.removeAllListeners();
    }
    
    if (window.viewer) {
        try {
            // Stop rendering immediately
            viewer.scene.requestRenderMode = true;
            viewer.scene.maximumRenderTimeChange = 0;
            
            // Clear all data
            if (viewer.scene && viewer.scene.primitives) {
                viewer.scene.primitives.removeAll();
            }
            if (viewer.entities) {
                viewer.entities.removeAll();
            }
            if (viewer.dataSources) {
                viewer.dataSources.removeAll();
            }
            
            // Clear tile cache
            if (viewer.scene && viewer.scene.globe && viewer.scene.globe.tileCache) {
                viewer.scene.globe.tileCache.reset();
            }
            
            // Destroy the viewer safely
            try {
                viewer.destroy();
            } catch (destroyError) {
                // Expected during cleanup - ignore
            }
            
            window.viewer = null;
        } catch (e) {
            cesiumLog.error('Error during cleanup: ' + e.message);
            // Force clear the viewer reference even if cleanup fails
            window.viewer = null;
        }
    }
}

// Simple memory check for debugging
function checkMemory() {
    if (window.performance && window.performance.memory) {
        const memory = window.performance.memory;
        return {
            used: Math.round(memory.usedJSHeapSize / 1048576),
            total: Math.round(memory.totalJSHeapSize / 1048576),
            limit: Math.round(memory.jsHeapSizeLimit / 1048576)
        };
    }
    return null;
}

// Also cleanup on page unload
window.addEventListener('beforeunload', function() {
    cleanupCesium();
});

// Handle visibility changes to pause/resume rendering
document.addEventListener('visibilitychange', function() {
    if (window.viewer) {
        if (document.hidden) {
            viewer.scene.requestRenderMode = true;
            viewer.scene.maximumRenderTimeChange = Infinity;
        } else {
            viewer.scene.requestRenderMode = false;
        }
    }
});

// === PHASE 2 FEATURES: Flight Playback and Animation ===

// Playback state
let playbackState = {
    isPlaying: false,
    currentIndex: 0,
    playbackSpeed: 60.0,  // Default to 60x speed
    followMode: false,
    showPilot: null,
    animationFrame: null,
    lastUpdateTime: null,
    accumulatedTime: 0,
    positionProperty: null,  // For Cesium native time-based animation
    lastLoggedSecond: -1  // For debug logging
};

// Feature 3: Follow mode for flight playback
function setFollowMode(enabled) {
    if (!viewer) return;
    
    playbackState.followMode = enabled;
    
    if (enabled && playbackState.showPilot) {
        // Use Cesium's native entity tracking
        viewer.trackedEntity = playbackState.showPilot;
        
        // Set camera offset for better view
        const offset = new Cesium.Cartesian3(-500, -500, 300);
        viewer.scene.screenSpaceCameraController.enableRotate = true;
        viewer.scene.screenSpaceCameraController.enableTranslate = true;
        
        cesiumLog.info('Follow mode enabled with Cesium entity tracking');
    } else {
        // Disable tracking
        viewer.trackedEntity = undefined;
        cesiumLog.info('Follow mode disabled');
    }
}

function followFlightPoint(index) {
    if (!viewer || !igcPoints || index < 0 || index >= igcPoints.length) return;
    
    const point = igcPoints[index];
    
    // Calculate heading to next point for realistic orientation
    let heading = 0;
    if (index < igcPoints.length - 1) {
        const nextPoint = igcPoints[index + 1];
        heading = Cesium.Math.toRadians(
            Math.atan2(
                nextPoint.longitude - point.longitude,
                nextPoint.latitude - point.latitude
            ) * 180 / Math.PI
        );
    }
    
    // Position camera behind and above the pilot
    const offsetDistance = 100; // meters behind
    const offsetHeight = 50; // meters above
    
    viewer.camera.setView({
        destination: Cesium.Cartesian3.fromDegrees(
            point.longitude,
            point.latitude,
            point.altitude + offsetHeight
        ),
        orientation: {
            heading: heading,
            pitch: Cesium.Math.toRadians(-10), // Look slightly down
            roll: 0
        }
    });
    
    // Update pilot position
    updatePilotPosition(index);
}

// Update pilot marker position - DEPRECATED: Now handled by time-based animation
function updatePilotPosition(index) {
    // This function is kept for backward compatibility but does nothing
    // The pilot position is now controlled by Cesium's clock and SampledPositionProperty
    return;
}

// ============================================================================
// Fly-through Mode Functions
// ============================================================================

// Helper function to get color based on 15s climb rate (for dynamic track)
function getClimbRateColorForPoint(climbRate15s) {
    if (climbRate15s >= 0) {
        return Cesium.Color.GREEN; // Green: Any climb (rate >= 0 m/s)
    } else if (climbRate15s > -1.5) {
        return Cesium.Color.DODGERBLUE; // Blue: Weak sink (-1.5 < rate < 0 m/s)
    } else {
        return Cesium.Color.RED; // Red: Strong sink (rate <= -1.5 m/s)
    }
}

// Function to update the dynamic track primitive with per-vertex colors
function updateDynamicTrackPrimitive() {
    if (!viewer || !cesiumState.flyThroughMode.igcPoints || cesiumState.flyThroughMode.igcPoints.length === 0) {
        return;
    }
    
    // Remove old primitive if exists
    if (cesiumState.flyThroughMode.dynamicTrackPrimitive) {
        viewer.scene.primitives.remove(cesiumState.flyThroughMode.dynamicTrackPrimitive);
        cesiumState.flyThroughMode.dynamicTrackPrimitive = null;
    }
    
    // Only create new primitive if fly-through mode is enabled and track should be shown
    if (!cesiumState.flyThroughMode.enabled || !cesiumState.flyThroughMode.showDynamicTrack) {
        return;
    }
    
    const igcPoints = cesiumState.flyThroughMode.igcPoints;
    
    // Find current point index based on time
    const currentTime = viewer.clock.currentTime;
    let currentIndex = -1;
    for (let i = 0; i < igcPoints.length; i++) {
        const point = igcPoints[i];
        if (!point.timestamp) continue;
        
        try {
            const pointTime = Cesium.JulianDate.fromIso8601(point.timestamp);
            if (Cesium.JulianDate.secondsDifference(pointTime, currentTime) > 0) {
                break; // Found first point after current time
            }
            currentIndex = i;
        } catch (e) {
            continue;
        }
    }
    
    // If we haven't started yet, return
    if (currentIndex < 0) {
        return;
    }
    
    // Calculate window size based on ribbon settings
    const ribbonSeconds = cesiumState.flyThroughMode.ribbonAnimationSeconds || 3.0;
    const playbackSpeed = viewer.clock.multiplier || 60.0;
    const flightSecondsInWindow = ribbonSeconds * playbackSpeed;
    
    // Estimate how many points to show based on flight duration
    const totalDuration = Cesium.JulianDate.secondsDifference(
        Cesium.JulianDate.fromIso8601(igcPoints[igcPoints.length - 1].timestamp),
        Cesium.JulianDate.fromIso8601(igcPoints[0].timestamp)
    );
    const pointsPerSecond = igcPoints.length / totalDuration;
    const windowSize = Math.ceil(flightSecondsInWindow * pointsPerSecond);
    
    // Calculate window bounds
    const windowStart = Math.max(0, currentIndex - windowSize + 1);
    const windowEnd = currentIndex; // Never go past current position
    
    // Build positions and colors arrays for the window
    const positions = [];
    const colors = [];
    
    for (let i = windowStart; i <= windowEnd && i < igcPoints.length; i++) {
        const point = igcPoints[i];
        
        // Add position
        positions.push(
            Cesium.Cartesian3.fromDegrees(
                point.longitude,
                point.latitude,
                point.altitude
            )
        );
        
        // Add color based on climb rate
        const climbRate15s = point.climbRate15s || point.climbRate || 0;
        const color = getClimbRateColorForPoint(climbRate15s);
        colors.push(color.withAlpha(0.9)); // Slightly transparent
    }
    
    // Only create primitive if we have at least 2 positions
    if (positions.length < 2) {
        return;
    }
    
    // Create the polyline primitive with per-vertex colors
    const primitive = new Cesium.Primitive({
        geometryInstances: new Cesium.GeometryInstance({
            geometry: new Cesium.PolylineGeometry({
                positions: positions,
                width: 3.0,
                vertexFormat: Cesium.PolylineColorAppearance.VERTEX_FORMAT,
                colors: colors,
                colorsPerVertex: true
            })
        }),
        appearance: new Cesium.PolylineColorAppearance({
            translucent: true
        })
    });
    
    // Add to scene
    cesiumState.flyThroughMode.dynamicTrackPrimitive = viewer.scene.primitives.add(primitive);
}

// Show or hide the dynamic track
function showDynamicTrackSegments(show) {
    // Handle primitive visibility through updates
    cesiumState.flyThroughMode.showDynamicTrack = show;
    
    if (!show && cesiumState.flyThroughMode.dynamicTrackPrimitive) {
        // Remove the primitive when hiding
        viewer.scene.primitives.remove(cesiumState.flyThroughMode.dynamicTrackPrimitive);
        cesiumState.flyThroughMode.dynamicTrackPrimitive = null;
    } else if (show) {
        // Force an update to create the primitive when showing
        updateDynamicTrackPrimitive();
    }
}

// Note: Dynamic segment creation/update functions removed - segments are now pre-created at initialization

// Calculate trail positions for ribbon mode (animation-time based)
// Shows a ribbon trail of X seconds of animation time behind the pilot
// This creates a consistent visual trail regardless of playback speed
function calculateTrailPositions(currentTime) {
    if (!viewer || !igcPoints || igcPoints.length === 0) {
        return [];
    }
    
    // Build positions array - show all points up to current time
    const trailPositions = [];
    let pointsInTrail = 0;
    
    for (let i = 0; i < igcPoints.length; i++) {
        const point = igcPoints[i];
        
        // Skip points without timestamps
        if (!point.timestamp) {
            continue;
        }
        
        // Parse the point's timestamp
        let pointTime;
        try {
            pointTime = Cesium.JulianDate.fromIso8601(point.timestamp);
        } catch (e) {
            continue;
        }
        
        // Check if point is before or at current time
        const secondsFromCurrent = Cesium.JulianDate.secondsDifference(pointTime, currentTime);
        
        // Include all points up to current time for progressive track
        if (secondsFromCurrent <= 0) {
            trailPositions.push(
                Cesium.Cartesian3.fromDegrees(
                    point.longitude,
                    point.latitude,
                    point.altitude
                )
            );
            pointsInTrail++;
        } else {
            // We've passed the current time, stop checking
            break;
        }
    }
    
    // For ribbon mode, we only want the last N seconds worth of points
    if (cesiumState.flyThroughMode.ribbonMode === 'animation-time' && trailPositions.length > 0) {
        const ribbonAnimationSeconds = cesiumState.flyThroughMode.ribbonAnimationSeconds;
        
        // Calculate how many points to keep based on animation time
        // At 60x speed, 3 seconds of animation = 180 seconds of flight time
        const speedMultiplier = viewer.clock.multiplier || 1;
        const flightSecondsInRibbon = ribbonAnimationSeconds * speedMultiplier;
        
        // Estimate points per second (assuming roughly uniform sampling)
        const totalFlightDuration = Cesium.JulianDate.secondsDifference(
            Cesium.JulianDate.fromIso8601(igcPoints[igcPoints.length - 1].timestamp),
            Cesium.JulianDate.fromIso8601(igcPoints[0].timestamp)
        );
        const pointsPerSecond = igcPoints.length / totalFlightDuration;
        const maxPointsInRibbon = Math.ceil(flightSecondsInRibbon * pointsPerSecond);
        
        // Keep only the last N points for the ribbon
        if (trailPositions.length > maxPointsInRibbon) {
            const startIndex = trailPositions.length - maxPointsInRibbon;
            return trailPositions.slice(startIndex);
        }
    }
    
    // Very rare debug logging to avoid spam when paused
    if (Math.random() < 0.001) { // Log 0.1% of the time
    }
    
    return trailPositions;
}

// Calculate trail altitudes for the curtain wall in ribbon mode
function calculateTrailAltitudes(currentTime) {
    if (!viewer || !igcPoints || igcPoints.length === 0) {
        return [];
    }
    
    // Build altitudes array - match the positions array
    const trailAltitudes = [];
    let pointCount = 0;
    
    for (let i = 0; i < igcPoints.length; i++) {
        const point = igcPoints[i];
        
        // Skip points without timestamps
        if (!point.timestamp) {
            continue;
        }
        
        // Parse the point's timestamp
        let pointTime;
        try {
            pointTime = Cesium.JulianDate.fromIso8601(point.timestamp);
        } catch (e) {
            continue;
        }
        
        // Check if point is before or at current time
        const secondsFromCurrent = Cesium.JulianDate.secondsDifference(pointTime, currentTime);
        
        // Include all points up to current time
        if (secondsFromCurrent <= 0) {
            trailAltitudes.push(point.altitude);
            pointCount++;
        } else {
            // We've passed the current time, stop checking
            break;
        }
    }
    
    // For ribbon mode, match the positions array length
    if (cesiumState.flyThroughMode.ribbonMode === 'animation-time' && trailAltitudes.length > 0) {
        const ribbonAnimationSeconds = cesiumState.flyThroughMode.ribbonAnimationSeconds;
        const speedMultiplier = viewer.clock.multiplier || 1;
        const flightSecondsInRibbon = ribbonAnimationSeconds * speedMultiplier;
        
        const totalFlightDuration = Cesium.JulianDate.secondsDifference(
            Cesium.JulianDate.fromIso8601(igcPoints[igcPoints.length - 1].timestamp),
            Cesium.JulianDate.fromIso8601(igcPoints[0].timestamp)
        );
        const pointsPerSecond = igcPoints.length / totalFlightDuration;
        const maxPointsInRibbon = Math.ceil(flightSecondsInRibbon * pointsPerSecond);
        
        if (trailAltitudes.length > maxPointsInRibbon) {
            const startIndex = trailAltitudes.length - maxPointsInRibbon;
            return trailAltitudes.slice(startIndex);
        }
    }
    
    return trailAltitudes;
}

// Set fly-through mode (now internally managed based on playback state)
// This function is kept for potential manual override but is primarily controlled automatically
function setFlyThroughMode(enabled) {
    if (!viewer) {
        cesiumLog.error('Cannot set fly-through mode: viewer not initialized');
        return;
    }
    
    cesiumState.flyThroughMode.enabled = enabled;
    
    if (enabled) {
        // Enable fly-through mode
        
        // Ensure we have track entities
        if (!cesiumState.flyThroughMode.fullTrackEntity || !cesiumState.flyThroughMode.dynamicTrackEntity) {
            cesiumLog.error('Track entities not initialized - cannot enable fly-through mode');
            cesiumState.flyThroughMode.enabled = false;
            return;
        }
        
        // Hide full track (polylines only, not affecting pilot)
        showAllTrackSegments(false);
        
        // Show dynamic track
        showDynamicTrackSegments(true);
        
        // Hide static curtain wall
        if (cesiumState.flyThroughMode.curtainWallEntity) {
            cesiumState.flyThroughMode.curtainWallEntity.show = false;
        }
        
        // Show dynamic curtain wall
        if (cesiumState.flyThroughMode.dynamicCurtainEntity) {
            cesiumState.flyThroughMode.dynamicCurtainEntity.show = true;
        }
        
        // Only enable continuous rendering if animation is playing
        // This will be managed by clock event listeners
        if (viewer.clock.shouldAnimate) {
            viewer.scene.requestRenderMode = false; // Continuous rendering
        } else {
            viewer.scene.requestRenderMode = true; // On-demand rendering
        }
        
        // Ensure animation is running for ribbon to work
        if (!viewer.clock.shouldAnimate) {
            cesiumLog.info('Starting animation for ribbon trail');
            viewer.clock.shouldAnimate = true;
            // Enable continuous rendering when we start animation
            viewer.scene.requestRenderMode = false;
        }
        
        // If clock multiplier is 0, set to default speed
        if (viewer.clock.multiplier === 0) {
            viewer.clock.multiplier = 60; // Default 60x speed
            cesiumLog.info('Set clock multiplier to 60x for ribbon trail');
        }
        
        // Force initial render to update the dynamic track
        viewer.scene.requestRender();
        
        // Debug: Check if we have points
        
        // Debug: Check clock state
        if (viewer.clock) {
        }
        
        // Debug: Test calculate trail positions with current time
        if (viewer.clock && viewer.clock.currentTime) {
            const testPositions = calculateTrailPositions(viewer.clock.currentTime);
            
            // If we have positions, log details about first and last
            if (testPositions.length > 0) {
            }
        }
    } else {
        // Disable fly-through mode
        
        // Switch back to on-demand rendering when ribbon mode is disabled
        viewer.scene.requestRenderMode = true;
        
        // Show full track (polylines only, not affecting pilot)
        showAllTrackSegments(true);
        
        // Hide dynamic track segments
        showDynamicTrackSegments(false);
        
        // Show static curtain wall
        if (cesiumState.flyThroughMode.curtainWallEntity) {
            cesiumState.flyThroughMode.curtainWallEntity.show = true;
        }
        
        // Hide dynamic curtain wall
        if (cesiumState.flyThroughMode.dynamicCurtainEntity) {
            cesiumState.flyThroughMode.dynamicCurtainEntity.show = false;
        }
    }
    
    // No longer sending to Flutter since this is automatic
}

// Set the trail duration for fly-through mode
function setTrailDuration(seconds) {
    if (seconds < 1 || seconds > 60) {
        cesiumLog.error('Invalid trail duration: ' + seconds + ' seconds (must be 1-60)');
        return;
    }
    
    cesiumState.flyThroughMode.trailDuration = seconds * 1000; // Convert to milliseconds
    
    // Force update if fly-through mode is active
    if (cesiumState.flyThroughMode.enabled && viewer) {
        viewer.scene.requestRender();
    }
    
    // Send state change to Flutter
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('onTrailDurationChanged', seconds);
    }
}

// Get current fly-through mode state
function getFlyThroughMode() {
    return cesiumState.flyThroughMode.enabled;
}

// Get current trail duration in seconds (deprecated - kept for compatibility)
function getTrailDuration() {
    return cesiumState.flyThroughMode.trailDuration / 1000;
}

// Set ribbon duration in animation seconds
function setRibbonDuration(seconds) {
    if (seconds < 0.5 || seconds > 10) {
        cesiumLog.error('Invalid ribbon duration: ' + seconds + ' seconds (must be 0.5-10)');
        return;
    }
    
    cesiumState.flyThroughMode.ribbonAnimationSeconds = seconds;
    
    // Force update if fly-through mode is active
    if (cesiumState.flyThroughMode.enabled && viewer) {
        viewer.scene.requestRender();
    }
    
    // Send state change to Flutter (optional)
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('onRibbonDurationChanged', seconds);
    }
}

// Get current ribbon duration in animation seconds
function getRibbonDuration() {
    return cesiumState.flyThroughMode.ribbonAnimationSeconds;
}


// ============================================================================
// Scene Mode Management Functions
// ============================================================================

// Capture the current camera view for preservation during mode changes
function captureCurrentView() {
    if (!viewer || !viewer.camera) {
        return null;
    }
    
    const camera = viewer.camera;
    const scene = viewer.scene;
    
    // Get the current view rectangle (works in all modes)
    const rectangle = camera.computeViewRectangle(scene.globe.ellipsoid);
    
    // Also capture camera height/altitude for better restoration
    let altitude = 0;
    if (scene.mode === Cesium.SceneMode.SCENE3D || scene.mode === Cesium.SceneMode.COLUMBUS_VIEW) {
        // In 3D or Columbus mode, get the camera height
        const cartographic = camera.positionCartographic;
        if (cartographic) {
            altitude = cartographic.height;
        }
    } else if (scene.mode === Cesium.SceneMode.SCENE2D) {
        // In 2D mode, estimate altitude from the view size
        if (rectangle) {
            const width = Cesium.Math.toDegrees(rectangle.east - rectangle.west);
            const height = Cesium.Math.toDegrees(rectangle.north - rectangle.south);
            // Rough estimation: larger view = higher altitude
            altitude = Math.max(width, height) * 111000; // Convert degrees to meters approximately
        }
    }
    
    const savedView = {
        rectangle: rectangle,
        altitude: altitude,
        heading: camera.heading,
        pitch: camera.pitch,
        roll: camera.roll
    };
    
    return savedView;
}

// Restore the camera view after a mode change
function restoreCameraView(savedView, targetMode) {
    if (!viewer || !savedView || !viewer.camera) {
        return;
    }
    
    const camera = viewer.camera;
    
    try {
        if (savedView.rectangle) {
            // Calculate the center of the view rectangle
            const west = savedView.rectangle.west;
            const east = savedView.rectangle.east;
            const north = savedView.rectangle.north;
            const south = savedView.rectangle.south;
            
            const centerLon = (west + east) / 2;
            const centerLat = (north + south) / 2;
            
            // Calculate an appropriate altitude based on the view extent
            let altitude = savedView.altitude || 10000; // Default to 10km if not available
            
            if (targetMode === Cesium.SceneMode.SCENE2D) {
                // In 2D mode, set the view rectangle directly
                camera.setView({
                    destination: savedView.rectangle
                });
            } else if (targetMode === Cesium.SceneMode.SCENE3D) {
                // In 3D mode, position camera at the center with appropriate altitude
                const position = Cesium.Cartesian3.fromRadians(centerLon, centerLat, altitude);
                
                camera.setView({
                    destination: position,
                    orientation: {
                        heading: savedView.heading || 0,
                        pitch: savedView.pitch || -Cesium.Math.PI_OVER_TWO, // Look down
                        roll: savedView.roll || 0
                    }
                });
            } else if (targetMode === Cesium.SceneMode.COLUMBUS_VIEW) {
                // Columbus view - similar to 3D but with different projection
                const position = Cesium.Cartesian3.fromRadians(centerLon, centerLat, altitude);
                
                camera.setView({
                    destination: position,
                    orientation: {
                        heading: savedView.heading || 0,
                        pitch: savedView.pitch || -Cesium.Math.PI_OVER_TWO,
                        roll: savedView.roll || 0
                    }
                });
            }
        }
    } catch (e) {
        cesiumLog.error('Failed to restore camera view: ' + e.message);
    }
}

// Toggle navigation help dialog open/closed
function setNavigationHelpDialogOpen(open) {
    if (!viewer || !viewer.navigationHelpButton || !viewer.navigationHelpButton.viewModel) {
        cesiumLog.error('Cannot toggle navigation help dialog: not available');
        return;
    }
    
    const navHelpVM = viewer.navigationHelpButton.viewModel;
    if (navHelpVM.showInstructions !== undefined) {
        navHelpVM.showInstructions = open;
        cesiumLog.info('Navigation help dialog set to: ' + (open ? 'open' : 'closed'));
    }
}

// Set the scene mode (2D, 3D, or Columbus View)
function setSceneMode(mode) {
    if (!viewer) {
        cesiumLog.error('Cannot set scene mode: viewer not initialized');
        return;
    }
    
    // Convert string mode to Cesium.SceneMode enum
    let sceneMode;
    switch(mode) {
        case '2D':
        case 2:
        case Cesium.SceneMode.SCENE2D:
            sceneMode = Cesium.SceneMode.SCENE2D;
            break;
        case '3D':
        case 3:
        case Cesium.SceneMode.SCENE3D:
            sceneMode = Cesium.SceneMode.SCENE3D;
            break;
        case 'COLUMBUS':
        case 2.5:
        case Cesium.SceneMode.COLUMBUS_VIEW:
            sceneMode = Cesium.SceneMode.COLUMBUS_VIEW;
            break;
        default:
            cesiumLog.error('Invalid scene mode: ' + mode);
            return;
    }
    
    // Only change if different from current mode
    if (viewer.scene.mode !== sceneMode) {
        cesiumLog.info('Changing scene mode to: ' + getSceneModeString(sceneMode));
        
        // Capture current view before morphing
        const savedView = captureCurrentView();
        
        // Use morphing for smooth transition
        const duration = 2.0; // 2 second transition
        switch(sceneMode) {
            case Cesium.SceneMode.SCENE2D:
                viewer.scene.morphTo2D(duration);
                break;
            case Cesium.SceneMode.SCENE3D:
                viewer.scene.morphTo3D(duration);
                break;
            case Cesium.SceneMode.COLUMBUS_VIEW:
                viewer.scene.morphToColumbusView(duration);
                break;
        }
        
        // Restore view after morph completes
        viewer.scene.morphComplete.addEventListener(function restoreView() {
            // Remove this one-time listener
            viewer.scene.morphComplete.removeEventListener(restoreView);
            
            // Restore the saved view with a small delay to ensure morph is fully complete
            setTimeout(() => {
                if (savedView) {
                    restoreCameraView(savedView, sceneMode);
                }
            }, 100);
        });
        
        // Save preference
        saveSceneModePreference(sceneMode);
    }
}

// Get the current scene mode
function getSceneMode() {
    if (!viewer) {
        return null;
    }
    return getSceneModeString(viewer.scene.mode);
}

// Toggle between 2D and 3D modes
function toggleSceneMode() {
    if (!viewer) {
        cesiumLog.error('Cannot toggle scene mode: viewer not initialized');
        return;
    }
    
    const currentMode = viewer.scene.mode;
    const newMode = (currentMode === Cesium.SceneMode.SCENE3D) 
        ? Cesium.SceneMode.SCENE2D 
        : Cesium.SceneMode.SCENE3D;
    
    setSceneMode(newMode);
}

// Convert Cesium.SceneMode enum to string
function getSceneModeString(mode) {
    switch(mode) {
        case Cesium.SceneMode.SCENE2D:
            return '2D';
        case Cesium.SceneMode.SCENE3D:
            return '3D';
        case Cesium.SceneMode.COLUMBUS_VIEW:
            return 'COLUMBUS';
        default:
            return 'UNKNOWN';
    }
}

// Save scene mode preference to localStorage
function saveSceneModePreference(mode) {
    try {
        // Check if localStorage is available (may not be in WebView)
        if (typeof(Storage) !== "undefined" && window.localStorage) {
            localStorage.setItem('cesium_scene_mode', mode.toString());
        } else {
        }
    } catch (e) {
    }
}

// Load scene mode preference from localStorage
function loadSceneModePreference() {
    try {
        // Check if localStorage is available (may not be in WebView)
        if (typeof(Storage) !== "undefined" && window.localStorage) {
            const saved = localStorage.getItem('cesium_scene_mode');
            if (saved !== null) {
                const mode = parseInt(saved);
                return mode;
            }
        }
    } catch (e) {
        // Expected in WebView context - preferences handled by Flutter
    }
    return Cesium.SceneMode.SCENE3D; // Default to 3D
}

// Event handler for scene mode changes
function onSceneModeChanged() {
    cesiumState.sceneMode = viewer.scene.mode;
    cesiumState.sceneModeChanging = false;
    
    const modeString = getSceneModeString(viewer.scene.mode);
    cesiumLog.info('Scene mode changed to: ' + modeString);
    
    // Notify Flutter of the change
    if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('onSceneModeChanged', modeString);
    }
    
    // Adjust terrain settings based on mode
    if (viewer.scene.mode === Cesium.SceneMode.SCENE2D) {
        // In 2D mode, terrain doesn't make sense
        // Store current terrain state if needed
        if (viewer.terrainProvider && !(viewer.terrainProvider instanceof Cesium.EllipsoidTerrainProvider)) {
            cesiumState.previousTerrainProvider = viewer.terrainProvider;
        }
        // viewer.terrainProvider = new Cesium.EllipsoidTerrainProvider();
        
        // Adjust camera constraints for 2D
        viewer.scene.screenSpaceCameraController.enableRotate = false;
        viewer.scene.screenSpaceCameraController.enableTilt = false;
    } else {
        // In 3D or Columbus mode, restore terrain if it was previously enabled
        if (cesiumState.previousTerrainProvider) {
            // viewer.terrainProvider = cesiumState.previousTerrainProvider;
        }
        
        // Enable full camera controls
        viewer.scene.screenSpaceCameraController.enableRotate = true;
        viewer.scene.screenSpaceCameraController.enableTilt = true;
    }
    
    // Ensure flight track is visible in new mode
    if (flightTrackEntity && viewer.scene.mode === Cesium.SceneMode.SCENE2D) {
        // Adjust entity properties for 2D if needed
        flightTrackEntity.polyline.clampToGround = false;
    }
    
    // Restore camera view if it was saved before morphing (for scene mode picker usage)
    if (cesiumState.savedViewBeforeMorph) {
        setTimeout(() => {
            restoreCameraView(cesiumState.savedViewBeforeMorph, viewer.scene.mode);
            cesiumState.savedViewBeforeMorph = null; // Clear after use
        }, 100);
    }
}

// Event handler for when scene mode is changing
function onSceneModeChanging() {
    cesiumState.sceneModeChanging = true;
    
    // Capture the current view before the morph starts
    // This handles cases where the user uses the scene mode picker directly
    cesiumState.savedViewBeforeMorph = captureCurrentView();
}


// Playback functions removed - using native Cesium Animation and Timeline widgets

// Export functions for Flutter access
window.cleanupCesium = cleanupCesium;
window.checkMemory = checkMemory;
window.initializeCesium = initializeCesium;

// Phase 1 Feature exports
window.setTerrainExaggeration = setTerrainExaggeration;
window.switchBaseMap = switchBaseMap;
window.createColoredFlightTrack = createColoredFlightTrack;
window.setTrackOpacity = setTrackOpacity;
window.setCameraPreset = setCameraPreset;
window.flyToLocation = flyToLocation;
window.setCameraControlsEnabled = setCameraControlsEnabled;
window.getClimbRateColor = getClimbRateColor;

// Phase 2 Feature exports (Playback)
window.setFollowMode = setFollowMode;

// Scene mode management exports
window.setSceneMode = setSceneMode;
window.setNavigationHelpDialogOpen = setNavigationHelpDialogOpen;
window.getSceneMode = getSceneMode;
window.toggleSceneMode = toggleSceneMode;

// Fly-through mode exports
window.setFlyThroughMode = setFlyThroughMode;
window.getFlyThroughMode = getFlyThroughMode;
window.setTrailDuration = setTrailDuration;
window.getTrailDuration = getTrailDuration;
window.setRibbonDuration = setRibbonDuration;
window.getRibbonDuration = getRibbonDuration;