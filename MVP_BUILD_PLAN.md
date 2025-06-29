# MVP Build Plan - Free Flight Log

## Week 1-2: Foundation Setup

### Day 1-2: Environment & Project Setup

1. **Install Flutter**
   ```bash
   # Download Flutter SDK
   git clone https://github.com/flutter/flutter.git -b stable
   export PATH="$PATH:`pwd`/flutter/bin"
   
   # Verify installation
   flutter doctor
   
   # Install Android Studio & SDK
   ```

2. **Create Project**
   ```bash
   cd /home/kmdiwqqd/Projects/free_flight_log
   flutter create free_flight_log_app --org com.yourname.freeflightlog
   cd free_flight_log_app
   ```

3. **Initial Dependencies**
   ```yaml
   # pubspec.yaml
   dependencies:
     flutter:
       sdk: flutter
     sqflite: ^2.3.0
     path_provider: ^2.1.0
     provider: ^6.1.0
     intl: ^0.18.0
   ```

### Day 3-4: Database Layer

1. **Create Database Helper**
   ```dart
   // lib/data/database_helper.dart
   class DatabaseHelper {
     static const _databaseName = "FlightLog.db";
     static const _databaseVersion = 1;
     
     // Singleton pattern
     // Table creation
     // CRUD operations
   }
   ```

2. **Define Tables**
   - flights table (simplified for MVP)
   - sites table (basic)
   - wings table (basic)

### Day 5-6: Core Models & Repository

1. **Flight Model**
   ```dart
   // lib/data/models/flight.dart
   class Flight {
     final int? id;
     final DateTime date;
     final DateTime launchTime;
     final DateTime landingTime;
     final String siteName;
     final String? wing;
     final double? maxAltitude;
     final String? notes;
   }
   ```

2. **Flight Repository**
   ```dart
   // lib/data/repositories/flight_repository.dart
   class FlightRepository {
     Future<List<Flight>> getAllFlights();
     Future<Flight> createFlight(Flight flight);
     Future<void> updateFlight(Flight flight);
     Future<void> deleteFlight(int id);
   }
   ```

### Day 7-8: Manual Flight Entry

1. **Entry Form Screen**
   - Date picker (default today)
   - Time pickers for launch/landing
   - Site name text field
   - Wing dropdown
   - Max altitude (optional)
   - Notes field
   - Save button

2. **Form Validation**
   - Landing time after launch
   - Required fields check
   - Duration calculation

### Day 9-10: Flight List Display

1. **List Screen**
   - Show flights in reverse chronological order
   - Display: Date, Site, Duration, Max Alt
   - Tap to view details
   - Pull to refresh

2. **Flight Details**
   - Show all flight information
   - Edit button
   - Delete button (with confirmation)

### Day 11-12: Navigation & Polish

1. **Bottom Navigation**
   - Flight Log (main)
   - Add Flight (+)
   - Statistics (basic)

2. **Basic Statistics**
   - Total flights
   - Total hours
   - Flights this year
   - Hours this year

### Day 13-14: Testing & Refinement

1. **Testing**
   - Add 10-20 sample flights
   - Test CRUD operations
   - Verify calculations
   - Check edge cases

2. **UI Polish**
   - Consistent styling
   - Loading states
   - Error handling
   - Empty states

## MVP Deliverables

### Core Features
✓ Manual flight entry
✓ Flight list display
✓ Flight editing/deletion
✓ Basic statistics
✓ Local data persistence

### What's NOT in MVP
- IGC import
- Maps
- Charts
- Export functions
- Advanced statistics
- Site/Wing management

## Development Checklist

### Setup Phase
- [ ] Install Flutter & Android Studio
- [ ] Create new Flutter project
- [ ] Set up version control (git)
- [ ] Configure VS Code/Android Studio
- [ ] Run hello world on device/emulator

### Database Phase
- [ ] Add sqflite dependency
- [ ] Create DatabaseHelper class
- [ ] Define table schemas
- [ ] Implement CRUD operations
- [ ] Test database operations

### UI Phase
- [ ] Create flight entry form
- [ ] Implement flight list
- [ ] Add navigation
- [ ] Build statistics screen
- [ ] Apply consistent styling

### Testing Phase
- [ ] Manual testing on device
- [ ] Add sample data
- [ ] Test edge cases
- [ ] Fix bugs
- [ ] Performance check

## Quick Start Commands

```bash
# Start development
cd free_flight_log_app
flutter pub get
flutter run

# Run on specific device
flutter devices
flutter run -d <device_id>

# Build APK for testing
flutter build apk --debug

# Check for issues
flutter analyze
flutter test
```

## Next Steps After MVP

1. **Week 3-4**: IGC Import
   - IGC parser
   - File picker
   - Automatic calculations

2. **Week 5-6**: Visualizations
   - Integrate maps
   - Add charts
   - Flight replay

3. **Week 7-8**: Polish
   - Full feature set
   - Play Store prep
   - Beta testing

## Key MVP Success Criteria

1. **Functional**: Can add, view, edit, delete flights
2. **Reliable**: Data persists between app launches
3. **Usable**: Intuitive UI, minimal taps to log flight
4. **Fast**: Responsive performance
5. **Stable**: No crashes, handles errors gracefully

This MVP proves the core concept and provides a solid foundation for adding advanced features.