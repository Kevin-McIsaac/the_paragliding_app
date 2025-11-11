# The Paragliding App - Functional Specification

## 1. Introduction

### 1.1 Purpose
The Paragliding App is a mobile application designed to simplify flight logging for paraglider, hang glider, and microlight pilots. The app automates data collection from flight computers while providing manual entry options, comprehensive flight analysis, and regulatory compliance reporting.

### 1.2 Scope
This document defines the functional requirements for the The Paragliding App mobile application, including all user-facing features, data management capabilities, and integration requirements.

### 1.3 Target Users
- Paraglider pilots
- Hang glider pilots
- Microlight pilots
- Flight instructors and schools
- Pilots requiring flight logs for license compliance

## 2. System Overview

### 2.1 Core Objectives

- Minimize manual data entry through automated IGC file import
- Provide comprehensive flight analysis and visualization
- Enable quick manual flight logging when track logs are unavailable
- Support regulatory compliance through detailed statistics

### 2.2 Key Features Summary

- Automated flight data import from IGC files (track logs)
- Manual flight entry with quick form
- Advanced site management with map integration
- Dual visualization system:
  - 2D OpenStreetMap with comprehensive caching
  - 3D Cesium globe with terrain rendering
- Wing/equipment management with aliases
- Statistical analysis and reporting
- Timezone-aware IGC processing with automatic detection
- Comprehensive map caching (12-month duration)
- Performance monitoring and optimization
- Database management tools

## 3. Functional Requirements

### 3.1 Flight Data Management

#### 3.1.1 Flight Log Display

**Description**: Primary interface showing all logged flights in a tabular format.

**Requirements**:

- FR-1.1: Display flights in a scrollable table with the following columns:
  - Date/Time
  - Site Name
  - Duration
  - Maximum Altitude
  - Maximum Climb Rate
  - Distance (if available)
  - Wing/Equipment
- FR-1.2: Support sorting by any column (ascending/descending)
- FR-1.3: Display most recent flights first by default
- FR-1.4: Show flight count and total hours at bottom of list
- FR-1.5: Provide visual indicator for flights with track logs vs manual entries

#### 3.1.2 Flight Details View

**Description**: Detailed view of individual flight records.

**Requirements**:

- FR-2.1: Display all flight parameters:
  - Launch site and coordinates
  - Landing site and coordinates
  - Launch/Landing times
  - Flight duration
  - Maximum/Average altitude
  - Maximum climb/sink rates
  - Total distance (if track log available)
  - Wing/Equipment used
  - Notes/Comments
- FR-2.2: Show altitude profile chart (if track log available)
- FR-2.3: Display climb rate chart (if track log available)
- FR-2.4: Provide edit capability for all manual fields
- FR-2.5: Include delete flight option with confirmation

#### 3.1.3 Flight Sharing Integration

**Description**: Handle IGC files shared from external applications.

**Requirements**:

- FR-1.6: Accept IGC files shared from other applications
- FR-1.7: Automatically import shared IGC files 
- FR-1.8: Show import preview before adding to flight log
- FR-1.9: Handle multiple file sharing sessions

### 3.2 Flight Data Import

#### 3.2.1 IGC File Import

**Description**: Import flight data from IGC (International Gliding Commission) format files.

**Requirements**:

- FR-3.1: Support single and batch IGC file import
- FR-3.2: Parse IGC files to extract:
  - GPS track points
  - Altitude data (GPS and barometric)
  - Date and time
  - Pilot name (if present)
- FR-3.3: Automatically calculate from track data:
  - Launch/Landing sites and times
  - Flight duration
  - Maximum altitude achieved
  - Maximum climb rate
  - Maximum sink rate
  - Total distance flown
  - Straight-line distance
- FR-3.4: Automatic timezone detection from GPS coordinates
- FR-3.5: Handle midnight crossing flights with date incrementation
- FR-3.6: Perform reverse geocoding to identify site names
- FR-3.7: Detect and prevent duplicate imports
- FR-3.8: Store complete IGC data for later visualization
- FR-3.9: Validate chronological order of timestamps

#### 3.2.2 Parajournal CSV Import

**Description**: Import flight logs from Parajournal application export files.

**Requirements**:

- FR-4.1: Parse Parajournal CSV format
- FR-4.2: Map Parajournal fields to app data model
- FR-4.3: Import flight summary data (no track logs in CSV)
- FR-4.4: Handle date/time format conversion
- FR-4.5: Preserve all available Parajournal data fields

