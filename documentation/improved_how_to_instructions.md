# Improved Instructions for Free Flight Log User Manual

## Documentation Guidelines

### Writing Style

- Write in active voice, second person ("You can import...")
- Use British spelling (colour, analyse, organise)
- Keep procedures under 7 steps when possible
- Use consistent formatting for UI elements
- Test each procedure before documenting

### Formatting Standards

- **Bold** for UI elements (buttons, menus, fields)
- `Code style` for file names and technical terms
- ✓ Checkmarks for automatic features
- ⚠️ Warning symbols for important notes
- Numbered lists for step-by-step procedures
- Bullet points for feature lists

---

# Free Flight Log User Guide

## Getting Started (5 minutes)

### What You'll Learn

Import your first flight and understand the main screen in under 5 minutes.

### Your First Import

1. Tap **Import Flight** from the home screen
2. Select your IGC file from your vario, XCTrack, or cloud storage
3. Tap **Import** - the app automatically detects timezone and calculates statistics
4. Review your flight in the list

### Understanding the Home Screen

The main screen shows all your flights with:

- **Total flights** and **hours flown** at the top
- **Sortable columns**: Launch Site, Date, Duration, Distance, Max Altitude
- **Tap any flight** to see detailed analysis and 3D replay

---

## Daily Use

### Import Flights from Your Vario

#### What You'll Learn

How to import IGC files from any source and handle duplicates.

#### Steps

1. Connect your vario to your device or access cloud storage
2. Tap **Import Flight**
3. Browse to your IGC files (supports batch selection)
4. Select files and tap **Import**

#### What the App Does Automatically

✓ Detects timezone from GPS coordinates  
✓ Names launch sites using ParaglidingEarth database  
✓ Calculates flight statistics (distance, duration, max climb)  
✓ Prevents duplicate imports using date and GPS data  

#### Handling Duplicates

When the app detects a duplicate:

- **Skip**: Ignores the duplicate file
- **Replace**: Updates existing flight with new data
- **Keep Both**: Imports as separate flight (rare edge cases)

### Fix Unknown Launch Sites

#### Scenario 1: New Site Not in Database

**Problem:** Your launch site appears as "Unknown Site"

**Solution:**

1. Tap the **flight** to open details
2. Tap the **site name** (underlined)
3. Enter correct **site name** and **country**
4. Tap **Save**

**Result:** Future flights from nearby GPS coordinates will automatically use this site name.

#### Scenario 2: GPS Started After Launch

**Problem:** Wrong launch coordinates because GPS started late

**Solution:**

1. Open **flight details**
2. Tap **Edit Site** on the map
3. Tap the correct launch point on the map
4. Confirm the location
5. Save changes

### Track Your Equipment

#### Edit Wing Names

**Why:** Standardise equipment names for accurate statistics

**Steps:**

1. Go to **Settings** → **Manage Wings**
2. Tap the **wing name** to edit
3. Enter standard name (e.g., "Advance Omega X-Alps 2" instead of "omega")
4. Tap **Save**

#### Merge Duplicate Wings

**Why:** Combine statistics when you have multiple entries for the same wing

**Steps:**

1. Go to **Settings** → **Manage Wings**
2. Tap **Select** mode
3. Choose the wings to merge
4. Tap **Merge Wings**
5. Choose which name to keep
6. Confirm - all flights transfer to the kept wing

---

## Analysis Tools

### View Flight Statistics

#### What You'll Learn

Access yearly statistics, wing usage, and site summaries.

#### Steps

1. Tap **Statistics** from the main menu
2. Review:
   - **Yearly totals**: Flights and hours per year
   - **Wing usage**: Hours per wing type
   - **Site statistics**: Flights per launch site, grouped by country
3. Tap any **site name** to edit location details

### Replay Flights in 3D

#### What You'll Learn

Use the 3D viewer to analyse flight performance and relive flights.

#### Opening 3D View

1. Tap any **flight** from the main list
2. Tap **View in 3D** button
3. Wait for terrain and track to load

#### 3D Navigation

- **Zoom**: Pinch or scroll wheel
- **Pan**: Drag to move around
- **Tilt**: Right-click drag or two-finger drag
- **Reset view**: Tap the **home** icon

