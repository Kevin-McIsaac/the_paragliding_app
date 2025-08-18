// Cesium 3D Map JavaScript Module
// Handles initialization, memory management, and lifecycle

// Simplified state management
const cesiumState = {
    flyThroughMode: {
        enabled: false,
        staticTrackPrimitive: null,
        dynamicTrackPrimitive: null,
        showDynamicTrack: false,
        igcPoints: null,
        lastWindowStart: -1,
        lastWindowEnd: -1,
        curtainWallEntity: null,
        dynamicCurtainEntity: null,
        lastUpdateTime: null,
        updateInterval: 100,
        ribbonAnimationSeconds: 3.0,
        onTickCallback: null
    },
    flightTrackHomeView: null
};

// Global variables
let viewer = null;
let igcPoints = [];

// Simplified logging
const cesiumLog = {
    debug: (message) => {
        if (window.cesiumConfig && window.cesiumConfig.debug) {
            console.log('[Cesium Debug] ' + message);
        }
    },
    info: (message) => console.log('[Cesium] ' + message),
    error: (message) => console.error('[Cesium Error] ' + message)
};

// Main initialization function
function initializeCesium(config) {
    // Set Cesium Ion token
    Cesium.Ion.defaultAccessToken = config.token;
    
    
    // Store track points if provided during initialization
    const hasInitialTrack = config.trackPoints && config.trackPoints.length > 0;
    
    try {
        // Essential imagery providers
        const imageryViewModels = [
            new Cesium.ProviderViewModel({
                name: 'Bing Maps Aerial with Labels',
                iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/bingAerialLabels.png'),
                tooltip: 'Bing Maps aerial imagery with labels',
                creationFunction: () => Cesium.IonImageryProvider.fromAssetId(3)
            }),
            new Cesium.ProviderViewModel({
                name: 'Bing Maps Aerial',
                iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/bingAerial.png'),
                tooltip: 'Bing Maps aerial imagery without labels',
                creationFunction: () => Cesium.IonImageryProvider.fromAssetId(2)
            }),
            new Cesium.ProviderViewModel({
                name: 'Bing Maps Roads',
                iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/bingRoads.png'),
                tooltip: 'Bing Maps road imagery',
                creationFunction: () => Cesium.IonImageryProvider.fromAssetId(4)
            }),
            new Cesium.ProviderViewModel({
                name: 'OpenStreetMap',
                iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/openStreetMap.png'),
                tooltip: 'OpenStreetMap',
                creationFunction: () => new Cesium.OpenStreetMapImageryProvider({
                    url: 'https://a.tile.openstreetmap.org/'
                })
            })
        ];
        
        // Apply saved base map preference or use default
        const selectedImageryProvider = config.savedBaseMap ? 
            imageryViewModels.find(vm => vm.name === config.savedBaseMap) || imageryViewModels[0] :
            imageryViewModels[0];
        
        // Simplified Cesium viewer settings
        viewer = new Cesium.Viewer("cesiumContainer", {
            terrain: Cesium.Terrain.fromWorldTerrain({
                requestWaterMask: false,
                requestVertexNormals: true
            }),
            requestRenderMode: true,  // Only render on demand
            maximumRenderTimeChange: Infinity,
            
            // Essential UI controls
            baseLayerPicker: true,
            imageryProviderViewModels: imageryViewModels,
            selectedImageryProviderViewModel: selectedImageryProvider,
            geocoder: true,
            homeButton: true,
            sceneModePicker: true,
            navigationHelpButton: true,
            navigationInstructionsInitiallyVisible: config.savedNavigationHelpDialogOpen || false,
            animation: true,
            timeline: true,
            fullscreenButton: true,
            vrButton: false,
            shadows: false,
            shouldAnimate: false,  // Start paused
        });
        
        
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
        
        // Set terrain exaggeration to 1.0 for accurate GPS altitude representation
        viewer.scene.globe.terrainExaggeration = 1.0;  // No exaggeration - true GPS altitudes
        viewer.scene.globe.terrainExaggerationRelativeHeight = 0.0;
        
        // Configure imagery provider for better performance
        const imageryProvider = viewer.imageryLayers.get(0);
        if (imageryProvider) {
            imageryProvider.brightness = 1.0;
            imageryProvider.contrast = 1.0;
            imageryProvider.saturation = 1.0;
        }
        
        // Apply saved scene mode preference
        if (config.savedSceneMode && config.savedSceneMode !== '3D') {
            const sceneMode = config.savedSceneMode === '2D' ? Cesium.SceneMode.SCENE2D :
                             config.savedSceneMode === 'Columbus' ? Cesium.SceneMode.COLUMBUS_VIEW :
                             Cesium.SceneMode.SCENE3D;
            viewer.scene.mode = sceneMode;
        }
        
        // Set initial camera view if no track points provided
        if (!hasInitialTrack) {
            viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(config.lon, config.lat, config.altitude),
                orientation: {
                    heading: 0,
                    pitch: Cesium.Math.toRadians(-45),
                    roll: 0
                }
            });
        }
        
        // Basic layer picker event handling
        if (viewer.baseLayerPicker) {
            const imageryObservable = Cesium.knockout.getObservable(
                viewer.baseLayerPicker.viewModel, 
                'selectedImagery'
            );
            imageryObservable.subscribe(function(newImagery) {
                if (newImagery && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('onImageryProviderChanged', newImagery.name);
                }
            });
        }
        
        // Simple loading overlay handler
        const tileLoadHandler = function(queuedTileCount) {
            if (queuedTileCount === 0) {
                document.getElementById('loadingOverlay').style.display = 'none';
                viewer.scene.globe.tileLoadProgressEvent.removeEventListener(tileLoadHandler);
            }
        };
        viewer.scene.globe.tileLoadProgressEvent.addEventListener(tileLoadHandler);
        
        // Fly-through mode is automatic based on playback state
        
        // If track points were provided, create the track immediately
        if (hasInitialTrack) {
            // Use a small delay to ensure viewer is fully ready
            setTimeout(() => {
                createColoredFlightTrack(config.trackPoints);
            }, 100);
        }
        
        // Store viewer globally for cleanup
        window.viewer = viewer;
        
        // Add scene mode change listener
        viewer.scene.morphComplete.addEventListener(onSceneModeChanged);
        
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
                                      (config.savedNavigationHelpDialogOpen ? 'open' : 'closed'));
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
        
        // Basic home button behavior - custom flight track view if available
        if (viewer.homeButton && viewer.homeButton.viewModel) {
            viewer.homeButton.viewModel.command.beforeExecute.addEventListener(function(commandInfo) {
                if (cesiumState.flyThroughMode.staticTrackPrimitive && cesiumState.flightTrackHomeView?.boundingSphere) {
                    commandInfo.cancel = true;
                    viewer.camera.flyToBoundingSphere(cesiumState.flightTrackHomeView.boundingSphere, {
                        duration: 3.0,
                        offset: cesiumState.flightTrackHomeView.offset
                    });
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

// Show or hide all track segments
function showAllTrackSegments(show) {
    if (cesiumState.flyThroughMode.staticTrackPrimitive) {
        cesiumState.flyThroughMode.staticTrackPrimitive.show = show;
    }
}

// Feature 2: 3D Flight Track Rendering
// Create flight track with Cesium-native features
function createColoredFlightTrack(points) {
    if (!viewer || !points || points.length === 0) return;
    
    igcPoints = points;
    
    // Extract timezone from first point
    let trackTimezone = '+00:00';
    let timezoneOffsetSeconds = 0;
    
    if (points[0]?.timezone) {
        trackTimezone = points[0].timezone;
        
        // Parse timezone offset for display adjustments
        const tzMatch = trackTimezone.match(/^([+-])(\d{2}):(\d{2})$/);
        if (tzMatch) {
            const sign = tzMatch[1] === '+' ? 1 : -1;
            const hours = parseInt(tzMatch[2], 10);
            const minutes = parseInt(tzMatch[3], 10);
            timezoneOffsetSeconds = sign * ((hours * 3600) + (minutes * 60));
        }
        
        // Store timezone globally for display formatting
        window.flightTimezone = trackTimezone;
        window.flightTimezoneOffsetSeconds = timezoneOffsetSeconds;
        
        // Configure Animation widget to show local time
        if (viewer.animation && timezoneOffsetSeconds !== 0) {
            viewer.animation.viewModel.dateFormatter = function(julianDate) {
                const localJulianDate = Cesium.JulianDate.addSeconds(julianDate, timezoneOffsetSeconds, new Cesium.JulianDate());
                const gregorian = Cesium.JulianDate.toGregorianDate(localJulianDate);
                return `${gregorian.year}-${gregorian.month.toString().padStart(2, '0')}-${gregorian.day.toString().padStart(2, '0')}`;
            };
            
            viewer.animation.viewModel.timeFormatter = function(julianDate) {
                const localJulianDate = Cesium.JulianDate.addSeconds(julianDate, timezoneOffsetSeconds, new Cesium.JulianDate());
                const gregorian = Cesium.JulianDate.toGregorianDate(localJulianDate);
                const hours = gregorian.hour.toString().padStart(2, '0');
                const minutes = gregorian.minute.toString().padStart(2, '0');
                const seconds = Math.floor(gregorian.second).toString().padStart(2, '0');
                return `${hours}:${minutes}:${seconds} ${trackTimezone}`;
            };
        }
        
        // Configure Timeline to show local time
        if (viewer.timeline && timezoneOffsetSeconds !== 0) {
            viewer.timeline.makeLabel = function(date) {
                const localJulianDate = Cesium.JulianDate.addSeconds(date, timezoneOffsetSeconds, new Cesium.JulianDate());
                const gregorian = Cesium.JulianDate.toGregorianDate(localJulianDate);
                const hours = gregorian.hour.toString().padStart(2, '0');
                const minutes = gregorian.minute.toString().padStart(2, '0');
                const seconds = Math.floor(gregorian.second).toString().padStart(2, '0');
                return `${hours}:${minutes}:${seconds} ${trackTimezone}`;
            };
        }
    }
    
    // Clear existing entities
    viewer.entities.removeAll();
    playbackState.showPilot = null;
    // Build positions and colors arrays for per-vertex colored primitive
    const positions = [];
    const colors = [];
    
    for (let i = 0; i < points.length; i++) {
        const point = points[i];
        
        // Add position
        positions.push(
            Cesium.Cartesian3.fromDegrees(
                point.longitude,
                point.latitude,
                point.altitude
            )
        );
        
        // Add color based on 15s climb rate
        const climbRate15s = point.climbRate15s || point.climbRate || 0;
        const color = getClimbRateColorForPoint(climbRate15s);
        colors.push(color.withAlpha(0.9)); // Slightly transparent
    }
    
    // Create a single primitive with per-vertex colors for smooth gradients
    const staticTrackPrimitive = new Cesium.Primitive({
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
        }),
        asynchronous: false  // Synchronous rendering for consistency
    });
    
    // Add primitive to scene
    cesiumState.flyThroughMode.staticTrackPrimitive = viewer.scene.primitives.add(staticTrackPrimitive);
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
                
                return calculateTrailAltitudes(time);
            }, false),
            // minimumHeights not specified = extends to ground automatically
            material: Cesium.Color.DODGERBLUE.withAlpha(0.1),  // 10% opaque
            outline: false
        }
    });
    
    cesiumState.flyThroughMode.dynamicCurtainEntity = dynamicCurtainEntity;
    
    // Set up time-based animation if timestamps are available
    if (points[0].timestamp) {
        setupTimeBasedAnimation(points);
    } else {
        // Fallback to index-based animation (simplified)
    }
    
    // Zoom to track with padding for UI
    zoomToEntitiesWithPadding(0.9); // 90% screen coverage
    
}


