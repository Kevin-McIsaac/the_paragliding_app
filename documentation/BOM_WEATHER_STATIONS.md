# BOM (Bureau of Meteorology) Weather Stations

This document describes the Australian Bureau of Meteorology (BOM) weather station XML data format and HTTP access methods for integrating real-time weather observations into The Paragliding App.

## Overview

The BOM provides free, real-time weather observations from Automatic Weather Stations (AWS) across Australia via XML files updated every 10 minutes. The data includes wind speed, wind direction, wind gusts, temperature, pressure, and other meteorological observations critical for flight planning.

**Key Features:**
- ✅ **Free HTTP access** - No API key required
- ✅ **Real-time data** - Updates every 10 minutes (x:00, x:10, x:20, x:30, x:40, x:50)
- ✅ **Comprehensive coverage** - Hundreds of stations across all Australian states
- ✅ **Aviation-grade data** - Many stations at airports and airfields
- ✅ **Rich metadata** - Station coordinates, elevation, timezone, type
- ✅ **Wind data in km/h** - No conversion needed for paragliding use

## HTTP Access (Recommended)

### Base URLs by State

BOM provides **HTTP access** to XML observation files - **no FTP client needed**:

| State/Territory | Product ID | HTTP URL | Approx. Stations |
|----------------|-----------|----------|-----------------|
| **Western Australia** | IDW60920 | `http://reg.bom.gov.au/fwo/IDW60920.xml` | ~150 |
| **New South Wales** | IDN60920 | `http://reg.bom.gov.au/fwo/IDN60920.xml` | ~200 |
| **Victoria** | IDV60920 | `http://reg.bom.gov.au/fwo/IDV60920.xml` | ~120 |
| **Queensland** | IDQ60920 | `http://reg.bom.gov.au/fwo/IDQ60920.xml` | ~180 |
| **South Australia** | IDS60920 | `http://reg.bom.gov.au/fwo/IDS60920.xml` | ~100 |
| **Tasmania** | IDT60920 | `http://reg.bom.gov.au/fwo/IDT60920.xml` | ~50 |
| **Northern Territory** | IDD60920 | `http://reg.bom.gov.au/fwo/IDD60920.xml` | ~60 |
| **Australian Capital Territory** | IDN60920 | Included in NSW file | ~10 |

### Alternative Access Methods

**FTP Access (if needed):**
```
ftp://ftp.bom.gov.au/anon/gen/fwo/IDW60920.xml
```

**Note:** HTTP is recommended for Flutter integration as it works with the standard `http` package without requiring additional FTP client libraries.

### Update Frequency

- **Updates:** Every 10 minutes at x:00, x:10, x:20, x:30, x:40, x:50
- **Latency:** 2-3 minutes after observation time
- **Consistency:** File URLs never change (allows for direct addressing)

### Example HTTP Request

```bash
curl -s "http://reg.bom.gov.au/fwo/IDW60920.xml" \
  -H "Accept: text/xml" \
  -H "User-Agent: TheParaglidingApp/1.0"
```

**Response:** XML document (~400KB for WA, varies by state)

## XML Structure

### Document Root

```xml
<?xml version="1.0"?>
<product xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         version="v1.7.1"
         xsi:noNamespaceSchemaLocation="http://www.bom.gov.au/schema/v1.7/product.xsd">
  <amoc>...</amoc>
  <observations>...</observations>
</product>
```

### Metadata Section (`<amoc>`)

Contains document-level metadata:

```xml
<amoc>
  <source>
    <sender>Australian Government Bureau of Meteorology</sender>
    <region>Western Australia</region>
    <office>WARO</office>
    <copyright>http://www.bom.gov.au/other/copyright.shtml</copyright>
    <disclaimer>http://www.bom.gov.au/other/disclaimer.shtml</disclaimer>
  </source>
  <identifier>IDW60920</identifier>
  <issue-time-utc>2025-10-27T22:41:02+00:00</issue-time-utc>
  <issue-time-local tz="WST">2025-10-28T06:41:02+08:00</issue-time-local>
  <sent-time>2025-10-27T22:43:06+00:00</sent-time>
  <status>O</status>
</amoc>
```

