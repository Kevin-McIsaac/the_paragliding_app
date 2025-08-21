// Cesium 3D Map Module - Refactored with idiomatic patterns
// Uses CustomDataSource, native time-dynamic properties, and efficient data management

// ============================================================================
// Backward Compatibility - cesiumLog shim
// ============================================================================

// Define cesiumLog for backward compatibility with Flutter-injected code
window.cesiumLog = {
    debug: (message) => {
        if (window.cesiumConfig?.debug) {
            console.log('[Cesium Debug] ' + message);
        }
    },
    info: (message) => console.log('[Cesium] ' + message),
    error: (message) => console.error('[Cesium Error] ' + message),
    warn: (message) => console.warn('[Cesium Warning] ' + message)
};

// ============================================================================
// Performance Reporting to Flutter
// ============================================================================

class PerformanceReporter {
    static report(metric, value) {
        // Log to console for visibility
        console.log(`[Performance] ${metric}: ${typeof value === 'number' ? value.toFixed(2) + 'ms' : value}`);
        
        // Also send to Flutter
        if (window.flutter_inappwebview?.callHandler) {
            window.flutter_inappwebview.callHandler('performanceMetric', { metric, value });
        }
    }
    
    static measureTime(operation, fn) {
        const start = performance.now();
        const result = fn();
        const duration = performance.now() - start;
        this.report(operation, duration);
        return result;
    }
}

// ============================================================================
// Flight Data Source - Idiomatic Cesium CustomDataSource
// ============================================================================

class FlightDataSource extends Cesium.CustomDataSource {
    constructor(name, igcPoints) {
        super(name);
        
        // Store raw data
        this.igcPoints = igcPoints;
        this.positions = [];
        this.times = [];
        this.timezone = igcPoints[0]?.timezone || '+00:00';
        this.timezoneOffsetSeconds = this._parseTimezoneOffset(this.timezone);
        
        // Process data once
        this._processFlightData();
        
        // Create entities
        this._createPilotEntity();
        this._createCurtainWall();
    }
    
    _parseTimezoneOffset(timezone) {
        const match = timezone.match(/^([+-])(\d{2}):(\d{2})$/);
        if (!match) return 0;
        
        const sign = match[1] === '+' ? 1 : -1;
        const hours = parseInt(match[2], 10);
        const minutes = parseInt(match[3], 10);
        return sign * ((hours * 3600) + (minutes * 60));
    }
    
    _processFlightData() {
        const processStart = performance.now();
        
        // Build arrays once
        this.times = new Array(this.igcPoints.length);
        this.positions = new Array(this.igcPoints.length);
        
        for (let i = 0; i < this.igcPoints.length; i++) {
            const point = this.igcPoints[i];
            this.times[i] = Cesium.JulianDate.fromIso8601(point.timestamp);
            this.positions[i] = Cesium.Cartesian3.fromDegrees(
                point.longitude, 
                point.latitude, 
                point.altitude
            );
        }
        
        // Calculate time bounds
        this.startTime = this.times[0];
        this.stopTime = this.times[this.times.length - 1];
        this.totalDuration = Cesium.JulianDate.secondsDifference(this.stopTime, this.startTime);
        
        // Calculate bounding sphere for camera operations
        this.boundingSphere = Cesium.BoundingSphere.fromPoints(this.positions);
        
        PerformanceReporter.report('dataProcessing', performance.now() - processStart);
    }
    
    _createPilotEntity() {
        // Create position property with bulk add
        const positionProperty = new Cesium.SampledPositionProperty();
        positionProperty.setInterpolationOptions({
            interpolationDegree: 1,  // Linear for velocity calculation
            interpolationAlgorithm: Cesium.LinearApproximation
        });
        positionProperty.forwardExtrapolationType = Cesium.ExtrapolationType.HOLD;
        positionProperty.backwardExtrapolationType = Cesium.ExtrapolationType.HOLD;
        
        // Add all samples at once
        const bulkAddStart = performance.now();
        positionProperty.addSamples(this.times, this.positions);
        PerformanceReporter.report('bulkPositionAdd', performance.now() - bulkAddStart);
        
        // Store position property for reuse
        this.positionProperty = positionProperty;
        
        // Create pilot entity
        this.pilotEntity = this.entities.add({
            id: 'pilot',
            name: 'Pilot',
            availability: new Cesium.TimeIntervalCollection([
                new Cesium.TimeInterval({
                    start: this.startTime,
                    stop: this.stopTime
                })
            ]),
            position: positionProperty,
            orientation: new Cesium.VelocityOrientationProperty(positionProperty),
            point: {
                pixelSize: 16,
                color: Cesium.Color.YELLOW,
                outlineColor: Cesium.Color.BLACK,
                outlineWidth: 3,
                heightReference: Cesium.HeightReference.NONE,
                disableDepthTestDistance: Number.POSITIVE_INFINITY,
                scaleByDistance: new Cesium.NearFarScalar(1000, 1.5, 100000, 0.5)
            },
            viewFrom: new Cesium.Cartesian3(0.0, -1000.0, 500.0)
        });
    }
    
