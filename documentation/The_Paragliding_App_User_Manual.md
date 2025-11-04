# The Paragliding App User Manual

## Getting Started (5 minutes)

### What You'll Learn

Import your first flight and understand the main screen in under 5 minutes.

### Your First Import

1. Open the app and tap the **menu button** (⋮) in the top-right corner
2. Select **Import IGC** from the dropdown menu
3. Tap **Select IGC Files** and browse to your IGC file from your vario, XCTrack, or cloud storage
4. Select your files and the button will change to show **Import X Flight(s)**. You can select as many files as you like and they will all be imported.
5. Tap the import button and wait for processing - for each flight the app automatically
   1. Detects the local timezone.
   2. Apply the name of the launch site if the take off is withing 500m of a known site.
6. Review the import results and tap **Done** to complete the import and return to your flight list

### Understanding the App Navigation

The app has four main sections accessible via the **bottom navigation bar**:

1. **Flight Log** - Your complete flight history and logbook
2. **Nearby Sites** - Interactive map showing flying sites, airspace, and weather
3. **Forecast** - Multi-site weather forecast comparison
4. **Statistics** - Flight summaries by year, wing, and site

The app remembers which tab you last viewed and returns to it when you reopen the app.

### Understanding the Flight Log Screen

The Flight Log screen shows all your flights with:

- **Menu button** (⋮) in top-right provides access to all the app features
- **Total flights** and **flight hours** displayed at the top of the list. You can use the **Select Flights** menu item to limit this to a subset of flights.
- **Sortable table** with columns: Launch Site, Launch Date & Time, Duration, Track Dist (km), Straight Dist (km), Max Alt (m)
- **Tap any flight** to see the flight statistics, watch a 3D replay or correct flight details
- **Add flight button** (+) floating button for manual flight entry

### Main Menu Structure

The **menu button (⋮)** in the top-right corner provides access to:

- **Statistics** - View flight summaries and totals by year, wing or site
- **Manage Sites** - Edit launch locations
- **Manage Wings** - Track your equipment
- **Import IGC** - Import flight files
- **Select Flights** - Bulk operations like delete
- **Preferences** - Configure app settings for 3D visualization, detection thresholds, and wind limits
- **Database Settings** - Data backup and maintenance. Be careful!
- **About** - App information

---

## Daily Use

### Import Flights from Your Vario

How to import IGC files from any source and handle duplicates efficiently.

#### Steps

Before you start check that your vario or cloud storage is connected to your device 
and can be accessed in the file manager. These will usually show up as a device or volume. 

1. Tap **menu (⋮)** → **Import IGC**
2. Tap **Select IGC Files** and browse to your IGC files
3. Select multiple files if needed (shows "and X more files..." for batches)
4. Tap **Import X Flights** to start processing
5. Monitor progress as each file is processed

#### What the App Does Automatically

✓ Detects timezone from GPS coordinates  
✓ Names launch sites using ParaglidingEarth database  
✓ Calculates comprehensive flight statistics (distance, duration, climb rates)  
✓ Prevents duplicate imports with the same start date 
✓ Shows processing status for each file

#### Handling Duplicates

When the app detects a duplicate flight:

**Duplicate Flight Found** dialog appears with options:

- **Skip**: Ignores the duplicate file
- **Skip All**: Ignores all remaining duplicates in this batch  
- **Replace**: Updates existing flight with new IGC data
- **Replace All**: Replaces all duplicates found in this batch

The dialog shows comparison details between your existing flight and the new IGC file to help you decide.

### Fix Unknown Launch Sites

When you load a flight the app will assign it to the nearest
known lanuch site withing a 500m radius. It first checks sites already
in your log book and if nothing matches it checks Paragliding Earth. 
If there are no matches, it creates a new launch site in your log 
and gives it a unique name, i.e., "Unknown 9"

#### Scenario 1: New Site
This happens when the launch is not from a site allready in the log book or PGE

**Problem:** Your launch site appears as "Unknown N" 

**Solution:**