**Key Fields:**
- `identifier`: Product ID (e.g., IDW60920)
- `issue-time-utc`: When observations were issued (UTC)
- `issue-time-local`: Local time with timezone
- `region`: State/territory name

### Station Structure (`<station>`)

Each station element contains rich metadata and observation data:

```xml
<station wmo-id="94608"
         bom-id="009225"
         tz="Australia/Perth"
         stn-name="PERTH METRO"
         stn-height="24.90"
         type="AWS"
         lat="-31.9192"
         lon="115.8728"
         forecast-district-id="WA_PW009"
         description="Perth">
  <period index="0"
          time-utc="2025-10-27T22:40:00+00:00"
          time-local="2025-10-28T06:40:00+08:00"
          wind-src="OMD">
    <level index="0" type="surface">
      <element units="km/h" type="wind_spd_kmh">9</element>
      <element units="deg" type="wind_dir_deg">56</element>
      <element units="km/h" type="gust_kmh">13</element>
      <!-- Additional weather elements... -->
    </level>
  </period>
</station>
```

### Station Attributes

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| `wmo-id` | String | WMO station identifier | "94608" |
| `bom-id` | String | BOM internal station ID | "009225" |
| `stn-name` | String | Station name (uppercase) | "PERTH METRO" |
| `lat` | Float | Latitude (decimal degrees) | "-31.9192" |
| `lon` | Float | Longitude (decimal degrees) | "115.8728" |
| `stn-height` | Float | Elevation above sea level (meters) | "24.90" |
| `type` | String | Station type | "AWS", "PAWS" |
| `tz` | String | IANA timezone | "Australia/Perth" |
| `description` | String | Location description | "Perth" |
| `forecast-district-id` | String | BOM forecast district | "WA_PW009" |

**Station Types:**
- `AWS` - Automatic Weather Station (permanent)
- `PAWS` - Portable Automatic Weather Station (temporary)

### Period (Observation Time)

The `<period>` element contains observation timestamp and source:

```xml
<period index="0"
        time-utc="2025-10-27T22:40:00+00:00"
        time-local="2025-10-28T06:40:00+08:00"
        wind-src="OMD">
```

**Attributes:**
- `index="0"` - Most recent observation (always 0)
- `time-utc` - Observation time in UTC (ISO 8601)
- `time-local` - Observation time in local timezone (ISO 8601)
- `wind-src` - Wind measurement source code

**Wind Source Codes:**
- `OMD` - One Minute Data (most common)
- `AWS` - Automatic Weather Station average
- Other codes may indicate different averaging periods

### Weather Elements

Each observation element has a `type` attribute and optional `units`:

#### Wind Data (Primary Interest for Paragliding)

| Element Type | Units | Description | Typical Range |
|-------------|-------|-------------|---------------|
| `wind_spd_kmh` | km/h | Current wind speed | 0-80 |
| `wind_dir_deg` | deg | Wind direction (meteorological) | 0-360 |
| `wind_dir` | - | Cardinal direction | "N", "NE", "E", etc. |
| `gust_kmh` | km/h | Current gust speed | 0-120 |
| `wind_gust_spd` | knots | Gust speed (knots) | 0-65 |

**Note:** Wind direction is **meteorological** (direction wind is coming FROM), not heading.

#### Additional Weather Elements

