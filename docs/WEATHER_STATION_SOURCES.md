# Weather Station Sources

Last updated: 2026-11-09

The app can show wind from seven station networks. This page is the short
overview. The code-level detail is in
[Weather Station APIs](api/WEATHER_STATIONS.md) and
[Adding Weather Providers](ADDING_WEATHER_PROVIDERS.md).

## The seven layers

| Layer | Network | Coverage | API key | How it loads |
|---|---|---|---|---|
| Aviation Weather Center | METAR airport reports | Airports worldwide | None | By viewport |
| NWS Observations | US National Weather Service | US only | None | By viewport |
| Holfuy | Launch-site wind stations | Worldwide | None | On tap |
| Pioupiou (OpenWindMap) | Community wind stations | Global | None | One global list |
| FFVL Beacons | French paragliding beacons | France | Free FFVL key | One global list |
| Bureau of Meteorology | Australian weather stations | Australia | None | By state |
| WU PWS | Weather Underground personal stations | Global | None (paused) | Point probe, then readings |

## What each one gives you

- **Aviation Weather Center** has the broadest free coverage. It reports
  airport wind from METAR. Airports are often far from a launch.
- **NWS** is the same kind of data for the United States. It uses
  `api.weather.gov`.
- **Holfuy** has about 1,500 stations, many at paragliding launches. The app
  reads one station only when you tap its marker.
- **Pioupiou** has about 760 community stations. The app loads the whole list
  once, then filters it to the viewport.
- **FFVL** has about 650 beacons in France. It needs a free FFVL API key.
- **BOM** covers Australia. The app fetches only the states that overlap the
  view.
- **WU PWS** is the only layer with a shared key and point-based discovery.
  See the next section.

## The WU PWS layer (paused)

The shared key was rejected with **HTTP 401** on 2026-11-09. A 401 means the key is
rejected, not rate limited, which returns 429. The app labels 401 as "throttled", so its
message is misleading.

The source is now unused. The key is removed from `env.json` and from CI. The provider
reports itself unconfigured through `WeatherUndergroundPwsProvider.awaitingValidKey`, so
the service skips it. The map filter shows its checkbox disabled with
"Unavailable - no valid API key".

To restore the layer, set `awaitingValidKey` to `false`, add a valid key to `env.json`,
and enable the layer in the filter. The other six layers keep working in the meantime.

## If you need a global personal-station layer

- **Synoptic Data** aggregates CWOP, RAWS and many mesonets. Its
  `stations/latest` service supports radius and bounding-box requests. Free
  permanent access is through the Open Access program for public,
  non-commercial use. Otherwise access is a trial and then paid.
- **aprs.fi** offers a free key for free public apps. It returns CWOP/APRS
  weather, but only by station name. It has no area search, so it cannot drive
  map discovery.
- **Open-Meteo** is free and keyless, but it returns model forecasts, not
  station observations. It cannot replace the WU PWS layer.

## Turning layers on and off

The map filter dialog has a checkbox for each layer. The app reads each choice
from `SharedPreferences`. Station fetches start at zoom 10 or higher. The
service merges all enabled layers and drops duplicates within 150 m.

## Related documentation

- [Weather Station APIs](api/WEATHER_STATIONS.md) - per-provider implementation
  and caching
- [PWS Station Discovery](PWS_STATION_DISCOVERY.md) - WU discovery design
- [Adding Weather Providers](ADDING_WEATHER_PROVIDERS.md) - how to add a source
