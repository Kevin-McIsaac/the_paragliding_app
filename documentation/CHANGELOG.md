# Changelog

This document contains a complete history of major updates and feature implementations for the Free Flight Log project.

## August 2025 - Shared Flight Track Widget & Code Duplication Elimination
- **FlightTrackWidget Implementation**: Created shared widget to eliminate code duplication between embedded and full-screen flight track views
  - **Unified Codebase**: Single widget handles both FlightDetailScreen embedded cards and FlightTrackScreen full-screen view
  - **Configuration Pattern**: FlightTrackConfig class provides three display modes: `embedded()`, `embeddedWithControls()`, and `fullScreen()`
  - **Consistent Features**: Both views now show identical functionality including FAB controls, statistics header, and climb rate visualization
  - **No Functionality Drift**: Shared implementation prevents features from becoming inconsistent between views
- **RenderFlex Constraint Fix**: Resolved unbounded height constraint errors in scrollable contexts
  - **Embedded Mode**: Always provides bounded height via SizedBox with fallback to 350px
  - **Loading/Error States**: Fixed constraint handling using SizedBox.expand for full-screen and proper height for embedded
  - **Flexible Layout**: Replaced Expanded with Flexible in full-screen mode for better constraint compatibility
  - **mainAxisSize.min**: Used throughout for optimal sizing behavior in scrollable containers
- **Enhanced Display Configurations**:
  - **embedded()**: Height 250px, minimal features for compact display
  - **embeddedWithControls()**: Height 350px, full features including stats bar, FAB menu, and legend
  - **fullScreen()**: No height constraint, optimized for dedicated screen real estate
- **Code Architecture Improvements**:
  - **Statistics Logic Migration**: Moved all flight statistics calculations from FlightTrackScreen to shared widget
  - **State Management**: Proper handling of map preferences and display options across configurations
  - **Widget Composition**: Clean separation of concerns with configuration-driven feature toggling

## August 2025 - Enhanced Flight Track Visualization & User Experience
- **Climb Rate Color Visualization**: Redesigned flight track display to use climb rate colors instead of altitude
  - **Green**: Climb rates ≥ 0 m/s (thermals/lift areas)
  - **Royal Blue**: Weak sink rates -1.5 to 0 m/s (neutral air)
  - **Red**: Strong sink rates ≤ -1.5 m/s (heavy sink areas)
  - **15-Second Averaging**: Uses smoothed climb rate data for realistic thermal analysis
- **Interactive Color Legend**: Added bottom-left legend showing climb rate color scheme and thresholds
- **Professional Crosshairs**: Replaced circular selected point marker with precision crosshairs
  - **Minimal Design**: Clean black lines with white outline for visibility
  - **Center Gap**: 50% center gap for unobstructed view of selected track point
  - **Precision Targeting**: Professional scope-like appearance for accurate point selection
- **Enhanced FAB Menu**: Improved floating action button controls
  - **Distance Line**: Renamed "Straight Line" to "Distance" with gray dotted line
  - **Persistent Settings**: FAB menu states remembered across app sessions using SharedPreferences
  - **Proper Toggle**: Distance label marker now correctly shows/hides with distance line
- **Visual Improvements**: 
  - **Removed Altitude Submenu**: Streamlined interface by removing unused altitude color options
  - **Gray Distance Line**: Changed from orange to gray for better visual hierarchy
  - **Consistent Styling**: All map overlays use coordinated color scheme

## January 2025 - Advanced Site Management and Performance Optimization
- **Hybrid Site Lookup System**: Optimized site matching with intelligent multi-tier approach
  - **Flight Log Priority**: Searches user's existing 22 sites first (~2ms, 250x faster for known sites)
  - **API Enhancement**: Enhances local sites missing country data with ParaglidingEarth API
  - **Progressive Data**: Old sites get enhanced with country information over time
  - **Smart Fallback**: API lookup for completely new sites with full country data
