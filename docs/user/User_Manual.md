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
- **Total flights** and **flight hours** displayed at the top of the list
- **Date range filtering** - Filter flights by time period (see below)
- **Search bar** - Filter flights by launch site name in real-time
- **Sortable table** with columns: Launch Site, Launch Date & Time, Duration, Track Dist (km), Straight Dist (km), Max Alt (m)
  - **Tap any column header** to sort by that column (ascending/descending toggle)
- **Tap any flight** to see the flight statistics, watch a 3D replay or correct flight details
- **Add flight button** (+) floating button for manual flight entry

#### Filter Flights by Date Range

Use the date range filter at the top to view specific time periods:

1. Tap the **date range dropdown** (defaults to "All Time")
2. Select from preset ranges:
   - **All Time** - Shows every flight in your logbook
   - **This Year** - Current calendar year only
   - **Last 12 Months** - Rolling 12-month period
   - **Last 6 Months** - Rolling 6-month period
   - **Last 3 Months** - Rolling 3-month period
   - **Last 30 Days** - Last month of flights
   - **Custom Range** - Pick specific start and end dates
3. The flight list and statistics update immediately

**Uses:**
- Check currency requirements (e.g., flights in last 90 days)
- Review seasonal flying patterns
- Generate period-specific statistics
- Prepare logbook summaries for specific timeframes

#### Search and Sort Flights

**To search by launch site:**
1. Type in the **search bar** at the top
2. Results filter in real-time as you type
3. Clear the search to see all flights again

**To sort the table:**
1. Tap any **column header** (Date, Site, Duration, Distance, etc.)
2. First tap sorts ascending, second tap sorts descending
3. A sort indicator appears on the active column
4. Sorting persists until you change it

### Main Menu Structure

The **menu button (⋮)** in the top-right corner provides access to:

- **Import IGC** - Import flight files from your vario or cloud storage
- **Add Flight** - Manually log a flight without IGC file
- **Manage Sites** - View, edit, and organize launch/landing locations
- **Manage Wings** - Track and manage your equipment inventory
- ────────── (divider)
- **Data Management** - Database backup, IGC files, PGE sync, airspace data, and premium maps
- **Preferences** - Configure app settings for 3D visualization, detection thresholds, and wind limits
- **About** - App version, build information, credits, and support

---

## Daily Use

### Manually Log a Flight

If you don't have an IGC file (e.g., forgot your vario, battery died, or recreational flight), you can manually enter flight details.

#### Steps

1. Tap the **floating (+) button** at the bottom-right of the Flight Log screen
2. Or tap **menu (⋮)** → **Add Flight**
3. Fill in the flight details form:
   - **Date** (required) - Tap to open date picker
   - **Launch Time** (required) - Enter time in HH:MM format
   - **Landing Time** (optional) - Auto-calculates duration
   - **Launch Site** (required) - Select from dropdown or create new
   - **Landing Site** (optional) - Select if different from launch
   - **Wing** (required) - Select equipment used
   - **Duration** - Auto-calculated from times, or enter manually
   - **Max Altitude** (optional) - Highest point in meters
   - **Distance** (optional) - Flight distance in km
   - **Notes** (optional) - Flight description, conditions, etc.
4. Tap **Save** to add the flight to your logbook

#### When to Use Manual Entry

✓ Vario battery died mid-flight
✓ Forgot GPS device
✓ Recreational flight without tracking
✓ Training flight from known site
✓ Quick logbook entry for insurance/currency records

#### Tips

- **Duration auto-calculates** when you enter both launch and landing times
- **Create sites on-the-fly**: If the launch site isn't in the dropdown, you can add it during flight entry
- **Edit later**: You can always edit manually-entered flights to add missing details
- **No track data**: Manual flights won't have GPS tracks, so 3D replay won't be available

---

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

### Edit Flight Details

If you need to correct flight information (wrong date, site, wing, etc.), you can edit any flight.

#### Steps

1. Tap the **flight** in your Flight Log to open Flight Details
2. Tap the **Edit** button (usually in top-right or as a menu option)
3. The Edit Flight screen opens with a form showing current flight data
4. Modify any field:
   - **Date** - Tap to open date picker
   - **Launch Time** - Enter or adjust launch time
   - **Landing Time** - Enter or adjust landing time (duration auto-updates)
   - **Launch Site** - Select different site from dropdown
   - **Landing Site** - Select different landing site
   - **Wing** - Change equipment used
   - **Duration** - Manually adjust if time calculation is incorrect
   - **Max Altitude** - Correct altitude value
   - **Distance** - Adjust distance if needed
   - **Notes** - Add or modify flight notes
