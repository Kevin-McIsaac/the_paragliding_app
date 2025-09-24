# Wind Rose Implementation Plan - Revised

Based on the codebase analysis, here's the refined 3-phase implementation:

-----

## Phase 2: Weather API Abstraction (Open-Meteo)
**Goal**: Create switchable weather provider system, start with Open-Meteo

**Files to Create:**

- `lib/services/weather_provider.dart` - Abstract base class
- `lib/services/providers/open_meteo_provider.dart` - Free API implementation
- `lib/data/models/wind_data.dart` - Wind conditions model
- `lib/services/weather_cache_service.dart` - 5-minute caching

**API Details:**
- Open-Meteo: `https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=wind_speed_10m,wind_direction_10m,wind_gusts_10m`
- No API key required, free tier
- Returns wind speed (km/h), direction (degrees), gusts

## Phase 3: Live Wind Integration
**Goal**: Overlay current wind conditions on static compass

**Enhancements:**
- Add animated wind arrow pointing to current direction
- Color-code compatibility: Green (matches site directions), Yellow (marginal ±22.5°), Red (unsafe)
- Show wind speed text in center of compass
- Auto-refresh every 5 minutes while dialog open
- Loading/error states with retry option

**Integration Points:**
- Weather tab fetches data when opened
- Combines static site directions with live wind data
- Graceful degradation when API unavailable

**Success Criteria:**
- Clear visual indication of wind suitability for launch
- Fast loading (<2s) with smooth 60fps animations
- Robust error handling and offline capability