| Element Type | Units | Description |
|-------------|-------|-------------|
| `air_temperature` | Celsius | Air temperature |
| `apparent_temp` | Celsius | Feels-like temperature |
| `dew_point` | Celsius | Dew point temperature |
| `rel-humidity` | % | Relative humidity |
| `pres` | hPa | Station pressure |
| `qnh_pres` | hPa | QNH pressure (aviation) |
| `msl_pres` | hPa | Mean sea level pressure |
| `rainfall` | mm | Rainfall accumulation |
| `vis_km` | km | Visibility |
| `cloud` | - | Cloud conditions |
| `delta_t` | Celsius | Temperature-dewpoint spread |

### Missing/Unavailable Data

When a sensor is unavailable or data is missing:
- Element may be absent entirely
- Element may exist but have no text content: `<element type="wind_spd_kmh"/>`
- Text content may be empty string

**Handling Strategy:**
```dart
final windSpeedText = element.text;
final windSpeed = windSpeedText != null && windSpeedText.isNotEmpty
    ? double.tryParse(windSpeedText)
    : null;
```

## Data Examples

### Example 1: Coastal Station with Wind

```xml
<station wmo-id="94608" bom-id="009225" tz="Australia/Perth"
         stn-name="PERTH METRO" stn-height="24.90" type="AWS"
         lat="-31.9192" lon="115.8728">
  <period index="0" time-utc="2025-10-27T22:40:00+00:00"
          time-local="2025-10-28T06:40:00+08:00" wind-src="OMD">
    <level index="0" type="surface">
      <element units="km/h" type="wind_spd_kmh">9</element>
      <element units="deg" type="wind_dir_deg">56</element>
      <element type="wind_dir">NE</element>
      <element units="km/h" type="gust_kmh">13</element>
      <element units="Celsius" type="air_temperature">18.7</element>
      <element units="hPa" type="qnh_pres">1012.7</element>
    </level>
  </period>
</station>
```

**Parsed Output:**
- Station: PERTH METRO
- Location: -31.9192°, 115.8728° (24.9m elevation)
- Time: 2025-10-28 06:40 AWST (UTC+8)
- Wind: 9 km/h from NE (56°)
- Gusts: 13 km/h
- Temperature: 18.7°C
- QNH: 1012.7 hPa

### Example 2: Airport Station

```xml
<station wmo-id="94610" bom-id="009021" tz="Australia/Perth"
         stn-name="PERTH AIRPORT" stn-height="15.40" type="AWS"
         lat="-31.9275" lon="115.9764">
  <period index="0" time-utc="2025-10-27T22:40:00+00:00"
          time-local="2025-10-28T06:40:00+08:00" wind-src="OMD">
    <level index="0" type="surface">
      <element units="km/h" type="wind_spd_kmh">28</element>
      <element units="deg" type="wind_dir_deg">61</element>
      <element type="wind_dir">ENE</element>
      <element units="km/h" type="gust_kmh">32</element>
      <element units="Celsius" type="air_temperature">17.2</element>
      <element units="%" type="rel-humidity">42</element>
      <element units="km" type="vis_km">40</element>
    </level>
  </period>
</station>
```

### Example 3: Station with Missing Wind Data

```xml
<station wmo-id="99200" bom-id="503621" tz="Australia/Perth"
         stn-name="ESPERANCE NTC AWS" stn-height="12.50" type="AWS"
         lat="-33.8707" lon="121.8971">
  <period index="0" time-utc="2025-10-27T22:40:00+00:00"
          time-local="2025-10-28T06:40:00+08:00">
    <level index="0" type="surface">
      <element units="Celsius" type="air_temperature">15.3</element>
      <element units="hPa" type="qnh_pres">1015.2</element>
      <!-- No wind elements present -->
    </level>
  </period>
</station>
```

**Note:** Wind data missing - station may be temporarily offline or sensors malfunctioning.

## Parsing Strategy

### Python Example (Command Line Testing)

