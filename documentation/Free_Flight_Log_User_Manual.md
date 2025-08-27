# Free Flight Log User Manual

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

### Understanding the Home Screen

The main screen shows all your flights with:

- **Menu button** (⋮) in top-right provides access to all the app features
- **Total flights** and **flight hours** displayed at the top of the list. You can use the **Select Flights** menu item to limit this to a subset of flights.
- **Sortable table** with columns: Launch Site, Launch Date & Time, Duration, Track Dist (km), Straight Dist (km), Max Alt (m)
- **Tap any flight** to see the flight statistics, watch a 3D replay or correct flight details
- **Add flight button** (+) floating button for manual flight entry

### Main Menu Structure

The **menu button (⋮)** in the top-right corner provides access to:

- **Statistics** - View flight summaries and totals by year, wing or site.
- **Manage Sites** - Edit launch locations.
- **Manage Wings** - Track your equipment.
- **Import IGC** - Import flight files.
- **Select Flights** - Bulk operations like delete
- **Database Settings** - Data dackup and maintenance. Be careful!
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

## Analysis Tools

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

### Navigation

- **Main Menu**: Tap menu button (⋮) in top-right
- **Flight Details**: Tap any flight in the main list
- **Edit Mode**: Look for underlined, clickable text
- **Selection Mode**: Long press items to enter bulk selection
- **Back Navigation**: Use device back button or arrow in top-left
- **Manual Entry**: Tap floating (+) button on home screen

### Data Locations and Limits

- **Local Storage**: All data stored on device only
- **No Account Required**: Completely offline operation
- **Flight Limit**: No practical limit on number of flights
- **File Size**: Large IGC files (multi-hour flights) supported

### Glossary

- **IGC**: Standard flight recorder file format containing GPS track data
- **Wing**: Your paraglider, hang glider, microlight, or other aircraft
- **Site**: Launch location with GPS coordinates and descriptive name
- **PGE**: ParaglidingEarth - community database of flying sites worldwide
- **Vario**: Variometer or flight computer device that records IGC files
- **Track**: GPS flight path showing position over time
- **Straight Distance**: Direct line distance from launch to landing
- **Track Distance**: Total distance flown following the actual flight path

---

This  manual covers all aspects of using Free Flight Log effectively, from basic flight import through advanced data analysis and maintenance. The app is designed to minimise manual work while providing powerful tools for serious flight analysis and record-keeping.
