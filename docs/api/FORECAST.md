# Weather Forecast API Documentation

## API Provider

The Paragliding App uses **Open-Meteo** for weather forecast data.

### API Endpoint
```
https://api.open-meteo.com/v1/forecast
```

### Example Request (Warnbro Beach)
```
https://api.open-meteo.com/v1/forecast?latitude=-32.3235&longitude=115.7420&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation&wind_speed_unit=kmh&forecast_days=7&timezone=auto
```

## Weather Models

### Australian Bureau of Meteorology (BOM) Model

**Model Parameter:** `models=bom_access_global`

#### Important Notice
> **BOM is currently upgrading its key platforms and services. During this process, open-data delivery has been temporarily suspended.** We look forward to BOM resuming open-data access soon so that high-resolution forecasts are once again available to Australian citizens.

#### Model Details
The BOM ACCESS (Australian Community Climate and Earth-System Simulator) model specifications are defined in the [BOM NWP Data documentation](https://www.bom.gov.au/nwp/doc/access/NWPData.shtml).

### Recommended Settings for Australia

**Use "Best Match" model selection for Australian locations**

When the app is set to "Best Match" (default), Open-Meteo automatically selects the most appropriate weather model for the location. This ensures optimal forecast accuracy while the BOM ACCESS model is temporarily unavailable.

## Available Weather Models in the App

1. **Best Match** (`best_match`) - Automatic model selection for optimal accuracy
2. **NOAA GFS** (`gfs_seamless`) - Global, best for North America, 13km resolution
3. **DWD ICON** (`icon_seamless`) - Best for Europe, combines multiple resolutions
4. **ECMWF IFS** (`ecmwf_ifs025`) - Widely regarded as most accurate globally
5. **Météo-France** (`meteofrance_seamless`) - Excellent for France/Western Europe
6. **JMA** (`jma_seamless`) - Best for East Asia/Japan
7. **GEM** (`gem_seamless`) - Best for Canada

## Forecast Data Parameters

The app requests the following hourly parameters:
- `wind_speed_10m` - Wind speed at 10 meters height
- `wind_direction_10m` - Wind direction at 10 meters height
- `wind_gusts_10m` - Wind gusts at 10 meters height
- `precipitation` - Precipitation amount

### Additional Settings
- **Forecast Days:** 7 days
- **Wind Speed Unit:** km/h
- **Timezone:** Automatic (based on location)

## Implementation Notes

- The app can batch multiple locations in a single API request using comma-separated coordinates
- Forecasts are cached to reduce API calls and improve performance
- The weather model can be changed in the app's settings
- When BOM ACCESS model becomes available again, it can be added to the weather model options