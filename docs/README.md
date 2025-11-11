# Documentation Index

Welcome to The Paragliding App documentation. All documentation is organized in this `/docs/` directory.

## For Users

- **[User Manual](user/User_Manual.md)** - Complete guide for using The Paragliding App
- **[Google Play Store Description](user/google_play_store_description.md)** - App store listing information
- **[Privacy Policy](privacy_policy.md)** - Privacy policy and data handling

## For Developers

### Core Architecture & Design

- **[Architecture](ARCHITECTURE.md)** - Production system architecture overview
- **[Technical Design](TECHNICAL_DESIGN.md)** - Comprehensive technical architecture document
- **[Functional Specification](FUNCTIONAL_SPECIFICATION.md)** - Complete feature requirements and specifications

### Developer References (Claude Code)

- **[IGC Trimming](IGC_TRIMMING.md)** - Flight track data processing and trimming logic
- **[Timestamps](TIMESTAMPS.md)** - UTC/local timezone conversion handling
- **[Database](DATABASE.md)** - Database strategy and schema overview
- **[Adding Weather Providers](ADDING_WEATHER_PROVIDERS.md)** - Guide to integrating new weather data sources

## API Documentation

External service integrations and API references:

- **[OpenAIP API Structure](api/OPENAIP_API_STRUCTURE.md)** - Aviation data API (airspaces, airports, navaids)
- **[Aviation Weather Center API](api/AVIATION_WEATHER_CENTER_API.md)** - NOAA aviation weather integration
- **[Weather Stations](api/WEATHER_STATIONS.md)** - Weather station providers comparison
- **[BOM Weather Stations](api/BOM_WEATHER_STATIONS.md)** - Australian Bureau of Meteorology integration
- **[Forecast API](api/FORECAST.md)** - Weather forecast API documentation

## Performance Documentation

Airspace rendering pipeline optimization work:

- **[Airspace Pipeline Architecture](performance/AIRSPACE_PIPELINE_ARCHITECTURE.md)** - Complete pipeline design and data flow
- **[Airspace Performance Optimization](performance/AIRSPACE_PERFORMANCE_OPTIMIZATION.md)** - Optimization journey and techniques
- **[Airspace Performance Metrics](performance/AIRSPACE_PERFORMANCE_METRICS.md)** - Benchmarks and real-world test results

## Development Setup

Platform-specific development environment setup guides:

- **[ChromeOS Flutter Setup](setup/CHROMEOS_FLUTTER_SETUP.md)** - Flutter development on ChromeOS
- **[Wireless ADB Setup](setup/WIRELESS_ADB_SETUP.md)** - Wireless Android debugging configuration

## Historical Documentation

Archived documentation for reference (not current implementation):

- **[Archive Directory](archive/)** - Historical design documents, old specifications, and technology comparisons

---

## Documentation Organization

```
docs/
├── README.md                     # This file - documentation index
├── privacy_policy.md            # Privacy policy (required for app stores)
│
├── ARCHITECTURE.md              # Core architecture docs
├── TECHNICAL_DESIGN.md
├── FUNCTIONAL_SPECIFICATION.md
│
├── IGC_TRIMMING.md              # Claude Code references
├── TIMESTAMPS.md
├── DATABASE.md
├── ADDING_WEATHER_PROVIDERS.md
│
├── user/                        # User-facing documentation
│   ├── User_Manual.md
│   └── google_play_store_description.md
│
├── api/                         # External API integration guides
│   ├── OPENAIP_API_STRUCTURE.md
│   ├── AVIATION_WEATHER_CENTER_API.md
│   ├── WEATHER_STATIONS.md
│   ├── BOM_WEATHER_STATIONS.md
│   └── FORECAST.md
│
├── performance/                 # Performance optimization documentation
│   ├── AIRSPACE_PIPELINE_ARCHITECTURE.md
│   ├── AIRSPACE_PERFORMANCE_OPTIMIZATION.md
│   └── AIRSPACE_PERFORMANCE_METRICS.md
│
├── setup/                       # Development environment setup
│   ├── CHROMEOS_FLUTTER_SETUP.md
│   └── WIRELESS_ADB_SETUP.md
│
└── archive/                     # Historical documentation
    ├── improved_how_to_instructions.md
    ├── 3D_TECH_RECOMMENDATION.md
    ├── AIRSPACE_ALGORITHM_ANALYSIS.md
    ├── LINEAR_OPTIMIZATION_RESULTS.md
    ├── bidirectional-chart-sync.md
    ├── EDIT_SITES_CLICK_DRAG_SPECIFICATION.md
    ├── Cesium_PRD.md
    ├── Cesium_Native_Analysis.md
    ├── MAPLIBRE_VS_CESIUM_COMPARISON.md
    ├── maps.md
    ├── preferences.md
    └── TRACK_RENDERING.md
```

---

## Contributing to Documentation

When adding or updating documentation:

1. **Choose the right location**:
   - User-facing docs → `user/`
   - API integration guides → `api/`
   - Performance analysis → `performance/`
   - Setup guides → `setup/`
   - Core architecture → root level
   - Outdated/historical → `archive/`

2. **Update this README** to include new documentation in the appropriate section

3. **Use markdown format** with clear headings and code examples

4. **Include dates** in technical documents (e.g., "Last Updated: YYYY-MM-DD")

5. **Link related docs** to help readers navigate between connected topics

---

*Last Updated: 2025-01-12*