1. Open **Manage Sites** from the home screen menu
2. Tap the launch site, e.g, "Unknown 9"
3. View the flight (red dot) on the map.
4. If this is the correct location for the launch 
   1. enter the **Site Name** and **Country** 
   2. Tap **Save**
5. Otherwise click on the correct location in the map a dialogue will appear 
   1. Enter the  **Site Name** and **Country**
   2. Tap **Save**

**Result:** Future flights from nearby GPS coordinates (within 500m) will automatically
be assigned to this site.

#### Scenario 2: GPS Started After Launch

If you start the GPS after takeoff you flight will have the wrong launch site

**Problem:** Your launch site appears as "Unknown N" 

**Solution:**

1. Open **Manage Sites** from the home screen menu
2. Tap the launch site, e.g., "Unknown 9"
3. The app will show nearby launch sites.
4. Zoom in or out to see more sites.
5. Select the correct launch site.
6. Tap **Save** to confirm

**Result:** The flight is reassigned to the selected site.

### Track Your Equipment

#### Edit Wing Names

**Why:** Standardise equipment names for accurate statistics and easier searching

**Steps:**

1. Tap **menu (⋮)** → **Manage Wings**
2. Find your wing and tap the **popup menu (⋮)** next to it
3. Select **Edit** from the menu
4. Update the **Manufacturer**, **Model**, **Size**, or **Notes**
5. Tap **Save**

**Example:** Change "omega" to "Advance Omega X-Alps 2" for clearer identification.

#### Merge Duplicate Wings

**Why:** Combine statistics when you have multiple entries for the same wing

**Steps:**

1. Tap **menu (⋮)** → **Manage Wings**
2. Tap **Select Wings to Merge** in the top bar
3. Select the wings you want to combine using the checkboxes
4. Tap **Merge Wings** at the top
5. Choose which wing name to keep as the primary
6. Tap **Merge** to confirm

**Result:** All flights transfer to the kept wing, and the duplicate entries are removed.

---

## Nearby Sites and Weather

### Explore Flying Sites on the Map

#### What You'll Learn

Use the interactive map to discover flying sites, check airspace restrictions, view weather forecasts, and find nearby weather stations.

#### Opening Nearby Sites

1. Tap the **Nearby Sites** tab in the bottom navigation bar
2. The map loads showing your current location (if location permission granted)
3. Flying sites appear as markers on the map
4. Pan and zoom to explore different regions

#### Understanding Site Markers

Site markers use different colours and icons:

- **Blue markers with star** - Sites you've flown from (in your logbook)
- **Orange markers** - Sites from ParaglidingEarth database you haven't flown yet
- **Wind icons on markers** - Current/forecast wind direction and speed when forecasts are enabled

**Tap any site marker** to open a detailed popup with:
- Site name, country, altitude, and coordinates
- Distance and bearing from your location
- Link to ParaglidingEarth page
- Current weather forecast with flyability assessment
- Week summary forecast table

#### Managing Favorite Sites

Mark sites you fly regularly as favorites for quick access:

1. Tap a site marker to open its details
2. Tap the **star icon** in the top-right to add to favorites
3. The star turns solid when the site is a favorite
4. Access your favorites in the **Forecast** tab

**Benefits:**
- Quick access to weather for your regular sites
- Filter forecast view to show only favorites
- Favorites persist across app restarts

### View Weather and Airspace

#### Enabling Map Overlays

The map supports multiple overlay types. Tap the **filter icon** (funnel) in the top-right to toggle:

**Sites Overlay** (on by default)
- Shows flying site markers from your logbook and ParaglidingEarth
- Blue markers = sites you've flown, orange = new sites

**Airspace Overlay**
- Displays controlled airspace polygons from OpenAIP
- Different colours for airspace types: controlled zones (red), restricted areas (orange), danger zones, etc.
- Helps plan flights to avoid restricted airspace
- Tap airspace polygons to see details (name, type, altitude limits)

**Forecast Overlay**
- Adds wind direction/speed icons to site markers
- Shows flyability status with colour coding:
  - **Green** = Good conditions for flying
  - **Orange** = Caution - marginal conditions
  - **Red** = Unsafe - do not fly
