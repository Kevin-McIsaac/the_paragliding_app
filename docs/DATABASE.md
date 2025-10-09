# Database Development

## Pre-Release Schema Strategy

- **No Database Migrations**: Since the app is pre-release, we use a simplified approach
- **Schema Changes**: Any database schema changes require clearing app data during development
- **Clean v1.0**: The current schema in `database_helper.dart` represents the v1.0 release baseline
- **Future Migrations**: Post-release migrations will start from v2 with the current schema as the baseline

## Developer Workflow

When pulling code changes that modify the database schema:
1. Clear app data: Settings → Apps → The Paragliding App → Storage → Clear Data
2. Or use the emulator wipe: `flutter_controller.sh clean` (if available)
3. Hot restart the app to recreate the database with the new schema
4. Re-import any test data as needed

## Benefits

- **Simplified codebase**: No complex migration logic during development
- **Clean baseline**: Start v1.0 with optimized schema
- **Fewer bugs**: No migration-related errors during development
- **Performance**: Faster app startup without migration checks

## Database Architecture

- **Pattern**: MVVM with Repository pattern
- **Database**: SQLite via sqflite (mobile) + sqflite_common_ffi (desktop)
- **Scale**: <10 tables, largest table <5000 rows
- **Access**: Simple StatefulWidget with direct database access

## Key Services

- `database_helper.dart` - Low-level database operations
- `database_service.dart` - Main database service layer with business logic
- Simple management approach - keep operations straightforward