// Setup Cesium-native time-based animation
function setupTimeBasedAnimation(points) {
    if (!viewer || !points || points.length === 0) return;
    
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
        
    });
    
    
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
    
    
    // Set timeline bounds
    if (viewer.timeline) {
        viewer.timeline.zoomTo(startTime, stopTime);
    }
    
    // Force initial position evaluation
    const initialPosition = positionProperty.getValue(startTime);
    if (!initialPosition) {
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
                
            }
    });
}

// Feature 3: Camera Controls

// Zoom to entities with padding for UI elements
function zoomToEntitiesWithPadding(padding) {
    if (!viewer) return;
    
    // If we have a primitive-based track, zoom to its bounds
    if (cesiumState.flyThroughMode.staticTrackPrimitive && igcPoints && igcPoints.length > 0) {
        // Calculate bounding sphere from track points
        const positions = igcPoints.map(point => 
            Cesium.Cartesian3.fromDegrees(point.longitude, point.latitude, point.altitude)
        );
        const boundingSphere = Cesium.BoundingSphere.fromPoints(positions);
        
        // Get launch coordinates from first point
        const launchPoint = igcPoints[0];
        const launchLon = launchPoint.longitude;
        const launchLat = launchPoint.latitude;
        
        // Step 1: Set initial view at 30,000 km above launch
        viewer.camera.setView({
            destination: Cesium.Cartesian3.fromDegrees(launchLon, launchLat, 30000000), // 30,000 km
            orientation: {
                heading: 0,
                pitch: Cesium.Math.toRadians(-90), // Looking straight down
                roll: 0
            }
        });
        
        // Step 2: Wait 5 seconds, then fly to bounding sphere view
        setTimeout(function() {
            viewer.camera.flyToBoundingSphere(boundingSphere, {
                duration: 5.0,
                offset: new Cesium.HeadingPitchRange(
                    Cesium.Math.toRadians(0),   // Heading: 0 = North
                    Cesium.Math.toRadians(-90), // Pitch: -90 = looking straight down
                    boundingSphere.radius * 2.5  // Range: 2.5x the radius for good framing
                ),
                complete: function() {
                    // Step 3: Fly to home view with -30 degree angle
                    viewer.camera.flyToBoundingSphere(boundingSphere, {
                        duration: 3.0,
                        offset: new Cesium.HeadingPitchRange(
                            Cesium.Math.toRadians(0),   // Heading: 0 = North
                            Cesium.Math.toRadians(-30), // Pitch: -30 = looking down at 30 degree angle
                            boundingSphere.radius * 2.75  // Range: 2.75x the radius for better framing
                        )
                    });
                }
            });
        }, 5000);
        
        // Store this view as the home view for the flight track
        cesiumState.flightTrackHomeView = {
            boundingSphere: boundingSphere,
            offset: new Cesium.HeadingPitchRange(
                Cesium.Math.toRadians(0),
                Cesium.Math.toRadians(-30),
                boundingSphere.radius * 2.75
            )
        };
    }
}