- Updates automatically based on current time

**Weather Stations Overlay**
- Shows nearby weather stations with real-time observations
- Different icons for station types: BOM, METAR, PGE stations
- Tap stations to see current wind, temperature, and conditions
- Useful for checking actual conditions vs forecasts

#### Changing Map Providers

1. Tap the **map settings icon** (three layers) in the top-right
2. Select from available map providers:
   - **OpenStreetMap** - Free topographic maps
   - **Google Satellite** - Aerial imagery
   - **Google Hybrid** - Satellite with labels
   - Other providers as configured
3. The map reloads with your selected provider
4. Your choice is saved for future sessions

#### Understanding Flyability Status

The app calculates flyability based on wind conditions:

**Green (Good):**
- Wind speed below caution threshold (default: 20 km/h)
- Safe flying conditions expected

**Orange (Caution):**
- Wind speed between caution and maximum thresholds (default: 20-25 km/h)
- Marginal conditions - exercise caution and assess local conditions
- May be suitable for experienced pilots or specific sites

**Red (Unsafe):**
- Wind speed above maximum threshold (default: 25 km/h)
- OR precipitation present (rain/snow)
- Do not fly

⚠️ **Important:** Flyability thresholds can be customized in **Preferences** → **Wind Thresholds**. Always use your judgment and check local conditions before flying.

---

## Weather Forecasts

### Compare Multi-Site Forecasts

#### What You'll Learn

View week-long weather forecasts for multiple flying sites simultaneously to plan your flying week.

#### Opening the Forecast Screen

1. Tap the **Forecast** tab in the bottom navigation bar
2. The screen shows a week summary table with multiple sites
3. Each row represents one flying site
4. Each column represents one day of the week

#### Understanding the Forecast Table

The week summary table uses colour coding for flyability:

**Table Layout:**
- **Rows** - Flying sites (up to 50 sites)
- **Columns** - Days of the week with dates
- **Cells** - Coloured boxes indicating flyability for that site/day
  - **Green** = Good flying conditions
  - **Orange** = Caution - marginal conditions
  - **Red** = Unsafe - strong winds or precipitation
  - **Grey** = No forecast data available

**Tap any cell** to see detailed hourly forecast for that site and day.

#### Selecting Sites for Forecast

The app offers three modes for site selection (use the tabs at the top):

**Favorites Mode:**
1. Shows only sites you've marked as favorites
2. Quick access to your regular flying sites
3. Empty if you haven't favorited any sites yet
4. Add favorites by tapping stars on site markers in the Nearby Sites screen

**Near Here Mode:**
1. Shows sites near your current GPS location
2. Requires location permission
3. Adjust distance filter: 10km, 50km, or 100km radius
4. Adjust site limit: 10, 20, or 50 sites
5. Sorted by distance from your location

**Near Site Mode:**
1. Shows sites near a selected reference site
2. Tap the search box and type a site name
3. Select the reference site from search results
4. Adjust distance and site limit filters
5. Useful for planning trips to flying regions

#### Adjusting Forecast Filters

**Distance Filter:**
1. Tap the distance dropdown (10 km / 50 km / 100 km)
2. Select your desired radius
3. The forecast table refreshes with sites within that distance

**Site Limit Filter:**
1. Tap the site count dropdown (10 sites / 20 sites / 50 sites)
2. Select how many sites to display
3. More sites = more scrolling, but better overview of region

**Settings are saved** and persist across app restarts.

#### Understanding Multi-Model Forecasts

The app can fetch forecasts from multiple weather models:

- **Open-Meteo** - Primary free forecast provider
- **Additional models** - May be available depending on configuration

When multiple models are available:
- The app displays the model being used
- Tap the forecast attribution bar at bottom to see details
- Different models may show different predictions - use your judgment

#### Refreshing Forecast Data

Forecasts are automatically loaded when you open the screen.

To manually refresh:
1. Pull down on the forecast table (pull-to-refresh gesture)
2. The app fetches the latest forecast data
3. Loading indicators show which data sources are being queried