### 3.3 Manual Flight Entry

#### 3.3.1 Quick Entry Form

**Description**: Simplified form for rapid manual flight logging.

**Requirements**:

- FR-5.1: Provide form with fields:
  - Date (default: today)
  - Launch time
  - Landing time (calculate duration)
  - Site (dropdown of known sites + new entry)
  - Wing (dropdown of known wings + new entry)
  - Maximum altitude (optional)
  - Notes (optional)
- FR-5.2: Auto-save site names for future use
- FR-5.3: Auto-save wing/equipment names for future use
- FR-5.4: Validate time entries (landing after launch)
- FR-5.5: Support metric and imperial units based on settings

### 3.4 Flight Visualization

#### 3.4.1 2D Map View

**Description**: Display flight track on interactive map.

**Requirements**:

- FR-6.1: Show flight path on OpenStreetMap (via flutter_map)
- FR-6.2: Animate flight replay with time controls
- FR-6.3: Color-code track by:
  - Altitude
  - Climb rate
  - Time
- FR-6.4: Display launch/landing markers
- FR-6.5: Show current position during replay
- FR-6.6: Include map controls (zoom, pan, map type)

#### 3.4.2 3D Visualization

**Description**: Interactive three-dimensional flight path display using Cesium 3D Globe.

**Requirements**:

- FR-7.1: Real-time 3D flight visualization on Cesium globe
- FR-7.2: Interactive flight replay with temporal controls
- FR-7.3: Terrain-aware flight path rendering
- FR-7.4: Multiple quality modes (Performance/Quality/Ultra)
- FR-7.5: Free provider system (OpenStreetMap, Stamen Terrain)
- FR-7.6: Development mode with quota optimization
- FR-7.7: Performance monitoring and frame rate tracking
- FR-7.8: Altitude-coded flight track visualization

#### 3.4.3 Charts and Graphs

**Description**: Statistical visualization of flight parameters.

**Requirements**:

- FR-8.1: Altitude vs Time chart
- FR-8.2: Climb Rate vs Time chart
- FR-8.3: Synchronized chart interaction
- FR-8.4: Zoom and pan capabilities
- FR-8.5: Display units based on user settings

### 3.5 Site Management

#### 3.5.1 Site Recognition and Editing

**Description**: Comprehensive site management with visual map interface.

**Requirements**:

- FR-9.1: Interactive site editing with OpenStreetMap integration
- FR-9.2: Visual site placement and coordinate adjustment
- FR-9.3: Display nearby flights and existing sites on map
- FR-9.4: Multiple map provider options (OpenStreetMap, satellite imagery)
- FR-9.5: Site bounds visualization for launches in area
- FR-9.6: Automatic site name suggestions from coordinates
- FR-9.7: Manual site coordinate fine-tuning with map interface

#### 3.5.2 Site Database and Management
**Description**: Advanced site database with comprehensive management tools.

**Requirements**:

- FR-10.1: Bulk site import from KML/XML files (popular paragliding sites)
- FR-10.2: Site search and filtering capabilities
- FR-10.3: Site statistics (flight count, total hours)
- FR-10.4: Site merging and duplicate detection
- FR-10.5: Country and region classification
- FR-10.6: Cache management for site data
- FR-10.7: Export site data in various formats

### 3.6 Equipment Management

#### 3.6.1 Wing/Equipment Management

**Description**: Comprehensive wing and equipment management with aliases support.

**Requirements**:

- FR-11.1: Complete wing database with detailed specifications
- FR-11.2: Wing alias system for alternative names/abbreviations
- FR-11.3: Flight and hours tracking per wing
- FR-11.4: Active/retired wing status management
- FR-11.5: Detailed wing specifications (manufacturer, model, size, color)
- FR-11.6: Wing purchase date and notes tracking
- FR-11.7: Automatic wing selection in flight forms
- FR-11.8: Wing usage statistics and reporting

### 3.7 Statistics and Reporting

#### 3.7.1 Flight Statistics

**Description**: Comprehensive flight activity analysis.

**Requirements**:

- FR-12.1: Display total flights and flight hours
- FR-12.2: Show current year statistics
- FR-12.3: Break down by:
  - Site (flights and hours)
  - Wing (flights and hours)
  - Month/Season
  - Flight type (local/XC)
