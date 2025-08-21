# Product Requirements Document: Cesium 3D Flight Track Visualization

## 1. Executive Summary

### 1.1 Product Overview
A web-based 3D flight track visualization system using CesiumJS that displays paraglider, hang glider, and microlight flight paths with real-time playback, performance metrics, and interactive controls.

### 1.2 Primary Use Case
Pilots review their recorded flights in an immersive 3D environment, analyzing flight performance through visual track representation, altitude profiles, and real-time statistics.

### 1.3 Key Differentiators
- Climb rate-based track coloring for thermal identification
- Curtain wall visualization showing altitude profile
- Real-time flight statistics display
- Smooth camera following during playback
- Performance-optimized for mobile devices

## 2. Technical Architecture

### 2.1 Core Technology Stack
- **Framework**: CesiumJS 1.132+
- **Language**: JavaScript (ES6+)
- **Integration**: Flutter WebView via JavaScript handlers
- **Data Format**: IGC (International Gliding Commission) flight records

### 2.2 System Components
```
┌─────────────────────────────────────────────────┐
│                Flutter Application               │
├─────────────────────────────────────────────────┤
│              WebView Container                   │
├─────────────────────────────────────────────────┤
│           CesiumJS Flight Viewer                 │
├──────────────┬──────────────┬───────────────────┤
│   Flight     │   Track      │    Statistics     │
│   DataSource │  Primitives  │     Display       │
├──────────────┴──────────────┴───────────────────┤
│              Cesium Core Engine                  │
└─────────────────────────────────────────────────┘
```

## 3. Functional Requirements

### 3.1 Data Input & Processing

#### 3.1.1 IGC Point Structure
**Input Format:**
```javascript
{
  timestamp: "2025-07-11T11:03:56.000+02:00",  // ISO8601 with timezone
  latitude: 45.12345,                          // Decimal degrees
  longitude: 6.54321,                          // Decimal degrees
  altitude: 1234,                              // GPS altitude in meters
  gpsAltitude: 1234,                           // GPS altitude (preferred)
  pressureAltitude: 1230,                      // Pressure altitude (optional)
  climbRate: 2.5,                              // Instantaneous climb rate (m/s)
  climbRate15s: 2.3,                           // 15-second average (m/s)
  groundSpeed: 35.5,                           // Ground speed (km/h)
  timezone: "+02:00"                           // Timezone offset
}
```

#### 3.1.2 Data Processing Requirements
- **Bulk Processing**: Process entire track arrays in single operations
- **Position Conversion**: Convert lat/lon/alt to Cesium Cartesian3 coordinates
- **Time Conversion**: Convert ISO8601 timestamps to Cesium JulianDate
- **Timezone Handling**: Apply timezone offsets for local time display
- **Validation**: Ensure chronological order and data integrity

### 3.2 Track Visualization

#### 3.2.1 Polyline Track
**Visual Representation:**
- Width: 3.0 pixels
- Opacity: 0.9 (90% opaque)
- Anti-aliasing: Enabled
- Depth test: Disabled at distance

**Color Coding by Climb Rate:**
- **Green** (RGB: 0,255,0): Positive climb rate (≥ 0 m/s)
- **Blue** (RGB: 30,144,255): Weak sink (-1.5 to 0 m/s)  
- **Red** (RGB: 255,0,0): Strong sink (< -1.5 m/s)

**Implementation Modes:**
1. **Static Mode**: Full track visible at all times
2. **Ribbon Mode**: Dynamic trailing segment during playback
   - Default trail duration: 3 seconds of flight time
   - Adjusts based on playback speed multiplier

#### 3.2.2 Curtain Wall
**Purpose:** Visualize altitude profile beneath flight path

**Specifications:**
- Extends from track position to ground level
- Semi-transparent blue (DODGERBLUE with 10% opacity)
- No outline to maintain clean appearance
- Two modes:
  1. Static: Complete wall for entire track
  2. Dynamic: Trailing wall synchronized with ribbon mode

### 3.3 Pilot Entity