// Cleanup function
function cleanupCesium() {
    // Hide stats container
    const statsContainer = document.getElementById('statsContainer');
    const cesiumContainer = document.getElementById('cesiumContainer');
    if (statsContainer) {
        statsContainer.classList.remove('visible');
        statsContainer.innerHTML = '';
    }
    if (cesiumContainer) {
        cesiumContainer.classList.remove('with-stats');
    }
    
    if (window.viewer) {
        try {
            // Stop rendering and clear data
            viewer.scene.requestRenderMode = true;
            viewer.scene.primitives.removeAll();
            viewer.entities.removeAll();
            viewer.dataSources.removeAll();
            
            // Clear tile cache and destroy viewer
            if (viewer.scene.globe?.tileCache) {
                viewer.scene.globe.tileCache.reset();
            }
            
            viewer.destroy();
        } catch (e) {
            cesiumLog.error('Cleanup error: ' + e.message);
        } finally {
            window.viewer = null;
        }
    }
}

// Memory check for debugging
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

// Minimal playback state - only for pilot entity tracking
let playbackState = {
    showPilot: null,
    positionProperty: null  // For Cesium native time-based animation
};


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
    
    // Only create new primitive if fly-through mode is enabled and track should be shown
    if (!cesiumState.flyThroughMode.enabled || !cesiumState.flyThroughMode.showDynamicTrack) {
        // If we should hide, remove existing primitive
        if (cesiumState.flyThroughMode.dynamicTrackPrimitive) {
            viewer.scene.primitives.remove(cesiumState.flyThroughMode.dynamicTrackPrimitive);
            cesiumState.flyThroughMode.dynamicTrackPrimitive = null;
            cesiumState.flyThroughMode.lastWindowStart = -1;
            cesiumState.flyThroughMode.lastWindowEnd = -1;
        }
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
    
    // Calculate window size based on ribbon settings (matching wall logic exactly)
    const ribbonSeconds = cesiumState.flyThroughMode.ribbonAnimationSeconds || 3.0;
    const playbackSpeed = viewer.clock.multiplier || 1;  // Use 1 as default like the wall
    const flightSecondsInWindow = ribbonSeconds * playbackSpeed;
    
    // Estimate how many points to show based on flight duration
    const totalDuration = Cesium.JulianDate.secondsDifference(
        Cesium.JulianDate.fromIso8601(igcPoints[igcPoints.length - 1].timestamp),
        Cesium.JulianDate.fromIso8601(igcPoints[0].timestamp)
    );
    const pointsPerSecond = igcPoints.length / totalDuration;
    const maxPointsInRibbon = Math.ceil(flightSecondsInWindow * pointsPerSecond);
    
    // Calculate window bounds - matching wall's slice logic exactly
    // The wall keeps the last maxPointsInRibbon points from 0 to currentIndex
    const pointsUpToCurrent = currentIndex + 1;  // Number of points from 0 to currentIndex inclusive
    const windowStart = Math.max(0, pointsUpToCurrent - maxPointsInRibbon);
    const windowEnd = currentIndex; // Never go past current position
    
    // Check if window has changed - skip update if unchanged
    if (windowStart === cesiumState.flyThroughMode.lastWindowStart && 
        windowEnd === cesiumState.flyThroughMode.lastWindowEnd) {
        return; // No change needed, avoid flickering
    }
    
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
    
    // Create the polyline primitive with per-vertex colors (synchronous to prevent flickering)
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
        }),
        asynchronous: false  // Synchronous rendering to prevent flickering
    });
    
    // Double buffering: Add new primitive before removing old one
    const oldPrimitive = cesiumState.flyThroughMode.dynamicTrackPrimitive;
    cesiumState.flyThroughMode.dynamicTrackPrimitive = viewer.scene.primitives.add(primitive);
    
    // Remove old primitive after new one is added
    if (oldPrimitive) {
        viewer.scene.primitives.remove(oldPrimitive);
    }
    
    // Update tracking for next comparison
    cesiumState.flyThroughMode.lastWindowStart = windowStart;
    cesiumState.flyThroughMode.lastWindowEnd = windowEnd;
}

