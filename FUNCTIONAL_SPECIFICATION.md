# Free Flight Log - Functional Specification

## 1. Introduction

### 1.1 Purpose
Free Flight Log is a mobile application designed to simplify flight logging for paraglider, hang glider, and microlight pilots. The app automates data collection from flight computers while providing manual entry options, comprehensive flight analysis, and regulatory compliance reporting.

### 1.2 Scope
This document defines the functional requirements for the Free Flight Log mobile application, including all user-facing features, data management capabilities, and integration requirements.

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
- Manual flight entry
- Site recognition and naming
- Flight visualization (2D/3D)
- Statistical analysis and reporting
- Data import/export capabilities
- import track logs from xctrack

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
- FR-3.4: Perform reverse geocoding to identify site names
- FR-3.5: Detect and prevent duplicate imports
- FR-3.6: Store complete IGC data for later visualization

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

- FR-6.1: Show flight path on Google Maps
- FR-6.2: Animate flight replay with time controls
- FR-6.3: Color-code track by:
  - Altitude
  - Climb rate
  - Time
- FR-6.4: Display launch/landing markers
- FR-6.5: Show current position during replay
- FR-6.6: Include map controls (zoom, pan, map type)

#### 3.4.2 3D Visualization

**Description**: Three-dimensional flight path display.

**Requirements**:

- FR-7.1: Export to Google Earth KML format
- FR-7.2: Include altitude exaggeration option
- FR-7.3: Embed flight statistics in KML
- FR-7.4: Support track color coding

#### 3.4.3 Charts and Graphs

**Description**: Statistical visualization of flight parameters.

**Requirements**:

- FR-8.1: Altitude vs Time chart
- FR-8.2: Climb Rate vs Time chart
- FR-8.3: Synchronized chart interaction
- FR-8.4: Zoom and pan capabilities
- FR-8.5: Display units based on user settings

### 3.5 Site Management

#### 3.5.1 Site Recognition

**Description**: Automatic identification and naming of flying sites.

**Requirements**:

- FR-9.1: Reverse geocode launch coordinates
- FR-9.2: Learn custom site names from user
- FR-9.3: Apply learned names to future flights at same location
- FR-9.4: Define site radius for matching (e.g., 500m)
- FR-9.5: Allow manual site name override

#### 3.5.2 Site Database
**Description**: Maintain database of known flying sites.

**Requirements**:

- FR-10.1: Store site name and coordinates
- FR-10.2: Track flight count per site
- FR-10.3: Calculate total hours per site
- FR-10.4: Allow site editing and merging
- FR-10.5: Support site deletion (update associated flights)

### 3.6 Equipment Management

#### 3.6.1 Wing/Equipment Tracking

**Description**: Manage pilot's equipment inventory.

**Requirements**:

- FR-11.1: Maintain list of wings/equipment
- FR-11.2: Track flights per wing
- FR-11.3: Calculate hours per wing
- FR-11.4: Set active/retired status
- FR-11.5: Support equipment notes (size, color, etc.)

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

### 3.9 Settings and Configuration

#### 3.9.1 User Preferences

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

#### 3.9.2 Data Management

**Description**: Database maintenance options.

**Requirements**:

- FR-16.1: Backup database locally
- FR-16.2: Restore from backup
- FR-16.3: Clear all data (with confirmation)
- FR-16.4: Database statistics display
- FR-16.5: Automatic backup reminders

## 4. User Interface Requirements

### 4.1 Navigation

- Tab-based navigation with icons:
  - Flight Log (main view)
  - Statistics
  - Sites
  - Wings
  - Settings
- Hamburger menu for import/export functions
- Consistent back navigation

### 4.2 Design Principles

- Mobile-first responsive design
- Support portrait and landscape orientations
- Minimize required user inputs
- Clear visual hierarchy
- Consistent use of icons and colors
- Support for dark/light themes

### 4.3 Performance Requirements

- Flight list loads within 2 seconds
- IGC import processes at >1000 points/second
- Smooth map animations at 30fps
- Charts render within 1 second

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

- Android 15 and above
- Tablet and phone form factors

### 6.2 Performance

- Support database of 10,000+ flights
- Handle IGC files up to 10MB
- Maintain 60fps UI interactions
- Offline operation (no internet required except for maps)

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

## 7. Future Enhancements

## 8. Appendices

### 8.1 Glossary

- **IGC**: International Gliding Commission file format
- **XC**: Cross Country flight
- **Track Log**: GPS breadcrumb trail of flight path
- **Thermal**: Rising air used for gaining altitude
- **Sink Rate**: Rate of altitude loss
- **Wing**: Paraglider/hang glider canopy

### 8.2 References

- IGC File Format Specification
- Parajournal CSV Format
- Google Maps API Documentation
- KML Reference Documentation