5. Tap **Save** to apply changes
6. Tap **Cancel** to discard changes

#### Common Edits

**Wrong launch site:**
- Often happens when GPS started after takeoff
- Change to correct site from dropdown
- Or create new site if not in list

**Incorrect time/date:**
- Timezone detection occasionally fails
- Manually adjust to local time at launch location
- Duration recalculates automatically

**Wrong wing:**
- Easy to forget to change in vario
- Select correct wing from dropdown
- Helps keep accurate wing statistics

**Missing notes:**
- Add weather conditions
- Document lessons learned
- Record memorable moments

#### What You Can't Edit

- **GPS track data** - The actual flight path from IGC file is immutable
- To change track data, you must re-import the IGC file (use "Replace" in duplicate dialog)
- 3D visualization always uses original IGC track points

---

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

The map supports multiple overlay types. Tap the **filter icon** (funnel) in the top-right to open the filter dialog with checkboxes:

**Filter Behavior:**
- ✓ **Checkboxes apply immediately** - No need to tap "Apply" or "OK"
- Each overlay can be toggled independently
- Your filter selections are saved and persist across app sessions
- Close the filter dialog by tapping outside it or using the back button

**Sites Overlay** (checkbox, on by default)
- Shows flying site markers from your logbook and ParaglidingEarth
- Blue markers with star = sites you've flown (Flown Sites)
- Orange markers = sites from ParaglidingEarth you haven't flown yet (New Sites)
- Uncheck to hide all site markers

**Airspace Overlay** (checkbox, off by default)
- Displays controlled airspace polygons from OpenAIP
- Different colours for airspace types: controlled zones (red), restricted areas (orange), danger zones, etc.
- Helps plan flights to avoid restricted airspace
- Tap airspace polygons to see details (name, type, altitude limits)
- Check to enable airspace visualization

**Forecast Overlay** (checkbox, off by default)
- Adds wind direction/speed icons to site markers
- Shows flyability status with colour coding:
  - **Green** = Good conditions for flying
  - **Orange** = Caution - marginal conditions
  - **Red** = Unsafe - do not fly
- Updates automatically based on current time
- Requires internet connection for weather data
- Check to enable wind/flyability indicators

**Weather Stations Overlay** (checkbox, off by default)
- Shows nearby weather stations with real-time observations
- Different icons for station types: BOM (Bureau of Meteorology), METAR (aviation stations), PGE stations
- Tap stations to see current wind, temperature, and conditions
- Useful for checking actual conditions vs forecasts
- Check to enable weather station markers

**Tips:**
- Enable only the overlays you need to reduce map clutter
- Airspace overlay is essential for flight planning in controlled airspace regions
- Forecast overlay helps with quick site selection based on conditions
- Weather stations provide ground truth vs model forecasts

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
2. Or tap the **Statistics tab** in the bottom navigation bar
3. Select a **date range filter** at the top (same options as Flight Log):
   - All Time / This Year / Last 12 Months / Last 6 Months / Last 3 Months / Last 30 Days / Custom Range
4. Review the three main sections:
   - **Flights by Year**: Annual flight counts and total hours
   - **Flights by Wing**: Usage statistics for each piece of equipment
   - **Flights by Site**: Launch locations grouped by country
5. Tap any **site name** (underlined) to edit location details
6. View totals at the bottom of each section

#### Understanding the Statistics

- **Active wings** are shown first, followed by inactive equipment
- **Sites are grouped by country** with flight counts
- **Yearly statistics** help track progress and currency requirements
- **Total rows** provide overall summaries
- **Date filtering** allows you to analyze specific time periods (e.g., "How much did I fly this year?" or "Which wing did I use most in the last 6 months?")

### View Flight Details

#### What You'll Learn

Access comprehensive information about a specific flight including statistics, track visualization, and notes.

#### Opening Flight Details

1. Tap any **flight row** in the Flight Log screen
2. The Flight Detail screen opens showing multiple information sections
3. Scroll to explore different sections (each can be expanded/collapsed)

#### Flight Information Sections

