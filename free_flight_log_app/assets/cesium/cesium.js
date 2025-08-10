// Cesium 3D Map JavaScript Module
// Handles initialization, memory management, and lifecycle

// Global variables
let viewer = null;
let cleanupTimer = null;
let initialLoadComplete = false;

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
            baseLayerPicker: false,
            geocoder: false,
            homeButton: true,
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
        
        // Strict tile cache management to prevent memory limit warnings
        viewer.scene.globe.tileCacheSize = 25;  // Reduced cache size to prevent memory warnings
        viewer.scene.globe.preloadSiblings = false;  // Don't preload adjacent tiles
        viewer.scene.globe.preloadAncestors = false;  // Don't preload parent tiles
        
        // Tile memory budget - set explicit memory limit for tiles
        viewer.scene.globe.maximumMemoryUsage = 128;  // Set max memory usage in MB
        
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
        
        // Set initial camera view
        viewer.camera.setView({
            destination: Cesium.Cartesian3.fromDegrees(config.lon, config.lat, config.altitude),
            orientation: {
                heading: Cesium.Math.toRadians(0),
                pitch: Cesium.Math.toRadians(-45),
                roll: 0.0
            }
        });
        
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
                    if (memoryUsage > 100 * 1024 * 1024) {  // If over 100MB
                        cesiumLog.debug('High memory usage: ' + (memoryUsage / 1024 / 1024).toFixed(1) + 'MB - forcing cleanup');
                        
                        // Clear unused primitives and entities
                        viewer.scene.primitives.removeAll();
                        viewer.entities.removeAll();
                        
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
        cesiumLog.debug('Camera position: lat=' + config.lat + ', lon=' + config.lon + ', altitude=' + config.altitude);
        
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
        
        if (usage.used > usage.total * 0.8) {
            // High memory usage - trigger cleanup
            cesiumLog.debug('High memory usage detected: ' + usage.used + 'MB, triggering cleanup');
            if (window.viewer) {
                // Reduce quality temporarily to free memory
                viewer.scene.globe.maximumScreenSpaceError = 8;
                viewer.scene.primitives.removeAll();
                
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

// Export functions for Flutter access
window.cleanupCesium = cleanupCesium;
window.checkMemory = checkMemory;
window.initializeCesium = initializeCesium;