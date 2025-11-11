# Bidirectional Map-Chart Synchronization

## Overview
Implementation of seamless bidirectional synchronization between Flutter Map and fl_chart altitude visualization in the Flight Track 2D widget.

## Architecture

### Key Components
- **Map Click Detection**: `onTap` callback in FlutterMap MapOptions
- **Chart Touch Handling**: fl_chart's native LineTouchData system
- **State Management**: Single source of truth with selection source tracking

### Core State Variables
```dart
int? _selectedTrackPointIndex;     // Currently selected track point
bool _selectionFromMap = false;    // Tracks whether selection came from map
```

## Implementation Details

### Map → Chart Synchronization
1. **Map Click**: `onTap` finds closest track point using Haversine distance
2. **Tooltip Display**: `showingTooltipIndicators` shows programmatic tooltip
3. **Visual Crosshair**: `showingIndicators` shows native fl_chart crosshair
4. **Touch Handling**: `handleBuiltInTouches: !_selectionFromMap` enables programmatic control

### Chart → Map Synchronization
1. **Chart Hover**: Native `touchCallback` detects chart interaction
2. **Yellow Dot**: Map marker positioned at corresponding GPS coordinates
3. **Flag Reset**: `_selectionFromMap = false` restores normal chart behavior

### Key Technical Solutions

#### Dynamic Touch Control
```dart
handleBuiltInTouches: !_selectionFromMap
```
- Map clicks: Disables built-in touches, enables programmatic tooltips
- Chart hover: Enables built-in touches, allows native interaction

#### Dual Indicator System
```dart
// Tooltip with altitude value
showingTooltipIndicators: [ShowingTooltipIndicators([LineBarSpot(...)])]

// Visual crosshair line and dot
showingIndicators: [_selectedTrackPointIndex]
```

#### Selection Conflict Prevention
```dart
// Only clear selection if it wasn't from map
if (!_selectionFromMap) {
  setState(() => _selectedTrackPointIndex = null);
}
```

## Lessons Learned

### What Didn't Work
- **Manual coordinate calculations**: Alignment drift across chart width
- **Custom overlay widgets**: Fighting with fl_chart's internal layout
- **Single indicator approach**: Missing either tooltip or crosshair

### What Works
- **Native fl_chart APIs**: `showingIndicators` + `showingTooltipIndicators`
- **Dynamic touch control**: Conditional `handleBuiltInTouches`
- **Source tracking**: Prevents touch handler conflicts

## Performance Considerations
- Single `setState()` call for both map and chart updates
- Efficient distance calculation using simplified Haversine formula
- Reusable `LineChartBarData` instance to avoid recreation

## Usage
Click any point on the flight track map to see synchronized crosshair and tooltip on the altitude chart. Hover over the altitude chart to see the yellow tracking dot move along the map.