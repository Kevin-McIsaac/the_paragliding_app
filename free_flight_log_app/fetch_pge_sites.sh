#!/bin/bash

# Fetch worldwide PGE sites with altitude and country
echo "Fetching PGE sites worldwide..."

# Ensure assets/data directory exists
mkdir -p assets/data

# Get all sites from PGE API (no limit, no style parameter)
curl -s "http://www.paraglidingearth.com/api/geojson/getBoundingBoxSites.php?north=90&south=-90&west=-180&east=180" -o /tmp/pge_sites_raw.json

# Extract to CSV with fields matching PGE schema plus altitude and country
echo "id,name,longitude,latitude,altitude,country,wind_n,wind_ne,wind_e,wind_se,wind_s,wind_sw,wind_w,wind_nw" > /tmp/pge_sites_full.csv

# Parse JSON and extract required fields
jq -r '.features[] |
  [
    .properties.pge_site_id,
    .properties.name,
    .geometry.coordinates[0],
    .geometry.coordinates[1],
    ((.properties.takeoff_altitude // "0") | tonumber | floor),  # altitude as integer
    (.properties.countryCode // ""),
    ((.properties.N // "0") | tonumber),
    ((.properties.NE // "0") | tonumber),
    ((.properties.E // "0") | tonumber),
    ((.properties.SE // "0") | tonumber),
    ((.properties.S // "0") | tonumber),
    ((.properties.SW // "0") | tonumber),
    ((.properties.W // "0") | tonumber),
    ((.properties.NW // "0") | tonumber)
  ] | @csv' /tmp/pge_sites_raw.json >> /tmp/pge_sites_full.csv

# Compress and save to assets/data directory
gzip -c /tmp/pge_sites_full.csv > assets/data/world_sites_extracted.csv.gz

# Clean up intermediate files
rm -f /tmp/pge_sites_raw.json /tmp/pge_sites_full.csv

echo "Done! Created assets/data/world_sites_extracted.csv.gz with $(zcat assets/data/world_sites_extracted.csv.gz | wc -l) sites"