```python
import xml.etree.ElementTree as ET

tree = ET.parse('IDW60920.xml')
root = tree.getroot()

stations = []

for station in root.findall('.//station'):
    # Station metadata
    station_data = {
        'name': station.get('stn-name'),
        'bom_id': station.get('bom-id'),
        'latitude': float(station.get('lat')),
        'longitude': float(station.get('lon')),
        'elevation_m': float(station.get('stn-height')),
        'timezone': station.get('tz'),
        'type': station.get('type'),
    }

    # Observation data
    period = station.find('.//period[@index="0"]')
    if period is not None:
        station_data['time_utc'] = period.get('time-utc')
        station_data['time_local'] = period.get('time-local')

        # Extract wind elements
        for element in period.findall('.//element'):
            elem_type = element.get('type')
            if elem_type == 'wind_spd_kmh' and element.text:
                station_data['wind_speed_kmh'] = float(element.text)
            elif elem_type == 'wind_dir_deg' and element.text:
                station_data['wind_direction_deg'] = float(element.text)
            elif elem_type == 'gust_kmh' and element.text:
                station_data['wind_gust_kmh'] = float(element.text)
            elif elem_type == 'air_temperature' and element.text:
                station_data['temperature_c'] = float(element.text)

    stations.append(station_data)
```

### Flutter/Dart Integration

**Package Requirements:**
```yaml
dependencies:
  http: ^1.1.0
  xml: ^6.3.0
```

**Service Implementation:**
```dart
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class BomWeatherProvider implements WeatherStationProvider {
  static const String _baseUrl = 'http://reg.bom.gov.au/fwo';

  Future<List<WeatherStation>> fetchStations(LatLngBounds bounds) async {
    // Determine which state(s) overlap with bounds
    final stateFiles = _determineStateFiles(bounds);

    final List<WeatherStation> allStations = [];

    for (final productId in stateFiles) {
      final url = '$_baseUrl/$productId.xml';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'text/xml',
          'User-Agent': 'TheParaglidingApp/1.0',
        },
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final stations = _parseXml(response.body, bounds);
        allStations.addAll(stations);
      }
    }

    return allStations;
  }

  List<WeatherStation> _parseXml(String xmlBody, LatLngBounds bounds) {
    final document = XmlDocument.parse(xmlBody);
    final stations = <WeatherStation>[];

    for (final stationNode in document.findAllElements('station')) {
      final lat = double.parse(stationNode.getAttribute('lat')!);
      final lon = double.parse(stationNode.getAttribute('lon')!);

      // Filter to bounding box
      if (!bounds.contains(LatLng(lat, lon))) continue;

      final period = stationNode.findElements('period')
          .where((e) => e.getAttribute('index') == '0')
          .firstOrNull;

      if (period == null) continue;

      // Extract wind data
      double? windSpeed, windDir, windGust;

      for (final element in period.findAllElements('element')) {
        final type = element.getAttribute('type');
        final text = element.text;

        if (text.isEmpty) continue;

        switch (type) {
          case 'wind_spd_kmh':
            windSpeed = double.tryParse(text);
          case 'wind_dir_deg':
            windDir = double.tryParse(text);
          case 'gust_kmh':
            windGust = double.tryParse(text);
        }
      }

      // Only include stations with wind data
      if (windSpeed == null && windDir == null) continue;

      stations.add(WeatherStation(
        id: stationNode.getAttribute('bom-id')!,
        name: stationNode.getAttribute('stn-name')!,
        latitude: lat,
        longitude: lon,
        elevation: double.parse(stationNode.getAttribute('stn-height')!),
        source: WeatherStationSource.bom,
        windSpeed: windSpeed,
        windDirection: windDir,
        windGust: windGust,
        observationTime: DateTime.parse(period.getAttribute('time-utc')!),
      ));
    }

    return stations;
  }

  List<String> _determineStateFiles(LatLngBounds bounds) {
    // Map bounding box to Australian states
    // WA: 113-129°E, 13-35°S
    // NSW/ACT: 141-154°E, 28-38°S
    // VIC: 141-150°E, 34-39°S
    // QLD: 138-154°E, 9-29°S
    // SA: 129-141°E, 26-38°S
    // TAS: 144-149°E, 40-44°S
    // NT: 129-138°E, 11-26°S

    final files = <String>[];

    // Simplified logic - check center point
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLon = (bounds.east + bounds.west) / 2;

    if (centerLon >= 113 && centerLon <= 129) files.add('IDW60920'); // WA
    if (centerLon >= 129 && centerLon <= 141) files.add('IDS60920'); // SA
    if (centerLon >= 129 && centerLon <= 138 && centerLat <= -11) files.add('IDD60920'); // NT
    if (centerLon >= 138 && centerLon <= 154 && centerLat >= -29) files.add('IDQ60920'); // QLD
    if (centerLon >= 141 && centerLon <= 154 && centerLat <= -28) files.add('IDN60920'); // NSW
    if (centerLon >= 141 && centerLon <= 150 && centerLat <= -34) files.add('IDV60920'); // VIC
    if (centerLon >= 144 && centerLon <= 149 && centerLat <= -40) files.add('IDT60920'); // TAS

    return files.isEmpty ? ['IDW60920'] : files; // Default to WA
  }
}
```