- FR-12.4: Track personal records:
  - Longest flight
  - Highest altitude
  - Best climb rate
  - Longest distance
- FR-12.5: Support date range filtering

#### 3.7.2 Compliance Reporting

**Description**: Reports for license and insurance requirements.

**Requirements**:

- FR-13.1: Generate flight log summary
- FR-13.2: Include unlogged flights/hours option
- FR-13.3: Export reports in PDF/CSV format
- FR-13.4: Customizable date ranges
- FR-13.5: Include pilot information

### 3.8 Data Export

#### 3.8.1 Export Capabilities

**Description**: Export flight data in various formats.

**Requirements**:

- FR-14.1: Export complete database backup
- FR-14.2: Export filtered flight list as CSV
- FR-14.3: Export individual flight as:
  - IGC file (if track available)
  - KML file
  - GPX file
- FR-14.4: Batch export options
- FR-14.5: Email export files

### 3.9 Data Management and Caching

#### 3.9.1 Advanced Caching System

**Description**: Multi-layer caching for optimal performance and offline capability.

**Requirements**:

- FR-16.1: 2D map tile caching with 12-month duration
- FR-16.2: 3D Cesium tile caching with memory management
- FR-16.3: Cache statistics and monitoring
- FR-16.4: Manual cache clearing options
- FR-16.5: Automatic cache size management
- FR-16.6: Human-readable cache size display (KB/MB/GB)
- FR-16.7: Cache persistence across app restarts

#### 3.9.2 Database Management

**Description**: Comprehensive database management and maintenance tools.

**Requirements**:

- FR-17.1: Database statistics display (flights, sites, wings count)
- FR-17.2: Database size monitoring and reporting
- FR-17.3: Performance tracking and optimization
- FR-17.4: Data integrity validation
- FR-17.5: Startup performance monitoring
- FR-17.6: Logging system with multiple levels

### 3.10 Settings and Configuration

#### 3.10.1 User Preferences

**Description**: Configurable application settings.

**Requirements**:

- FR-15.1: Unit preferences:
  - Altitude: meters/feet
  - Distance: km/miles
  - Climb rate: m/s, ft/min, knots
  - Speed: km/h, mph, knots
  - Temperature: °C/°F
- FR-15.2: Pilot information:
  - Name
  - License number
  - Default wing
- FR-15.3: Display preferences:
  - Date format
  - Time format
  - Default map type
- FR-15.4: Calculation settings:
  - Climb rate averaging period
  - Minimum flight duration

#### 3.10.2 Data Management

**Description**: Database maintenance options.

**Requirements**:

- FR-16.1: Backup database locally
- FR-16.2: Restore from backup
- FR-16.3: Clear all data (with confirmation)
- FR-16.4: Database statistics display
- FR-16.5: Automatic backup reminders

## 4. User Interface Requirements

### 4.1 Navigation

- Primary screens accessible via navigation:
  - Flight List (main view with comprehensive flight management)
  - Flight Details (with 2D/3D visualization options)
  - Flight Track 3D (dedicated Cesium globe interface)
  - IGC Import (with preview and batch processing)
  - Statistics (comprehensive flight analytics)
  - Site Management (with interactive map editing)
  - Wing Management (with aliases and detailed tracking)
  - Database Settings (with cache and performance management)
  - About screen (with version and system information)
- Context-sensitive navigation between related screens
- Consistent Material Design navigation patterns

### 4.2 Design Principles

- Mobile-first responsive design
- Support portrait and landscape orientations
- Minimize required user inputs
- Clear visual hierarchy
- Consistent use of icons and colors
- Support for dark/light themes

### 4.3 Performance Requirements

- App startup completes within 2 seconds (1.625s achieved)
- Flight list loads within 2 seconds (460ms achieved)
- Cesium 3D initialization within 500ms (312ms achieved)
- IGC import processes at >1000 points/second
- Smooth map animations at 60fps
- Chart rendering within 1 second
- Map tile caching reduces network requests by 95%
- Memory usage optimized (23MB typical for 3D visualization)

## 5. Data Models

