# Edit Sites Screen: Click and Drag Specification 

## Overview

The Edit Sites screen provides an interactive map interface for managing paragliding sites with comprehensive click and drag functionality. Users can 
- edit a site by clicking on it
- merge sites by one a site markers on top another
  - create new sites by clicking a API site, launch site or   empty areaa

## Site Types

1. **Local Sites** (Blue markers): Sites from the local database with flight history. Uses dragable 
2. **API Sites** (Green markers): External sites from ParaglidingEarth API
3. **Launch Markers** (Small circular markers): Individual flight launch points

## Click Behaviors

### 1. Site Markers
- **Local Sites (Blue)**: Edit site details  
- **API Sites (Green)**: Create a Local site then edit site deatils.

### 2. Launch Markers
- **Action**: Create new site at launch location and edit details 
- **Behavior**: Same as clicking empty area
- **UI**: Shows "Create New Site" dialog with nearby sites and flights summary

### 3. Empty Map Areas
- **Action**: Create new site at clicked coordinates
- **Dialog Contents**:
  - Site creation form with coordinates pre-filled
  - Summary: "X nearby sites, Y flights within 500m"
  - No detailed list of sites/flights (simplified UI)

## Drag Behaviors

### 1. Current Site (Red) → Any Target
- **Valid Targets**: Local Sites (Blue), API Sites (Green)
- **Action**: Merge current site into target
- **Process**:
  1. Move all flights from current site to target site
  2. Delete current site from database
  3. Continue editing the target site (seamless transition)
- **Confirmation Dialog**: "Move X flights from [Current] to [Target]?"

### 2. Local Sites (Blue) → Any Target
- **Valid Targets**: Any other site (Current, Local, or API)
- **Action**: Merge local site into target
- **Process**:
  1. Move all flights from source to target
  2. Delete source site
  3. Refresh map markers
- **Confirmation Dialog**: "Move X flights from [Source] to [Target]?"

### 3. API Sites (Green)
- **Drag Capability**: Not draggable (drop target only)
- **Rationale**: External sites should not be moved, only used as merge targets

## Drag Interaction Details

### Visual Feedback
- **During Drag**: Marker follows cursor with slight offset
- **Drop Zones**: All other sites act as valid drop zones
- **Invalid Operations**: No visual feedback for invalid drops

### Distance Calculation
- **Method**: Haversine formula for geographical accuracy
- **Threshold**: Uses configurable distance tolerance for drop detection
- **Precision**: Handles coordinate precision and floating-point comparisons

### Snap-Back Prevention
- **Issue**: Drag timeout causes marker to return to original position
- **Solution**: Detect snap-back events (movement < 0.1 meter tolerance)
- **Behavior**: Ignore self-merge dialogs from snap-back events

## Merge Process

### Flight Movement
1. **Database Transaction**: Atomic operation to ensure data consistency
2. **Reassignment**: Update `launch_site_id` for all affected flights
3. **Cleanup**: Delete empty source sites after successful transfer
4. **Cache Invalidation**: Clear map data cache to force refresh

### Site Selection Priority
- **Current Site Merge**: Target becomes new current site
- **Local Site Merge**: Standard merge with map refresh
- **API Site Merge**: Convert API site data to local site format

### Error Handling
- **Database Errors**: Rollback transaction, show error message
- **Network Issues**: Graceful degradation with offline functionality
- **Validation**: Prevent self-merge and invalid operations

## User Experience Enhancements

### Tooltip System
- **Format**: Name → Country → X launches
- **Current Site**: Shows actual flight count from database
- **Local Sites**: Shows flight count with real-time updates
- **API Sites**: Shows "0 launches" (external sites have no local flights)
- **Launch Markers**: Shows site name and flight date

### Dialog Simplification
- **Merge Confirmations**: Focus on flight movement, remove deletion warnings
- **Create Site**: Show summary counts without detailed lists
- **Success Messages**: Brief confirmation without technical details

### Navigation Flow
- **Current Site Drag**: User continues editing target site after merge
- **Other Merges**: User remains on current edit screen with refreshed data
- **Site Creation**: User can immediately edit newly created site

## Technical Implementation

### Drag Detection
- **Plugin**: flutter_map_dragmarker v8.0.3
- **Callbacks**: onDragStart, onDragUpdate, onDragEnd
- **Coordinate System**: LatLng with geographical distance calculations

### State Management
- **Local State**: Site lists, flight counts, map bounds
- **Cache Management**: Bounds-based caching with invalidation
- **Real-time Updates**: Immediate UI refresh after operations

### Performance Optimization
- **Debounced Loading**: 500ms debounce for map movement
- **Batch Operations**: Load sites and flights in parallel
- **Selective Refresh**: Only refresh affected map regions

## Edge Cases

### Boundary Conditions
- **Zoom Levels**: Maintain functionality across all zoom levels
- **Map Edges**: Handle dragging near map boundaries
- **Coordinate Precision**: Handle floating-point precision issues

### Data Consistency
- **Concurrent Edits**: Handle multiple edit sessions gracefully
- **Offline Mode**: Queue operations for when connectivity returns
- **Validation**: Ensure site coordinates remain within valid ranges

### User Recovery
- **Undo Support**: Clear operation history on successful merges
- **Error Recovery**: Maintain user context on operation failures
- **Session Management**: Preserve edit state across app lifecycle

## Configuration

### Constants
- **Launch Radius**: 500m for nearby flight detection
- **Marker Sizes**: Current (40px), Sites (36px), Launches (16px)
- **Debounce Timing**: 500ms for map operations
- **Distance Tolerance**: 0.1m for snap-back detection

### Customization Points
- **Map Providers**: OpenStreetMap, Google Satellite switching
- **Site Colors**: Red (current), Blue (local), Green (API)
- **Interaction Modes**: Standard drag, long-press drag options

This specification defines the complete interaction model for the Edit Sites screen, ensuring consistent and intuitive site management workflows.