**Basic Flight Info** (always visible at top):
- Date and time (local timezone)
- Launch and landing sites with coordinates
- Wing/equipment used
- Duration (hours:minutes)
- Track distance vs straight-line distance
- Maximum altitude and altitude gain

**Flight Statistics** (expandable card):
- Climb rate statistics (current/average/maximum)
- Speed statistics (ground speed metrics)
- Time in climb vs glide
- Flight efficiency calculations
- Detailed performance metrics

**2D Map View** (expandable card):
- Top-down map showing flight path
- Launch marker (green) and landing marker (red)
- Track line visualization
- Zoom and pan to explore track details
- Change map provider (OpenStreetMap, Satellite, etc.)

**3D Track Visualization** (expandable card):
- Interactive 3D viewer with terrain (see "Replay Flights in 3D" below for details)
- Play/pause replay controls
- Speed and time controls
- Color-coded altitude/climb rate display

**Notes Section** (expandable card):
- View existing flight notes
- **Inline editing**: Tap the **edit icon** to enter edit mode
- Type or modify notes directly
- Tap **Save** to store changes or **Cancel** to discard
- IGC file source path (for imported flights)

#### Available Actions

From the flight detail screen, you can:

- **Edit flight details**: Change date, time, site, wing, or other metadata
- **View full-screen 3D**: Expand the 3D track for immersive replay
- **Share flight**: Export or share flight data
- **Delete flight**: Remove from logbook (with confirmation)
- **Add/edit notes**: Document conditions, lessons learned, or memorable moments

#### Card Expansion States

Each section (Statistics, 2D Map, 3D Track, Notes) can be:
- **Expanded**: Shows full content
- **Collapsed**: Shows only section title
- Tap the section header to toggle
- Your expansion preferences are saved across app sessions

---

### Replay Flights in 3D

#### What You'll Learn

Use the interactive 3D viewer to analyse flight performance and relive your flying experiences.

#### Opening 3D View

1. Tap any **flight** from your main flight list to open Flight Details
2. Scroll down to the **3D Track** section
3. Tap the section header to expand (if collapsed)
4. The interactive 3D map loads automatically showing terrain and flight track
5. Or tap **View Full Screen** to open in immersive mode

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
- **Current stats display**: Shows altitude, speed, and climb rate at current replay position

#### Map and Scene Options

**Change Map Provider:**

- Tap the **map provider dropdown** in the top-right
- Choose from available maps (OpenStreetMap, Satellite, Terrain, etc.)
- Premium maps available with Cesium ION token (see Data Management)

**Understanding Track Colours:**

- Track colour represents climb rate performance
- **Green** = Climbing (climb rate > 0 m/s)
- **Blue** = Gliding (climb rate between 0 and -1.5 m/s)
- **Red** = Sinking (climb rate < -1.5 m/s)
- Colour gradient shows thermal activity and flight efficiency

---

## Managing Your Data

### Organise Site Information

#### View All Sites

1. Tap **menu (⋮)** → **Manage Sites**
2. The screen shows **site statistics** at the top:
   - Total sites count
   - Sites with flights vs without flights
   - Total flights from all sites
3. Use the **search bar** to find specific sites: "Search sites by name or country..."
4. Change sorting with the **sorting dropdown menu**:
   - **Group by Country** - Shows country section headers with sites grouped underneath
   - **Sort by Name** - Alphabetical order (A-Z)
   - **Sort by Date Added** - Newest sites first
5. Each site row displays:
   - Site name
   - Coordinates (latitude, longitude)
   - Altitude in meters
   - Country
   - **Flight count badge** - Number of flights from this site
   - Favorite star indicator (if marked as favorite)

#### Country Grouping View

When using **Group by Country** sorting:
- Sites are organized under country section headers
- Country headers are collapsible/expandable
- Tap a country header to collapse or expand all sites in that country
- Total flight count shown per country
- Helps organize large site databases by region

#### Edit Site Details

1. Find the site in **Manage Sites** list
2. Tap the **popup menu (⋮)** next to the site
3. Select **Edit** from the menu
4. The **Edit Site** screen opens with an interactive map showing:
   - Current site location with draggable marker
   - Launch radius circle (visualizes 500m detection radius)
   - Map controls (zoom in/out)
5. **Adjust location precisely**:
   - Drag the marker to the exact launch point
   - Or tap anywhere on the map to place the marker
   - Coordinates update automatically