## State Bounding Box Reference

Approximate bounding boxes for determining which state files to fetch:

| State | Min Lon | Max Lon | Min Lat | Max Lat |
|-------|---------|---------|---------|---------|
| WA | 113.0 | 129.0 | -35.0 | -13.0 |
| NT | 129.0 | 138.0 | -26.0 | -11.0 |
| SA | 129.0 | 141.0 | -38.0 | -26.0 |
| QLD | 138.0 | 154.0 | -29.0 | -9.0 |
| NSW | 141.0 | 154.0 | -38.0 | -28.0 |
| VIC | 141.0 | 150.0 | -39.0 | -34.0 |
| TAS | 144.0 | 149.0 | -44.0 | -40.0 |
| ACT | 148.7 | 149.4 | -35.9 | -35.1 |

**Note:** Boundaries are approximate. For map views spanning multiple states, fetch multiple files and combine results.

## Caching Strategy

### Recommended Approach: State-Based Global Cache

Given the characteristics of BOM data:
- **Medium network size** (~150 stations per state)
- **Updates every 10 minutes** (relatively frequent)
- **State-level files** (not bbox API)
- **Australian coverage only** (regional focus)

**Strategy: State File Cache with Dual TTL**

```dart
class _StateCacheEntry {
  final List<WeatherStation> stations;
  final DateTime stationListTimestamp;    // Longer TTL
  final DateTime measurementsTimestamp;   // Shorter TTL
  final String productId;                 // IDW60920, IDN60920, etc.

  bool get stationListExpired =>
      DateTime.now().difference(stationListTimestamp) > Duration(hours: 6);

  bool get measurementsExpired =>
      DateTime.now().difference(measurementsTimestamp) > Duration(minutes: 10);
}

final Map<String, _StateCacheEntry> _stateCache = {};

Future<List<WeatherStation>> fetchStations(LatLngBounds bounds) async {
  final stateFiles = _determineStateFiles(bounds);
  final List<WeatherStation> allStations = [];

  for (final productId in stateFiles) {
    final cached = _stateCache[productId];

    // Check if we need to refresh
    if (cached != null && !cached.stationListExpired) {
      if (cached.measurementsExpired) {
        // Refresh measurements but keep station list
        await _refreshStateMeasurements(productId);
      }
      // Filter cached stations to bounds
      allStations.addAll(
        cached.stations.where((s) => bounds.contains(s.location))
      );
    } else {
      // Fetch fresh data
      final stations = await _fetchStateFile(productId);
      _stateCache[productId] = _StateCacheEntry(
        stations: stations,
        stationListTimestamp: DateTime.now(),
        measurementsTimestamp: DateTime.now(),
        productId: productId,
      );
      allStations.addAll(
        stations.where((s) => bounds.contains(s.location))
      );
    }
  }

  return allStations;
}
```

