#!/bin/bash

# Fetch worldwide PGE sites with altitude and country
echo "Fetching PGE sites worldwide..."

# Ensure assets/data directory exists
mkdir -p assets/data

# Get all sites from PGE API (no limit, no style parameter)
curl -s "http://www.paraglidingearth.com/api/geojson/getBoundingBoxSites.php?north=90&south=-90&west=-180&east=180" -o /tmp/pge_sites_raw.json

# Extract to CSV with fields matching PGE schema plus altitude, country, and last_edit
echo "id,name,longitude,latitude,altitude,country,wind_n,wind_ne,wind_e,wind_se,wind_s,wind_sw,wind_w,wind_nw,last_edit" > /tmp/pge_sites_full.csv

# Parse JSON and extract required fields including last_edit timestamp
jq -r '.features[] |
  [
    .properties.pge_site_id,
    .properties.name,
    .geometry.coordinates[0],
    .geometry.coordinates[1],
    ((.properties.takeoff_altitude // "0") | if . == "" then 0 else tonumber | floor end),  # altitude as integer
    (.properties.countryCode // ""),
    ((.properties.N // "0") | if . == "" then 0 else tonumber end),
    ((.properties.NE // "0") | if . == "" then 0 else tonumber end),
    ((.properties.E // "0") | if . == "" then 0 else tonumber end),
    ((.properties.SE // "0") | if . == "" then 0 else tonumber end),
    ((.properties.S // "0") | if . == "" then 0 else tonumber end),
    ((.properties.SW // "0") | if . == "" then 0 else tonumber end),
    ((.properties.W // "0") | if . == "" then 0 else tonumber end),
    ((.properties.NW // "0") | if . == "" then 0 else tonumber end),
    (.properties.last_edit // "")  # last_edit as date string (YYYY-MM-DD)
  ] | @csv' /tmp/pge_sites_raw.json >> /tmp/pge_sites_full.csv

# Verify counts match
JSON_COUNT=$(jq '.features | length' /tmp/pge_sites_raw.json)
CSV_COUNT=$(($(wc -l < /tmp/pge_sites_full.csv) - 1))  # Subtract header line

if [ "$JSON_COUNT" -ne "$CSV_COUNT" ]; then
  echo "ERROR: Count mismatch! JSON has $JSON_COUNT sites but CSV has $CSV_COUNT sites"
  echo "Some sites failed to process. Check for sites with invalid data."
  exit 1
fi

echo "Success: Processed $CSV_COUNT sites from JSON to CSV"

# Compress and save to assets/data directory
gzip -c /tmp/pge_sites_full.csv > assets/data/world_sites_extracted.csv.gz

# Clean up intermediate files
#rm -f /tmp/pge_sites_raw.json /tmp/pge_sites_full.csv

echo "Done! Created assets/data/world_sites_extracted.csv.gz with $(zcat assets/data/world_sites_extracted.csv.gz | wc -l) sites"