⚠️ **Note:** Forecast data requires internet connection. The app caches forecasts briefly to minimize API calls.

---

### View Flight Statistics

#### What You'll Learn

Access comprehensive statistics about your flying including yearly totals, wing usage, and site summaries.

#### Steps

1. Tap **menu (⋮)** → **Statistics**
2. Review the three main sections:
   - **Flights by Year**: Annual flight counts and total hours
   - **Flights by Wing**: Usage statistics for each piece of equipment
   - **Flights by Site**: Launch locations grouped by country
3. Tap any **site name** (underlined) to edit location details
4. View totals at the bottom of each section

#### Understanding the Statistics

- **Active wings** are shown first, followed by inactive equipment
- **Sites are grouped by country** with flight counts
- **Yearly statistics** help track progress and currency requirements
- **Total rows** provide overall summaries

### Replay Flights in 3D

#### What You'll Learn

Use the interactive 3D viewer to analyse flight performance and relive your flying experiences.

#### Opening 3D View

1. Tap any **flight** from your main flight list
2. Scroll down to the **Flight Track** section in flight details
3. The interactive 3D map loads automatically showing terrain and flight track
4. The track appears as a coloured line showing altitude and climb rate

#### 3D Navigation

- **Zoom**: Pinch gesture or mouse wheel
- **Pan**: Single finger drag to move around
- **Tilt**: Two-finger drag or right-click drag to change viewing angle
- **Reset view**: Tap the **home icon** to return to default view

#### Flight Replay Controls

- **Play/Pause button**: Start or stop animated flight replay
- **Speed controls**: Adjust replay speed from 1x to 16x
- **Progress slider**: Jump to any point in the flight
- **Follow mode**: Tap **camera icon** to have the view follow the pilot automatically
- **Full screen**: Tap **expand icon** for immersive viewing

#### Map and Scene Options

**Change Map Provider:**

- Tap the **map provider dropdown** in the top-right
- Choose from the avaialble maps. 


**Understanding Track Colours:**

- Track colour represents altitude or climb rate
- Green = climing, i.e., climb rate > 0
- Blue = glide, ie.., climb rate between 0 and -1.5ms
- Red = sink, i.e., climb rate < -1.5ms

---

## Managing Your Data

### Organise Site Information

#### View All Sites

1. Tap **menu (⋮)** → **Manage Sites**
2. Use the **search bar** to find specific sites: "Search sites by name or country..."
3. Change sorting with the **dropdown menu**:
   - **Group by Country** (default) - shows country headers
   - **Sort by Name** - alphabetical order
   - **Sort by Date Added** - newest first
4. Each site shows coordinates, altitude, country, and **flight count badge**

#### Edit Site Details

1. Find the site in **Manage Sites** list
2. Tap the **popup menu (⋮)** next to the site
3. Select **Edit** from the menu
4. Modify any field: **Site Name**, **Latitude**, **Longitude**, **Altitude (metres)**, **Country**
5. Use the **interactive map** to visually confirm or adjust coordinates
6. Tap **Save** to apply changes

⚠️ **Important:** Changes affect all flights associated with this location.

### Configure App Preferences

#### What You'll Learn

Customize app behavior for 3D visualization, flight detection, and weather thresholds.

#### Opening Preferences

1. Tap **menu (⋮)** → **Preferences**
2. The preferences screen shows three expandable sections
3. Tap any section header to expand or collapse it

#### 3D Visualization Settings

Configure how flight replays appear in 3D view:

**Scene Mode:**
- **3D** (default) - Full 3D globe with perspective
- **Columbus** - 2.5D view (flat map with 3D terrain)
- **2D** - Flat map view (fastest performance)

**Base Map:**
- **Satellite** (default) - Aerial imagery
- **OpenStreetMap** - Street map with terrain
- **Hybrid** - Satellite with labels

**Terrain:**
- **Enabled** (default) - Show 3D terrain elevation
- **Disabled** - Flat surface (faster on older devices)

