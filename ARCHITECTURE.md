# Technical Architecture

This document details the technical implementation of the Free Flight Log application, including architecture patterns, database schema, and key technical considerations.

## Architecture Overview (Implemented)

**Current Implementation:**
- **Pattern**: MVVM with Repository pattern ✅
- **State Management**: Provider (ready for implementation) 
- **Database**: SQLite via sqflite (mobile) + sqflite_common_ffi (desktop) ✅
- **UI Framework**: Flutter with Material Design 3 ✅

### Current Project Structure
```
lib/
├── data/
│   ├── models/              # ✅ Flight, Site, Wing models
│   ├── repositories/        # ✅ Data access layer (CRUD operations)
│   └── datasources/         # ✅ Database helper with initialization
├── presentation/
│   ├── screens/             # ✅ Flight list, Add flight form
│   ├── widgets/             # 📁 Ready for reusable components
│   └── providers/           # 📁 Ready for state management
├── services/                # 📁 Ready for import/export, location
└── main.dart               # ✅ App entry point with database init
```

### Implemented Features
- **Flight Model**: Complete data model with validation and climb rate fields
- **Database Helper**: SQLite initialization for all platforms with migration support
- **Flight Repository**: Full CRUD operations with statistics
- **Site Repository**: Location management with coordinate search
- **Wing Repository**: Equipment tracking with usage stats
- **Flight List Screen**: Material Design 3 UI with empty states
- **Add Flight Form**: Comprehensive form with validation
- **Flight Detail Screen**: Complete flight information with inline editing capabilities
- **IGC Import Service**: Full IGC file parsing with climb rate calculations
- **IGC Import Screen**: File selection with folder memory and batch import
- **Flight Track Visualization**: OpenStreetMap (flutter_map) and canvas-based track display
- **Navigation**: Screen transitions with result callbacks
- **Inline Editing**: Direct editing of flight details without separate edit screens

## Key Technical Considerations

### IGC File Format
- International Gliding Commission standard for flight tracks
- Contains GPS coordinates, altitude, timestamps
- Parser extracts launch/landing sites, max altitude, climb rates
- Supports both pressure and GPS altitude data
- Calculates instantaneous and 15-second averaged climb rates
- Stores complete track data for visualization

### Database Schema
Three main tables with current implementation:
- `flights`: Core flight records with comprehensive statistics including climb rates
- `sites`: Launch/landing locations with custom names and coordinates
- `wings`: Equipment tracking with automatic creation from IGC data
- Database version 3 with migration support for climb rate fields and timezone information

### Climb Rate Calculations
- **Instantaneous rates**: Point-to-point climb/sink calculations
- **15-second averaged rates**: Smoothed rates using ±7.5 second window
- **Pressure altitude priority**: Uses barometric altitude when available for accuracy
- **GPS fallback**: Falls back to GPS altitude when pressure data unavailable
- **Thermal analysis**: 15-second window filters GPS noise for realistic thermal readings

## Development Status

### ✅ MVP Features (COMPLETED)
1. ✅ Manual flight entry form with validation
2. ✅ Flight list display with statistics
3. ✅ Basic CRUD operations (Create, Read, Update, Delete)
4. ✅ Simple statistics (total flights/hours/max altitude)
5. ✅ Local SQLite persistence with cross-platform support
6. ✅ IGC file import and parsing with climb rate calculations
7. ✅ OpenStreetMap integration for cross-platform track visualization
8. ✅ Flight detail view with inline editing capability and comprehensive statistics
9. ✅ Wing/equipment management with automatic creation from IGC data
10. ✅ Database migrations for schema updates

### 🚀 Next Features (Post-MVP)
1. 📋 Altitude and climb rate charts (fl_chart ready)
2. 📋 Site recognition via reverse geocoding
3. 📋 Export functionality (CSV, KML)
4. 📋 Provider state management implementation
5. 📋 Advanced flight analysis and statistics
6. 📋 Flight comparison and trend analysis