    _createCurtainWall() {
        // Static curtain wall
        this.staticCurtainEntity = this.entities.add({
            id: 'static-curtain',
            name: 'Flight Track Curtain',
            show: true,
            wall: {
                positions: this.positions,
                maximumHeights: this.igcPoints.map(p => p.altitude),
                material: Cesium.Color.DODGERBLUE.withAlpha(0.1),
                outline: false
            }
        });
        
        // Dynamic curtain wall for ribbon mode
        this.dynamicCurtainEntity = this.entities.add({
            id: 'dynamic-curtain',
            name: 'Dynamic Flight Curtain',
            show: false,
            wall: {
                positions: new Cesium.CallbackProperty((time) => {
                    if (!this._ribbonEnabled) return [];
                    return this._getTrailPositions(time);
                }, false),
                maximumHeights: new Cesium.CallbackProperty((time) => {
                    if (!this._ribbonEnabled) return [];
                    return this._getTrailAltitudes(time);
                }, false),
                material: Cesium.Color.DODGERBLUE.withAlpha(0.1),
                outline: false
            }
        });
        
        this._ribbonEnabled = false;
        this._ribbonSeconds = 3.0;
    }
    
    enableRibbonMode(enabled) {
        this._ribbonEnabled = enabled;
        this.staticCurtainEntity.show = !enabled;
        this.dynamicCurtainEntity.show = enabled;
    }
    
    _getTrailPositions(currentTime) {
        const index = this._findTimeIndex(currentTime);
        if (index < 0) return [];
        
        const windowSize = this._calculateRibbonWindow();
        const startIdx = Math.max(0, index - windowSize + 1);
        return this.positions.slice(startIdx, index + 1);
    }
    
    _getTrailAltitudes(currentTime) {
        const index = this._findTimeIndex(currentTime);
        if (index < 0) return [];
        
        const windowSize = this._calculateRibbonWindow();
        const startIdx = Math.max(0, index - windowSize + 1);
        return this.igcPoints.slice(startIdx, index + 1).map(p => p.altitude);
    }
    
    _calculateRibbonWindow() {
        const viewer = cesiumApp?.viewer;
        if (!viewer) return 100;
        
        const speedMultiplier = viewer.clock.multiplier || 1;
        const flightSeconds = this._ribbonSeconds * speedMultiplier;
        const pointsPerSecond = this.igcPoints.length / this.totalDuration;
        return Math.ceil(flightSeconds * pointsPerSecond);
    }
    
    _findTimeIndex(time) {
        // Binary search for efficiency
        let left = 0;
        let right = this.times.length - 1;
        
        while (left <= right) {
            const mid = Math.floor((left + right) / 2);
            const cmp = Cesium.JulianDate.compare(this.times[mid], time);
            
            if (cmp < 0) left = mid + 1;
            else if (cmp > 0) right = mid - 1;
            else return mid;
        }
        
        return Math.max(0, left - 1);
    }
    
    getStatisticsAt(time) {
        const index = this._findTimeIndex(time);
        if (index < 0 || index >= this.igcPoints.length) return null;
        
        const point = this.igcPoints[index];
        
        // Calculate speed if not provided
        let speed = point.groundSpeed || 0;
        if (!speed && index > 0) {
            const prevPoint = this.igcPoints[index - 1];
            const distance = Cesium.Cartesian3.distance(
                this.positions[index - 1],
                this.positions[index]
            );
            const timeDiff = Cesium.JulianDate.secondsDifference(
                this.times[index],
                this.times[index - 1]
            );
            if (timeDiff > 0) {
                speed = (distance / timeDiff) * 3.6; // m/s to km/h
            }
        }
        
        return {
            altitude: point.gpsAltitude || point.altitude || 0,
            climbRate: point.climbRate || 0,
            speed: speed,
            time: this.times[index],
            localTime: this._toLocalTime(this.times[index])
        };
    }
    
    _toLocalTime(julianDate) {
        if (this.timezoneOffsetSeconds === 0) return julianDate;
        return Cesium.JulianDate.addSeconds(
            julianDate, 
            this.timezoneOffsetSeconds, 
            new Cesium.JulianDate()
        );
    }
}

// ============================================================================
// Track Primitive Collection - Manages colored track primitives
// ============================================================================