**Trail Duration:**
- **60 seconds** (default) - How long the flight trail stays visible behind the glider
- Options: 30s, 60s, 120s, 300s

**Quality:**
- **1.0** (default) - Full resolution
- **0.5 to 2.0** - Adjust for performance vs quality trade-off
- Lower values = better performance, higher = sharper visuals

#### Takeoff/Landing Detection Settings

Fine-tune how the app detects the start and end of flights:

⚠️ **Advanced users only** - These settings affect how IGC files are processed during import.

**Speed Threshold:**
- Default: **10 km/h**
- Minimum ground speed to consider as "flying"
- Lower values = more sensitive detection

**Climb Rate Threshold:**
- Default: **0.5 m/s**
- Minimum climb rate to distinguish takeoff from ground activity
- Used in combination with speed

**Triangle Closing Distance:**
- Default: **100 metres**
- Maximum distance from launch to landing to consider as a "local flight"
- Affects distance calculations

**Triangle Sampling Interval:**
- Default: **30 seconds**
- How often to sample points when detecting triangle tasks
- Lower values = more precise but slower processing

#### Wind Threshold Settings

Set your personal limits for flyability assessment:

**Wind Speed Thresholds (km/h):**
- Use the **dual slider** to set two thresholds:
  - **Left handle (Caution)** - Default: 20 km/h
    - Below this = Green (good conditions)
  - **Right handle (Unsafe)** - Default: 25 km/h
    - Above this = Red (do not fly)
  - **Between handles** = Orange (caution - marginal)

**Adjusting Thresholds:**
1. Drag the left slider to set caution threshold
2. Drag the right slider to set unsafe threshold
3. The values update immediately
4. Changes affect all weather displays and forecasts

⚠️ **Important:** These are personal limits. Consider your experience level, wing type, site characteristics, and local conditions. Conservative thresholds (lower values) are safer, especially for newer pilots.

**Saving Changes:**
- All preference changes save automatically
- You'll see a confirmation message when saved
- Changes take effect immediately across the app

---

## Understanding Storage

- **Local Database**: All flight data stored on your device only
- **Map Cache**: Stores map tiles for offline viewing (rebuilds automatically)

⚠️ **Critical Warning:** Never tap **Delete Database** unless you want to permanently lose all flight data. This action cannot be undone.

---

## Troubleshooting

### Common Import Issues


**Problem: Import takes too long or times out**

- Check internet connection (required for site name lookups)
- Close other apps to free up device memory

**Problem: Wrong timezone in flight details**

- Verify GPS coordinates are valid in the IGC file header
- Check if your flight crossed timezone boundaries
- Manually edit **Launch Date** and **Launch Time** in flight details
- Times should reflect local timezone at launch location

**Problem: Flights marked as duplicates incorrectly**

- Check if flights have identical date and start time
- Use **Replace** option if the new IGC file has better data

### Site and Location Issues

**Problem: Wrong site assigned to flight**

- Open flight details and tap the **launch site name**
- Click on the site and select the correct launch site
- Create a new site if no existing site is appropriate

### Weather and Forecast Issues

**Problem: No weather forecast showing**

- Check internet connection - forecasts require online access
- Verify location permission is granted (for Near Here mode)
- Try toggling the forecast overlay off and on
- Pull down to refresh forecast data

**Problem: Forecast shows all grey/no data**

- The site may be outside coverage area of weather providers
- Check if site coordinates are valid
- Try a different site or different forecast provider

**Problem: Flyability colors don't match my expectations**

- Review your wind thresholds in **Preferences** → **Wind Thresholds**
- Default thresholds: Caution = 20 km/h, Unsafe = 25 km/h
- Adjust thresholds based on your experience and equipment
- Remember: Flyability is a guide only, always assess local conditions

**Problem: Favorites not showing in Forecast tab**

- Ensure you've marked sites as favorites (star icon on site details)
- Pull down to refresh the forecast screen
- Check that Favorites mode is selected (top tabs)

### Map and Airspace Issues

**Problem: Map not loading or showing blank tiles**

