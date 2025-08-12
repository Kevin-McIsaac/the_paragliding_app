// Cesium 3D Map JavaScript Module
// Handles initialization, memory management, and lifecycle

// Global variables
let viewer = null;
let cleanupTimer = null;
let initialLoadComplete = false;
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
            targetFrameRate: 30,  // Balanced frame rate
            resolutionScale: 0.85,  // Better quality while still saving memory
            
            // WebGL context options for low memory usage
            contextOptions: {
                webgl: {
                    powerPreference: 'low-power',  // Use low-power GPU
                    antialias: false,  // Disable antialiasing
                    preserveDrawingBuffer: false,
                    failIfMajorPerformanceCaveat: true,
                    depth: true,
                    stencil: false,
                    alpha: false
                }
            },
            
            // Disable unused widgets to reduce overhead
            baseLayerPicker: true,
            geocoder: true,
            homeButton: true,  // Remove home button as requested
            sceneModePicker: false,
            navigationHelpButton: false,
            animation: false,
            timeline: false,
            fullscreenButton: false,
            vrButton: false,
            infoBox: false,
            selectionIndicator: false,
            shadows: false,
            shouldAnimate: false,
        });
        
        cesiumLog.debug('Cesium viewer created, configuring aggressive memory optimizations...');
        
        // Configure scene for minimal memory usage
        viewer.scene.globe.enableLighting = false;
        viewer.scene.globe.showGroundAtmosphere = false;  // Disable atmosphere
        viewer.scene.fog.enabled = false;  // Disable fog
        viewer.scene.globe.depthTestAgainstTerrain = false;  // Faster rendering
        viewer.scene.screenSpaceCameraController.enableCollisionDetection = false;
        
        // Balanced tile cache management
        viewer.scene.globe.tileCacheSize = 100;  // Increased cache for better rendering
        viewer.scene.globe.preloadSiblings = false;  // Don't preload adjacent tiles
        viewer.scene.globe.preloadAncestors = false;  // Don't preload parent tiles
        
        // Tile memory budget - increase for better rendering
        viewer.scene.globe.maximumMemoryUsage = 256;  // Increased memory limit in MB
        
        // Balanced screen space error for decent quality with good performance
        viewer.scene.globe.maximumScreenSpaceError = 4;  // Slightly reduced quality to save memory
        
        // Moderate texture size limit
        viewer.scene.maximumTextureSize = 1024;  // Reduced texture size to save memory
        
        // Set explicit tile load limits
        viewer.scene.globe.loadingDescendantLimit = 10;  // Limit concurrent tile loads
        viewer.scene.globe.immediatelyLoadDesiredLevelOfDetail = false;  // Progressive loading
        
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
        
        // Handle tile memory exceeded events
        viewer.scene.globe.tileLoadProgressEvent.addEventListener(function() {
            // Monitor for memory issues
            const globe = viewer.scene.globe;
            if (globe._surface && globe._surface._tilesToRender) {
                const tileCount = globe._surface._tilesToRender.length;
                if (tileCount > 30) {
                    cesiumLog.debug('High tile count detected: ' + tileCount + ' - adjusting quality');
                    // Temporarily increase screen space error to reduce tile count
                    viewer.scene.globe.maximumScreenSpaceError = 6;
                    
                    // Reset after a delay
                    setTimeout(() => {
                        viewer.scene.globe.maximumScreenSpaceError = 4;
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
                    if (tileCount > 25) {
                        cesiumLog.debug('High tile count: ' + tileCount + ' - reducing quality');
                        // Temporarily increase screen space error to reduce tile count
                        viewer.scene.globe.maximumScreenSpaceError = 6;
                        
                        // Reset after a delay
                        setTimeout(() => {
                            viewer.scene.globe.maximumScreenSpaceError = 4;
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
            width: 10,
            material: new Cesium.PolylineGlowMaterialProperty({
                glowPower: 0.2,
                taperPower: 0.5,
                color: Cesium.Color.YELLOW.withAlpha(0.8)
            }),
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
            width: 8,
            material: new Cesium.PolylineGlowMaterialProperty({
                glowPower: 0.25,
                taperPower: 0.2,
                color: Cesium.Color.DODGERBLUE.withAlpha(0.9)
            }),
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
    points.forEach(point => {
        const time = Cesium.JulianDate.fromIso8601(point.timestamp);
        const position = Cesium.Cartesian3.fromDegrees(
            point.longitude,
            point.latitude,
            point.altitude
        );
        positionProperty.addSample(time, position);
    });
    
    // Create pilot entity with time-dynamic position
    const pilotEntity = viewer.entities.add({
        name: 'Pilot',
        availability: new Cesium.TimeIntervalCollection([
            new Cesium.TimeInterval({
                start: startTime,
                stop: stopTime
            })
        ]),
        position: positionProperty,
        // Pilot marker
        point: {
            pixelSize: 12,
            color: Cesium.Color.YELLOW,
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 2,
            heightReference: Cesium.HeightReference.NONE,
            disableDepthTestDistance: Number.POSITIVE_INFINITY
        },
        // Path visualization (trail behind pilot)
        path: {
            show: true,
            leadTime: 0,
            trailTime: 60, // Show 60 seconds of trail
            width: 8,
            material: new Cesium.PolylineGlowMaterialProperty({
                glowPower: 0.15,
                taperPower: 0.3,
                color: Cesium.Color.YELLOW.withAlpha(0.5)
            })
        },
        // Orientation based on velocity
        orientation: new Cesium.VelocityOrientationProperty(positionProperty)
    });
    
    // Store pilot entity reference
    playbackState.showPilot = pilotEntity;
    playbackState.positionProperty = positionProperty;
    
    // Configure viewer clock for playback
    viewer.clock.startTime = startTime.clone();
    viewer.clock.stopTime = stopTime.clone();
    viewer.clock.currentTime = startTime.clone();
    viewer.clock.clockRange = Cesium.ClockRange.LOOP_STOP;
    viewer.clock.multiplier = 1;
    viewer.clock.shouldAnimate = false; // Start paused
    
    // Set timeline bounds
    if (viewer.timeline) {
        viewer.timeline.zoomTo(startTime, stopTime);
    }
    
    cesiumLog.info('Time-based animation configured with Cesium native features');
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
    playbackSpeed: 30.0,  // Default to 30x speed
    followMode: false,
    showPilot: null,
    animationFrame: null,
    lastUpdateTime: null,
    accumulatedTime: 0,
    positionProperty: null  // For Cesium native time-based animation
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

// Update pilot marker position without changing camera
function updatePilotPosition(index) {
    if (!viewer || !igcPoints || index < 0 || index >= igcPoints.length) return;
    
    const point = igcPoints[index];
    
    // Add pilot marker if not exists
    if (!playbackState.showPilot) {
        playbackState.showPilot = viewer.entities.add({
            name: 'Pilot',
            position: Cesium.Cartesian3.fromDegrees(
                point.longitude,
                point.latitude,
                point.altitude
            ),
            point: {
                pixelSize: 12,
                color: Cesium.Color.YELLOW,
                outlineColor: Cesium.Color.BLACK,
                outlineWidth: 3,
                heightReference: Cesium.HeightReference.NONE,
                disableDepthTestDistance: Number.POSITIVE_INFINITY // Always visible
            },
            billboard: {
                image: 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48cGF0aCBmaWxsPSIjRkZENzAwIiBkPSJNMTIgMkw0IDIwaDEzbC03LTE4eiIvPjwvc3ZnPg==', // Yellow triangle
                scale: 0.8,
                verticalOrigin: Cesium.VerticalOrigin.CENTER,
                heightReference: Cesium.HeightReference.NONE,
                disableDepthTestDistance: Number.POSITIVE_INFINITY // Always visible
            }
        });
    } else {
        // Update pilot position
        playbackState.showPilot.position = Cesium.Cartesian3.fromDegrees(
            point.longitude,
            point.latitude,
            point.altitude
        );
    }
}

// Feature 4: Playback controls using Cesium native clock
function startPlayback() {
    if (!viewer || !igcPoints || igcPoints.length === 0) {
        cesiumLog.error('Cannot start playback: viewer=' + !!viewer + ', points=' + igcPoints.length);
        return;
    }
    
    // If at the end, restart from beginning
    if (playbackState.currentIndex >= igcPoints.length - 1) {
        playbackState.currentIndex = 0;
        cesiumLog.info('Restarting playback from beginning');
    }
    
    // Check if using time-based animation
    if (viewer.clock && playbackState.positionProperty) {
        // Use Cesium's native clock for time-based playback
        viewer.clock.shouldAnimate = true;
        viewer.clock.multiplier = playbackState.playbackSpeed;
        playbackState.isPlaying = true;
        
        cesiumLog.info('Started Cesium native playback at speed ' + playbackState.playbackSpeed + 'x');
    } else {
        // Fallback to index-based animation
        playbackState.isPlaying = true;
        playbackState.lastUpdateTime = Date.now();
        playbackState.accumulatedTime = 0;
        
        // Always show pilot marker when playback starts
        updatePilotPosition(playbackState.currentIndex);
        
        cesiumLog.info('Playback started at speed ' + playbackState.playbackSpeed + 'x, index=' + playbackState.currentIndex + '/' + igcPoints.length);
        
        // Start animation loop
        animatePlayback();
    }
}

function pausePlayback() {
    playbackState.isPlaying = false;
    
    // Check if using time-based animation
    if (viewer.clock && playbackState.positionProperty) {
        viewer.clock.shouldAnimate = false;
        cesiumLog.info('Paused Cesium native playback');
    } else {
        // Fallback index-based pause
        if (playbackState.animationFrame) {
            cancelAnimationFrame(playbackState.animationFrame);
            playbackState.animationFrame = null;
        }
        cesiumLog.info('Playback paused at index ' + playbackState.currentIndex);
    }
}

function stopPlayback() {
    pausePlayback();
    playbackState.currentIndex = 0;
    playbackState.accumulatedTime = 0;
    
    // Remove pilot marker
    if (playbackState.showPilot) {
        viewer.entities.remove(playbackState.showPilot);
        playbackState.showPilot = null;
    }
    
    cesiumLog.info('Playback stopped');
}

function setPlaybackSpeed(speed) {
    // Speed represents time multiplier for Cesium clock
    playbackState.playbackSpeed = Math.max(1.0, Math.min(120.0, speed));
    
    // Update Cesium clock multiplier if using time-based animation
    if (viewer.clock && playbackState.positionProperty) {
        viewer.clock.multiplier = playbackState.playbackSpeed;
    }
    
    cesiumLog.info('Playback speed set to ' + playbackState.playbackSpeed + 'x');
}

function seekToPosition(index) {
    if (!igcPoints || index < 0 || index >= igcPoints.length) return;
    
    playbackState.currentIndex = index;
    
    // Throttle rapid seek operations to prevent GPU overload
    if (playbackState.seekTimeout) {
        clearTimeout(playbackState.seekTimeout);
    }
    
    playbackState.seekTimeout = setTimeout(() => {
        if (playbackState.followMode) {
            followFlightPoint(index);
        } else {
            // Always update pilot position when seeking
            updatePilotPosition(index);
        }
        
        // Request render only when frame is ready
        if (viewer && viewer.scene) {
            viewer.scene.requestRender();
        }
        
        // Update timeline position (will be called from Flutter)
        if (window.onPlaybackPositionChanged) {
            window.onPlaybackPositionChanged(index);
        }
        
        playbackState.seekTimeout = null;
    }, 50); // 50ms debounce to prevent rapid GPU updates
    
    cesiumLog.debug('Seeked to position ' + index);
}

function stepForward() {
    if (!igcPoints || playbackState.currentIndex >= igcPoints.length - 1) return;
    
    seekToPosition(playbackState.currentIndex + 1);
}

function stepBackward() {
    if (!igcPoints || playbackState.currentIndex <= 0) return;
    
    seekToPosition(playbackState.currentIndex - 1);
}

function animatePlayback() {
    if (!playbackState.isPlaying) return;
    
    const now = Date.now();
    const deltaTime = now - playbackState.lastUpdateTime;
    playbackState.lastUpdateTime = now;
    
    // Speed represents points per second (1x = 1 point/sec, 10x = 10 points/sec)
    // Accumulate fractional points based on elapsed time
    const pointsPerMs = playbackState.playbackSpeed / 1000;
    playbackState.accumulatedTime += deltaTime * pointsPerMs;
    
    // Check if we should advance to the next point(s)
    if (playbackState.accumulatedTime >= 1) {
        // Calculate how many whole points to advance
        const pointsToAdvance = Math.floor(playbackState.accumulatedTime);
        playbackState.accumulatedTime -= pointsToAdvance;
        
        // Advance by the calculated number of points (usually 1, but more at high speeds)
        for (let i = 0; i < pointsToAdvance && playbackState.currentIndex < igcPoints.length - 1; i++) {
            playbackState.currentIndex++;
        }
        
        // Animation advancing silently
        
        if (playbackState.currentIndex < igcPoints.length) {
            if (playbackState.followMode) {
                followFlightPoint(playbackState.currentIndex);
            } else {
                // Always update pilot position during animation
                updatePilotPosition(playbackState.currentIndex);
            }
            
            // Force render to show pilot position change
            if (viewer && viewer.scene) {
                viewer.scene.requestRender();
            }
            
            // Notify Flutter of position change - this is critical for slider update
            if (window.onPlaybackPositionChanged) {
                window.onPlaybackPositionChanged(playbackState.currentIndex);
            }
        }
        
        if (playbackState.currentIndex >= igcPoints.length - 1) {
            // Reached end of flight - just pause, don't stop
            pausePlayback();
            // Keep pilot at final position
            updatePilotPosition(igcPoints.length - 1);
            cesiumLog.info('Playback completed - paused at end');
            
            if (window.onPlaybackCompleted) {
                window.onPlaybackCompleted();
            }
            return; // Stop the animation loop
        }
    }
    
    // Continue animation loop
    playbackState.animationFrame = requestAnimationFrame(animatePlayback);
}

// Get playback state for UI updates
function getPlaybackState() {
    return {
        isPlaying: playbackState.isPlaying,
        currentIndex: playbackState.currentIndex,
        totalPoints: igcPoints.length,
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