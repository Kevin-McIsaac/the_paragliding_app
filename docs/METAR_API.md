# METAR API Integration

## API Endpoint

```
https://aviationweather.gov/api/data/metar
```

## Request Format

```bash
curl -s "https://aviationweather.gov/api/data/metar?bbox={minLat},{minLon},{maxLat},{maxLon}&format=json" \
  -H "Accept: application/json" \
  -H "User-Agent: FreeFlightLog/1.0"
```

### Parameters

- `bbox`: Bounding box as `minLat,minLon,maxLat,maxLon` (comma-separated)
- `format`: `json` (default is XML)

### Example

```bash
# Get METAR stations near Annecy (45.9°N, 6.1°E)
curl -s "https://aviationweather.gov/api/data/metar?bbox=45.5,5.7,46.3,6.5&format=json"
```

## Response Format

Returns JSON array of station objects:

```json
[
  {
    "icaoId": "LFLP",
    "name": "Annecy/Meythet Arpt, AR, FR",
    "lat": 45.93,
    "lon": 6.106,
    "elev": 460,
    "reportTime": "2025-10-03T22:00:00.000Z",
    "wdir": 70,      // Wind direction in degrees (0-360)
    "wspd": 4,       // Wind speed in knots
    "temp": 11,      // Temperature in Celsius
    "dewp": 9,       // Dew point in Celsius
    "visib": "6+",   // Visibility in miles ("6+" means 6+ miles)
    "altim": 1020,   // Altimeter setting in hPa
    "cover": "CAVOK", // Cloud cover summary
    "fltCat": "VFR"  // Flight category
  }
]
```

## Extracting Wind Data

### Wind Direction (`wdir`)
- **Type**: Integer
- **Units**: Degrees (0-360, where 0/360 = North, 90 = East, 180 = South, 270 = West)
- **Missing**: Field absent if calm/variable winds

### Wind Speed (`wspd`)
- **Type**: Integer
- **Units**: Knots (kt)
- **Missing**: Field absent if calm winds

### Wind Gust (`wgst`)
- **Type**: Integer
- **Units**: Knots (kt)
- **Missing**: Field only present when gusts are reported

### Example Extraction

```dart
final response = await http.get(Uri.parse(url));
final List<dynamic> stations = json.decode(response.body);

for (final station in stations) {
  final windDir = station['wdir'];      // null if calm
  final windSpeed = station['wspd'];    // null if calm
  final windGust = station['wgst'];     // null if no gusts
  final stationName = station['name'];

  if (windDir != null && windSpeed != null) {
    final gustStr = windGust != null ? ' gusting ${windGust}kt' : '';
    print('$stationName: ${windSpeed}kt from ${windDir}°$gustStr');
  }
}
```

## Key Fields Reference

| Field | Type | Units | Description |
|-------|------|-------|-------------|
| `icaoId` | String | - | ICAO station identifier |
| `name` | String | - | Station name and location |
| `lat` | Double | degrees | Latitude |
| `lon` | Double | degrees | Longitude |
| `elev` | Integer | meters | Elevation |
| `wdir` | Integer | degrees | Wind direction (0-360) |
| `wspd` | Integer | knots | Wind speed |
| `wgst` | Integer | knots | Wind gust (only present if gusts reported) |
| `temp` | Integer | °C | Temperature |
| `altim` | Integer | hPa | QNH pressure |
| `fltCat` | String | - | VFR/MVFR/IFR/LIFR |

## Notes

- METAR updates typically every 30 minutes (at :20 and :50 past the hour for most stations)
- Use `reportTime` to check data freshness
- Calm winds: `wdir` and `wspd` fields may be absent
- Variable winds: `wdir` may show average or be absent
- No API key required