- **Country-Based Site Organization**: Streamlined location system using actual API data
  - **ParaglidingEarth API Integration**: Fixed to use `countryCode` field with ISO-to-name mapping
  - **Country-Only Structure**: Removed state/region fields (API doesn't provide reliable data)
  - **Database Migration v6**: Cleaned up schema to remove unused state column
  - **Country Mapping**: Comprehensive ISO 3166-1 country code to full name conversion
- **Enhanced Site Selection Dialog**: Major UX improvements for site management
  - **Country Organization**: Sites grouped by country with clear headers
  - **Search Enhancement**: Search by site names and countries simultaneously  
  - **Visual Hierarchy**: Country headers with indented sites for easy navigation
  - **Smart Sorting**: Countries alphabetical, "Unknown Country" at end
  - **Dialog Cancellation Fix**: Cancel button now properly preserves current selection
- **Site Migration Tools**: Automated country data population
  - **Migration Service**: Updates existing sites with country information from API
  - **Database Settings**: "Update Site Country Info" button for one-click migration
  - **Progress Tracking**: Detailed migration results with success/skip/error counts
  - **Batch Processing**: Handles large site collections with rate limiting
- **Timezone Caching Implementation**: Eliminated duplicate timezone detection messages during IGC import
  - **Coordinate-Based Caching**: Uses GPS coordinates as cache key to prevent duplicate detections
  - **Performance Improvement**: Caches timezone results per coordinate location for faster subsequent imports
  - **Clean Debug Output**: Only prints timezone detection message on first occurrence
- **Comprehensive Site Management**: Added full site management functionality
  - **ManageSitesScreen**: Complete interface for viewing, editing, and managing flight sites
  - **Search and Filter**: Real-time site search with instant filtering capabilities
  - **Edit Sites**: Full form validation for coordinates, altitude, and site names
  - **Delete Protection**: Sites used in flights cannot be deleted (safety feature)
  - **Site Statistics**: Shows usage counts and comprehensive site information
- **Improved Navigation Structure**: Reorganized menu system for better user experience
  - **Main Menu Integration**: Moved site management to main menu under "Manage Wings"
  - **Import/Refresh in Menu**: Moved Import IGC and Refresh buttons from app bar to main menu
  - **Cleaner App Bar**: Reduced clutter in app bar, focusing on essential selection actions
  - **Logical Grouping**: Actions (Import/Refresh) at top, then management features, then settings

## January 2025 - GPS-Based Timezone Detection
- **GPS Coordinate Timezone Detection**: System now always uses launch GPS coordinates to determine timezone
  - **HFTZNUTCOFFSET Override**: Intentionally ignores timezone headers in IGC files
  - **Location-Based Accuracy**: Ensures times reflect actual flight location timezone
  - **Automatic Detection**: Maps GPS coordinates to nearest timezone region
  - **Fallback Logic**: Uses longitude-based estimation for remote locations
- **B Record UTC Handling**: Correctly treats B records as UTC time per IGC specification
  - **Fixed Time Conversion**: B records parsed as UTC, then converted to local time
  - **Proper UTC to Local**: Changed from incorrect local-to-UTC to correct UTC-to-local conversion
  - **Standards Compliance**: Aligns with official IGC file format specification
- **Timezone Service Implementation**: New service for coordinate-to-timezone mapping
  - **Major Cities Database**: Covers global timezone regions with radius-based matching
  - **Timezone Offset Conversion**: Converts timezone IDs to offset strings (e.g., "Europe/Zurich" → "+02:00")
  - **Seasonal Awareness**: Handles daylight saving time based on flight date
- **Enhanced Reliability**: GPS-based detection eliminates unreliable manual timezone settings
  - **Console Logging**: Reports when overriding file timezone with GPS-detected timezone
  - **Test Coverage**: Comprehensive tests for timezone detection and UTC conversion

## August 2025 - Timezone Support & Enhanced Flight Analysis
- **Comprehensive Timezone Support**: Full implementation of timezone handling for IGC imports
  - **HFTZNUTCOFFSET Parsing**: Extracts timezone information from IGC headers (e.g., "+10.00h" → "+10:00")
  - **Timezone-Aware Timestamps**: All track points converted to proper timezone-aware DateTime objects
  - **Database Schema**: Added timezone field to flights table with v3 migration
  - **Display Enhancement**: Times shown with timezone indicators (e.g., "14:30 +10:00") for imported flights
  - **International Support**: Accurate time representation for flights logged in different timezones
- **Enhanced Flight List Table**: Comprehensive flight analysis at a glance
  - **Track Distance Column**: Added ground track distance column showing actual flight path distance
  - **Distance Distinction**: Clear separation between track distance (flight path) and straight distance (direct line)
  - **Sortable Columns**: All distance metrics sortable for performance analysis
  - **Professional Layout**: 5-column table with Launch Date/Time, Duration, Track Distance, Straight Distance, Max Altitude
- **Midnight Crossing Fix**: Automatic detection and correction of negative durations
  - **Smart Duration Calculation**: Detects when landing time appears before launch time
  - **24-Hour Adjustment**: Automatically adds 24 hours for flights crossing midnight
  - **Test Coverage**: Comprehensive unit tests for edge cases and midnight scenarios
- **IGC Source Traceability**: Display of source IGC file path in flight notes for full traceability

## August 2025 - Inline Editing Implementation
- **Complete Inline Editing**: Implemented comprehensive inline editing for all flight details
- **Notes Editing**: Click-to-edit notes with TextFormField, save/cancel buttons, and empty state handling
- **Flight Details Editing**: Tap-to-edit functionality for all fields:
  - **Date**: Tap date → DatePicker dialog
  - **Times**: Tap launch/landing times → TimePicker dialogs with auto-duration calculation
  - **Sites**: Tap site names → Site selection dialogs with radio button interface
  - **Equipment**: Tap wing name → Wing selection dialog
- **Visual Indicators**: Underlined editable fields with theme colors for clear interaction cues
- **Simplified Interface**: Removed separate EditFlightScreen and edit button for streamlined UX
- **Error Handling**: Comprehensive try-catch with user feedback via SnackBar messages
- **State Management**: Proper loading states and optimistic UI updates
- **Data Integrity**: All existing flight data preserved during inline updates

## August 2025 - IGC Import Enhancements & Flight Track Visualization
- **HFDTE Parsing Correction**: Fixed IGC date parsing from incorrect YYMMDD to correct DDMMYY format
- **Date Accuracy**: Ensures flight dates are parsed correctly from IGC file headers
- **Duplicate Detection**: Added comprehensive duplicate flight detection during IGC import
- **User Choice Options**: Implemented Skip/Skip All/Replace/Replace All options for duplicate handling
- **Enhanced Results**: Detailed import results showing imported, replaced, skipped, and failed files
- **Straight Line Visualization**: Added straight-line distance overlay on both OpenStreetMap and Canvas flight track views
- **Distance Labels**: Straight distance displayed directly on the visualization line (marker for Maps, text overlay for Canvas)
- **Enhanced Statistics**: Shows track distance and straight distance (removed efficiency calculation)
- **Interactive Controls**: Toggle visibility of straight line via popup menu in both map and canvas views
- **Consistent Experience**: Both map and canvas views now offer identical functionality and visual design
- **Parser Update**: Updated `IgcParser._parseDate()` method with correct format interpretation

## August 2025 - Cross-Platform Map Migration
- **OpenStreetMap Migration**: Migrated from Google Maps to flutter_map with OpenStreetMap for full cross-platform compatibility
- **Linux Desktop Support**: Flight track visualization now works natively on Linux desktop without dependencies
- **Maintained Functionality**: All existing map features preserved including straight-line distance visualization
- **Enhanced Compatibility**: Single codebase now supports maps on all platforms (Linux, Android, iOS, macOS, Windows)

## December 2024 - Enhanced Climb Rate Analysis
- **15-Second Averaging**: Upgraded from 5-second to 15-second climb rate calculations for more stable readings
- **Dual Rate Display**: Shows both instantaneous and 15-second averaged climb/sink rates
- **Database Migration**: Added support for new climb rate fields with automatic migration
- **UI Improvements**: Enhanced flight statistics display with consolidated climb rate information
- **Test Coverage**: Added comprehensive unit tests for climb rate calculations
- **Folder Memory**: IGC import now remembers last used folder for improved workflow

## January 2025 - Landing Sites Redesign & Site Management
- **Landing Sites Conceptual Redesign**: Separated launch sites (named, reusable) from landing locations (coordinates)
  - **Database v4 Migration**: Added landing coordinate columns (latitude, longitude, altitude, description)
  - **Removed landing_site_id**: Landing locations no longer stored as "sites"
  - **Flight Model Update**: Uses direct landing coordinates instead of site references
  - **IGC Import Optimization**: No longer creates landing "sites" or queries API for landing locations
  - **UI Improvements**: Landing locations show coordinates with optional custom descriptions
  - **Site Management Cleanup**: "Manage Sites" now only shows launch sites (much cleaner)
- **Launch Site Handling**: 
  - **Unknown Site Fallback**: Launch sites without matches now use "Unknown" instead of coordinate strings
  - **ParaglidingEarth API**: Continues to work for launch site identification only
  - **Personalized Fallback**: Uses sites from user's flight log when API unavailable
- **Fixed SQL Errors**: Updated all queries to remove references to removed landing_site_id column
  - `getSitesUsedInFlights()`: Now only queries launch sites
  - `canDeleteSite()`: Only checks launch site usage
  - `getFlightsBySite()`: Returns flights launched from site
- **ParaglidingEarth API Notes**:
  - **No Rate Limiting Handler**: Current implementation lacks explicit rate limit handling
  - **24-Hour Cache**: Reduces API calls significantly
  - **Launch Sites Only**: API no longer queried for landing locations (performance improvement)

## Key Files Updated
- `lib/presentation/widgets/flight_track_widget.dart`: Shared flight track widget with configuration-driven display modes (NEW)
- `lib/presentation/screens/flight_track_screen.dart`: Simplified to use shared FlightTrackWidget with fullScreen() config
- `lib/presentation/screens/flight_detail_screen.dart`: Updated to use FlightTrackWidget with embeddedWithControls() config, eliminating code duplication
- `lib/presentation/screens/flight_track_screen.dart`: Major flight track visualization overhaul with climb rate colors, crosshairs, and persistent FAB settings
- `lib/presentation/screens/flight_track_canvas_screen.dart`: Updated canvas view to match new color scheme (altitude to royal blue)
- `lib/data/models/flight.dart`: Added timezone field and midnight crossing duration logic
- `lib/data/models/igc_file.dart`: Enhanced with timezone support and smart duration calculation
- `lib/data/datasources/database_helper.dart`: Database v3 migration for timezone column
- `lib/services/igc_parser.dart`: GPS-based timezone detection, B record UTC handling, HFTZNUTCOFFSET override
- `lib/services/timezone_service.dart`: GPS coordinate to timezone mapping service (NEW)
- `lib/services/igc_import_service.dart`: Timezone preservation during IGC import
- `lib/data/repositories/flight_repository.dart`: Timezone field support and migration handling
- `lib/presentation/screens/flight_detail_screen.dart`: Timezone-aware time display and IGC source info
- `lib/presentation/screens/flight_list_screen.dart`: Enhanced table with track distance column and timezone display
- `lib/presentation/screens/edit_flight_screen.dart`: Timezone field preservation during edits
- `lib/presentation/screens/add_flight_screen.dart`: Explicit null timezone for manual flights
- `lib/main.dart`: Timezone database initialization on app startup
- `test/midnight_crossing_test.dart`: Comprehensive unit tests for midnight crossing scenarios (NEW)
- `test/timezone_test.dart`: Tests for GPS-based timezone detection and UTC conversion (NEW)
- `lib/presentation/widgets/duplicate_flight_dialog.dart`: User choice dialog for duplicates
- `lib/presentation/screens/flight_track_screen.dart`: Added straight line visualization and enhanced statistics
- `lib/presentation/screens/flight_track_canvas_screen.dart`: Added matching straight line visualization for canvas view