class TrackPrimitiveCollection {
    constructor(viewer, flightData) {
        this.viewer = viewer;
        this.flightData = flightData;
        this.staticPrimitive = null;
        this.dynamicPrimitive = null;
        this._ribbonEnabled = false;
        this._lastDynamicWindow = { start: -1, end: -1 };
        
        // Create static track immediately
        this._createStaticTrack();
    }
    
    _createStaticTrack() {
        const start = performance.now();
        
        const positions = this.flightData.positions;
        const colors = this._generateColors(0, positions.length - 1);
        
        if (positions.length < 2) return;
        
        this.staticPrimitive = this.viewer.scene.primitives.add(
            new Cesium.Primitive({
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
                asynchronous: false
            })
        );
        
        PerformanceReporter.report('staticTrackCreation', performance.now() - start);
    }
    
    _generateColors(startIdx, endIdx) {
        const colors = new Array(endIdx - startIdx + 1);
        const points = this.flightData.igcPoints;
        
        for (let i = startIdx; i <= endIdx; i++) {
            const climbRate = points[i].climbRate15s || points[i].climbRate || 0;
            colors[i - startIdx] = this._getClimbRateColor(climbRate).withAlpha(0.9);
        }
        
        return colors;
    }
    
    _getClimbRateColor(rate) {
        if (rate >= 0) return Cesium.Color.GREEN;
        if (rate > -1.5) return Cesium.Color.DODGERBLUE;
        return Cesium.Color.RED;
    }
    
    enableRibbonMode(enabled) {
        this._ribbonEnabled = enabled;
        this.staticPrimitive.show = !enabled;
        
        if (!enabled && this.dynamicPrimitive) {
            this.viewer.scene.primitives.remove(this.dynamicPrimitive);
            this.dynamicPrimitive = null;
            this._lastDynamicWindow = { start: -1, end: -1 };
        }
    }
    
    updateDynamicTrack(currentTime) {
        if (!this._ribbonEnabled) return;
        
        const currentIdx = this.flightData._findTimeIndex(currentTime);
        if (currentIdx < 0) return;
        
        const windowSize = this.flightData._calculateRibbonWindow();
        const startIdx = Math.max(0, currentIdx - windowSize + 1);
        
        // Skip if window hasn't changed
        if (startIdx === this._lastDynamicWindow.start && 
            currentIdx === this._lastDynamicWindow.end) {
            return;
        }
        
        // Create new primitive
        const positions = this.flightData.positions.slice(startIdx, currentIdx + 1);
        const colors = this._generateColors(startIdx, currentIdx);
        
        if (positions.length < 2) return;
        
        const newPrimitive = this.viewer.scene.primitives.add(
            new Cesium.Primitive({
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
                asynchronous: false
            })
        );
        
        // Remove old primitive after adding new one (double buffering)
        if (this.dynamicPrimitive) {
            this.viewer.scene.primitives.remove(this.dynamicPrimitive);
        }
        
        this.dynamicPrimitive = newPrimitive;
        this._lastDynamicWindow = { start: startIdx, end: currentIdx };
    }
    
    destroy() {
        if (this.staticPrimitive) {
            this.viewer.scene.primitives.remove(this.staticPrimitive);
        }
        if (this.dynamicPrimitive) {
            this.viewer.scene.primitives.remove(this.dynamicPrimitive);
        }
    }
}

// ============================================================================
// Statistics Display Manager
// ============================================================================

class StatisticsDisplay {
    constructor(flightData) {
        this.flightData = flightData;
        this.container = document.getElementById('statsContainer');
        this.cesiumContainer = document.getElementById('cesiumContainer');
        this.playbackControls = document.getElementById('playbackControls');
    }
    
    show() {
        if (this.container) {
            this.container.classList.add('visible');
            this.container.innerHTML = '<span>Initializing...</span>';
        }
        if (this.cesiumContainer) {
            this.cesiumContainer.classList.add('with-stats');
        }
        if (this.playbackControls) {
            this.playbackControls.classList.add('visible', 'with-stats');
        }
    }
    
    hide() {
        if (this.container) {
            this.container.classList.remove('visible');
            this.container.innerHTML = '';
        }
        if (this.cesiumContainer) {
            this.cesiumContainer.classList.remove('with-stats');
        }
        if (this.playbackControls) {
            this.playbackControls.classList.remove('visible', 'with-stats');
        }
    }
    