#### 3.3.1 Visual Representation
**Marker Specifications:**
- Shape: Circular point
- Size: 16 pixels base
- Core color: Yellow (RGB: 255,255,0)
- Outline: Black, 3 pixels wide
- Scaling: Distance-based (1.5x at 1km, 0.5x at 100km)

#### 3.3.2 Motion Properties
**Position:**
- Sampled position property with linear interpolation
- Forward/backward extrapolation: HOLD
- Update frequency: Synchronized with clock tick

**Orientation:**
- Velocity-based orientation (points in direction of travel)
- Automatic calculation from position derivatives

#### 3.3.3 Camera View
- Default view offset: 1000m behind, 500m above
- Trackable entity for camera following
- Smooth transitions when tracked

### 3.4 Statistics Display

#### 3.4.1 Display Panel
**Location:** Top-right corner overlay
**Background:** Semi-transparent dark (rgba(42,42,42,0.9))
**Border radius:** 8px
**Padding:** 15px

#### 3.4.2 Metrics Displayed
1. **Altitude**
   - Icon: height
   - Format: "1234m"
   - Source: GPS altitude preferred

2. **Climb Rate**
   - Icons: trending_up/trending_flat/trending_down
   - Format: "+2.5m/s" or "-1.2m/s"
   - Source: 15s average preferred, fallback to instantaneous

3. **Ground Speed**
   - Icon: speed
   - Format: "35.5km/h"
   - Calculation: From GPS positions if not provided

4. **Local Time**
   - Icon: access_time
   - Format: "HH:MM (timezone)"
   - Display: Converted to launch location timezone

### 3.5 Playback Controls

#### 3.5.1 Control Panel
**Location:** Bottom-center overlay
**Components:**
```
[▶️/⏸️ Play] [1x ▼ Speed] [📹 Follow]
```

#### 3.5.2 Play/Pause Button
- Toggle animation state
- Icon changes: play_arrow ↔ pause
- Auto-reset at track end
- Auto-play from start if activated at end

#### 3.5.3 Speed Selector
**Options:**
- 0.25x: Slow motion analysis
- 0.5x: Detailed review
- 1x: Real-time
- 2x: Quick review
- 5x: Fast forward
- 10x: Rapid scan
- 30x: Quick overview
- 60x: Full flight scan
- 120x: Ultra-fast

#### 3.5.4 Camera Follow Button
- Toggle tracked entity
- Visual feedback: Green when active
- Maintains smooth following with configurable offset

### 3.6 Map & Terrain

#### 3.6.1 Imagery Providers
**Required Options:**
1. Bing Maps Aerial with Labels (default)
2. Bing Maps Aerial (no labels)
3. Bing Maps Roads
4. OpenStreetMap

**Implementation:**
- Layer picker UI element
- Persistent selection across sessions
- Fallback to default on error

#### 3.6.2 Terrain
**Specifications:**
- Cesium World Terrain
- Vertex normals: Enabled for shading
- Water mask: Disabled (performance)
- Exaggeration: 1.0 (no vertical scaling)
- Depth testing: Enabled

### 3.7 Timeline

#### 3.7.1 Display
- Shows full flight duration
- Displays local time with timezone
- Interactive scrubbing
- Visual current time indicator

#### 3.7.2 Behavior
- Auto-zoom to flight duration
- Click to jump to time
- Drag for scrubbing
- Smooth animation transitions

## 4. Performance Requirements

### 4.1 Target Metrics
- **Initial Load**: < 3 seconds
- **Track Processing**: < 500ms for 10,000 points
- **Frame Rate**: Minimum 30 FPS during playback
- **Memory Usage**: < 512MB for typical flight

### 4.2 Optimization Strategies

#### 4.2.1 Data Processing
- Bulk array operations instead of loops
- Pre-calculate positions and times
- Cache bounding spheres
- Binary search for time lookups

#### 4.2.2 Rendering
- Request render mode when static
- Primitive collection for tracks (vs entities)
- Double buffering for dynamic updates
- LOD scaling for markers

