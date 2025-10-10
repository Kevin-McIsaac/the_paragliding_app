# NWS Weather Station Coverage - Geographic Bounding Boxes
# All coordinates in WGS84 (EPSG:4326) format: [min_lon, min_lat, max_lon, max_lat]
# Based on US Census 2017 data and geographic extents

nws_bounding_boxes = {
    # Continental United States (CONUS)covering all lower 48 states
    "CONUS": {
        "name": "Continental United States",
        "bbox": [-125.0, 24.5, -66.9, 49.6],
        "description": "Lower 48 states plus DC"
    },
    
    # Alaska
    "Alaska": {
        "name": "Alaska",
        "bbox": [-179.148909, 51.214183, 179.77847, 71.365162],
        "description": "Includes Aleutian Islands crossing 180° meridian",
        "note": "Crosses International Date Line - spans from ~179°W to ~180°E"
    },
    
    # Hawaii
    "Hawaii": {
        "name": "Hawaii",
        "bbox": [-178.334698, 18.910361, -154.806773, 28.402123],
        "description": "All Hawaiian Islands including Northwestern Hawaiian Islands"
    },
    
    # Puerto Rico & US Virgin Islands
    "Puerto_Rico": {
        "name": "Puerto Rico",
        "bbox": [-67.945404, 17.88328, -65.220703, 18.515683],
        "description": "Main island of Puerto Rico"
    },
    
    "US_Virgin_Islands": {
        "name": "US Virgin Islands",
        "bbox": [-65.085452, 17.673976, -64.564907, 18.412655],
        "description": "St. Thomas, St. John, St. Croix"
    },
    
    # Combined Caribbean region
    "Caribbean": {
        "name": "Puerto Rico & US Virgin Islands Combined",
        "bbox": [-67.945404, 17.673976, -64.564907, 18.515683],
        "description": "Combined bounding box for Caribbean territories"
    },
    
    # Pacific Territories
    "Guam": {
        "name": "Guam",
        "bbox": [144.618068, 13.234189, 144.956712, 13.654383],
        "description": "Territory of Guam"
    },
    
    "Northern_Mariana_Islands": {
        "name": "Northern Mariana Islands",
        "bbox": [144.886331, 14.110472, 146.064818, 20.553802],
        "description": "Commonwealth including Saipan, Tinian, Rota"
    },
    
    "American_Samoa": {
        "name": "American Samoa",
        "bbox": [-171.089874, -14.548699, -168.1433, -11.046934],
        "description": "Territory in South Pacific"
    },
    
}