// Show or hide the dynamic track
function showDynamicTrackSegments(show) {
    // Handle primitive visibility through updates
    cesiumState.flyThroughMode.showDynamicTrack = show;
    
    if (!show && cesiumState.flyThroughMode.dynamicTrackPrimitive) {
        // Remove the primitive when hiding
        viewer.scene.primitives.remove(cesiumState.flyThroughMode.dynamicTrackPrimitive);
        cesiumState.flyThroughMode.dynamicTrackPrimitive = null;
        // Reset window tracking
        cesiumState.flyThroughMode.lastWindowStart = -1;
        cesiumState.flyThroughMode.lastWindowEnd = -1;
    } else if (show) {
        // Reset window tracking to force update when showing
        cesiumState.flyThroughMode.lastWindowStart = -1;
        cesiumState.flyThroughMode.lastWindowEnd = -1;
        // Force an update to create the primitive when showing
        updateDynamicTrackPrimitive();
    }
}


// Helper function to get trail data for ribbon mode
function getTrailData(currentTime, extractData) {
    if (!viewer || !igcPoints || igcPoints.length === 0) {
        return [];
    }
    
    const trailData = [];
    
    for (let i = 0; i < igcPoints.length; i++) {
        const point = igcPoints[i];
        
        if (!point.timestamp) continue;
        
        let pointTime;
        try {
            pointTime = Cesium.JulianDate.fromIso8601(point.timestamp);
        } catch (e) {
            continue;
        }
        
        const secondsFromCurrent = Cesium.JulianDate.secondsDifference(pointTime, currentTime);
        
        if (secondsFromCurrent <= 0) {
            trailData.push(extractData(point));
        } else {
            break;
        }
    }
    
    // Apply ribbon window
    if (trailData.length > 0) {
        const ribbonAnimationSeconds = cesiumState.flyThroughMode.ribbonAnimationSeconds;
        const speedMultiplier = viewer.clock.multiplier || 1;
        const flightSecondsInRibbon = ribbonAnimationSeconds * speedMultiplier;
        
        const totalFlightDuration = Cesium.JulianDate.secondsDifference(
            Cesium.JulianDate.fromIso8601(igcPoints[igcPoints.length - 1].timestamp),
            Cesium.JulianDate.fromIso8601(igcPoints[0].timestamp)
        );
        const pointsPerSecond = igcPoints.length / totalFlightDuration;
        const maxPointsInRibbon = Math.ceil(flightSecondsInRibbon * pointsPerSecond);
        
        if (trailData.length > maxPointsInRibbon) {
            return trailData.slice(trailData.length - maxPointsInRibbon);
        }
    }
    
    return trailData;
}