#### 4.2.3 Memory Management
- Tile cache: 300 tiles maximum
- Texture size limit: 2048px
- Automatic garbage collection triggers
- Memory pressure handling with quality reduction

### 4.3 Mobile Optimization
- Touch-friendly controls
- Responsive layout
- Reduced quality settings on low-end devices
- WebView integration optimizations

## 5. User Interface Requirements

### 5.1 Cesium Viewer Configuration

#### 5.1.1 Essential UI Elements
**Enabled:**
- Base layer picker
- Geocoder (search)
- Home button
- Scene mode picker (2D/3D/Columbus)
- Timeline
- Navigation help
- Fullscreen button

**Disabled:**
- Animation widget (redundant with custom controls)
- VR button
- Shadows (performance)

#### 5.1.2 Initial Camera View
**Without Track:**
- User's current location or last known position
- Altitude: 10,000m
- Pitch: -45°

**With Track:**
1. Start at high altitude (30,000km)
2. Fly to bounding sphere (5 seconds)
3. Final approach to optimal viewing angle (3 seconds)
4. Final position: 2.75x bounding radius, -30° pitch

### 5.2 Scene Modes

#### 5.2.1 3D Mode (Default)
- Full globe visualization
- Free camera movement
- Collision detection enabled
- Terrain interaction

#### 5.2.2 2D Mode
- Flat map projection
- Disabled rotation/tilt
- Simplified controls
- Better for track overview

#### 5.2.3 Columbus View
- 2.5D perspective
- Altitude visualization
- Compromise between 2D/3D

## 6. Integration Requirements

### 6.1 Flutter Communication

#### 6.1.1 Inbound Messages (Flutter → Cesium)
```javascript
// Initialize viewer
initializeCesium({
  token: "cesium_ion_token",
  lat: 45.0,
  lon: 6.0,
  altitude: 10000,
  trackPoints: [...],
  savedBaseMap: "Bing Maps Aerial",
  savedSceneMode: "3D"
})

// Load track
createColoredFlightTrack(igcPoints)

// Control playback
togglePlayback()
changePlaybackSpeed(multiplier)
toggleCameraFollow()

// Memory management
handleMemoryPressure()
cleanupCesium()
```

#### 6.1.2 Outbound Messages (Cesium → Flutter)
```javascript
// Performance metrics
flutter_inappwebview.callHandler('performanceMetric', {
  metric: 'dataProcessing',
  value: 250 // milliseconds
})

// Scene mode changes
flutter_inappwebview.callHandler('onSceneModeChanged', '2D')

// Memory status
flutter_inappwebview.callHandler('memoryStatus', {
  used: 256,  // MB
  total: 512, // MB
  limit: 1024 // MB
})
```

## 7. Data Structures

### 7.1 Class Hierarchy

```
CesiumFlightApp
├── FlightDataSource (extends Cesium.CustomDataSource)
│   ├── IGC Points Array
│   ├── Position Property
│   ├── Pilot Entity
│   ├── Static Curtain Entity
│   └── Dynamic Curtain Entity
├── TrackPrimitiveCollection
│   ├── Static Primitive
│   └── Dynamic Primitive
└── StatisticsDisplay
    └── DOM Container
```

### 7.2 Key Algorithms

#### 7.2.1 Time Index Binary Search
```javascript
function findTimeIndex(times, targetTime) {
  let left = 0, right = times.length - 1;
  while (left <= right) {
    const mid = Math.floor((left + right) / 2);
    const cmp = Cesium.JulianDate.compare(times[mid], targetTime);
    if (cmp < 0) left = mid + 1;
    else if (cmp > 0) right = mid - 1;
    else return mid;
  }
  return Math.max(0, left - 1);
}
```

#### 7.2.2 Ribbon Window Calculation
```javascript
function calculateRibbonWindow(ribbonSeconds, playbackSpeed, totalPoints, flightDuration) {
  const effectiveSeconds = ribbonSeconds * playbackSpeed;
  const pointsPerSecond = totalPoints / flightDuration;
  return Math.ceil(effectiveSeconds * pointsPerSecond);
}
```

