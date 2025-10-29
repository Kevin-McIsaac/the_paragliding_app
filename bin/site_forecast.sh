#!/bin/bash

# site_forecast.sh
# Look up a paragliding site and display its 7-day weather forecast
# Usage: ./site_forecast.sh "Site Name"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check dependencies
for cmd in curl jq awk; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd is required but not installed.${NC}" >&2
        exit 1
    fi
done

# Check arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 \"Site Name\""
    echo "Example: $0 \"Planai\""
    exit 1
fi

SITE_NAME="$1"

# URL encode the site name
ENCODED_NAME=$(echo -n "$SITE_NAME" | jq -sRr @uri)

echo -e "${BLUE}Searching for site: ${YELLOW}$SITE_NAME${NC}\n"

# Step 1: Search for site in ParaglidingEarth
SEARCH_URL="https://paraglidingearth.com/assets/ajax/searchSitesJSON.php?name=$ENCODED_NAME"

SEARCH_RESPONSE=$(curl -s "$SEARCH_URL" -H "User-Agent: TheParaglidingApp/1.0")

if [ -z "$SEARCH_RESPONSE" ]; then
    echo -e "${RED}Error: No response from ParaglidingEarth API${NC}" >&2
    exit 1
fi

# Check if any sites were found
SITE_COUNT=$(echo "$SEARCH_RESPONSE" | jq -r '.features | length' 2>/dev/null || echo "0")

if [ "$SITE_COUNT" -eq 0 ]; then
    echo -e "${RED}Error: No sites found matching '$SITE_NAME'${NC}" >&2
    exit 1
fi

# Get first matching site
SITE_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.features[0].id')
SITE_FULL_NAME=$(echo "$SEARCH_RESPONSE" | jq -r '.features[0].name')
LATITUDE=$(echo "$SEARCH_RESPONSE" | jq -r '.features[0].lat')
LONGITUDE=$(echo "$SEARCH_RESPONSE" | jq -r '.features[0].lng')
COUNTRY_CODE=$(echo "$SEARCH_RESPONSE" | jq -r '.features[0].countryCode // "unknown"')

# Validate coordinates
if [ "$LATITUDE" == "null" ] || [ "$LONGITUDE" == "null" ]; then
    echo -e "${RED}Error: Could not extract coordinates from site data${NC}" >&2
    exit 1
fi

# Display site information
echo -e "${GREEN}Site Found:${NC}"
echo -e "  Name:        $SITE_FULL_NAME"
echo -e "  Country:     $COUNTRY_CODE"
echo -e "  Site ID:     $SITE_ID"
echo -e "  Coordinates: ${YELLOW}$LATITUDE, $LONGITUDE${NC}"
echo ""

# Step 2: Fetch 7-day weather forecast from Open-Meteo
echo -e "${BLUE}Fetching 7-day weather forecast...${NC}\n"

FORECAST_URL="https://api.open-meteo.com/v1/forecast?latitude=$LATITUDE&longitude=$LONGITUDE&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation&wind_speed_unit=kmh&forecast_days=7&timezone=auto"

FORECAST_RESPONSE=$(curl -s "$FORECAST_URL")

if [ -z "$FORECAST_RESPONSE" ]; then
    echo -e "${RED}Error: No response from Open-Meteo API${NC}" >&2
    exit 1
fi

# Extract timezone for display
TIMEZONE=$(echo "$FORECAST_RESPONSE" | jq -r '.timezone // "UTC"')

# Extract hourly data
TIMES=($(echo "$FORECAST_RESPONSE" | jq -r '.hourly.time[]'))
WIND_SPEEDS=($(echo "$FORECAST_RESPONSE" | jq -r '.hourly.wind_speed_10m[] // 0'))
WIND_DIRS=($(echo "$FORECAST_RESPONSE" | jq -r '.hourly.wind_direction_10m[] // 0'))
GUSTS=($(echo "$FORECAST_RESPONSE" | jq -r '.hourly.wind_gusts_10m[] // 0'))
PRECIP=($(echo "$FORECAST_RESPONSE" | jq -r '.hourly.precipitation[] // 0'))

# Function to convert wind direction degrees to cardinal direction
deg_to_cardinal() {
    local deg=$1
    local val=$(awk "BEGIN {printf \"%d\", ($deg + 22.5) / 45}")
    local directions=("N" "NE" "E" "SE" "S" "SW" "W" "NW")
    local idx=$((val % 8))
    echo "${directions[$idx]}"
}

# Display forecast
echo -e "${GREEN}7-Day Hourly Wind Forecast (${TIMEZONE}):${NC}"
echo -e "${GREEN}Flying Hours: 07:00 - 19:00${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}\n"

# Process 7 days
for day in {0..6}; do
    start_idx=$((day * 24))

    # Get date from first timestamp of the day
    if [ $start_idx -lt ${#TIMES[@]} ]; then
        DATE=$(echo "${TIMES[$start_idx]}" | cut -d'T' -f1)

        echo -e "${YELLOW}Day $((day + 1)) - $DATE${NC}"
        echo -e "Time  Wind(km/h) Dir    Gust(km/h) Precip(mm)"
        echo -e "────  ────────── ────── ────────── ──────────"

        # Show hours 7-19 (7am to 7pm)
        for hour in {7..19}; do
            idx=$((start_idx + hour))

            if [ $idx -lt ${#TIMES[@]} ]; then
                # Extract time (HH:MM)
                time_str=$(echo "${TIMES[$idx]}" | cut -d'T' -f2 | cut -d':' -f1-2)

                # Get weather data
                wind_speed=${WIND_SPEEDS[$idx]}
                wind_dir=${WIND_DIRS[$idx]}
                gust=${GUSTS[$idx]}
                precip=${PRECIP[$idx]}

                # Convert direction to cardinal
                cardinal=$(deg_to_cardinal $wind_dir)

                # Format wind direction with degree symbol
                dir_str=$(printf "%3s %3.0f°" "$cardinal" "$wind_dir")

                # Format the output line
                printf "%5s %10.1f %-10s %10.1f %10.1f\n" \
                    "$time_str" "$wind_speed" "$dir_str" "$gust" "$precip"
            fi
        done
        echo ""
    fi
done

echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BLUE}Forecast generated at: $(date)${NC}"
echo -e "${BLUE}Data source: Open-Meteo API${NC}"
echo -e "${BLUE}Site data: ParaglidingEarth${NC}"