// Calculate trail positions for ribbon mode
function calculateTrailPositions(currentTime) {
    return getTrailData(currentTime, point => 
        Cesium.Cartesian3.fromDegrees(point.longitude, point.latitude, point.altitude)
    );
}

// Calculate trail altitudes for ribbon mode
function calculateTrailAltitudes(currentTime) {
    return getTrailData(currentTime, point => point.altitude);
}

// ============================================================================
// Scene Mode Management Functions
// ============================================================================

// Get scene mode as string
function getSceneModeString(sceneMode) {
    switch(sceneMode) {
        case Cesium.SceneMode.SCENE2D:
            return '2D';
        case Cesium.SceneMode.COLUMBUS_VIEW:
            return 'Columbus';
        case Cesium.SceneMode.SCENE3D:
            return '3D';
        default:
            return '3D';
    }
}

// Event handler for scene mode changes
function onSceneModeChanged() {
    const modeString = getSceneModeString(viewer.scene.mode);
    cesiumLog.info('Scene mode changed to: ' + modeString);
    
    // Notify Flutter of the change
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('onSceneModeChanged', modeString);
    }
    
    // Restore camera to flight track view if available
    if (cesiumState.flightTrackHomeView && cesiumState.flightTrackHomeView.boundingSphere) {
        // Small delay to ensure scene mode transition is complete
        setTimeout(() => {
            viewer.camera.flyToBoundingSphere(cesiumState.flightTrackHomeView.boundingSphere, {
                duration: 2.0,
                offset: cesiumState.flightTrackHomeView.offset
            });
            cesiumLog.info('Camera restored to flight track view after scene mode change');
        }, 500);
    }
}

// Export functions for Flutter access
window.cleanupCesium = cleanupCesium;
window.checkMemory = checkMemory;
window.initializeCesium = initializeCesium;

window.createColoredFlightTrack = createColoredFlightTrack;

// End of file