    update(time) {
        if (!this.container || !this.container.classList.contains('visible')) return;
        
        const stats = this.flightData.getStatisticsAt(time);
        if (!stats) return;
        
        // Format time
        const gregorian = Cesium.JulianDate.toGregorianDate(stats.localTime);
        const timeStr = `${gregorian.hour.toString().padStart(2, '0')}:${gregorian.minute.toString().padStart(2, '0')}`;
        const tzLabel = this.flightData.timezone ? ` (${this.flightData.timezone})` : '';
        
        // Choose climb icon
        const climbIcon = stats.climbRate > 0.1 ? 'trending_up' : 
                         stats.climbRate < -0.1 ? 'trending_down' : 'trending_flat';
        const climbSign = stats.climbRate >= 0 ? '+' : '';
        
        // Update HTML
        this.container.innerHTML = `
            <div class="stat-item">
                <i class="material-icons">height</i>
                <div class="stat-value">${stats.altitude.toFixed(0)}m</div>
                <div class="stat-label">Altitude</div>
            </div>
            <div class="stat-item">
                <i class="material-icons">${climbIcon}</i>
                <div class="stat-value">${climbSign}${stats.climbRate.toFixed(1)}m/s</div>
                <div class="stat-label">Climb</div>
            </div>
            <div class="stat-item">
                <i class="material-icons">speed</i>
                <div class="stat-value">${stats.speed.toFixed(1)}km/h</div>
                <div class="stat-label">Speed</div>
            </div>
            <div class="stat-item">
                <i class="material-icons">access_time</i>
                <div class="stat-value">${timeStr}</div>
                <div class="stat-label">Time${tzLabel}</div>
            </div>
        `;
    }
}

// ============================================================================
// Main Cesium Flight Application
// ============================================================================

class CesiumFlightApp {
    constructor() {
        this.viewer = null;
        this.flightDataSource = null;
        this.trackPrimitives = null;
        this.statisticsDisplay = null;
        this.cameraFollowing = false;
        this._ribbonModeAuto = true;
        this._updateThrottle = { lastUpdate: 0, interval: 100 };
        this._originalQualitySettings = null;
        this._qualityRestoreTimer = null;
    }
    
    initialize(config) {
        PerformanceReporter.measureTime('initialization', () => {
            this._createViewer(config);
            this._setupEventHandlers();
            
            // Load initial track if provided
            if (config.trackPoints?.length > 0) {
                setTimeout(() => this.loadFlightTrack(config.trackPoints), 100);
            }
        });
    }
    
    _createViewer(config) {
        // Essential imagery providers
        const imageryProviders = this._createImageryProviders();
        const selectedProvider = config.savedBaseMap ? 
            imageryProviders.find(vm => vm.name === config.savedBaseMap) || imageryProviders[0] :
            imageryProviders[0];
        
        // Detect high DPI displays and apply resolution scaling
        const devicePixelRatio = window.devicePixelRatio || 1.0;
        const resolutionScale = devicePixelRatio > 1 ? Math.min(devicePixelRatio, 2.0) : 1.0;
        
        // Create viewer with optimized settings
        this.viewer = new Cesium.Viewer("cesiumContainer", {
            terrain: Cesium.Terrain.fromWorldTerrain({
                requestWaterMask: false,
                requestVertexNormals: true
            }),
            requestRenderMode: true,
            maximumRenderTimeChange: Infinity,
            resolutionScale: resolutionScale,  // Apply high DPI scaling
            
            // UI controls
            baseLayerPicker: true,
            imageryProviderViewModels: imageryProviders,
            selectedImageryProviderViewModel: selectedProvider,
            geocoder: true,
            homeButton: true,
            sceneModePicker: true,
            navigationHelpButton: true,
            navigationInstructionsInitiallyVisible: config.savedNavigationHelpDialogOpen || false,
            animation: false,
            timeline: true,
            fullscreenButton: true,
            vrButton: false,
            shadows: false,
            shouldAnimate: false,
            creditContainer: document.getElementById('customCreditContainer')
        });
        
        this._configureScene();
        this._setupInitialView(config);
        
        // Hide terrain options from baseLayerPicker - show only imagery choices
        if (this.viewer.baseLayerPicker && this.viewer.baseLayerPicker.viewModel) {
            this.viewer.baseLayerPicker.viewModel.terrainProviderViewModels = [];
            
            // Hide the "Imagery" category label whenever the picker is opened
            const hideImageryLabel = () => {
                const pickerContainer = document.querySelector('.cesium-baseLayerPicker-dropDown');
                if (pickerContainer) {
                    const categoryLabels = pickerContainer.querySelectorAll('.cesium-baseLayerPicker-sectionTitle');
                    categoryLabels.forEach(label => {
                        if (label.textContent === 'Imagery') {
                            label.style.display = 'none';
                        }
                    });
                }
            };
            
            // Watch for dropdown visibility changes
            const pickerButton = document.querySelector('.cesium-baseLayerPicker-selected');
            if (pickerButton) {
                pickerButton.addEventListener('click', () => {
                    setTimeout(hideImageryLabel, 10);
                });
            }
            
            // Also hide on initial load
            setTimeout(hideImageryLabel, 100);
        }
    }
    