**Cache TTLs:**
- **Station metadata** (location, name, ID): 6 hours
  - Stations rarely move or change names
  - Medium refresh reduces API calls
- **Wind measurements**: 10 minutes
  - Matches BOM update frequency
  - Ensures timely data for flight decisions

**Memory footprint:** ~150 stations × 7 states × ~500 bytes = ~0.5 MB (acceptable)

## Performance Considerations

### File Sizes

| State | Typical Size | Stations | Parse Time |
|-------|-------------|----------|------------|
| WA | ~420 KB | ~150 | ~200-400ms |
| NSW | ~480 KB | ~200 | ~250-500ms |
| QLD | ~450 KB | ~180 | ~230-450ms |
| VIC | ~380 KB | ~120 | ~180-350ms |
| SA | ~320 KB | ~100 | ~150-300ms |
| TAS | ~180 KB | ~50 | ~100-200ms |
| NT | ~220 KB | ~60 | ~120-250ms |

**Optimization Tips:**
1. Only fetch state files overlapping the visible map bounds
2. Cache parsed station objects, not raw XML
3. Filter to bounding box during parsing (don't parse unnecessary stations)
4. Use `xml` package's streaming parser for very large files
5. Fetch multiple state files in parallel with `Future.wait()`

### Network Efficiency

```dart
// ✅ Good: Parallel fetching of multiple states
final futures = stateFiles.map((id) => _fetchStateFile(id));
final results = await Future.wait(futures);

// ❌ Bad: Sequential fetching
for (final id in stateFiles) {
  await _fetchStateFile(id);  // Blocks on each
}
```

## Terms of Use & Attribution

### Copyright

From BOM's copyright notice:
> Products in this service are covered by copyright. Apart from any fair dealing for the purposes of private study, research, criticism or review, as permitted under the Copyright Act, no part may be reproduced by any process or stored electronically without written permission.

### Commercial Use

From BOM data feeds page:
> Some products available from this service are free and not for commercial use.

**Interpretation:** For a free paragliding app (non-commercial), BOM data is likely acceptable under "fair dealing." For commercial versions or paid features, formal licensing may be required.

### Attribution Requirements

**Recommended attribution:**
```
Weather data provided by the Australian Bureau of Meteorology
http://www.bom.gov.au/
```

**Where to display:**
- About screen (mandatory)
- Weather station tooltips/popups (recommended)
- Settings screen (optional)

### Disclaimers

BOM requires users to acknowledge their disclaimer:
> http://www.bom.gov.au/other/disclaimer.shtml

**Key points:**
- Data provided "as is" without warranty
- Not guaranteed to be error-free or current
- Users assume all risk

**Implementation:** Link to BOM disclaimer from app's About screen.

## Integration Checklist

- [ ] Add `WeatherStationSource.bom` to enum
- [ ] Create `BomWeatherProvider` implementing `WeatherStationProvider` interface
- [ ] Implement state-based file fetching logic
- [ ] Implement XML parsing with `xml` package
- [ ] Handle missing/null wind data gracefully
- [ ] Implement state file cache with dual TTL (6hr/10min)
- [ ] Add bounding box to state file mapping
- [ ] Handle multi-state map views (fetch multiple files)
- [ ] Set appropriate timeout (30 seconds recommended)
- [ ] Add structured logging for debugging
- [ ] Include User-Agent header: `TheParaglidingApp/1.0`
- [ ] Add BOM attribution to About screen
- [ ] Link to BOM disclaimer
- [ ] Test with all Australian states
- [ ] Test with stations missing wind data
- [ ] Test cache refresh logic
- [ ] Verify wind direction is interpreted correctly (from, not to)

## Known Limitations

1. **Australia only** - No coverage outside Australian territories
2. **No historical data** - Only current observations (use separate API for historical)
3. **No forecasts** - Observations only (forecasts available via different BOM products)
4. **Coarse station network** - Sparse coverage in remote areas
5. **Manual updates** - Some stations update less frequently (check `time-utc`)
6. **Missing sensors** - Not all stations have all sensors (check for null)
7. **No station-specific queries** - Must download entire state file
8. **Large file sizes** - 180-480 KB per state (use caching aggressively)

## Testing API Endpoint

### Command Line (curl + Python)

**Table format:**
```bash
curl -s "http://reg.bom.gov.au/fwo/IDW60920.xml" | python3 -c "
import sys
import xml.etree.ElementTree as ET

tree = ET.parse(sys.stdin)
root = tree.getroot()

print('Station Name | Lat | Lon | Time (Local) | Wind (km/h) | Dir (deg) | Gust (km/h)')
print('-' * 100)

for station in root.findall('.//station'):
    name = station.get('stn-name')
    lat = station.get('lat')
    lon = station.get('lon')

    period = station.find('.//period[@index=\"0\"]')
    if period:
        time_local = period.get('time-local')

        wind_spd = wind_dir = wind_gust = None

        for element in period.findall('.//element'):
            elem_type = element.get('type')
            if elem_type == 'wind_spd_kmh':
                wind_spd = element.text or 'N/A'
            elif elem_type == 'wind_dir_deg':
                wind_dir = element.text or 'N/A'
            elif elem_type == 'gust_kmh':
                wind_gust = element.text or 'N/A'

        print(f'{name} | {lat} | {lon} | {time_local} | {wind_spd} | {wind_dir} | {wind_gust}')
"
```

**JSON format:**
```bash
curl -s "http://reg.bom.gov.au/fwo/IDW60920.xml" | python3 -c "
import sys, json, xml.etree.ElementTree as ET

tree = ET.parse(sys.stdin)
stations = []

for station in tree.getroot().findall('.//station'):
    period = station.find('.//period[@index=\"0\"]')
    if not period: continue

    data = {
        'name': station.get('stn-name'),
        'bom_id': station.get('bom-id'),
        'latitude': float(station.get('lat')),
        'longitude': float(station.get('lon')),
        'time_utc': period.get('time-utc'),
        'time_local': period.get('time-local'),
    }

    for element in period.findall('.//element'):
        elem_type = element.get('type')
        text = element.text
        if text:
            if elem_type == 'wind_spd_kmh':
                data['wind_speed_kmh'] = float(text)
            elif elem_type == 'wind_dir_deg':
                data['wind_direction_deg'] = float(text)
            elif elem_type == 'gust_kmh':
                data['wind_gust_kmh'] = float(text)

    if 'wind_speed_kmh' in data or 'wind_direction_deg' in data:
        stations.append(data)

print(json.dumps(stations[:5], indent=2))  # First 5 stations
"
```

## Related Documentation

- [Adding Weather Station Providers](../docs/ADDING_WEATHER_PROVIDERS.md) - Integration guide
- [BOM Data Feeds](http://www.bom.gov.au/catalogue/data-feeds.shtml) - Official BOM documentation
- [BOM Observations XML Spec](http://www.bom.gov.au/catalogue/Observations-XML.pdf) - XML format details
- [BOM Copyright](http://www.bom.gov.au/other/copyright.shtml) - Terms of use
- [BOM Disclaimer](http://www.bom.gov.au/other/disclaimer.shtml) - Liability disclaimer

## Support

For BOM data issues:
- **BOM Support:** http://www.bom.gov.au/other/contact.shtml
- **Data Feeds FAQ:** http://www.bom.gov.au/catalogue/data-feeds.shtml

For integration questions:
- Check existing weather providers: `lib/services/weather_providers/`
- Review [ADDING_WEATHER_PROVIDERS.md](../docs/ADDING_WEATHER_PROVIDERS.md)