### 5.1 Flight Record
```
{
  id: unique_identifier,
  date: date,
  launchTime: time,
  landingTime: time,
  duration: minutes,
  launchSite: {
    name: string,
    coordinates: {lat, lon},
    altitude: number
  },
  landingSite: {
    name: string,
    coordinates: {lat, lon},
    altitude: number
  },
  maxAltitude: number,
  maxClimbRate: number,
  maxSinkRate: number,
  distance: number,
  wing: string,
  notes: string,
  trackLog: igc_data,
  source: 'manual' | 'igc' | 'parajournal'
}
```

### 5.2 Site Record
```
{
  id: unique_identifier,
  name: string,
  coordinates: {lat, lon},
  altitude: number,
  flightCount: number,
  totalHours: number,
  lastUsed: date,
  customName: boolean
}
```

### 5.3 Wing Record
```
{
  id: unique_identifier,
  name: string,
  manufacturer: string,
  model: string,
  size: string,
  color: string,
  purchaseDate: date,
  flightCount: number,
  totalHours: number,
  active: boolean,
  notes: string
}
```

## 6. Non-Functional Requirements

### 6.1 Platform Support

- Android 5.0+ (API level 21 and above)
- Desktop platforms via sqflite_common_ffi
- Tablet and phone form factors
- ChromeOS support (verified on Chromebox Reference)
- WebView-based 3D visualization compatible with Android WebView

### 6.2 Performance

- Support database of 10,000+ flights (149 flights tested successfully)
- Handle IGC files up to 10MB with timezone processing
- Maintain 60fps UI interactions with optimized rendering
- Comprehensive offline operation:
  - 12-month map tile caching for complete offline maps
  - Local SQLite database with no cloud dependencies
  - Cached 3D terrain data for offline 3D visualization
- Memory-efficient operation (sub-100MB typical usage)

### 6.3 Security

- Local data encryption
- No cloud storage of personal data
- Optional password protection
- Secure file handling

### 6.4 Usability

- Intuitive for non-technical users
- Maximum 3 taps to log a flight
- Clear error messages
- Undo capability for destructive actions

### 6.5 Reliability

- Automatic save of entered data
- Crash recovery
- Data validation
- Backup reminders

## 7. Advanced Features Implemented

### 7.1 Dual Mapping Architecture

- **2D Mapping**: OpenStreetMap integration with flutter_map
  - Multiple tile providers (OpenStreetMap, satellite imagery)
  - 12-month HTTP cache headers (max-age=31536000)
  - 95% bandwidth reduction through comprehensive caching
  - Interactive site editing with visual feedback

- **3D Mapping**: Cesium 3D Globe integration
  - Professional flight visualization with terrain rendering
  - WebView-based implementation with flutter_inappwebview
  - Multiple quality modes (Performance/Quality/Ultra)
  - Free provider fallback system (OpenStreetMap, Stamen Terrain)
  - Development mode with quota optimization
  - Real-time performance monitoring

### 7.2 Performance Optimization System

- **Startup Performance Tracking**: Detailed measurement of initialization phases
- **Cache Management**: Multi-layer caching with statistics and monitoring
- **Memory Optimization**: Efficient data structures and garbage collection
- **GPU Performance**: Adaptive quality scaling based on device capabilities

### 7.3 Advanced IGC Processing

- **Timezone Intelligence**: Automatic timezone detection from GPS coordinates
- **Midnight Crossing Handling**: Seamless date transitions for long flights
- **Data Validation**: Chronological timestamp validation and error detection
- **Sharing Integration**: Direct IGC file import from external applications

## 8. Future Enhancements

(Reserved for planned future features)

## 9. Appendices

### 9.1 Glossary

- **IGC**: International Gliding Commission file format
- **XC**: Cross Country flight
- **Track Log**: GPS breadcrumb trail of flight path
- **Thermal**: Rising air used for gaining altitude
- **Sink Rate**: Rate of altitude loss
- **Wing**: Paraglider/hang glider canopy
- **Cesium**: 3D globe and mapping platform for visualization
- **Tile Caching**: Local storage of map image tiles for offline use
- **LRU**: Least Recently Used cache eviction strategy
- **WebView**: Component for displaying web content within mobile apps
- **OpenStreetMap (OSM)**: Collaborative open-source mapping project
- **flutter_map**: Flutter package for displaying interactive maps

### 9.2 References

- IGC File Format Specification
- OpenStreetMap Tile Server Documentation
- flutter_map Package Documentation
- Cesium 3D Globe API Reference
- Flutter InAppWebView Documentation
- Timezone Database (IANA) Documentation