    _createImageryProviders() {
        return [
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
    }
    
    _configureScene() {
        const scene = this.viewer.scene;
        const globe = scene.globe;
        
        // Enhanced terrain lighting for better depth perception
        globe.enableLighting = true;
        globe.lightingFadeOutDistance = 6500000;
        globe.lightingFadeInDistance = 9000000;
        globe.nightFadeOutDistance = 10000000;
        globe.nightFadeInDistance = 50000000;
        globe.showGroundAtmosphere = true;
        globe.depthTestAgainstTerrain = true;
        globe.terrainExaggeration = 1.0;
        
        // Set base color to dark gray for less jarring transitions when switching maps
        globe.baseColor = Cesium.Color.fromCssColorString('#2b2b2b');
        scene.backgroundColor = Cesium.Color.fromCssColorString('#2b2b2b');
        
        // Adjust fog for clearer terrain
        scene.fog.enabled = true;
        scene.fog.density = 0.00005;  // Reduced density for clearer distant terrain
        scene.fog.screenSpaceErrorFactor = 2.0;
        
        scene.highDynamicRange = true;
        scene.fxaa = true;
        scene.msaaSamples = 8;
        
        // High-quality terrain settings
        globe.tileCacheSize = 500;  // Increased cache for smoother terrain
        globe.preloadSiblings = true;
        globe.preloadAncestors = true;
        globe.maximumMemoryUsage = 512;
        globe.maximumScreenSpaceError = 1.0;  // Reduced for higher quality terrain
        
        // Camera controls
        const controller = scene.screenSpaceCameraController;
        controller.enableCollisionDetection = true;
        controller.minimumZoomDistance = 10.0;
        controller.minimumCollisionTerrainHeight = 5000.0;
        controller.collisionDetectionHeightBuffer = 10.0;
    }
    
    _setupInitialView(config) {
        if (!config.trackPoints?.length) {
            this.viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(config.lon, config.lat, config.altitude),
                orientation: {
                    heading: 0,
                    pitch: Cesium.Math.toRadians(-45),
                    roll: 0
                }
            });
        }
        
