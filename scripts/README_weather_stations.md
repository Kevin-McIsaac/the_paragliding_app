# Weather Station Provider Comparison Script

This Python script compares weather station availability across different weather data providers for a given paragliding site.

## Purpose

The script helps you:
- See which weather providers have stations near a specific paragliding site
- Compare coverage between different weather APIs
- Identify gaps in weather data availability

## Weather Providers Queried

1. **FFVL Beacons** - French paragliding federation weather beacons (requires API key)
2. **Pioupiou** - Community wind stations (global coverage)
3. **AWC METAR** - Aviation Weather Center airport stations (global)
4. **NWS** - National Weather Service stations (US only)
5. **BOM** - Bureau of Meteorology (Australia only)

## Installation

```bash
# Requires Python 3.6+
pip install requests
```

## Usage

### Option 1: Search by Site Name (uses ParaglidingEarth.com API)

```bash
python3 scripts/check_weather_stations.py "Annecy"
```

### Option 2: Provide Coordinates Directly

```bash
python3 scripts/check_weather_stations.py "45.9,6.9" "Annecy"
```

## Configuration

### FFVL API Key

Edit the script to add your FFVL API key (get one from https://balisemeteo.com/api/):

```python
FFVL_API_KEY = "your_actual_api_key_here"
```

### Search Radius

Default is 50km. You can modify this in the script:

```python
SEARCH_RADIUS_KM = 50
```

## Output

The script outputs a markdown table showing:
- Station names
- Distance from the site (in km)
- Which providers return each station (✓/✗)

Example output:

```markdown
| Station Name                 | Distance (km) | FFVL Beacons | Pioupiou | AWC METAR | NWS | BOM |
|------------------------------|---------------|--------------|----------|-----------|-----|-----|
| Annecy-Meythet              |        3.2 km |      ✗       |    ✗     |     ✓     |  ✗  |  ✗  |
| Mont Blanc Beacon           |       28.5 km |      ✓       |    ✓     |     ✗     |  ✗  |  ✗  |
```

## Troubleshooting

### 403 Forbidden Errors

If you encounter 403 errors:

1. **Run from your local machine** - Some APIs block cloud/server IPs
2. **Check API keys** - FFVL requires a valid API key
3. **Try again later** - APIs may have rate limiting

### PGE Search Not Working

If ParaglidingEarth.com search fails:
- Use the coordinate input method instead: `python3 script.py "LAT,LON" "Site Name"`

### No Stations Found

If no stations are found:
- Try increasing `SEARCH_RADIUS_KM` in the script
- The location might be in a remote area with no weather stations
- Some providers only cover specific regions (NWS=US, BOM=Australia)

## Provider-Specific Notes

### FFVL
- Requires API key (get from https://balisemeteo.com/api/)
- Primarily covers France and surrounding European countries
- ~650 beacons

### Pioupiou
- No API key required
- Global coverage
- ~1000 community stations
- Note: Uses HTTP (not HTTPS)

### AWC METAR
- No API key required
- Global airport coverage
- Only returns airports with METAR weather reports

### NWS
- No API key required
- US and territories only
- Returns 0 stations quickly for non-US locations

### BOM
- No API key required
- Australia only
- Requires state-specific queries (simplified in this script)

## Related Files

- Application implementation: `lib/services/weather_station_service.dart`
- Provider implementations: `lib/services/weather_providers/`
- API configuration: `the_paragliding_app/.env`

## Example Commands

```bash
# Search for Annecy by name
python3 scripts/check_weather_stations.py "Annecy"

# Search using coordinates for Chamonix
python3 scripts/check_weather_stations.py "45.9237,6.8694" "Chamonix"

# Search for a US site
python3 scripts/check_weather_stations.py "37.4,-122.1" "Palo Alto"

# Search for an Australian site
python3 scripts/check_weather_stations.py "-33.9,151.2" "Sydney"
```

## How It Works

1. **Site Lookup**: Queries ParaglidingEarth.com API to find GPS coordinates (or uses provided coordinates)
2. **Provider Queries**: Queries each weather provider's API in parallel
3. **Distance Filtering**: Uses Haversine formula to filter stations within the specified radius
4. **Deduplication**: Identifies unique stations (some may appear in multiple providers)
5. **Table Generation**: Creates a markdown table showing availability across providers

## Integration with App

This script uses the same APIs and logic as The Paragliding App's weather station feature:
- APIs defined in `lib/services/weather_providers/`
- Same search radius (50km default)
- Same distance calculation (Haversine)
- Same provider configuration

The script is useful for:
- Debugging why certain stations appear/don't appear
- Comparing provider coverage before choosing which to enable
- Finding gaps in weather data coverage for your flying area
