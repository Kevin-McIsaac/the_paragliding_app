// Cesium 3D Map JavaScript Module
// Handles initialization, memory management, and lifecycle

// Global variables
let viewer = null;
let cleanupTimer = null;
let initialLoadComplete = false;
let flightTrackEntity = null;
let igcPoints = [];
let currentTerrainExaggeration = 1.0;

// Stats positioning configuration
let statsPosition = 'bottom-center'; // Options: 'top-left', 'top-right', 'bottom-left', 'bottom-right', 'bottom-center'

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
                    requestVertexNormals: false
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
                requestVertexNormals: false,  // Disable lighting calculations
                requestMetadata: false  // Disable metadata
            }),
            scene3DOnly: true,  // Disable 2D/Columbus view modes for performance
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
        
        // Disable terrain exaggeration
        viewer.scene.globe.terrainExaggeration = 1.0;
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
            // 'S' key to cycle through stats positions
            if (event.key === 's' || event.key === 'S') {
                cycleStatsPosition();
                event.preventDefault();
            }
            // Number keys for direct position selection
            else if (event.key === '1') {
                setStatsPosition('bottom-center');
                event.preventDefault();
            }
            else if (event.key === '2') {
                setStatsPosition('top-left');
                event.preventDefault();
            }
            else if (event.key === '3') {
                setStatsPosition('top-right');
                event.preventDefault();
            }
            else if (event.key === '4') {
                setStatsPosition('bottom-left');
                event.preventDefault();
            }
            else if (event.key === '5') {
                setStatsPosition('bottom-right');
                event.preventDefault();
            }
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
        const loadingStartTime = Date.now();
        
        const tileLoadHandler = function(queuedTileCount) {
            if (queuedTileCount === 0 && !initialLoadComplete) {
                initialLoadComplete = true;
                const loadTime = ((Date.now() - loadingStartTime) / 1000).toFixed(2);
                cesiumLog.info('Initial tile load complete in ' + loadTime + 's');
                document.getElementById('loadingOverlay').style.display = 'none';
                
                // Remove the listener after initial load
                viewer.scene.globe.tileLoadProgressEvent.removeEventListener(tileLoadHandler);
            } else if (config.debug && !initialLoadComplete) {
                // Only log significant changes in debug mode
                const change = Math.abs(lastTileCount - queuedTileCount);
                if (change > 10 || (queuedTileCount === 0 && lastTileCount > 0)) {
                    cesiumLog.debug('Tiles queued: ' + queuedTileCount);
                    lastTileCount = queuedTileCount;
                }
            }
        };
        viewer.scene.globe.tileLoadProgressEvent.addEventListener(tileLoadHandler);
        
        // Setup periodic memory cleanup with aggressive management
        cleanupTimer = setInterval(() => {
            if (viewer && viewer.scene && viewer.scene.globe) {
                // Check memory usage via performance API
                if (window.performance && window.performance.memory) {
                    const memoryUsage = window.performance.memory.usedJSHeapSize;
                    if (memoryUsage > 300 * 1024 * 1024) {  // Only cleanup if over 300MB
                        cesiumLog.debug('High memory usage: ' + (memoryUsage / 1024 / 1024).toFixed(1) + 'MB - trimming tile cache');
                        
                        // Only trim tile cache, preserve flight track entities
                        viewer.scene.globe.tileCache.trim();
                        
                        // Force garbage collection if available
                        if (window.gc) {
                            window.gc();
                        }
                    }
                }
                
                // Monitor tile count for cleanup
                if (viewer.scene.globe._surface && viewer.scene.globe._surface._tilesToRender) {
                    const tileCount = viewer.scene.globe._surface._tilesToRender.length;
                    if (tileCount > 50) {  // Increased threshold
                        // Silently adjust without logging to reduce console spam
                        // Temporarily increase screen space error to reduce tile count
                        viewer.scene.globe.maximumScreenSpaceError = 4;
                        
                        // Reset after a delay
                        setTimeout(() => {
                            viewer.scene.globe.maximumScreenSpaceError = 3;
                        }, 5000);
                    }
                }
            }
        }, 30000);  // Every 30 seconds for better memory management
        
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
        
        // Expose stats position functions to be callable from Flutter
        window.setStatsPosition = setStatsPosition;
        window.cycleStatsPosition = cycleStatsPosition;
        
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
function createFlightTrack(points) {
    if (!viewer || !points || points.length === 0) return;
    
    // Store points globally for other features
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
        cesiumLog.info('Track timezone: ' + trackTimezone);
        
        // Parse timezone offset for display adjustments
        const tzMatch = trackTimezone.match(/^([+-])(\d{2}):(\d{2})$/);
        if (tzMatch) {
            const sign = tzMatch[1] === '+' ? 1 : -1;
            const hours = parseInt(tzMatch[2], 10);
            const minutes = parseInt(tzMatch[3], 10);
            timezoneOffsetSeconds = sign * ((hours * 3600) + (minutes * 60));
            cesiumLog.info('Timezone offset seconds: ' + timezoneOffsetSeconds);
        }
        
        // Store timezone globally for display formatting
        window.flightTimezone = trackTimezone;
        window.flightTimezoneOffsetSeconds = timezoneOffsetSeconds;
        
        // Now update the Animation widget formatters with the timezone info
        if (viewer.animation && timezoneOffsetSeconds !== 0) {
            cesiumLog.info('Configuring Animation widget for timezone: ' + trackTimezone);
            
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
            
            // Override time formatter to show local time
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
        }
        
        // Also update Timeline to show local time
        if (viewer.timeline && timezoneOffsetSeconds !== 0) {
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
        }
    }
    
    // Remove existing track if any
    if (flightTrackEntity) {
        viewer.entities.remove(flightTrackEntity);
        flightTrackEntity = null;
    }
    
    // Convert points to Cartesian3 positions
    const positions = points.map(point => 
        Cesium.Cartesian3.fromDegrees(
            point.longitude,
            point.latitude,
            point.altitude
        )
    );
    
    // Create polyline entity with glow effect
    flightTrackEntity = viewer.entities.add({
        name: 'Flight Track',
        polyline: {
            positions: positions,
            width: 4,
            material: Cesium.Color.YELLOW.withAlpha(0.9),
            clampToGround: false,
            show: true
        }
    });
    
    // Zoom to flight track with padding for UI
    zoomToEntitiesWithPadding(0.3); // 30% padding
    
    cesiumLog.info('Flight track created with ' + points.length + ' points');
}