        // Apply saved scene mode
        if (config.savedSceneMode && config.savedSceneMode !== '3D') {
            const sceneMode = config.savedSceneMode === '2D' ? Cesium.SceneMode.SCENE2D :
                             config.savedSceneMode === 'Columbus' ? Cesium.SceneMode.COLUMBUS_VIEW :
                             Cesium.SceneMode.SCENE3D;
            this.viewer.scene.mode = sceneMode;
        }
    }
    
    _setupEventHandlers() {
        // Clock tick handler
        this.viewer.clock.onTick.addEventListener((clock) => this._onClockTick(clock));
        
        // Scene mode change handler
        this.viewer.scene.morphComplete.addEventListener(() => this._onSceneModeChange());
        
        // Home button override
        if (this.viewer.homeButton?.viewModel) {
            this.viewer.homeButton.viewModel.command.beforeExecute.addEventListener((commandInfo) => {
                if (this.flightDataSource?.boundingSphere) {
                    commandInfo.cancel = true;
                    this._flyToFlightTrack();
                }
            });
        }
        
        // Loading overlay
        this.viewer.scene.globe.tileLoadProgressEvent.addEventListener((queuedTileCount) => {
            if (queuedTileCount === 0) {
                document.getElementById('loadingOverlay').style.display = 'none';
            }
        });
    }
    
    loadFlightTrack(igcPoints) {
        if (!igcPoints?.length) return;
        
        PerformanceReporter.measureTime('totalTrackLoad', () => {
            // Clear existing data
            this._clearAll();
            
            // Create new flight data source
            this.flightDataSource = new FlightDataSource('Flight Track', igcPoints);
            this.viewer.dataSources.add(this.flightDataSource);
            
            // Create track primitives
            this.trackPrimitives = new TrackPrimitiveCollection(this.viewer, this.flightDataSource);
            
            // Create statistics display
            this.statisticsDisplay = new StatisticsDisplay(this.flightDataSource);
            this.statisticsDisplay.show();
            
            // Configure clock
            this._configureClock();
            
            // Configure timeline for local time
            this._configureTimeline();
            
            // Zoom to track
            this._performInitialZoom();
            
            // Force resize after UI changes
            setTimeout(() => this.viewer.resize(), 350);
        });
    }
    
    _configureClock() {
        const clock = this.viewer.clock;
        const data = this.flightDataSource;
        
        clock.startTime = data.startTime.clone();
        clock.stopTime = data.stopTime.clone();
        clock.currentTime = data.startTime.clone();
        clock.clockRange = Cesium.ClockRange.CLAMPED;
        clock.multiplier = 60;
        clock.shouldAnimate = false;
        
        if (this.viewer.timeline) {
            this.viewer.timeline.zoomTo(data.startTime, data.stopTime);
        }
    }
    
    _configureTimeline() {
        const data = this.flightDataSource;
        const offsetSeconds = data.timezoneOffsetSeconds;
        const timezone = data.timezone;
        
        if (this.viewer.timeline && offsetSeconds !== 0) {
            this.viewer.timeline.makeLabel = (date) => {
                const localDate = Cesium.JulianDate.addSeconds(date, offsetSeconds, new Cesium.JulianDate());
                const gregorian = Cesium.JulianDate.toGregorianDate(localDate);
                const hours = gregorian.hour.toString().padStart(2, '0');
                const minutes = gregorian.minute.toString().padStart(2, '0');
                const seconds = Math.floor(gregorian.second).toString().padStart(2, '0');
                return `${hours}:${minutes}:${seconds} ${timezone}`;
            };
        }
    }
    
    _performInitialZoom() {
        const data = this.flightDataSource;
        const launch = data.igcPoints[0];
        const boundingSphere = data.boundingSphere;
        
        // Step 1: High altitude view
        this.viewer.camera.setView({
            destination: Cesium.Cartesian3.fromDegrees(launch.longitude, launch.latitude, 30000000),
            orientation: {
                heading: 0,
                pitch: Cesium.Math.toRadians(-90),
                roll: 0
            }
        });
        
        // Step 2: Fly to bounding sphere
        setTimeout(() => {
            this.viewer.camera.flyToBoundingSphere(boundingSphere, {
                duration: 5.0,
                offset: new Cesium.HeadingPitchRange(
                    Cesium.Math.toRadians(0),
                    Cesium.Math.toRadians(-90),
                    boundingSphere.radius * 2.5
                ),
                complete: () => {
                    // Step 3: Final view angle
                    this.viewer.camera.flyToBoundingSphere(boundingSphere, {
                        duration: 3.0,
                        offset: new Cesium.HeadingPitchRange(
                            Cesium.Math.toRadians(0),
                            Cesium.Math.toRadians(-30),
                            boundingSphere.radius * 2.75
                        )
                    });
                }
            });
        }, 5000);
    }
    
    _flyToFlightTrack() {
        if (!this.flightDataSource) return;
        
        const boundingSphere = this.flightDataSource.boundingSphere;
        this.viewer.camera.flyToBoundingSphere(boundingSphere, {
            duration: 3.0,
            offset: new Cesium.HeadingPitchRange(
                Cesium.Math.toRadians(0),
                Cesium.Math.toRadians(-30),
                boundingSphere.radius * 2.75
            )
        });
    }
    
    _onClockTick(clock) {
        if (!this.flightDataSource) return;
        
        // Handle automatic ribbon mode
        this._updateRibbonMode(clock);
        
        // Update statistics
        this.statisticsDisplay?.update(clock.currentTime);
        
        // Update dynamic track (throttled)
        const now = Date.now();
        if (now - this._updateThrottle.lastUpdate > this._updateThrottle.interval) {
            this._updateThrottle.lastUpdate = now;
            this.trackPrimitives?.updateDynamicTrack(clock.currentTime);
        }
        
        // Handle play button state
        this._updatePlayButton();
        
        // Handle end of playback
        this._handlePlaybackEnd(clock);
        
        // Update render mode
        this._updateRenderMode(clock);
    }
    
    _updateRibbonMode(clock) {
        if (!this._ribbonModeAuto) return;
        
        const atStart = Cesium.JulianDate.secondsDifference(clock.currentTime, clock.startTime) < 0.5;
        const atEnd = Cesium.JulianDate.compare(clock.currentTime, clock.stopTime) >= 0;
        const isStopped = !clock.shouldAnimate;
        
        const shouldShowRibbon = !(isStopped && (atStart || atEnd));
        
        if (shouldShowRibbon !== this._currentRibbonState) {
            this.flightDataSource?.enableRibbonMode(shouldShowRibbon);
            this.trackPrimitives?.enableRibbonMode(shouldShowRibbon);
            this._currentRibbonState = shouldShowRibbon;
        }
    }
    
    _updatePlayButton() {
        const button = document.getElementById('playButton');
        if (!button) return;
        
        const icon = button.querySelector('.material-icons');
        if (!icon) return;
        
        const clock = this.viewer.clock;
        const atStart = Cesium.JulianDate.secondsDifference(clock.currentTime, clock.startTime) < 0.5;
        const atEnd = Cesium.JulianDate.compare(clock.currentTime, clock.stopTime) >= 0;
        
        icon.textContent = (!clock.shouldAnimate || atStart || atEnd) ? 'play_arrow' : 'pause';
    }
    
    _handlePlaybackEnd(clock) {
        // Track animation state
        if (!this._wasAnimating) {
            this._wasAnimating = false;
        }
        
        const atEnd = Cesium.JulianDate.compare(clock.currentTime, clock.stopTime) >= 0;
        const justStarted = clock.shouldAnimate && !this._wasAnimating;
        
        if (atEnd && justStarted) {
            clock.currentTime = clock.startTime.clone();
        }
        
        if (atEnd && clock.shouldAnimate && !justStarted) {
            clock.shouldAnimate = false;
            clock.currentTime = clock.startTime.clone();
        }
        
        this._wasAnimating = clock.shouldAnimate;
    }
    
    _updateRenderMode(clock) {
        const shouldContinuousRender = this._currentRibbonState && clock.shouldAnimate;
        
        if (shouldContinuousRender && this.viewer.scene.requestRenderMode) {
            this.viewer.scene.requestRenderMode = false;
        } else if (!shouldContinuousRender && !this.viewer.scene.requestRenderMode) {
            this.viewer.scene.requestRenderMode = true;
            this.viewer.scene.requestRender();
        }
    }
    
    _onSceneModeChange() {
        const modeString = this._getSceneModeString();
        
        if (window.flutter_inappwebview?.callHandler) {
            window.flutter_inappwebview.callHandler('onSceneModeChanged', modeString);
        }
        
        // Update camera controls
        const controller = this.viewer.scene.screenSpaceCameraController;
        if (this.viewer.scene.mode === Cesium.SceneMode.SCENE2D) {
            controller.enableCollisionDetection = false;
            controller.enableRotate = false;
            controller.enableTilt = false;
        } else {
            controller.enableCollisionDetection = true;
            controller.enableRotate = true;
            controller.enableTilt = true;
        }
        
        // Restore view
        if (this.flightDataSource) {
            setTimeout(() => this._flyToFlightTrack(), 500);
        }
    }
    
    _getSceneModeString() {
        switch(this.viewer.scene.mode) {
            case Cesium.SceneMode.SCENE2D: return '2D';
            case Cesium.SceneMode.COLUMBUS_VIEW: return 'Columbus';
            default: return '3D';
        }
    }
    
    togglePlayback() {
        if (!this.viewer) return;
        this.viewer.clock.shouldAnimate = !this.viewer.clock.shouldAnimate;
    }
    
    changePlaybackSpeed(speed) {
        if (!this.viewer) return;
        const speedValue = parseFloat(speed);
        if (!isNaN(speedValue)) {
            this.viewer.clock.multiplier = speedValue;
            document.getElementById('speedPicker').value = speed;
        }
    }
    
    toggleCameraFollow() {
        if (!this.viewer || !this.flightDataSource) return;
        
        const pilot = this.flightDataSource.pilotEntity;
        const button = document.getElementById('followButton');
        
        if (this.viewer.trackedEntity === pilot) {
            this.viewer.trackedEntity = undefined;
            this.cameraFollowing = false;
            if (button) button.style.backgroundColor = 'rgba(42, 42, 42, 0.8)';
        } else {
            this.viewer.trackedEntity = pilot;
            this.cameraFollowing = true;
            if (button) button.style.backgroundColor = 'rgba(76, 175, 80, 0.8)';
        }
    }
    
    _clearAll() {
        if (this.trackPrimitives) {
            this.trackPrimitives.destroy();
            this.trackPrimitives = null;
        }
        
        if (this.flightDataSource) {
            this.viewer.dataSources.remove(this.flightDataSource);
            this.flightDataSource = null;
        }
        
        this.viewer.entities.removeAll();
        this.viewer.scene.primitives.removeAll();
        
        this.statisticsDisplay?.hide();
    }
    
    cleanup() {
        this._clearAll();
        this.statisticsDisplay = null;
        
        if (this.viewer) {
            this.viewer.scene.requestRenderMode = true;
            this.viewer.destroy();
            this.viewer = null;
        }
    }
    
    handleMemoryPressure() {
        if (!this.viewer) return;
        
        PerformanceReporter.report('memoryPressureHandled', true);
        
        const globe = this.viewer.scene.globe;
        const scene = this.viewer.scene;
        
        // Store original settings on first memory pressure
        if (!this._originalQualitySettings) {
            this._originalQualitySettings = {
                tileCacheSize: globe.tileCacheSize,
                maximumMemoryUsage: globe.maximumMemoryUsage,
                maximumScreenSpaceError: globe.maximumScreenSpaceError,
                maximumTextureSize: scene.maximumTextureSize || 8192
            };
            console.log('[Cesium] Storing original quality settings:', this._originalQualitySettings);
        }
        
        // Clear tile cache
        if (globe?.tileCache) {
            globe.tileCache.reset();
        }
        
        // Apply gradual quality reduction (70% memory, 2x quality degradation)
        globe.tileCacheSize = Math.floor(this._originalQualitySettings.tileCacheSize * 0.7);
        globe.maximumMemoryUsage = Math.floor(this._originalQualitySettings.maximumMemoryUsage * 0.7);
        globe.maximumScreenSpaceError = Math.min(this._originalQualitySettings.maximumScreenSpaceError * 2, 4.0);
        scene.maximumTextureSize = 2048;
        
        console.log('[Cesium] Applied gradual quality reduction:', {
            tileCacheSize: globe.tileCacheSize,
            maximumMemoryUsage: globe.maximumMemoryUsage,
            maximumScreenSpaceError: globe.maximumScreenSpaceError
        });
        
        // Request render with reduced quality
        scene.requestRenderMode = true;
        scene.requestRender();
        
        // Clear any existing restore timer
        if (this._qualityRestoreTimer) {
            clearTimeout(this._qualityRestoreTimer);
        }
        
        // Schedule quality restoration after 30 seconds
        this._qualityRestoreTimer = setTimeout(() => {
            this.restoreQualitySettings();
        }, 30000);
        
        console.log('[Cesium] Quality will be restored in 30 seconds');
        
        // Trigger garbage collection if available
        if (window.gc) window.gc();
    }
    
    restoreQualitySettings() {
        if (!this.viewer || !this._originalQualitySettings) return;
        
        const globe = this.viewer.scene.globe;
        const scene = this.viewer.scene;
        
        console.log('[Cesium] Restoring original quality settings');
        
        // Restore original settings
        globe.tileCacheSize = this._originalQualitySettings.tileCacheSize;
        globe.maximumMemoryUsage = this._originalQualitySettings.maximumMemoryUsage;
        globe.maximumScreenSpaceError = this._originalQualitySettings.maximumScreenSpaceError;
        scene.maximumTextureSize = this._originalQualitySettings.maximumTextureSize;
        
        // Clear the restore timer
        if (this._qualityRestoreTimer) {
            clearTimeout(this._qualityRestoreTimer);
            this._qualityRestoreTimer = null;
        }
        
        // Request render with restored quality
        scene.requestRenderMode = false;
        scene.requestRender();
        
        console.log('[Cesium] Quality settings restored:', {
            tileCacheSize: globe.tileCacheSize,
            maximumMemoryUsage: globe.maximumMemoryUsage,
            maximumScreenSpaceError: globe.maximumScreenSpaceError
        });
        
        PerformanceReporter.report('qualityRestored', true);
    }
}

