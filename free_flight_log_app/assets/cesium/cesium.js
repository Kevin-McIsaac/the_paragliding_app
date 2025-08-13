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
    sceneModeChanging: false  // Flag to track if scene mode is changing
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
            selectedImageryProviderViewModel: imageryViewModels[0],  // Default to Bing Aerial
            terrainProviderViewModels: terrainViewModels,  // Use custom limited terrain providers
            selectedTerrainProviderViewModel: terrainViewModels[0],  // Default to World Terrain
            geocoder: true,
            homeButton: false,  // Remove home button as requested
            sceneModePicker: true,
            navigationHelpButton: true,
            animation: true,  // Enable native animation widget
            timeline: true,   // Enable native timeline widget
            fullscreenButton: true,
            vrButton: false,
            infoBox: false,
            selectionIndicator: true,
            shadows: false,
            shouldAnimate: false,  // Start paused
        });
        
        cesiumLog.debug('Cesium viewer created, configuring aggressive memory optimizations...');
        
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
        viewer.scene.globe.depthTestAgainstTerrain = true;  // Enable terrain occlusion
        viewer.scene.screenSpaceCameraController.enableCollisionDetection = false;
        
        // Enhanced tile cache management for quality
        viewer.scene.globe.tileCacheSize = 200;  // Larger cache for smoother experience
        viewer.scene.globe.preloadSiblings = true;  // Preload adjacent tiles for smoother panning
        viewer.scene.globe.preloadAncestors = false;  // Don't preload parent tiles
        
        // Tile memory budget - increase for better quality
        viewer.scene.globe.maximumMemoryUsage = 512;  // Higher memory limit for better quality
        
        // Better quality with reasonable performance
        viewer.scene.globe.maximumScreenSpaceError = 3;  // Good quality with reasonable tile count
        
        // Higher texture resolution
        viewer.scene.maximumTextureSize = 2048;  // Higher resolution textures
        
        // Set explicit tile load limits
        viewer.scene.globe.loadingDescendantLimit = 15;  // Balanced concurrent tile loads
        viewer.scene.globe.immediatelyLoadDesiredLevelOfDetail = false;  // Progressive loading for better performance
        
        // Enable FXAA for better edge quality
        viewer.scene.fxaa = true;
        viewer.scene.msaaSamples = 4;  // Multi-sample anti-aliasing
        
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
        
        // Handle tile memory exceeded events
        viewer.scene.globe.tileLoadProgressEvent.addEventListener(function() {
            // Monitor for memory issues
            const globe = viewer.scene.globe;
            if (globe._surface && globe._surface._tilesToRender) {
                const tileCount = globe._surface._tilesToRender.length;
                if (tileCount > 50) {  // Increased threshold for higher quality settings
                    // Only log occasionally to reduce spam
                    if (Math.random() < 0.1) {  // Log 10% of the time
                        cesiumLog.debug('High tile count: ' + tileCount);
                    }
                    // Temporarily increase screen space error to reduce tile count
                    viewer.scene.globe.maximumScreenSpaceError = 4;  // Less aggressive reduction
                    
                    // Reset after a delay
                    setTimeout(() => {
                        viewer.scene.globe.maximumScreenSpaceError = 3;  // Reset to our new default
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
                    cesiumLog.debug('Tiles queued: ' + queuedTileCount);
                    lastTileCount = queuedTileCount;
                }
            }
        };
        viewer.scene.globe.tileLoadProgressEvent.addEventListener(tileLoadHandler);
        
        // Simple memory management - let browser handle most cleanup
        
        cesiumLog.info('Cesium viewer initialized successfully');
        
        // If track points were provided, create the track immediately
        if (hasInitialTrack) {
            cesiumLog.info('Creating initial track with ' + config.trackPoints.length + ' points');
            // Use a small delay to ensure viewer is fully ready
            setTimeout(() => {
                createColoredFlightTrack(config.trackPoints);
                cesiumLog.info('Initial track created and view set');
            }, 100);
        } else {
            cesiumLog.debug('Camera position: lat=' + config.lat + ', lon=' + config.lon + ', altitude=' + config.altitude);
        }
        
        // Store viewer globally for cleanup
        window.viewer = viewer;
        
        
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
    cesiumLog.debug('Terrain exaggeration set to: ' + value);
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
        cesiumLog.debug('First point keys: ' + Object.keys(points[0]).join(', '));
        cesiumLog.debug('First point timezone field: ' + points[0].timezone);
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
    
    // Convert points to Cartesian3 positions for the single polyline
    const positions = points.map(point => 
        Cesium.Cartesian3.fromDegrees(
            point.longitude,
            point.latitude,
            point.altitude
        )
    );
    
    // Create single blue polyline for entire track
    const trackEntity = viewer.entities.add({
        name: 'Flight Track',
        polyline: {
            positions: positions,
            width: 3,
            material: Cesium.Color.DODGERBLUE.withAlpha(0.9),
            clampToGround: false,
            show: true
        }
    });
    
    // Set up time-based animation if timestamps are available
    if (points[0].timestamp) {
        setupTimeBasedAnimation(points);
    } else {
        // Fallback to index-based animation
        playbackState.currentIndex = 0;
        updatePilotPosition(0);
    }
    
    // Zoom to track with padding for UI
    zoomToEntitiesWithPadding(0.3); // 30% padding
    
    cesiumLog.info('Single blue track created with ' + points.length + ' points');
}


// Setup Cesium-native time-based animation
function setupTimeBasedAnimation(points) {
    if (!viewer || !points || points.length === 0) return;
    
    cesiumLog.info('Setting up time-based animation with ' + points.length + ' points');
    cesiumLog.debug('First point timestamp: ' + points[0].timestamp);
    cesiumLog.debug('Last point timestamp: ' + points[points.length - 1].timestamp);
    
    // Parse timestamps and create time intervals
    const startTime = Cesium.JulianDate.fromIso8601(points[0].timestamp);
    const stopTime = Cesium.JulianDate.fromIso8601(points[points.length - 1].timestamp);
    
    cesiumLog.debug('Start time: ' + startTime.toString());
    cesiumLog.debug('Stop time: ' + stopTime.toString());
    
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
            cesiumLog.debug('Added sample ' + index + ' at time: ' + time.toString());
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
    
    // Force scene rendering on each frame to ensure pilot updates
    viewer.scene.requestRenderMode = false;  // Disable request render mode to force continuous rendering
    
    // Track animation state for play-at-end detection
    let wasAnimating = false;
    
    // Add clock tick listener to update statistics label
    viewer.clock.onTick.addEventListener(function(clock) {
        // Check if we just started playing from the end
        const atEnd = Cesium.JulianDate.compare(clock.currentTime, clock.stopTime) >= 0;
        const justStartedPlaying = clock.shouldAnimate && !wasAnimating;
        
        if (atEnd && justStartedPlaying) {
            // Reset to start when play is clicked at end
            clock.currentTime = clock.startTime.clone();
            cesiumLog.info('Animation reset to start - play clicked at end');
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
                
                // Debug log every 30 seconds of simulation time
                const seconds = Cesium.JulianDate.secondsDifference(clock.currentTime, clock.startTime);
                if (Math.floor(seconds) % 30 === 0 && Math.floor(seconds) !== playbackState.lastLoggedSecond) {
                    playbackState.lastLoggedSecond = Math.floor(seconds);
                    cesiumLog.debug('Stats update - time: ' + seconds.toFixed(0) + 's, index: ' + currentIndex);
                }
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
    
    cesiumLog.debug('Track opacity set to: ' + opacity);
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
            zoomToEntitiesWithPadding(0.3);
    }
    
    cesiumLog.info('Camera preset: ' + preset);
}

// Zoom to entities with padding for UI elements
function zoomToEntitiesWithPadding(padding) {
    if (!viewer || viewer.entities.values.length === 0) return;
    
    // Get the bounding sphere of all entities
    viewer.zoomTo(viewer.entities).then(function() {
        // After initial zoom, adjust the camera to add padding
        if (padding && padding > 0) {
            // Move camera back by the padding percentage
            var camera = viewer.camera;
            var distance = Cesium.Cartesian3.distance(camera.position, camera.pickEllipsoid(new Cesium.Cartesian2(
                viewer.canvas.clientWidth / 2,
                viewer.canvas.clientHeight / 2
            )));
            
            if (distance) {
                camera.moveBackward(distance * padding);
            }
        }
    });
}

// Smooth camera fly to location
function flyToLocation(lon, lat, alt, duration) {
    if (!viewer) return;
    
    viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(lon, lat, alt),
        duration: duration || 3.0,
        complete: function() {
            cesiumLog.debug('Camera transition complete');
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
    
    cesiumLog.debug('Camera controls ' + (enabled ? 'enabled' : 'disabled'));
}

// Cleanup function to be called from Flutter before disposal
function cleanupCesium() {
    cesiumLog.debug('Cleaning up Cesium resources...');
    
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
                cesiumLog.debug('Viewer destroy error (expected): ' + destroyError.message);
            }
            
            window.viewer = null;
            cesiumLog.debug('Cesium cleanup completed');
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
            cesiumLog.debug('Page hidden - rendering paused');
        } else {
            viewer.scene.requestRenderMode = false;
            cesiumLog.debug('Page visible - rendering resumed');
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
    
    cesiumLog.debug('Captured view: altitude=' + altitude + ', rectangle=' + (rectangle ? 'yes' : 'no'));
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
                cesiumLog.debug('Restored 2D view with rectangle');
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
                cesiumLog.debug('Restored 3D view at altitude: ' + altitude);
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
                cesiumLog.debug('Restored Columbus view at altitude: ' + altitude);
            }
        }
    } catch (e) {
        cesiumLog.error('Failed to restore camera view: ' + e.message);
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
            cesiumLog.debug('Saved scene mode preference: ' + getSceneModeString(mode));
        } else {
            cesiumLog.debug('localStorage not available - preference will be saved in Flutter');
        }
    } catch (e) {
        cesiumLog.debug('Could not save to localStorage (expected in WebView): ' + e.message);
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
                cesiumLog.debug('Loaded scene mode preference: ' + getSceneModeString(mode));
                return mode;
            }
        }
    } catch (e) {
        // Expected in WebView context - preferences handled by Flutter
        cesiumLog.debug('Could not load from localStorage (expected in WebView)');
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
    cesiumLog.debug('Scene mode morphing started');
    
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
window.getSceneMode = getSceneMode;
window.toggleSceneMode = toggleSceneMode;