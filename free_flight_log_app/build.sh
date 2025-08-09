#!/bin/bash

# Build script for Free Flight Log app with OSM compliance flag
# This script includes the necessary dart-define flag to suppress the flutter_map OSM warning
# We have implemented all OSM compliance requirements (attribution, user agent, etc.)

# Default to linux platform if not specified
PLATFORM=${1:-linux}

# Shift to remove platform from arguments if provided
if [ "$#" -gt 0 ]; then
    shift
fi

# Build with OSM compliance flag
flutter build "$PLATFORM" --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not." "$@"