6. Modify site fields:
   - **Site Name** (required)
   - **Country** (required)
   - **Altitude (metres)** - Launch elevation
   - **Notes** - Access info, directions, or special considerations
   - Coordinates auto-update from map marker position
7. **Change map provider** if needed (satellite view helps identify exact launch)
8. Tap **Save** to apply changes

⚠️ **Important:**
- Changes affect all flights associated with this location
- The 500m radius circle shows the area where flights will auto-match to this site
- Use satellite imagery to precisely position the marker at the actual launch point

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

## Data Management & Advanced Features

### Understanding Data Storage

The app stores multiple types of data on your device:

- **Local Database**: All flight records, sites, wings, and statistics
- **IGC Files**: Original GPS track files from imports
- **Map Cache**: Temporary map tiles for faster loading
- **PGE Sites Database**: Paragliding Earth site database (synced periodically)
- **Airspace Data**: OpenAIP airspace polygons (downloaded on demand)
- **Preferences**: Your app settings and customizations

All data is stored locally on your device. The app does not sync to cloud storage automatically.

---

### Manage Database and Backups

#### What You'll Learn

Backup your flight data, manage database integrity, and understand storage usage.

#### Access Data Management

1. Tap **menu (⋮)** → **Data Management**
2. The screen shows multiple expandable sections for different data types

#### Database Management Section

**Database Statistics:**
- Total flights count
- Total sites count
- Total wings count
- Database file size
- Last backup date (if available)

**Available Operations:**

**Export Database:**
1. Tap **Export Database** button
2. Choose export location (Downloads, cloud storage, etc.)
3. A complete SQLite database file is saved
4. File includes all flights, sites, wings, and preferences
5. Use for backups or transferring to another device

**Database Integrity Check:**
1. Tap **Check Database Integrity**
2. App verifies database structure and data consistency
3. Reports any corruption or issues found
4. Recommended before major operations or if experiencing errors

**Reset Database** (⚠️ Destructive):
1. Tap **Reset Database**
2. Confirmation dialog appears with **severe warning**
3. Type confirmation phrase if required
4. All flight data, sites, and wings are permanently deleted
5. ⚠️ **This cannot be undone** - only use if starting fresh or restoring from backup

---

### Manage IGC Files

#### What You'll Learn

Understand IGC file storage and clean up orphaned files to free device space.

#### IGC File Management Section

**IGC Backup Statistics:**
- Total IGC files stored
- Total storage used by IGC files
- Oldest and newest file dates
- Orphaned files count (files without matching flight records)

**Available Operations:**

**Clean Up Orphaned IGC Files:**
1. Tap **Clean Up Orphaned Files**
2. App scans for IGC files that don't match any flight record
3. Review list of files to be removed
4. Confirm cleanup
5. Storage is freed and cleanup history is recorded

**Why orphaned files exist:**
- Flights were deleted but IGC files remained
- Import failures left partial data
- Manual database operations

**Benefits of cleanup:**
- Frees device storage
- Keeps file system organized
- Improves backup/restore performance

---

### Configure Premium Maps (Cesium ION Token)

#### What You'll Learn

Enable premium map providers including Bing Maps satellite imagery for 3D flight visualization.

#### Why Use Premium Maps

**Free Maps (Default):**
- OpenStreetMap terrain
- Basic satellite imagery
- Limited 3D terrain quality

**Premium Maps (with Cesium ION token):**
- High-resolution Bing Maps satellite imagery
- Enhanced 3D terrain data
- Better performance and caching
- Professional visualization quality

#### Getting a Cesium ION Token

