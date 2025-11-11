# Map options

WHich provider shoudl we use for satelite maps 

  | Provider    | Cost               | Max Zoom | Update Frequency | Coverage |
  |-------------|--------------------|----------|------------------|----------|
  | Google      | Free*              | 20-22    | Frequent         | Global   |
  | Mapbox      | $0.60/1k after 50k | 22       | Regular          | Global   |
  | Esri/ArcGIS | Free*              | 19-20    | Moderate         | Global   |
  | Bing        | Free up to 125k/yr | 19-21    | Regular          | Global   |
  | MapTiler    | $25/mo after 100k  | 20       | Regular          | Global   |
  | Sentinel-2  | Free               | 14-15    | Annual           | Global   |
  | USGS        | Free               | 16-19    | Varies           | US only  |

  *Free for non-commercial use

  Recommendation:

  For a paragliding app, I'd suggest offering:
  1. Primary: Google Satellite (current) - best quality and zoom
  2. Alternative: Esri World Imagery - free, good quality, reliable
  3. Fallback: OpenStreetMap (current street view) - always available

Remember what was last used across session. 

  | Parameter       | OpenStreetMap              | Sentinel-2              | Bing Maps Aerial   |
  |-----------------|----------------------------|-------------------------|--------------------|
  | Data Source     | OSM Community              | ESA Satellite           | Microsoft          |
  | Type            | Street Map                 | Satellite               | Aerial + Labels    |
  | Resolution      | 18 zoom levels             | 10m                     | Variable           |
  | URL             | {s}.tile.openstreetmap.org | Cesium Ion Asset 3954   | Cesium Ion Asset 3 |
  | Subdomains      | a, b, c                    | N/A                     | N/A                |
  | Max Zoom        | 18                         | Ion default             | Ion default        |
  | Cost            | Free                       | Free (Ion quota)        | Free (Ion quota)   |
  | Color Tuning    | None                       | Saturation/Hue/Contrast | None               |
  | Terrain Shadows | Enabled                    | Disabled                | Disabled           |
  | Fallback        | Primary fallback           | Falls back to OSM       | Falls back to OSM  |
  | Credit          | © OpenStreetMap            | Cesium Ion              | Cesium Ion         |

  | Parameter  | OpenStreetMap | Sentinel-2 | Bing Maps Aerial |
  |------------|---------------|------------|------------------|
  | Brightness | 1.0 (default) | 0.95       | 1.0 (default)    |
  | Contrast   | 1.0 (default) | 1.15       | 1.0 (default)    |
  | Saturation | 1.0 (default) | 0.55       | 1.0 (default)    |
  | Hue        | 0.0 (default) | -0.09      | 0.0 (default)    |
  | Gamma      | 1.0 (default) | 1.25       | 1.0 (default)    |

Scene-level settings (all providers):

- Scene gamma: 1.8 (brightens overall scene)
- Atmosphere brightness: +0.3
- Atmosphere saturation: -0.1