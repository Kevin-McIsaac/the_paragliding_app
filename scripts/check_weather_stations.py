#!/usr/bin/env python3
"""
Weather Station Provider Comparison Script

This script takes a paragliding site name, looks up its GPS coordinates from
ParaglidingEarth.com, then queries multiple weather station APIs to find which
providers return stations within a 50km radius.

Usage:
    python check_weather_stations.py "Site Name"

Example:
    python check_weather_stations.py "Annecy"
"""

import sys
import json
import math
import requests
from typing import Dict, List, Tuple, Optional
from collections import defaultdict

# ==============================================================================
# API Configuration
# ==============================================================================

# FFVL API Key - replace with your actual key from https://balisemeteo.com/api/
FFVL_API_KEY = "12fbb9720455a2abb825c29233ac8bd0"

# API Endpoints
PGE_SEARCH_URL = "https://paraglidingearth.com/assets/ajax/searchSitesJSON.php"
FFVL_BASE_URL = "https://data.ffvl.fr/api/"
PIOUPIOU_BASE_URL = "http://api.pioupiou.fr/v1"
AWC_METAR_URL = "https://aviationweather.gov/api/data/metar"
NWS_BASE_URL = "https://api.weather.gov"
BOM_BASE_URL = "http://reg.bom.gov.au/fwo"

# Search radius in kilometers
SEARCH_RADIUS_KM = 50

# User agent for HTTP requests
USER_AGENT = "TheParaglidingApp/1.0 WeatherStationComparison"

