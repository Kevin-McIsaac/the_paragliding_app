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