## 8. Error Handling

### 8.1 Graceful Degradation
- Missing climb rate: Calculate from altitude changes
- Missing speed: Calculate from position changes
- Missing timezone: Default to UTC
- Invalid timestamps: Skip points and log warning

### 8.2 Resource Limits
- Maximum points: 100,000
- Maximum flight duration: 24 hours
- Minimum points for track: 2
- Memory pressure: Reduce quality settings

### 8.3 User Feedback
- Loading overlay during initialization
- Progress indicators for long operations
- Error messages for invalid data
- Memory warnings when approaching limits

## 9. Testing Requirements

### 9.1 Functional Tests
- Load tracks with 10 to 10,000 points
- Verify color coding accuracy
- Test all playback speeds
- Validate timezone conversions
- Check memory cleanup

### 9.2 Performance Tests
- Measure load times for various track sizes
- Monitor frame rates during playback
- Track memory usage over time
- Test on minimum spec devices

### 9.3 Edge Cases
- Flights crossing midnight
- Flights crossing date line
- Zero altitude flights
- Missing data fields
- Rapid playback speed changes

## 10. Future Enhancements

### 10.1 Phase 2 Features
- Multiple track comparison
- Waypoint/turnpoint markers
- Airspace overlays
- Weather data integration
- Track sharing/export

### 10.2 Phase 3 Features
- Real-time tracking
- Competition scoring
- Route optimization
- Thermal mapping
- Social features

## 11. Acceptance Criteria

### 11.1 Core Functionality
- [ ] Track loads and displays within 3 seconds
- [ ] Colors accurately represent climb rates
- [ ] Statistics update in real-time
- [ ] Playback controls respond immediately
- [ ] Camera following is smooth
- [ ] Memory usage stays under limits

### 11.2 User Experience
- [ ] Interface is intuitive without training
- [ ] Performance is smooth on target devices
- [ ] Visual quality meets expectations
- [ ] All controls are accessible
- [ ] Error messages are helpful

### 11.3 Technical Requirements
- [ ] WebView integration works bidirectionally
- [ ] Memory management prevents crashes
- [ ] Performance metrics are tracked
- [ ] Code is maintainable and documented
- [ ] No console errors in normal operation

## Appendix A: Color Specifications

| Element | Color | RGB | Hex | Alpha |
|---------|-------|-----|-----|-------|
| Track Green | Climb | 0,255,0 | #00FF00 | 0.9 |
| Track Blue | Weak Sink | 30,144,255 | #1E90FF | 0.9 |
| Track Red | Strong Sink | 255,0,0 | #FF0000 | 0.9 |
| Pilot Marker | Yellow | 255,255,0 | #FFFF00 | 1.0 |
| Pilot Outline | Black | 0,0,0 | #000000 | 1.0 |
| Curtain Wall | Dodger Blue | 30,144,255 | #1E90FF | 0.1 |
| Stats Panel | Dark Gray | 42,42,42 | #2A2A2A | 0.9 |
| Follow Active | Green | 76,175,80 | #4CAF50 | 0.8 |

## Appendix B: Performance Benchmarks

| Operation | Target Time | Max Time | Points |
|-----------|------------|----------|--------|
| Initial Load | 1s | 3s | N/A |
| Track Processing | 200ms | 500ms | 5,000 |
| Track Processing | 400ms | 1000ms | 10,000 |
| Frame Rate (Static) | 60 FPS | 30 FPS | Any |
| Frame Rate (Playback) | 30 FPS | 20 FPS | Any |
| Memory Usage | 256MB | 512MB | 10,000 |

## Appendix C: Browser Compatibility

| Browser | Minimum Version | Optimal Version |
|---------|----------------|-----------------|
| Chrome | 90+ | 100+ |
| Safari | 14+ | 16+ |
| Firefox | 88+ | 100+ |
| Edge | 90+ | 100+ |
| WebView Android | 90+ | 100+ |
| WebView iOS | 14+ | 16+ |