1. Visit [Cesium ION](https://cesium.com/ion/) (free account available)
2. Create a free account
3. Navigate to **Access Tokens** in your account dashboard
4. Create a new token or use the default token
5. Copy the token string (starts with "eyJ...")

#### Configure Token in App

1. Tap **menu (⋮)** → **Data Management**
2. Scroll to **Premium Maps** section
3. Tap **Configure Cesium Token**
4. Paste your token in the input field
5. Tap **Validate Token**
6. If valid, a success message appears and premium maps are enabled
7. Tap **Save**

#### Using Premium Maps

Once configured:
- 3D flight tracks automatically use enhanced terrain
- Map provider dropdown shows additional options (Bing Aerial, Bing Road, etc.)
- Better zoom levels and detail available
- Terrain quality improves significantly

**Free Tier Limits:**
- Cesium offers a generous free tier for personal use
- Sufficient for typical paragliding app usage
- Monitor your usage in Cesium ION dashboard if concerned

---

### Sync Paragliding Earth Sites Database

#### What You'll Learn

Download and update the global database of flying sites from ParaglidingEarth.

#### PGE Sites Database Section

**Database Information:**
- Last sync date and time
- Total sites in database
- Last update check
- Sync status (up to date / update available)

**Available Operations:**

**Sync Now:**
1. Tap **Sync PGE Sites Database**
2. App connects to ParaglidingEarth API
3. Downloads latest site data (name, coordinates, country, altitude)
4. Incremental sync - only downloads new or changed sites
5. Progress indicator shows download status
6. Sync completes and shows updated site count

**Force Full Re-sync:**
1. Tap **Force Full Re-sync**
2. Deletes local PGE cache
3. Downloads complete fresh database
4. Use if experiencing sync issues or missing sites
5. Takes longer than incremental sync

**When to Sync:**
- First app launch (automatic)
- Every 7-30 days (recommended)
- Before traveling to new flying regions
- If you notice missing sites on the map
- After ParaglidingEarth announces major updates

**Benefits:**
- Automatic site naming during IGC import
- Discover new flying sites in Nearby Sites map
- Access to global site database (50,000+ sites)
- Community-maintained site information

---

### Manage Airspace Data

#### What You'll Learn

Download and configure airspace overlays for flight planning and safety.

#### Airspace Data Section

**Available Operations:**

**Select Airspace Regions:**
1. Tap **Manage Airspace Data**
2. Choose countries or regions to download:
   - Select by country (e.g., Australia, USA, Europe)
   - Choose airspace types (CTR, TMA, CTA, Restricted, Danger, etc.)
3. Tap **Download Selected**
4. Airspace polygons download and cache locally
5. Data becomes available in map overlay immediately

**Airspace Type Filters:**
- **CTR** (Control Zone) - Airport controlled airspace
- **TMA** (Terminal Maneuvering Area) - Approach/departure zones
- **CTA** (Control Area) - En-route controlled airspace
- **Restricted** - Military or special use airspace
- **Danger** - Hazardous areas (firing ranges, etc.)
- **Prohibited** - Absolutely no-fly zones

**Refresh Airspace Data:**
1. Tap **Refresh Airspace**
2. Re-downloads selected regions with latest data
3. Use when airspace changes are announced (NOTAMs, etc.)

**Clear Airspace Cache:**
1. Tap **Clear Airspace Cache**
2. Frees storage by removing downloaded airspace data
3. Re-download when needed

**Data Source:**
- All airspace from OpenAIP (Open Aviation Data)
- Community-maintained and regularly updated
- Free and open data

---

### Understanding Storage and Backups

#### Storage Breakdown

**What uses storage:**
- Database: 1-50 MB (depending on flight count)
- IGC files: 100 KB - 1 MB per flight
- Map cache: Up to 500 MB (auto-managed)
- PGE sites database: 10-20 MB
- Airspace data: 5-50 MB per country

**Total for 1000 flights:** Approximately 200-500 MB

#### Backup Best Practices

**Regular Backups:**
- Export database monthly or after every 10-20 flights
- Store backups in cloud storage (Google Drive, Dropbox, etc.)
- Keep backups before major app updates
- Test restore process occasionally

**What to backup:**
- ✓ Database export (includes all flights, sites, wings)
- ✓ IGC files folder (original track data)
- ✗ Map cache (regenerates automatically)
- ✗ PGE database (re-syncs from API)

**Restore Process:**
1. Install app on new device
2. Import database export
3. Re-import IGC files if needed
4. Sync PGE sites database
5. Reconfigure preferences

⚠️ **Critical Warning:** The **Reset Database** operation permanently deletes ALL flight data. This action cannot be undone. Always export a backup before using this function.

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

### App Information and Credits

To view app version, build information, and credits:

1. Tap **menu (⋮)** → **About**
2. The About screen shows:
   - App name and version number
   - Build information (Git commit, branch, build date)
   - Feature highlights with icons
   - Credits and acknowledgments
   - External links:
     - GitHub repository (tap to open in browser)
     - Project documentation
     - License information
   - Contact and support information

**Uses:**
- Check your app version when reporting issues
- View build information for troubleshooting
- Access project documentation
- See app credits and contributors
- Find support and feedback channels

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
