#!/bin/bash

# Run script for Free Flight Log app with OSM compliance flag
# This script includes the necessary dart-define flag to suppress the flutter_map OSM warning
# We have implemented all OSM compliance requirements (attribution, user agent, etc.)

flutter run -d linux --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not." "$@"