# ==============================================================================
# Distance Calculation (Haversine Formula)
# ==============================================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate the great circle distance between two points on Earth.

    Args:
        lat1, lon1: Latitude and longitude of first point in decimal degrees
        lat2, lon2: Latitude and longitude of second point in decimal degrees

    Returns:
        Distance in kilometers
    """
    # Convert decimal degrees to radians
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])

    # Haversine formula
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))

    # Radius of Earth in kilometers
    r = 6371

    return c * r

# ==============================================================================
# PGE Site Lookup
# ==============================================================================

def search_pge_site(site_name: str) -> Optional[Tuple[str, float, float]]:
    """
    Search for a paragliding site on ParaglidingEarth.com

    Args:
        site_name: Name of the site to search for

    Returns:
        Tuple of (site_name, latitude, longitude) or None if not found
    """
    try:
        # Use persistent session for PGE API (helps avoid rate limiting)
        session = requests.Session()
        session.headers.update({'User-Agent': USER_AGENT})

        response = session.get(
            PGE_SEARCH_URL,
            params={'name': site_name},
            timeout=10
        )

        # Handle 403 - PGE might be blocking the request
        if response.status_code == 403:
            print("⚠️  PGE API returned 403 Forbidden. You can:")
            print("   1. Provide coordinates directly: python script.py 45.9,6.9 'Site Name'")
            print("   2. Try again later (possible rate limiting)")
            return None

        response.raise_for_status()

        data = response.json()

        if not data.get('features'):
            return None

        # Get the first result
        first_result = data['features'][0]
        name = first_result.get('name', 'Unknown')
        lat = first_result.get('lat')
        lon = first_result.get('lng')

        if lat is None or lon is None:
            return None

        return (name, float(lat), float(lon))

    except Exception as e:
        print(f"Error searching PGE: {e}")
        return None

# ==============================================================================
# Weather Provider Queries
# ==============================================================================

def query_ffvl(lat: float, lon: float, radius_km: float) -> List[Dict]:
    """Query FFVL weather beacons (French paragliding federation)"""
    stations = []

    if not FFVL_API_KEY or FFVL_API_KEY == "your_ffvl_api_key_here":
        print("Warning: FFVL API key not configured")
        return stations

    try:
        # Fetch all beacons
        response = requests.get(
            FFVL_BASE_URL,
            params={
                'base': 'balises',
                'r': 'list',
                'mode': 'json',
                'key': FFVL_API_KEY
            },
            headers={'User-Agent': USER_AGENT},
            timeout=15
        )
        response.raise_for_status()
        data = response.json()

        # Filter by distance
        for beacon in data:
            beacon_lat = float(beacon.get('latitude', 0))
            beacon_lon = float(beacon.get('longitude', 0))
            distance = haversine_distance(lat, lon, beacon_lat, beacon_lon)

            if distance <= radius_km:
                stations.append({
                    'name': beacon.get('nom', 'Unknown'),
                    'lat': beacon_lat,
                    'lon': beacon_lon,
                    'distance_km': round(distance, 1)
                })

    except Exception as e:
        print(f"Error querying FFVL: {e}")

    return stations

def query_pioupiou(lat: float, lon: float, radius_km: float) -> List[Dict]:
    """Query Pioupiou/OpenWindMap community wind stations"""
    stations = []

    try:
        response = requests.get(
            f"{PIOUPIOU_BASE_URL}/live-with-meta/all",
            headers={'User-Agent': USER_AGENT},
            timeout=15
        )
        response.raise_for_status()
        data = response.json()

        # Parse response
        for station in data.get('data', []):
            station_meta = station.get('meta', {})
            station_lat = station_meta.get('latitude')
            station_lon = station_meta.get('longitude')

            if station_lat is None or station_lon is None:
                continue

            distance = haversine_distance(lat, lon, station_lat, station_lon)

            if distance <= radius_km:
                stations.append({
                    'name': station_meta.get('name', f"Pioupiou {station.get('id', 'Unknown')}"),
                    'lat': station_lat,
                    'lon': station_lon,
                    'distance_km': round(distance, 1)
                })

    except Exception as e:
        print(f"Error querying Pioupiou: {e}")

    return stations

def query_awc_metar(lat: float, lon: float, radius_km: float) -> List[Dict]:
    """Query Aviation Weather Center METAR stations"""
    stations = []

    try:
        # Calculate bounding box (approximate)
        lat_delta = radius_km / 111.0  # 1 degree latitude ≈ 111km
        lon_delta = radius_km / (111.0 * math.cos(math.radians(lat)))

        bbox = f"{lat-lat_delta},{lon-lon_delta},{lat+lat_delta},{lon+lon_delta}"

        response = requests.get(
            AWC_METAR_URL,
            params={
                'bbox': bbox,
                'format': 'json'
            },
            headers={
                'Accept': 'application/json',
                'User-Agent': USER_AGENT
            },
            timeout=15
        )
        response.raise_for_status()
        data = response.json()

        # Filter by distance
        for station in data:
            station_lat = station.get('lat')
            station_lon = station.get('lon')

            if station_lat is None or station_lon is None:
                continue

            distance = haversine_distance(lat, lon, station_lat, station_lon)

            if distance <= radius_km:
                stations.append({
                    'name': f"{station.get('name', 'Unknown')} ({station.get('icaoId', 'N/A')})",
                    'lat': station_lat,
                    'lon': station_lon,
                    'distance_km': round(distance, 1)
                })

    except Exception as e:
        print(f"Error querying AWC METAR: {e}")

    return stations

def query_nws(lat: float, lon: float, radius_km: float) -> List[Dict]:
    """Query National Weather Service stations (US only)"""
    stations = []

    # Quick geographic check - NWS only covers US and territories
    # Continental US: roughly -125 to -67 longitude, 24 to 50 latitude
    if not ((-125 <= lon <= -67 and 24 <= lat <= 50) or  # Continental US
            (-180 <= lon <= -130 and 51 <= lat <= 72) or  # Alaska
            (-178 <= lon <= -154 and 18 <= lat <= 29)):    # Hawaii
        return stations  # Outside US coverage

    try:
        # Get grid point
        response = requests.get(
            f"{NWS_BASE_URL}/points/{lat:.4f},{lon:.4f}",
            headers={'User-Agent': USER_AGENT},
            timeout=10
        )

        if response.status_code == 404:
            return stations  # Not in NWS coverage area

        response.raise_for_status()
        data = response.json()

        # Get observation stations
        stations_url = data.get('properties', {}).get('observationStations')
        if not stations_url:
            return stations

        response = requests.get(
            stations_url,
            headers={'User-Agent': USER_AGENT},
            timeout=10
        )
        response.raise_for_status()
        stations_data = response.json()

        # Filter by distance
        for station_url in stations_data.get('features', []):
            station_props = station_url.get('properties', {})
            geometry = station_url.get('geometry', {})
            coords = geometry.get('coordinates', [])

            if len(coords) < 2:
                continue

            station_lon, station_lat = coords[0], coords[1]
            distance = haversine_distance(lat, lon, station_lat, station_lon)

            if distance <= radius_km:
                stations.append({
                    'name': station_props.get('name', 'Unknown'),
                    'lat': station_lat,
                    'lon': station_lon,
                    'distance_km': round(distance, 1)
                })

    except Exception as e:
        print(f"Error querying NWS: {e}")

    return stations

def query_bom(lat: float, lon: float, radius_km: float) -> List[Dict]:
    """Query Australian Bureau of Meteorology stations (Australia only)"""
    stations = []

    # Quick geographic check - BOM only covers Australia
    # Australia: roughly 113 to 154 longitude, -44 to -10 latitude
    if not (113 <= lon <= 154 and -44 <= lat <= -10):
        return stations  # Outside Australia

    # BOM requires state-specific queries which is complex
    # For this comparison script, we'll return empty list with a note
    print("Note: BOM provider requires state-specific queries (not implemented in this script)")

    return stations

# ==============================================================================
# Main Script
# ==============================================================================

def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python check_weather_stations.py \"Site Name\"")
        print("  python check_weather_stations.py LAT,LON \"Site Name\"")
        print()
        print("Examples:")
        print("  python check_weather_stations.py \"Annecy\"")
        print("  python check_weather_stations.py \"45.9,6.9\" \"Annecy\"")
        sys.exit(1)

    print(f"\n{'='*80}")
    print(f"Weather Station Provider Comparison")
    print(f"{'='*80}\n")

    # Check if first argument is coordinates (lat,lon format)
    if ',' in sys.argv[1]:
        try:
            lat_str, lon_str = sys.argv[1].split(',')
            lat = float(lat_str)
            lon = float(lon_str)
            name = sys.argv[2] if len(sys.argv) > 2 else "Custom Location"
            print(f"📍 Using provided coordinates")
            print(f"   Location: {name}")
            print(f"   Coordinates: {lat:.4f}, {lon:.4f}")
            print(f"   Search radius: {SEARCH_RADIUS_KM} km\n")
        except (ValueError, IndexError) as e:
            print(f"❌ Invalid coordinates format. Use: LAT,LON (e.g., 45.9,6.9)")
            sys.exit(1)
    else:
        # Step 1: Look up site coordinates via PGE
        site_name = sys.argv[1]
        print(f"🔍 Searching for site: {site_name}")
        site_info = search_pge_site(site_name)

        if not site_info:
            print(f"❌ Site not found: {site_name}")
            print(f"\n💡 Tip: You can provide coordinates directly:")
            print(f"   python check_weather_stations.py \"LAT,LON\" \"{site_name}\"")
            sys.exit(1)

        name, lat, lon = site_info
        print(f"✅ Found: {name}")
        print(f"   Coordinates: {lat:.4f}, {lon:.4f}")
        print(f"   Search radius: {SEARCH_RADIUS_KM} km\n")

    # Step 2: Query each provider
    print(f"🌐 Querying weather station providers...\n")

    providers = {
        'FFVL Beacons': query_ffvl(lat, lon, SEARCH_RADIUS_KM),
        'Pioupiou': query_pioupiou(lat, lon, SEARCH_RADIUS_KM),
        'AWC METAR': query_awc_metar(lat, lon, SEARCH_RADIUS_KM),
        'NWS': query_nws(lat, lon, SEARCH_RADIUS_KM),
        'BOM': query_bom(lat, lon, SEARCH_RADIUS_KM),
    }

    # Step 3: Build station-to-provider mapping
    station_providers = defaultdict(set)
    all_stations = {}

    for provider_name, stations in providers.items():
        for station in stations:
            # Use coordinates as unique key (rounded to avoid floating point issues)
            station_key = f"{station['lat']:.4f},{station['lon']:.4f}"
            station_providers[station_key].add(provider_name)
            if station_key not in all_stations:
                all_stations[station_key] = station

    # Step 4: Print summary
    print(f"📊 Results Summary:")
    print(f"   Total unique stations found: {len(all_stations)}")
    for provider_name, stations in providers.items():
        print(f"   {provider_name}: {len(stations)} stations")
    print()

    # Step 5: Generate markdown table
    if not all_stations:
        print("ℹ️  No weather stations found within 50km radius.")
        return

    print(f"\n{'='*80}")
    print("Markdown Table: Station Availability by Provider")
    print(f"{'='*80}\n")

    # Sort stations by distance
    sorted_stations = sorted(
        all_stations.items(),
        key=lambda x: x[1]['distance_km']
    )

    # Header
    provider_names = list(providers.keys())
    print("| Station Name | Distance (km) | " + " | ".join(provider_names) + " |")
    print("|" + "-" * 14 + "|" + "-" * 15 + "|" + "|".join(["-" * (len(p) + 2) for p in provider_names]) + "|")

    # Rows
    for station_key, station in sorted_stations:
        name = station['name'][:30]  # Truncate long names
        distance = station['distance_km']

        # Check marks for each provider
        checks = []
        for provider_name in provider_names:
            if provider_name in station_providers[station_key]:
                checks.append("✓")
            else:
                checks.append("✗")

        print(f"| {name:<30} | {distance:>6.1f} km | " + " | ".join([f"{c:^{len(p)}}" for c, p in zip(checks, provider_names)]) + " |")

    print()

if __name__ == "__main__":
    main()