#### Flight Replay Controls

- **Play/Pause**: Start or stop flight replay
- **Speed**: Adjust replay speed (1x to 16x)
- **Follow mode**: Tap **camera icon** to follow the pilot
- **Full screen**: Tap **expand icon** for immersive view

#### Map Options

**Change Map Type:**

- **Street Map**: OpenStreetMap view
- **Satellite**: Google Satellite imagery
- **Terrain**: Esri terrain view

**Change Scene:**

- **Realistic**: Earth terrain with atmosphere
- **Performance**: Simplified view for older devices

---

## Managing Your Data

### Organise Site Information

#### View All Sites

1. Go to **Settings** → **Manage Sites**
2. Browse by **country** groupings
3. Use **search** to find specific locations
4. View **flight count** for each site

#### Edit Site Details

1. Find the site in **Manage Sites** or tap from **Statistics**
2. Tap the **site name**
3. Modify name, coordinates, altitude, or country
4. Tap **Save**

⚠️ **Note:** Changes affect all flights from this location.

### Database Maintenance

#### Backup Your Data

**Why:** Protect your flight history

**Steps:**

1. Go to **Settings** → **Database Settings**
2. Tap **Export Database**
3. Save the file to cloud storage
4. Keep multiple backups in different locations

#### Performance Tuning

**If the app feels slow:**

1. Go to **Settings** → **Database Settings**
2. Check **cache statistics**
3. Tap **Clear Map Cache** if cache is very large (>500MB)
4. Restart the app

⚠️ **Warning:** Never tap **Delete Database** unless you want to lose all data permanently.

---

## Troubleshooting

### Common Import Issues

**Problem: Can't select IGC files**

- Check file permissions in device settings
- Ensure files aren't corrupted
- Try importing one file at a time

**Problem: Import takes too long**

- Check internet connection (needed for site lookups)
- Import smaller batches (10-20 files at once)
- Close other apps to free memory

**Problem: Wrong timezone**

- Check GPS coordinates are valid in the IGC file
- Manually edit flight times in **Flight Details**

### Site and Location Issues

**Problem: Wrong site assigned**

- Use the site editing map to click correct launch point
- The app reassigns flights within 500m radius automatically

**Problem: Sites not merging**

- Use **Edit Site** to manually adjust coordinates
- Sites must be within 100m to be considered the same

### Performance Issues

**Problem: 3D view won't load**

- Check internet connection for terrain data
- Try switching to **Performance** scene mode
- Clear browser cache in **Database Settings**

**Problem: App crashes during import**

- Import smaller batches
- Restart app before large imports
- Check available device storage

---

## Quick Reference

### File Formats Supported

- **IGC files**: Standard flight recorder format
- **KML files**: Limited support for basic tracks

### Automatic Features Summary

✓ Timezone detection from GPS  
✓ Launch site naming from ParaglidingEarth  
✓ Duplicate flight prevention  
✓ Flight statistics calculation  
✓ Wing and site name standardisation  

### Glossary

- **IGC**: Standard flight recorder file format containing GPS track
- **Wing**: Your paraglider, hang glider, or microlight
- **Site**: Launch location with coordinates and name
- **PGE**: ParaglidingEarth - online database of flying sites
- **Vario**: Variometer or flight computer device

### Data Locations

- **Local Database**: Stored on your device
- **No Cloud Sync**: All data remains local
- **Manual Backup**: Use export feature for backups

---

## Advanced Features

### Batch Operations

- **Multi-select flights**: Long press to enter selection mode
- **Bulk delete**: Remove multiple flights at once
- **View selection totals**: See combined statistics

### Map Features

- **Multiple providers**: OpenStreetMap, Google, Esri
- **Offline caching**: 12-month cache duration
- **Interactive markers**: Different colours for site types

### Statistics Depth

- **Yearly breakdowns**: Flights and hours per year
- **Equipment tracking**: Hours per wing
- **Geographic analysis**: Flights per country and site

This user manual structure prioritises practical workflows over feature descriptions, making it easier for pilots to accomplish their goals quickly and efficiently.