// Create simplified blue track with Cesium-native features
function createColoredFlightTrack(points) {
    if (!viewer || !points || points.length === 0) return;
    
    igcPoints = points;
    
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

// Change stats position and update the label
function setStatsPosition(newPosition) {
    const validPositions = ['top-left', 'top-right', 'bottom-left', 'bottom-right', 'bottom-center'];
    
    if (!validPositions.includes(newPosition)) {
        cesiumLog.error('Invalid stats position: ' + newPosition);
        return;
    }
    
    statsPosition = newPosition;
    cesiumLog.info('Stats position changed to: ' + statsPosition);
    
    // Update the label if it exists
    if (playbackState.statsLabel) {
        const newPos = getStatsPositioning();
        playbackState.statsLabel.label.pixelOffset = newPos.pixelOffset;
        playbackState.statsLabel.label.horizontalOrigin = newPos.horizontalOrigin;
        playbackState.statsLabel.label.verticalOrigin = newPos.verticalOrigin;
    }
}

// Cycle through stats positions
function cycleStatsPosition() {
    const positions = ['bottom-center', 'top-left', 'top-right', 'bottom-left', 'bottom-right'];
    const currentIndex = positions.indexOf(statsPosition);
    const nextIndex = (currentIndex + 1) % positions.length;
    setStatsPosition(positions[nextIndex]);
}

// Calculate pixel offset and origin for stats position
function getStatsPositioning() {
    const padding = 20; // Padding from edges
    const canvasWidth = viewer.canvas.width;
    const canvasHeight = viewer.canvas.height;
    
    let pixelOffset, horizontalOrigin, verticalOrigin;
    
    switch(statsPosition) {
        case 'top-left':
            pixelOffset = new Cesium.Cartesian2(-canvasWidth/2 + padding + 80, -canvasHeight/2 + padding + 30);
            horizontalOrigin = Cesium.HorizontalOrigin.LEFT;
            verticalOrigin = Cesium.VerticalOrigin.TOP;
            break;
        case 'top-right':
            pixelOffset = new Cesium.Cartesian2(canvasWidth/2 - padding - 80, -canvasHeight/2 + padding + 30);
            horizontalOrigin = Cesium.HorizontalOrigin.RIGHT;
            verticalOrigin = Cesium.VerticalOrigin.TOP;
            break;
        case 'bottom-left':
            pixelOffset = new Cesium.Cartesian2(-canvasWidth/2 + padding + 80, canvasHeight/2 - padding - 10);
            horizontalOrigin = Cesium.HorizontalOrigin.LEFT;
            verticalOrigin = Cesium.VerticalOrigin.BOTTOM;
            break;
        case 'bottom-right':
            pixelOffset = new Cesium.Cartesian2(canvasWidth/2 - padding - 80, canvasHeight/2 - padding - 10);
            horizontalOrigin = Cesium.HorizontalOrigin.RIGHT;
            verticalOrigin = Cesium.VerticalOrigin.BOTTOM;
            break;
        case 'bottom-center':
        default:
            pixelOffset = new Cesium.Cartesian2(0, canvasHeight/2 - 25);
            horizontalOrigin = Cesium.HorizontalOrigin.CENTER;
            verticalOrigin = Cesium.VerticalOrigin.BOTTOM;
            break;
    }
    
    return { pixelOffset, horizontalOrigin, verticalOrigin };
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
    
    // Get positioning based on current statsPosition setting
    const statsPos = getStatsPositioning();
    
    // Create a separate label entity for statistics
    const statsLabel = viewer.entities.add({
        name: 'StatsLabel',
        position: firstPos,  // Position doesn't matter for screen-space label
        label: {
            text: 'Initializing...',
            font: '12px monospace',
            fillColor: Cesium.Color.WHITE,
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 2,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: statsPos.pixelOffset,
            horizontalOrigin: statsPos.horizontalOrigin,
            verticalOrigin: statsPos.verticalOrigin,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
            backgroundColor: Cesium.Color.BLACK.withAlpha(0.6),
            showBackground: true,
            backgroundPadding: new Cesium.Cartesian2(15, 5),
            eyeOffset: new Cesium.Cartesian3(0, 0, -1000)  // Ensure it's always in front
        }
    });
    
    playbackState.statsLabel = statsLabel;  // Store reference to label
    
    // Force scene rendering on each frame to ensure pilot updates
    viewer.scene.requestRenderMode = false;  // Disable request render mode to force continuous rendering
    
    // Add clock tick listener to update statistics label
    viewer.clock.onTick.addEventListener(function(clock) {
        // Force scene update
        viewer.scene.requestRender();
        
        if (playbackState.statsLabel) {
                
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
                    
                    // Format time (HH:MM format for compact display)
                    const date = Cesium.JulianDate.toDate(clock.currentTime);
                    const timeStr = date.getHours().toString().padStart(2, '0') + ':' + 
                                  date.getMinutes().toString().padStart(2, '0');
                    
                    // Update label text with horizontal format using pipe separators
                    const labelText = 
                        'Alt: ' + altitude.toFixed(0) + 'm  |  ' +
                        'Climb: ' + (climbRate >= 0 ? '+' : '') + climbRate.toFixed(1) + 'm/s  |  ' + 
                        'Speed: ' + speed.toFixed(1) + 'km/h  |  ' +
                        timeStr;
                    
                    playbackState.statsLabel.label.text = labelText;
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
    
    // Clear the cleanup timer first
    if (cleanupTimer !== null) {
        clearInterval(cleanupTimer);
        cleanupTimer = null;
    }
    
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

// Memory monitoring function
function checkMemory() {
    if (window.performance && window.performance.memory) {
        const memory = window.performance.memory;
        const usage = {
            used: Math.round(memory.usedJSHeapSize / 1048576),
            total: Math.round(memory.totalJSHeapSize / 1048576),
            limit: Math.round(memory.jsHeapSizeLimit / 1048576)
        };
        
        // Only trigger cleanup if memory usage is above 200MB (not 80% of 33MB!)
        if (usage.used > 200) {
            // High memory usage - trigger cleanup but preserve flight track
            cesiumLog.debug('High memory usage detected: ' + usage.used + 'MB, triggering cleanup');
            if (window.viewer) {
                // Only trim tile cache, don't remove entities
                viewer.scene.globe.tileCache.trim();
                
                // Reduce quality temporarily to free memory
                viewer.scene.globe.maximumScreenSpaceError = 8;
                
                // Reset quality after memory pressure is reduced
                setTimeout(() => {
                    if (viewer.scene && viewer.scene.globe) {
                        viewer.scene.globe.maximumScreenSpaceError = 4;
                    }
                }, 5000);
            }
        }
        
        return usage;
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


// Feature 4: Playback controls using Cesium native clock
function startPlayback() {
    cesiumLog.info('startPlayback called');
    
    if (!viewer || !viewer.clock || !igcPoints || igcPoints.length === 0) {
        cesiumLog.error('Cannot start playback: No viewer or track data');
        return;
    }
    
    cesiumLog.debug('Viewer exists: ' + (viewer !== null));
    cesiumLog.debug('Clock exists: ' + (viewer.clock !== null));
    cesiumLog.debug('Track points: ' + igcPoints.length);
    cesiumLog.debug('Pilot entity exists: ' + (playbackState.showPilot !== null));
    
    // If at the end, restart from beginning
    if (playbackState.currentIndex >= igcPoints.length - 1) {
        playbackState.currentIndex = 0;
        cesiumLog.info('Restarting playback from beginning');
    }
    
    // Sync clock to current position
    const currentPoint = igcPoints[playbackState.currentIndex];
    if (currentPoint && currentPoint.timestamp) {
        const targetTime = Cesium.JulianDate.fromIso8601(currentPoint.timestamp);
        viewer.clock.currentTime = targetTime;
        cesiumLog.debug('Set clock time to: ' + targetTime.toString());
    }
    
    // Start clock animation
    viewer.clock.multiplier = playbackState.playbackSpeed;
    viewer.clock.shouldAnimate = true;
    playbackState.isPlaying = true;
    
    cesiumLog.info('Clock animation started - shouldAnimate: ' + viewer.clock.shouldAnimate + 
                   ', multiplier: ' + viewer.clock.multiplier);
    
    // Check if pilot entity is visible
    if (playbackState.showPilot) {
        cesiumLog.debug('Pilot entity show: ' + playbackState.showPilot.show);
        
        // Get current position from position property
        const currentPos = playbackState.positionProperty.getValue(viewer.clock.currentTime);
        if (currentPos) {
            cesiumLog.info('Pilot position at current time is valid');
            // Convert to lat/lon for debugging
            const carto = Cesium.Cartographic.fromCartesian(currentPos);
            cesiumLog.debug('Pilot at: lat=' + Cesium.Math.toDegrees(carto.latitude).toFixed(6) + 
                          ', lon=' + Cesium.Math.toDegrees(carto.longitude).toFixed(6) + 
                          ', alt=' + carto.height.toFixed(0));
        } else {
            cesiumLog.error('Cannot get pilot position at current time!');
        }
    }
    
    cesiumLog.info('Started playback at speed ' + playbackState.playbackSpeed + 'x from index ' + playbackState.currentIndex);
}

// DEPRECATED: Use Cesium's native Animation widget
function pausePlayback() {
    cesiumLog.info('pausePlayback called - use Cesium Animation widget instead');
}

// DEPRECATED: Use Cesium's native Animation widget
function stopPlayback() {
    cesiumLog.info('stopPlayback called - use Cesium Animation widget instead');
}

// DEPRECATED: Use Cesium's native Animation widget
function setPlaybackSpeed(speed) {
    cesiumLog.info('setPlaybackSpeed called - use Cesium Animation widget instead');
}

function seekToPosition(index) {
    if (!viewer || !viewer.clock || !igcPoints || index < 0 || index >= igcPoints.length) return;
    
    playbackState.currentIndex = index;
    
    // Update clock time to match the selected point
    const point = igcPoints[index];
    if (point && point.timestamp) {
        const targetTime = Cesium.JulianDate.fromIso8601(point.timestamp);
        viewer.clock.currentTime = targetTime;
        
        // If using simple pilot mode, manually update position immediately
        if (playbackState.simplePilot && playbackState.showPilot && playbackState.positionProperty) {
            const newPos = playbackState.positionProperty.getValue(targetTime);
            if (newPos) {
                playbackState.showPilot.position = newPos;
                cesiumLog.debug('Manually updated pilot position on seek');
            }
        }
    }
    
    // Update camera if in follow mode
    if (playbackState.followMode) {
        followFlightPoint(index);
    }
    
    cesiumLog.debug('Seeked to position ' + index);
}

// Get current index from clock time
function getCurrentIndexFromClock() {
    if (!viewer || !viewer.clock || !igcPoints || igcPoints.length === 0) return 0;
    
    const startTime = Cesium.JulianDate.fromIso8601(igcPoints[0].timestamp);
    const endTime = Cesium.JulianDate.fromIso8601(igcPoints[igcPoints.length - 1].timestamp);
    const currentTime = viewer.clock.currentTime;
    
    const totalSeconds = Cesium.JulianDate.secondsDifference(endTime, startTime);
    const elapsedSeconds = Cesium.JulianDate.secondsDifference(currentTime, startTime);
    
    const progress = Math.max(0, Math.min(1, elapsedSeconds / totalSeconds));
    return Math.floor(progress * (igcPoints.length - 1));
}

// DEPRECATED: Use Cesium's native Timeline widget
function stepForward() {
    cesiumLog.info('stepForward called - use Cesium Timeline widget instead');
}

// DEPRECATED: Use Cesium's native Timeline widget
function stepBackward() {
    cesiumLog.info('stepBackward called - use Cesium Timeline widget instead');
}

function animatePlayback() {
    // DEPRECATED: Animation is now handled by Cesium's clock
    // This function is kept for backward compatibility but does nothing
    return;
}

// Get playback state for UI updates
function getPlaybackState() {
    // Calculate current index from clock time if playing
    let currentIndex = playbackState.currentIndex;
    if (viewer && viewer.clock && igcPoints && igcPoints.length > 0) {
        currentIndex = getCurrentIndexFromClock();
        playbackState.currentIndex = currentIndex; // Keep state in sync
        
        // Debug pilot position during playback
        if (playbackState.isPlaying && playbackState.showPilot && playbackState.positionProperty) {
            const currentPos = playbackState.positionProperty.getValue(viewer.clock.currentTime);
            if (!currentPos) {
                cesiumLog.error('Pilot position is null during playback at time: ' + viewer.clock.currentTime.toString());
            }
            
            // Check if entity is actually being rendered
            if (playbackState.showPilot.isShowing !== false) {
                // Entity should be showing
                const boundingSphere = viewer.scene.globe.pick(
                    viewer.camera.getPickRay(new Cesium.Cartesian2(
                        viewer.canvas.width / 2,
                        viewer.canvas.height / 2
                    )),
                    viewer.scene
                );
                
                if (currentIndex % 30 === 0) {  // Log every 30th frame to avoid spam
                    cesiumLog.debug('Playback index: ' + currentIndex + ', clock time: ' + viewer.clock.currentTime.toString());
                }
            }
        }
    }
    
    return {
        isPlaying: playbackState.isPlaying,
        currentIndex: currentIndex,
        totalPoints: igcPoints ? igcPoints.length : 0,
        playbackSpeed: playbackState.playbackSpeed,
        followMode: playbackState.followMode
    };
}

// Export functions for Flutter access
window.cleanupCesium = cleanupCesium;
window.checkMemory = checkMemory;
window.initializeCesium = initializeCesium;

// Phase 1 Feature exports
window.setTerrainExaggeration = setTerrainExaggeration;
window.switchBaseMap = switchBaseMap;
window.createFlightTrack = createFlightTrack;
window.createColoredFlightTrack = createColoredFlightTrack;
window.setTrackOpacity = setTrackOpacity;
window.setCameraPreset = setCameraPreset;
window.flyToLocation = flyToLocation;
window.setCameraControlsEnabled = setCameraControlsEnabled;
window.getClimbRateColor = getClimbRateColor;

// Phase 2 Feature exports (Playback)
window.setFollowMode = setFollowMode;
window.startPlayback = startPlayback;
window.pausePlayback = pausePlayback;
window.stopPlayback = stopPlayback;
window.setPlaybackSpeed = setPlaybackSpeed;
window.seekToPosition = seekToPosition;
window.stepForward = stepForward;
window.stepBackward = stepBackward;
window.getPlaybackState = getPlaybackState;