// ============================================================================
// Global Instance and API
// ============================================================================

let cesiumApp = null;

// Initialize function called from HTML
function initializeCesium(config) {
    // Set Ion token
    Cesium.Ion.defaultAccessToken = config.token;
    
    // Create and initialize app
    cesiumApp = new CesiumFlightApp();
    cesiumApp.initialize(config);
    
    // Store globally for compatibility
    window.viewer = cesiumApp.viewer;
}

// Public API functions
function createColoredFlightTrack(points) {
    cesiumApp?.loadFlightTrack(points);
}

function togglePlayback() {
    cesiumApp?.togglePlayback();
}

function changePlaybackSpeed(speed) {
    cesiumApp?.changePlaybackSpeed(speed);
}

function toggleCameraFollow() {
    cesiumApp?.toggleCameraFollow();
}

function cleanupCesium() {
    cesiumApp?.cleanup();
    cesiumApp = null;
    window.viewer = null;
}

function handleMemoryPressure() {
    cesiumApp?.handleMemoryPressure();
}

function restoreQualitySettings() {
    cesiumApp?.restoreQualitySettings();
}

function checkMemory() {
    if (window.performance?.memory) {
        const memory = window.performance.memory;
        return {
            used: Math.round(memory.usedJSHeapSize / 1048576),
            total: Math.round(memory.totalJSHeapSize / 1048576),
            limit: Math.round(memory.jsHeapSizeLimit / 1048576)
        };
    }
    return null;
}

// Cleanup on page unload
window.addEventListener('beforeunload', cleanupCesium);

// Handle visibility changes
document.addEventListener('visibilitychange', () => {
    if (cesiumApp?.viewer) {
        if (document.hidden) {
            cesiumApp.viewer.scene.requestRenderMode = true;
            cesiumApp.viewer.scene.maximumRenderTimeChange = Infinity;
        } else {
            cesiumApp.viewer.scene.requestRenderMode = false;
        }
    }
});

// Export public API
window.initializeCesium = initializeCesium;
window.createColoredFlightTrack = createColoredFlightTrack;
window.togglePlayback = togglePlayback;
window.changePlaybackSpeed = changePlaybackSpeed;
window.toggleCameraFollow = toggleCameraFollow;
window.cleanupCesium = cleanupCesium;
window.handleMemoryPressure = handleMemoryPressure;
window.restoreQualitySettings = restoreQualitySettings;
window.checkMemory = checkMemory;