- Check internet connection
- Try changing map provider (**Map Settings** → select different provider)
- Clear map cache in **Database Settings** if tiles are corrupted
- Zoom to a different location and zoom back

**Problem: Airspace overlay not showing**

- Ensure airspace overlay is enabled (**Filter icon** → check Airspace)
- Zoom in closer - airspace only loads within view bounds
- Check internet connection - airspace data downloads on demand
- Some regions may have no airspace data in OpenAIP database

**Problem: Weather stations not appearing**

- Enable weather stations overlay (**Filter icon** → check Weather Stations)
- Weather stations only load for visible map area
- Not all regions have weather station coverage
- Check internet connection for station data

**Problem: Site markers showing wrong wind data**

- Ensure forecast overlay is enabled
- Forecasts update based on current time
- Pull down to refresh weather data
- Wind data requires internet connection

**Problem: Map performance is slow**

- Switch to OpenStreetMap provider (uses less data)
- Disable airspace overlay if not needed
- Disable weather stations overlay
- Zoom out less - detailed views require less data

---

## Quick Reference

### File Formats Supported

- **IGC files**: Standard flight recorder format (primary)

### Automatic Features Summary

✓ Timezone detection from GPS coordinates
✓ Launch site naming from ParaglidingEarth database
✓ Duplicate flight prevention using multiple criteria
✓ Comprehensive flight statistics calculation
✓ Wing and site name standardisation
✓ Interactive map caching (12-month duration)
✓ Weather forecast integration with flyability assessment
✓ Airspace overlay from OpenAIP database
✓ Multi-site weather comparison
✓ ParaglidingEarth database sync on app load  

### Navigation

- **Bottom Navigation Bar**: Four main tabs (Flight Log, Nearby Sites, Forecast, Statistics)
- **Main Menu**: Tap menu button (⋮) in top-right of Flight Log screen
- **Flight Details**: Tap any flight in the main list
- **Site Details**: Tap site markers on map or site names in lists
- **Edit Mode**: Look for underlined, clickable text
- **Selection Mode**: Long press items to enter bulk selection
- **Back Navigation**: Use device back button or arrow in top-left
- **Manual Entry**: Tap floating (+) button on Flight Log screen
- **Map Filters**: Tap filter icon (funnel) on Nearby Sites screen
- **Map Settings**: Tap map settings icon (layers) on Nearby Sites screen

### Data Locations and Limits

- **Local Storage**: All data stored on device only
- **No Account Required**: Completely offline operation
- **Flight Limit**: No practical limit on number of flights
- **File Size**: Large IGC files (multi-hour flights) supported

### Glossary

- **Airspace**: Controlled regions of airspace with restrictions (from OpenAIP database)
- **Favorites**: Sites you've marked for quick access in weather forecasts
- **Flyability**: Colour-coded assessment of flying conditions (green/orange/red)
- **IGC**: Standard flight recorder file format containing GPS track data
- **Multi-Model Forecast**: Weather predictions from multiple forecast providers
- **OpenAIP**: Open aviation database providing airspace and airport data
- **PGE**: ParaglidingEarth - community database of flying sites worldwide
- **Site**: Launch location with GPS coordinates and descriptive name
- **Straight Distance**: Direct line distance from launch to landing
- **Track**: GPS flight path showing position over time
- **Track Distance**: Total distance flown following the actual flight path
- **Vario**: Variometer or flight computer device that records IGC files
- **Weather Station**: Ground station providing real-time weather observations
- **Week Summary**: Seven-day forecast table showing flyability for multiple sites
- **Wind Threshold**: Personal limits for caution (orange) and unsafe (red) conditions
- **Wing**: Your paraglider, hang glider, microlight, or other aircraft

---

## Summary

This manual covers all aspects of using The Paragliding App effectively, from basic flight import through weather forecasting, airspace awareness, and advanced data analysis. The app combines comprehensive logbook functionality with real-time weather data and interactive maps to help you plan flights, maintain records, and fly safely. All features are designed to minimise manual work while providing powerful tools for pilots at every experience level.
