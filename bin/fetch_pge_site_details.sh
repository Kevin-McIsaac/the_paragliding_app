#!/bin/bash

# Fetch detailed PGE site data for given coordinates
# Usage: ./fetch_pge_site_details.sh <latitude> <longitude>

set -e

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <latitude> <longitude>"
    echo ""
    echo "Example:"
    echo "  $0 47.0986 11.3243  # Neustift - Elfer, Austria"
    echo ""
    exit 1
fi

LAT="$1"
LNG="$2"

# Validate coordinates are numeric
if ! [[ "$LAT" =~ ^-?[0-9]+\.?[0-9]*$ ]] || ! [[ "$LNG" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
    echo "Error: Latitude and longitude must be numeric values"
    exit 1
fi

# Validate coordinate ranges (using awk instead of bc)
LAT_VALID=$(awk -v lat="$LAT" 'BEGIN { print (lat >= -90 && lat <= 90) ? 1 : 0 }')
if [ "$LAT_VALID" -eq 0 ]; then
    echo "Error: Latitude must be between -90 and 90"
    exit 1
fi

LNG_VALID=$(awk -v lng="$LNG" 'BEGIN { print (lng >= -180 && lng <= 180) ? 1 : 0 }')
if [ "$LNG_VALID" -eq 0 ]; then
    echo "Error: Longitude must be between -180 and 180"
    exit 1
fi

echo "Fetching detailed site data for coordinates: $LAT, $LNG"
echo "API: https://www.paragliding.earth/api/getAroundLatLngSites.php"
echo ""

# Construct URL (matching app parameters exactly)
URL="https://www.paragliding.earth/api/getAroundLatLngSites.php?lat=${LAT}&lng=${LNG}&distance=0.01&limit=1&style=detailled"

# Fetch data
RESPONSE=$(curl -s "$URL")

# Check if response is empty
if [ -z "$RESPONSE" ]; then
    echo "Error: Empty response from API"
    exit 1
fi

# Check for error in response
if echo "$RESPONSE" | grep -q "error"; then
    echo "Error in API response:"
    echo "$RESPONSE"
    exit 1
fi

# Output raw XML
echo "=== RAW XML RESPONSE ==="
echo "$RESPONSE"
echo ""

# Try to pretty-print if xmllint is available
if command -v xmllint &> /dev/null; then
    echo "=== FORMATTED XML ==="
    echo "$RESPONSE" | xmllint --format -
    echo ""
fi

# Extract key information
echo "=== EXTRACTED INFORMATION ==="

# Site name
SITE_NAME=$(echo "$RESPONSE" | grep -oP '(?<=<name>).*?(?=</name>)' | head -1)
echo "Site: $SITE_NAME"

# Country
COUNTRY=$(echo "$RESPONSE" | grep -oP '(?<=<countryCode>).*?(?=</countryCode>)')
if [ -n "$COUNTRY" ]; then
    echo "Country: $COUNTRY"
fi

# Takeoff altitude
TAKEOFF_ALT=$(echo "$RESPONSE" | grep -oP '(?<=<takeoff_altitude>).*?(?=</takeoff_altitude>)')
if [ -n "$TAKEOFF_ALT" ]; then
    echo "Takeoff Altitude: ${TAKEOFF_ALT}m"
fi

# Takeoff description
TAKEOFF_DESC=$(echo "$RESPONSE" | grep -oP '(?<=<takeoff_description>).*?(?=</takeoff_description>)')
if [ -n "$TAKEOFF_DESC" ]; then
    echo "Takeoff Description: $TAKEOFF_DESC"
fi

# Landing altitude
LANDING_ALT=$(echo "$RESPONSE" | grep -oP '(?<=<landing_altitude>).*?(?=</landing_altitude>)')
if [ -n "$LANDING_ALT" ]; then
    echo "Landing Altitude: ${LANDING_ALT}m"
fi

# Landing coordinates
LANDING_LAT=$(echo "$RESPONSE" | grep -oP '(?<=<landing_lat>).*?(?=</landing_lat>)')
LANDING_LNG=$(echo "$RESPONSE" | grep -oP '(?<=<landing_lng>).*?(?=</landing_lng>)')
if [ -n "$LANDING_LAT" ] && [ -n "$LANDING_LNG" ]; then
    echo "Landing Coordinates: $LANDING_LAT, $LANDING_LNG"
fi

# Landing description
LANDING_DESC=$(echo "$RESPONSE" | grep -oP '(?<=<landing_description>).*?(?=</landing_description>)')
if [ -n "$LANDING_DESC" ]; then
    echo "Landing Description: $LANDING_DESC"
fi

# Wind orientations
echo ""
echo "Wind Orientations:"
for DIR in N NE E SE S SW W NW; do
    VAL=$(echo "$RESPONSE" | grep -oP "(?<=<$DIR>).*?(?=</$DIR>)")
    if [ -n "$VAL" ] && [ "$VAL" != "0" ]; then
        echo "  $DIR: $VAL"
    fi
done

# Flight rules
RULES=$(echo "$RESPONSE" | grep -oP '(?<=<flight_rules>).*?(?=</flight_rules>)')
if [ -n "$RULES" ]; then
    echo ""
    echo "Flight Rules: $RULES"
fi

# Access instructions
ACCESS=$(echo "$RESPONSE" | grep -oP '(?<=<going_there>).*?(?=</going_there>)')
if [ -n "$ACCESS" ]; then
    echo ""
    echo "Access: $ACCESS"
fi

# Comments
COMMENTS=$(echo "$RESPONSE" | grep -oP '(?<=<comments>).*?(?=</comments>)')
if [ -n "$COMMENTS" ]; then
    echo ""
    echo "Comments: $COMMENTS"
fi

# PGE site ID
PGE_ID=$(echo "$RESPONSE" | grep -oP '(?<=<pge_site_id>).*?(?=</pge_site_id>)')
if [ -n "$PGE_ID" ]; then
    echo ""
    echo "PGE Site ID: $PGE_ID"
    echo "PGE Link: http://www.paraglidingearth.com/?site=$PGE_ID"
fi

echo ""
echo "Done!"
